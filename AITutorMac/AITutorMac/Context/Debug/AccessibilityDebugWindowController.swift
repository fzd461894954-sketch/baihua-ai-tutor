import AppKit
import SwiftUI

@MainActor
final class AccessibilityDebugWindowController: NSObject, NSWindowDelegate {
  private let snapshotController: AccessibilitySnapshotController
  private var window: NSWindow?

  init(snapshotController: AccessibilitySnapshotController) {
    self.snapshotController = snapshotController
  }

  func show() {
    snapshotController.refreshPermissionState()
    let window = window ?? makeWindow()
    self.window = window
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func stop() {
    snapshotController.cancelCurrentRead(clearSnapshot: true)
    window?.orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) {
    snapshotController.cancelCurrentRead()
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Context Debug · Accessibility"
    window.isReleasedWhenClosed = false
    window.center()
    window.delegate = self
    window.contentViewController = NSHostingController(
      rootView: AccessibilityDebugView(controller: snapshotController)
    )
    return window
  }
}
