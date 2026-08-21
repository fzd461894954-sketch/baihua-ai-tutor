#if DEBUG
import XCTest

@testable import AITutorMac

@MainActor
final class TutorRealDemoTests: XCTestCase {
  func testArkEndpointUsesJSONObjectCompatibilityMode() throws {
    let arkEndpoint = try XCTUnwrap(
      URL(string: "https://ark.cn-beijing.volces.com/api/v3/chat/completions")
    )
    let genericEndpoint = try XCTUnwrap(
      URL(string: "https://provider.example/v1/chat/completions")
    )

    XCTAssertEqual(tutorRealDemoResponseFormat(for: arkEndpoint), .jsonObject)
    XCTAssertEqual(tutorRealDemoResponseFormat(for: genericEndpoint), .jsonSchema)
  }

  func testLiveArkTutorContractWhenExplicitlyConfigured() async throws {
    guard
      let apiKey = ProcessInfo.processInfo.environment["ARK_E2E_API_KEY"],
      !apiKey.isEmpty
    else {
      throw XCTSkip("ARK_E2E_API_KEY is intentionally absent")
    }
    let controller = TutorRealDemoController()
    controller.configuration = DebugLLMConfiguration(
      endpoint: "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
      model: "doubao-seed-evolving",
      apiKey: apiKey
    )
    controller.selectCase(id: "api")

    controller.explain()
    await waitForTerminalState(controller, timeoutNanoseconds: 90_000_000_000)

    let record = try XCTUnwrap(controller.latestRunRecord)
    let quality = try XCTUnwrap(controller.latestQualityReport)
    XCTAssertEqual(controller.state, .succeeded, "failure=\(String(describing: controller.latestFailure))")
    XCTAssertEqual(record.outcome, .success)
    XCTAssertNotNil(controller.latestPresentation)
    print(
      "ARK_E2E_METRICS model=doubao-seed-evolving "
        + "latency_ms=\(record.latencyMilliseconds) "
        + "input_tokens=\(record.inputTokenCount.map(String.init) ?? "unavailable") "
        + "output_tokens=\(record.outputTokenCount.map(String.init) ?? "unavailable") "
        + "outcome=\(record.outcome.rawValue) quality=\(quality.rating.rawValue)"
    )
    controller.shutdown()
  }

  func testValidJSONCompletesClosedLoopAndRecordsPrivacySafeUsage() async throws {
    let fake = FakeLLMProvider(behavior: .success)
    let provider = DecoratedTutorDemoProvider(base: fake, decoration: .usage)
    let controller = makeController(provider: provider)
    let privateSource = "PRIVATE_BODY_API_仅用于本次请求"
    configure(controller, source: privateSource)

    controller.explain()
    await waitForTerminalState(controller)

    XCTAssertEqual(controller.state, .succeeded)
    XCTAssertEqual(controller.latestResponse?.schemaVersion, TutorResponse.currentSchemaVersion)
    XCTAssertEqual(controller.latestPresentation?.outcome, .lesson)
    let record = try XCTUnwrap(controller.latestRunRecord)
    XCTAssertEqual(record.outcome, .success)
    XCTAssertEqual(record.inputTokenCount, 12)
    XCTAssertEqual(record.outputTokenCount, 7)
    XCTAssertEqual(record.totalTokenCount, 19)
    XCTAssertFalse(String(reflecting: record).contains(privateSource))
  }

  func testInvalidJSONIsReportedAsDecodeFailure() async {
    let fake = FakeLLMProvider(behavior: .malformedJSON)
    let provider = DecoratedTutorDemoProvider(base: fake, decoration: .usage)
    let controller = makeController(provider: provider)
    configure(controller)

    controller.explain()
    await waitForTerminalState(controller)

    XCTAssertEqual(controller.state, .failed)
    XCTAssertEqual(controller.latestFailure, .invalidJSON)
    XCTAssertNil(controller.latestResponse)
    XCTAssertEqual(controller.latestRunRecord?.totalTokenCount, 19)
  }

  func testTimeoutIsRecordedWithoutResponseBody() async {
    let controller = makeController(provider: FakeLLMProvider(behavior: .timeout))
    configure(controller)

    controller.explain()
    await waitForTerminalState(controller)

    XCTAssertEqual(controller.state, .failed)
    XCTAssertEqual(controller.latestFailure, .timeout)
    XCTAssertEqual(controller.latestRunRecord?.outcome, .failure)
    XCTAssertNil(controller.latestRunRecord?.totalTokenCount)
  }

  func testCancellationCancelsProviderAndRecordsCancelledRun() async {
    let provider = FakeLLMProvider(
      behavior: .success,
      responseDelayNanoseconds: 5_000_000_000
    )
    let controller = makeController(provider: provider)
    configure(controller)
    controller.explain()
    await waitForGenerateCall(provider)

    controller.cancel()
    await waitForCancelCall(provider)

    XCTAssertEqual(controller.state, .cancelled)
    XCTAssertEqual(controller.latestRunRecord?.outcome, .cancelled)
    XCTAssertNil(controller.latestPresentation)
    let cancelCallCount = await provider.cancelCallCount
    XCTAssertGreaterThanOrEqual(cancelCallCount, 1)
  }

  func testLongValidResponseIsValidatedThenPresentationIsTruncated() async throws {
    let fake = FakeLLMProvider(behavior: .success)
    let provider = DecoratedTutorDemoProvider(base: fake, decoration: .longExplanation)
    let controller = makeController(provider: provider)
    configure(controller)

    controller.explain()
    await waitForTerminalState(controller)

    XCTAssertEqual(controller.state, .succeeded)
    let quality = try XCTUnwrap(controller.latestQualityReport)
    XCTAssertEqual(quality.explanationCharacterCount, 1_500)
    let presentation = try XCTUnwrap(controller.latestPresentation)
    XCTAssertEqual(presentation.plainExplanation.count, 1_200)
    XCTAssertTrue(presentation.didTruncateContent)
  }

  func testChineseExplanationQualitySignalUsesValidatedTutorResponse() async throws {
    let controller = makeController(provider: FakeLLMProvider(behavior: .success))
    configure(controller, source: "API 是什么？")

    controller.explain()
    await waitForTerminalState(controller)

    let quality = try XCTUnwrap(controller.latestQualityReport)
    XCTAssertTrue(quality.containsChineseExplanation)
    XCTAssertGreaterThan(quality.chineseCharacterCount, 4)
  }

  func testAnalogyGenerationQualitySignal() async throws {
    let controller = makeController(provider: FakeLLMProvider(behavior: .success))
    configure(controller, source: "请解释 API")

    controller.explain()
    await waitForTerminalState(controller)

    let quality = try XCTUnwrap(controller.latestQualityReport)
    XCTAssertTrue(quality.hasAnalogy)
    XCTAssertNotNil(controller.latestPresentation?.analogy)
  }

  func testGlossaryGenerationQualitySignal() async throws {
    let controller = makeController(provider: FakeLLMProvider(behavior: .success))
    configure(controller, source: "请解释 API")

    controller.explain()
    await waitForTerminalState(controller)

    let quality = try XCTUnwrap(controller.latestQualityReport)
    XCTAssertGreaterThan(quality.glossaryTermCount, 0)
    XCTAssertFalse(try XCTUnwrap(controller.latestPresentation).terms.isEmpty)
  }

  func testSameDatasetCaseMultipleRunsReuseSemanticChunkIdentity() async throws {
    let provider = FakeLLMProvider(behavior: .success)
    let controller = makeController(provider: provider)
    controller.configuration = DebugLLMConfiguration(
      endpoint: "https://example.test/v1/chat/completions",
      model: "test-model",
      apiKey: "runtime-key"
    )
    controller.selectCase(id: "api")
    let expectedChunkID = try XCTUnwrap(controller.selectedCase?.semanticChunk.id)

    controller.explain()
    await waitForTerminalState(controller)
    let firstChunkID = controller.latestResponse?.sourceChunkID

    controller.explain()
    await waitForTerminalState(controller)
    let secondChunkID = controller.latestResponse?.sourceChunkID
    let generateCallCount = await provider.generateCallCount

    XCTAssertEqual(firstChunkID, expectedChunkID)
    XCTAssertEqual(secondChunkID, expectedChunkID)
    XCTAssertEqual(generateCallCount, 2)
    XCTAssertEqual(controller.runRecords.count, 2)
  }

  func testShutdownClearsRuntimeCredentialsAndTransientBodies() async {
    let controller = makeController(
      provider: FakeLLMProvider(
        behavior: .success,
        responseDelayNanoseconds: 5_000_000_000
      )
    )
    configure(controller)
    controller.explain()

    controller.shutdown()

    XCTAssertEqual(controller.configuration, DebugLLMConfiguration())
    XCTAssertTrue(controller.sourceText.isEmpty)
    XCTAssertTrue(controller.runRecords.isEmpty)
    XCTAssertNil(controller.latestResponse)
    XCTAssertNil(controller.latestPresentation)
    XCTAssertEqual(controller.state, .idle)
  }

  func testDismissPreservesRuntimeConfigurationButClearsTransientBodies() async {
    let controller = makeController(
      provider: FakeLLMProvider(
        behavior: .success,
        responseDelayNanoseconds: 5_000_000_000
      )
    )
    configure(controller)
    let expectedConfiguration = controller.configuration
    controller.explain()

    controller.dismiss()

    XCTAssertEqual(controller.configuration, expectedConfiguration)
    XCTAssertTrue(controller.sourceText.isEmpty)
    XCTAssertTrue(controller.runRecords.isEmpty)
    XCTAssertNil(controller.latestResponse)
    XCTAssertNil(controller.latestPresentation)
    XCTAssertEqual(controller.state, .idle)
  }

  func testResponsesEndpointIsRejectedBeforeProviderCall() {
    let controller = makeController(provider: FakeLLMProvider(behavior: .success))
    controller.configuration = DebugLLMConfiguration(
      endpoint: "https://ark.cn-beijing.volces.com/api/v3/responses",
      model: "test-model",
      apiKey: "runtime-key"
    )
    controller.sourceText = "API 是一组让不同软件互相沟通的约定。"

    controller.explain()

    XCTAssertEqual(controller.state, .failed)
    XCTAssertEqual(controller.latestFailure, .unsupportedEndpoint)
  }

  private func makeController(
    provider: any LLMProvider
  ) -> TutorRealDemoController {
    TutorRealDemoController(providerFactory: { _ in provider })
  }

  private func configure(
    _ controller: TutorRealDemoController,
    source: String = "API 是一组让不同软件互相沟通的约定。"
  ) {
    controller.configuration = DebugLLMConfiguration(
      endpoint: "https://example.test/v1/chat/completions",
      model: "test-model",
      apiKey: "runtime-key"
    )
    controller.sourceText = source
  }

  private func waitForTerminalState(
    _ controller: TutorRealDemoController,
    timeoutNanoseconds: UInt64 = 1_000_000_000
  ) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while controller.state == .running,
          DispatchTime.now().uptimeNanoseconds < deadline
    {
      try? await Task.sleep(nanoseconds: 2_000_000)
    }
    if controller.state == .running {
      XCTFail("Timed out waiting for demo flow")
    }
  }

  private func waitForGenerateCall(_ provider: FakeLLMProvider) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
    while await provider.generateCallCount == 0,
          DispatchTime.now().uptimeNanoseconds < deadline
    {
      try? await Task.sleep(nanoseconds: 2_000_000)
    }
  }

  private func waitForCancelCall(_ provider: FakeLLMProvider) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
    while await provider.cancelCallCount == 0,
          DispatchTime.now().uptimeNanoseconds < deadline
    {
      try? await Task.sleep(nanoseconds: 2_000_000)
    }
  }
}

private actor DecoratedTutorDemoProvider: LLMProvider {
  enum Decoration: Sendable {
    case usage
    case longExplanation
  }

  let base: FakeLLMProvider
  let decoration: Decoration

  init(base: FakeLLMProvider, decoration: Decoration) {
    self.base = base
    self.decoration = decoration
  }

  func generate(from prompt: PromptPackage) async throws -> RawLLMResponse {
    let response = try await base.generate(from: prompt)
    switch decoration {
    case .usage:
      return RawLLMResponse(
        content: response.content,
        finishReason: response.finishReason,
        usage: LLMUsageMetadata(
          inputTokenCount: 12,
          outputTokenCount: 7,
          totalTokenCount: 19
        ),
        providerMetadata: response.providerMetadata
      )
    case .longExplanation:
      return try responseWithLongExplanation(response)
    }
  }

  func stream(
    from prompt: PromptPackage
  ) async -> AsyncThrowingStream<RawLLMStreamChunk, Error> {
    await base.stream(from: prompt)
  }

  func cancel() async {
    await base.cancel()
  }

  private func responseWithLongExplanation(
    _ response: RawLLMResponse
  ) throws -> RawLLMResponse {
    guard
      let data = response.content.data(using: .utf8),
      var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      var outcome = root["outcome"] as? [String: Any],
      var lesson = outcome["lesson"] as? [String: Any]
    else {
      throw LLMProviderError.invalidResponse
    }
    lesson["plainExplanation"] = String(repeating: "中", count: 1_500)
    outcome["lesson"] = lesson
    root["outcome"] = outcome
    let transformed = try JSONSerialization.data(
      withJSONObject: root,
      options: [.sortedKeys]
    )
    guard let content = String(data: transformed, encoding: .utf8) else {
      throw LLMProviderError.invalidResponse
    }
    return RawLLMResponse(
      content: content,
      finishReason: response.finishReason,
      usage: response.usage,
      providerMetadata: response.providerMetadata
    )
  }
}
#endif
