import Foundation
import Observation

enum TutorManualRuntimeState: String, Equatable, Sendable {
  case idle
  case loading
  case completed
  case failed
}

/// Composition controller for the explicit Panel action. It owns no
/// source body, prompt, raw response, credential, or response history.
@MainActor
@Observable
final class TutorManualRuntimeController {
  private(set) var state: TutorManualRuntimeState = .idle
  private(set) var activeSessionID: UUID?
  private(set) var latestLatencyMetrics: TutorLatencyMetrics?

  @ObservationIgnored private let contentProvider: CurrentExplainableContentProvider
  @ObservationIgnored private let coordinator: TutorCoordinator
  @ObservationIgnored private let router: TutorPresentationRouter
  @ObservationIgnored private let contentStore: TutorPanelContentStore
  @ObservationIgnored private let prepareEngine: @MainActor @Sendable () async -> Bool
  @ObservationIgnored private var actionTask: Task<Void, Never>?
  @ObservationIgnored private var actionGeneration = 0
  @ObservationIgnored private var requestedChunkID: UUID?
  @ObservationIgnored private var activeLatencyTrace: TutorLatencyTrace?

  init(
    contentProvider: CurrentExplainableContentProvider,
    coordinator: TutorCoordinator,
    router: TutorPresentationRouter,
    contentStore: TutorPanelContentStore,
    prepareEngine: @escaping @MainActor @Sendable () async -> Bool
  ) {
    self.contentProvider = contentProvider
    self.coordinator = coordinator
    self.router = router
    self.contentStore = contentStore
    self.prepareEngine = prepareEngine

    coordinator.onPresentationReady = { [weak self] presentation, trigger in
      guard let self, trigger == .userInitiated else {
        return
      }
      if self.router.route(presentation, origin: .userInitiated) {
        self.coordinator.markPanelPresented(
          responseID: presentation.responseMetadata.responseID
        )
        self.latestLatencyMetrics = self.coordinator.latestLatencyMetrics
        self.logCompletedLatency()
        self.activeLatencyTrace = nil
        self.requestedChunkID = nil
        self.state = .completed
      }
    }
    coordinator.onRequestFailure = { [weak self] error in
      guard let self, error != .cancelled else {
        return
      }
      self.router.routeError(.requestFailed, origin: .userInitiated)
      self.latestLatencyMetrics = self.coordinator.latestLatencyMetrics
      self.activeLatencyTrace = nil
      self.requestedChunkID = nil
      self.state = .failed
    }
  }

  deinit {
    actionTask?.cancel()
  }

  func liveSessionDidStart(_ sessionID: UUID) {
    AppLogger.tutorRuntime.info(
      "Tutor runtime received live session start session=\(sessionID.uuidString, privacy: .public)"
    )
    cancelPendingWork()
    if state == .loading {
      contentStore.clear()
    }
    state = .idle
    activeSessionID = sessionID
    contentProvider.beginSession(sessionID)
    coordinator.startSession(sessionID)
    router.activateSession(sessionID)
  }

  func liveSessionDidEnd() {
    AppLogger.tutorRuntime.info("Tutor runtime received live session end")
    cancelPendingWork()
    activeSessionID = nil
    contentProvider.invalidateSession()
    coordinator.stop()
    router.deactivateSession()
    if state == .loading {
      contentStore.clear()
    }
    state = .idle
  }

  @discardableResult
  func receive(
    _ chunk: SemanticChunk,
    sessionID: UUID
  ) -> CurrentExplainableContentReceiveResult {
    let result = contentProvider.receive(chunk, sessionID: sessionID)
    guard result == .accepted else {
      return result
    }
    if
      state == .loading,
      let requestedChunkID,
      requestedChunkID != chunk.id
    {
      cancelPendingWork()
      contentStore.clear()
      state = .idle
    }
    return result
  }

  func handle(_ intent: TutorPanelActionIntent) {
    switch intent {
    case .explainCurrentContent, .retryCurrentContent:
      explainCurrentContent()
    case .dismissCurrentPresentation:
      cancelPendingWork()
      contentStore.clear()
      router.clearTutorNotification()
      state = .idle
    case .openModelSettings:
      break
    case .playTutorVoice, .stopTutorVoice:
      break
#if DEBUG
    case .showDebugFixture:
      break
#endif
    }
  }

  func stop() {
    liveSessionDidEnd()
    coordinator.onPresentationReady = nil
    coordinator.onRequestFailure = nil
  }

  func providerConfigurationDidChange() {
    cancelPendingWork()
    if state == .loading {
      contentStore.clear()
    }
    state = .idle
  }

  private func explainCurrentContent() {
    let latencyTrace = TutorLatencyTrace()
    activeLatencyTrace = latencyTrace
    latestLatencyMetrics = nil
    let sessionDescription = activeSessionID?.uuidString ?? "none"
    AppLogger.tutorRuntime.info(
      "Manual explain requested session=\(sessionDescription, privacy: .public) providerAvailable=\(self.contentProvider.hasStableContent, privacy: .public)"
    )
    cancelPendingWork()
    contentStore.setLoading()
    state = .loading
    actionGeneration += 1
    let generation = actionGeneration
    let sessionID = activeSessionID

    actionTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      do {
        let chunk = try self.contentProvider.currentSemanticChunk()
        latencyTrace.markContentResolved()
        self.requestedChunkID = chunk.id
        guard await self.prepareEngine() else {
          guard self.owns(generation: generation, sessionID: sessionID) else {
            return
          }
          self.router.routeError(.modelNotConfigured, origin: .userInitiated)
          self.latestLatencyMetrics = latencyTrace.snapshot
          self.activeLatencyTrace = nil
          self.requestedChunkID = nil
          self.state = .failed
          self.actionTask = nil
          return
        }
        guard self.owns(generation: generation, sessionID: sessionID) else {
          return
        }
        self.actionTask = nil
        self.coordinator.requestExplanation(
          for: chunk,
          latencyTrace: latencyTrace
        )
      } catch {
        guard self.owns(generation: generation, sessionID: sessionID) else {
          return
        }
        self.actionTask = nil
        self.router.routeError(.noStableContent, origin: .userInitiated)
        self.latestLatencyMetrics = latencyTrace.snapshot
        self.activeLatencyTrace = nil
        self.requestedChunkID = nil
        self.state = .failed
      }
    }
  }

  private func cancelPendingWork() {
    actionGeneration += 1
    actionTask?.cancel()
    actionTask = nil
    coordinator.cancelCurrentRequest()
    if let activeLatencyTrace {
      latestLatencyMetrics = activeLatencyTrace.snapshot
    }
    activeLatencyTrace = nil
    requestedChunkID = nil
  }

  private func owns(generation: Int, sessionID: UUID?) -> Bool {
    !Task.isCancelled
      && generation == actionGeneration
      && activeSessionID == sessionID
  }

  private func logCompletedLatency() {
    guard let metrics = latestLatencyMetrics else {
      return
    }
    let total = Self.milliseconds(metrics.totalTutorLatency)
    let ttfb = Self.milliseconds(metrics.timeToFirstByte)
    let generation = Self.milliseconds(metrics.generationDuration)
    let inputTokens = metrics.inputTokens.map(String.init) ?? "unavailable"
    let outputTokens = metrics.outputTokens.map(String.init) ?? "unavailable"
    AppLogger.tutorRuntime.info(
      "Tutor latency completed trace=\(metrics.traceID.uuidString, privacy: .public) total_ms=\(total, privacy: .public) ttfb_ms=\(ttfb, privacy: .public) generation_ms=\(generation, privacy: .public) input_tokens=\(inputTokens, privacy: .public) output_tokens=\(outputTokens, privacy: .public)"
    )
  }

  private static func milliseconds(_ duration: TimeInterval?) -> String {
    duration.map { String(Int(($0 * 1_000).rounded())) } ?? "unavailable"
  }

#if DEBUG
  func usesContentProvider(_ provider: CurrentExplainableContentProvider) -> Bool {
    contentProvider === provider
  }

  var currentContentDiagnosticSnapshot: CurrentExplainableContentDiagnosticSnapshot {
    contentProvider.diagnosticSnapshot
  }
#endif
}
