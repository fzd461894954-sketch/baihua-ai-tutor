import XCTest

@testable import AITutorMac

final class TutorContractTests: XCTestCase {
  func testFactoryCopiesSemanticChunkWithoutInventingContext() throws {
    let factory = TutorRequestFactory(now: fixedNow, makeID: requestID)
    let chunk = semanticChunk(
      text: "API 是应用之间约定好的接口。",
      confidence: .medium,
      flushReason: .sentenceComplete
    )
    let learner = LearnerProfileSnapshot(
      level: .beginner,
      selectionSource: .userSelected,
      preferredLanguage: "zh-Hans",
      updatedAt: Date(timeIntervalSince1970: 1_900)
    )

    let request = try factory.make(
      from: chunk,
      sessionID: sessionID(),
      sequence: 7,
      learner: learner,
      trigger: .userInitiated
    )

    XCTAssertEqual(request.schemaVersion, TutorRequest.currentSchemaVersion)
    XCTAssertEqual(request.id, requestID())
    XCTAssertEqual(request.sessionID, sessionID())
    XCTAssertEqual(request.sequence, 7)
    XCTAssertEqual(request.createdAt, fixedNow())
    XCTAssertEqual(request.task, .explainInPlainLanguage)
    XCTAssertEqual(request.trigger, .userInitiated)
    XCTAssertEqual(request.source.chunkID, chunk.id)
    XCTAssertEqual(request.source.sourceRevisionID, chunk.sourceRevisionID)
    XCTAssertEqual(request.source.text, chunk.text)
    XCTAssertEqual(request.source.diffConfidence, .medium)
    XCTAssertEqual(request.source.flushReason, .sentenceComplete)
    XCTAssertEqual(request.source.chunkCreatedAt, chunk.createdAt)
    XCTAssertEqual(request.source.completeness, .completeSentence)
    XCTAssertEqual(request.learner, learner)
    XCTAssertEqual(request.output.language, learner.preferredLanguage)
    XCTAssertEqual(request.policyVersion, TutorRequestFactory.defaultPolicyVersion)
  }

  func testSourceCompletenessMapsEveryFlushReason() throws {
    let factory = TutorRequestFactory()
    let expectations: [(SemanticFlushReason, TutorSourceCompleteness)] = [
      (.sentenceComplete, .completeSentence),
      (.idleTimeout, .possiblyIncomplete),
      (.sizeLimit, .boundedSegment),
      (.manualFlush, .userForced),
    ]

    for (index, expectation) in expectations.enumerated() {
      let request = try factory.make(
        from: semanticChunk(flushReason: expectation.0),
        sessionID: sessionID(),
        sequence: index + 1,
        learner: .productDefault(at: fixedNow())
      )
      XCTAssertEqual(request.source.completeness, expectation.1)
    }
  }

  func testFactoryRejectsWhitespaceAndOversizedSourceText() {
    let factory = TutorRequestFactory(maximumSourceCharacterCount: 4)

    assertFactoryError(
      chunk: semanticChunk(text: " \n\t "),
      factory: factory,
      expected: .invalidRequest(.emptySourceText)
    )
    assertFactoryError(
      chunk: semanticChunk(text: "12345"),
      factory: factory,
      expected: .invalidRequest(.sourceTextTooLong(maximum: 4, actual: 5))
    )
  }

  func testFactoryCountsExtendedGraphemeClusters() throws {
    let factory = TutorRequestFactory(maximumSourceCharacterCount: 2)
    let request = try factory.make(
      from: semanticChunk(text: "好👩‍💻"),
      sessionID: sessionID(),
      sequence: 1,
      learner: .productDefault(at: fixedNow())
    )

    XCTAssertEqual(request.source.text.count, 2)
  }

  func testFactoryCannotRaiseTheDomainSourceLimit() {
    let factory = TutorRequestFactory(maximumSourceCharacterCount: 2_000)

    XCTAssertEqual(
      factory.maximumSourceCharacterCount,
      TutorRequest.defaultMaximumSourceCharacterCount
    )
    assertFactoryError(
      chunk: semanticChunk(text: String(repeating: "字", count: 1_001)),
      factory: factory,
      expected: .invalidRequest(
        .sourceTextTooLong(maximum: 1_000, actual: 1_001)
      )
    )
  }

  func testFakeLLMProviderCompletesRawDecodeAndValidationPipeline() async throws {
    let request = try makeRequest()
    let engine: any TutorEngine = LLMTutorEngine(
      provider: FakeLLMProvider(
        behavior: .success,
        now: responseNow,
        makeID: responseID
      )
    )
    let prompt = try TutorPromptBuilder().build(from: request)

    let response = try await engine.respond(to: request, prompt: prompt)

    XCTAssertEqual(response.schemaVersion, TutorResponse.currentSchemaVersion)
    XCTAssertEqual(response.id, responseID())
    XCTAssertEqual(response.requestID, request.id)
    XCTAssertEqual(response.sessionID, request.sessionID)
    XCTAssertEqual(response.sequence, request.sequence)
    XCTAssertEqual(response.sourceChunkID, request.source.chunkID)
    XCTAssertEqual(response.createdAt, responseNow())
    guard case let .lesson(lesson) = response.outcome else {
      return XCTFail("Expected a lesson response")
    }
    XCTAssertFalse(lesson.plainExplanation.isEmpty)
    XCTAssertEqual(lesson.confidence, .high)
  }

  func testFakeLLMProviderSupportsNonLessonOutcomes() async throws {
    let request = try makeRequest()
    let prompt = try TutorPromptBuilder().build(from: request)

    let needsMoreContext = try await LLMTutorEngine(
      provider: FakeLLMProvider(behavior: .needsMoreContext)
    ).respond(to: request, prompt: prompt)
    guard case let .needsMoreContext(value) = needsMoreContext.outcome else {
      return XCTFail("Expected needsMoreContext")
    }
    XCTAssertFalse(value.reason.isEmpty)

    let blocked = try await LLMTutorEngine(
      provider: FakeLLMProvider(behavior: .blocked)
    ).respond(to: request, prompt: prompt)
    guard case let .blocked(value) = blocked.outcome else {
      return XCTFail("Expected blocked")
    }
    XCTAssertEqual(value.reason, .unsupported)
  }

  func testFakeLLMProviderPropagatesConfiguredProviderError() async throws {
    let request = try makeRequest()
    let engine = LLMTutorEngine(
      provider: FakeLLMProvider(behavior: .unavailable)
    )

    do {
      _ = try await engine.respond(
        to: request,
        prompt: TutorPromptBuilder().build(from: request)
      )
      XCTFail("Expected unavailable error")
    } catch let error as LLMProviderError {
      XCTAssertEqual(error, .unavailable)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testResponseValidatorAcceptsAValidLesson() throws {
    let request = try makeRequest()
    let response = tutorResponse(
      for: request,
      outcome: .lesson(validLesson())
    )

    XCTAssertEqual(
      try TutorResponseValidator().validate(response, for: request),
      response
    )
  }

  func testResponseValidatorRejectsCorrelationMismatch() throws {
    let request = try makeRequest()
    let response = TutorResponse(
      schemaVersion: TutorResponse.currentSchemaVersion,
      id: responseID(),
      requestID: UUID(),
      sessionID: UUID(),
      sequence: request.sequence + 1,
      sourceChunkID: UUID(),
      createdAt: responseNow(),
      outcome: .lesson(validLesson())
    )

    assertValidationIssues(
      response,
      request: request,
      expected: [
        .requestIDMismatch,
        .sessionIDMismatch,
        .sequenceMismatch,
        .sourceChunkIDMismatch,
      ]
    )
  }

  func testResponseValidatorRejectsInvalidLessonBody() throws {
    let request = try makeRequest()
    let response = tutorResponse(
      for: request,
      outcome: .lesson(
        TutorLesson(
          title: " ",
          plainExplanation: "\n",
          keyPoints: ["", "1", "2", "3", "4", "5"],
          glossary: [TutorTerm(term: " ", plainDefinition: "")],
          analogy: nil,
          example: nil,
          checkQuestion: nil,
          caveats: [],
          confidence: .low
        )
      )
    )

    assertValidationIssues(
      response,
      request: request,
      expected: [
        .emptyPlainExplanation,
        .emptyOptionalLessonField(.title),
        .tooManyKeyPoints(maximum: 5, actual: 6),
        .emptyKeyPoint(index: 0),
        .emptyGlossaryTerm(index: 0),
        .emptyGlossaryDefinition(index: 0),
      ]
    )
  }

  func testResponseValidatorRejectsEmptyStatusBodies() throws {
    let request = try makeRequest()

    assertValidationIssues(
      tutorResponse(
        for: request,
        outcome: .needsMoreContext(
          TutorNeedsMoreContext(reason: " ", suggestedAction: "\n")
        )
      ),
      request: request,
      expected: [.emptyNeedsMoreContextReason, .emptySuggestedAction]
    )

    assertValidationIssues(
      tutorResponse(
        for: request,
        outcome: .blocked(TutorBlock(reason: .invalidInput, message: ""))
      ),
      request: request,
      expected: [.emptyBlockMessage]
    )
  }

  private func makeRequest() throws -> TutorRequest {
    try TutorRequestFactory(now: fixedNow, makeID: requestID).make(
      from: semanticChunk(),
      sessionID: sessionID(),
      sequence: 1,
      learner: .productDefault(at: fixedNow())
    )
  }

  private func semanticChunk(
    text: String = "稳定的新增文本。",
    confidence: DiffConfidence = .high,
    flushReason: SemanticFlushReason = .sentenceComplete
  ) -> SemanticChunk {
    SemanticChunk(
      id: chunkID(),
      sourceRevisionID: 3,
      text: text,
      confidence: confidence,
      createdAt: Date(timeIntervalSince1970: 1_800),
      flushReason: flushReason
    )
  }

  private func tutorResponse(
    for request: TutorRequest,
    outcome: TutorOutcome
  ) -> TutorResponse {
    TutorResponse(
      schemaVersion: TutorResponse.currentSchemaVersion,
      id: responseID(),
      requestID: request.id,
      sessionID: request.sessionID,
      sequence: request.sequence,
      sourceChunkID: request.source.chunkID,
      createdAt: responseNow(),
      outcome: outcome
    )
  }

  private func validLesson() -> TutorLesson {
    TutorLesson(
      title: "白话解释",
      plainExplanation: "这是一段有效的白话解释。",
      keyPoints: ["第一点", "第二点"],
      glossary: [TutorTerm(term: "API", plainDefinition: "应用之间的约定接口")],
      analogy: "像餐厅菜单。",
      example: "一个程序向另一个程序请求数据。",
      checkQuestion: "API 的作用是什么？",
      caveats: ["当前输入只是新增片段。"],
      confidence: .high
    )
  }

  private func assertFactoryError(
    chunk: SemanticChunk,
    factory: TutorRequestFactory,
    expected: TutorEngineError,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try factory.make(
        from: chunk,
        sessionID: sessionID(),
        sequence: 1,
        learner: .productDefault(at: fixedNow())
      ),
      file: file,
      line: line
    ) { error in
      XCTAssertEqual(error as? TutorEngineError, expected, file: file, line: line)
    }
  }

  private func assertValidationIssues(
    _ response: TutorResponse,
    request: TutorRequest,
    expected: [TutorResponseValidationIssue],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try TutorResponseValidator().validate(response, for: request),
      file: file,
      line: line
    ) { error in
      XCTAssertEqual(
        error as? TutorEngineError,
        .invalidResponse(expected),
        file: file,
        line: line
      )
    }
  }

  private func fixedNow() -> Date {
    Date(timeIntervalSince1970: 2_000)
  }

  private func responseNow() -> Date {
    Date(timeIntervalSince1970: 2_100)
  }

  private func chunkID() -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
  }

  private func requestID() -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
  }

  private func responseID() -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
  }

  private func sessionID() -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000404")!
  }
}
