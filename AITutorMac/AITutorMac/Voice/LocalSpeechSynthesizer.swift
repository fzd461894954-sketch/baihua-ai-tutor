@preconcurrency import AVFoundation
import Foundation
import OSLog

enum LocalSpeechServiceStatus: Equatable, Sendable {
  case notInstalled
  case stopped
  case starting
  case ready
  case failed

  var displayText: String {
    switch self {
    case .notInstalled:
      return "尚未安装"
    case .stopped:
      return "已安装，尚未启动"
    case .starting:
      return "正在启动"
    case .ready:
      return "本地 Qwen3-TTS 已就绪"
    case .failed:
      return "本地服务暂时不可用"
    }
  }

  var systemImageName: String {
    switch self {
    case .notInstalled:
      return "square.and.arrow.down"
    case .stopped:
      return "stop.circle"
    case .starting:
      return "hourglass"
    case .ready:
      return "checkmark.circle.fill"
    case .failed:
      return "exclamationmark.triangle.fill"
    }
  }
}

@MainActor
protocol LocalSpeechServiceMonitoring: AnyObject {
  var localServiceStatus: LocalSpeechServiceStatus { get }
  var localServiceStatusHandler: ((LocalSpeechServiceStatus) -> Void)? { get set }

  func prepareLocalService()
  func refreshLocalServiceStatus()
  func shutdownLocalService()
}

struct MLXSpeechRequestPayload: Encodable, Equatable, Sendable {
  let model: String
  let input: String
  let voice: String
  let speed: Float
  let pitch: Float
  let langCode: String
  let responseFormat: String
  let stream: Bool

  enum CodingKeys: String, CodingKey {
    case model
    case input
    case voice
    case speed
    case pitch
    case langCode = "lang_code"
    case responseFormat = "response_format"
    case stream
  }
}

enum LocalQwenVoice: String, CaseIterable, Sendable {
  static let identifierPrefix = "local.qwen3."

  case serena = "Serena"
  case vivian = "Vivian"
  case uncleFu = "Uncle_Fu"
  case dylan = "Dylan"
  case eric = "Eric"

  var identifier: String {
    Self.identifierPrefix + rawValue.lowercased()
  }

  var displayName: String {
    switch self {
    case .serena:
      return "Serena · 本地温柔女声"
    case .vivian:
      return "Vivian · 本地明亮女声"
    case .uncleFu:
      return "傅叔 · 本地沉稳男声"
    case .dylan:
      return "Dylan · 本地北京男声"
    case .eric:
      return "Eric · 本地成都男声"
    }
  }

  static var speechVoiceOptions: [SpeechVoiceOption] {
    allCases.map {
      SpeechVoiceOption(
        identifier: $0.identifier,
        name: $0.displayName,
        language: "zh-CN"
      )
    }
  }

  static func resolve(identifier: String?) -> LocalQwenVoice? {
    guard let identifier else {
      return nil
    }
    return allCases.first(where: { $0.identifier == identifier })
  }
}

enum LocalSpeechServiceError: Error {
  case notInstalled
  case launchFailed
  case unavailable
  case invalidResponse
  case playbackFailed
}

struct MLXSpeechServiceClient {
  static let defaultModel = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"

  let endpoint: URL
  let session: URLSession

  init(
    endpoint: URL = URL(string: "http://127.0.0.1:8000")!,
    session: URLSession = .shared
  ) {
    self.endpoint = endpoint
    self.session = session
  }

  func isHealthy() async -> Bool {
    var request = URLRequest(url: endpoint.appendingPathComponent("openapi.json"))
    request.timeoutInterval = 2
    do {
      let (_, response) = try await session.data(for: request)
      guard let response = response as? HTTPURLResponse else {
        return false
      }
      return 200..<300 ~= response.statusCode
    } catch {
      return false
    }
  }

  func synthesize(_ payload: MLXSpeechRequestPayload) async throws -> Data {
    var request = URLRequest(url: endpoint.appendingPathComponent("v1/audio/speech"))
    request.httpMethod = "POST"
    request.timeoutInterval = 5 * 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await session.data(for: request)
    guard
      let response = response as? HTTPURLResponse,
      200..<300 ~= response.statusCode,
      !data.isEmpty
    else {
      throw LocalSpeechServiceError.invalidResponse
    }
    return data
  }

  static func payload(for request: SpeechRequest, voice: LocalQwenVoice) -> MLXSpeechRequestPayload {
    MLXSpeechRequestPayload(
      model: defaultModel,
      input: request.text,
      voice: voice.rawValue,
      speed: generationSpeed(for: request.rate),
      pitch: request.pitch,
      langCode: "Chinese",
      responseFormat: "wav",
      stream: false
    )
  }

  static func generationSpeed(for appRate: Float) -> Float {
    let range = SpeechConfiguration.rateRange
    let progress = (appRate.clamped(to: range) - range.lowerBound)
      / (range.upperBound - range.lowerBound)
    return 0.82 + (progress * 0.36)
  }
}

@MainActor
final class LocalMLXVoiceService {
  private let client: MLXSpeechServiceClient
  private let executableURL: URL
  private var process: Process?
  private var serviceLogHandle: FileHandle?

  private(set) var status: LocalSpeechServiceStatus
  var statusHandler: ((LocalSpeechServiceStatus) -> Void)?

  init(
    client: MLXSpeechServiceClient = MLXSpeechServiceClient(),
    executableURL: URL? = nil
  ) {
    self.client = client
    let resolvedExecutableURL = executableURL ?? Self.defaultExecutableURL()
    self.executableURL = resolvedExecutableURL
    status = FileManager.default.isExecutableFile(atPath: resolvedExecutableURL.path)
      ? .stopped
      : .notInstalled
  }

  func ensureReady() async throws {
    if await client.isHealthy() {
      setStatus(.ready)
      return
    }

    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
      setStatus(.notInstalled)
      throw LocalSpeechServiceError.notInstalled
    }

    if process?.isRunning != true {
      try launch()
    }

    setStatus(.starting)
    for _ in 0..<60 {
      if Task.isCancelled {
        throw CancellationError()
      }
      if await client.isHealthy() {
        setStatus(.ready)
        return
      }
      try await Task.sleep(nanoseconds: 250_000_000)
    }

    setStatus(.failed)
    throw LocalSpeechServiceError.unavailable
  }

  func refreshStatus() {
    Task { [weak self] in
      guard let self else { return }
      if await self.client.isHealthy() {
        self.setStatus(.ready)
      } else if FileManager.default.isExecutableFile(atPath: self.executableURL.path) {
        self.setStatus(self.process?.isRunning == true ? .starting : .stopped)
      } else {
        self.setStatus(.notInstalled)
      }
    }
  }

  func shutdown() {
    guard let process, process.isRunning else {
      closeServiceLog()
      return
    }
    process.terminationHandler = nil
    process.terminate()
    self.process = nil
    closeServiceLog()
    setStatus(.stopped)
  }

  private func launch() throws {
    let serviceRootURL = self.serviceRootURL
    let mlxLogDirectoryURL = serviceRootURL.appendingPathComponent("logs", isDirectory: true)
    try FileManager.default.createDirectory(
      at: mlxLogDirectoryURL,
      withIntermediateDirectories: true
    )

    let process = Process()
    process.executableURL = executableURL
    process.currentDirectoryURL = serviceRootURL
    process.arguments = [
      "--host", "127.0.0.1",
      "--port", "8000",
      "--log-dir", mlxLogDirectoryURL.path
    ]
    let serviceLogHandle = try makeServiceLogHandle()
    process.standardOutput = serviceLogHandle
    process.standardError = serviceLogHandle
    process.terminationHandler = { [weak self, weak process] _ in
      Task { @MainActor [weak self, weak process] in
        guard let self, self.process === process else { return }
        let exitCode = process?.terminationStatus ?? -1
        self.process = nil
        self.closeServiceLog()
        AppLogger.voice.error(
          "Local Qwen3-TTS service exited with status \(exitCode, privacy: .public)"
        )
        if self.status != .failed {
          self.setStatus(.stopped)
        }
      }
    }

    do {
      try process.run()
      self.process = process
      self.serviceLogHandle = serviceLogHandle
      setStatus(.starting)
      AppLogger.voice.info("Local Qwen3-TTS service launched")
    } catch {
      try? serviceLogHandle.close()
      setStatus(.failed)
      AppLogger.voice.error("Local Qwen3-TTS service could not launch")
      throw LocalSpeechServiceError.launchFailed
    }
  }

  private func makeServiceLogHandle() throws -> FileHandle {
    let logURL = serviceRootURL
      .appendingPathComponent("service.log", isDirectory: false)
    FileManager.default.createFile(atPath: logURL.path, contents: Data())
    return try FileHandle(forWritingTo: logURL)
  }

  private var serviceRootURL: URL {
    executableURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func closeServiceLog() {
    try? serviceLogHandle?.close()
    serviceLogHandle = nil
  }

  private func setStatus(_ newStatus: LocalSpeechServiceStatus) {
    guard newStatus != status else {
      return
    }
    status = newStatus
    statusHandler?(newStatus)
  }

  fileprivate static func defaultExecutableURL() -> URL {
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return applicationSupport
      .appendingPathComponent("BaihuaAI", isDirectory: true)
      .appendingPathComponent("LocalVoice", isDirectory: true)
      .appendingPathComponent(".venv", isDirectory: true)
      .appendingPathComponent("bin", isDirectory: true)
      .appendingPathComponent("mlx_audio.server", isDirectory: false)
  }
}

@MainActor
final class LocalQwenSpeechSynthesizer: NSObject, SpeechSynthesizing {
  private let client: MLXSpeechServiceClient
  private let service: LocalMLXVoiceService
  private var generationTask: Task<Void, Never>?
  private var player: AVAudioPlayer?
  private var activeRequestID: UUID?
  private var activeVolume: Float = 1

  var eventHandler: ((SpeechSynthesizerEvent) -> Void)?
  var failureHandler: ((SpeechRequest) -> Void)?

  init(
    client: MLXSpeechServiceClient = MLXSpeechServiceClient(),
    service: LocalMLXVoiceService? = nil
  ) {
    self.client = client
    self.service = service ?? LocalMLXVoiceService(client: client)
    super.init()
  }

  var availableVoices: [SpeechVoiceOption] {
    LocalQwenVoice.speechVoiceOptions
  }

  func speak(_ request: SpeechRequest) throws {
    guard let voice = LocalQwenVoice.resolve(identifier: request.voiceIdentifier) else {
      throw SpeechSynthesizerError.unavailable
    }

    stop()
    activeRequestID = request.id
    activeVolume = request.volume
    let payload = MLXSpeechServiceClient.payload(for: request, voice: voice)

    generationTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.service.ensureReady()
        let audio = try await self.client.synthesize(payload)
        try Task.checkCancellation()
        try self.play(audio, requestID: request.id)
      } catch is CancellationError {
        return
      } catch {
        guard self.activeRequestID == request.id else { return }
        self.activeRequestID = nil
        self.generationTask = nil
        AppLogger.voice.error("Local Qwen3-TTS generation failed; using system fallback")
        self.failureHandler?(request)
      }
    }
  }

  @discardableResult
  func stop() -> Bool {
    let wasActive = activeRequestID != nil || generationTask != nil || player?.isPlaying == true
    generationTask?.cancel()
    generationTask = nil
    player?.stop()
    player = nil
    activeRequestID = nil
    return wasActive
  }

  @discardableResult
  func pause() -> Bool {
    guard let player, player.isPlaying else {
      return false
    }
    player.pause()
    return true
  }

  @discardableResult
  func `continue`() -> Bool {
    guard let player, !player.isPlaying, activeRequestID != nil else {
      return false
    }
    return player.play()
  }

  private func play(_ data: Data, requestID: UUID) throws {
    guard activeRequestID == requestID else {
      throw CancellationError()
    }
    let player = try AVAudioPlayer(data: data)
    player.delegate = self
    player.volume = activeVolume
    player.prepareToPlay()
    guard player.play() else {
      throw LocalSpeechServiceError.playbackFailed
    }
    self.player = player
    generationTask = nil
    eventHandler?(.didStart(requestID))
  }

  fileprivate func didFinishPlayback(successfully: Bool) {
    guard let requestID = activeRequestID else {
      return
    }
    activeRequestID = nil
    player = nil
    if successfully {
      eventHandler?(.didFinish(requestID))
    } else {
      eventHandler?(.didCancel(requestID))
    }
  }
}

extension LocalQwenSpeechSynthesizer: @preconcurrency AVAudioPlayerDelegate {
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    didFinishPlayback(successfully: flag)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    didFinishPlayback(successfully: false)
  }
}

@MainActor
final class HybridSpeechSynthesizer: SpeechSynthesizing, LocalSpeechServiceMonitoring {
  private enum ActiveSource {
    case local
    case system
  }

  private let local: LocalQwenSpeechSynthesizer
  private let system: SystemSpeechSynthesizer
  private let service: LocalMLXVoiceService
  private var activeSource: ActiveSource?

  var eventHandler: ((SpeechSynthesizerEvent) -> Void)?
  var localServiceStatusHandler: ((LocalSpeechServiceStatus) -> Void)?

  init(
    client: MLXSpeechServiceClient = MLXSpeechServiceClient(),
    executableURL: URL? = nil,
    system: SystemSpeechSynthesizer? = nil
  ) {
    let service = LocalMLXVoiceService(
      client: client,
      executableURL: executableURL
    )
    let resolvedSystem = system ?? SystemSpeechSynthesizer()
    self.service = service
    local = LocalQwenSpeechSynthesizer(client: client, service: service)
    self.system = resolvedSystem

    local.eventHandler = { [weak self] event in
      self?.forward(event, source: .local)
    }
    local.failureHandler = { [weak self] request in
      self?.fallBackToSystem(for: request)
    }
    resolvedSystem.eventHandler = { [weak self] event in
      self?.forward(event, source: .system)
    }
    service.statusHandler = { [weak self] status in
      self?.localServiceStatusHandler?(status)
    }
  }

  var availableVoices: [SpeechVoiceOption] {
    local.availableVoices + system.availableVoices
  }

  var localServiceStatus: LocalSpeechServiceStatus {
    service.status
  }

  func speak(_ request: SpeechRequest) throws {
    stop()
    if LocalQwenVoice.resolve(identifier: request.voiceIdentifier) != nil {
      activeSource = .local
      try local.speak(request)
    } else {
      activeSource = .system
      try system.speak(request)
    }
  }

  @discardableResult
  func stop() -> Bool {
    activeSource = nil
    let localStopped = local.stop()
    let systemStopped = system.stop()
    return localStopped || systemStopped
  }

  @discardableResult
  func pause() -> Bool {
    switch activeSource {
    case .local:
      return local.pause()
    case .system:
      return system.pause()
    case nil:
      return false
    }
  }

  @discardableResult
  func `continue`() -> Bool {
    switch activeSource {
    case .local:
      return local.continue()
    case .system:
      return system.continue()
    case nil:
      return false
    }
  }

  func prepareLocalService() {
    Task { [weak self] in
      do {
        try await self?.service.ensureReady()
      } catch {
        // Local speech remains optional; requests automatically use the system fallback.
      }
    }
  }

  func refreshLocalServiceStatus() {
    service.refreshStatus()
  }

  func shutdownLocalService() {
    local.stop()
    service.shutdown()
  }

  private func fallBackToSystem(for request: SpeechRequest) {
    guard activeSource == .local else {
      return
    }
    activeSource = .system
    let fallback = SpeechRequest(
      id: request.id,
      text: request.text,
      voiceIdentifier: system.availableVoices.first(where: { $0.language == "zh-CN" })?.identifier,
      rate: request.rate,
      pitch: request.pitch,
      volume: request.volume
    )
    do {
      try system.speak(fallback)
    } catch {
      activeSource = nil
      eventHandler?(.didCancel(request.id))
    }
  }

  private func forward(_ event: SpeechSynthesizerEvent, source: ActiveSource) {
    guard activeSource == source else {
      return
    }
    switch event {
    case .didFinish, .didCancel:
      activeSource = nil
    case .didStart:
      break
    }
    eventHandler?(event)
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
