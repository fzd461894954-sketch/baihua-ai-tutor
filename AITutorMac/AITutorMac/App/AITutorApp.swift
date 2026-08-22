import SwiftUI

@main
struct AITutorApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("白话 AI", systemImage: "sparkles") {
      MenuBarContentView(
        appState: appDelegate.appState,
        contextState: appDelegate.contextState,
        accessibilitySnapshotController: appDelegate.accessibilitySnapshotController,
        onIntent: { intent in
          switch intent {
          case .togglePanel:
            appDelegate.appState.isPanelVisible
              ? appDelegate.hidePanel()
              : appDelegate.showPanel()
          case .togglePetVisibility:
            appDelegate.appState.isPetVisible
              ? appDelegate.hidePet()
              : appDelegate.showPet()
          case .openSettings:
            appDelegate.showModelSettings()
          case .openPetLibrary:
            appDelegate.showPetLibrary()
          case .openVoiceSettings:
            appDelegate.showVoiceSettings()
          case .quit:
            appDelegate.terminateApp()
          }
        },
        showAccessibilityDebug: appDelegate.showAccessibilityDebug,
        showTutorDebug: appDelegate.showTutorDebug,
        petStateController: appDelegate.petStateController,
        voiceController: appDelegate.voiceController,
        speechInputController: appDelegate.speechInputController,
        transitionPetState: appDelegate.transitionPetState,
        speak: appDelegate.speak,
        stopSpeaking: appDelegate.stopSpeaking
      )
    }
    .menuBarExtraStyle(.menu)
#if DEBUG
    .commands {
      CommandMenu("Context Debug") {
        Button("Accessibility Snapshot…") {
          appDelegate.showAccessibilityDebug()
        }
        Button("Tutor Debug…") {
          appDelegate.showTutorDebug()
        }
        Divider()
        Button("Realtime Voice Spike…") {
          appDelegate.showRealtimeVoiceSpike()
        }
      }
    }
#endif

    Settings {
      AIModelSettingsView(controller: appDelegate.aiModelSettingsController)
        .onAppear {
          appDelegate.aiModelSettingsController.reload()
        }
    }
  }
}
