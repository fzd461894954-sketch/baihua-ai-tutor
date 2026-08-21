import XCTest

@testable import AITutorMac

#if DEBUG
final class LLMProviderContractTests: XCTestCase {
  func testProviderSuccessReturnsRawResponseBeforeDecoding() async throws {
    let request = makeRequest()
    let prompt = try TutorPromptBuilder().build(from: request)
    let provider = FakeLLMProvider(
      now: { responseDate },
      makeID: { responseID }
    )

    let rawResponse = try await provider.generate(from: prompt)

    XCTAssertFalse(rawResponse.content.isEmpty)
    XCTAssertEqual(rawResponse.finishReason, .stop)
    XCTAssertEqual(rawResponse.usage, .unavailable)
    XCTAssertEqual(rawResponse.providerMetadata.providerIdentifier, "fake.local")
    XCTAssertEqual(rawResponse.providerMetadata.modelIdentifier, "fake-deterministic")

    let decoded = try TutorResponseDecoder().decode(rawResponse)
    let validated = try TutorResponseValidator().validate(decoded, for: request)
    XCTAssertEqual(validated.id, responseID)
    XCTAssertEqual(validated.requestID, request.id)
    XCTAssertEqual(validated.sessionID, request.sessionID)
    XCTAssertEqual(validated.sourceChunkID, request.source.chunkID)
  }

  func testStreamYieldsOrderedChunksAndFinalMetadata() async throws {
    let provider = FakeLLMProvider(
      streamChunks: ["第一段", "第二段", "第三段"]
    )
    let prompt = try makePrompt()
    let stream = await provider.stream(from: prompt)
    var received: [RawLLMStreamChunk] = []

    for try await chunk in stream {
      received.append(chunk)
    }

    XCTAssertEqual(received.map(\.sequence), [0, 1, 2])
    XCTAssertEqual(received.map(\.contentDelta), ["第一段", "第二段", "第三段"])
    XCTAssertEqual(received[0].finishReason, nil)
    XCTAssertEqual(received[1].finishReason, nil)
    XCTAssertEqual(received[2].finishReason, .stop)
    XCTAssertNil(received[0].usage)
    XCTAssertEqual(received[2].usage, .unavailable)
  }

  func testCancellingEngineCancelsActiveProviderGeneration() async throws {
    let request = makeRequest()
    let prompt = try TutorPromptBuilder().build(from: request)
    let provider = FakeLLMProvider(responseDelayNanoseconds: 5_000_000_000)
    let engine = LLMTutorEngine(provider: provider)
    let task = Task {
      try await engine.respond(to: request, prompt: prompt)
    }

    await assertEventually("Provider generation did not start") {
      await provider.generateCallCount == 1
    }
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch let error as LLMProviderError {
      XCTAssertEqual(error, .cancelled)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await assertEventually("Provider cancel was not invoked") {
      await provider.cancelCallCount == 1
    }
  }

  func testCancelEndsActiveStreamWithCancelledError() async throws {
    let provider = FakeLLMProvider(
      streamDelayNanoseconds: 5_000_000_000,
      streamChunks: ["不会完成的分块"]
    )
    let prompt = try makePrompt()
    let stream = await provider.stream(from: prompt)
    let consumer = Task {
      for try await _ in stream {}
    }

    await provider.cancel()

    do {
      try await consumer.value
      XCTFail("Expected stream cancellation")
    } catch let error as LLMProviderError {
      XCTAssertEqual(error, .cancelled)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testProviderTimeoutIsDistinct() async throws {
    let provider = FakeLLMProvider(behavior: .timeout)

    do {
      _ = try await provider.generate(from: makePrompt())
      XCTFail("Expected timeout")
    } catch let error as LLMProviderError {
      XCTAssertEqual(error, .timeout)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testMalformedJSONProducesDecodingFailure() async throws {
    let rawResponse = try await FakeLLMProvider(
      behavior: .malformedJSON
    ).generate(from: makePrompt())

    XCTAssertThrowsError(try TutorResponseDecoder().decode(rawResponse)) { error in
      XCTAssertEqual(error as? LLMProviderError, .decodingFailed)
    }
  }

  func testValidJSONOutsideTutorSchemaIsInvalidResponse() {
    let rawResponse = RawLLMResponse(
      content: "{\"schemaVersion\":1}",
      finishReason: .stop,
      usage: .unavailable,
      providerMetadata: testMetadata
    )

    XCTAssertThrowsError(try TutorResponseDecoder().decode(rawResponse)) { error in
      XCTAssertEqual(error as? LLMProviderError, .invalidResponse)
    }
  }

  func testUnsupportedResponseSchemaVersionIsInvalidResponse() async throws {
    let rawResponse = try await FakeLLMProvider().generate(from: makePrompt())
    let unsupported = try replacingRootValue(
      in: rawResponse,
      key: "schemaVersion",
      value: TutorResponse.currentSchemaVersion + 1
    )

    XCTAssertThrowsError(try TutorResponseDecoder().decode(unsupported)) { error in
      XCTAssertEqual(error as? LLMProviderError, .invalidResponse)
    }
  }

  func testValidatorFailureOccursAfterSuccessfulDecode() async throws {
    let request = makeRequest()
    let prompt = try TutorPromptBuilder().build(from: request)
    let rawResponse = try await FakeLLMProvider().generate(from: prompt)
    let mismatchedRawResponse = try replacingRootValue(
      in: rawResponse,
      key: "requestID",
      value: UUID().uuidString
    )

    let decoded = try TutorResponseDecoder().decode(mismatchedRawResponse)
    XCTAssertThrowsError(
      try TutorResponseValidator().validate(decoded, for: request)
    ) { error in
      XCTAssertEqual(
        error as? TutorEngineError,
        .invalidResponse([.requestIDMismatch])
      )
    }
  }

  func testOutOfOrderRawResponsesRemainCorrelated() async throws {
    let firstRequest = makeRequest(
      requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000811")!,
      sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000812")!,
      chunkID: UUID(uuidString: "00000000-0000-0000-0000-000000000813")!,
      sequence: 1
    )
    let secondRequest = makeRequest(
      requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000821")!,
      sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000812")!,
      chunkID: UUID(uuidString: "00000000-0000-0000-0000-000000000823")!,
      sequence: 2
    )
    let firstPrompt = try TutorPromptBuilder().build(from: firstRequest)
    let secondPrompt = try TutorPromptBuilder().build(from: secondRequest)
    let firstRaw = try await FakeLLMProvider().generate(from: firstPrompt)
    let secondRaw = try await FakeLLMProvider().generate(from: secondPrompt)
    let provider = ControlledRawLLMProvider()
    let engine = LLMTutorEngine(provider: provider)

    let firstTask = Task {
      try await engine.respond(to: firstRequest, prompt: firstPrompt)
    }
    await assertEventually("First provider call was not captured") {
      await provider.callCount == 1
    }
    let secondTask = Task {
      try await engine.respond(to: secondRequest, prompt: secondPrompt)
    }
    await assertEventually("Second provider call was not captured") {
      await provider.callCount == 2
    }

    await provider.complete(call: 1, with: secondRaw)
    let secondResponse = try await secondTask.value
    await provider.complete(call: 0, with: firstRaw)
    let firstResponse = try await firstTask.value

    XCTAssertEqual(secondResponse.requestID, secondRequest.id)
    XCTAssertEqual(secondResponse.sequence, 2)
    XCTAssertEqual(firstResponse.requestID, firstRequest.id)
    XCTAssertEqual(firstResponse.sequence, 1)
  }

  private func makePrompt() throws -> PromptPackage {
    try TutorPromptBuilder().build(from: makeRequest())
  }

  private func makeRequest(
    requestID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
    sessionID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000802")!,
    chunkID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000803")!,
    sequence: Int = 1
  ) -> TutorRequest {
    TutorRequest(
      schemaVersion: TutorRequest.currentSchemaVersion,
      id: requestID,
      sessionID: sessionID,
      sequence: sequence,
      createdAt: Date(timeIntervalSince1970: 4_000),
      task: .explainInPlainLanguage,
      trigger: .automatic,
      source: TutorSourceSnapshot(
        chunkID: chunkID,
        sourceRevisionID: sequence,
        text: "API 是程序之间的约定。",
        diffConfidence: .high,
        flushReason: .sentenceComplete,
        chunkCreatedAt: Date(timeIntervalSince1970: 3_900)
      ),
      learner: .productDefault(at: Date(timeIntervalSince1970: 3_800)),
      output: .default(),
      policyVersion: TutorRequestFactory.defaultPolicyVersion
    )
  }

  private func replacingRootValue(
    in response: RawLLMResponse,
    key: String,
    value: Any
  ) throws -> RawLLMResponse {
    let data = try XCTUnwrap(response.content.data(using: .utf8))
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    object[key] = value
    let changedData = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys]
    )
    return RawLLMResponse(
      content: try XCTUnwrap(String(data: changedData, encoding: .utf8)),
      finishReason: response.finishReason,
      usage: response.usage,
      providerMetadata: response.providerMetadata
    )
  }

  private func assertEventually(
    _ message: String,
    condition: @escaping () async -> Bool
  ) async {
    for _ in 0..<400 {
      if await condition() {
        return
      }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail(message)
  }
}

private actor ControlledRawLLMProvider: LLMProvider {
  typealias Continuation = CheckedContinuation<
    Result<RawLLMResponse, LLMProviderError>,
    Never
  >

  private var continuations: [Continuation] = []

  var callCount: Int {
    continuations.count
  }

  func generate(from prompt: PromptPackage) async throws -> RawLLMResponse {
    let result = await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
    return try result.get()
  }

  func stream(
    from prompt: PromptPackage
  ) async -> AsyncThrowingStream<RawLLMStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }

  func cancel() async {}

  func complete(call index: Int, with response: RawLLMResponse) {
    guard continuations.indices.contains(index) else {
      return
    }
    continuations[index].resume(returning: .success(response))
  }
}

private let responseDate = Date(timeIntervalSince1970: 4_100)
private let responseID = UUID(
  uuidString: "00000000-0000-0000-0000-000000000804"
)!
private let testMetadata = LLMProviderMetadata(
  providerIdentifier: "test.local",
  modelIdentifier: nil,
  requestIdentifier: nil,
  values: [:]
)
#endif
