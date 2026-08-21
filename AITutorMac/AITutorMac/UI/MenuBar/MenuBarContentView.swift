import AppKit
import SwiftUI

struct MenuBarContentView: View {
  let appState: AppState
  let contextState: ContextState
  let accessibilitySnapshotController: AccessibilitySnapshotController
  let showPanel: () -> Void
  let hidePanel: () -> Void
  let showPet: () -> Void
  let hidePet: () -> Void
  let showPetLibrary: () -> Void
  let showVoiceSettings: () -> Void
  let showAccessibilityDebug: () -> Void
  let showTutorDebug: () -> Void
  let petStateController: PetStateController
  let voiceController: VoiceController
  let speechInputController: SpeechInputController
  let transitionPetState: (PetState) -> Void
  let speak: (String) -> Void
  let stopSpeaking: () -> Void
  let terminateApp: () -> Void

  var body: some View {
    Text("白话 AI")
    Text("当前应用：\(contextState.userContextApplication?.displayName ?? "未检测到")")

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

    Divider()

    Button("我的桌面老师…", action: showPetLibrary)
    Button("语音设置…", action: showVoiceSettings)

    if speechInputController.isMicrophoneActive {
      Label("正在听…", systemImage: "mic.fill")
    }

#if DEBUG
    Divider()

    Text("吉祥物状态：\(petStateController.currentState.displayName)")

    ContextDebugView(
      contextState: contextState,
      classifier: TargetApplicationClassifier(),
      accessibilitySnapshotController: accessibilitySnapshotController
    )

    Button("Accessibility Snapshot…", action: showAccessibilityDebug)
    Button("Tutor Debug…", action: showTutorDebug)

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

      Menu("语音") {
        Button("播放测试句") {
          speak("它现在正在给这个项目安装运行所需要的软件。")
        }
        Button("停止朗读", action: stopSpeaking)
          .disabled(!voiceController.isActive)
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
