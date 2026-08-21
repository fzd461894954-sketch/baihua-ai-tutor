import AppKit
import SwiftUI

@MainActor
final class AccessibilityDebugWindowController: NSObject, NSWindowDelegate {
  private let snapshotController: AccessibilitySnapshotController
  private let liveMonitor: AccessibilityLiveMonitor
  private var window: NSWindow?

  init(
    snapshotController: AccessibilitySnapshotController,
    liveMonitor: AccessibilityLiveMonitor
  ) {
    self.snapshotController = snapshotController
    self.liveMonitor = liveMonitor
  }

  func show() {
    snapshotController.refreshPermissionState()
    let window = window ?? makeWindow()
    self.window = window
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func stop() {
    liveMonitor.stop()
    snapshotController.cancelCurrentRead(clearSnapshot: true)
    window?.orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) {
    // Closing diagnostics must not own or invalidate the user's live session.
    // Live Watch remains controlled by its explicit stop action and app shutdown.
    snapshotController.cancelManualRead()
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 980),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Context Debug · Accessibility"
    window.isReleasedWhenClosed = false
    window.center()
    window.delegate = self
    window.contentViewController = NSHostingController(
      rootView: AccessibilityDebugView(
        controller: snapshotController,
        liveMonitor: liveMonitor
      )
    )
    return window
  }
}
