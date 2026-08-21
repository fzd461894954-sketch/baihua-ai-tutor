import Foundation

enum TutorPresentationRouteOrigin: Equatable, Sendable {
  case userInitiated
  case automatic
}

/// Routes an already scheduled presentation into Panel UI state. It neither
/// creates lessons nor owns window visibility.
@MainActor
final class TutorPresentationRouter {
  private let contentStore: TutorPanelContentStore
  private let petNotificationSink: (any TutorPetNotifying)?
  private let petBubbleAdapter: TutorPetBubbleAdapter
  private let isPanelVisible: @MainActor () -> Bool

  private(set) var activeSessionID: UUID?

  init(
    contentStore: TutorPanelContentStore,
    petNotificationSink: (any TutorPetNotifying)? = nil,
    petBubbleAdapter: TutorPetBubbleAdapter = TutorPetBubbleAdapter(),
    isPanelVisible: @escaping @MainActor () -> Bool = { false }
  ) {
    self.contentStore = contentStore
    self.petNotificationSink = petNotificationSink
    self.petBubbleAdapter = petBubbleAdapter
    self.isPanelVisible = isPanelVisible
  }

  func activateSession(_ sessionID: UUID) {
    if activeSessionID != sessionID {
      petNotificationSink?.clearTutorNotification()
    }
    activeSessionID = sessionID
  }

  func deactivateSession() {
    activeSessionID = nil
    petNotificationSink?.clearTutorNotification()
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

    // A route never opens the window. STEP 09-3 only notifies for an explicit
    // user request that completed while the full Panel was hidden.
    if origin == .userInitiated, !isPanelVisible() {
      petNotificationSink?.notify(
        petBubbleAdapter.makeNotification(from: presentation)
      )
    }
    return true
  }

  func routeError(
    _ error: TutorPanelErrorPresentation,
    origin: TutorPresentationRouteOrigin
  ) {
    contentStore.presentError(error)
    if origin == .userInitiated, !isPanelVisible() {
      petNotificationSink?.notify(petBubbleAdapter.makeErrorNotification())
    }
  }

  func clearTutorNotification() {
    petNotificationSink?.clearTutorNotification()
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
