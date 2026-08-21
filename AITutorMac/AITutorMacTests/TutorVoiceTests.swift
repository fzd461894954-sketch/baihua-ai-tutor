import XCTest

@testable import AITutorMac

@MainActor
final class TutorVoiceTests: XCTestCase {
  func testLessonCreatesVoiceScriptFromPlainExplanation() throws {
    let presentation = TutorPanelPresentationFixtures.apiLesson

    let script = try XCTUnwrap(TutorVoicePresentationAdapter().makeScript(from: presentation))

    XCTAssertEqual(script.presentationID, presentation.responseMetadata.responseID)
    XCTAssertEqual(script.text, presentation.plainExplanation)
    XCTAssertEqual(script.language, "zh-CN")
  }

  func testDefaultScriptDoesNotReadSupplementaryLessonFields() throws {
    let presentation = TutorPanelPresentationFixtures.apiLesson

    let script = try XCTUnwrap(TutorVoicePresentationAdapter().makeScript(from: presentation))

    XCTAssertFalse(script.text.contains(presentation.keyPoints[0]))
    XCTAssertFalse(script.text.contains(presentation.terms[0].plainDefinition))
    XCTAssertFalse(script.text.contains(try XCTUnwrap(presentation.analogy)))
    XCTAssertFalse(script.text.contains(try XCTUnwrap(presentation.checkQuestion)))
  }

  func testShortExplanationAppendsAtMostThreeKeyPoints() throws {
    let presentation = copy(
      TutorPanelPresentationFixtures.apiLesson,
      explanation: "API 是软件间的约定。",
      keyPoints: ["要点一", "要点二", "要点三", "要点四"]
    )

    let script = try XCTUnwrap(TutorVoicePresentationAdapter().makeScript(from: presentation))

    XCTAssertTrue(script.text.contains("要点一"))
    XCTAssertTrue(script.text.contains("要点三"))
    XCTAssertFalse(script.text.contains("要点四"))
  }

  func testLongLessonIsClippedToProductLimit() throws {
    let script = try XCTUnwrap(
      TutorVoicePresentationAdapter().makeScript(from: TutorPanelPresentationFixtures.longLesson)
    )

    XCTAssertEqual(script.text.count, TutorVoicePresentationAdapter.defaultMaximumCharacterCount)
    XCTAssertTrue(script.text.hasSuffix("…"))
  }

  func testEmptyExplanationHasNoVoiceScript() {
    let presentation = copy(TutorPanelPresentationFixtures.apiLesson, explanation: " \n ")

    XCTAssertNil(TutorVoicePresentationAdapter().makeScript(from: presentation))
  }

  func testNeedsMoreContextHasNoVoiceScript() {
    XCTAssertNil(
      TutorVoicePresentationAdapter().makeScript(
        from: TutorPanelPresentationFixtures.needsMoreContext
      )
    )
  }

  func testBlockedHasNoVoiceScript() {
    XCTAssertNil(
      TutorVoicePresentationAdapter().makeScript(from: TutorPanelPresentationFixtures.blocked)
    )
  }

  func testPlayStartsOnlyAfterExplicitIntent() {
    let output = TutorVoiceOutputSpy()
    let coordinator = TutorVoiceCoordinator(voiceController: output)
    let presentation = TutorPanelPresentationFixtures.apiLesson

    coordinator.presentationDidChange(to: presentation.responseMetadata.responseID)
    XCTAssertTrue(output.spokenTexts.isEmpty)

    XCTAssertTrue(coordinator.play(presentation))
    XCTAssertEqual(output.spokenTexts, [presentation.plainExplanation])
    XCTAssertTrue(coordinator.isPlaying(presentation))
  }

  func testStopStopsActiveTutorPlayback() {
    let output = TutorVoiceOutputSpy()
    let coordinator = TutorVoiceCoordinator(voiceController: output)
    coordinator.play(TutorPanelPresentationFixtures.apiLesson)

    coordinator.stop()

    XCTAssertEqual(output.stopCount, 1)
    XCTAssertFalse(coordinator.isPlayingTutorVoice)
  }

  func testPresentationReplacementStopsOldSpeechWithoutAutoplayingNewLesson() {
    let output = TutorVoiceOutputSpy()
    let coordinator = TutorVoiceCoordinator(voiceController: output)
    coordinator.play(TutorPanelPresentationFixtures.apiLesson)

    coordinator.presentationDidChange(
      to: TutorPanelPresentationFixtures.minimalLesson.responseMetadata.responseID
    )

    XCTAssertEqual(output.stopCount, 1)
    XCTAssertEqual(output.spokenTexts.count, 1)
    XCTAssertFalse(coordinator.isPlayingTutorVoice)
  }

  func testNonPresentationStateStopsOldSpeech() {
    let output = TutorVoiceOutputSpy()
    let coordinator = TutorVoiceCoordinator(voiceController: output)
    coordinator.play(TutorPanelPresentationFixtures.apiLesson)

    coordinator.presentationDidChange(to: nil)

    XCTAssertEqual(output.stopCount, 1)
  }

  func testSamePresentationAndPanelClosePolicyKeepSpeechPlaying() {
    let output = TutorVoiceOutputSpy()
    let coordinator = TutorVoiceCoordinator(voiceController: output)
    let presentation = TutorPanelPresentationFixtures.apiLesson
    coordinator.play(presentation)

    coordinator.presentationDidChange(to: presentation.responseMetadata.responseID)

    XCTAssertEqual(output.stopCount, 0)
    XCTAssertTrue(coordinator.isPlaying(presentation))
  }

  func testNewVoiceReplacesOldVoiceWithoutQueue() {
    let pet = PetStateController()
    let synthesizer = TutorSpeechSynthesizerSpy()
    let voice = VoiceController(petStateController: pet, synthesizer: synthesizer)
    let coordinator = TutorVoiceCoordinator(voiceController: voice)

    coordinator.play(TutorPanelPresentationFixtures.apiLesson)
    coordinator.play(TutorPanelPresentationFixtures.minimalLesson)

    XCTAssertEqual(synthesizer.requests.count, 2)
    XCTAssertEqual(synthesizer.stopCount, 1)
    XCTAssertEqual(synthesizer.requests.last?.text,
                   TutorPanelPresentationFixtures.minimalLesson.plainExplanation)
    XCTAssertEqual(pet.currentState, .speaking)
  }

  func testCompletionClearsTutorOwnershipAndRestoresPreviousPetState() {
    let pet = PetStateController()
    pet.transition(to: .thinking)
    let synthesizer = TutorSpeechSynthesizerSpy()
    let voice = VoiceController(petStateController: pet, synthesizer: synthesizer)
    let coordinator = TutorVoiceCoordinator(voiceController: voice)
    coordinator.play(TutorPanelPresentationFixtures.apiLesson)

    XCTAssertEqual(pet.currentState, .speaking)
    synthesizer.finishLatest()

    XCTAssertEqual(pet.currentState, .thinking)
    XCTAssertFalse(coordinator.isPlayingTutorVoice)
    XCTAssertNil(coordinator.activePresentationID)
  }

  func testStoreEmitsOnlyPresentationIdentityForVoiceLifecycle() {
    let store = TutorPanelContentStore(availability: .available)
    var receivedIDs: [UUID?] = []
    store.onPresentationIDChange = { receivedIDs.append($0) }
    let presentation = TutorPanelPresentationFixtures.apiLesson

    store.present(presentation)
    store.setLoading()
    store.present(presentation)
    store.presentError()
    store.clear()

    XCTAssertEqual(receivedIDs, [
      presentation.responseMetadata.responseID,
      nil,
      presentation.responseMetadata.responseID,
      nil,
      nil,
    ])
  }

  private func copy(
    _ source: TutorPresentationModel,
    explanation: String? = nil,
    keyPoints: [String]? = nil
  ) -> TutorPresentationModel {
    TutorPresentationModel(
      responseMetadata: source.responseMetadata,
      outcome: source.outcome,
      lessonMetadata: source.lessonMetadata,
      title: source.title,
      plainExplanation: explanation ?? source.plainExplanation,
      keyPoints: keyPoints ?? source.keyPoints,
      terms: source.terms,
      analogy: source.analogy,
      example: source.example,
      checkQuestion: source.checkQuestion,
      caveats: source.caveats,
      suggestedAction: source.suggestedAction,
      blockReason: source.blockReason,
      didTruncateContent: source.didTruncateContent
    )
  }
}

@MainActor
private final class TutorVoiceOutputSpy: TutorVoiceOutputControlling {
  private(set) var status: VoicePlaybackStatus = .idle
  var isActive: Bool { status == .speaking || status == .paused }
  private(set) var spokenTexts: [String] = []
  private(set) var stopCount = 0
  private var observers: [UUID: @MainActor (VoicePlaybackStatus) -> Void] = [:]

  func speak(text: String) {
    spokenTexts.append(text)
    updateStatus(.speaking)
  }

  func stop() {
    stopCount += 1
    updateStatus(.idle)
  }

  func addStatusObserver(
    _ observer: @escaping @MainActor (VoicePlaybackStatus) -> Void
  ) -> UUID {
    let id = UUID()
    observers[id] = observer
    return id
  }

  func removeStatusObserver(_ observerID: UUID) {
    observers[observerID] = nil
  }

  private func updateStatus(_ newStatus: VoicePlaybackStatus) {
    status = newStatus
    observers.values.forEach { $0(newStatus) }
  }
}

@MainActor
private final class TutorSpeechSynthesizerSpy: SpeechSynthesizing {
  var availableVoices: [SpeechVoiceOption] = []
  var eventHandler: ((SpeechSynthesizerEvent) -> Void)?
  private(set) var requests: [SpeechRequest] = []
  private(set) var stopCount = 0
  private var activeRequestID: UUID?

  func speak(_ request: SpeechRequest) throws {
    requests.append(request)
    activeRequestID = request.id
    eventHandler?(.didStart(request.id))
  }

  func stop() -> Bool {
    stopCount += 1
    activeRequestID = nil
    return true
  }

  func pause() -> Bool { activeRequestID != nil }
  func `continue`() -> Bool { activeRequestID != nil }

  func finishLatest() {
    guard let activeRequestID else { return }
    self.activeRequestID = nil
    eventHandler?(.didFinish(activeRequestID))
  }
}
