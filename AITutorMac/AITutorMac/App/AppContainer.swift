import AppKit

@MainActor
final class AppContainer {
  let panelController: FloatingPanelController
  let tutorPanelContentStore: TutorPanelContentStore
  let tutorPresentationRouter: TutorPresentationRouter
  let tutorPetNotificationCenter: TutorPetNotificationCenter
  let petStateController: PetStateController
  let petWindowController: PetWindowController
  let petLibrary: PetLibrary
  let petLibraryWindowController: PetLibraryWindowController
  let voiceController: VoiceController
  let tutorVoiceCoordinator: TutorVoiceCoordinator
  let speechInputController: SpeechInputController
  let voiceSettingsWindowController: VoiceSettingsWindowController
  let contextState: ContextState
  let activeApplicationMonitor: ActiveApplicationMonitor
  let accessibilitySnapshotController: AccessibilitySnapshotController
  let contextRevisionPipeline: ContextRevisionPipeline
  let semanticBuffer: SemanticBuffer
  let accessibilityLiveMonitor: AccessibilityLiveMonitor
  let accessibilityDebugWindowController: AccessibilityDebugWindowController
  let llmProviderSettingsStore: LLMProviderSettingsStore
  let credentialStore: KeychainCredentialStore
  let tutorProviderFactory: TutorProviderFactory
  let aiModelSettingsController: AIModelSettingsController
  let aiModelSettingsWindowController: AIModelSettingsWindowController
  let tutorPanelCoordinator: TutorCoordinator
  let currentExplainableContentProvider: CurrentExplainableContentProvider
  let tutorManualRuntimeController: TutorManualRuntimeController
#if DEBUG
  let tutorCoordinator: TutorCoordinator
  let tutorDebugTraceStore: TutorDebugTraceStore
  let tutorDebugWindowController: TutorDebugWindowController
  let debugLLMConfigurationStore: DebugLLMConfigurationStore
  let tutorLatencyBenchmarkController: TutorLatencyBenchmarkController
  let tutorStreamModelBenchmarkController: TutorStreamModelBenchmarkController
  let realtimeVoiceCoordinator: DoubaoRealtimeVoiceCoordinator
  let realtimeVoiceSpikeWindowController: RealtimeVoiceSpikeWindowController
  private let realtimeVoiceLifecycleMonitor: RealtimeVoiceLifecycleMonitor
#endif

  private let appState: AppState
  private let hotKeyManager: HotKeyManager
#if DEBUG
  private var petStateStressTask: Task<Void, Never>?
  private var voiceStressTask: Task<Void, Never>?
  private var debugAutoExitTask: Task<Void, Never>?
  private var tutorAXConsoleCaptureTask: Task<Void, Never>?
#endif

  init(appState: AppState, contextState: ContextState) {
    self.appState = appState
    self.contextState = contextState
    let activeApplicationMonitor = ActiveApplicationMonitor(contextState: contextState)
    self.activeApplicationMonitor = activeApplicationMonitor
    let accessibilitySnapshotController = AccessibilitySnapshotController(
      contextState: contextState
    )
    self.accessibilitySnapshotController = accessibilitySnapshotController
    let contextRevisionPipeline = ContextRevisionPipeline()
    self.contextRevisionPipeline = contextRevisionPipeline
    let semanticBuffer = SemanticBuffer()
    self.semanticBuffer = semanticBuffer
    let accessibilityLiveMonitor = AccessibilityLiveMonitor(
      contextState: contextState,
      authorizationController: accessibilitySnapshotController.authorizationController,
      snapshotRequester: accessibilitySnapshotController,
      revisionPipeline: contextRevisionPipeline,
      semanticBuffer: semanticBuffer
    )
    self.accessibilityLiveMonitor = accessibilityLiveMonitor
    let accessibilityDebugWindowController = AccessibilityDebugWindowController(
      snapshotController: accessibilitySnapshotController,
      liveMonitor: accessibilityLiveMonitor
    )
    self.accessibilityDebugWindowController = accessibilityDebugWindowController
    let llmProviderSettingsStore = LLMProviderSettingsStore()
    self.llmProviderSettingsStore = llmProviderSettingsStore
    let credentialStore = KeychainCredentialStore()
    self.credentialStore = credentialStore
    let tutorProviderFactory = TutorProviderFactory(
      settingsStore: llmProviderSettingsStore,
      credentialStore: credentialStore
    )
    self.tutorProviderFactory = tutorProviderFactory
    let connectionTester = TutorProviderConnectionTester(
      providerFactory: tutorProviderFactory
    )
    let aiModelSettingsController = AIModelSettingsController(
      settingsStore: llmProviderSettingsStore,
      credentialStore: credentialStore,
      connectionTester: connectionTester
    )
    self.aiModelSettingsController = aiModelSettingsController
    let aiModelSettingsWindowController = AIModelSettingsWindowController(
      controller: aiModelSettingsController
    )
    self.aiModelSettingsWindowController = aiModelSettingsWindowController
#if DEBUG
    let tutorDebugTraceStore = TutorDebugTraceStore()
    self.tutorDebugTraceStore = tutorDebugTraceStore
    let tutorCoordinator = TutorCoordinator(
      engine: LLMTutorEngine(provider: FakeLLMProvider())
    )
    self.tutorCoordinator = tutorCoordinator
    let debugLLMConfigurationStore = DebugLLMConfigurationStore()
    self.debugLLMConfigurationStore = debugLLMConfigurationStore
    let realDemoController = TutorRealDemoController(
      configurationStore: debugLLMConfigurationStore
    )
    let tutorLatencyBenchmarkController = TutorLatencyBenchmarkController(
      providerFactory: tutorProviderFactory
    )
    self.tutorLatencyBenchmarkController = tutorLatencyBenchmarkController
    let tutorStreamModelBenchmarkController = TutorStreamModelBenchmarkController(
      providerFactory: tutorProviderFactory
    )
    self.tutorStreamModelBenchmarkController = tutorStreamModelBenchmarkController
    let tutorDebugWindowController = TutorDebugWindowController(
      coordinator: tutorCoordinator,
      traceStore: tutorDebugTraceStore,
      realDemoController: realDemoController,
      latencyBenchmarkController: tutorLatencyBenchmarkController,
      streamModelBenchmarkController: tutorStreamModelBenchmarkController
    )
    self.tutorDebugWindowController = tutorDebugWindowController

    let realtimeBootstrapProvider = MockRealtimeVoiceBootstrapProvider()
    let realtimeRTCClient = MockVolcRTCClientAdapter()
    let realtimeSession = DoubaoRTCSession(
      bootstrapProvider: realtimeBootstrapProvider,
      commandProvider: realtimeBootstrapProvider,
      rtcClient: realtimeRTCClient,
      maximumSessionDuration: 3 * 60
    )
    let realtimeVoiceCoordinator = DoubaoRealtimeVoiceCoordinator(session: realtimeSession)
    self.realtimeVoiceCoordinator = realtimeVoiceCoordinator
    realtimeVoiceSpikeWindowController = RealtimeVoiceSpikeWindowController(
      coordinator: realtimeVoiceCoordinator
    )
    realtimeVoiceLifecycleMonitor = RealtimeVoiceLifecycleMonitor(
      coordinator: realtimeVoiceCoordinator
    )
#endif
    activeApplicationMonitor.onLastExternalApplicationChange = {
      [weak accessibilitySnapshotController, weak accessibilityLiveMonitor] application in
      accessibilitySnapshotController?.targetApplicationDidChange()
      accessibilityLiveMonitor?.lastExternalApplicationDidChange(application)
    }
    activeApplicationMonitor.onApplicationTermination = { [weak accessibilityLiveMonitor] application in
      accessibilityLiveMonitor?.targetApplicationDidTerminate(application)
    }
    let initialTutorAvailability: TutorPanelActionAvailability = tutorProviderFactory.isAvailable()
      ? .available
      : .unavailable(message: "还没有配置教学模型。")
    let tutorPanelContentStore = TutorPanelContentStore(
      availability: initialTutorAvailability
    )
    let tutorPetNotificationCenter = TutorPetNotificationCenter(
      autoDismissDuration: PetConfiguration.default.tutorBubbleDuration
    )
    let tutorPresentationRouter = TutorPresentationRouter(
      contentStore: tutorPanelContentStore,
      petNotificationSink: tutorPetNotificationCenter,
      isPanelVisible: { appState.isTutorVisible }
    )
    let currentContentProvider = CurrentExplainableContentProvider()
    self.currentExplainableContentProvider = currentContentProvider
    let usesTutorAXConsoleCaptureProvider: Bool
    let tutorAXConsoleCaptureTarget: ActiveApplicationSnapshot?
    let tutorPanelCoordinator: TutorCoordinator
#if DEBUG
    usesTutorAXConsoleCaptureProvider = ProcessInfo.processInfo.arguments.contains(
      "--tutor-ax-console-capture"
    )
    let targetBundlePrefix = "--tutor-ax-console-target-bundle="
    tutorAXConsoleCaptureTarget = ProcessInfo.processInfo.arguments
      .first(where: { $0.hasPrefix(targetBundlePrefix) })
      .map { String($0.dropFirst(targetBundlePrefix.count)) }
      .flatMap { bundleIdentifier in
        NSRunningApplication.runningApplications(
          withBundleIdentifier: bundleIdentifier
        ).first(where: { !$0.isTerminated })
      }
      .map { application in
        ActiveApplicationSnapshot(
          localizedName: application.localizedName,
          bundleIdentifier: application.bundleIdentifier,
          processIdentifier: application.processIdentifier,
          observedAt: Date()
        )
      }
    if usesTutorAXConsoleCaptureProvider {
      let provider = OpenAICompatibleProvider(
        endpoint: URL(string: "http://127.0.0.1:1/chat/completions")!,
        model: "debug-request-assembly",
        apiKey: "debug-non-secret-placeholder",
        responseFormat: .jsonObject,
        requestTimeout: 0.25
      )
      tutorPanelCoordinator = TutorCoordinator(
        engine: LLMTutorEngine(provider: provider)
      )
    } else {
      tutorPanelCoordinator = TutorCoordinator(
        engine: ProductionTutorEngine(providerFactory: tutorProviderFactory)
      )
    }
#else
    usesTutorAXConsoleCaptureProvider = false
    tutorAXConsoleCaptureTarget = nil
    tutorPanelCoordinator = TutorCoordinator(
      engine: ProductionTutorEngine(providerFactory: tutorProviderFactory)
    )
#endif
    self.tutorPanelCoordinator = tutorPanelCoordinator
#if DEBUG
    tutorPanelCoordinator.debugConversationModeProvider = { [weak tutorDebugTraceStore] in
      tutorDebugTraceStore?.currentTurnOnly == true
        ? .currentTurnOnly
        : .normalContext
    }
    tutorPanelCoordinator.onDebugRequestStarted = {
      [weak tutorDebugTraceStore] request, prompt, _ in
      tutorDebugTraceStore?.recordRequest(request, prompt: prompt)
    }
    tutorPanelCoordinator.onDebugRequestFinished = {
      [weak tutorDebugTraceStore] requestID, metrics, exchange in
      tutorDebugTraceStore?.recordCompletion(
        requestID: requestID,
        metrics: metrics,
        exchange: exchange
      )
    }
#endif
    let tutorManualRuntimeController = TutorManualRuntimeController(
      contentProvider: currentContentProvider,
      coordinator: tutorPanelCoordinator,
      router: tutorPresentationRouter,
      contentStore: tutorPanelContentStore,
      prepareEngine: { [weak tutorProviderFactory] in
        usesTutorAXConsoleCaptureProvider || tutorProviderFactory?.isAvailable() == true
      },
      resolveCurrentContent: {
        [weak accessibilitySnapshotController, weak contextState,
         weak currentContentProvider] in
        guard
          let accessibilitySnapshotController,
          let contextState,
          let currentContentProvider
        else {
          throw CurrentExplainableContentError.noStableContent
        }
        guard let target = tutorAXConsoleCaptureTarget
          ?? contextState.lastExternalApplication else {
          AppLogger.accessibility.error(
            "Explicit Tutor snapshot failed error=noLastExternalApplication"
          )
          throw CurrentExplainableContentError.noStableContent
        }
        guard let sessionID = currentContentProvider.activeSessionID else {
          AppLogger.accessibility.error(
            "Explicit Tutor snapshot failed error=noActiveTutorSession"
          )
          throw CurrentExplainableContentError.noStableContent
        }

        let snapshot = try await accessibilitySnapshotController.resolveSnapshot(
          target: target
        )
        let result = currentContentProvider.receiveCurrentSnapshot(
          snapshot,
          revisionID: 0,
          sessionID: sessionID
        )
        if result == .rejected(.ambiguousContent) {
#if DEBUG
          if let selection = currentContentProvider.latestContentSelection {
            tutorDebugTraceStore.recordBlockedManualSnapshot(
              snapshot,
              selection: selection,
              revisionID: 0
            )
          }
#endif
          throw CurrentExplainableContentError.ambiguousContent
        }
        guard result == .accepted else {
          throw AccessibilityReaderError.readFailed
        }
        let chunk = try currentContentProvider.currentSemanticChunk()
#if DEBUG
        tutorDebugTraceStore.recordManualSnapshot(
          snapshot,
          selection: currentContentProvider.latestContentSelection,
          chunk: chunk
        )
#endif
        return chunk
      }
    )
    self.tutorManualRuntimeController = tutorManualRuntimeController

    let petStateController = PetStateController()
    self.petStateController = petStateController
    let voiceController = VoiceController(
      petStateController: petStateController,
      synthesizer: HybridSpeechSynthesizer()
    )
    self.voiceController = voiceController
    let speechInputController = SpeechInputController(
      authorizationController: SpeechAuthorizationController(),
      recognizerFactory: SystemSpeechRecognizerFactory(),
      voiceOutputController: voiceController
    )
    self.speechInputController = speechInputController
    voiceController.onWillSpeak = { [weak speechInputController] in
      if speechInputController?.isInteractionActive == true {
        speechInputController?.cancel()
      }
    }
    let tutorVoiceCoordinator = TutorVoiceCoordinator(voiceController: voiceController)
    self.tutorVoiceCoordinator = tutorVoiceCoordinator
    tutorPanelContentStore.onPresentationIDChange = { [weak tutorVoiceCoordinator] responseID in
      tutorVoiceCoordinator?.presentationDidChange(to: responseID)
    }

    let tutorPanelActionHandler: TutorPanelActionHandler
#if DEBUG
    let fixtureController = TutorPanelDebugFixtureController(
      contentStore: tutorPanelContentStore
    )
    tutorPanelActionHandler = TutorPanelActionHandler {
      [fixtureController, weak tutorManualRuntimeController, weak aiModelSettingsWindowController,
       weak accessibilitySnapshotController, weak tutorVoiceCoordinator]
      intent in
      switch intent {
      case .showDebugFixture:
        fixtureController.handle(intent)
      case .openModelSettings:
        aiModelSettingsWindowController?.show()
      case .openAccessibilitySettings:
        accessibilitySnapshotController?.authorizationController.openSystemSettings()
      case let .playTutorVoice(presentation):
        tutorVoiceCoordinator?.play(presentation)
      case .stopTutorVoice:
        tutorVoiceCoordinator?.stop()
      default:
        tutorManualRuntimeController?.handle(intent)
      }
    }
#else
    tutorPanelActionHandler = TutorPanelActionHandler {
      [weak tutorManualRuntimeController, weak aiModelSettingsWindowController,
       weak accessibilitySnapshotController, weak tutorVoiceCoordinator]
      intent in
      switch intent {
      case .openModelSettings:
        aiModelSettingsWindowController?.show()
      case .openAccessibilitySettings:
        accessibilitySnapshotController?.authorizationController.openSystemSettings()
      case let .playTutorVoice(presentation):
        tutorVoiceCoordinator?.play(presentation)
      case .stopTutorVoice:
        tutorVoiceCoordinator?.stop()
      default:
        tutorManualRuntimeController?.handle(intent)
      }
    }
#endif
    accessibilityLiveMonitor.onLiveSessionChange = { [weak tutorManualRuntimeController] sessionID in
      if let sessionID {
        AppLogger.tutorRuntime.info(
          "Live session bridge started session=\(sessionID.uuidString, privacy: .public)"
        )
        tutorManualRuntimeController?.liveSessionDidStart(sessionID)
      } else {
        AppLogger.tutorRuntime.info("Live session bridge ended")
        tutorManualRuntimeController?.liveSessionDidEnd()
      }
    }
#if DEBUG
    contextRevisionPipeline.onDebugSnapshot = { [weak tutorDebugTraceStore] snapshot in
      tutorDebugTraceStore?.recordPipeline(snapshot)
    }
    semanticBuffer.onDebugEvent = { [weak tutorDebugTraceStore] event in
      tutorDebugTraceStore?.recordBuffer(event)
    }
#endif
    semanticBuffer.onChunk = { [weak tutorManualRuntimeController] chunk in
      guard let sessionID = tutorManualRuntimeController?.activeSessionID else {
        AppLogger.tutorRuntime.notice(
          "Provider bridge received chunk id=\(chunk.id.uuidString, privacy: .public) revision=\(chunk.sourceRevisionID, privacy: .public) characters=\(chunk.text.count, privacy: .public) result=noActiveSession"
        )
        return
      }
      AppLogger.tutorRuntime.debug(
        "Provider bridge received chunk id=\(chunk.id.uuidString, privacy: .public) session=\(sessionID.uuidString, privacy: .public) revision=\(chunk.sourceRevisionID, privacy: .public) confidence=\(chunk.confidence.rawValue, privacy: .public) flush=\(chunk.flushReason.rawValue, privacy: .public) characters=\(chunk.text.count, privacy: .public)"
      )
      _ = tutorManualRuntimeController?.receive(chunk, sessionID: sessionID)
    }
    aiModelSettingsController.onConfigurationDidChange = {
      [weak tutorManualRuntimeController, weak tutorPanelContentStore, weak tutorProviderFactory] in
      tutorManualRuntimeController?.providerConfigurationDidChange()
      let availability: TutorPanelActionAvailability = tutorProviderFactory?.isAvailable() == true
        ? .available
        : .unavailable(message: "还没有配置教学模型。")
      tutorPanelContentStore?.setAvailability(availability)
    }
    self.tutorPanelContentStore = tutorPanelContentStore
    self.tutorPresentationRouter = tutorPresentationRouter
    self.tutorPetNotificationCenter = tutorPetNotificationCenter
    let panelController = FloatingPanelController(
      appState: appState,
      contentStore: tutorPanelContentStore,
      actionHandler: tutorPanelActionHandler,
      tutorVoiceCoordinator: tutorVoiceCoordinator,
      onVisibilityChange: { [weak tutorPetNotificationCenter] isVisible in
        if isVisible {
          tutorPetNotificationCenter?.panelDidBecomeVisible()
        }
      }
    )
    let libraryStore = PetLibraryStore()
    let imageValidator = PetImageValidator()
    let petLibrary = PetLibrary(store: libraryStore, validator: imageValidator)
    let petImporter = PetImporter(validator: imageValidator, store: libraryStore)
    self.panelController = panelController
    self.petLibrary = petLibrary

    let petWindowController = PetWindowController(
      appState: appState,
      pet: petLibrary.currentPet,
      petImage: petLibrary.image(for: petLibrary.currentPet),
      stateController: petStateController,
      speechInputController: speechInputController,
      tutorNotificationCenter: tutorPetNotificationCenter,
      tutorContentStore: tutorPanelContentStore,
      tutorActionHandler: tutorPanelActionHandler,
      tutorVoiceCoordinator: tutorVoiceCoordinator,
      onAskQuestion: { [weak tutorManualRuntimeController] question in
        tutorManualRuntimeController?.askQuestion(question)
      },
      onScaleChange: { [weak petLibrary] id, scale in
        petLibrary?.updateScale(for: id, scale: scale)
      }
    ) { [weak panelController] in
      panelController?.show()
    }
    self.petWindowController = petWindowController
    tutorPetNotificationCenter.onOpenTutor = { [weak petWindowController] in
      petWindowController?.showCompanion()
    }
    petLibraryWindowController = PetLibraryWindowController(
      library: petLibrary,
      importer: petImporter
    )
    voiceSettingsWindowController = VoiceSettingsWindowController(
      voiceController: voiceController,
      speechInputController: speechInputController
    )
    petLibrary.onCurrentPetChange = { [weak petWindowController] pet, image in
      petWindowController?.reloadPet(pet, image: image)
    }
    hotKeyManager = HotKeyManager()
  }

  func start() {
    accessibilitySnapshotController.refreshPermissionState()
    activeApplicationMonitor.start()
    panelController.create()
    petWindowController.start()
    voiceController.prepareLocalService()

    let registered = hotKeyManager.registerOptionSpace { [weak self] in
      AppLogger.hotKey.info("Global shortcut triggered")
      self?.panelController.toggle()
    }

    if !registered {
      appState.shellStatus = .hotKeyUnavailable
    }

    tutorPanelCoordinator.start()
#if DEBUG
    tutorCoordinator.start()
    realtimeVoiceLifecycleMonitor.start()
    startTutorAXConsoleCaptureIfRequested()
    applyPetStateDebugArgumentIfRequested()
    startPetStateStressTestIfRequested()
    applyVoiceDebugArgumentIfRequested()
    startVoiceStressTestIfRequested()
    scheduleDebugAutoExitIfRequested()
#endif
  }

  func stop() {
    semanticBuffer.onChunk = nil
#if DEBUG
    semanticBuffer.onDebugEvent = nil
    contextRevisionPipeline.onDebugSnapshot = nil
#endif
    accessibilityLiveMonitor.onLiveSessionChange = nil
    tutorManualRuntimeController.stop()
    tutorPanelCoordinator.stop()
#if DEBUG
    tutorCoordinator.stop()
    tutorDebugWindowController.stop()
    realtimeVoiceLifecycleMonitor.stop()
    tutorAXConsoleCaptureTask?.cancel()
    tutorAXConsoleCaptureTask = nil
#endif
    accessibilityDebugWindowController.stop()
    accessibilityLiveMonitor.stop()
    accessibilitySnapshotController.cancelCurrentRead(clearSnapshot: true)
    activeApplicationMonitor.stop()
#if DEBUG
    petStateStressTask?.cancel()
    petStateStressTask = nil
    voiceStressTask?.cancel()
    voiceStressTask = nil
    debugAutoExitTask?.cancel()
    debugAutoExitTask = nil
#endif
    speechInputController.cancel()
    tutorVoiceCoordinator.shutdown()
    voiceController.stop()
    voiceController.shutdownLocalService()
    hotKeyManager.unregister()
    aiModelSettingsWindowController.stop()
    voiceSettingsWindowController.stop()
    petLibraryWindowController.stop()
    petWindowController.stop()
    panelController.stop()
  }

  func refreshAccessibilityPermission() {
    accessibilitySnapshotController.refreshPermissionState()
  }

#if DEBUG
  var hasActiveRealtimeVoiceSession: Bool {
    realtimeVoiceCoordinator.isActive
  }

  func stopRealtimeVoiceForTermination() async {
    await realtimeVoiceSpikeWindowController.stop()
  }
#endif

#if DEBUG
  private func startTutorAXConsoleCaptureIfRequested() {
    guard ProcessInfo.processInfo.arguments.contains("--tutor-ax-console-capture") else {
      return
    }

    tutorAXConsoleCaptureTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: 500_000_000)
      } catch {
        return
      }
      guard let self else {
        return
      }

      tutorManualRuntimeController.handle(.explainCurrentContent)
      for _ in 0..<80 {
        do {
          try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
          return
        }
        if let report = tutorDebugTraceStore.completedConsoleReport() {
          print(
            report
              + "\n"
              + AXReadTraceStore.shared.consoleReport()
              + "\nUSER FACING RESULT\n"
              + tutorAXConsoleUIReport()
          )
          fflush(stdout)
          NSApplication.shared.terminate(nil)
          return
        }
      }

      print(
        tutorDebugTraceStore.incompleteConsoleReport()
          + "\n"
          + AXReadTraceStore.shared.consoleReport()
          + "\nUSER FACING RESULT\n"
          + tutorAXConsoleUIReport()
      )
      fflush(stdout)
      NSApplication.shared.terminate(nil)
    }
  }

  private func tutorAXConsoleUIReport() -> String {
    switch tutorPanelContentStore.state {
    case let .error(error):
      return [
        "state=error",
        "title=\(error.title)",
        "message=\(error.message)",
      ].joined(separator: "\n")
    case .loading:
      return "state=loading"
    case .presentation:
      return "state=presentation"
    case .empty:
      return "state=empty"
    }
  }

  private func applyPetStateDebugArgumentIfRequested() {
    let prefix = "--pet-state="
    guard
      let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
      let state = PetState(rawValue: String(argument.dropFirst(prefix.count)))
    else {
      return
    }

    petStateController.transition(to: state)
  }

  private func startPetStateStressTestIfRequested() {
    guard ProcessInfo.processInfo.arguments.contains("--pet-state-stress-test") else {
      return
    }

    let sequence: [PetState] = [
      .thinking,
      .warning,
      .success,
      .watching,
      .speaking,
      .needsInput,
      .error,
      .idle,
    ]

    petStateStressTask = Task { [weak self] in
      for index in 0..<30 {
        guard !Task.isCancelled else {
          return
        }

        self?.petStateController.transition(to: sequence[index % sequence.count])

        do {
          try await Task.sleep(nanoseconds: 120_000_000)
        } catch {
          return
        }
      }

      self?.petStateController.transition(to: .idle)
      AppLogger.pet.info("Pet state stress test completed: 30 transitions")
      self?.petStateStressTask = nil
    }
  }

  private func applyVoiceDebugArgumentIfRequested() {
    let prefix = "--voice-text="
    guard
      let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })
    else {
      return
    }

    voiceController.speak(text: String(argument.dropFirst(prefix.count)))
  }

  private func startVoiceStressTestIfRequested() {
    guard ProcessInfo.processInfo.arguments.contains("--voice-stress-test") else {
      return
    }

    voiceStressTask = Task { [weak self] in
      for index in 0..<30 {
        guard !Task.isCancelled else {
          return
        }
        self?.voiceController.speak(text: "语音替换压力测试 \(index + 1)")
        await Task.yield()
      }
      AppLogger.voice.info("System speech replacement stress test completed: 30 requests")
      self?.voiceStressTask = nil
    }
  }

  private func scheduleDebugAutoExitIfRequested() {
    let prefix = "--debug-auto-exit-after="
    guard
      let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
      let seconds = Double(argument.dropFirst(prefix.count)),
      seconds > 0
    else {
      return
    }

    debugAutoExitTask = Task {
      do {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      } catch {
        return
      }
      NSApplication.shared.terminate(nil)
    }
  }
#endif
}
