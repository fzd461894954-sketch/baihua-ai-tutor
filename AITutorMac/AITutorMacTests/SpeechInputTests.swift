import AppKit
import AVFoundation
import Speech
import SwiftUI
import XCTest

@testable import AITutorMac

@MainActor
final class SpeechInputTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var preferences: VoiceInputPreferencesStore!

  override func setUpWithError() throws {
    suiteName = "SpeechInputTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    preferences = VoiceInputPreferencesStore(defaults: defaults)
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suiteName)
    preferences = nil
    defaults = nil
    suiteName = nil
  }

  func testPermissionStateMappingCoversAllSystemValues() {
    XCTAssertEqual(
      SpeechAuthorizationController.mapMicrophoneStatus(.notDetermined),
      .notDetermined
    )
    XCTAssertEqual(
      SpeechAuthorizationController.mapMicrophoneStatus(.authorized),
      .authorized
    )
    XCTAssertEqual(
      SpeechAuthorizationController.mapMicrophoneStatus(.denied),
      .denied
    )
    XCTAssertEqual(
      SpeechAuthorizationController.mapMicrophoneStatus(.restricted),
      .restricted
    )
    XCTAssertEqual(
      SpeechAuthorizationController.mapSpeechStatus(.notDetermined),
      .notDetermined
    )
    XCTAssertEqual(
      SpeechAuthorizationController.mapSpeechStatus(.authorized),
      .authorized
    )
    XCTAssertEqual(
      SpeechAuthorizationController.mapSpeechStatus(.denied),
      .denied
    )
    XCTAssertEqual(
      SpeechAuthorizationController.mapSpeechStatus(.restricted),
      .restricted
    )
  }

  func testAppInitializationDoesNotRequestPermission() {
    let authorization = MockSpeechAuthorization(
      currentStatus: .init(microphone: .notDetermined, speechRecognition: .notDetermined)
    )

    _ = makeController(authorization: authorization)

    XCTAssertEqual(authorization.requestCount, 0)
  }

  func testActionBubblePanelCanBecomeKeyWithoutBecomingMain() {
    let expectedSize = NSSize(width: 330, height: 230)
    let panel = PetActionPanel(
      contentRect: NSRect(origin: .zero, size: expectedSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    panel.setContent(Text("按住说话"), size: expectedSize)

    XCTAssertTrue(panel.canBecomeKey)
    XCTAssertFalse(panel.canBecomeMain)
    XCTAssertEqual(panel.contentLayoutRect.size, expectedSize)
    XCTAssertEqual(panel.contentViewController?.view.frame.size, expectedSize)
  }

  func testHoldToTalkViewBalancesPressAndReleaseExactlyOnce() throws {
    let view = HoldToTalkCaptureNSView()
    var pressCount = 0
    var releaseCount = 0
    view.onPress = { pressCount += 1 }
    view.onRelease = { releaseCount += 1 }
    let mouseDown = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
      )
    )
    let mouseUp = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 2,
        clickCount: 1,
        pressure: 0
      )
    )

    view.mouseDown(with: mouseDown)
    view.mouseUp(with: mouseUp)
    view.mouseUp(with: mouseUp)

    XCTAssertEqual(pressCount, 1)
    XCTAssertEqual(releaseCount, 1)

    view.mouseDown(with: mouseDown)
    view.isEnabled = false
    view.mouseUp(with: mouseUp)

    XCTAssertEqual(pressCount, 2)
    XCTAssertEqual(releaseCount, 2)
  }

  func testFirstPressShowsProductExplanationBeforeSystemPermission() async {
    let authorization = MockSpeechAuthorization(
      currentStatus: .init(microphone: .notDetermined, speechRecognition: .notDetermined)
    )
    authorization.requestResult = .init(
      microphone: .authorized,
      speechRecognition: .authorized
    )
    let controller = makeController(authorization: authorization)

    controller.beginPushToTalk()

    XCTAssertTrue(controller.isShowingPermissionExplanation)
    XCTAssertEqual(authorization.requestCount, 0)
    XCTAssertEqual(controller.state, .idle)

    await controller.continuePermissionRequest()

    XCTAssertEqual(authorization.requestCount, 1)
    XCTAssertEqual(controller.state, .ready)
    XCTAssertFalse(controller.isMicrophoneActive)
  }

  func testMicrophoneAndSpeechDenialsAreDistinguished() async {
    let microphoneAuthorization = MockSpeechAuthorization(
      currentStatus: .init(microphone: .notDetermined, speechRecognition: .notDetermined)
    )
    microphoneAuthorization.requestResult = .init(
      microphone: .denied,
      speechRecognition: .notDetermined
    )
    let microphoneController = makeController(authorization: microphoneAuthorization)
    microphoneController.beginPushToTalk()
    await microphoneController.continuePermissionRequest()
    XCTAssertEqual(microphoneController.state, .denied)
    XCTAssertEqual(microphoneController.deniedPermission, .microphone)

    let speechAuthorization = MockSpeechAuthorization(
      currentStatus: .init(microphone: .notDetermined, speechRecognition: .notDetermined)
    )
    speechAuthorization.requestResult = .init(
      microphone: .authorized,
      speechRecognition: .denied
    )
    let speechController = makeController(authorization: speechAuthorization)
    speechController.beginPushToTalk()
    await speechController.continuePermissionRequest()
    XCTAssertEqual(speechController.state, .denied)
    XCTAssertEqual(speechController.deniedPermission, .speechRecognition)
  }

  func testSettledPermissionFailureDoesNotRequestOrExplainAgain() {
    let deniedAuthorization = MockSpeechAuthorization(
      currentStatus: .init(microphone: .denied, speechRecognition: .notDetermined)
    )
    let deniedController = makeController(authorization: deniedAuthorization)

    deniedController.beginPushToTalk()

    XCTAssertEqual(deniedController.state, .denied)
    XCTAssertEqual(deniedController.deniedPermission, .microphone)
    XCTAssertFalse(deniedController.isShowingPermissionExplanation)
    XCTAssertEqual(deniedAuthorization.requestCount, 0)

    let restrictedAuthorization = MockSpeechAuthorization(
      currentStatus: .init(microphone: .restricted, speechRecognition: .notDetermined)
    )
    let restrictedController = makeController(authorization: restrictedAuthorization)

    restrictedController.beginPushToTalk()

    XCTAssertEqual(restrictedController.state, .unavailable)
    XCTAssertNil(restrictedController.deniedPermission)
    XCTAssertFalse(restrictedController.isShowingPermissionExplanation)
    XCTAssertEqual(restrictedAuthorization.requestCount, 0)
  }

  func testStartStopAndFinalResultLifecycle() throws {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)

    controller.beginPushToTalk()
    let recognizer = try XCTUnwrap(factory.latestRecognizer)

    XCTAssertEqual(controller.state, .listening)
    XCTAssertTrue(controller.isMicrophoneActive)
    XCTAssertEqual(recognizer.startCount, 1)

    controller.endPushToTalk()
    XCTAssertEqual(controller.state, .transcribing)
    XCTAssertFalse(controller.isMicrophoneActive)
    XCTAssertEqual(recognizer.finishCount, 1)

    recognizer.send(.final("我还是没听懂 API 是什么意思。"))
    XCTAssertEqual(controller.state, .completed)
    XCTAssertEqual(controller.finalTranscript, "我还是没听懂 API 是什么意思。")
    XCTAssertFalse(controller.isMicrophoneActive)
  }

  func testDoubleStartDoesNotInstallSecondSession() {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)

    controller.beginPushToTalk()
    controller.beginPushToTalk()

    XCTAssertEqual(factory.makeCount, 1)
    XCTAssertEqual(factory.latestRecognizer?.startCount, 1)
  }

  func testStopWhenIdleDoesNothing() {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)

    controller.endPushToTalk()

    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(factory.makeCount, 0)
  }

  func testTimeoutStopsAudioAndShowsLimit() async throws {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory, maximumDuration: 0.01)

    controller.beginPushToTalk()
    let recognizer = try XCTUnwrap(factory.latestRecognizer)
    try await Task.sleep(nanoseconds: 50_000_000)

    XCTAssertEqual(controller.state, .transcribing)
    XCTAssertEqual(recognizer.finishCount, 1)
    XCTAssertFalse(recognizer.isCapturingAudio)
    XCTAssertEqual(controller.message, "单次语音最多 60 秒。")
  }

  func testCancelRemovesActiveRecognitionResources() throws {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)
    controller.beginPushToTalk()
    let recognizer = try XCTUnwrap(factory.latestRecognizer)

    controller.cancel()

    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(recognizer.cancelCount, 1)
    XCTAssertFalse(recognizer.isCapturingAudio)
  }

  func testPetHiddenCancelsVoiceInput() throws {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)
    let petState = PetStateController()
    let appState = AppState()
    let petSuiteName = "SpeechInputTests.Pet.\(UUID().uuidString)"
    let petDefaults = try XCTUnwrap(
      UserDefaults(suiteName: petSuiteName)
    )
    defer { petDefaults.removePersistentDomain(forName: petSuiteName) }
    let window = PetWindowController(
      appState: appState,
      pet: .officialFlowerBunny,
      petImage: NSImage(named: "official_flower_bunny"),
      store: PetStore(defaults: petDefaults),
      stateController: petState,
      speechInputController: controller,
      animationController: PetAnimationController(reduceMotionProvider: { false }),
      onOpenTutor: {}
    )
    defer { window.stop() }
    window.start()
    controller.beginPushToTalk()
    let recognizer = try XCTUnwrap(factory.latestRecognizer)

    window.hide()

    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(recognizer.cancelCount, 1)
    XCTAssertFalse(recognizer.isCapturingAudio)
  }

  func testStartingSTTStopsActiveTTSWithoutChangingPetState() {
    let output = MockVoiceOutputController()
    output.isActive = true
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory, output: output)
    let pet = PetStateController()
    pet.transition(to: .warning)

    controller.beginPushToTalk()

    XCTAssertEqual(output.stopCount, 1)
    XCTAssertFalse(output.isActive)
    XCTAssertEqual(controller.state, .listening)
    XCTAssertEqual(pet.currentState, .warning)
  }

  func testOnDeviceRecognitionIsRequiredWhenSupported() {
    let factory = MockSpeechRecognizerFactory()
    factory.supportsOnDeviceRecognition = true
    let controller = makeController(factory: factory)

    controller.beginPushToTalk()

    XCTAssertEqual(factory.latestRecognizer?.lastRequiresOnDeviceRecognition, true)
    XCTAssertFalse(controller.isUsingAppleService)
  }

  func testNetworkFallbackRequiresExplicitConsent() throws {
    let factory = MockSpeechRecognizerFactory()
    factory.supportsOnDeviceRecognition = false
    let controller = makeController(factory: factory)

    controller.beginPushToTalk()

    XCTAssertTrue(controller.isShowingCloudConsent)
    XCTAssertNil(factory.latestRecognizer?.lastRequiresOnDeviceRecognition)

    controller.chooseAppleService(allowed: true)
    controller.beginPushToTalk()

    XCTAssertEqual(factory.latestRecognizer?.lastRequiresOnDeviceRecognition, false)
    XCTAssertTrue(controller.isUsingAppleService)
    XCTAssertEqual(preferences.cloudSpeechRecognitionAllowed, true)
  }

  func testLocalOnlyChoiceDoesNotSilentlyUseNetwork() {
    let factory = MockSpeechRecognizerFactory()
    factory.supportsOnDeviceRecognition = false
    let controller = makeController(factory: factory)

    controller.beginPushToTalk()
    controller.chooseAppleService(allowed: false)
    controller.beginPushToTalk()

    XCTAssertEqual(controller.state, .unavailable)
    XCTAssertNil(factory.latestRecognizer?.lastRequiresOnDeviceRecognition)
    XCTAssertEqual(preferences.cloudSpeechRecognitionAllowed, false)
  }

  func testPartialAndFinalResultsStayInMemory() throws {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)
    controller.beginPushToTalk()
    let recognizer = try XCTUnwrap(factory.latestRecognizer)

    recognizer.send(.partial("我还是没理解"))
    XCTAssertEqual(controller.partialTranscript, "我还是没理解")
    XCTAssertEqual(controller.state, .listening)

    controller.endPushToTalk()
    recognizer.send(.final("我还是没理解 API 是什么意思。"))
    XCTAssertEqual(controller.finalTranscript, "我还是没理解 API 是什么意思。")
    XCTAssertEqual(controller.state, .completed)
  }

  func testSilentInputCompletesWithFriendlyMessage() throws {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)
    controller.beginPushToTalk()
    let recognizer = try XCTUnwrap(factory.latestRecognizer)
    controller.endPushToTalk()

    recognizer.send(.final(""))

    XCTAssertEqual(controller.state, .completed)
    XCTAssertEqual(controller.message, "没有听清，可以再说一次。")
  }

  func testErrorCleansUpAndClearReturnsToIdle() throws {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)
    controller.beginPushToTalk()
    let recognizer = try XCTUnwrap(factory.latestRecognizer)

    recognizer.send(.failure(.audioDeviceChanged))

    XCTAssertEqual(controller.state, .error)
    XCTAssertFalse(recognizer.isCapturingAudio)
    XCTAssertGreaterThanOrEqual(recognizer.cancelCount, 1)

    controller.clear()
    XCTAssertEqual(controller.state, .idle)
  }

  func testChineseAndEnglishLocalesArePassedToFactory() {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)

    controller.beginPushToTalk()
    XCTAssertEqual(factory.requestedLocales.last, "zh-CN")
    controller.cancel()

    controller.selectLocale(identifier: "en-US")
    controller.beginPushToTalk()
    XCTAssertEqual(factory.requestedLocales.last, "en-US")
  }

  func testUnavailableLocaleShowsFriendlyMessageWithoutStartingAudio() {
    let factory = MockSpeechRecognizerFactory()
    factory.shouldReturnRecognizer = false
    let controller = makeController(factory: factory)

    controller.beginPushToTalk()

    XCTAssertEqual(controller.state, .unavailable)
    XCTAssertEqual(controller.message, "当前语言暂时无法使用系统语音识别。")
    XCTAssertFalse(controller.isMicrophoneActive)
  }

  func testThirtyCyclesLeaveNoActiveRecognizerOrAccumulatedSession() throws {
    let factory = MockSpeechRecognizerFactory()
    let controller = makeController(factory: factory)

    for index in 0..<30 {
      controller.beginPushToTalk()
      let recognizer = try XCTUnwrap(factory.latestRecognizer)
      recognizer.send(.partial("partial \(index)"))
      controller.endPushToTalk()
      recognizer.send(.final("final \(index)"))
      XCTAssertEqual(controller.state, .completed)
      XCTAssertFalse(recognizer.isCapturingAudio)
    }

    XCTAssertEqual(factory.makeCount, 30)
    XCTAssertEqual(factory.recognizers.filter(\.isCapturingAudio).count, 0)
    XCTAssertTrue(factory.recognizers.allSatisfy { $0.startCount == 1 })
    XCTAssertTrue(factory.recognizers.allSatisfy { $0.finishCount == 1 })
    XCTAssertTrue(factory.recognizers.allSatisfy { $0.cancelCount >= 1 })
  }

  private func makeController(
    authorization: MockSpeechAuthorization? = nil,
    factory: MockSpeechRecognizerFactory? = nil,
    output: MockVoiceOutputController? = nil,
    maximumDuration: TimeInterval = 60
  ) -> SpeechInputController {
    let factory = factory ?? MockSpeechRecognizerFactory()
    let output = output ?? MockVoiceOutputController()
    return SpeechInputController(
      authorizationController: authorization ?? MockSpeechAuthorization.authorized,
      recognizerFactory: factory,
      voiceOutputController: output,
      preferencesStore: preferences,
      maximumDuration: maximumDuration
    )
  }

}

@MainActor
private final class MockSpeechAuthorization: SpeechAuthorizing {
  static var authorized: MockSpeechAuthorization {
    MockSpeechAuthorization(
      currentStatus: .init(microphone: .authorized, speechRecognition: .authorized)
    )
  }

  var currentStatus: SpeechPermissionSnapshot
  var requestResult: SpeechPermissionSnapshot
  var requestCount = 0
  var openedPermission: VoicePermissionKind?

  init(currentStatus: SpeechPermissionSnapshot) {
    self.currentStatus = currentStatus
    requestResult = currentStatus
  }

  func requestAuthorization() async -> SpeechPermissionSnapshot {
    requestCount += 1
    currentStatus = requestResult
    return requestResult
  }

  func openSystemSettings(for permission: VoicePermissionKind) {
    openedPermission = permission
  }
}

@MainActor
private final class MockSpeechRecognizerFactory: SpeechRecognizerCreating {
  var supportsOnDeviceRecognition = true
  var isAvailable = true
  var shouldReturnRecognizer = true
  var makeCount = 0
  var requestedLocales: [String] = []
  var recognizers: [MockSpeechRecognizer] = []

  var latestRecognizer: MockSpeechRecognizer? {
    recognizers.last
  }

  func makeRecognizer(localeIdentifier: String) -> (any SpeechRecognizing)? {
    makeCount += 1
    requestedLocales.append(localeIdentifier)
    guard shouldReturnRecognizer else {
      return nil
    }
    let recognizer = MockSpeechRecognizer(
      supportsOnDeviceRecognition: supportsOnDeviceRecognition,
      isAvailable: isAvailable
    )
    recognizers.append(recognizer)
    return recognizer
  }
}

@MainActor
private final class MockSpeechRecognizer: SpeechRecognizing {
  let supportsOnDeviceRecognition: Bool
  let isAvailable: Bool
  var eventHandler: ((SpeechRecognitionEvent) -> Void)?
  var isCapturingAudio = false
  var startCount = 0
  var finishCount = 0
  var cancelCount = 0
  var lastRequiresOnDeviceRecognition: Bool?

  init(supportsOnDeviceRecognition: Bool, isAvailable: Bool) {
    self.supportsOnDeviceRecognition = supportsOnDeviceRecognition
    self.isAvailable = isAvailable
  }

  func start(requiresOnDeviceRecognition: Bool) throws {
    startCount += 1
    lastRequiresOnDeviceRecognition = requiresOnDeviceRecognition
    isCapturingAudio = true
  }

  func finish() {
    finishCount += 1
    isCapturingAudio = false
  }

  func cancel() {
    cancelCount += 1
    isCapturingAudio = false
  }

  func send(_ event: SpeechRecognitionEvent) {
    eventHandler?(event)
  }
}

@MainActor
private final class MockVoiceOutputController: VoiceOutputControlling {
  var isActive = false
  var stopCount = 0

  func stop() {
    stopCount += 1
    isActive = false
  }
}
