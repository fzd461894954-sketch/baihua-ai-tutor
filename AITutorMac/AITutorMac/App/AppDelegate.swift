import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let automaticTerminationReason = "白话 AI 菜单栏伴侣需要持续响应快捷键"

  let appState = AppState()
  let contextState = ContextState()

  private lazy var container = AppContainer(
    appState: appState,
    contextState: contextState
  )

  var petStateController: PetStateController {
    container.petStateController
  }

  var voiceController: VoiceController {
    container.voiceController
  }

  var speechInputController: SpeechInputController {
    container.speechInputController
  }

  var accessibilitySnapshotController: AccessibilitySnapshotController {
    container.accessibilitySnapshotController
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

  func applicationDidBecomeActive(_ notification: Notification) {
    container.refreshAccessibilityPermission()
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

  @objc func showVoiceSettings() {
    container.voiceSettingsWindowController.show()
  }

  @objc func showAccessibilityDebug() {
    container.accessibilityDebugWindowController.show()
  }

  func speak(_ text: String) {
    container.voiceController.speak(text: text)
  }

  @objc func stopSpeaking() {
    container.voiceController.stop()
  }

  func transitionPetState(to state: PetState) {
    container.petWindowController.show()
    container.petStateController.transition(to: state)
  }

  @objc func terminateApp() {
    NSApplication.shared.terminate(nil)
  }
}
