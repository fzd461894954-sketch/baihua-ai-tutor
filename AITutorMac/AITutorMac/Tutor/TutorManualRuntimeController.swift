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

  @ObservationIgnored private let contentProvider: CurrentExplainableContentProvider
  @ObservationIgnored private let coordinator: TutorCoordinator
  @ObservationIgnored private let router: TutorPresentationRouter
  @ObservationIgnored private let contentStore: TutorPanelContentStore
  @ObservationIgnored private let prepareEngine: @MainActor @Sendable () async -> Bool
  @ObservationIgnored private var actionTask: Task<Void, Never>?
  @ObservationIgnored private var actionGeneration = 0
  @ObservationIgnored private var requestedChunkID: UUID?

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
        self.requestedChunkID = nil
        self.state = .completed
      }
    }
    coordinator.onRequestFailure = { [weak self] error in
      guard let self, error != .cancelled else {
        return
      }
      self.contentStore.presentError(.requestFailed)
      self.requestedChunkID = nil
      self.state = .failed
    }
  }

  deinit {
    actionTask?.cancel()
  }

  func liveSessionDidStart(_ sessionID: UUID) {
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

  func receive(_ chunk: SemanticChunk, sessionID: UUID) {
    if
      state == .loading,
      let requestedChunkID,
      requestedChunkID != chunk.id
    {
      cancelPendingWork()
      contentStore.clear()
      state = .idle
    }
    contentProvider.receive(chunk, sessionID: sessionID)
  }

  func handle(_ intent: TutorPanelActionIntent) {
    switch intent {
    case .explainCurrentContent, .retryCurrentContent:
      explainCurrentContent()
    case .dismissCurrentPresentation:
      cancelPendingWork()
      contentStore.clear()
      state = .idle
    case .openModelSettings:
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
        self.requestedChunkID = chunk.id
        guard await self.prepareEngine() else {
          guard self.owns(generation: generation, sessionID: sessionID) else {
            return
          }
          self.contentStore.presentError(.modelNotConfigured)
          self.requestedChunkID = nil
          self.state = .failed
          self.actionTask = nil
          return
        }
        guard self.owns(generation: generation, sessionID: sessionID) else {
          return
        }
        self.actionTask = nil
        self.coordinator.requestExplanation(for: chunk)
      } catch {
        guard self.owns(generation: generation, sessionID: sessionID) else {
          return
        }
        self.actionTask = nil
        self.contentStore.presentError(.noStableContent)
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
    requestedChunkID = nil
  }

  private func owns(generation: Int, sessionID: UUID?) -> Bool {
    !Task.isCancelled
      && generation == actionGeneration
      && activeSessionID == sessionID
  }
}
