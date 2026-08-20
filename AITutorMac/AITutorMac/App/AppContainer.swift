import AppKit

@MainActor
final class AppContainer {
  let panelController: FloatingPanelController
  let petStateController: PetStateController
  let petWindowController: PetWindowController
  let petLibrary: PetLibrary
  let petLibraryWindowController: PetLibraryWindowController
  let voiceController: VoiceController
  let speechInputController: SpeechInputController
  let voiceSettingsWindowController: VoiceSettingsWindowController
  let contextState: ContextState
  let activeApplicationMonitor: ActiveApplicationMonitor
  let accessibilitySnapshotController: AccessibilitySnapshotController
  let accessibilityDebugWindowController: AccessibilityDebugWindowController

  private let appState: AppState
  private let hotKeyManager: HotKeyManager
#if DEBUG
  private var petStateStressTask: Task<Void, Never>?
  private var voiceStressTask: Task<Void, Never>?
  private var debugAutoExitTask: Task<Void, Never>?
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
    let accessibilityDebugWindowController = AccessibilityDebugWindowController(
      snapshotController: accessibilitySnapshotController
    )
    self.accessibilityDebugWindowController = accessibilityDebugWindowController
    activeApplicationMonitor.onLastExternalApplicationChange = {
      [weak accessibilitySnapshotController] _ in
      accessibilitySnapshotController?.targetApplicationDidChange()
    }
    let panelController = FloatingPanelController(
      appState: appState,
      showAccessibilityDebug: { [weak accessibilityDebugWindowController] in
        accessibilityDebugWindowController?.show()
      }
    )
    let petStateController = PetStateController()
    let libraryStore = PetLibraryStore()
    let imageValidator = PetImageValidator()
    let petLibrary = PetLibrary(store: libraryStore, validator: imageValidator)
    let petImporter = PetImporter(validator: imageValidator, store: libraryStore)
    self.panelController = panelController
    self.petStateController = petStateController
    self.petLibrary = petLibrary

    let voiceController = VoiceController(petStateController: petStateController)
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

    let petWindowController = PetWindowController(
      appState: appState,
      pet: petLibrary.currentPet,
      petImage: petLibrary.image(for: petLibrary.currentPet),
      stateController: petStateController,
      speechInputController: speechInputController,
      onScaleChange: { [weak petLibrary] id, scale in
        petLibrary?.updateScale(for: id, scale: scale)
      }
    ) { [weak panelController] in
      panelController?.show()
    }
    self.petWindowController = petWindowController
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

    let registered = hotKeyManager.registerOptionSpace { [weak self] in
      AppLogger.hotKey.info("Global shortcut triggered")
      self?.panelController.toggle()
    }

    if !registered {
      appState.shellStatus = .hotKeyUnavailable
    }

#if DEBUG
    applyPetStateDebugArgumentIfRequested()
    startPetStateStressTestIfRequested()
    applyVoiceDebugArgumentIfRequested()
    startVoiceStressTestIfRequested()
    scheduleDebugAutoExitIfRequested()
#endif
  }

  func stop() {
    accessibilityDebugWindowController.stop()
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
    voiceController.stop()
    hotKeyManager.unregister()
    voiceSettingsWindowController.stop()
    petLibraryWindowController.stop()
    petWindowController.stop()
    panelController.stop()
  }

  func refreshAccessibilityPermission() {
    accessibilitySnapshotController.refreshPermissionState()
  }

#if DEBUG
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
