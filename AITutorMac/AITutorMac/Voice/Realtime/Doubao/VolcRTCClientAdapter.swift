import AVFoundation
import Foundation

enum VolcRTCClientEvent: Equatable, Sendable {
  case connected
  case microphoneActive(Bool)
  case remoteAudioStarted
  case aiThinking
  case aiSpeaking
  case aiStoppedSpeaking
  case userBargeIn
  case disconnected
  case fatal(RealtimeVoiceFailure)
}

@MainActor
protocol VolcRTCClientAdapting: AnyObject {
  var eventHandler: ((UUID, VolcRTCClientEvent) -> Void)? { get set }

  func requestMicrophoneAuthorization() async -> Bool
  func connect(using bootstrap: RealtimeVoiceBootstrap, sessionID: UUID) async throws
  func startMicrophone(sessionID: UUID) async throws
  func discardRemoteAudio()
  func disconnect(sessionID: UUID) async
}

/// Compile-safe boundary for the isolated spike. The real Objective-C RTC SDK
/// implementation belongs entirely in this file once the framework version is
/// selected and added to the project. Until then it fails honestly.
@MainActor
final class VolcRTCClientAdapter: VolcRTCClientAdapting {
  var eventHandler: ((UUID, VolcRTCClientEvent) -> Void)?

  func requestMicrophoneAuthorization() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .audio)
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  func connect(using bootstrap: RealtimeVoiceBootstrap, sessionID: UUID) async throws {
    throw RealtimeVoiceFailure.rtcSDKUnavailable
  }

  func startMicrophone(sessionID: UUID) async throws {
    throw RealtimeVoiceFailure.rtcSDKUnavailable
  }

  func discardRemoteAudio() {}

  func disconnect(sessionID: UUID) async {
    eventHandler?(sessionID, .microphoneActive(false))
    eventHandler?(sessionID, .disconnected)
  }
}

@MainActor
final class MockVolcRTCClientAdapter: VolcRTCClientAdapting {
  var eventHandler: ((UUID, VolcRTCClientEvent) -> Void)?
  var microphoneAuthorizationGranted = true
  var connectFailures: [RealtimeVoiceFailure] = []
  private(set) var connectAttemptCount = 0
  private(set) var disconnectCount = 0
  private(set) var discardRemoteAudioCount = 0
  private(set) var lastSessionID: UUID?

  func requestMicrophoneAuthorization() async -> Bool {
    microphoneAuthorizationGranted
  }

  func connect(using bootstrap: RealtimeVoiceBootstrap, sessionID: UUID) async throws {
    connectAttemptCount += 1
    lastSessionID = sessionID
    if !connectFailures.isEmpty {
      throw connectFailures.removeFirst()
    }
    eventHandler?(sessionID, .connected)
  }

  func startMicrophone(sessionID: UUID) async throws {
    eventHandler?(sessionID, .microphoneActive(true))
  }

  func discardRemoteAudio() {
    discardRemoteAudioCount += 1
  }

  func disconnect(sessionID: UUID) async {
    disconnectCount += 1
    eventHandler?(sessionID, .microphoneActive(false))
    eventHandler?(sessionID, .disconnected)
  }

  func emit(_ event: VolcRTCClientEvent, sessionID: UUID? = nil) {
    guard let resolvedSessionID = sessionID ?? lastSessionID else {
      return
    }
    eventHandler?(resolvedSessionID, event)
  }
}
