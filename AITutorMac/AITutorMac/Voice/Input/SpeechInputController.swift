import Foundation
import Observation

@MainActor
protocol VoiceOutputControlling: AnyObject {
  var isActive: Bool { get }
  func stop()
}

extension VoiceController: VoiceOutputControlling {}

@MainActor
@Observable
final class SpeechInputController {
  static let maximumRecordingDuration: TimeInterval = 60
  static let permissionExplanation =
    "花花老师需要使用麦克风，才能听懂你的问题。只有你点按麦克风开始说话后才会使用，结束后会把识别出的文字作为问题提交。"

  private(set) var state: VoiceInputState = .idle
  private(set) var permissionStatus: SpeechPermissionSnapshot
  private(set) var partialTranscript = ""
  private(set) var finalTranscript = ""
  private(set) var message: String?
  private(set) var deniedPermission: VoicePermissionKind?
  private(set) var isShowingPermissionExplanation = false
  private(set) var isShowingCloudConsent = false
  private(set) var onDeviceRecognitionSupported: Bool?
  private(set) var isUsingAppleService = false
  private(set) var selectedLocaleIdentifier: String

  @ObservationIgnored
  private let authorizationController: any SpeechAuthorizing
  @ObservationIgnored
  private let recognizerFactory: any SpeechRecognizerCreating
  @ObservationIgnored
  private let voiceOutputController: any VoiceOutputControlling
  @ObservationIgnored
  private let preferencesStore: VoiceInputPreferencesStore
  @ObservationIgnored
  private let maximumDurationNanoseconds: UInt64
  @ObservationIgnored
  private var recognizer: (any SpeechRecognizing)?
  @ObservationIgnored
  private var timeoutTask: Task<Void, Never>?
  @ObservationIgnored
  private var permissionRequestID: UUID?
  @ObservationIgnored
  private var isPressActive = false
  @ObservationIgnored
  private var didReachTimeLimit = false

  init(
    authorizationController: any SpeechAuthorizing,
    recognizerFactory: any SpeechRecognizerCreating,
    voiceOutputController: any VoiceOutputControlling,
    preferencesStore: VoiceInputPreferencesStore = VoiceInputPreferencesStore(),
    localeIdentifier: String = "zh-CN",
    maximumDuration: TimeInterval = 60
  ) {
    self.authorizationController = authorizationController
    self.recognizerFactory = recognizerFactory
    self.voiceOutputController = voiceOutputController
    self.preferencesStore = preferencesStore
    selectedLocaleIdentifier = localeIdentifier
    permissionStatus = authorizationController.currentStatus
    maximumDurationNanoseconds = UInt64(max(0, maximumDuration) * 1_000_000_000)
  }

  var isMicrophoneActive: Bool {
    state == .listening && recognizer?.isCapturingAudio == true
  }

  var isInteractionActive: Bool {
    isPressActive || state == .listening || state == .transcribing
  }

  var cloudSpeechRecognitionAllowed: Bool? {
    preferencesStore.cloudSpeechRecognitionAllowed
  }

  func beginPushToTalk() {
    guard state != .requestingPermission,
          state != .listening,
          state != .transcribing else {
      return
    }

    isPressActive = true
    deniedPermission = nil
    message = nil
    didReachTimeLimit = false
    permissionStatus = authorizationController.currentStatus

    guard permissionStatus.isFullyAuthorized else {
      handleMissingAuthorization(permissionStatus)
      return
    }

    startRecognitionIfAvailable()
  }

  func endPushToTalk() {
    isPressActive = false
    guard state == .listening else {
      return
    }

    timeoutTask?.cancel()
    timeoutTask = nil
    state = .transcribing
    recognizer?.finish()
    AppLogger.voiceInput.info("Voice input stopped")
  }

  func continuePermissionRequest() async {
    guard isShowingPermissionExplanation else {
      return
    }

    isShowingPermissionExplanation = false
    preferencesStore.acknowledgePermissionExplanation()
    state = .requestingPermission
    message = nil
    let requestID = UUID()
    permissionRequestID = requestID

    let status = await authorizationController.requestAuthorization()
    guard permissionRequestID == requestID else {
      return
    }
    permissionRequestID = nil
    permissionStatus = status
    isPressActive = false

    if status.isFullyAuthorized {
      state = .ready
      message = "权限已开启，请再次点按麦克风开始说话。"
    } else {
      handleDeniedAuthorization(status)
    }
  }

  func cancelPermissionExplanation() {
    isShowingPermissionExplanation = false
    isPressActive = false
    state = .idle
    message = nil
  }

  func chooseAppleService(allowed: Bool) {
    preferencesStore.saveCloudSpeechRecognitionAllowed(allowed)
    isShowingCloudConsent = false
    isPressActive = false
    if allowed {
      state = .ready
      message = "已允许 Apple 语音识别服务。请再次点按麦克风开始说话。"
    } else {
      state = .unavailable
      message = "当前语言无法完全在这台 Mac 上完成语音识别。"
    }
  }

  func clear() {
    cancel()
    partialTranscript = ""
    finalTranscript = ""
    message = nil
    state = .idle
  }

  func cancel() {
    let wasActive = state == .listening || state == .transcribing
    permissionRequestID = nil
    isPressActive = false
    timeoutTask?.cancel()
    timeoutTask = nil
    recognizer?.cancel()
    recognizer = nil
    isShowingPermissionExplanation = false
    isShowingCloudConsent = false
    didReachTimeLimit = false
    partialTranscript = ""
    finalTranscript = ""
    message = nil
    deniedPermission = nil
    isUsingAppleService = false
    state = .idle
    if wasActive {
      AppLogger.voiceInput.info("Voice input cancelled")
    }
  }

  func selectLocale(identifier: String) {
    guard identifier != selectedLocaleIdentifier else {
      return
    }
    cancel()
    selectedLocaleIdentifier = identifier
    onDeviceRecognitionSupported = nil
    state = permissionStatus.isFullyAuthorized ? .ready : .idle
  }

  func openSystemSettings() {
    guard let deniedPermission else {
      return
    }
    authorizationController.openSystemSettings(for: deniedPermission)
  }

  private func handleMissingAuthorization(_ status: SpeechPermissionSnapshot) {
    let settledFailures: [VoicePermissionStatus] = [
      .denied,
      .restricted,
      .unavailable,
    ]
    if settledFailures.contains(status.microphone)
      || settledFailures.contains(status.speechRecognition) {
      handleDeniedAuthorization(status)
      return
    }

    if status.needsSystemRequest {
      isShowingPermissionExplanation = true
      state = .idle
      message = nil
      return
    }
    handleDeniedAuthorization(status)
  }

  private func handleDeniedAuthorization(_ status: SpeechPermissionSnapshot) {
    isPressActive = false
    isShowingPermissionExplanation = false
    deniedPermission = nil

    if status.microphone == .denied {
      state = .denied
      deniedPermission = .microphone
      message = "麦克风权限没有开启。请在系统设置 → 隐私与安全性 → 麦克风中开启。"
    } else if status.microphone == .restricted || status.microphone == .unavailable {
      state = .unavailable
      message = "这台 Mac 当前无法提供麦克风权限。"
    } else if status.speechRecognition == .denied {
      state = .denied
      deniedPermission = .speechRecognition
      message = "语音识别权限没有开启。请在系统设置 → 隐私与安全性 → 语音识别中开启。"
    } else {
      state = .unavailable
      message = "这台 Mac 当前无法提供语音识别权限。"
    }
    if state == .denied {
      AppLogger.voiceInput.info("Voice input permission denied")
    } else {
      AppLogger.voiceInput.info("Voice input permission unavailable")
    }
  }

  private func startRecognitionIfAvailable() {
    partialTranscript = ""
    finalTranscript = ""
    isShowingCloudConsent = false
    onDeviceRecognitionSupported = nil
    isUsingAppleService = false

    guard let recognizer = recognizerFactory.makeRecognizer(
      localeIdentifier: selectedLocaleIdentifier
    ) else {
      isPressActive = false
      state = .unavailable
      message = "当前语言暂时无法使用系统语音识别。"
      return
    }

    onDeviceRecognitionSupported = recognizer.supportsOnDeviceRecognition
    guard recognizer.isAvailable else {
      isPressActive = false
      state = .unavailable
      message = "当前语言暂时无法使用系统语音识别。"
      return
    }

    let requiresOnDeviceRecognition: Bool
    if recognizer.supportsOnDeviceRecognition {
      requiresOnDeviceRecognition = true
    } else if preferencesStore.cloudSpeechRecognitionAllowed == true {
      requiresOnDeviceRecognition = false
      isUsingAppleService = true
    } else if preferencesStore.cloudSpeechRecognitionAllowed == false {
      isPressActive = false
      state = .unavailable
      message = "当前语言无法完全在这台 Mac 上完成语音识别。"
      return
    } else {
      isPressActive = false
      state = .unavailable
      isShowingCloudConsent = true
      message = "当前语言无法完全在这台 Mac 上完成语音识别。是否允许使用 Apple 的语音识别服务？"
      return
    }

    recognizer.eventHandler = { [weak self] event in
      self?.handleRecognitionEvent(event)
    }

    if voiceOutputController.isActive {
      voiceOutputController.stop()
    }

    do {
      try recognizer.start(
        requiresOnDeviceRecognition: requiresOnDeviceRecognition
      )
      self.recognizer = recognizer
      state = .listening
      message = nil
      scheduleTimeout()
      AppLogger.voiceInput.info("Voice input started")
    } catch {
      recognizer.cancel()
      isPressActive = false
      state = .error
      message = "麦克风暂时无法启动，请检查输入设备后重试。"
      AppLogger.voiceInput.error("Voice input could not start")
    }
  }

  private func scheduleTimeout() {
    timeoutTask?.cancel()
    let duration = maximumDurationNanoseconds
    timeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: duration)
      } catch {
        return
      }
      self?.maximumDurationReached()
    }
  }

  private func maximumDurationReached() {
    guard state == .listening else {
      return
    }
    isPressActive = false
    didReachTimeLimit = true
    timeoutTask = nil
    state = .transcribing
    message = "单次语音最多 60 秒。"
    recognizer?.finish()
    AppLogger.voiceInput.info("Voice input reached maximum duration")
  }

  private func handleRecognitionEvent(_ event: SpeechRecognitionEvent) {
    switch event {
    case let .partial(text):
      guard state == .listening || state == .transcribing else {
        return
      }
      partialTranscript = text

    case let .final(text):
      finishWithTranscript(text)

    case let .failure(failure):
      handleRecognitionFailure(failure)
    }
  }

  private func finishWithTranscript(_ text: String) {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let reachedTimeLimit = didReachTimeLimit
    cleanupRecognition()
    finalTranscript = text
    partialTranscript = ""
    state = .completed
    if text.isEmpty {
      message = "没有听清，可以再说一次。"
    } else if reachedTimeLimit {
      message = "单次语音最多 60 秒。"
    } else {
      message = nil
    }
    AppLogger.voiceInput.info("Recognition completed")
  }

  private func handleRecognitionFailure(_ failure: SpeechRecognitionFailure) {
    if state == .transcribing,
       failure == .recognitionFailed {
      let bestText = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
      finishWithTranscript(bestText)
      return
    }

    cleanupRecognition()
    state = .error
    switch failure {
    case .audioDeviceChanged, .audioInputUnavailable:
      message = "麦克风设备已变化，请重新点按麦克风开始说话。"
    case .networkUnavailable:
      message = "Apple 语音识别服务暂时无法连接，请检查网络后重试。"
    case .recognizerUnavailable:
      message = "当前语言暂时无法使用系统语音识别。"
    case .recognitionFailed:
      message = "这次没有识别成功，请再试一次。"
    }
    AppLogger.voiceInput.error("Voice input recognition failed")
  }

  private func cleanupRecognition() {
    isPressActive = false
    timeoutTask?.cancel()
    timeoutTask = nil
    recognizer?.cancel()
    recognizer = nil
    isUsingAppleService = false
    didReachTimeLimit = false
  }
}
