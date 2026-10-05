import Foundation
import OSLog

struct RealtimeVoiceRetryPolicy: Equatable, Sendable {
  static let spikeDefault = RealtimeVoiceRetryPolicy(
    maximumAttempts: 3,
    initialBackoff: 0.25,
    multiplier: 2
  )

  let maximumAttempts: Int
  let initialBackoff: TimeInterval
  let multiplier: Double

  func backoff(afterFailedAttempt attempt: Int) -> TimeInterval {
    initialBackoff * pow(multiplier, Double(max(0, attempt - 1)))
  }
}

@MainActor
final class DoubaoRTCSession: RealtimeVoiceSession {
  var eventHandler: ((RealtimeVoiceEvent) -> Void)?

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.baihuaai.AITutorMac",
    category: "realtime-voice-spike"
  )

  private let bootstrapProvider: any RealtimeVoiceBootstrapProviding
  private let commandProvider: (any RealtimeVoiceCommandProviding)?
  private let rtcClient: any VolcRTCClientAdapting
  private let retryPolicy: RealtimeVoiceRetryPolicy
  private let maximumSessionDuration: TimeInterval
  private let timerInterval: TimeInterval
  private let now: @Sendable () -> Date

  private(set) var stateMachine = RealtimeVoiceStateMachine()
  private(set) var bootstrap: RealtimeVoiceBootstrap?
  private(set) var activeSessionID: UUID?
  private(set) var sessionStartedAt: Date?
  private var timerTask: Task<Void, Never>?
  private var stopTask: Task<Void, Never>?

  init(
    bootstrapProvider: any RealtimeVoiceBootstrapProviding,
    commandProvider: (any RealtimeVoiceCommandProviding)? = nil,
    rtcClient: any VolcRTCClientAdapting,
    retryPolicy: RealtimeVoiceRetryPolicy = .spikeDefault,
    maximumSessionDuration: TimeInterval = 3 * 60,
    timerInterval: TimeInterval = 1,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.bootstrapProvider = bootstrapProvider
    self.commandProvider = commandProvider
    self.rtcClient = rtcClient
    self.retryPolicy = retryPolicy
    self.maximumSessionDuration = maximumSessionDuration
    self.timerInterval = timerInterval
    self.now = now
  }

  var state: RealtimeVoiceSessionState {
    stateMachine.state
  }

  var isActive: Bool {
    state != .idle
  }

  func start() async throws {
    guard state == .idle else {
      throw RealtimeVoiceFailure.duplicateStart
    }

    let sessionID = UUID()
    activeSessionID = sessionID
    rtcClient.eventHandler = { [weak self] eventSessionID, event in
      self?.handleRTCEvent(event, sessionID: eventSessionID)
    }

    do {
      try transition(to: .authorizing)
      guard await rtcClient.requestMicrophoneAuthorization() else {
        throw RealtimeVoiceFailure.microphonePermissionDenied
      }

      try transition(to: .bootstrapping)
      emit(.aiTaskStatusChanged(.starting))
      let bootstrap = try await bootstrapProvider.createSession()
      self.bootstrap = bootstrap
      guard !bootstrap.isExpired(at: now()) else {
        throw RealtimeVoiceFailure.bootstrapExpired
      }
      emit(.aiTaskStatusChanged(.started))
      Self.logger.info("AI task started")

      try transition(to: .connecting)
      emit(.rtcStatusChanged(.connecting))
      try await connectWithBoundedRetry(bootstrap: bootstrap, sessionID: sessionID)
      try await rtcClient.startMicrophone(sessionID: sessionID)
      try transition(to: .ready)
      try transition(to: .listening)
      sessionStartedAt = now()
      startTimer(for: sessionID)
      Self.logger.info("Realtime voice session connected")
    } catch {
      let failure = normalizedFailure(error)
      await failAndStop(failure, reason: .startupFailure)
      throw failure
    }
  }

  func interrupt() async throws {
    guard [.listening, .thinking, .speaking].contains(state),
          let taskID = bootstrap?.taskID else {
      throw RealtimeVoiceFailure.interruptFailed(
        message: "No active realtime task can be interrupted."
      )
    }

    do {
      try transition(to: .interrupting)
      if let commandProvider {
        try await commandProvider.interruptSession(taskID: taskID)
      }
      rtcClient.discardRemoteAudio()
      emit(.aiSpeaking(false))
      emit(.interrupted)
      try transition(to: .listening)
      Self.logger.info("User interrupted AI")
    } catch {
      let failure = normalizedFailure(error, asInterruptFailure: true)
      emit(.failed(failure))
      try? transition(to: .listening)
      throw failure
    }
  }

  func stop() async {
    await stop(reason: .user)
  }

  func stop(reason: RealtimeVoiceStopReason) async {
    if let stopTask {
      await stopTask.value
      return
    }
    guard state != .idle else {
      return
    }

    let task = Task<Void, Never> { @MainActor [weak self] in
      guard let self else { return }
      await self.performStop(reason: reason)
    }
    stopTask = task
    await task.value
    stopTask = nil
  }

  private func performStop(reason: RealtimeVoiceStopReason) async {
    let duration = currentDuration
    timerTask?.cancel()
    timerTask = nil

    if state != .ending {
      try? transition(to: .ending)
    }
    emit(.microphoneActive(false))
    emit(.aiSpeaking(false))

    if let bootstrap {
      emit(.aiTaskStatusChanged(.stopping))
      await bootstrapProvider.stopSession(taskID: bootstrap.taskID)
      emit(.aiTaskStatusChanged(.stopped))
      Self.logger.info("AI task stopped")
    }

    if let activeSessionID {
      await rtcClient.disconnect(sessionID: activeSessionID)
    }
    rtcClient.eventHandler = nil
    emit(.rtcStatusChanged(.disconnected))

    bootstrap = nil
    activeSessionID = nil
    sessionStartedAt = nil
    try? transition(to: .idle)
    emit(.durationUpdated(duration))
    emit(.stopped(reason: reason, duration: duration))
    Self.logger.info("Realtime voice session ended; duration seconds: \(duration)")
  }

  private func connectWithBoundedRetry(
    bootstrap: RealtimeVoiceBootstrap,
    sessionID: UUID
  ) async throws {
    let maximumAttempts = max(1, retryPolicy.maximumAttempts)
    for attempt in 1...maximumAttempts {
      do {
        try await rtcClient.connect(using: bootstrap, sessionID: sessionID)
        return
      } catch {
        let failure = normalizedFailure(error)
        guard failure.isRetryable, attempt < maximumAttempts else {
          throw failure
        }
        let delay = retryPolicy.backoff(afterFailedAttempt: attempt)
        try await Task.sleep(
          nanoseconds: UInt64(max(0, delay) * 1_000_000_000)
        )
      }
    }
  }

  private func startTimer(for sessionID: UUID) {
    timerTask?.cancel()
    timerTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          try await Task.sleep(
            nanoseconds: UInt64(max(0.01, timerInterval) * 1_000_000_000)
          )
        } catch {
          return
        }
        guard activeSessionID == sessionID else { return }
        let duration = currentDuration
        emit(.durationUpdated(duration))
        if bootstrap?.isExpired(at: now()) == true {
          await failAndStop(.bootstrapExpired, reason: .bootstrapExpired)
          return
        }
        if duration >= maximumSessionDuration {
          await stop(reason: .sessionTimeout)
          return
        }
      }
    }
  }

  private var currentDuration: TimeInterval {
    guard let sessionStartedAt else { return 0 }
    return max(0, now().timeIntervalSince(sessionStartedAt))
  }

  private func handleRTCEvent(_ event: VolcRTCClientEvent, sessionID: UUID) {
    guard sessionID == activeSessionID else {
      return
    }

    switch event {
    case .connected:
      emit(.rtcStatusChanged(.connected))
      Self.logger.info("RTC connected")
    case let .microphoneActive(isActive):
      emit(.microphoneActive(isActive))
    case .remoteAudioStarted, .aiSpeaking:
      try? transition(to: .speaking)
      emit(.aiSpeaking(true))
      Self.logger.info("AI speaking")
    case .aiThinking:
      try? transition(to: .thinking)
    case .aiStoppedSpeaking:
      emit(.aiSpeaking(false))
      try? transition(to: .listening)
    case .userBargeIn:
      try? transition(to: .interrupting)
      rtcClient.discardRemoteAudio()
      emit(.aiSpeaking(false))
      emit(.interrupted)
      try? transition(to: .listening)
      Self.logger.info("User interrupted AI")
    case .disconnected:
      emit(.rtcStatusChanged(.disconnected))
    case let .fatal(failure):
      emit(.rtcStatusChanged(.failed))
      Task { @MainActor [weak self] in
        await self?.failAndStop(failure, reason: .rtcFatalError)
      }
    }
  }

  private func failAndStop(
    _ failure: RealtimeVoiceFailure,
    reason: RealtimeVoiceStopReason
  ) async {
    try? transition(to: .failed)
    emit(.aiTaskStatusChanged(.failed))
    emit(.failed(failure))
    await stop(reason: reason)
  }

  private func transition(to state: RealtimeVoiceSessionState) throws {
    try stateMachine.transition(to: state)
    emit(.stateChanged(state))
  }

  private func emit(_ event: RealtimeVoiceEvent) {
    eventHandler?(event)
  }

  private func normalizedFailure(
    _ error: Error,
    asInterruptFailure: Bool = false
  ) -> RealtimeVoiceFailure {
    if let failure = error as? RealtimeVoiceFailure {
      return failure
    }
    if asInterruptFailure {
      return .interruptFailed(message: String(describing: error))
    }
    return .rtcConnectionFailed(message: String(describing: error), retryable: false)
  }
}
