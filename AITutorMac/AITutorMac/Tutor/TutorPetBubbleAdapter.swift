import Foundation
import Observation

enum PetBubblePriority: Int, Comparable, Equatable, Sendable {
  case welcome
  case tutorNotification
  case safety
  case voiceInput

  static func < (lhs: PetBubblePriority, rhs: PetBubblePriority) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  static func automaticPriority(for state: PetState) -> PetBubblePriority? {
    switch state {
    case .needsInput, .warning, .success, .error:
      return .safety
    case .idle, .watching, .thinking, .speaking:
      return nil
    }
  }
}

struct PetTutorNotification: Equatable, Sendable {
  let id: UUID
  let title: String
  let message: String
  let priority: PetBubblePriority
  let sourcePresentationID: UUID?
}

struct TutorPetBubbleAdapter: Sendable {
  private let maximumTitleCharacters = 18

  func makeNotification(
    from presentation: TutorPresentationModel
  ) -> PetTutorNotification {
    let message: String
    switch presentation.outcome {
    case .lesson:
      let title = shortTitle(presentation.title)
      message = "我已经帮你讲清楚「\(title)」了，点我查看。"
    case .needsMoreContext:
      message = "这段内容还不够完整，点我看看原因。"
    case .blocked:
      message = "这段内容暂时不能这样解释，点我查看。"
    }

    return PetTutorNotification(
      id: UUID(),
      title: "花花老师",
      message: message,
      priority: .tutorNotification,
      sourcePresentationID: presentation.responseMetadata.responseID
    )
  }

  func makeErrorNotification() -> PetTutorNotification {
    PetTutorNotification(
      id: UUID(),
      title: "花花老师",
      message: "这次解释没有成功，点我重试。",
      priority: .tutorNotification,
      sourcePresentationID: nil
    )
  }

  private func shortTitle(_ value: String) -> String {
    let collapsed = value
      .split(whereSeparator: \Character.isWhitespace)
      .joined(separator: " ")
    let fallback = collapsed.isEmpty ? "这段内容" : collapsed
    guard fallback.count > maximumTitleCharacters else {
      return fallback
    }
    return String(fallback.prefix(maximumTitleCharacters)) + "…"
  }
}

@MainActor
protocol TutorPetNotifying: AnyObject {
  func notify(_ notification: PetTutorNotification)
  func clearTutorNotification()
}

@MainActor
protocol PetTutorNotificationRendering: AnyObject {
  @discardableResult
  func presentTutorNotification(_ notification: PetTutorNotification) -> Bool
  func dismissTutorNotification(id: UUID)
}

/// Keeps only lightweight notification metadata. The full lesson remains in
/// TutorPanelContentStore and is never copied into the Pet layer.
@MainActor
@Observable
final class TutorPetNotificationCenter: TutorPetNotifying {
  private(set) var latestNotification: PetTutorNotification?
  private(set) var visibleNotification: PetTutorNotification?
  private(set) var hasUnreadTutorPresentation = false

  var latestNotificationID: UUID? { latestNotification?.id }
  var latestSourcePresentationID: UUID? {
    latestNotification?.sourcePresentationID
  }
  var latestPriority: PetBubblePriority? { latestNotification?.priority }

  @ObservationIgnored private weak var renderer: (any PetTutorNotificationRendering)?
  @ObservationIgnored private let autoDismissDuration: TimeInterval
  @ObservationIgnored private var autoDismissTask: Task<Void, Never>?
  @ObservationIgnored var onOpenTutor: (@MainActor () -> Void)?

  init(autoDismissDuration: TimeInterval = 5) {
    self.autoDismissDuration = max(0.01, autoDismissDuration)
  }

  deinit {
    autoDismissTask?.cancel()
  }

  func attachRenderer(_ renderer: any PetTutorNotificationRendering) {
    self.renderer = renderer
  }

  func notify(_ notification: PetTutorNotification) {
    dismissVisiblePreservingUnread()
    latestNotification = notification
    hasUnreadTutorPresentation = true

    guard renderer?.presentTutorNotification(notification) == true else {
      return
    }
    visibleNotification = notification
    scheduleAutoDismiss(for: notification.id)
    AppLogger.pet.info(
      "Tutor Pet notification shown priority=\(notification.priority.rawValue, privacy: .public)"
    )
  }

  func clearTutorNotification() {
    autoDismissTask?.cancel()
    autoDismissTask = nil
    if let visibleNotification {
      renderer?.dismissTutorNotification(id: visibleNotification.id)
    }
    visibleNotification = nil
    latestNotification = nil
    hasUnreadTutorPresentation = false
  }

  func dismissVisiblePreservingUnread() {
    autoDismissTask?.cancel()
    autoDismissTask = nil
    guard let visibleNotification else {
      return
    }
    self.visibleNotification = nil
    renderer?.dismissTutorNotification(id: visibleNotification.id)
  }

  func markRead() {
    dismissVisiblePreservingUnread()
    hasUnreadTutorPresentation = false
  }

  func panelDidBecomeVisible() {
    markRead()
  }

  @discardableResult
  func openLatestTutor() -> Bool {
    guard latestNotification != nil else {
      return false
    }
    markRead()
    onOpenTutor?()
    return true
  }

  private func scheduleAutoDismiss(for notificationID: UUID) {
    autoDismissTask?.cancel()
    let nanoseconds = UInt64(autoDismissDuration * 1_000_000_000)
    autoDismissTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: nanoseconds)
      } catch {
        return
      }
      guard let self,
            self.visibleNotification?.id == notificationID else {
        return
      }
      self.visibleNotification = nil
      self.autoDismissTask = nil
      self.renderer?.dismissTutorNotification(id: notificationID)
      AppLogger.pet.debug("Tutor Pet notification auto-dismissed")
    }
  }
}
