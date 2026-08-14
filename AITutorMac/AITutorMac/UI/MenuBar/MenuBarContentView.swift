import AppKit
import SwiftUI

struct MenuBarContentView: View {
  let appState: AppState
  let showPanel: () -> Void
  let hidePanel: () -> Void
  let showPet: () -> Void
  let hidePet: () -> Void
  let petStateController: PetStateController
  let transitionPetState: (PetState) -> Void
  let terminateApp: () -> Void

  var body: some View {
    Text("白话 AI")

    Divider()

    Button("打开教学窗口", action: showPanel)
      .disabled(appState.isPanelVisible)
    Button("隐藏教学窗口", action: hidePanel)
      .disabled(!appState.isPanelVisible)

    Divider()

    Button("显示吉祥物", action: showPet)
      .disabled(appState.isPetVisible)
    Button("隐藏吉祥物", action: hidePet)
      .disabled(!appState.isPetVisible)

#if DEBUG
    Divider()

    Text("吉祥物状态：\(petStateController.currentState.displayName)")

    Menu("开发测试") {
      Menu("Pet 状态") {
        ForEach(PetState.allCases, id: \.self) { state in
          Button {
            transitionPetState(state)
          } label: {
            Label(
              state.displayName,
              systemImage: petStateController.currentState == state
                ? "checkmark"
                : (state.badgeSystemImageName ?? "minus")
            )
          }
        }
      }
    }
#endif

    Divider()

    Text("状态：\(appState.shellStatus.displayText)")

    Divider()

    Button("退出白话 AI", action: terminateApp)
      .keyboardShortcut("q")
  }
}
