#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class RealtimeVoiceSpikeWindowController: NSObject, NSWindowDelegate {
  private let coordinator: DoubaoRealtimeVoiceCoordinator
  private var window: NSWindow?

  init(coordinator: DoubaoRealtimeVoiceCoordinator) {
    self.coordinator = coordinator
  }

  func show() {
    let window = window ?? makeWindow()
    self.window = window
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func stop() async {
    await coordinator.stop(reason: .appTermination)
    window?.orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) {
    Task {
      await coordinator.stop(reason: .windowClosed)
    }
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 470),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Realtime Voice Spike"
    window.isReleasedWhenClosed = false
    window.center()
    window.delegate = self
    window.contentViewController = NSHostingController(
      rootView: RealtimeVoiceSpikeView(coordinator: coordinator)
    )
    return window
  }
}
#endif
