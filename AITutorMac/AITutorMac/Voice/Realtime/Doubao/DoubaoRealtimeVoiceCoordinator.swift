import Foundation
import Observation

@MainActor
@Observable
final class DoubaoRealtimeVoiceCoordinator: RealtimeVoiceSession {
  private(set) var state: RealtimeVoiceSessionState = .idle
  private(set) var rtcStatus: RealtimeVoiceRTCStatus = .idle
  private(set) var aiTaskStatus: RealtimeVoiceAITaskStatus = .idle
  private(set) var isMicrophoneActive = false
  private(set) var isAISpeaking = false
  private(set) var duration: TimeInterval = 0
  private(set) var lastError: String?
  private(set) var lastStopReason: RealtimeVoiceStopReason?

  @ObservationIgnored
  private let session: DoubaoRTCSession

  init(session: DoubaoRTCSession) {
    self.session = session
    session.eventHandler = { [weak self] event in
      self?.handle(event)
    }
  }

  var isActive: Bool {
    state != .idle
  }

  func start() async throws {
    lastError = nil
    lastStopReason = nil
    duration = 0
    try await session.start()
  }

  func interrupt() async throws {
    try await session.interrupt()
  }

  func stop() async {
    await session.stop()
  }

  func stop(reason: RealtimeVoiceStopReason) async {
    await session.stop(reason: reason)
  }

  private func handle(_ event: RealtimeVoiceEvent) {
    switch event {
    case let .stateChanged(state):
      self.state = state
    case let .rtcStatusChanged(status):
      rtcStatus = status
    case let .aiTaskStatusChanged(status):
      aiTaskStatus = status
    case let .microphoneActive(isActive):
      isMicrophoneActive = isActive
    case let .aiSpeaking(isSpeaking):
      isAISpeaking = isSpeaking
    case let .durationUpdated(duration):
      self.duration = duration
    case .interrupted:
      isAISpeaking = false
    case let .stopped(reason, duration):
      lastStopReason = reason
      self.duration = duration
    case let .failed(failure):
      lastError = failure.displayMessage
    }
  }
}
