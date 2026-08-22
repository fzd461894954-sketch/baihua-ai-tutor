import AppKit
import SwiftUI

enum MenuBarIntent: Equatable {
  case togglePanel
  case togglePetVisibility
  case openSettings
  case openPetLibrary
  case openVoiceSettings
  case quit
}

enum MenuBarItem: CaseIterable {
  case panel
  case petVisibility
  case petLibrary
  case settings
  case voiceSettings
  case quit

  var intent: MenuBarIntent {
    switch self {
    case .panel: .togglePanel
    case .petVisibility: .togglePetVisibility
    case .petLibrary: .openPetLibrary
    case .settings: .openSettings
    case .voiceSettings: .openVoiceSettings
    case .quit: .quit
    }
  }
}

struct MenuBarContentView: View {
  let appState: AppState
  let contextState: ContextState
  let accessibilitySnapshotController: AccessibilitySnapshotController
  let accessibilityLiveMonitor: AccessibilityLiveMonitor
  let onIntent: (MenuBarIntent) -> Void
  let showAccessibilityDebug: () -> Void
  let showTutorDebug: () -> Void
  let petStateController: PetStateController
  let voiceController: VoiceController
  let speechInputController: SpeechInputController
  let transitionPetState: (PetState) -> Void
  let speak: (String) -> Void
  let stopSpeaking: () -> Void

  var body: some View {
    Text("白话 AI")
    Text("当前应用：\(contextState.userContextApplication?.displayName ?? "未检测到")")

    if accessibilitySnapshotController.authorizationController.permissionState == .granted {
      Text("内容跟随：\(accessibilityLiveMonitor.state.displayName)")
      Button("开始跟随当前应用") {
        accessibilityLiveMonitor.start()
      }
      .disabled(accessibilityLiveMonitor.isLiveSessionActive)
      Button("停止跟随") {
        accessibilityLiveMonitor.stop()
      }
      .disabled(!accessibilityLiveMonitor.isLiveSessionActive)
    } else {
      Button("请求辅助功能权限…") {
        let authorization = accessibilitySnapshotController.authorizationController
        authorization.beginPermissionRequest()
        authorization.continuePermissionRequest()
        authorization.openSystemSettings()
      }
    }

    Divider()

    Button("打开教学窗口") { send(.panel) }
      .disabled(appState.isPanelVisible)
    Button("隐藏教学窗口") { send(.panel) }
      .disabled(!appState.isPanelVisible)

    Divider()

    Button("显示吉祥物") { send(.petVisibility) }
      .disabled(appState.isPetVisible)
    Button("隐藏吉祥物") { send(.petVisibility) }
      .disabled(!appState.isPetVisible)

    Divider()

    Button("我的桌面老师…") { send(.petLibrary) }
    Button("设置…") { send(.settings) }
    Button("语音设置…") { send(.voiceSettings) }

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

    Button("退出白话 AI") { send(.quit) }
      .keyboardShortcut("q")
  }

  private func send(_ item: MenuBarItem) {
    onIntent(item.intent)
  }
}
