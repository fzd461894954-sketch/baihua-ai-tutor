import Foundation

@MainActor
protocol RealtimeVoiceSession: AnyObject {
  func start() async throws
  func interrupt() async throws
  func stop() async
}
