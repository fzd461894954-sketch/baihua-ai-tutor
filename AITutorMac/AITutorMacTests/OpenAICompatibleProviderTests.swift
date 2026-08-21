import XCTest

@testable import AITutorMac

final class OpenAICompatibleProviderTests: XCTestCase {
  override func tearDown() {
    MockOpenAIURLProtocol.reset()
    super.tearDown()
  }

  func testSuccessBuildsChatCompletionRequestAndReturnsRawResponse() async throws {
    let capturedRequest = LockedValue<URLRequest>()
    let capturedBody = LockedValue<Data>()
    MockOpenAIURLProtocol.install { protocolInstance in
      capturedRequest.set(protocolInstance.request)
      if let data = protocolInstance.requestBodyData() {
        capturedBody.set(data)
      }
      protocolInstance.respond(
        statusCode: 200,
        chunks: [Self.successResponseData]
      )
    }
    let provider = makeProvider()

    let response = try await provider.generate(from: prompt)

    XCTAssertEqual(response.content, "{\"answer\":true}")
    XCTAssertEqual(response.finishReason, .stop)
    XCTAssertEqual(response.usage.inputTokenCount, 12)
    XCTAssertEqual(response.usage.outputTokenCount, 7)
    XCTAssertEqual(response.usage.totalTokenCount, 19)
    XCTAssertEqual(response.providerMetadata.providerIdentifier, "openai-compatible")
    XCTAssertEqual(response.providerMetadata.modelIdentifier, "test-model")
    XCTAssertEqual(response.providerMetadata.requestIdentifier, "chatcmpl-test")

    let request = try XCTUnwrap(capturedRequest.get())
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer runtime-key")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

    let body = try requestJSONObject(try XCTUnwrap(capturedBody.get()))
    XCTAssertEqual(body["model"] as? String, "test-model")
    XCTAssertEqual(body["temperature"] as? Double, 0.25)
    XCTAssertEqual(body["max_tokens"] as? Int, 640)
    XCTAssertEqual(body["stream"] as? Bool, false)

    let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[0]["role"] as? String, "system")
    XCTAssertTrue(
      try XCTUnwrap(messages[0]["content"] as? String).contains("Return only JSON")
    )
    XCTAssertEqual(messages[1]["role"] as? String, "user")
    XCTAssertEqual(messages[1]["content"] as? String, prompt.userContent)

    let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
    XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
    let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
    XCTAssertEqual(jsonSchema["name"] as? String, "TutorResponse")
    XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
    XCTAssertNotNil(jsonSchema["schema"] as? [String: Any])
  }

  func testTutorSchemaIsAdaptedToStructuredOutputTransportSubset() async throws {
    let capturedBody = LockedValue<Data>()
    MockOpenAIURLProtocol.install { protocolInstance in
      if let data = protocolInstance.requestBodyData() {
        capturedBody.set(data)
      }
      protocolInstance.respond(
        statusCode: 200,
        chunks: [Self.successResponseData]
      )
    }
    let chunk = SemanticChunk(
      id: UUID(),
      sourceRevisionID: 1,
      text: "请解释 API",
      confidence: .high,
      createdAt: Date(),
      flushReason: .manualFlush
    )
    let request = try TutorRequestFactory().make(
      from: chunk,
      sessionID: UUID(),
      sequence: 1,
      learner: .productDefault(),
      trigger: .userInitiated
    )
    let tutorPrompt = try TutorPromptBuilder().build(from: request)
    XCTAssertTrue(tutorPrompt.outputSchema.contains("\"$schema\""))
    XCTAssertTrue(tutorPrompt.outputSchema.contains("\"oneOf\""))

    _ = try await makeProvider().generate(from: tutorPrompt)

    let body = try requestJSONObject(try XCTUnwrap(capturedBody.get()))
    let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
    let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
    let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
    XCTAssertNil(schema["$schema"])
    let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
    let outcome = try XCTUnwrap(properties["outcome"] as? [String: Any])
    XCTAssertNil(outcome["oneOf"])
    XCTAssertEqual((outcome["anyOf"] as? [Any])?.count, 3)
  }

  func testStreamConvertsSSEEventsToOrderedChunks() async throws {
    let eventData = Data(
      (Self.streamEvent(content: "Hello ", finishReason: nil)
        + Self.streamEvent(content: "world", finishReason: "stop")
        + "data: [DONE]\n\n").utf8
    )
    let splitIndex = eventData.index(eventData.startIndex, offsetBy: 37)
    MockOpenAIURLProtocol.install { protocolInstance in
      protocolInstance.respond(
        statusCode: 200,
        chunks: [
          Data(eventData[..<splitIndex]),
          Data(eventData[splitIndex...]),
        ]
      )
    }
    let provider = makeProvider()
    let stream = await provider.stream(from: prompt)
    var chunks: [RawLLMStreamChunk] = []

    for try await chunk in stream {
      chunks.append(chunk)
    }

    XCTAssertEqual(chunks.map(\.sequence), [0, 1])
    XCTAssertEqual(chunks.map(\.contentDelta), ["Hello ", "world"])
    XCTAssertNil(chunks[0].finishReason)
    XCTAssertEqual(chunks[1].finishReason, .stop)
    XCTAssertEqual(chunks[0].providerMetadata.requestIdentifier, "chatcmpl-stream")
  }

  func testDoneTerminatesStreamWithoutWaitingForConnectionCompletion() async throws {
    let transportStopped = expectation(description: "URLSession task stopped after DONE")
    transportStopped.assertForOverFulfill = false
    MockOpenAIURLProtocol.install(
      stopHandler: { transportStopped.fulfill() }
    ) { protocolInstance in
      protocolInstance.respond(
        statusCode: 200,
        chunks: [Data("data: [DONE]\n\n".utf8)],
        finish: false
      )
    }
    let provider = makeProvider()
    let stream = await provider.stream(from: prompt)
    var count = 0

    for try await _ in stream {
      count += 1
    }

    XCTAssertEqual(count, 0)
    await fulfillment(of: [transportStopped], timeout: 1)
  }

  func testMalformedSSEFailsWithDecodingError() async {
    MockOpenAIURLProtocol.install { protocolInstance in
      protocolInstance.respond(
        statusCode: 200,
        chunks: [Data("data: {not-json}\n\n".utf8)]
      )
    }
    let provider = makeProvider()
    let stream = await provider.stream(from: prompt)

    do {
      for try await _ in stream {}
      XCTFail("Expected malformed SSE to fail")
    } catch let error as LLMProviderError {
      XCTAssertEqual(error, .decodingFailed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testMalformedJSONResponseFailsWithDecodingError() async {
    MockOpenAIURLProtocol.install { protocolInstance in
      protocolInstance.respond(
        statusCode: 200,
        chunks: [Data("{not-json}".utf8)]
      )
    }

    await assertGenerateError(.decodingFailed, provider: makeProvider())
  }

  func testInterruptedSSEWithoutDoneFailsAsInvalidResponse() async {
    MockOpenAIURLProtocol.install { protocolInstance in
      protocolInstance.respond(
        statusCode: 200,
        chunks: [Data(Self.streamEvent(content: "partial", finishReason: nil).utf8)]
      )
    }
    let provider = makeProvider()
    let stream = await provider.stream(from: prompt)

    do {
      for try await _ in stream {}
      XCTFail("Expected interrupted SSE to fail")
    } catch let error as LLMProviderError {
      XCTAssertEqual(error, .invalidResponse)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testUnauthorizedResponseIsUnavailable() async {
    MockOpenAIURLProtocol.install { protocolInstance in
      protocolInstance.respond(
        statusCode: 401,
        chunks: [Data("{\"error\":{\"message\":\"unauthorized\"}}".utf8)]
      )
    }

    await assertGenerateError(.unavailable, provider: makeProvider())
  }

  func testRateLimitResponseIsUnavailable() async {
    MockOpenAIURLProtocol.install { protocolInstance in
      protocolInstance.respond(
        statusCode: 429,
        chunks: [Data("{\"error\":{\"message\":\"rate limited\"}}".utf8)]
      )
    }

    await assertGenerateError(.unavailable, provider: makeProvider())
  }

  func testTimeoutMapsToProviderTimeout() async {
    MockOpenAIURLProtocol.install { protocolInstance in
      protocolInstance.fail(with: URLError(.timedOut))
    }

    await assertGenerateError(.timeout, provider: makeProvider())
  }

  func testNetworkUnavailableMapsToProviderUnavailable() async {
    MockOpenAIURLProtocol.install { protocolInstance in
      protocolInstance.fail(with: URLError(.notConnectedToInternet))
    }

    await assertGenerateError(.unavailable, provider: makeProvider())
  }

  func testTaskCancellationStopsURLSessionTask() async {
    let requestStarted = expectation(description: "Request started")
    let transportStopped = expectation(description: "URLSession task stopped")
    transportStopped.assertForOverFulfill = false
    MockOpenAIURLProtocol.install(
      stopHandler: { transportStopped.fulfill() }
    ) { protocolInstance in
      requestStarted.fulfill()
      protocolInstance.respond(statusCode: 200, chunks: [], finish: false)
    }
    let provider = makeProvider()
    let task = Task {
      try await provider.generate(from: prompt)
    }
    await fulfillment(of: [requestStarted], timeout: 1)

    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch let error as LLMProviderError {
      XCTAssertEqual(error, .cancelled)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await fulfillment(of: [transportStopped], timeout: 1)
  }

  func testStreamConsumerCancellationStopsURLSessionTask() async {
    let requestStarted = expectation(description: "Stream request started")
    let transportStopped = expectation(description: "Stream URLSession task stopped")
    transportStopped.assertForOverFulfill = false
    MockOpenAIURLProtocol.install(
      stopHandler: { transportStopped.fulfill() }
    ) { protocolInstance in
      requestStarted.fulfill()
      protocolInstance.respond(statusCode: 200, chunks: [], finish: false)
    }
    let provider = makeProvider()
    let stream = await provider.stream(from: prompt)
    let consumer = Task {
      for try await _ in stream {}
    }
    await fulfillment(of: [requestStarted], timeout: 1)

    consumer.cancel()

    await fulfillment(of: [transportStopped], timeout: 1)
    _ = await consumer.result
  }

  func testEmptyResponseIsInvalid() async {
    MockOpenAIURLProtocol.install { protocolInstance in
      protocolInstance.respond(statusCode: 200, chunks: [])
    }

    await assertGenerateError(.invalidResponse, provider: makeProvider())
  }

  private func makeProvider() -> OpenAICompatibleProvider {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockOpenAIURLProtocol.self]
    return OpenAICompatibleProvider(
      endpoint: URL(string: "https://example.test/v1/chat/completions")!,
      model: "test-model",
      apiKey: "runtime-key",
      temperature: 0.25,
      maxTokens: 640,
      requestTimeout: 2,
      sessionConfiguration: configuration
    )
  }

  private func requestJSONObject(_ data: Data) throws -> [String: Any] {
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
  }

  private func assertGenerateError(
    _ expected: LLMProviderError,
    provider: OpenAICompatibleProvider
  ) async {
    do {
      _ = try await provider.generate(from: prompt)
      XCTFail("Expected \(expected)")
    } catch let error as LLMProviderError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private static func streamEvent(
    content: String,
    finishReason: String?
  ) -> String {
    let escapedFinishReason = finishReason.map { "\"\($0)\"" } ?? "null"
    return """
    data: {"id":"chatcmpl-stream","object":"chat.completion.chunk","model":"test-model","choices":[{"index":0,"delta":{"content":"\(content)"},"finish_reason":\(escapedFinishReason)}]}


    """
  }

  private var prompt: PromptPackage {
    PromptPackage(
      systemInstruction: "Explain the supplied text.",
      userContent: "{\"source\":{\"text\":\"API\"}}",
      outputSchema: """
      {
        "type": "object",
        "additionalProperties": false,
        "required": ["answer"],
        "properties": { "answer": { "type": "boolean" } }
      }
      """,
      constraints: ["Return only JSON", "Do not reveal hidden reasoning"]
    )
  }

  private static let successResponseData = Data(
    """
    {
      "id": "chatcmpl-test",
      "object": "chat.completion",
      "model": "test-model",
      "system_fingerprint": "fp-test",
      "choices": [
        {
          "index": 0,
          "message": { "role": "assistant", "content": "{\\\"answer\\\":true}" },
          "finish_reason": "stop"
        }
      ],
      "usage": {
        "prompt_tokens": 12,
        "completion_tokens": 7,
        "total_tokens": 19
      }
    }
    """.utf8
  )
}

private final class MockOpenAIURLProtocol: URLProtocol {
  typealias Handler = @Sendable (MockOpenAIURLProtocol) -> Void

  private static let stateLock = NSLock()
  private static var handler: Handler?
  private static var stopHandler: (@Sendable () -> Void)?

  static func install(
    stopHandler: (@Sendable () -> Void)? = nil,
    handler: @escaping Handler
  ) {
    stateLock.lock()
    self.handler = handler
    self.stopHandler = stopHandler
    stateLock.unlock()
  }

  static func reset() {
    stateLock.lock()
    handler = nil
    stopHandler = nil
    stateLock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.stateLock.lock()
    let handler = Self.handler
    Self.stateLock.unlock()
    guard let handler else {
      fail(with: URLError(.unsupportedURL))
      return
    }
    handler(self)
  }

  override func stopLoading() {
    Self.stateLock.lock()
    let stopHandler = Self.stopHandler
    Self.stateLock.unlock()
    stopHandler?()
  }

  func respond(
    statusCode: Int,
    chunks: [Data],
    finish: Bool = true
  ) {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    chunks.forEach { client?.urlProtocol(self, didLoad: $0) }
    if finish {
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  func fail(with error: Error) {
    client?.urlProtocol(self, didFailWithError: error)
  }

  func requestBodyData() -> Data? {
    if let body = request.httpBody {
      return body
    }
    guard let stream = request.httpBodyStream else {
      return nil
    }

    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else {
        break
      }
      data.append(buffer, count: count)
    }
    return data
  }
}

private final class LockedValue<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value?

  func set(_ value: Value) {
    lock.lock()
    self.value = value
    lock.unlock()
  }

  func get() -> Value? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}
