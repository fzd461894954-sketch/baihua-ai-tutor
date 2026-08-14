@preconcurrency import AVFoundation
import AppKit
import Speech

@MainActor
protocol SpeechAuthorizing: AnyObject {
  var currentStatus: SpeechPermissionSnapshot { get }
  func requestAuthorization() async -> SpeechPermissionSnapshot
  func openSystemSettings(for permission: VoicePermissionKind)
}

@MainActor
final class SpeechAuthorizationController: SpeechAuthorizing {
  var currentStatus: SpeechPermissionSnapshot {
    SpeechPermissionSnapshot(
      microphone: Self.mapMicrophoneStatus(
        AVCaptureDevice.authorizationStatus(for: .audio)
      ),
      speechRecognition: Self.mapSpeechStatus(
        SFSpeechRecognizer.authorizationStatus()
      )
    )
  }

  func requestAuthorization() async -> SpeechPermissionSnapshot {
    var status = currentStatus

    if status.microphone == .notDetermined {
      let granted = await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          continuation.resume(returning: granted)
        }
      }
      status.microphone = granted ? .authorized : .denied
      if granted {
        AppLogger.voiceInput.info("Microphone permission granted")
      } else {
        AppLogger.voiceInput.info("Microphone permission denied")
      }
    }

    guard status.microphone == .authorized else {
      return SpeechPermissionSnapshot(
        microphone: status.microphone,
        speechRecognition: Self.mapSpeechStatus(SFSpeechRecognizer.authorizationStatus())
      )
    }

    status.speechRecognition = Self.mapSpeechStatus(SFSpeechRecognizer.authorizationStatus())
    if status.speechRecognition == .notDetermined {
      status.speechRecognition = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { authorizationStatus in
          continuation.resume(returning: Self.mapSpeechStatus(authorizationStatus))
        }
      }
      if status.speechRecognition == .authorized {
        AppLogger.voiceInput.info("Speech recognition permission granted")
      } else {
        AppLogger.voiceInput.info("Speech recognition permission denied")
      }
    }

    return status
  }

  func openSystemSettings(for permission: VoicePermissionKind) {
    let anchor: String
    switch permission {
    case .microphone:
      anchor = "Privacy_Microphone"
    case .speechRecognition:
      anchor = "Privacy_SpeechRecognition"
    }

    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    ) else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  static func mapMicrophoneStatus(
    _ status: AVAuthorizationStatus
  ) -> VoicePermissionStatus {
    switch status {
    case .notDetermined:
      return .notDetermined
    case .authorized:
      return .authorized
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    @unknown default:
      return .unavailable
    }
  }

  static func mapSpeechStatus(
    _ status: SFSpeechRecognizerAuthorizationStatus
  ) -> VoicePermissionStatus {
    switch status {
    case .notDetermined:
      return .notDetermined
    case .authorized:
      return .authorized
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    @unknown default:
      return .unavailable
    }
  }
}
