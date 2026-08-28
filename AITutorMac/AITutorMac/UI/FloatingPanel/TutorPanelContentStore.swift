import Foundation
import Observation

enum TutorPanelActionAvailability: Equatable, Sendable {
  case available
  case unavailable(message: String)

  var isAvailable: Bool {
    if case .available = self {
      return true
    }
    return false
  }

  var unavailableMessage: String? {
    guard case let .unavailable(message) = self else {
      return nil
    }
    return message
  }
}

struct TutorPanelErrorPresentation: Equatable, Sendable {
  static let noStableContent = TutorPanelErrorPresentation(
    title: "没有读到当前窗口内容",
    message: "请先切回要解释的应用，保持内容窗口打开，然后再试一次。"
  )

  static let ambiguousContent = TutorPanelErrorPresentation(
    title: "请先点一下要解释的内容",
    message: "我现在看到页面里有几段不同的内容，请点一下或选中你想让我解释的那一段。"
  )

  static let modelNotConfigured = TutorPanelErrorPresentation(
    title: "还没有配置教学模型",
    message: "请先在 AI 模型设置中配置模型服务。",
    recoveryAction: .openModelSettings
  )

  static let accessibilityPermissionRequired = TutorPanelErrorPresentation(
    title: "需要重新开启辅助功能权限",
    message: "请在系统设置中将 AITutorMac 的辅助功能权限关闭后重新开启，然后回到目标应用再试一次。",
    recoveryAction: .openAccessibilitySettings
  )

  static let requestFailed = TutorPanelErrorPresentation(
    title: "这次解释没有成功",
    message: "可以再试一次。"
  )

  let title: String
  let message: String
  let recoveryAction: TutorPanelErrorRecoveryAction

  init(
    title: String,
    message: String,
    recoveryAction: TutorPanelErrorRecoveryAction = .retry
  ) {
    self.title = Self.visibleText(title) ?? "这次解释没有成功"
    self.message = Self.visibleText(message) ?? "可以再试一次。"
    self.recoveryAction = recoveryAction
  }

  private static func visibleText(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

enum TutorPanelErrorRecoveryAction: Equatable, Sendable {
  case retry
  case openModelSettings
  case openAccessibilitySettings
}

enum TutorPanelState: Equatable, Sendable {
  case empty(availability: TutorPanelActionAvailability)
  case loading
  case presentation(TutorPresentationModel)
  case error(TutorPanelErrorPresentation)
}

/// Ephemeral UI state for the Tutor Panel. It intentionally has no request,
/// response, prompt, source body, provider, or history field.
@MainActor
@Observable
final class TutorPanelContentStore {
  private(set) var state: TutorPanelState

  @ObservationIgnored
  var onPresentationIDChange: (@MainActor (UUID?) -> Void)?

  private var emptyAvailability: TutorPanelActionAvailability

  init(
    availability: TutorPanelActionAvailability = .unavailable(
      message: "当前版本尚未连接解释服务。"
    )
  ) {
    emptyAvailability = availability
    state = .empty(availability: availability)
  }

  func setLoading() {
    updateState(.loading)
  }

  func setAvailability(_ availability: TutorPanelActionAvailability) {
    emptyAvailability = availability
    if case .empty = state {
      updateState(.empty(availability: availability))
    }
  }

  func present(_ presentation: TutorPresentationModel) {
    updateState(.presentation(presentation))
  }

  func presentError(
    _ error: TutorPanelErrorPresentation = .requestFailed
  ) {
    updateState(.error(error))
  }

  func clear() {
    updateState(.empty(availability: emptyAvailability))
  }

  private func updateState(_ newState: TutorPanelState) {
    state = newState
    if case let .presentation(presentation) = newState {
      onPresentationIDChange?(presentation.responseMetadata.responseID)
    } else {
      onPresentationIDChange?(nil)
    }
  }
}
