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
    title: "还没有可解释的内容",
    message: "我现在还没有检测到可以解释的新内容。"
  )

  static let modelNotConfigured = TutorPanelErrorPresentation(
    title: "还没有配置教学模型",
    message: "请先在 Tutor Debug 的 Real LLM Demo 中配置模型服务。"
  )

  static let requestFailed = TutorPanelErrorPresentation(
    title: "这次解释没有成功",
    message: "可以再试一次。"
  )

  let title: String
  let message: String

  init(title: String, message: String) {
    self.title = Self.visibleText(title) ?? "这次解释没有成功"
    self.message = Self.visibleText(message) ?? "可以再试一次。"
  }

  private static func visibleText(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
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

  private let emptyAvailability: TutorPanelActionAvailability

  init(
    availability: TutorPanelActionAvailability = .unavailable(
      message: "当前版本尚未连接解释服务。"
    )
  ) {
    emptyAvailability = availability
    state = .empty(availability: availability)
  }

  func setLoading() {
    state = .loading
  }

  func present(_ presentation: TutorPresentationModel) {
    state = .presentation(presentation)
  }

  func presentError(
    _ error: TutorPanelErrorPresentation = .requestFailed
  ) {
    state = .error(error)
  }

  func clear() {
    state = .empty(availability: emptyAvailability)
  }
}
