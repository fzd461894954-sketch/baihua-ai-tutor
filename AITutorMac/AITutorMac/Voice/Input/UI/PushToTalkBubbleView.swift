import AppKit
import SwiftUI

@MainActor
struct PushToTalkBubbleView: View {
  let speechInputController: SpeechInputController
  let tutorNotification: PetTutorNotification?
  let onOpenTutor: () -> Void

  var body: some View {
    @Bindable var speechInputController = speechInputController

    VStack(alignment: .leading, spacing: 10) {
      if let tutorNotification,
         !speechInputController.isInteractionActive {
        tutorReadyContent(tutorNotification)
        Divider()
      }

      HStack(spacing: 7) {
        Image(systemName: headerSymbol)
          .foregroundStyle(headerColor)
        Text(headerTitle)
          .font(.system(size: 14, weight: .semibold))
        Spacer()
      }

      if speechInputController.isShowingPermissionExplanation {
        permissionExplanation
      } else if speechInputController.isShowingCloudConsent {
        cloudConsent
      } else {
        interactionContent
      }

#if DEBUG
      Text(debugStatus)
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(.tertiary)
#endif
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .stroke(.primary.opacity(0.08), lineWidth: 1)
    }
    .padding(5)
  }

  private func tutorReadyContent(
    _ notification: PetTutorNotification
  ) -> some View {
    HStack(alignment: .center, spacing: 9) {
      Image(systemName: "sparkles")
        .foregroundStyle(.purple)
      VStack(alignment: .leading, spacing: 2) {
        Text("解释已经准备好了")
          .font(.system(size: 12, weight: .semibold))
        Text(notification.message)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 4)
      Button("查看解释") {
        speechInputController.cancel()
        onOpenTutor()
      }
      .controlSize(.small)
    }
  }

  private var permissionExplanation: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(SpeechInputController.permissionExplanation)
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        Button("取消") {
          speechInputController.cancelPermissionExplanation()
        }
        Button("继续") {
          Task {
            await speechInputController.continuePermissionRequest()
          }
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private var cloudConsent: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(speechInputController.message ?? "")
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        Button("仅使用本机") {
          speechInputController.chooseAppleService(allowed: false)
        }
        Button("允许 Apple 语音识别") {
          speechInputController.chooseAppleService(allowed: true)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private var interactionContent: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(displayText)
        .font(.system(size: 12))
        .foregroundStyle(displayTextColor)
        .lineLimit(3)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

      if speechInputController.state == .denied {
        Button("打开系统设置") {
          speechInputController.openSystemSettings()
        }
      } else if speechInputController.state != .requestingPermission,
                speechInputController.state != .transcribing {
        pushToTalkControl
      }

      HStack(spacing: 8) {
        if speechInputController.state == .completed {
          Button("清除") {
            speechInputController.clear()
          }
        }

        Spacer()

        Button("打开教学窗口") {
          speechInputController.cancel()
          onOpenTutor()
        }
      }
      .font(.system(size: 11))
    }
  }

  private var pushToTalkControl: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(
          speechInputController.state == .listening
            ? Color.red.opacity(0.9)
            : Color.accentColor
        )

      Label(
        speechInputController.state == .listening ? "松开结束" : pushToTalkLabel,
        systemImage: speechInputController.state == .listening
          ? "mic.fill"
          : "mic"
      )
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)

      HoldToTalkCaptureView(
        isEnabled: isPushToTalkEnabled,
        onPress: speechInputController.beginPushToTalk,
        onRelease: speechInputController.endPushToTalk
      )
    }
    .frame(height: 34)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(pushToTalkLabel)
    .accessibilityHint("按住开始使用麦克风，松开结束")
  }

  private var isPushToTalkEnabled: Bool {
    switch speechInputController.state {
    case .requestingPermission, .transcribing, .denied:
      return false
    case .idle, .ready, .listening, .completed, .unavailable, .error:
      return !speechInputController.isShowingCloudConsent
    }
  }

  private var pushToTalkLabel: String {
    speechInputController.state == .completed ? "按住重新说" : "按住说话"
  }

  private var headerTitle: String {
    switch speechInputController.state {
    case .listening:
      return "正在听…"
    case .transcribing:
      return "正在整理文字…"
    case .completed:
      return "我听到了"
    case .denied:
      return "需要权限"
    case .unavailable, .error:
      return "这次没有听到"
    case .requestingPermission:
      return "正在请求权限…"
    case .idle, .ready:
      return "你好，我是你的 AI 老师。"
    }
  }

  private var headerSymbol: String {
    speechInputController.state == .listening ? "mic.fill" : "sparkles"
  }

  private var headerColor: Color {
    speechInputController.state == .listening ? .red : .purple
  }

  private var displayText: String {
    if !speechInputController.partialTranscript.isEmpty {
      return speechInputController.partialTranscript
    }
    if !speechInputController.finalTranscript.isEmpty {
      return speechInputController.finalTranscript
    }
    if let message = speechInputController.message {
      return message
    }
    switch speechInputController.state {
    case .listening:
      return "正在听你说话…"
    case .transcribing:
      return "麦克风已停止，正在等待最终文字。"
    default:
      return "按住下方按钮说话，松开后得到文字。"
    }
  }

  private var displayTextColor: Color {
    speechInputController.finalTranscript.isEmpty ? .secondary : .primary
  }

#if DEBUG
  private var debugStatus: String {
    let onDevice = speechInputController.onDeviceRecognitionSupported
      .map { $0 ? "yes" : "no" } ?? "unknown"
    return "state=\(speechInputController.state.rawValue) locale=\(speechInputController.selectedLocaleIdentifier) onDevice=\(onDevice)"
  }
#endif
}

private struct HoldToTalkCaptureView: NSViewRepresentable {
  let isEnabled: Bool
  let onPress: () -> Void
  let onRelease: () -> Void

  func makeNSView(context: Context) -> HoldToTalkCaptureNSView {
    let view = HoldToTalkCaptureNSView()
    view.onPress = onPress
    view.onRelease = onRelease
    view.isEnabled = isEnabled
    return view
  }

  func updateNSView(_ nsView: HoldToTalkCaptureNSView, context: Context) {
    nsView.onPress = onPress
    nsView.onRelease = onRelease
    nsView.isEnabled = isEnabled
  }

  static func dismantleNSView(
    _ nsView: HoldToTalkCaptureNSView,
    coordinator: Void
  ) {
    nsView.releaseIfNeeded()
  }
}

final class HoldToTalkCaptureNSView: NSView {
  var isEnabled = true {
    didSet {
      if !isEnabled {
        releaseIfNeeded()
      }
    }
  }
  var onPress: (() -> Void)?
  var onRelease: (() -> Void)?

  private var isHolding = false
  private var localMouseUpMonitor: Any?
  private var globalMouseUpMonitor: Any?

  override var acceptsFirstResponder: Bool { true }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled, !isHolding else {
      return
    }
    isHolding = true
    installReleaseMonitorsIfNeeded()
    onPress?()
  }

  override func mouseDragged(with event: NSEvent) {
    // The view keeps mouse capture until mouseUp, including outside its bounds.
  }

  override func mouseUp(with event: NSEvent) {
    releaseIfNeeded()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      releaseIfNeeded()
    }
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }

  func releaseIfNeeded() {
    guard isHolding else {
      return
    }
    isHolding = false
    removeReleaseMonitors()
    onRelease?()
  }

  private func installReleaseMonitorsIfNeeded() {
    guard window != nil,
          localMouseUpMonitor == nil,
          globalMouseUpMonitor == nil else {
      return
    }

    localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) {
      [weak self] event in
      self?.releaseIfNeeded()
      return event
    }
    globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) {
      [weak self] _ in
      DispatchQueue.main.async {
        self?.releaseIfNeeded()
      }
    }
  }

  private func removeReleaseMonitors() {
    if let localMouseUpMonitor {
      NSEvent.removeMonitor(localMouseUpMonitor)
      self.localMouseUpMonitor = nil
    }
    if let globalMouseUpMonitor {
      NSEvent.removeMonitor(globalMouseUpMonitor)
      self.globalMouseUpMonitor = nil
    }
  }
}
