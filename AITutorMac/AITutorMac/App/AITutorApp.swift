import SwiftUI

@main
struct AITutorApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("白话 AI", systemImage: "sparkles") {
      MenuBarContentView(
        appState: appDelegate.appState,
        showPanel: appDelegate.showPanel,
        hidePanel: appDelegate.hidePanel,
        showPet: appDelegate.showPet,
        hidePet: appDelegate.hidePet,
        showPetLibrary: appDelegate.showPetLibrary,
        showVoiceSettings: appDelegate.showVoiceSettings,
        petStateController: appDelegate.petStateController,
        voiceController: appDelegate.voiceController,
        transitionPetState: appDelegate.transitionPetState,
        speak: appDelegate.speak,
        stopSpeaking: appDelegate.stopSpeaking,
        terminateApp: appDelegate.terminateApp
      )
    }
    .menuBarExtraStyle(.menu)
  }
}
