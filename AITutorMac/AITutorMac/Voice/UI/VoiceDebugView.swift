import AppKit
import SwiftUI

@MainActor
struct VoiceDebugView: View {
  let voiceController: VoiceController

#if DEBUG
  @State private var debugText = "它现在正在给这个项目安装运行所需要的软件。"
#endif

  var body: some View {
    @Bindable var voiceController = voiceController

    Form {
      Section("语音") {
        Picker("声音", selection: voiceSelection) {
          Text("自动（简体中文优先）").tag("")
          ForEach(voiceController.availableVoices) { voice in
            Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
          }
        }
        .accessibilityHint("优先使用你选择的声音，不可用时自动回退")

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
        Text("朗读由 macOS 系统语音完成。文字不会发送给第三方 TTS 服务，也不会保存为音频文件。")
          .font(.callout)
          .foregroundStyle(.secondary)
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
  private var window: NSWindow?

  init(voiceController: VoiceController) {
    self.voiceController = voiceController
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
      rootView: VoiceDebugView(voiceController: voiceController)
    )
    window.center()
    self.window = window
  }
}
