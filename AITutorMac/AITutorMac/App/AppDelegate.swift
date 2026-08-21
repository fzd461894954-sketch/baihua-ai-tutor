import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let automaticTerminationReason = "白话 AI 菜单栏伴侣需要持续响应快捷键"
#if DEBUG
  private var isCompletingRealtimeVoiceTermination = false
#endif

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

  var aiModelSettingsController: AIModelSettingsController {
    container.aiModelSettingsController
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

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if DEBUG
    guard container.hasActiveRealtimeVoiceSession else {
      return .terminateNow
    }
    guard !isCompletingRealtimeVoiceTermination else {
      return .terminateLater
    }

    isCompletingRealtimeVoiceTermination = true
    Task {
      await container.stopRealtimeVoiceForTermination()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
#else
    return .terminateNow
#endif
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

  @objc func showModelSettings() {
    container.aiModelSettingsWindowController.show()
  }

  @objc func showAccessibilityDebug() {
    container.accessibilityDebugWindowController.show()
  }

  @objc func showTutorDebug() {
#if DEBUG
    container.tutorDebugWindowController.show()
#endif
  }

  @objc func showRealtimeVoiceSpike() {
#if DEBUG
    container.realtimeVoiceSpikeWindowController.show()
#endif
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
