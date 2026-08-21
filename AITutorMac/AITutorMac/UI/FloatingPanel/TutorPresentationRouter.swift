import Foundation

enum TutorPresentationRouteOrigin: Equatable, Sendable {
  case userInitiated
  case automatic
}

/// A future notification seam only. No Pet implementation is connected in
/// STEP 09-1.
typealias TutorFuturePetNotification = @MainActor @Sendable (
  TutorPresentationModel
) -> Void

/// Routes an already scheduled presentation into Panel UI state. It neither
/// creates lessons nor owns window visibility.
@MainActor
final class TutorPresentationRouter {
  private let contentStore: TutorPanelContentStore
  private let futurePetNotification: TutorFuturePetNotification?

  private(set) var activeSessionID: UUID?

  init(
    contentStore: TutorPanelContentStore,
    futurePetNotification: TutorFuturePetNotification? = nil
  ) {
    self.contentStore = contentStore
    self.futurePetNotification = futurePetNotification
  }

  func activateSession(_ sessionID: UUID) {
    activeSessionID = sessionID
  }

  func deactivateSession() {
    activeSessionID = nil
  }

  @discardableResult
  func route(
    _ presentation: TutorPresentationModel,
    origin: TutorPresentationRouteOrigin
  ) -> Bool {
    guard
      let activeSessionID,
      presentation.responseMetadata.sessionID == activeSessionID,
      Self.isValid(presentation)
    else {
      return false
    }

    contentStore.present(presentation)

    // A route never opens the window. Automatic needs-more-context results
    // also stay quiet instead of producing a future Pet notification.
    if origin == .automatic, presentation.outcome != .needsMoreContext {
      futurePetNotification?(presentation)
    }
    return true
  }

  private static func isValid(
    _ presentation: TutorPresentationModel
  ) -> Bool {
    guard
      presentation.responseMetadata.sequence > 0,
      hasVisibleText(presentation.title),
      hasVisibleText(presentation.plainExplanation)
    else {
      return false
    }

    switch presentation.outcome {
    case .lesson:
      return presentation.lessonMetadata != nil
    case .needsMoreContext, .blocked:
      return presentation.lessonMetadata == nil
    }
  }

  private static func hasVisibleText(_ value: String) -> Bool {
    value.contains(where: { !$0.isWhitespace })
  }
}
