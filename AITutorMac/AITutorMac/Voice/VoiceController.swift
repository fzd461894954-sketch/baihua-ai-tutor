@preconcurrency import AVFoundation
import Foundation
import Observation
import OSLog

struct SpeechRequest: Equatable, Sendable {
  let id: UUID
  let text: String
  let voiceIdentifier: String?
  let rate: Float
  let pitch: Float
  let volume: Float
}

enum SpeechSynthesizerEvent: Equatable, Sendable {
  case didStart(UUID)
  case didFinish(UUID)
  case didCancel(UUID)
}

enum SpeechSynthesizerError: Error {
  case unavailable
}

@MainActor
protocol SpeechSynthesizing: AnyObject {
  var availableVoices: [SpeechVoiceOption] { get }
  var eventHandler: ((SpeechSynthesizerEvent) -> Void)? { get set }

  func speak(_ request: SpeechRequest) throws
  @discardableResult func stop() -> Bool
  @discardableResult func pause() -> Bool
  @discardableResult func `continue`() -> Bool
}

enum VoicePlaybackStatus: Equatable, Sendable {
  case idle
  case speaking
  case paused
  case unavailable

  var displayText: String {
    switch self {
    case .idle:
      return "未在朗读"
    case .speaking:
      return "正在朗读"
    case .paused:
      return "朗读已暂停"
    case .unavailable:
      return "语音暂时不可用"
    }
  }
}

@MainActor
@Observable
final class VoiceController {
  static let unavailableMessage = "当前语音暂时不可用，请选择其他声音。"

  private(set) var configuration: SpeechConfiguration
  private(set) var availableVoices: [SpeechVoiceOption]
  private(set) var status: VoicePlaybackStatus = .idle
  private(set) var userMessage: String?
  private(set) var localServiceStatus: LocalSpeechServiceStatus?

  @ObservationIgnored
  private let synthesizer: any SpeechSynthesizing
  @ObservationIgnored
  private let preferencesStore: VoicePreferencesStore
  @ObservationIgnored
  private let petStateController: PetStateController
  @ObservationIgnored
  private var activeRequestID: UUID?
  @ObservationIgnored
  private var restorationState: PetState?
  @ObservationIgnored
  private var statusObservers: [UUID: @MainActor (VoicePlaybackStatus) -> Void] = [:]
  @ObservationIgnored
  var onWillSpeak: (() -> Void)?

  init(
    petStateController: PetStateController,
    synthesizer: (any SpeechSynthesizing)? = nil,
    preferencesStore: VoicePreferencesStore = VoicePreferencesStore()
  ) {
    self.petStateController = petStateController
    let synthesizer = synthesizer ?? SystemSpeechSynthesizer()
    self.synthesizer = synthesizer
    self.preferencesStore = preferencesStore
    configuration = preferencesStore.load()
    availableVoices = synthesizer.availableVoices
    synthesizer.eventHandler = { [weak self] event in
      self?.handle(event)
    }
    if let monitor = synthesizer as? any LocalSpeechServiceMonitoring {
      localServiceStatus = monitor.localServiceStatus
      monitor.localServiceStatusHandler = { [weak self] status in
        self?.localServiceStatus = status
      }
    }
  }

  var isActive: Bool {
    status == .speaking || status == .paused
  }

  @discardableResult
  func addStatusObserver(
    _ observer: @escaping @MainActor (VoicePlaybackStatus) -> Void
  ) -> UUID {
    let observerID = UUID()
    statusObservers[observerID] = observer
    return observerID
  }

  func removeStatusObserver(_ observerID: UUID) {
    statusObservers[observerID] = nil
  }

  func speak(text: String) {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return
    }

    onWillSpeak?()
    userMessage = nil
    if restorationState == nil {
      restorationState = stableRestorationState(for: petStateController.currentState)
    }

    if activeRequestID != nil {
      activeRequestID = nil
      synthesizer.stop()
    }

    let requestID = UUID()
    let resolvedVoiceIdentifier = SpeechConfiguration.resolvedVoiceIdentifier(
      preferredIdentifier: configuration.voiceIdentifier,
      availableVoices: availableVoices
    )
    let request = SpeechRequest(
      id: requestID,
      text: text,
      voiceIdentifier: resolvedVoiceIdentifier,
      rate: configuration.rate,
      pitch: configuration.pitch,
      volume: configuration.volume
    )

    activeRequestID = requestID
    setStatus(.speaking)
    petStateController.transition(to: .speaking)

    do {
      try synthesizer.speak(request)
      AppLogger.voice.info("Speech request started")
    } catch {
      AppLogger.voice.error("Speech request could not start")
      activeRequestID = nil
      setStatus(.unavailable)
      userMessage = Self.unavailableMessage
      restorePetState()
    }
  }

  func stop() {
    guard activeRequestID != nil || isActive else {
      return
    }

    activeRequestID = nil
    synthesizer.stop()
    setStatus(.idle)
    userMessage = nil
    restorePetState()
    AppLogger.voice.info("Speech stopped by user")
  }

  func pause() {
    guard status == .speaking, synthesizer.pause() else {
      return
    }
    setStatus(.paused)
    AppLogger.voice.info("System speech paused")
  }

  func `continue`() {
    guard status == .paused, synthesizer.continue() else {
      return
    }
    setStatus(.speaking)
    AppLogger.voice.info("System speech continued")
  }

  func refreshAvailableVoices() {
    availableVoices = synthesizer.availableVoices
    (synthesizer as? any LocalSpeechServiceMonitoring)?.refreshLocalServiceStatus()
  }

  func prepareLocalService() {
    (synthesizer as? any LocalSpeechServiceMonitoring)?.prepareLocalService()
  }

  func shutdownLocalService() {
    (synthesizer as? any LocalSpeechServiceMonitoring)?.shutdownLocalService()
  }

  var selectedVoiceUsesLocalModel: Bool {
    guard let voiceIdentifier = configuration.voiceIdentifier else {
      return availableVoices.contains(where: {
        $0.language == "zh-CN" && $0.identifier.hasPrefix(LocalQwenVoice.identifierPrefix)
      })
    }
    return voiceIdentifier.hasPrefix(LocalQwenVoice.identifierPrefix)
  }

  func selectVoice(identifier: String?) {
    updateConfiguration { $0.voiceIdentifier = identifier }
  }

  func setRate(_ rate: Float) {
    updateConfiguration { $0.rate = rate }
  }

  func setPitch(_ pitch: Float) {
    updateConfiguration { $0.pitch = pitch }
  }

  func setVolume(_ volume: Float) {
    updateConfiguration { $0.volume = volume }
  }

  private func updateConfiguration(_ update: (inout SpeechConfiguration) -> Void) {
    var updated = configuration
    update(&updated)
    updated = updated.clamped()
    guard updated != configuration else {
      return
    }
    configuration = updated
    preferencesStore.save(updated)
  }

  private func handle(_ event: SpeechSynthesizerEvent) {
    let requestID: UUID
    switch event {
    case let .didStart(id), let .didFinish(id), let .didCancel(id):
      requestID = id
    }

    guard requestID == activeRequestID else {
      return
    }

    switch event {
    case .didStart:
      setStatus(.speaking)
    case .didFinish, .didCancel:
      activeRequestID = nil
      setStatus(.idle)
      restorePetState()
      AppLogger.voice.info("Speech request ended")
    }
  }

  private func setStatus(_ newStatus: VoicePlaybackStatus) {
    guard newStatus != status else {
      return
    }
    status = newStatus
    for observer in statusObservers.values {
      observer(newStatus)
    }
  }

  private func stableRestorationState(for state: PetState) -> PetState {
    switch state {
    case .success, .speaking:
      return .idle
    case .idle, .watching, .thinking, .needsInput, .warning, .error:
      return state
    }
  }

  private func restorePetState() {
    guard let restorationState else {
      return
    }
    self.restorationState = nil
    petStateController.transition(to: restorationState)
  }
}

@MainActor
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing {
  private enum AdapterEvent {
    case didStart
    case didFinish
    case didCancel
  }

  private let synthesizer = AVSpeechSynthesizer()
  private var requestIDs: [ObjectIdentifier: UUID] = [:]

  var eventHandler: ((SpeechSynthesizerEvent) -> Void)?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  var availableVoices: [SpeechVoiceOption] {
    AVSpeechSynthesisVoice.speechVoices()
      .map {
        SpeechVoiceOption(
          identifier: $0.identifier,
          name: $0.name,
          language: $0.language
        )
      }
      .sorted {
        if $0.language == $1.language {
          return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if $0.language == "zh-CN" { return true }
        if $1.language == "zh-CN" { return false }
        return $0.language.localizedStandardCompare($1.language) == .orderedAscending
      }
  }

  func speak(_ request: SpeechRequest) throws {
    let utterance = AVSpeechUtterance(string: request.text)
    if let voiceIdentifier = request.voiceIdentifier {
      utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
    }
    utterance.rate = request.rate
    utterance.pitchMultiplier = request.pitch
    utterance.volume = request.volume
    requestIDs[ObjectIdentifier(utterance)] = request.id
    synthesizer.speak(utterance)
  }

  @discardableResult
  func stop() -> Bool {
    let stopped = synthesizer.stopSpeaking(at: .immediate)
    requestIDs.removeAll(keepingCapacity: true)
    return stopped
  }

  @discardableResult
  func pause() -> Bool {
    synthesizer.pauseSpeaking(at: .immediate)
  }

  @discardableResult
  func `continue`() -> Bool {
    synthesizer.continueSpeaking()
  }

  private func emit(_ event: AdapterEvent, for utterance: AVSpeechUtterance) {
    let key = ObjectIdentifier(utterance)
    guard let requestID = requestIDs[key] else {
      return
    }

    switch event {
    case .didStart:
      eventHandler?(.didStart(requestID))
    case .didFinish:
      requestIDs[key] = nil
      eventHandler?(.didFinish(requestID))
    case .didCancel:
      requestIDs[key] = nil
      eventHandler?(.didCancel(requestID))
    }
  }
}

extension SystemSpeechSynthesizer: @preconcurrency AVSpeechSynthesizerDelegate {
  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didStart utterance: AVSpeechUtterance
  ) {
    emit(.didStart, for: utterance)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    emit(.didFinish, for: utterance)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    emit(.didCancel, for: utterance)
  }
}
