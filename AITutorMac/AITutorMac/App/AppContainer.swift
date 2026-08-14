import Foundation

@MainActor
final class AppContainer {
  let panelController: FloatingPanelController
  let petStateController: PetStateController
  let petWindowController: PetWindowController

  private let appState: AppState
  private let hotKeyManager: HotKeyManager
#if DEBUG
  private var petStateStressTask: Task<Void, Never>?
#endif

  init(appState: AppState) {
    self.appState = appState
    let panelController = FloatingPanelController(appState: appState)
    let petStateController = PetStateController()
    self.panelController = panelController
    self.petStateController = petStateController
    petWindowController = PetWindowController(
      appState: appState,
      stateController: petStateController
    ) { [weak panelController] in
      panelController?.show()
    }
    hotKeyManager = HotKeyManager()
  }

  func start() {
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
#endif
  }

  func stop() {
#if DEBUG
    petStateStressTask?.cancel()
    petStateStressTask = nil
#endif
    hotKeyManager.unregister()
    petWindowController.stop()
    panelController.stop()
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
#endif
}
