import AppKit
import SwiftUI

@MainActor
struct VoiceDebugView: View {
  let voiceController: VoiceController
  let speechInputController: SpeechInputController

#if DEBUG
  @State private var debugText = "它现在正在给这个项目安装运行所需要的软件。"
#endif

  var body: some View {
    @Bindable var voiceController = voiceController

    Form {
      Section("语音") {
        Picker("声音", selection: voiceSelection) {
          Text("自动（本地 Qwen3 优先）").tag("")
          ForEach(voiceController.availableVoices) { voice in
            Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
          }
        }
        .accessibilityHint("优先使用你选择的声音，不可用时自动回退")

        if let localStatus = voiceController.localServiceStatus {
          HStack {
            Label(localStatus.displayText, systemImage: localStatus.systemImageName)
              .foregroundStyle(localStatus == .ready ? .green : .secondary)

            Spacer()

            Button(localStatus == .ready ? "重新检测" : "启动本地语音") {
              voiceController.prepareLocalService()
            }
            .disabled(localStatus == .starting || localStatus == .notInstalled)
          }

          if localStatus == .notInstalled {
            Text("请先运行项目中的 scripts/setup-local-voice.sh。安装完成后重新打开应用。")
              .font(.callout)
              .foregroundStyle(.secondary)
          } else if localStatus != .ready {
            Text("本地模型不可用时会自动使用 Apple 系统中文语音，不会中断朗读。")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }

        settingSlider(
          title: "语速",
          lowerLabel: "较慢",
          upperLabel: "较快",
          value: rateBinding,
          range: SpeechConfiguration.rateRange
        )
        settingSlider(
          title: "音调",
          lowerLabel: "较低",
          upperLabel: "较高",
          value: pitchBinding,
          range: SpeechConfiguration.pitchRange
        )
        settingSlider(
          title: "音量",
          lowerLabel: "较小",
          upperLabel: "较大",
          value: volumeBinding,
          range: SpeechConfiguration.volumeRange
        )
      }

      Section {
        HStack {
          Button("播放示例") {
            voiceController.speak(text: "它正在检查数据库权限，你暂时不用操作。")
          }
          .keyboardShortcut(.return, modifiers: .command)

          Button("停止朗读") {
            voiceController.stop()
          }
          .disabled(!voiceController.isActive)

          Spacer()

          Text(voiceController.status.displayText)
            .foregroundStyle(.secondary)
        }

        if let message = voiceController.userMessage {
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
      }

#if DEBUG
      Section("开发测试") {
        TextEditor(text: $debugText)
          .font(.body)
          .frame(minHeight: 72)
          .overlay {
            RoundedRectangle(cornerRadius: 6)
              .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
          }

        Button("让老师讲给我听") {
          voiceController.speak(text: debugText)
        }
        .disabled(debugText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
#endif

      Section("隐私") {
        Text(voicePrivacyText)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Section("语音输入") {
        Picker("识别语言", selection: inputLocaleSelection) {
          Text("简体中文").tag("zh-CN")
          Text("English (US)").tag("en-US")
        }
        Text("麦克风只会在你点按花花老师卡片中的麦克风按钮后使用，再次点按结束。")
          .font(.callout)
          .foregroundStyle(.secondary)

#if DEBUG
        Text("权限：麦克风 \(speechInputController.permissionStatus.microphone.rawValue) · 语音识别 \(speechInputController.permissionStatus.speechRecognition.rawValue)")
          .font(.caption.monospaced())
        Text("输入状态：\(speechInputController.state.rawValue)")
          .font(.caption.monospaced())
        Text("本机识别：\(onDeviceDebugText)")
          .font(.caption.monospaced())
#endif
      }
    }
    .formStyle(.grouped)
    .padding(8)
    .frame(minWidth: 500, minHeight: 500)
    .onAppear {
      voiceController.refreshAvailableVoices()
    }
  }

  private var voiceSelection: Binding<String> {
    Binding(
      get: {
        guard
          let identifier = voiceController.configuration.voiceIdentifier,
          voiceController.availableVoices.contains(where: { $0.identifier == identifier })
        else {
          return ""
        }
        return identifier
      },
      set: { voiceController.selectVoice(identifier: $0.isEmpty ? nil : $0) }
    )
  }

  private var rateBinding: Binding<Float> {
    Binding(
      get: { voiceController.configuration.rate },
      set: { voiceController.setRate($0) }
    )
  }

  private var pitchBinding: Binding<Float> {
    Binding(
      get: { voiceController.configuration.pitch },
      set: { voiceController.setPitch($0) }
    )
  }

  private var volumeBinding: Binding<Float> {
    Binding(
      get: { voiceController.configuration.volume },
      set: { voiceController.setVolume($0) }
    )
  }

  private var voicePrivacyText: String {
    if voiceController.selectedVoiceUsesLocalModel {
      return "朗读文字只发送到这台 Mac 上的 127.0.0.1 本地 Qwen3-TTS 服务。服务不可用时自动使用 Apple 系统语音；应用不会保存生成的音频。"
    }
    return "朗读由 Apple 系统语音完成。文字不会发送给第三方 TTS 服务，也不会保存为音频文件。"
  }

  private var inputLocaleSelection: Binding<String> {
    Binding(
      get: { speechInputController.selectedLocaleIdentifier },
      set: { speechInputController.selectLocale(identifier: $0) }
    )
  }

#if DEBUG
  private var onDeviceDebugText: String {
    speechInputController.onDeviceRecognitionSupported
      .map { $0 ? "supported" : "unsupported" } ?? "unknown"
  }
#endif

  private func settingSlider(
    title: String,
    lowerLabel: String,
    upperLabel: String,
    value: Binding<Float>,
    range: ClosedRange<Float>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
      HStack {
        Text(lowerLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        Slider(value: value, in: range)
        Text(upperLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

@MainActor
final class VoiceSettingsWindowController: NSObject, NSWindowDelegate {
  private let voiceController: VoiceController
  private let speechInputController: SpeechInputController
  private var window: NSWindow?

  init(
    voiceController: VoiceController,
    speechInputController: SpeechInputController
  ) {
    self.voiceController = voiceController
    self.speechInputController = speechInputController
  }

  func show() {
    createIfNeeded()
    NSApplication.shared.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func stop() {
    window?.orderOut(nil)
    window?.contentViewController = nil
    window = nil
  }

  private func createIfNeeded() {
    guard window == nil else {
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 540),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "语音"
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName("VoiceSettingsWindow")
    window.contentMinSize = NSSize(width: 500, height: 500)
    window.delegate = self
    window.contentViewController = NSHostingController(
      rootView: VoiceDebugView(
        voiceController: voiceController,
        speechInputController: speechInputController
      )
    )
    window.center()
    self.window = window
  }
}
