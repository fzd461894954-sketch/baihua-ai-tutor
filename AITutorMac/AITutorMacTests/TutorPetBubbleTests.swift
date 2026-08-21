import XCTest

@testable import AITutorMac

@MainActor
final class TutorPetBubbleTests: XCTestCase {
  func testPanelVisibleRoutesPresentationWithoutPetBubble() {
    let fixture = makeRouterFixture(panelVisible: true)

    XCTAssertTrue(fixture.router.route(fixture.presentation, origin: .userInitiated))
    XCTAssertEqual(fixture.store.state, .presentation(fixture.presentation))
    XCTAssertFalse(fixture.center.hasUnreadTutorPresentation)
    XCTAssertTrue(fixture.renderer.presented.isEmpty)
  }

  func testPanelHiddenRoutesPresentationToTutorBubble() {
    let fixture = makeRouterFixture(panelVisible: false)

    XCTAssertTrue(fixture.router.route(fixture.presentation, origin: .userInitiated))

    XCTAssertTrue(fixture.center.hasUnreadTutorPresentation)
    XCTAssertEqual(fixture.renderer.presented.count, 1)
    XCTAssertEqual(
      fixture.center.latestSourcePresentationID,
      fixture.presentation.responseMetadata.responseID
    )
  }

  func testBubbleOpenActionOpensPanelAndMarksRead() {
    let center = TutorPetNotificationCenter(autoDismissDuration: 5)
    let renderer = RecordingTutorNotificationRenderer()
    center.attachRenderer(renderer)
    var panelOpenCount = 0
    center.onOpenTutor = { panelOpenCount += 1 }
    center.notify(makeNotification())

    XCTAssertTrue(center.openLatestTutor())

    XCTAssertEqual(panelOpenCount, 1)
    XCTAssertFalse(center.hasUnreadTutorPresentation)
    XCTAssertNil(center.visibleNotification)
  }

  func testBubbleOpenDoesNotRegenerateTutorRequest() {
    let fixture = makeRouterFixture(panelVisible: false)
    var panelOpenCount = 0
    let tutorRequestCount = 1
    fixture.center.onOpenTutor = { panelOpenCount += 1 }
    XCTAssertTrue(fixture.router.route(fixture.presentation, origin: .userInitiated))

    XCTAssertTrue(fixture.center.openLatestTutor())

    XCTAssertEqual(panelOpenCount, 1)
    XCTAssertEqual(tutorRequestCount, 1)
    XCTAssertEqual(fixture.store.state, .presentation(fixture.presentation))
  }

  func testDoubleClickEntryUsesLatestPresentationAndMarksRead() {
    let center = TutorPetNotificationCenter(autoDismissDuration: 5)
    var panelOpenCount = 0
    center.onOpenTutor = { panelOpenCount += 1 }
    center.notify(makeNotification())

    let didOpen = center.openLatestTutor()

    XCTAssertTrue(didOpen)
    XCTAssertEqual(panelOpenCount, 1)
    XCTAssertFalse(center.hasUnreadTutorPresentation)
    XCTAssertNotNil(center.latestNotification)
  }

  func testTutorBubbleAutoDismisses() async {
    let center = TutorPetNotificationCenter(autoDismissDuration: 0.02)
    let renderer = RecordingTutorNotificationRenderer()
    center.attachRenderer(renderer)
    let notification = makeNotification()
    center.notify(notification)

    try? await Task.sleep(nanoseconds: 60_000_000)

    XCTAssertNil(center.visibleNotification)
    XCTAssertEqual(renderer.dismissed, [notification.id])
  }

  func testUnreadSurvivesBubbleAutoDismissal() async {
    let center = TutorPetNotificationCenter(autoDismissDuration: 0.02)
    center.attachRenderer(RecordingTutorNotificationRenderer())
    center.notify(makeNotification())

    try? await Task.sleep(nanoseconds: 60_000_000)

    XCTAssertTrue(center.hasUnreadTutorPresentation)
    XCTAssertNotNil(center.latestNotification)
  }

  func testOpeningPanelClearsUnreadWithoutClearingLessonMetadata() {
    let center = TutorPetNotificationCenter(autoDismissDuration: 5)
    let notification = makeNotification()
    center.notify(notification)

    center.panelDidBecomeVisible()

    XCTAssertFalse(center.hasUnreadTutorPresentation)
    XCTAssertEqual(center.latestNotification, notification)
  }

  func testFloatingPanelVisibilityCallbackMarksNotificationRead() {
    let appState = AppState()
    let store = TutorPanelContentStore(availability: .available)
    let center = TutorPetNotificationCenter(autoDismissDuration: 5)
    let voiceController = VoiceController(petStateController: PetStateController())
    let tutorVoiceCoordinator = TutorVoiceCoordinator(voiceController: voiceController)
    let panel = FloatingPanelController(
      appState: appState,
      contentStore: store,
      actionHandler: TutorPanelActionHandler { _ in },
      tutorVoiceCoordinator: tutorVoiceCoordinator,
      onVisibilityChange: { isVisible in
        if isVisible {
          center.panelDidBecomeVisible()
        }
      }
    )
    center.notify(makeNotification())

    panel.show()

    XCTAssertTrue(appState.isPanelVisible)
    XCTAssertFalse(center.hasUnreadTutorPresentation)
    panel.stop()
  }

  func testNewResultReplacesOldNotification() {
    let center = TutorPetNotificationCenter(autoDismissDuration: 5)
    let renderer = RecordingTutorNotificationRenderer()
    center.attachRenderer(renderer)
    let first = makeNotification(message: "first")
    let second = makeNotification(message: "second")
    center.notify(first)

    center.notify(second)

    XCTAssertEqual(center.latestNotification, second)
    XCTAssertEqual(center.visibleNotification, second)
    XCTAssertEqual(renderer.presented, [first, second])
    XCTAssertEqual(renderer.dismissed, [first.id])
  }

  func testPetStateWarningHasPriorityOverTutorNotification() {
    XCTAssertGreaterThan(
      PetBubblePriority.automaticPriority(for: .warning) ?? .welcome,
      .tutorNotification
    )
    let center = TutorPetNotificationCenter(autoDismissDuration: 5)
    let renderer = RecordingTutorNotificationRenderer(activePriority: .safety)
    center.attachRenderer(renderer)

    center.notify(makeNotification())

    XCTAssertNil(center.visibleNotification)
    XCTAssertTrue(center.hasUnreadTutorPresentation)
  }

  func testActiveVoiceInputHasHighestPriority() {
    XCTAssertGreaterThan(PetBubblePriority.voiceInput, .safety)
    let center = TutorPetNotificationCenter(autoDismissDuration: 5)
    let renderer = RecordingTutorNotificationRenderer(activePriority: .voiceInput)
    center.attachRenderer(renderer)

    center.notify(makeNotification())

    XCTAssertNil(center.visibleNotification)
    XCTAssertTrue(center.hasUnreadTutorPresentation)
  }

  func testSessionInvalidationClearsNotificationState() {
    let fixture = makeRouterFixture(panelVisible: false)
    XCTAssertTrue(fixture.router.route(fixture.presentation, origin: .userInitiated))

    fixture.router.deactivateSession()

    XCTAssertNil(fixture.center.latestNotification)
    XCTAssertNil(fixture.center.visibleNotification)
    XCTAssertFalse(fixture.center.hasUnreadTutorPresentation)
  }

  func testNeedsMoreContextUsesHonestNotificationCopy() {
    let notification = TutorPetBubbleAdapter().makeNotification(
      from: TutorPanelPresentationFixtures.needsMoreContext
    )

    XCTAssertTrue(notification.message.contains("还不够完整"))
    XCTAssertFalse(notification.message.contains("解释好了"))
  }

  func testBlockedUsesNeutralNotificationWithoutTechnicalReason() {
    let notification = TutorPetBubbleAdapter().makeNotification(
      from: TutorPanelPresentationFixtures.blocked
    )

    XCTAssertEqual(notification.message, "这段内容暂时不能这样解释，点我查看。")
    XCTAssertFalse(notification.message.contains("privacy"))
  }

  func testErrorRouteUsesRetryNotificationWithoutTechnicalDetails() {
    let fixture = makeRouterFixture(panelVisible: false)

    fixture.router.routeError(.requestFailed, origin: .userInitiated)

    XCTAssertEqual(fixture.store.state, .error(.requestFailed))
    XCTAssertEqual(fixture.center.latestNotification?.message, "这次解释没有成功，点我重试。")
    XCTAssertNil(fixture.center.latestSourcePresentationID)
  }

  func testNoTutorResultLeavesExistingPetNotificationBehaviorUntouched() {
    let center = TutorPetNotificationCenter(autoDismissDuration: 5)
    let renderer = RecordingTutorNotificationRenderer()
    center.attachRenderer(renderer)

    XCTAssertNil(center.latestNotification)
    XCTAssertNil(center.visibleNotification)
    XCTAssertFalse(center.hasUnreadTutorPresentation)
    XCTAssertTrue(renderer.presented.isEmpty)
    XCTAssertEqual(PetBubble.automatic(for: .warning), .warning)
    XCTAssertEqual(PetBubble.automatic(for: .success), .success)
  }

  private func makeRouterFixture(panelVisible: Bool) -> RouterFixture {
    let store = TutorPanelContentStore(availability: .available)
    let center = TutorPetNotificationCenter(autoDismissDuration: 5)
    let renderer = RecordingTutorNotificationRenderer()
    center.attachRenderer(renderer)
    let presentation = TutorPanelPresentationFixtures.apiLesson
    let router = TutorPresentationRouter(
      contentStore: store,
      petNotificationSink: center,
      isPanelVisible: { panelVisible }
    )
    router.activateSession(presentation.responseMetadata.sessionID)
    return RouterFixture(
      store: store,
      center: center,
      renderer: renderer,
      router: router,
      presentation: presentation
    )
  }

  private func makeNotification(
    message: String = "我已经帮你解释好了。"
  ) -> PetTutorNotification {
    PetTutorNotification(
      id: UUID(),
      title: "花花老师",
      message: message,
      priority: .tutorNotification,
      sourcePresentationID: UUID()
    )
  }
}

@MainActor
private struct RouterFixture {
  let store: TutorPanelContentStore
  let center: TutorPetNotificationCenter
  let renderer: RecordingTutorNotificationRenderer
  let router: TutorPresentationRouter
  let presentation: TutorPresentationModel
}

@MainActor
private final class RecordingTutorNotificationRenderer: PetTutorNotificationRendering {
  let activePriority: PetBubblePriority?
  var presented: [PetTutorNotification] = []
  var dismissed: [UUID] = []

  init(activePriority: PetBubblePriority? = nil) {
    self.activePriority = activePriority
  }

  func presentTutorNotification(_ notification: PetTutorNotification) -> Bool {
    guard activePriority.map({ $0 > notification.priority }) != true else {
      return false
    }
    presented.append(notification)
    return true
  }

  func dismissTutorNotification(id: UUID) {
    dismissed.append(id)
  }
}
