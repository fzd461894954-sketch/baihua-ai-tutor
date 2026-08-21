import Foundation

struct RealtimeVoiceBootstrap: Equatable, Sendable {
  let rtcAppID: String
  let rtcToken: String
  let roomID: String
  let userID: String
  let taskID: String
  let expiresAt: Date

  func isExpired(at date: Date = Date()) -> Bool {
    expiresAt <= date
  }
}
