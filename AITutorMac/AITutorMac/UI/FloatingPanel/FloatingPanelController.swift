import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
  private enum Layout {
    static let defaultSize = NSSize(width: 400, height: 600)
    static let minimumSize = NSSize(width: 360, height: 480)
    static let screenMargin: CGFloat = 24
    static let frameAutosaveName = "AITutorFloatingPanelFrame"
  }

  private let appState: AppState
  private let showAccessibilityDebug: () -> Void
  private var panel: NSPanel?
  private var escapeKeyMonitor: Any?

  init(
    appState: AppState,
    showAccessibilityDebug: @escaping () -> Void = {}
  ) {
    self.appState = appState
    self.showAccessibilityDebug = showAccessibilityDebug
    super.init()
  }

  func create() {
    guard panel == nil else {
      return
    }

    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: Layout.defaultSize),
      styleMask: [
        .titled,
        .closable,
        .resizable,
        .fullSizeContentView,
        .nonactivatingPanel,
      ],
      backing: .buffered,
      defer: false
    )

    panel.title = "白话 AI"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.isMovableByWindowBackground = true
    panel.minSize = Layout.minimumSize
    panel.backgroundColor = .clear
    panel.contentViewController = NSHostingController(
      rootView: FloatingPanelView(
        showAccessibilityDebug: showAccessibilityDebug
      )
    )
    panel.delegate = self

    let restoredSavedFrame = panel.setFrameUsingName(Layout.frameAutosaveName)
    panel.setFrameAutosaveName(Layout.frameAutosaveName)
    if !restoredSavedFrame {
      panel.setFrame(
        NSRect(origin: .zero, size: Layout.defaultSize),
        display: false
      )
      positionNearTopRight(panel)
    }

    self.panel = panel
  }

  func show() {
    create()
    guard let panel, !panel.isVisible else {
      return
    }

    installEscapeKeyMonitor()
    panel.orderFrontRegardless()
    panel.makeKey()
    appState.isPanelVisible = true
    AppLogger.panel.info("Panel shown")
  }

  func hide() {
    guard let panel, panel.isVisible else {
      return
    }

    removeEscapeKeyMonitor()
    panel.orderOut(nil)
    appState.isPanelVisible = false
    AppLogger.panel.info("Panel hidden")
  }

  func toggle() {
    if panel?.isVisible == true {
      hide()
    } else {
      show()
    }
  }

  func stop() {
    removeEscapeKeyMonitor()
    panel?.orderOut(nil)
    appState.isPanelVisible = false
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hide()
    return false
  }

  private func positionNearTopRight(_ panel: NSPanel) {
    guard let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
      panel.center()
      return
    }

    let origin = NSPoint(
      x: visibleFrame.maxX - Layout.defaultSize.width - Layout.screenMargin,
      y: visibleFrame.maxY - Layout.defaultSize.height - Layout.screenMargin
    )
    panel.setFrameOrigin(origin)
  }

  private func installEscapeKeyMonitor() {
    guard escapeKeyMonitor == nil else {
      return
    }

    escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53, self?.panel?.isVisible == true else {
        return event
      }

      self?.hide()
      return nil
    }
  }

  private func removeEscapeKeyMonitor() {
    guard let escapeKeyMonitor else {
      return
    }

    NSEvent.removeMonitor(escapeKeyMonitor)
    self.escapeKeyMonitor = nil
  }
}
