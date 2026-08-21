import XCTest
@testable import AITutorMac

@MainActor
final class TutorRuntimeIntegrationTests: XCTestCase {
  func testCurrentContentReturnsOnlyLatestValidChunkInActiveSession() throws {
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    let first = makeChunk(text: "API 是应用之间的约定。")
    let latest = makeChunk(text: "HTTP 是一种通信协议。", confidence: .low)

    provider.beginSession(sessionID)
    provider.receive(first, sessionID: sessionID)
    provider.receive(latest, sessionID: sessionID)

    XCTAssertEqual(try provider.currentSemanticChunk(), latest)
    XCTAssertTrue(provider.hasStableContent)
  }

  func testCurrentContentRejectsWrongSessionOversizeAndInvalidation() throws {
    let provider = CurrentExplainableContentProvider(maximumCharacterCount: 10)
    let sessionID = UUID()
    provider.beginSession(sessionID)
    provider.receive(makeChunk(text: "wrong"), sessionID: UUID())
    provider.receive(makeChunk(text: String(repeating: "x", count: 11)), sessionID: sessionID)

    XCTAssertThrowsError(try provider.currentSemanticChunk())

    provider.receive(makeChunk(text: "valid"), sessionID: sessionID)
    XCTAssertNoThrow(try provider.currentSemanticChunk())
    provider.invalidateSession(sessionID)
    XCTAssertThrowsError(try provider.currentSemanticChunk())
    XCTAssertFalse(provider.hasStableContent)
  }

#if DEBUG
  func testRealDemoAndPanelRuntimeShareOnlyInMemoryConfiguration() {
    let configurationStore = DebugLLMConfigurationStore()
    let controller = TutorRealDemoController(configurationStore: configurationStore)
    let configuration = DebugLLMConfiguration(
      endpoint: "https://example.invalid/v1/chat/completions",
      model: "debug-model",
      apiKey: "debug-placeholder"
    )

    controller.configuration = configuration

    XCTAssertEqual(configurationStore.validatedConfiguration(), configuration)
    controller.shutdown()
    XCTAssertNil(configurationStore.validatedConfiguration())
  }

  func testPanelRuntimeRejectsResponsesEndpointConfiguration() {
    let configurationStore = DebugLLMConfigurationStore()
    configurationStore.configuration = DebugLLMConfiguration(
      endpoint: "https://ark.cn-beijing.volces.com/api/v3/responses",
      model: "debug-model",
      apiKey: "debug-placeholder"
    )

    XCTAssertNil(configurationStore.validatedConfiguration())
  }

  func testNoContentShowsFriendlyMessageWithoutProviderCall() async {
    let provider = FakeLLMProvider()
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: provider))

    runtime.controller.handle(.explainCurrentContent)
    XCTAssertEqual(runtime.store.state, .loading)
    await settle()

    XCTAssertEqual(runtime.store.state, .error(.noStableContent))
    let callCount = await provider.generateCallCount
    XCTAssertEqual(callCount, 0)
  }

  func testExplainImmediatelyLoadsThenRoutesSuccessfulPresentation() async {
    let provider = FakeLLMProvider(responseDelayNanoseconds: 40_000_000)
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: provider))
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(makeChunk(confidence: .low), sessionID: sessionID)

    runtime.controller.handle(.explainCurrentContent)
    XCTAssertEqual(runtime.store.state, .loading)

    await eventually {
      if case .presentation = runtime.store.state { return true }
      return false
    }
    XCTAssertEqual(runtime.coordinator.latestRequest?.trigger, .userInitiated)
    XCTAssertEqual(runtime.controller.state, .completed)
  }

  func testMissingConfigurationDoesNotCallProvider() async {
    let provider = FakeLLMProvider()
    let runtime = makeRuntime(
      engine: LLMTutorEngine(provider: provider),
      prepareEngine: { false }
    )
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(makeChunk(), sessionID: sessionID)

    runtime.controller.handle(.explainCurrentContent)
    await eventually { runtime.store.state == .error(.modelNotConfigured) }

    let callCount = await provider.generateCallCount
    XCTAssertEqual(callCount, 0)
  }

  func testProviderFailureShowsRetryableError() async {
    let provider = FakeLLMProvider(behavior: .unavailable)
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: provider))
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(makeChunk(), sessionID: sessionID)

    runtime.controller.handle(.explainCurrentContent)
    await eventually { runtime.store.state == .error(.requestFailed) }

    XCTAssertEqual(runtime.controller.state, .failed)
    let callCount = await provider.generateCallCount
    XCTAssertEqual(callCount, 1)
  }

  func testDismissCancelsLoadingWithoutShowingError() async {
    let provider = FakeLLMProvider(responseDelayNanoseconds: 300_000_000)
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: provider))
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(makeChunk(), sessionID: sessionID)
    runtime.controller.handle(.explainCurrentContent)
    await eventually { await provider.generateCallCount == 1 }

    runtime.controller.handle(.dismissCurrentPresentation)
    await settle()

    XCTAssertEqual(runtime.store.state, .empty(availability: .available))
    XCTAssertEqual(runtime.controller.state, .idle)
  }

  func testNewSessionRejectsLateResultAndClearsLoading() async {
    let provider = FakeLLMProvider(responseDelayNanoseconds: 200_000_000)
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: provider))
    let firstSession = UUID()
    runtime.controller.liveSessionDidStart(firstSession)
    runtime.controller.receive(makeChunk(), sessionID: firstSession)
    runtime.controller.handle(.explainCurrentContent)
    await eventually { await provider.generateCallCount == 1 }

    let nextSession = UUID()
    runtime.controller.liveSessionDidStart(nextSession)
    try? await Task.sleep(nanoseconds: 250_000_000)

    XCTAssertEqual(runtime.store.state, .empty(availability: .available))
    XCTAssertNil(runtime.coordinator.latestPresentation)
    XCTAssertEqual(runtime.coordinator.currentSessionID, nextSession)
  }

  func testNewChunkInSameSessionCancelsStaleExplanation() async {
    let provider = FakeLLMProvider(responseDelayNanoseconds: 180_000_000)
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: provider))
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(makeChunk(text: "old content"), sessionID: sessionID)
    runtime.controller.handle(.explainCurrentContent)
    await eventually { await provider.generateCallCount == 1 }

    runtime.controller.receive(makeChunk(text: "new content"), sessionID: sessionID)
    try? await Task.sleep(nanoseconds: 220_000_000)

    XCTAssertEqual(runtime.store.state, .empty(availability: .available))
    XCTAssertNil(runtime.coordinator.latestPresentation)
    XCTAssertEqual(runtime.controller.state, .idle)
  }

  func testDoubleExplainCancelsOldRequestAndStartsNewRequest() async {
    let provider = FakeLLMProvider(responseDelayNanoseconds: 100_000_000)
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: provider))
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(makeChunk(), sessionID: sessionID)

    runtime.controller.handle(.explainCurrentContent)
    await eventually { await provider.generateCallCount == 1 }
    runtime.controller.handle(.explainCurrentContent)
    await eventually { await provider.generateCallCount == 2 }
    await eventually {
      if case .presentation = runtime.store.state { return true }
      return false
    }

    XCTAssertEqual(runtime.coordinator.requestCount, 2)
    let cancelCount = await provider.cancelCallCount
    XCTAssertGreaterThanOrEqual(cancelCount, 1)
  }

  func testStopInvalidatesSessionAndDropsLateResult() async {
    let provider = FakeLLMProvider(responseDelayNanoseconds: 150_000_000)
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: provider))
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(makeChunk(), sessionID: sessionID)
    runtime.controller.handle(.explainCurrentContent)
    await eventually { await provider.generateCallCount == 1 }

    runtime.controller.stop()
    try? await Task.sleep(nanoseconds: 200_000_000)

    XCTAssertNil(runtime.controller.activeSessionID)
    XCTAssertEqual(runtime.coordinator.state, .stopped)
    XCTAssertNil(runtime.coordinator.latestPresentation)
    XCTAssertEqual(runtime.store.state, .empty(availability: .available))
  }

  private func makeRuntime(
    engine: any TutorEngine,
    prepareEngine: @escaping @MainActor @Sendable () async -> Bool = { true }
  ) -> RuntimeFixture {
    let store = TutorPanelContentStore(availability: .available)
    let router = TutorPresentationRouter(contentStore: store)
    let contentProvider = CurrentExplainableContentProvider()
    let coordinator = TutorCoordinator(engine: engine)
    let controller = TutorManualRuntimeController(
      contentProvider: contentProvider,
      coordinator: coordinator,
      router: router,
      contentStore: store,
      prepareEngine: prepareEngine
    )
    return RuntimeFixture(store: store, coordinator: coordinator, controller: controller)
  }
#endif

  private func makeChunk(
    text: String = "JSON 是一种结构化数据格式。",
    confidence: DiffConfidence = .high
  ) -> SemanticChunk {
    SemanticChunk(
      id: UUID(),
      sourceRevisionID: 1,
      text: text,
      confidence: confidence,
      createdAt: Date(),
      flushReason: .idleTimeout
    )
  }

  private func settle() async {
    for _ in 0..<8 { await Task.yield() }
  }

  private func eventually(
    _ predicate: @escaping @MainActor () async -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0..<100 {
      if await predicate() { return }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Condition did not become true", file: file, line: line)
  }
}

#if DEBUG
@MainActor
private struct RuntimeFixture {
  let store: TutorPanelContentStore
  let coordinator: TutorCoordinator
  let controller: TutorManualRuntimeController
}
#endif
