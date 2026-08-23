import AppKit
import ApplicationServices
import Observation

protocol AccessibilityTrustProviding {
  func isTrusted() -> Bool
  func requestSystemPrompt()
}
struct SystemAccessibilityTrustProvider: AccessibilityTrustProviding {
  func isTrusted() -> Bool {
    AXIsProcessTrusted()
  }

  func requestSystemPrompt() {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
    ] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
  }
}

@MainActor
@Observable
final class AccessibilityAuthorizationController {
  static let permissionExplanation = """
    花花老师使用 macOS 辅助功能权限，读取你正在使用的 AI 应用中已经显示在界面上的文字。

    它不会自动点击、自动输入、修改其他 App、控制鼠标或执行任何操作。
    """

  private(set) var permissionState: AccessibilityPermissionState
  private(set) var isShowingPermissionExplanation = false

  @ObservationIgnored private let trustProvider: AccessibilityTrustProviding
  @ObservationIgnored private let settingsOpener: () -> Void
  @ObservationIgnored private var hasPromptedThisSession = false

  init(
    trustProvider: AccessibilityTrustProviding = SystemAccessibilityTrustProvider(),
    settingsOpener: @escaping () -> Void = AccessibilityAuthorizationController
      .openAccessibilitySettings
  ) {
    self.trustProvider = trustProvider
    self.settingsOpener = settingsOpener
    permissionState = trustProvider.isTrusted() ? .granted : .notGranted
  }

  func refreshState() {
    permissionState = trustProvider.isTrusted() ? .granted : .notGranted
    if permissionState == .granted {
      isShowingPermissionExplanation = false
    }
  }

  func beginPermissionRequest() {
    refreshState()
    guard permissionState != .granted else {
      return
    }
    isShowingPermissionExplanation = true
  }

  func cancelPermissionRequest() {
    isShowingPermissionExplanation = false
  }

  func continuePermissionRequest() {
    guard isShowingPermissionExplanation else {
      return
    }

    isShowingPermissionExplanation = false
    if !hasPromptedThisSession {
      hasPromptedThisSession = true
      trustProvider.requestSystemPrompt()
    }
    refreshState()
  }

  func openSystemSettings() {
    settingsOpener()
  }

  nonisolated private static func openAccessibilitySettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
