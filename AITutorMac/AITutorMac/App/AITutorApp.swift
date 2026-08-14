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
        petStateController: appDelegate.petStateController,
        transitionPetState: appDelegate.transitionPetState,
        terminateApp: appDelegate.terminateApp
      )
    }
    .menuBarExtraStyle(.menu)
  }
}
