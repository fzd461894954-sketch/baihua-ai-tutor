import XCTest

@testable import AITutorMac

@MainActor
final class TutorCoordinatorTests: XCTestCase {
#if DEBUG
  func testChunkCreatesRequestAndCompletesFakeFlow() async throws {
    let coordinator = TutorCoordinator(
      engine: LLMTutorEngine(provider: FakeLLMProvider())
    )
    let chunk = makeChunk(text: "API 是应用之间的约定。")

    coordinator.start()
    coordinator.receive(chunk)

    await assertEventually("Fake response was not received") {
      coordinator.latestResponse != nil
    }

    XCTAssertEqual(coordinator.latestChunk, chunk)
    XCTAssertEqual(coordinator.latestChunkAdmission, .accepted(.automatic))
    XCTAssertEqual(coordinator.latestRequest?.source.chunkID, chunk.id)
    XCTAssertEqual(coordinator.latestRequest?.sequence, 1)
    XCTAssertNotNil(coordinator.latestPromptPackage)
    XCTAssertEqual(coordinator.requestCount, 1)
    guard let request = coordinator.latestRequest,
          let response = coordinator.latestResponse else {
      return XCTFail("Expected a completed request and response")
    }
    XCTAssertEqual(
      coordinator.requestState,
      .succeeded(requestID: request.id, sequence: request.sequence)
    )
    XCTAssertEqual(coordinator.providerState, .succeeded(responseID: response.id))
    XCTAssertEqual(response.requestID, request.id)
    XCTAssertEqual(response.sessionID, request.sessionID)
    XCTAssertEqual(response.sourceChunkID, chunk.id)
    XCTAssertEqual(coordinator.latestPresentation?.responseMetadata.responseID, response.id)
    XCTAssertEqual(coordinator.latestPresentation?.outcome, .lesson)
  }
#endif

  func testDuplicateChunkDoesNotCreateAnotherRequest() async throws {
    let engine = ControlledTutorEngine()
    let coordinator = TutorCoordinator(engine: engine)
    let chunk = makeChunk()

    coordinator.start()
    coordinator.receive(chunk)
    await assertEventually("First request was not started") {
      await engine.requestCount() == 1
    }

    coordinator.receive(chunk)

    XCTAssertEqual(coordinator.receivedChunkCount, 2)
    XCTAssertEqual(coordinator.duplicateChunkCount, 1)
    XCTAssertEqual(coordinator.requestCount, 1)
    XCTAssertEqual(coordinator.latestChunkAdmission, .skipped(.duplicateChunk))
    let providerRequestCount = await engine.requestCount()
    XCTAssertEqual(providerRequestCount, 1)

    let capturedRequest = await engine.request(at: 0)
    let request = try XCTUnwrap(capturedRequest)
    await engine.complete(with: makeResponse(for: request))
    await assertEventually("Pending request was not completed") {
      coordinator.latestResponse != nil
    }
  }

  func testLowConfidenceAutomaticChunkIsSkippedButManualChunkIsAccepted() async throws {
    let engine = ControlledTutorEngine()
    let coordinator = TutorCoordinator(engine: engine)

    coordinator.start()
    coordinator.receive(
      makeChunk(
        text: "可能还不稳定",
        confidence: .low,
        flushReason: .idleTimeout
      )
    )

    XCTAssertEqual(coordinator.latestChunkAdmission, .skipped(.lowConfidence))
    XCTAssertEqual(coordinator.requestCount, 0)
    let skippedProviderRequestCount = await engine.requestCount()
    XCTAssertEqual(skippedProviderRequestCount, 0)

    coordinator.receive(
      makeChunk(
        text: "用户要求现在解释",
        confidence: .low,
        flushReason: .manualFlush
      )
    )
    await assertEventually("Manual request was not accepted") {
      await engine.requestCount() == 1
    }

    let capturedRequest = await engine.request(at: 0)
    let request = try XCTUnwrap(capturedRequest)
    XCTAssertEqual(request.trigger, .userInitiated)
    XCTAssertEqual(coordinator.latestChunkAdmission, .accepted(.userInitiated))

    await engine.complete(with: makeResponse(for: request))
    await assertEventually("Manual request did not complete") {
      coordinator.latestResponse?.requestID == request.id
    }
  }

  func testNewRequestAndExplicitCancelCancelActiveProviderWork() async throws {
    let engine = CancellationObservingEngine()
    let coordinator = TutorCoordinator(engine: engine)

    coordinator.start()
    coordinator.receive(makeChunk(text: "第一个片段。"))
    await assertEventually("First provider call was not started") {
      await engine.startedRequestIDs().count == 1
    }
    let firstStartedIDs = await engine.startedRequestIDs()
    let firstID = try XCTUnwrap(firstStartedIDs.first)

    coordinator.receive(makeChunk(text: "第二个片段。"))
    await assertEventually("Replacement request did not cancel the first call") {
      let started = await engine.startedRequestIDs()
      let cancelled = await engine.cancelledRequestIDs()
      return started.count == 2 && cancelled.contains(firstID)
    }
    let secondStartedIDs = await engine.startedRequestIDs()
    let secondID = try XCTUnwrap(secondStartedIDs.last)

    coordinator.cancelCurrentRequest()
    await assertEventually("Explicit cancellation did not reach the provider") {
      await engine.cancelledRequestIDs().contains(secondID)
    }

    XCTAssertEqual(coordinator.requestState, .cancelled(requestID: secondID))
    XCTAssertEqual(coordinator.providerState, .cancelled(requestID: secondID))
    XCTAssertEqual(coordinator.lastError, .cancelled)
    XCTAssertNil(coordinator.activeExecutionContext)
    XCTAssertNil(coordinator.latestPresentation)
    XCTAssertEqual(coordinator.state, .idle)
  }

  func testOutOfOrderResponseCannotOverwriteNewestResponse() async throws {
    let engine = ControlledTutorEngine()
    let coordinator = TutorCoordinator(engine: engine)

    coordinator.start()
    coordinator.receive(makeChunk(text: "旧片段。"))
    await assertEventually("First request was not captured") {
      await engine.requestCount() == 1
    }
    let capturedOldRequest = await engine.request(at: 0)
    let oldRequest = try XCTUnwrap(capturedOldRequest)

    coordinator.receive(makeChunk(text: "新片段。"))
    await assertEventually("Second request was not captured") {
      await engine.requestCount() == 2
    }
    let capturedNewRequest = await engine.request(at: 1)
    let newRequest = try XCTUnwrap(capturedNewRequest)
    let newResponse = makeResponse(for: newRequest)

    await engine.complete(with: newResponse)
    await assertEventually("Newest response was not applied") {
      coordinator.latestResponse?.id == newResponse.id
    }

    await engine.complete(with: makeResponse(for: oldRequest))
    await allowTasksToSettle()

    XCTAssertEqual(coordinator.latestResponse?.id, newResponse.id)
    XCTAssertEqual(coordinator.latestResponse?.requestID, newRequest.id)
    XCTAssertEqual(
      coordinator.latestPresentation?.responseMetadata.responseID,
      newResponse.id
    )
    XCTAssertEqual(
      coordinator.requestState,
      .succeeded(requestID: newRequest.id, sequence: newRequest.sequence)
    )
  }

  func testSessionResetRejectsOldResponseAndRestartsSequence() async throws {
    let engine = ControlledTutorEngine()
    let coordinator = TutorCoordinator(engine: engine)

    coordinator.start()
    let oldSessionID = try XCTUnwrap(coordinator.currentSessionID)
    coordinator.receive(makeChunk(text: "旧 session 的片段。"))
    await assertEventually("Old session request was not captured") {
      await engine.requestCount() == 1
    }
    let capturedOldRequest = await engine.request(at: 0)
    let oldRequest = try XCTUnwrap(capturedOldRequest)

    coordinator.resetSession()
    let newSessionID = try XCTUnwrap(coordinator.currentSessionID)

    XCTAssertNotEqual(newSessionID, oldSessionID)
    XCTAssertNil(coordinator.latestChunk)
    XCTAssertNil(coordinator.latestRequest)
    XCTAssertNil(coordinator.latestResponse)
    XCTAssertNil(coordinator.latestPresentation)
    XCTAssertEqual(coordinator.requestCount, 0)
    XCTAssertEqual(coordinator.state, .idle)

    await engine.complete(with: makeResponse(for: oldRequest))
    await allowTasksToSettle()
    XCTAssertNil(coordinator.latestResponse)

    coordinator.receive(makeChunk(text: "新 session 的片段。"))
    await assertEventually("New session request was not captured") {
      await engine.requestCount() == 2
    }
    let capturedNewRequest = await engine.request(at: 1)
    let newRequest = try XCTUnwrap(capturedNewRequest)
    XCTAssertEqual(newRequest.sessionID, newSessionID)
    XCTAssertEqual(newRequest.sequence, 1)

    await engine.complete(with: makeResponse(for: newRequest))
    await assertEventually("New session response was not applied") {
      coordinator.latestResponse?.requestID == newRequest.id
    }
  }

  func testStopCancelsAndClearsSessionState() async throws {
    let engine = ControlledTutorEngine()
    let coordinator = TutorCoordinator(engine: engine)

    coordinator.start()
    coordinator.receive(makeChunk())
    await assertEventually("Provider request was not captured") {
      await engine.requestCount() == 1
    }
    let capturedRequest = await engine.request(at: 0)
    let request = try XCTUnwrap(capturedRequest)

    coordinator.stop()

    XCTAssertEqual(coordinator.state, .stopped)
    XCTAssertNil(coordinator.currentSessionID)
    XCTAssertNil(coordinator.latestChunk)
    XCTAssertNil(coordinator.latestChunkAdmission)
    XCTAssertNil(coordinator.latestRequest)
    XCTAssertNil(coordinator.latestResponse)
    XCTAssertNil(coordinator.latestPresentation)
    XCTAssertNil(coordinator.activeExecutionContext)
    XCTAssertNil(coordinator.lastError)
    XCTAssertEqual(coordinator.requestState, .idle)
    XCTAssertEqual(coordinator.providerState, .idle)
    XCTAssertEqual(coordinator.receivedChunkCount, 0)
    XCTAssertEqual(coordinator.duplicateChunkCount, 0)
    XCTAssertEqual(coordinator.requestCount, 0)

    await engine.complete(with: makeResponse(for: request))
    await allowTasksToSettle()
    XCTAssertNil(coordinator.latestResponse)
    XCTAssertNil(coordinator.latestPresentation)
    XCTAssertEqual(coordinator.state, .stopped)
  }

#if DEBUG
  func testProviderFailureIsExposedWithoutResponse() async {
    let coordinator = TutorCoordinator(
      engine: LLMTutorEngine(
        provider: FakeLLMProvider(behavior: .unavailable)
      )
    )

    coordinator.start()
    coordinator.receive(makeChunk())

    await assertEventually("Provider failure was not recorded") {
      coordinator.lastError == .provider(.unavailable)
    }

    guard let request = coordinator.latestRequest else {
      return XCTFail("Expected the failed request metadata")
    }
    XCTAssertEqual(
      coordinator.requestState,
      .failed(requestID: request.id, error: .provider(.unavailable))
    )
    XCTAssertEqual(
      coordinator.providerState,
      .failed(error: .provider(.unavailable))
    )
    XCTAssertNil(coordinator.latestResponse)
    XCTAssertNil(coordinator.latestPresentation)
    XCTAssertEqual(coordinator.state, .idle)
  }
#endif

  func testValidatorFailureRejectsProviderResponse() async {
    let coordinator = TutorCoordinator(engine: InvalidResponseEngine())

    coordinator.start()
    coordinator.receive(makeChunk())

    await assertEventually("Validator failure was not recorded") {
      coordinator.lastError == .invalidResponse([.requestIDMismatch])
    }

    guard let request = coordinator.latestRequest else {
      return XCTFail("Expected request metadata")
    }
    let expectedError = TutorEngineError.invalidResponse([.requestIDMismatch])
    XCTAssertEqual(
      coordinator.requestState,
      .failed(requestID: request.id, error: expectedError)
    )
    XCTAssertEqual(coordinator.providerState, .failed(error: expectedError))
    XCTAssertNil(coordinator.latestResponse)
    XCTAssertNil(coordinator.latestPresentation)
  }

  private func assertEventually(
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

  private func allowTasksToSettle() async {
    for _ in 0..<5 {
      await Task.yield()
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
  }
}

private actor ControlledTutorEngine: TutorEngine {
  typealias Completion = Result<TutorResponse, TutorEngineError>
  typealias Continuation = CheckedContinuation<Completion, Never>

  private var requests: [TutorRequest] = []
  private var continuations: [UUID: Continuation] = [:]

  func respond(
    to request: TutorRequest,
    prompt: PromptPackage
  ) async throws -> TutorResponse {
    let result = await withCheckedContinuation { continuation in
      requests.append(request)
      continuations[request.id] = continuation
    }
    return try result.get()
  }

  func requestCount() -> Int {
    requests.count
  }

  func request(at index: Int) -> TutorRequest? {
    requests.indices.contains(index) ? requests[index] : nil
  }

  func complete(with response: TutorResponse) {
    continuations.removeValue(forKey: response.requestID)?.resume(
      returning: .success(response)
    )
  }
}

private actor CancellationObservingEngine: TutorEngine {
  private var started: [UUID] = []
  private var cancelled: [UUID] = []

  func respond(
    to request: TutorRequest,
    prompt: PromptPackage
  ) async throws -> TutorResponse {
    started.append(request.id)
    do {
      try await Task.sleep(nanoseconds: 30_000_000_000)
    } catch {
      cancelled.append(request.id)
      throw TutorEngineError.cancelled
    }
    throw TutorEngineError.generationFailed
  }

  func startedRequestIDs() -> [UUID] {
    started
  }

  func cancelledRequestIDs() -> [UUID] {
    cancelled
  }
}

private struct InvalidResponseEngine: TutorEngine {
  func respond(
    to request: TutorRequest,
    prompt: PromptPackage
  ) async throws -> TutorResponse {
    TutorResponse(
      schemaVersion: TutorResponse.currentSchemaVersion,
      id: UUID(),
      requestID: UUID(),
      sessionID: request.sessionID,
      sequence: request.sequence,
      sourceChunkID: request.source.chunkID,
      createdAt: Date(),
      outcome: .lesson(
        TutorLesson(
          title: nil,
          plainExplanation: "这个响应故意使用了错误的 request ID。",
          keyPoints: [],
          glossary: [],
          analogy: nil,
          example: nil,
          checkQuestion: nil,
          caveats: [],
          confidence: .high
        )
      )
    )
  }
}

private func makeChunk(
  id: UUID = UUID(),
  text: String = "这是一个稳定的语义片段。",
  confidence: DiffConfidence = .high,
  flushReason: SemanticFlushReason = .sentenceComplete
) -> SemanticChunk {
  SemanticChunk(
    id: id,
    sourceRevisionID: 42,
    text: text,
    confidence: confidence,
    createdAt: Date(timeIntervalSince1970: 2_000),
    flushReason: flushReason
  )
}

private func makeResponse(for request: TutorRequest) -> TutorResponse {
  TutorResponse(
    schemaVersion: TutorResponse.currentSchemaVersion,
    id: UUID(),
    requestID: request.id,
    sessionID: request.sessionID,
    sequence: request.sequence,
    sourceChunkID: request.source.chunkID,
    createdAt: Date(timeIntervalSince1970: 2_001),
    outcome: .lesson(
      TutorLesson(
        title: nil,
        plainExplanation: "这是一个本地测试响应。",
        keyPoints: [],
        glossary: [],
        analogy: nil,
        example: nil,
        checkQuestion: nil,
        caveats: [],
        confidence: .high
      )
    )
  )
}
