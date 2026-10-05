import Foundation

enum RealtimeVoiceFailure: Error, Equatable, Sendable {
  case duplicateStart
  case microphonePermissionDenied
  case bootstrapUnavailable
  case bootstrapExpired
  case rtcSDKUnavailable
  case rtcConnectionFailed(message: String, retryable: Bool)
  case aiTaskStartFailed(message: String)
  case interruptFailed(message: String)
  case illegalStateTransition(
    from: RealtimeVoiceSessionState,
    to: RealtimeVoiceSessionState
  )

  var isRetryable: Bool {
    if case let .rtcConnectionFailed(_, retryable) = self {
      return retryable
    }
    return false
  }

  var displayMessage: String {
    switch self {
    case .duplicateStart:
      return "A realtime voice session is already active."
    case .microphonePermissionDenied:
      return "Microphone permission was not granted."
    case .bootstrapUnavailable:
      return "The bootstrap service is not configured."
    case .bootstrapExpired:
      return "The bootstrap token has expired."
    case .rtcSDKUnavailable:
      return "VolcEngineRTC is not installed in this build."
    case let .rtcConnectionFailed(message, _),
         let .aiTaskStartFailed(message),
         let .interruptFailed(message):
      return message
    case let .illegalStateTransition(from, to):
      return "Illegal realtime voice transition: \(from.rawValue) → \(to.rawValue)."
    }
  }
}
