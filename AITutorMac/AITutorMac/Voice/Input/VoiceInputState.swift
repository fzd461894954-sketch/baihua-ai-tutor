import Foundation

enum VoiceInputState: String, Equatable, Sendable {
  case idle
  case requestingPermission
  case ready
  case listening
  case transcribing
  case completed
  case denied
  case unavailable
  case error

  var displayName: String {
    switch self {
    case .idle:
      return "未在听"
    case .requestingPermission:
      return "正在请求权限"
    case .ready:
      return "可以开始说话"
    case .listening:
      return "正在听…"
    case .transcribing:
      return "正在整理文字…"
    case .completed:
      return "识别完成"
    case .denied:
      return "权限未开启"
    case .unavailable:
      return "语音识别不可用"
    case .error:
      return "识别未完成"
    }
  }
}

enum VoicePermissionStatus: String, Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
  case unavailable
}

struct SpeechPermissionSnapshot: Equatable, Sendable {
  var microphone: VoicePermissionStatus
  var speechRecognition: VoicePermissionStatus

  static let unknown = SpeechPermissionSnapshot(
    microphone: .notDetermined,
    speechRecognition: .notDetermined
  )

  var isFullyAuthorized: Bool {
    microphone == .authorized && speechRecognition == .authorized
  }

  var needsSystemRequest: Bool {
    microphone == .notDetermined || speechRecognition == .notDetermined
  }
}

enum VoicePermissionKind: Equatable, Sendable {
  case microphone
  case speechRecognition
}

enum SpeechRecognitionFailure: Equatable, Sendable {
  case recognizerUnavailable
  case audioInputUnavailable
  case audioDeviceChanged
  case networkUnavailable
  case recognitionFailed
}

enum SpeechRecognitionEvent: Equatable, Sendable {
  case partial(String)
  case final(String)
  case failure(SpeechRecognitionFailure)
}

struct VoiceInputPreferencesStore {
  private enum Key {
    static let permissionExplanationAcknowledged =
      "voice.input.permissionExplanationAcknowledged"
    static let cloudSpeechRecognitionAllowed =
      "voice.input.cloudSpeechRecognitionAllowed"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var permissionExplanationAcknowledged: Bool {
    defaults.bool(forKey: Key.permissionExplanationAcknowledged)
  }

  var cloudSpeechRecognitionAllowed: Bool? {
    guard defaults.object(forKey: Key.cloudSpeechRecognitionAllowed) != nil else {
      return nil
    }
    return defaults.bool(forKey: Key.cloudSpeechRecognitionAllowed)
  }

  func acknowledgePermissionExplanation() {
    defaults.set(true, forKey: Key.permissionExplanationAcknowledged)
  }

  func saveCloudSpeechRecognitionAllowed(_ allowed: Bool) {
    defaults.set(allowed, forKey: Key.cloudSpeechRecognitionAllowed)
  }
}
