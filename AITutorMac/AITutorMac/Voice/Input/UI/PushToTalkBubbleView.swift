import AppKit
import SwiftUI

@MainActor
struct PushToTalkBubbleView: View {
  let speechInputController: SpeechInputController
  let tutorNotification: PetTutorNotification?
  let onOpenTutor: () -> Void

  var body: some View {
    @Bindable var speechInputController = speechInputController

    BubbleChrome {
      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        if let tutorNotification,
           !speechInputController.isInteractionActive {
          tutorReadyContent(tutorNotification)
          Divider()
        }

        HStack(spacing: AppSpacing.xs) {
          Image(systemName: headerSymbol)
            .foregroundStyle(headerColor)
          Text(headerTitle)
            .font(AppTypography.bubbleTitle)
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
    }
    .padding(AppSpacing.xxs)
  }

  private func tutorReadyContent(
    _ notification: PetTutorNotification
  ) -> some View {
    HStack(alignment: .center, spacing: 9) {
      Image(systemName: "sparkles")
        .foregroundStyle(.purple)
      VStack(alignment: .leading, spacing: 2) {
        Text("解释已经准备好了")
          .font(AppTypography.bubbleTitle)
        Text(notification.message)
          .font(AppTypography.bubbleBody)
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
        .font(AppTypography.bubbleBody)
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
        .font(AppTypography.bubbleBody)
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
        .font(AppTypography.bubbleBody)
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

      HStack(spacing: AppSpacing.xs) {
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
      .font(.callout)
    }
  }

  private var pushToTalkControl: some View {
    ZStack {
      RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        .fill(
          speechInputController.state == .listening
            ? AppColors.listeningAttention
            : AppColors.brand
        )

      Label(
        speechInputController.state == .listening ? "松开结束" : pushToTalkLabel,
        systemImage: speechInputController.state == .listening
          ? "mic.fill"
          : "mic"
      )
      .font(AppTypography.bubbleBody.weight(.semibold))
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
    .accessibilityValue(pushToTalkAccessibilityValue)
    .accessibilityHint("按住或按住空格键说话；VoiceOver 操作可开始，再次操作结束")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default) {
      togglePushToTalkForAccessibility()
    }
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

  private var pushToTalkAccessibilityValue: String {
    speechInputController.state == .listening ? "正在听，再次操作结束" : "未在听，操作后开始"
  }

  private func togglePushToTalkForAccessibility() {
    guard isPushToTalkEnabled else { return }
    if speechInputController.state == .listening {
      speechInputController.endPushToTalk()
    } else {
      speechInputController.beginPushToTalk()
    }
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
    speechInputController.state == .listening
      ? AppColors.listeningAttention
      : AppColors.stateActive
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
  override var focusRingMaskBounds: NSRect { bounds }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    focusRingType = .default
    setAccessibilityElement(false)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    focusRingType = .default
    setAccessibilityElement(false)
  }

  override func drawFocusRingMask() {
    NSBezierPath(
      roundedRect: bounds.insetBy(dx: 2, dy: 2),
      xRadius: AppRadius.control,
      yRadius: AppRadius.control
    ).fill()
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled, !isHolding else {
      return
    }
    window?.makeFirstResponder(self)
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

  override func keyDown(with event: NSEvent) {
    guard isSpaceKey(event) else {
      super.keyDown(with: event)
      return
    }
    guard isEnabled, !isHolding, !event.isARepeat else { return }
    isHolding = true
    onPress?()
  }

  override func keyUp(with event: NSEvent) {
    guard isSpaceKey(event) else {
      super.keyUp(with: event)
      return
    }
    releaseIfNeeded()
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { needsDisplay = true }
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    releaseIfNeeded()
    let resigned = super.resignFirstResponder()
    if resigned { needsDisplay = true }
    return resigned
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

  private func isSpaceKey(_ event: NSEvent) -> Bool {
    event.keyCode == 49 || event.charactersIgnoringModifiers == " "
  }
}
