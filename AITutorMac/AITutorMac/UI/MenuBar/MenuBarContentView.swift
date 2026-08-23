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
    Text("花花老师")
    Text("当前应用：\(contextState.userContextApplication?.displayName ?? "未检测到")")

    if accessibilitySnapshotController.authorizationController.permissionState == .granted {
      Text("持续跟随（可选）：\(accessibilityLiveMonitor.state.displayName)")
      Button("开始持续跟随当前应用") {
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

    Button {
      send(.panel)
    } label: {
      Label(
        appState.isPanelVisible ? "隐藏独立教学窗" : "显示独立教学窗",
        systemImage: appState.isPanelVisible ? "rectangle.slash" : "rectangle.on.rectangle"
      )
    }

    Divider()

    Button {
      send(.petVisibility)
    } label: {
      Label(
        appState.isPetVisible ? "隐藏花花老师" : "显示花花老师",
        systemImage: appState.isPetVisible ? "eye.slash" : "eye"
      )
    }

    Divider()

    Button("老师形象…") { send(.petLibrary) }
    Button("AI 模型设置…") { send(.settings) }
    Button("声音与麦克风…") { send(.voiceSettings) }

    if speechInputController.isMicrophoneActive {
      Label("正在听…", systemImage: "mic.fill")
    }

#if DEBUG
    Divider()

    Text("花花老师状态：\(petStateController.currentState.displayName)")

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

    Button("退出花花老师") { send(.quit) }
      .keyboardShortcut("q")
  }

  private func send(_ item: MenuBarItem) {
    onIntent(item.intent)
  }
}
