import Foundation

enum RealtimeVoiceSessionState: String, CaseIterable, Equatable, Sendable {
  case idle
  case authorizing
  case bootstrapping
  case connecting
  case ready
  case listening
  case thinking
  case speaking
  case interrupting
  case ending
  case failed

  var displayName: String {
    switch self {
    case .idle: return "Idle"
    case .authorizing: return "Authorizing"
    case .bootstrapping: return "Bootstrapping"
    case .connecting: return "Connecting"
    case .ready: return "Ready"
    case .listening: return "Listening"
    case .thinking: return "Thinking"
    case .speaking: return "Speaking"
    case .interrupting: return "Interrupting"
    case .ending: return "Ending"
    case .failed: return "Failed"
    }
  }
}

struct RealtimeVoiceStateMachine: Sendable {
  private(set) var state: RealtimeVoiceSessionState = .idle

  mutating func transition(to next: RealtimeVoiceSessionState) throws {
    guard next != state else {
      return
    }
    guard Self.allowedTransitions[state, default: []].contains(next) else {
      throw RealtimeVoiceFailure.illegalStateTransition(from: state, to: next)
    }
    state = next
  }

  private static let allowedTransitions: [
    RealtimeVoiceSessionState: Set<RealtimeVoiceSessionState>
  ] = [
    .idle: [.authorizing],
    .authorizing: [.bootstrapping, .ending, .failed],
    .bootstrapping: [.connecting, .ending, .failed],
    .connecting: [.ready, .ending, .failed],
    .ready: [.listening, .speaking, .ending, .failed],
    .listening: [.thinking, .speaking, .interrupting, .ending, .failed],
    .thinking: [.listening, .speaking, .interrupting, .ending, .failed],
    .speaking: [.listening, .interrupting, .ending, .failed],
    .interrupting: [.listening, .ending, .failed],
    .ending: [.idle, .failed],
    .failed: [.ending, .idle],
  ]
}
