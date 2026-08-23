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

  func testTenChunksReturnLatestHighConfidenceChunkForManualExplain() throws {
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    let start = Date(timeIntervalSince1970: 1_000)
    provider.beginSession(sessionID)

    var latest: SemanticChunk?
    for index in 1...10 {
      let chunk = makeChunk(
        text: "stable chunk \(index)",
        confidence: index == 10 ? .high : .medium,
        revisionID: index,
        createdAt: start.addingTimeInterval(TimeInterval(index))
      )
      XCTAssertEqual(provider.receive(chunk, sessionID: sessionID), .accepted)
      latest = chunk
    }

    XCTAssertEqual(try provider.currentSemanticChunk(), latest)
#if DEBUG
    let diagnostics = provider.diagnosticSnapshot
    XCTAssertEqual(diagnostics.chunksReceived, 10)
    XCTAssertEqual(diagnostics.chunksAccepted, 10)
    XCTAssertEqual(diagnostics.chunksRejected, 0)
    XCTAssertEqual(diagnostics.latestConfidence, .high)
    XCTAssertEqual(diagnostics.latestChunkRevision, 10)
    XCTAssertEqual(diagnostics.lastRetrievalResult, .available)
    XCTAssertTrue(diagnostics.isAvailable)
#endif
  }

  func testSessionReplacementStopAndWrongSessionAreDeterministic() throws {
    let provider = CurrentExplainableContentProvider()
    let sessionA = UUID()
    let sessionB = UUID()
    let chunkA = makeChunk(text: "session A")
    let wrongChunk = makeChunk(text: "late session A")
    let chunkB = makeChunk(text: "session B")

    provider.beginSession(sessionA)
    XCTAssertEqual(provider.receive(chunkA, sessionID: sessionA), .accepted)
    provider.beginSession(sessionB)
    XCTAssertThrowsError(try provider.currentSemanticChunk())
    XCTAssertEqual(
      provider.receive(wrongChunk, sessionID: sessionA),
      .rejected(.wrongSession)
    )
    XCTAssertEqual(provider.receive(chunkB, sessionID: sessionB), .accepted)
    XCTAssertEqual(try provider.currentSemanticChunk(), chunkB)

    provider.invalidateSession(sessionB)
    XCTAssertThrowsError(try provider.currentSemanticChunk())
    XCTAssertEqual(
      provider.receive(chunkB, sessionID: sessionB),
      .rejected(.invalidatedSession)
    )
  }

  func testCurrentSnapshotExcludesBrowserChromeAndKeepsVisibleContent() throws {
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)
    let snapshot = makeSnapshot(
      plainText: "Back\nhttps://chatgpt.\nTransformer 会根据上下文预测下一个 token。",
      nodes: [
        AccessibleTextNode(
          role: "AXButton",
          text: "Back",
          depth: 1,
          sourceAttribute: .title
        ),
        AccessibleTextNode(
          role: "AXTextField",
          text: "https://chatgpt.",
          depth: 2,
          sourceAttribute: .value
        ),
        AccessibleTextNode(
          role: "AXStaticText",
          text: "Transformer 会根据上下文预测下一个 token。",
          depth: 4,
          sourceAttribute: .value
        ),
      ]
    )

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 4, sessionID: sessionID),
      .accepted
    )
    let chunk = try provider.currentSemanticChunk()
    XCTAssertEqual(chunk.text, "Transformer 会根据上下文预测下一个 token。")
    XCTAssertFalse(chunk.text.contains("https://chatgpt."))
    XCTAssertFalse(chunk.text.contains("Back"))
    XCTAssertEqual(chunk.flushReason, .manualFlush)
  }

  func testCurrentSnapshotExcerptRemainsBoundedToTutorLimit() throws {
    let provider = CurrentExplainableContentProvider(maximumCharacterCount: 100)
    let sessionID = UUID()
    provider.beginSession(sessionID)
    let content = String(repeating: "older context line\n", count: 20)
      + "latest visible explanation"
    let snapshot = makeSnapshot(
      plainText: content,
      nodes: [
        AccessibleTextNode(
          role: "AXStaticText",
          text: content,
          depth: 3,
          sourceAttribute: .value
        ),
      ]
    )

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 2, sessionID: sessionID),
      .accepted
    )
    let chunk = try provider.currentSemanticChunk()
    XCTAssertLessThanOrEqual(chunk.text.count, 100)
    XCTAssertTrue(chunk.text.contains("latest visible explanation"))
  }

#if DEBUG
  func testRealDemoConfigurationIsClearedOnShutdown() {
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
    let metrics = runtime.controller.latestLatencyMetrics
    XCTAssertNotNil(metrics?.contentResolvedAt)
    XCTAssertNotNil(metrics?.requestCreatedAt)
    XCTAssertNotNil(metrics?.promptBuiltAt)
    XCTAssertNotNil(metrics?.httpStartedAt)
    XCTAssertNotNil(metrics?.networkCompletedAt)
    XCTAssertNotNil(metrics?.decodedAt)
    XCTAssertNotNil(metrics?.validatedAt)
    XCTAssertNotNil(metrics?.presentationReadyAt)
    XCTAssertNotNil(metrics?.panelPresentedAt)
    XCTAssertNotNil(metrics?.totalTutorLatency)
    XCTAssertNil(metrics?.firstSSEContentAt)
  }

  func testExplainUsesExplicitlyResolvedCurrentContentInsteadOfOldChunk() async {
    let provider = FakeLLMProvider()
    let resolvedChunk = makeChunk(text: "实际页面正文。", revisionID: 7)
    let runtime = makeRuntime(
      engine: LLMTutorEngine(provider: provider),
      resolveCurrentContent: { resolvedChunk }
    )
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(
      makeChunk(text: "https://chatgpt.", revisionID: 6),
      sessionID: sessionID
    )

    runtime.controller.handle(.explainCurrentContent)
    await eventually {
      if case .presentation = runtime.store.state { return true }
      return false
    }

    XCTAssertEqual(runtime.coordinator.latestRequest?.source.text, resolvedChunk.text)
    XCTAssertEqual(runtime.coordinator.latestRequest?.source.sourceRevisionID, 7)
  }

  func testQuestionUsesCurrentScreenContentAndReachesTutorPrompt() async {
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: FakeLLMProvider()))
    let sessionID = UUID()
    let chunk = makeChunk(text: "Transformer 会根据上下文预测下一个 token。")
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(chunk, sessionID: sessionID)

    runtime.controller.askQuestion("这里的 token 是什么意思？")
    await eventually {
      if case .presentation = runtime.store.state { return true }
      return false
    }

    XCTAssertEqual(runtime.coordinator.latestRequest?.source.text, chunk.text)
    XCTAssertEqual(
      runtime.coordinator.latestRequest?.learnerQuestion,
      "这里的 token 是什么意思？"
    )
    XCTAssertTrue(
      runtime.coordinator.latestPromptPackage?.userContent
        .contains("这里的 token 是什么意思？") == true
    )
  }

  func testQuestionWorksWithoutActiveScreenSession() async {
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: FakeLLMProvider()))

    runtime.controller.askQuestion("用生活例子解释一下 API。")
    await eventually {
      if case .presentation = runtime.store.state { return true }
      return false
    }

    XCTAssertNotNil(runtime.controller.activeSessionID)
    XCTAssertEqual(
      runtime.coordinator.latestRequest?.learnerQuestion,
      "用生活例子解释一下 API。"
    )
    XCTAssertEqual(
      runtime.coordinator.latestRequest?.source.text,
      "用生活例子解释一下 API。"
    )
  }

  func testSnapshotResolutionFailureDoesNotSendOldChunk() async {
    let provider = FakeLLMProvider()
    let runtime = makeRuntime(
      engine: LLMTutorEngine(provider: provider),
      resolveCurrentContent: { throw AccessibilityReaderError.readFailed }
    )
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(
      makeChunk(text: "https://chatgpt.", revisionID: 6),
      sessionID: sessionID
    )

    runtime.controller.handle(.explainCurrentContent)
    await eventually { runtime.store.state == .error(.noStableContent) }

    XCTAssertNil(runtime.coordinator.latestRequest)
    let callCount = await provider.generateCallCount
    XCTAssertEqual(callCount, 0)
  }

  func testPanelDismissAndPresentationUpdateDoNotClearCurrentContent() throws {
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: FakeLLMProvider()))
    let sessionID = UUID()
    let chunk = makeChunk()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(chunk, sessionID: sessionID)

    runtime.store.present(TutorPanelPresentationFixtures.apiLesson)
    runtime.controller.handle(.dismissCurrentPresentation)

    XCTAssertEqual(try runtime.contentProvider.currentSemanticChunk(), chunk)
    XCTAssertTrue(runtime.contentProvider.hasStableContent)
  }

  func testCompositionRootRuntimeUsesInjectedCurrentContentProvider() {
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: FakeLLMProvider()))

    XCTAssertTrue(runtime.controller.usesContentProvider(runtime.contentProvider))
    XCTAssertEqual(
      runtime.controller.currentContentDiagnosticSnapshot.providerInstanceIdentity,
      runtime.contentProvider.diagnosticSnapshot.providerInstanceIdentity
    )
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

  func testProviderConfigurationChangeCancelsActiveRequest() async {
    let provider = FakeLLMProvider(responseDelayNanoseconds: 200_000_000)
    let runtime = makeRuntime(engine: LLMTutorEngine(provider: provider))
    let sessionID = UUID()
    runtime.controller.liveSessionDidStart(sessionID)
    runtime.controller.receive(makeChunk(), sessionID: sessionID)
    runtime.controller.handle(.explainCurrentContent)
    await eventually { await provider.generateCallCount == 1 }

    runtime.controller.providerConfigurationDidChange()
    try? await Task.sleep(nanoseconds: 240_000_000)

    XCTAssertEqual(runtime.controller.state, .idle)
    XCTAssertEqual(runtime.store.state, .empty(availability: .available))
    XCTAssertNil(runtime.coordinator.latestPresentation)
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
    prepareEngine: @escaping @MainActor @Sendable () async -> Bool = { true },
    resolveCurrentContent:
      (@MainActor @Sendable () async throws -> SemanticChunk)? = nil
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
      prepareEngine: prepareEngine,
      resolveCurrentContent: resolveCurrentContent
    )
    return RuntimeFixture(
      store: store,
      contentProvider: contentProvider,
      coordinator: coordinator,
      controller: controller
    )
  }
#endif

  private func makeChunk(
    text: String = "JSON 是一种结构化数据格式。",
    confidence: DiffConfidence = .high,
    revisionID: Int = 1,
    createdAt: Date = Date()
  ) -> SemanticChunk {
    SemanticChunk(
      id: UUID(),
      sourceRevisionID: revisionID,
      text: text,
      confidence: confidence,
      createdAt: createdAt,
      flushReason: .idleTimeout
    )
  }

  private func makeSnapshot(
    plainText: String,
    nodes: [AccessibleTextNode]
  ) -> AccessibleTextSnapshot {
    AccessibleTextSnapshot(
      window: AccessibleWindowSnapshot(
        application: AccessibleApplicationSnapshot(
          appName: "Chrome",
          bundleIdentifier: "com.google.Chrome",
          processIdentifier: 200,
          observedAt: Date(),
          source: .accessibility
        ),
        windowTitle: "ChatGPT",
        windowRole: "AXWindow",
        windowSubrole: "AXStandardWindow",
        observedAt: Date(),
        source: .accessibility
      ),
      nodes: nodes,
      plainText: plainText,
      characterCount: plainText.count,
      nodeCount: nodes.count,
      visitedNodeCount: nodes.count + 1,
      roleCounts: [:],
      truncated: false,
      duration: 0.01
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
  let contentProvider: CurrentExplainableContentProvider
  let coordinator: TutorCoordinator
  let controller: TutorManualRuntimeController
}
#endif
