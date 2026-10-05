#if DEBUG
import AppKit
import Foundation

@MainActor
final class RealtimeVoiceLifecycleMonitor {
  private let coordinator: DoubaoRealtimeVoiceCoordinator
  private var sleepObserver: NSObjectProtocol?

  init(coordinator: DoubaoRealtimeVoiceCoordinator) {
    self.coordinator = coordinator
  }

  func start() {
    guard sleepObserver == nil else { return }
    sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        await self?.coordinator.stop(reason: .systemSleep)
      }
    }
  }

  func stop() {
    if let sleepObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
    }
    sleepObserver = nil
  }
}
#endif
