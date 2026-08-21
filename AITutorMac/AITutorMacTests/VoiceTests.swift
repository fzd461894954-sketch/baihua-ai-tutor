import AppKit
import XCTest

@testable import AITutorMac

@MainActor
final class VoiceTests: XCTestCase {
  func testDefaultSpeechConfigurationUsesTeachingFriendlySafeValues() {
    let configuration = SpeechConfiguration.default

    XCTAssertNil(configuration.voiceIdentifier)
    XCTAssertEqual(configuration.rate, 0.46, accuracy: 0.0001)
    XCTAssertEqual(configuration.pitch, 1, accuracy: 0.0001)
    XCTAssertEqual(configuration.volume, 1, accuracy: 0.0001)
    XCTAssertTrue(SpeechConfiguration.rateRange.contains(configuration.rate))
    XCTAssertTrue(SpeechConfiguration.pitchRange.contains(configuration.pitch))
    XCTAssertTrue(SpeechConfiguration.volumeRange.contains(configuration.volume))
  }

  func testPreferencesPersistAndClampWithoutSpeechText() throws {
    let suiteName = "VoiceTests.Preferences.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = VoicePreferencesStore(defaults: defaults)

    store.save(
      SpeechConfiguration(
        voiceIdentifier: "voice.selected",
        rate: 99,
        pitch: -2,
        volume: 0.6
      )
    )
    let restored = store.load()

    XCTAssertEqual(restored.voiceIdentifier, "voice.selected")
    XCTAssertEqual(restored.rate, SpeechConfiguration.rateRange.upperBound)
    XCTAssertEqual(restored.pitch, SpeechConfiguration.pitchRange.lowerBound)
    XCTAssertEqual(restored.volume, 0.6, accuracy: 0.0001)
    XCTAssertNil(defaults.object(forKey: "voice.preferences.text"))
  }

  func testVoiceSelectionUsesChosenThenChineseThenSystemDefault() {
    let voices = [
      SpeechVoiceOption(identifier: "english", name: "English", language: "en-US"),
      SpeechVoiceOption(identifier: "chinese", name: "Chinese", language: "zh-CN"),
    ]

    XCTAssertEqual(
      SpeechConfiguration.resolvedVoiceIdentifier(
        preferredIdentifier: "english",
        availableVoices: voices
      ),
      "english"
    )
    XCTAssertEqual(
      SpeechConfiguration.resolvedVoiceIdentifier(
        preferredIdentifier: "missing",
        availableVoices: voices
      ),
      "chinese"
    )
    XCTAssertNil(
      SpeechConfiguration.resolvedVoiceIdentifier(
        preferredIdentifier: "missing",
        availableVoices: [voices[0]]
      )
    )
  }

  func testSpeakTransitionsToSpeakingAndCompletionRestoresPreviousState() throws {
    let (voice, speech, pet) = makeVoice(startingAt: .thinking)

    voice.speak(text: "它正在检查数据库权限，你暂时不用操作。")

    XCTAssertEqual(pet.currentState, .speaking)
    XCTAssertEqual(voice.status, .speaking)
    XCTAssertEqual(speech.requests.count, 1)
    speech.finishLatest()

    XCTAssertEqual(pet.currentState, .thinking)
    XCTAssertEqual(voice.status, .idle)
  }

  func testStopImmediatelyRestoresPreviousState() {
    let (voice, speech, pet) = makeVoice(startingAt: .warning)
    voice.speak(text: String(repeating: "这是一个很长的测试句。", count: 20))

    voice.stop()

    XCTAssertEqual(speech.stopCount, 1)
    XCTAssertEqual(pet.currentState, .warning)
    XCTAssertEqual(voice.status, .idle)
    XCTAssertFalse(voice.isActive)
  }

  func testRepeatedSpeakReplacesOldRequestAndRestoresOriginalState() {
    let (voice, speech, pet) = makeVoice(startingAt: .needsInput)

    voice.speak(text: "A speaking")
    let firstRequest = speech.requests[0]
    voice.speak(text: "B speaking")

    XCTAssertEqual(speech.stopCount, 1)
    XCTAssertEqual(speech.requests.count, 2)
    XCTAssertEqual(speech.requests.last?.text, "B speaking")
    XCTAssertEqual(pet.currentState, .speaking)

    speech.send(.didCancel(firstRequest.id))
    XCTAssertEqual(pet.currentState, .speaking)
    speech.finishLatest()
    XCTAssertEqual(pet.currentState, .needsInput)
  }

  func testThirtySpeakCallsDoNotQueueAndDoNotLockSpeakingState() {
    let (voice, speech, pet) = makeVoice(startingAt: .thinking)

    for index in 0..<30 {
      voice.speak(text: "request \(index)")
      XCTAssertEqual(pet.currentState, .speaking)
    }

    XCTAssertEqual(speech.requests.count, 30)
    XCTAssertEqual(speech.stopCount, 29)
    XCTAssertEqual(speech.maximumActiveRequestCount, 1)

    speech.finishLatest()
    XCTAssertEqual(pet.currentState, .thinking)
    XCTAssertEqual(voice.status, .idle)
  }

  func testStableStatesAreRestoredAfterSpeaking() {
    for state in [PetState.idle, .thinking, .warning, .needsInput] {
      let (voice, speech, pet) = makeVoice(startingAt: state)
      voice.speak(text: "state restoration")
      XCTAssertEqual(pet.currentState, .speaking)
      speech.finishLatest()
      XCTAssertEqual(pet.currentState, state)
    }
  }

  func testStaleSuccessCompletionCannotOverrideSpeakingAndRestoresToIdle() throws {
    let pet = PetStateController()
    let renderer = VoiceRecordingRenderer()
    pet.renderer = renderer
    pet.transition(to: .success)
    let staleSuccessCompletion = try XCTUnwrap(renderer.completion)
    let speech = MockSpeechSynthesizer()
    let voice = VoiceController(petStateController: pet, synthesizer: speech)

    voice.speak(text: "success race")
    staleSuccessCompletion(.success)

    XCTAssertEqual(pet.currentState, .speaking)
    speech.finishLatest()
    XCTAssertEqual(pet.currentState, .idle)
  }

  func testPauseAndContinueKeepPetInSpeakingState() {
    let (voice, speech, pet) = makeVoice(startingAt: .idle)
    voice.speak(text: "pause test")

    voice.pause()
    XCTAssertEqual(voice.status, .paused)
    XCTAssertEqual(pet.currentState, .speaking)

    voice.continue()
    XCTAssertEqual(voice.status, .speaking)
    XCTAssertEqual(pet.currentState, .speaking)
    XCTAssertEqual(speech.pauseCount, 1)
    XCTAssertEqual(speech.continueCount, 1)
  }

  func testUnavailableSpeechShowsFriendlyMessageAndRestoresState() {
    let pet = PetStateController()
    pet.transition(to: .warning)
    let speech = MockSpeechSynthesizer()
    speech.shouldFailToSpeak = true
    let voice = VoiceController(petStateController: pet, synthesizer: speech)

    voice.speak(text: "will fail")

    XCTAssertEqual(voice.status, .unavailable)
    XCTAssertEqual(voice.userMessage, VoiceController.unavailableMessage)
    XCTAssertEqual(pet.currentState, .warning)
  }

  func testCustomPetSwitchAndHideDoNotInterruptActiveSpeech() throws {
    let suiteName = "VoiceTests.CustomPet.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState()
    let pet = PetStateController()
    let speech = MockSpeechSynthesizer()
    let voice = VoiceController(petStateController: pet, synthesizer: speech)
    let speechInputController = SpeechInputController(
      authorizationController: SpeechAuthorizationController(),
      recognizerFactory: SystemSpeechRecognizerFactory(),
      voiceOutputController: voice
    )
    let window = PetWindowController(
      appState: appState,
      pet: .officialFlowerBunny,
      petImage: NSImage(named: "official_flower_bunny"),
      store: PetStore(defaults: defaults),
      stateController: pet,
      speechInputController: speechInputController,
      tutorNotificationCenter: TutorPetNotificationCenter(),
      animationController: PetAnimationController(reduceMotionProvider: { false }),
      onOpenTutor: {}
    )
    defer { window.stop() }
    let customPet = PetModel(
      id: "user_voice_test",
      name: "自定义老师",
      source: .userImported,
      type: .staticImage,
      assetLocation: "pet.png",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      scale: 1
    )

    window.start()
    voice.speak(text: "custom pet keeps speaking")
    window.reloadPet(customPet, image: NSImage(named: "official_flower_bunny"))
    window.hide()

    XCTAssertEqual(pet.currentState, .speaking)
    XCTAssertTrue(voice.isActive)
    XCTAssertEqual(speech.stopCount, 0)
    XCTAssertFalse(appState.isPetVisible)

    speech.finishLatest()
    XCTAssertEqual(pet.currentState, .idle)
    XCTAssertEqual(voice.status, .idle)
  }

  private func makeVoice(
    startingAt state: PetState
  ) -> (VoiceController, MockSpeechSynthesizer, PetStateController) {
    let pet = PetStateController()
    pet.transition(to: state)
    let speech = MockSpeechSynthesizer()
    let voice = VoiceController(petStateController: pet, synthesizer: speech)
    return (voice, speech, pet)
  }
}

@MainActor
private final class MockSpeechSynthesizer: SpeechSynthesizing {
  var availableVoices: [SpeechVoiceOption] = [
    SpeechVoiceOption(identifier: "mock.zh-CN", name: "Mock Chinese", language: "zh-CN")
  ]
  var eventHandler: ((SpeechSynthesizerEvent) -> Void)?
  var requests: [SpeechRequest] = []
  var stopCount = 0
  var pauseCount = 0
  var continueCount = 0
  var maximumActiveRequestCount = 0
  var shouldFailToSpeak = false

  private var activeRequestID: UUID?

  func speak(_ request: SpeechRequest) throws {
    if shouldFailToSpeak {
      throw SpeechSynthesizerError.unavailable
    }
    requests.append(request)
    activeRequestID = request.id
    maximumActiveRequestCount = max(maximumActiveRequestCount, activeRequestID == nil ? 0 : 1)
    eventHandler?(.didStart(request.id))
  }

  @discardableResult
  func stop() -> Bool {
    stopCount += 1
    activeRequestID = nil
    return true
  }

  @discardableResult
  func pause() -> Bool {
    pauseCount += 1
    return activeRequestID != nil
  }

  @discardableResult
  func `continue`() -> Bool {
    continueCount += 1
    return activeRequestID != nil
  }

  func finishLatest() {
    guard let activeRequestID else {
      return
    }
    self.activeRequestID = nil
    eventHandler?(.didFinish(activeRequestID))
  }

  func send(_ event: SpeechSynthesizerEvent) {
    eventHandler?(event)
  }
}

@MainActor
private final class VoiceRecordingRenderer: PetStateRendering {
  var completion: ((PetState) -> Void)?

  func prepareForStateTransition(from state: PetState) {}

  func renderPetState(_ state: PetState, completion: @escaping (PetState) -> Void) {
    self.completion = completion
  }
}
