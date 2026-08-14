import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let automaticTerminationReason = "白话 AI 菜单栏伴侣需要持续响应快捷键"

  let appState = AppState()

  private lazy var container = AppContainer(appState: appState)

  var petStateController: PetStateController {
    container.petStateController
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
    ProcessInfo.processInfo.disableAutomaticTermination(
      automaticTerminationReason
    )
    container.start()
    AppLogger.lifecycle.info("App launched")
  }

  func applicationWillTerminate(_ notification: Notification) {
    container.stop()
    AppLogger.lifecycle.info("App terminated")
    ProcessInfo.processInfo.enableAutomaticTermination(
      automaticTerminationReason
    )
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  @objc func showPanel() {
    container.panelController.show()
  }

  @objc func hidePanel() {
    container.panelController.hide()
  }

  @objc func showPet() {
    container.petWindowController.show()
  }

  @objc func hidePet() {
    container.petWindowController.hide()
  }

  @objc func showPetLibrary() {
    container.petLibraryWindowController.show()
  }

  func transitionPetState(to state: PetState) {
    container.petWindowController.show()
    container.petStateController.transition(to: state)
  }

  @objc func terminateApp() {
    NSApplication.shared.terminate(nil)
  }
}
