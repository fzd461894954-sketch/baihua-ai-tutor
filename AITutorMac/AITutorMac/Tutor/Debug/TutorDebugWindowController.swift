#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class TutorDebugWindowController: NSObject, NSWindowDelegate {
  private let coordinator: TutorCoordinator
  private let realDemoController: TutorRealDemoController
  private var window: NSWindow?

  init(coordinator: TutorCoordinator) {
    self.coordinator = coordinator
    realDemoController = TutorRealDemoController()
  }

  init(
    coordinator: TutorCoordinator,
    realDemoController: TutorRealDemoController
  ) {
    self.coordinator = coordinator
    self.realDemoController = realDemoController
  }

  func show() {
    realDemoController.prepareForDisplay()
    let window = window ?? makeWindow()
    self.window = window
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func stop() {
    realDemoController.shutdown()
    window?.orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) {
    realDemoController.dismiss()
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 860),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Tutor Debug"
    window.isReleasedWhenClosed = false
    window.center()
    window.delegate = self
    window.contentViewController = NSHostingController(
      rootView: TabView {
        TutorDebugView(coordinator: coordinator)
          .tabItem {
            Label("Fake Contract", systemImage: "shippingbox")
          }
        TutorRealDemoView(controller: realDemoController)
          .tabItem {
            Label("Real LLM Demo", systemImage: "checkmark.seal")
          }
      }
    )
    return window
  }
}
#endif
