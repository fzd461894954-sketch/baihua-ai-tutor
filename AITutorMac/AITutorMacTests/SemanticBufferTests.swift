import Darwin
import XCTest

@testable import AITutorMac

@MainActor
final class SemanticBufferTests: XCTestCase {
  func testDefaultPolicyUsesStabilityCheckThenFifteenHundredMillisecondFlush() {
    XCTAssertEqual(SemanticBufferConfiguration.default.stabilityCheckDelay, 0.7)
    XCTAssertEqual(SemanticBufferConfiguration.default.idleFlushDelay, 1.5)
    XCTAssertEqual(SemanticBufferConfiguration.default.maximumCharacterCount, 1_000)
  }

  func testCompleteSentenceImmediatelyProducesOneChunk() {
    let buffer = SemanticBuffer(now: fixedNow, makeID: fixedID)
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }

    buffer.ingest(revision(id: 1, addedText: "这是完整句子。", characterCount: 7))

    XCTAssertEqual(chunks.count, 1)
    XCTAssertEqual(chunks[0].id, fixedID())
    XCTAssertEqual(chunks[0].sourceRevisionID, 1)
    XCTAssertEqual(chunks[0].text, "这是完整句子。")
    XCTAssertEqual(chunks[0].confidence, .high)
    XCTAssertEqual(chunks[0].createdAt, fixedNow())
    XCTAssertEqual(chunks[0].flushReason, .sentenceComplete)
    XCTAssertEqual(buffer.state, .idle)
    XCTAssertEqual(buffer.pendingCharacterCount, 0)
  }

  func testStreamingGrowthProducesOneCombinedChunk() {
    let buffer = SemanticBuffer()
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }

    buffer.ingest(revision(id: 1, addedText: "API 是", characterCount: 5))
    buffer.ingest(revision(id: 2, addedText: "接口", characterCount: 7))
    XCTAssertTrue(chunks.isEmpty)
    XCTAssertEqual(buffer.pendingText, "API 是接口")

    buffer.ingest(revision(id: 3, addedText: "。", characterCount: 8))

    XCTAssertEqual(chunks.map(\.text), ["API 是接口。"])
    XCTAssertEqual(chunks.first?.sourceRevisionID, 3)
    XCTAssertEqual(buffer.chunkCount, 1)
  }

  func testMultipleSentencesProduceMultipleChunks() {
    let buffer = SemanticBuffer()
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }

    buffer.ingest(
      revision(id: 8, addedText: "第一句。Second sentence!最后一句？", characterCount: 29)
    )

    XCTAssertEqual(chunks.map(\.text), ["第一句。", "Second sentence!", "最后一句？"])
    XCTAssertEqual(chunks.map(\.flushReason), Array(repeating: .sentenceComplete, count: 3))
    XCTAssertEqual(buffer.chunkCount, 3)
  }

  func testStabilityCheckDoesNotFlushBeforeIdleDeadline() async {
    let buffer = SemanticBuffer(
      configuration: SemanticBufferConfiguration(
        stabilityCheckDelay: 0.02,
        idleFlushDelay: 0.08,
        maximumCharacterCount: 1_000
      )
    )
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }
    buffer.ingest(revision(id: 1, addedText: "尚未结束", characterCount: 4))

    await waitFor { buffer.state == .ready }

    XCTAssertTrue(chunks.isEmpty)
    XCTAssertEqual(buffer.pendingText, "尚未结束")

    await waitFor { chunks.count == 1 }
    XCTAssertEqual(chunks.first?.flushReason, .idleTimeout)
  }

  func testNewInputCancelsAndReplacesIdleFlushTask() async {
    let buffer = SemanticBuffer(configuration: fastConfiguration)
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }

    buffer.ingest(revision(id: 1, addedText: "API ", characterCount: 4))
    try? await Task.sleep(nanoseconds: 10_000_000)
    buffer.ingest(revision(id: 2, addedText: "稳定", characterCount: 6))

    try? await Task.sleep(nanoseconds: 20_000_000)
    XCTAssertTrue(chunks.isEmpty)

    await waitFor { chunks.count == 1 }
    XCTAssertEqual(chunks.first?.text, "API 稳定")
    XCTAssertEqual(chunks.first?.sourceRevisionID, 2)
  }

  func testSizeLimitUsesMostRecentSentenceBoundary() {
    let buffer = SemanticBuffer(
      configuration: SemanticBufferConfiguration(
        stabilityCheckDelay: 0.7,
        idleFlushDelay: 1.5,
        maximumCharacterCount: 8
      )
    )
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }

    buffer.ingest(revision(id: 1, addedText: "甲乙。丙丁戊己庚辛", characterCount: 10))

    XCTAssertEqual(chunks.count, 1)
    XCTAssertEqual(chunks[0].text, "甲乙。")
    XCTAssertEqual(chunks[0].flushReason, .sizeLimit)
    XCTAssertEqual(buffer.pendingText, "丙丁戊己庚辛")
    XCTAssertLessThan(buffer.pendingCharacterCount, 8)
  }

  func testResetClearsPendingTextAndCancelsTask() {
    let buffer = SemanticBuffer()
    buffer.ingest(revision(id: 1, addedText: "pending", characterCount: 7))
    XCTAssertTrue(buffer.hasScheduledFlushTask)

    buffer.ingest(revision(id: 2, kind: .reset, addedText: "", characterCount: 30))

    XCTAssertEqual(buffer.state, .idle)
    XCTAssertEqual(buffer.pendingText, "")
    XCTAssertFalse(buffer.hasScheduledFlushTask)
    XCTAssertEqual(buffer.chunkCount, 0)
  }

  func testBaselineNoChangeAndAmbiguousNeverEmitText() {
    let buffer = SemanticBuffer()
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }

    buffer.ingest(revision(id: 0, kind: .baseline, addedText: "full screen", characterCount: 11))
    buffer.ingest(revision(id: 0, kind: .noChange, addedText: "", characterCount: 11))
    buffer.ingest(revision(id: 1, kind: .ambiguous, addedText: "", characterCount: 12))

    XCTAssertTrue(chunks.isEmpty)
    XCTAssertEqual(buffer.pendingCharacterCount, 0)
    XCTAssertFalse(buffer.hasScheduledFlushTask)
  }

  func testIdentityChangeClearsBeforeAcceptingNewContext() {
    let buffer = SemanticBuffer()
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }
    buffer.ingest(revision(id: 1, addedText: "旧上下文", characterCount: 4))

    buffer.ingest(
      revision(
        id: 1,
        addedText: "新上下文。",
        characterCount: 5,
        identity: identity(window: "window-b")
      )
    )

    XCTAssertEqual(chunks.map(\.text), ["新上下文。"])
    XCTAssertFalse(chunks.contains { $0.text.contains("旧上下文") })
    XCTAssertEqual(buffer.currentIdentity, identity(window: "window-b"))
  }

  func testOneHundredFastRevisionsProduceFarFewerChunks() {
    let buffer = SemanticBuffer()
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }
    var characterCount = 0

    for id in 1...100 {
      let fragment = id.isMultiple(of: 20) ? "。" : "字"
      characterCount += fragment.count
      buffer.ingest(
        revision(id: id, addedText: fragment, characterCount: characterCount)
      )
    }

    XCTAssertEqual(chunks.count, 5)
    XCTAssertEqual(chunks.map(\.sourceRevisionID), [20, 40, 60, 80, 100])
    XCTAssertEqual(buffer.pendingCharacterCount, 0)
    XCTAssertFalse(buffer.hasScheduledFlushTask)
  }

  func testEmojiRemainWholeCharacters() {
    let buffer = SemanticBuffer()
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }

    buffer.ingest(revision(id: 1, addedText: "你好👩‍💻", characterCount: 3))
    buffer.ingest(revision(id: 2, addedText: "！", characterCount: 4))

    XCTAssertEqual(chunks.map(\.text), ["你好👩‍💻！"])
    XCTAssertEqual(chunks.first?.text.count, 4)
  }

  func testFencedCodeDoesNotFlushOnInternalPunctuation() async {
    let buffer = SemanticBuffer(configuration: fastConfiguration)
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }
    let code = "```swift\nprint(\"Hi.\")\n```"

    buffer.ingest(revision(id: 1, addedText: code, characterCount: code.count))

    XCTAssertTrue(chunks.isEmpty)
    await waitFor { chunks.count == 1 }
    XCTAssertEqual(chunks.first?.text, code)
    XCTAssertEqual(chunks.first?.flushReason, .idleTimeout)
  }

  func testMixedChineseAndEnglishFlushesAsOneSentence() {
    let buffer = SemanticBuffer()
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }

    buffer.ingest(revision(id: 1, addedText: "Semantic Buffer ", characterCount: 16))
    buffer.ingest(revision(id: 2, addedText: "已经 ready。", characterCount: 25))

    XCTAssertEqual(chunks.map(\.text), ["Semantic Buffer 已经 ready。"])
  }

  func testManualFlushUsesManualReasonAndLowestConfidence() {
    let buffer = SemanticBuffer(now: fixedNow, makeID: fixedID)
    buffer.ingest(
      revision(id: 1, addedText: "partial ", characterCount: 8, confidence: .high)
    )
    buffer.ingest(
      revision(id: 2, addedText: "content", characterCount: 15, confidence: .medium)
    )

    let chunk = buffer.manualFlush()

    XCTAssertEqual(chunk?.text, "partial content")
    XCTAssertEqual(chunk?.confidence, .medium)
    XCTAssertEqual(chunk?.flushReason, .manualFlush)
    XCTAssertFalse(buffer.hasScheduledFlushTask)
  }

  func testOneThousandRevisionsRemainBoundedAndLeaveNoTask() {
    let buffer = SemanticBuffer(
      configuration: SemanticBufferConfiguration(
        stabilityCheckDelay: 0.7,
        idleFlushDelay: 1.5,
        maximumCharacterCount: 100
      )
    )
    var emittedCharacterCount = 0
    buffer.onChunk = { emittedCharacterCount += $0.text.count }

    for id in 1...1_000 {
      buffer.ingest(revision(id: id, addedText: "x", characterCount: id))
      XCTAssertLessThan(buffer.pendingCharacterCount, 100)
    }

    XCTAssertEqual(buffer.chunkCount, 10)
    XCTAssertEqual(emittedCharacterCount, 1_000)
    XCTAssertEqual(buffer.pendingCharacterCount, 0)
    XCTAssertEqual(buffer.state, .idle)
    XCTAssertFalse(buffer.hasScheduledFlushTask)
  }

  private var fastConfiguration: SemanticBufferConfiguration {
    SemanticBufferConfiguration(
      stabilityCheckDelay: 0.01,
      idleFlushDelay: 0.04,
      maximumCharacterCount: 1_000
    )
  }

  private func revision(
    id: Int,
    kind: ContextDiffKind = .added,
    addedText: String,
    characterCount: Int,
    confidence: DiffConfidence = .high,
    identity: ContextIdentity? = nil
  ) -> ContextRevision {
    ContextRevision(
      revisionID: id,
      timestamp: fixedNow(),
      changeType: kind,
      addedText: addedText,
      confidence: confidence,
      fingerprint: ContextFingerprint(rawValue: "fingerprint-\(id)"),
      characterCount: characterCount,
      identity: identity ?? self.identity()
    )
  }

  private func identity(window: String = "window-a") -> ContextIdentity {
    ContextIdentity(
      bundleIdentifier: "com.openai.codex",
      processIdentifier: 200,
      focusedWindowIdentity: FocusedWindowIdentity(rawValue: window),
      liveSessionIdentifier: UUID(
        uuidString: "00000000-0000-0000-0000-000000000301"
      )!
    )
  }

  private func waitFor(
    timeoutNanoseconds: UInt64 = 500_000_000,
    _ condition: @escaping @MainActor () -> Bool
  ) async {
    let iterations = Int(timeoutNanoseconds / 5_000_000)
    for _ in 0..<max(1, iterations) {
      if condition() {
        return
      }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for SemanticBuffer state")
  }

  private func fixedNow() -> Date {
    Date(timeIntervalSince1970: 3_000)
  }

  private func fixedID() -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000399")!
  }
}
