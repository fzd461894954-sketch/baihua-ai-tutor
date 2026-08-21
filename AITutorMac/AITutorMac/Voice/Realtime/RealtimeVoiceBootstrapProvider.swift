import Foundation

protocol RealtimeVoiceBootstrapProviding: Sendable {
  func createSession() async throws -> RealtimeVoiceBootstrap
  func stopSession(taskID: String) async
}

protocol RealtimeVoiceCommandProviding: Sendable {
  func interruptSession(taskID: String) async throws
}

actor MockRealtimeVoiceBootstrapProvider:
  RealtimeVoiceBootstrapProviding,
  RealtimeVoiceCommandProviding
{
  enum Behavior: Sendable {
    case success
    case failure(RealtimeVoiceFailure)
  }

  private let behavior: Behavior
  private let expiresAfter: TimeInterval
  private(set) var createdSessionCount = 0
  private(set) var interruptedTaskIDs: [String] = []
  private(set) var stoppedTaskIDs: [String] = []

  init(
    behavior: Behavior = .success,
    expiresAfter: TimeInterval = 10 * 60
  ) {
    self.behavior = behavior
    self.expiresAfter = expiresAfter
  }

  func createSession() async throws -> RealtimeVoiceBootstrap {
    switch behavior {
    case .success:
      createdSessionCount += 1
      let suffix = String(createdSessionCount)
      return RealtimeVoiceBootstrap(
        rtcAppID: "mock-rtc-app",
        rtcToken: "mock-short-lived-token-\(suffix)",
        roomID: "mock-room-\(suffix)",
        userID: "mock-user-\(suffix)",
        taskID: "mock-task-\(suffix)",
        expiresAt: Date().addingTimeInterval(expiresAfter)
      )
    case let .failure(failure):
      throw failure
    }
  }

  func interruptSession(taskID: String) async throws {
    interruptedTaskIDs.append(taskID)
  }

  func stopSession(taskID: String) async {
    stoppedTaskIDs.append(taskID)
  }
}
