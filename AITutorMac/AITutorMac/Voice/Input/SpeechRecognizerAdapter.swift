@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

@MainActor
protocol SpeechRecognizing: AnyObject {
  var supportsOnDeviceRecognition: Bool { get }
  var isAvailable: Bool { get }
  var isCapturingAudio: Bool { get }
  var eventHandler: ((SpeechRecognitionEvent) -> Void)? { get set }

  func start(requiresOnDeviceRecognition: Bool) throws
  func finish()
  func cancel()
}

@MainActor
protocol SpeechRecognizerCreating: AnyObject {
  func makeRecognizer(localeIdentifier: String) -> (any SpeechRecognizing)?
}

@MainActor
final class SystemSpeechRecognizerFactory: SpeechRecognizerCreating {
  func makeRecognizer(localeIdentifier: String) -> (any SpeechRecognizing)? {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
      return nil
    }
    return SystemSpeechRecognizerAdapter(recognizer: recognizer)
  }
}

@MainActor
final class SystemSpeechRecognizerAdapter: SpeechRecognizing {
  private enum AdapterError: Error {
    case alreadyRunning
    case audioInputUnavailable
  }

  private let recognizer: SFSpeechRecognizer
  private let audioEngine: AVAudioEngine
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var configurationObserver: NSObjectProtocol?
  private var inputTapInstalled = false

  var eventHandler: ((SpeechRecognitionEvent) -> Void)?
  private(set) var isCapturingAudio = false

  init(
    recognizer: SFSpeechRecognizer,
    audioEngine: AVAudioEngine = AVAudioEngine()
  ) {
    self.recognizer = recognizer
    self.audioEngine = audioEngine
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: audioEngine,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.audioConfigurationDidChange()
      }
    }
  }

  deinit {
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
  }

  var supportsOnDeviceRecognition: Bool {
    recognizer.supportsOnDeviceRecognition
  }

  var isAvailable: Bool {
    recognizer.isAvailable
  }

  func start(requiresOnDeviceRecognition: Bool) throws {
    guard recognitionTask == nil, !isCapturingAudio else {
      throw AdapterError.alreadyRunning
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = requiresOnDeviceRecognition

    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
      throw AdapterError.audioInputUnavailable
    }

    recognitionRequest = request
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      Task { @MainActor [weak self] in
        self?.process(result: result, error: error)
      }
    }

    inputNode.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: recordingFormat
    ) { [weak request] buffer, _ in
      request?.append(buffer)
    }
    inputTapInstalled = true

    do {
      audioEngine.prepare()
      try audioEngine.start()
      isCapturingAudio = true
    } catch {
      cleanup(cancelRecognition: true)
      throw error
    }
  }

  func finish() {
    stopAudioCapture()
    recognitionRequest?.endAudio()
  }

  func cancel() {
    cleanup(cancelRecognition: true)
  }

  private func process(
    result: SFSpeechRecognitionResult?,
    error: Error?
  ) {
    if let result {
      let text = result.bestTranscription.formattedString
      if result.isFinal {
        cleanup(cancelRecognition: false)
        eventHandler?(.final(text))
        return
      }
      eventHandler?(.partial(text))
    }

    guard let error else {
      return
    }
    cleanup(cancelRecognition: false)
    eventHandler?(.failure(Self.failure(for: error)))
  }

  private func audioConfigurationDidChange() {
    guard isCapturingAudio || recognitionTask != nil else {
      return
    }
    cleanup(cancelRecognition: true)
    eventHandler?(.failure(.audioDeviceChanged))
  }

  private func stopAudioCapture() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    if inputTapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      inputTapInstalled = false
    }
    isCapturingAudio = false
  }

  private func cleanup(cancelRecognition: Bool) {
    stopAudioCapture()
    if cancelRecognition {
      recognitionTask?.cancel()
    }
    recognitionTask = nil
    recognitionRequest = nil
  }

  private static func failure(for error: Error) -> SpeechRecognitionFailure {
    let error = error as NSError
    if error.domain == NSURLErrorDomain {
      return .networkUnavailable
    }
    if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
       underlyingError.domain == NSURLErrorDomain {
      return .networkUnavailable
    }
    return .recognitionFailed
  }
}
