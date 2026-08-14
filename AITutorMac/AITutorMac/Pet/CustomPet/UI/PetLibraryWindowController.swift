import AppKit
import SwiftUI

@MainActor
final class PetLibraryWindowController: NSObject, NSWindowDelegate {
  private let library: PetLibrary
  private let importer: PetImporter
  private var window: NSWindow?

  init(library: PetLibrary, importer: PetImporter) {
    self.library = library
    self.importer = importer
  }

  func show() {
    createIfNeeded()
    NSApplication.shared.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func stop() {
    window?.orderOut(nil)
    window?.contentViewController = nil
    window = nil
  }

  private func createIfNeeded() {
    guard window == nil else {
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "我的桌面老师"
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName("PetLibraryWindow")
    window.contentMinSize = NSSize(width: 560, height: 500)
    window.delegate = self
    window.contentViewController = NSHostingController(
      rootView: PetLibraryView(library: library, importer: importer)
    )
    window.center()
    self.window = window
  }
}
