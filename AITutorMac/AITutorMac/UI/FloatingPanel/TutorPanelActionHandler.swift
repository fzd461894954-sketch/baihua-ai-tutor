import Foundation

enum TutorPanelActionIntent: Equatable, Sendable {
  case explainCurrentContent
  case retryCurrentContent
  case dismissCurrentPresentation
  case openModelSettings
  case openAccessibilitySettings
  case playTutorVoice(TutorPresentationModel)
  case stopTutorVoice
#if DEBUG
  case showDebugFixture(TutorPanelDebugFixture)
#endif
}

/// Outbound-only UI contract. FloatingPanelView sends an intent and remains
/// unaware of Context, Coordinator, Prompt, Provider, or model execution.
@MainActor
struct TutorPanelActionHandler {
  private let handleIntent: @MainActor (TutorPanelActionIntent) -> Void

  init(
    handle: @escaping @MainActor (TutorPanelActionIntent) -> Void
  ) {
    handleIntent = handle
  }

  func handle(_ intent: TutorPanelActionIntent) {
    handleIntent(intent)
  }

  static let unavailable = TutorPanelActionHandler { _ in }
}

/// Input boundary for an explicitly initiated Tutor request. The Panel never
/// reads Context, prompts, providers, or raw model responses directly.
@MainActor
protocol TutorCurrentContentProviding: AnyObject {
  func currentSemanticChunk() throws -> SemanticChunk
}
