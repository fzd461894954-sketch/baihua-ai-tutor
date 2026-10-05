import XCTest

@testable import AITutorMac

@MainActor
final class TutorInteractionPolicyTests: XCTestCase {
  func testHighPriorityTopicsShowImmediately() {
    let policy = TutorInteractionPolicy()

    for topic in [
      TutorInteractionTopicType.error,
      .warning,
      .security,
      .failure,
    ] {
      let input = interactionInput(
        presentation: interactionPresentation(confidence: .low),
        confidence: .low,
        topicType: topic
      )

      XCTAssertEqual(
        policy.decide(input),
        TutorInteractionDecision(
          action: .show,
          priority: .high,
          reason: .highPriorityTopic
        ),
        "Expected \(topic.rawValue) to override low confidence"
      )
    }
  }

  func testLowConfidenceConceptIsIgnored() {
    let presentation = interactionPresentation(confidence: .low)
    let decision = TutorInteractionPolicy().decide(
      interactionInput(
        presentation: presentation,
        confidence: .low,
        topicType: .concept
      )
    )

    XCTAssertEqual(
      decision,
      TutorInteractionDecision(
        action: .ignore,
        priority: .low,
        reason: .lowConfidence
      )
    )
  }

  func testIncompletePresentationIsQueued() {
    let presentation = interactionPresentation(
      outcome: .needsMoreContext,
      confidence: nil
    )
    let decision = TutorInteractionPolicy().decide(
      interactionInput(
        presentation: presentation,
        confidence: nil,
        topicType: .incomplete
      )
    )

    XCTAssertEqual(
      decision,
      TutorInteractionDecision(
        action: .queue,
        priority: .low,
        reason: .incompleteContent
      )
    )
  }

  func testDuplicateQueuedItemMergesIntoNewestVersion() {
    let queue = TutorDisplayQueue()
    let sourceChunkID = UUID()
    let older = interactionPresentation(
      responseID: UUID(),
      sourceChunkID: sourceChunkID,
      sequence: 1
    )
    let newer = interactionPresentation(
      responseID: UUID(),
      sourceChunkID: sourceChunkID,
      sequence: 2
    )
    let decision = interactionDecision(action: .queue, priority: .low)

    queue.submit(
      older,
      input: interactionInput(presentation: older),
      decision: decision
    )
    queue.submit(
      newer,
      input: interactionInput(presentation: newer),
      decision: decision
    )

    XCTAssertEqual(queue.queueCount, 1)
    XCTAssertEqual(queue.queuedItems.first?.id, newer.responseMetadata.responseID)
    XCTAssertEqual(queue.duplicateMergeCount, 1)
  }

  func testQueueLimitKeepsHighestPriorityAndNewestItems() {
    let queue = TutorDisplayQueue(
      configuration: TutorDisplayQueueConfiguration(maximumQueuedItemCount: 2)
    )
    let low = interactionPresentation(responseID: UUID(), sequence: 1)
    let normal = interactionPresentation(responseID: UUID(), sequence: 2)
    let high = interactionPresentation(responseID: UUID(), sequence: 3)

    queue.submit(
      low,
      input: interactionInput(presentation: low),
      decision: interactionDecision(action: .queue, priority: .low)
    )
    queue.submit(
      normal,
      input: interactionInput(presentation: normal),
      decision: interactionDecision(action: .queue, priority: .normal)
    )
    queue.submit(
      high,
      input: interactionInput(presentation: high),
      decision: interactionDecision(action: .queue, priority: .high)
    )

    XCTAssertEqual(queue.queueCount, 2)
    XCTAssertEqual(
      queue.queuedItems.map(\.id),
      [high.responseMetadata.responseID, normal.responseMetadata.responseID]
    )
  }

  func testNewerShowItemReplacesAndCancelsOlderItem() {
    let queue = TutorDisplayQueue()
    let older = interactionPresentation(responseID: UUID(), sequence: 1)
    let newer = interactionPresentation(responseID: UUID(), sequence: 2)
    let decision = interactionDecision(action: .show, priority: .normal)

    queue.submit(
      older,
      input: interactionInput(presentation: older),
      decision: decision
    )
    queue.submit(
      newer,
      input: interactionInput(presentation: newer),
      decision: decision
    )

    XCTAssertEqual(queue.currentDisplayItem?.id, newer.responseMetadata.responseID)
    XCTAssertEqual(queue.lastCancelledItemID, older.responseMetadata.responseID)
  }

  func testResetCleansCurrentItemQueueAndBookkeeping() {
    let queue = TutorDisplayQueue()
    let visible = interactionPresentation(responseID: UUID(), sequence: 1)
    let waiting = interactionPresentation(responseID: UUID(), sequence: 2)

    queue.submit(
      visible,
      input: interactionInput(presentation: visible),
      decision: interactionDecision(action: .show, priority: .normal)
    )
    queue.submit(
      waiting,
      input: interactionInput(presentation: waiting),
      decision: interactionDecision(action: .queue, priority: .low)
    )
    queue.cancelCurrentDisplay()

    queue.reset()

    XCTAssertNil(queue.currentDisplayItem)
    XCTAssertTrue(queue.queuedItems.isEmpty)
    XCTAssertEqual(queue.queueCount, 0)
    XCTAssertEqual(queue.duplicateMergeCount, 0)
    XCTAssertNil(queue.lastCancelledItemID)
  }

#if DEBUG
  func testCoordinatorCompletesFakeFlowThroughPolicyAndDisplayQueue() async {
    let coordinator = TutorCoordinator(
      engine: LLMTutorEngine(provider: FakeLLMProvider())
    )
    let chunk = interactionChunk(text: "Error 表示操作失败。")

    coordinator.start()
    coordinator.receive(chunk)

    await assertInteractionEventually("Policy decision was not produced") {
      coordinator.latestInteractionDecision != nil
    }

    XCTAssertEqual(coordinator.latestInteractionInput?.topicType, .error)
    XCTAssertEqual(coordinator.latestInteractionInput?.confidence, .high)
    XCTAssertEqual(coordinator.latestInteractionInput?.flushReason, chunk.flushReason)
    XCTAssertEqual(coordinator.latestInteractionInput?.textLength, chunk.text.count)
    XCTAssertEqual(
      coordinator.latestInteractionInput?.presentationMetadata,
      coordinator.latestPresentation?.responseMetadata
    )
    XCTAssertEqual(coordinator.latestInteractionDecision?.action, .show)
    XCTAssertEqual(coordinator.latestInteractionDecision?.priority, .high)
    XCTAssertEqual(
      coordinator.displayQueue.currentDisplayItem?.id,
      coordinator.latestPresentation?.responseMetadata.responseID
    )
    XCTAssertEqual(coordinator.displayQueue.queueCount, 0)
  }

  func testCoordinatorSessionResetCleansPolicyAndDisplayQueue() async {
    let coordinator = TutorCoordinator(
      engine: LLMTutorEngine(provider: FakeLLMProvider())
    )

    coordinator.start()
    coordinator.receive(interactionChunk(text: "API 是程序之间的约定。"))
    await assertInteractionEventually("Display item was not produced") {
      coordinator.displayQueue.currentDisplayItem != nil
    }
    XCTAssertEqual(coordinator.latestInteractionDecision?.action, .show)
    XCTAssertEqual(coordinator.latestInteractionDecision?.priority, .normal)

    coordinator.resetSession()

    XCTAssertNil(coordinator.latestInteractionInput)
    XCTAssertNil(coordinator.latestInteractionDecision)
    XCTAssertNil(coordinator.displayQueue.currentDisplayItem)
    XCTAssertEqual(coordinator.displayQueue.queueCount, 0)
    XCTAssertEqual(coordinator.displayQueue.duplicateMergeCount, 0)
  }
#endif

  private func assertInteractionEventually(
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @escaping @MainActor () async -> Bool
  ) async {
    for _ in 0..<400 {
      if await condition() {
        return
      }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail(message, file: file, line: line)
  }
}

private let interactionSessionID = UUID(
  uuidString: "00000000-0000-0000-0000-000000000601"
)!

private func interactionPresentation(
  responseID: UUID = UUID(),
  sourceChunkID: UUID = UUID(),
  sequence: Int = 1,
  outcome: TutorPresentationOutcomeKind = .lesson,
  confidence: TutorAnswerConfidence? = .high
) -> TutorPresentationModel {
  TutorPresentationModel(
    responseMetadata: TutorPresentationResponseMetadata(
      responseID: responseID,
      requestID: UUID(),
      sessionID: interactionSessionID,
      sequence: sequence,
      sourceChunkID: sourceChunkID,
      createdAt: Date(timeIntervalSince1970: TimeInterval(sequence))
    ),
    outcome: outcome,
    lessonMetadata: confidence.map {
      TutorPresentationLessonMetadata(
        confidence: $0,
        keyPointCount: 1,
        termCount: 0,
        caveatCount: 0,
        hasAnalogy: false,
        hasExample: false,
        hasCheckQuestion: false
      )
    },
    title: "教学标题",
    plainExplanation: "教学解释",
    keyPoints: ["关键点"],
    terms: [],
    analogy: nil,
    example: nil,
    checkQuestion: nil,
    caveats: [],
    suggestedAction: nil,
    blockReason: nil,
    didTruncateContent: false
  )
}

private func interactionInput(
  presentation: TutorPresentationModel,
  confidence: TutorAnswerConfidence? = .high,
  topicType: TutorInteractionTopicType? = .concept
) -> TutorInteractionInput {
  TutorInteractionInput(
    presentationMetadata: presentation.responseMetadata,
    outcome: presentation.outcome,
    confidence: confidence,
    flushReason: .sentenceComplete,
    textLength: 20,
    topicType: topicType
  )
}

private func interactionDecision(
  action: TutorInteractionAction,
  priority: TutorInteractionPriority
) -> TutorInteractionDecision {
  TutorInteractionDecision(
    action: action,
    priority: priority,
    reason: action == .show ? .conceptExplanation : .incompleteContent
  )
}

private func interactionChunk(text: String) -> SemanticChunk {
  SemanticChunk(
    id: UUID(),
    sourceRevisionID: 1,
    text: text,
    confidence: .high,
    createdAt: Date(timeIntervalSince1970: 6_100),
    flushReason: .sentenceComplete
  )
}
