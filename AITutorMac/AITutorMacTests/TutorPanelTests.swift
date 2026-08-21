import XCTest
@testable import AITutorMac

@MainActor
final class TutorPanelTests: XCTestCase {
  func testStoreMovesThroughLoadingPresentationErrorAndClear() {
    let store = TutorPanelContentStore(availability: .available)
    XCTAssertEqual(store.state, .empty(availability: .available))

    store.setLoading()
    XCTAssertEqual(store.state, .loading)

    store.present(TutorPanelPresentationFixtures.apiLesson)
    XCTAssertEqual(store.state, .presentation(TutorPanelPresentationFixtures.apiLesson))

    store.presentError()
    XCTAssertEqual(store.state, .error(.requestFailed))

    store.clear()
    XCTAssertEqual(store.state, .empty(availability: .available))
  }

  func testReleaseStyleStoreRestoresUnavailableEmptyState() {
    let availability = TutorPanelActionAvailability.unavailable(message: "未连接")
    let store = TutorPanelContentStore(availability: availability)
    store.setLoading()
    store.clear()
    XCTAssertEqual(store.state, .empty(availability: availability))
  }

  func testLessonFixturesCoverFullMinimalAndLongVariants() {
    let full = TutorPanelPresentationFixtures.apiLesson
    XCTAssertEqual(full.outcome, .lesson)
    XCTAssertFalse(full.keyPoints.isEmpty)
    XCTAssertNotNil(full.analogy)
    XCTAssertNotNil(full.example)
    XCTAssertNotNil(full.checkQuestion)
    XCTAssertFalse(full.terms.isEmpty)

    let minimal = TutorPanelPresentationFixtures.minimalLesson
    XCTAssertTrue(minimal.keyPoints.isEmpty)
    XCTAssertTrue(minimal.terms.isEmpty)
    XCTAssertNil(minimal.analogy)
    XCTAssertNil(minimal.example)
    XCTAssertNil(minimal.checkQuestion)

    let long = TutorPanelPresentationFixtures.longLesson
    XCTAssertTrue(long.didTruncateContent)
    XCTAssertEqual(long.keyPoints.count, TutorPresentationLimits.default.maximumKeyPoints)
    XCTAssertEqual(long.terms.count, TutorPresentationLimits.default.maximumTerms)
    XCTAssertEqual(long.caveats.count, TutorPresentationLimits.default.maximumCaveats)
  }

  func testGlossaryDefaultsToFolded() {
    XCTAssertFalse(TutorPanelLayoutPolicy.glossaryStartsExpanded)
  }

  func testNonLessonFixturesContainOnlyStatusPresentationFields() {
    let needsMore = TutorPanelPresentationFixtures.needsMoreContext
    XCTAssertEqual(needsMore.outcome, .needsMoreContext)
    XCTAssertNotNil(needsMore.suggestedAction)
    XCTAssertNil(needsMore.lessonMetadata)

    let blocked = TutorPanelPresentationFixtures.blocked
    XCTAssertEqual(blocked.outcome, .blocked)
    XCTAssertEqual(blocked.blockReason, .privacyRisk)
    XCTAssertNil(blocked.lessonMetadata)
  }

  func testActionHandlerForwardsEveryRequiredIntent() {
    var received: [TutorPanelActionIntent] = []
    let handler = TutorPanelActionHandler { received.append($0) }

    handler.handle(.explainCurrentContent)
    handler.handle(.retryCurrentContent)
    handler.handle(.dismissCurrentPresentation)
    handler.handle(.playTutorVoice(TutorPanelPresentationFixtures.apiLesson))
    handler.handle(.stopTutorVoice)

    XCTAssertEqual(received, [
      .explainCurrentContent,
      .retryCurrentContent,
      .dismissCurrentPresentation,
      .playTutorVoice(TutorPanelPresentationFixtures.apiLesson),
      .stopTutorVoice,
    ])
  }

  func testRouterAcceptsActiveSessionWithoutOwningWindow() {
    let store = TutorPanelContentStore(availability: .available)
    let presentation = TutorPanelPresentationFixtures.apiLesson
    let router = TutorPresentationRouter(contentStore: store)
    router.activateSession(presentation.responseMetadata.sessionID)

    XCTAssertTrue(router.route(presentation, origin: .userInitiated))
    XCTAssertEqual(store.state, .presentation(presentation))
  }

  func testRouterRejectsOldSessionAndMalformedPresentation() {
    let store = TutorPanelContentStore(availability: .available)
    let presentation = TutorPanelPresentationFixtures.apiLesson
    let router = TutorPresentationRouter(contentStore: store)
    router.activateSession(UUID())

    XCTAssertFalse(router.route(presentation, origin: .userInitiated))
    XCTAssertEqual(store.state, .empty(availability: .available))

    router.activateSession(presentation.responseMetadata.sessionID)
    let malformed = copy(presentation, title: "   ", sequence: 0)
    XCTAssertFalse(router.route(malformed, origin: .userInitiated))
    XCTAssertEqual(store.state, .empty(availability: .available))
  }

  func testAutomaticNeedsMoreContextRoutesQuietly() {
    let store = TutorPanelContentStore(availability: .available)
    let presentation = TutorPanelPresentationFixtures.needsMoreContext
    let notifier = RecordingTutorPetNotifier()
    let router = TutorPresentationRouter(
      contentStore: store,
      petNotificationSink: notifier
    )
    router.activateSession(presentation.responseMetadata.sessionID)

    XCTAssertTrue(router.route(presentation, origin: .automatic))
    XCTAssertTrue(notifier.notifications.isEmpty)
    XCTAssertEqual(store.state, .presentation(presentation))
  }

  private func copy(
    _ value: TutorPresentationModel,
    title: String,
    sequence: Int
  ) -> TutorPresentationModel {
    let metadata = TutorPresentationResponseMetadata(
      responseID: value.responseMetadata.responseID,
      requestID: value.responseMetadata.requestID,
      sessionID: value.responseMetadata.sessionID,
      sequence: sequence,
      sourceChunkID: value.responseMetadata.sourceChunkID,
      createdAt: value.responseMetadata.createdAt
    )
    return TutorPresentationModel(
      responseMetadata: metadata,
      outcome: value.outcome,
      lessonMetadata: value.lessonMetadata,
      title: title,
      plainExplanation: value.plainExplanation,
      keyPoints: value.keyPoints,
      terms: value.terms,
      analogy: value.analogy,
      example: value.example,
      checkQuestion: value.checkQuestion,
      caveats: value.caveats,
      suggestedAction: value.suggestedAction,
      blockReason: value.blockReason,
      didTruncateContent: value.didTruncateContent
    )
  }
}

@MainActor
private final class RecordingTutorPetNotifier: TutorPetNotifying {
  var notifications: [PetTutorNotification] = []
  var clearCount = 0

  func notify(_ notification: PetTutorNotification) {
    notifications.append(notification)
  }

  func clearTutorNotification() {
    clearCount += 1
  }
}
