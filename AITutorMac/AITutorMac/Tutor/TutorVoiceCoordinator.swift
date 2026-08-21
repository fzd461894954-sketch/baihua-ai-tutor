import Foundation
import Observation

@MainActor
protocol TutorVoiceOutputControlling: AnyObject {
  var status: VoicePlaybackStatus { get }
  var isActive: Bool { get }

  func speak(text: String)
  func stop()
  @discardableResult
  func addStatusObserver(
    _ observer: @escaping @MainActor (VoicePlaybackStatus) -> Void
  ) -> UUID
  func removeStatusObserver(_ observerID: UUID)
}

extension VoiceController: TutorVoiceOutputControlling {}

/// Coordinates explicit Tutor Panel voice intents. It retains only IDs and
/// playback state; lesson text is created transiently and handed directly to
/// the existing VoiceController.
@MainActor
@Observable
final class TutorVoiceCoordinator {
  private(set) var activePresentationID: UUID?
  private(set) var playbackStatus: VoicePlaybackStatus

  @ObservationIgnored private let voiceController: any TutorVoiceOutputControlling
  @ObservationIgnored private let adapter: TutorVoicePresentationAdapter
  @ObservationIgnored private var statusObserverID: UUID?

  init(
    voiceController: any TutorVoiceOutputControlling,
    adapter: TutorVoicePresentationAdapter = TutorVoicePresentationAdapter()
  ) {
    self.voiceController = voiceController
    self.adapter = adapter
    playbackStatus = voiceController.status
    statusObserverID = voiceController.addStatusObserver { [weak self] status in
      self?.voiceStatusDidChange(status)
    }
  }

  var isPlayingTutorVoice: Bool {
    activePresentationID != nil && isActive(playbackStatus)
  }

  func isPlaying(_ presentation: TutorPresentationModel) -> Bool {
    activePresentationID == presentation.responseMetadata.responseID
      && isActive(playbackStatus)
  }

  func isAvailable(for presentation: TutorPresentationModel) -> Bool {
    adapter.makeScript(from: presentation) != nil
  }

  @discardableResult
  func play(_ presentation: TutorPresentationModel) -> Bool {
    guard let script = adapter.makeScript(from: presentation) else {
      return false
    }

    activePresentationID = script.presentationID
    voiceController.speak(text: script.text)
    playbackStatus = voiceController.status
    guard voiceController.isActive else {
      activePresentationID = nil
      return false
    }

    AppLogger.voice.info(
      "Tutor voice started presentationID=\(script.presentationID.uuidString, privacy: .public)"
    )
    return true
  }

  func stop() {
    guard let presentationID = activePresentationID else {
      return
    }
    activePresentationID = nil
    voiceController.stop()
    playbackStatus = voiceController.status
    AppLogger.voice.info(
      "Tutor voice stopped presentationID=\(presentationID.uuidString, privacy: .public)"
    )
  }

  /// Any content replacement stops an old lesson. Hiding the Panel does not
  /// call this method, so playback can continue with the existing Voice UX as
  /// the stop fallback.
  func presentationDidChange(to presentationID: UUID?) {
    guard let activePresentationID,
          activePresentationID != presentationID else {
      return
    }
    stop()
  }

  func shutdown() {
    stop()
    if let statusObserverID {
      voiceController.removeStatusObserver(statusObserverID)
      self.statusObserverID = nil
    }
  }

  private func voiceStatusDidChange(_ status: VoicePlaybackStatus) {
    playbackStatus = status
    guard !isActive(status), let presentationID = activePresentationID else {
      return
    }
    activePresentationID = nil
    AppLogger.voice.info(
      "Tutor voice completed presentationID=\(presentationID.uuidString, privacy: .public)"
    )
  }

  private func isActive(_ status: VoicePlaybackStatus) -> Bool {
    status == .speaking || status == .paused
  }
}
