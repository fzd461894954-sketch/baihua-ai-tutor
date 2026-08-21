import XCTest

@testable import AITutorMac

@MainActor
final class TutorPresentationTests: XCTestCase {
#if DEBUG
  func testSemanticChunkCompletesThroughFakeProviderToPresentationModel() async {
    let coordinator = TutorCoordinator(
      engine: LLMTutorEngine(
        provider: FakeLLMProvider(
          now: { presentationDate },
          makeID: { presentationResponseID }
        )
      ),
      output: completeOutputPreferences
    )

    coordinator.start()
    coordinator.receive(presentationChunk(text: "API 怎么工作？"))

    await assertPresentationEventually("Presentation was not produced") {
      coordinator.latestPresentation != nil
    }

    guard let presentation = coordinator.latestPresentation else {
      return XCTFail("Expected presentation")
    }
    XCTAssertEqual(presentation.outcome, .lesson)
    XCTAssertEqual(presentation.responseMetadata.responseID, presentationResponseID)
    XCTAssertEqual(presentation.responseMetadata.sourceChunkID, coordinator.latestChunk?.id)
    XCTAssertTrue(presentation.title.contains("API"))
    XCTAssertFalse(presentation.plainExplanation.isEmpty)
    XCTAssertFalse(presentation.keyPoints.isEmpty)
    XCTAssertFalse(presentation.terms.isEmpty)
    XCTAssertNotNil(presentation.analogy)
    XCTAssertNotNil(presentation.example)
    XCTAssertNotNil(presentation.checkQuestion)
    XCTAssertFalse(presentation.caveats.isEmpty)
    XCTAssertEqual(presentation.lessonMetadata?.confidence, .high)
  }

  func testKeywordLessonsAreCompleteAndDeterministic() async throws {
    let samples = [
      ("API", "API"),
      ("http", "HTTP"),
      ("Json", "JSON"),
      ("ERROR", "Error"),
    ]
    let engine = LLMTutorEngine(
      provider: FakeLLMProvider(
        now: { presentationDate },
        makeID: { presentationResponseID }
      )
    )

    for (keyword, expectedTitleText) in samples {
      let request = try presentationRequest(text: "请解释 \(keyword)")
      let prompt = try TutorPromptBuilder().build(from: request)
      let first = try await engine.respond(to: request, prompt: prompt)
      let second = try await engine.respond(to: request, prompt: prompt)

      guard case let .lesson(firstLesson) = first.outcome,
            case let .lesson(secondLesson) = second.outcome else {
        return XCTFail("Expected lesson for \(keyword)")
      }
      XCTAssertEqual(firstLesson, secondLesson)
      XCTAssertTrue(firstLesson.title?.contains(expectedTitleText) == true)
      XCTAssertFalse(firstLesson.plainExplanation.isEmpty)
      XCTAssertGreaterThanOrEqual(firstLesson.keyPoints.count, 2)
      XCTAssertFalse(firstLesson.glossary.isEmpty)
      XCTAssertNotNil(firstLesson.analogy)
      XCTAssertNotNil(firstLesson.example)
      XCTAssertNotNil(firstLesson.checkQuestion)
      XCTAssertFalse(firstLesson.caveats.isEmpty)
    }
  }

  func testNeedsMoreContextMapsToPresentationStatus() async throws {
    let request = try presentationRequest(text: "上下文不足")
    let engine = LLMTutorEngine(
      provider: FakeLLMProvider(
        behavior: .needsMoreContext,
        now: { presentationDate },
        makeID: { presentationResponseID }
      )
    )
    let response = try await engine.respond(
      to: request,
      prompt: TutorPromptBuilder().build(from: request)
    )
    let presentation = TutorPresentationMapper().makePresentation(from: response)

    XCTAssertEqual(presentation.outcome, .needsMoreContext)
    XCTAssertEqual(presentation.title, "需要更多上下文")
    XCTAssertFalse(presentation.plainExplanation.isEmpty)
    XCTAssertNotNil(presentation.suggestedAction)
    XCTAssertNil(presentation.lessonMetadata)
    XCTAssertNil(presentation.blockReason)
  }

  func testBlockedMapsReasonAndMessage() async throws {
    let request = try presentationRequest(text: "被阻止的内容")
    let engine = LLMTutorEngine(
      provider: FakeLLMProvider(
        behavior: .blocked,
        now: { presentationDate },
        makeID: { presentationResponseID }
      )
    )
    let response = try await engine.respond(
      to: request,
      prompt: TutorPromptBuilder().build(from: request)
    )
    let presentation = TutorPresentationMapper().makePresentation(from: response)

    XCTAssertEqual(presentation.outcome, .blocked)
    XCTAssertEqual(presentation.blockReason, .unsupported)
    XCTAssertFalse(presentation.plainExplanation.isEmpty)
    XCTAssertNil(presentation.lessonMetadata)
    XCTAssertNil(presentation.suggestedAction)
  }
#endif

  func testInvalidResponseIsRejectedBeforePresentationMapping() async {
    let coordinator = TutorCoordinator(engine: InvalidPresentationResponseEngine())

    coordinator.start()
    coordinator.receive(presentationChunk(text: "API"))

    await assertPresentationEventually("Invalid response was not rejected") {
      coordinator.lastError == .invalidResponse([.requestIDMismatch])
    }

    XCTAssertNil(coordinator.latestResponse)
    XCTAssertNil(coordinator.latestPresentation)
    XCTAssertEqual(
      coordinator.providerState,
      .failed(error: .invalidResponse([.requestIDMismatch]))
    )
  }

  func testPresentationMapsEveryLessonSectionAndMetadata() {
    let response = presentationResponse(
      outcome: .lesson(
        TutorLesson(
          title: "标题",
          plainExplanation: "大白话解释",
          keyPoints: ["关键点一", "关键点二"],
          glossary: [TutorTerm(term: "API", plainDefinition: "程序的服务约定")],
          analogy: "像餐厅菜单",
          example: "查询天气",
          checkQuestion: "请求像什么？",
          caveats: ["每个 API 的规则不同"],
          confidence: .medium
        )
      )
    )

    let presentation = TutorPresentationMapper().makePresentation(from: response)

    XCTAssertEqual(presentation.responseMetadata.responseID, response.id)
    XCTAssertEqual(presentation.responseMetadata.requestID, response.requestID)
    XCTAssertEqual(presentation.responseMetadata.sessionID, response.sessionID)
    XCTAssertEqual(presentation.responseMetadata.sequence, response.sequence)
    XCTAssertEqual(presentation.responseMetadata.sourceChunkID, response.sourceChunkID)
    XCTAssertEqual(presentation.responseMetadata.createdAt, response.createdAt)
    XCTAssertEqual(presentation.title, "标题")
    XCTAssertEqual(presentation.plainExplanation, "大白话解释")
    XCTAssertEqual(presentation.keyPoints, ["关键点一", "关键点二"])
    XCTAssertEqual(
      presentation.terms,
      [TutorPresentationTerm(term: "API", plainDefinition: "程序的服务约定")]
    )
    XCTAssertEqual(presentation.analogy, "像餐厅菜单")
    XCTAssertEqual(presentation.example, "查询天气")
    XCTAssertEqual(presentation.checkQuestion, "请求像什么？")
    XCTAssertEqual(presentation.caveats, ["每个 API 的规则不同"])
    XCTAssertEqual(
      presentation.lessonMetadata,
      TutorPresentationLessonMetadata(
        confidence: .medium,
        keyPointCount: 2,
        termCount: 1,
        caveatCount: 1,
        hasAnalogy: true,
        hasExample: true,
        hasCheckQuestion: true
      )
    )
    XCTAssertFalse(presentation.didTruncateContent)
  }

  func testLongPresentationTextIsTruncatedAtConfiguredLimits() {
    let limits = TutorPresentationLimits(
      maximumTitleCharacters: 5,
      maximumExplanationCharacters: 10,
      maximumKeyPoints: 1,
      maximumTerms: 1,
      maximumCaveats: 1,
      maximumListItemCharacters: 8,
      maximumTermCharacters: 4,
      maximumOptionalSectionCharacters: 7,
      maximumStatusCharacters: 9
    )
    let longText = String(repeating: "👩‍💻", count: 20)
    let response = presentationResponse(
      outcome: .lesson(
        TutorLesson(
          title: "这是一个很长的标题",
          plainExplanation: longText,
          keyPoints: [longText, "第二条"],
          glossary: [
            TutorTerm(term: "非常长的术语", plainDefinition: longText),
            TutorTerm(term: "术语二", plainDefinition: "定义二"),
          ],
          analogy: longText,
          example: longText,
          checkQuestion: longText,
          caveats: [longText, "第二条"],
          confidence: .high
        )
      )
    )

    let presentation = TutorPresentationMapper(limits: limits)
      .makePresentation(from: response)

    XCTAssertEqual(presentation.title.count, 5)
    XCTAssertEqual(presentation.plainExplanation.count, 10)
    XCTAssertEqual(presentation.keyPoints.count, 1)
    XCTAssertEqual(presentation.keyPoints.first?.count, 8)
    XCTAssertEqual(presentation.terms.count, 1)
    XCTAssertEqual(presentation.terms.first?.term.count, 4)
    XCTAssertEqual(presentation.terms.first?.plainDefinition.count, 8)
    XCTAssertEqual(presentation.analogy?.count, 7)
    XCTAssertEqual(presentation.example?.count, 7)
    XCTAssertEqual(presentation.checkQuestion?.count, 7)
    XCTAssertEqual(presentation.caveats.count, 1)
    XCTAssertEqual(presentation.caveats.first?.count, 8)
    XCTAssertTrue(presentation.plainExplanation.hasSuffix("…"))
    XCTAssertTrue(presentation.didTruncateContent)
  }

  func testEmptyOptionalFieldsAreOmittedAndRequiredTitleHasFallback() {
    let response = presentationResponse(
      outcome: .lesson(
        TutorLesson(
          title: " \n ",
          plainExplanation: "  可展示的解释  ",
          keyPoints: [" ", "有效关键点"],
          glossary: [
            TutorTerm(term: " ", plainDefinition: " "),
            TutorTerm(term: "JSON", plainDefinition: "数据格式"),
          ],
          analogy: "\n",
          example: nil,
          checkQuestion: " ",
          caveats: ["\t"],
          confidence: .low
        )
      )
    )

    let presentation = TutorPresentationMapper().makePresentation(from: response)

    XCTAssertEqual(presentation.title, "白话解释")
    XCTAssertEqual(presentation.plainExplanation, "可展示的解释")
    XCTAssertEqual(presentation.keyPoints, ["有效关键点"])
    XCTAssertEqual(
      presentation.terms,
      [TutorPresentationTerm(term: "JSON", plainDefinition: "数据格式")]
    )
    XCTAssertNil(presentation.analogy)
    XCTAssertNil(presentation.example)
    XCTAssertNil(presentation.checkQuestion)
    XCTAssertTrue(presentation.caveats.isEmpty)
    XCTAssertFalse(presentation.didTruncateContent)
  }

#if DEBUG
  func testCancellationDoesNotProducePresentation() async {
    let coordinator = TutorCoordinator(
      engine: LLMTutorEngine(
        provider: FakeLLMProvider(responseDelayNanoseconds: 5_000_000_000)
      )
    )

    coordinator.start()
    coordinator.receive(presentationChunk(text: "JSON 是什么？"))
    guard let requestID = coordinator.latestRequest?.id else {
      return XCTFail("Expected active request")
    }

    coordinator.cancelCurrentRequest()
    await settlePresentationTasks()

    XCTAssertEqual(coordinator.requestState, .cancelled(requestID: requestID))
    XCTAssertEqual(coordinator.providerState, .cancelled(requestID: requestID))
    XCTAssertNil(coordinator.latestResponse)
    XCTAssertNil(coordinator.latestPresentation)
    XCTAssertNil(coordinator.latestInteractionInput)
    XCTAssertNil(coordinator.latestInteractionDecision)
    XCTAssertNil(coordinator.displayQueue.currentDisplayItem)
    XCTAssertEqual(coordinator.displayQueue.queueCount, 0)
  }
#endif

  private func assertPresentationEventually(
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

  private func settlePresentationTasks() async {
    for _ in 0..<5 {
      await Task.yield()
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
  }
}

private struct InvalidPresentationResponseEngine: TutorEngine {
  func respond(
    to request: TutorRequest,
    prompt: PromptPackage
  ) async throws -> TutorResponse {
    TutorResponse(
      schemaVersion: TutorResponse.currentSchemaVersion,
      id: presentationResponseID,
      requestID: UUID(),
      sessionID: request.sessionID,
      sequence: request.sequence,
      sourceChunkID: request.source.chunkID,
      createdAt: presentationDate,
      outcome: .lesson(presentationLesson)
    )
  }
}

private let presentationDate = Date(timeIntervalSince1970: 3_100)
private let presentationResponseID = UUID(
  uuidString: "00000000-0000-0000-0000-000000000501"
)!
private let presentationRequestID = UUID(
  uuidString: "00000000-0000-0000-0000-000000000502"
)!
private let presentationSessionID = UUID(
  uuidString: "00000000-0000-0000-0000-000000000503"
)!
private let presentationChunkID = UUID(
  uuidString: "00000000-0000-0000-0000-000000000504"
)!

private let completeOutputPreferences = TutorOutputPreferences(
  language: "zh-Hans",
  detailLevel: .balanced,
  includeAnalogy: true,
  includeExample: true,
  includeCheckQuestion: true
)

private let presentationLesson = TutorLesson(
  title: "白话解释",
  plainExplanation: "这是一段有效解释。",
  keyPoints: [],
  glossary: [],
  analogy: nil,
  example: nil,
  checkQuestion: nil,
  caveats: [],
  confidence: .high
)

private func presentationChunk(text: String) -> SemanticChunk {
  SemanticChunk(
    id: UUID(),
    sourceRevisionID: 7,
    text: text,
    confidence: .high,
    createdAt: Date(timeIntervalSince1970: 3_000),
    flushReason: .sentenceComplete
  )
}

private func presentationRequest(text: String) throws -> TutorRequest {
  try TutorRequestFactory(
    now: { presentationDate },
    makeID: { presentationRequestID }
  ).make(
    from: SemanticChunk(
      id: presentationChunkID,
      sourceRevisionID: 7,
      text: text,
      confidence: .high,
      createdAt: Date(timeIntervalSince1970: 3_000),
      flushReason: .sentenceComplete
    ),
    sessionID: presentationSessionID,
    sequence: 1,
    learner: .productDefault(at: Date(timeIntervalSince1970: 2_900)),
    output: completeOutputPreferences
  )
}

private func presentationResponse(outcome: TutorOutcome) -> TutorResponse {
  TutorResponse(
    schemaVersion: TutorResponse.currentSchemaVersion,
    id: presentationResponseID,
    requestID: presentationRequestID,
    sessionID: presentationSessionID,
    sequence: 1,
    sourceChunkID: presentationChunkID,
    createdAt: presentationDate,
    outcome: outcome
  )
}
