import Foundation

enum RealtimeVoiceRTCStatus: String, Equatable, Sendable {
  case idle
  case connecting
  case connected
  case disconnected
  case failed
}

enum RealtimeVoiceAITaskStatus: String, Equatable, Sendable {
  case idle
  case starting
  case started
  case stopping
  case stopped
  case failed
}

enum RealtimeVoiceStopReason: String, Equatable, Sendable {
  case user
  case windowClosed
  case appTermination
  case systemSleep
  case unrecoverableNetwork
  case bootstrapExpired
  case rtcFatalError
  case sessionTimeout
  case startupFailure
}

enum RealtimeVoiceEvent: Equatable, Sendable {
  case stateChanged(RealtimeVoiceSessionState)
  case rtcStatusChanged(RealtimeVoiceRTCStatus)
  case aiTaskStatusChanged(RealtimeVoiceAITaskStatus)
  case microphoneActive(Bool)
  case aiSpeaking(Bool)
  case durationUpdated(TimeInterval)
  case interrupted
  case stopped(reason: RealtimeVoiceStopReason, duration: TimeInterval)
  case failed(RealtimeVoiceFailure)
}
