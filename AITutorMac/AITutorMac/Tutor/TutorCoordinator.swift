import Foundation
import Observation

enum TutorCoordinatorState: String, Equatable, Sendable {
  case stopped
  case idle
  case processing
}

enum TutorChunkSkipReason: String, Equatable, Sendable {
  case inactiveSession
  case duplicateChunk
  case emptyText
  case lowConfidence
}

enum TutorChunkAdmission: Equatable, Sendable {
  case accepted(TutorTrigger)
  case skipped(TutorChunkSkipReason)
}

enum TutorRequestState: Equatable, Sendable {
  case idle
  case running(requestID: UUID, sequence: Int)
  case succeeded(requestID: UUID, sequence: Int)
  case failed(requestID: UUID?, error: TutorEngineError)
  case cancelled(requestID: UUID)
}

enum TutorProviderState: Equatable, Sendable {
  case idle
  case running(requestID: UUID)
  case succeeded(responseID: UUID)
  case failed(error: TutorEngineError)
  case cancelled(requestID: UUID)
}

struct TutorExecutionContext: Equatable, Sendable {
  let sessionID: UUID
  let requestID: UUID
  let sequence: Int
  let startedAt: Date
}

struct TutorCoordinatorConfiguration: Equatable, Sendable {
  static let `default` = TutorCoordinatorConfiguration(
    maximumSeenChunkCount: 256,
    allowsLowConfidenceAutomaticRequests: false
  )

  let maximumSeenChunkCount: Int
  let allowsLowConfidenceAutomaticRequests: Bool

  init(
    maximumSeenChunkCount: Int,
    allowsLowConfidenceAutomaticRequests: Bool
  ) {
    self.maximumSeenChunkCount = max(1, maximumSeenChunkCount)
    self.allowsLowConfidenceAutomaticRequests = allowsLowConfidenceAutomaticRequests
  }
}

/// Owns only the latest Tutor flow and bounded Chunk IDs. It never writes to
/// Context and does not archive previous request, response, or body values.
@MainActor
@Observable
final class TutorCoordinator {
  private(set) var state: TutorCoordinatorState = .stopped
  private(set) var currentSessionID: UUID?
  private(set) var latestChunk: SemanticChunk?
  private(set) var latestChunkAdmission: TutorChunkAdmission?
  private(set) var latestRequest: TutorRequest?
  private(set) var latestPromptPackage: PromptPackage?
  private(set) var latestResponse: TutorResponse?
  private(set) var latestPresentation: TutorPresentationModel?
  private(set) var latestInteractionInput: TutorInteractionInput?
  private(set) var latestInteractionDecision: TutorInteractionDecision?
  private(set) var requestState: TutorRequestState = .idle
  private(set) var providerState: TutorProviderState = .idle
  private(set) var activeExecutionContext: TutorExecutionContext?
  private(set) var lastError: TutorEngineError?
  private(set) var receivedChunkCount = 0
  private(set) var duplicateChunkCount = 0
  private(set) var requestCount = 0
  let displayQueue: TutorDisplayQueue

  var isSessionActive: Bool {
    currentSessionID != nil
  }

  @ObservationIgnored private let engine: any TutorEngine
  @ObservationIgnored private let requestFactory: TutorRequestFactory
  @ObservationIgnored private let promptBuilder: TutorPromptBuilder
  @ObservationIgnored private let responseValidator: TutorResponseValidator
  @ObservationIgnored private let presentationMapper: TutorPresentationMapper
  @ObservationIgnored private let interactionInputFactory: TutorInteractionInputFactory
  @ObservationIgnored private let interactionPolicy: TutorInteractionPolicy
  @ObservationIgnored private let learner: LearnerProfileSnapshot
  @ObservationIgnored private let output: TutorOutputPreferences
  @ObservationIgnored private let configuration: TutorCoordinatorConfiguration
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let makeSessionID: @Sendable () -> UUID
  @ObservationIgnored private var nextSequence = 0
  @ObservationIgnored private var seenChunkIDs: Set<UUID> = []
  @ObservationIgnored private var seenChunkOrder: [UUID] = []
  @ObservationIgnored private var activeTask: Task<Void, Never>?
  @ObservationIgnored var onPresentationReady: (@MainActor (TutorPresentationModel, TutorTrigger) -> Void)?
  @ObservationIgnored var onRequestFailure: (@MainActor (TutorEngineError) -> Void)?

  init(
    engine: any TutorEngine,
    requestFactory: TutorRequestFactory = TutorRequestFactory(),
    promptBuilder: TutorPromptBuilder = TutorPromptBuilder(),
    responseValidator: TutorResponseValidator = TutorResponseValidator(),
    presentationMapper: TutorPresentationMapper = TutorPresentationMapper(),
    interactionInputFactory: TutorInteractionInputFactory = TutorInteractionInputFactory(),
    interactionPolicy: TutorInteractionPolicy = TutorInteractionPolicy(),
    displayQueue: TutorDisplayQueue? = nil,
    learner: LearnerProfileSnapshot = .productDefault(),
    output: TutorOutputPreferences = .default(),
    configuration: TutorCoordinatorConfiguration = .default,
    now: @escaping @Sendable () -> Date = { Date() },
    makeSessionID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.engine = engine
    self.requestFactory = requestFactory
    self.promptBuilder = promptBuilder
    self.responseValidator = responseValidator
    self.presentationMapper = presentationMapper
    self.interactionInputFactory = interactionInputFactory
    self.interactionPolicy = interactionPolicy
    self.displayQueue = displayQueue ?? TutorDisplayQueue()
    self.learner = learner
    self.output = output
    self.configuration = configuration
    self.now = now
    self.makeSessionID = makeSessionID
  }

  deinit {
    activeTask?.cancel()
  }

  func start() {
    guard currentSessionID == nil else {
      return
    }
    beginNewSession()
  }

  func resetSession() {
    beginNewSession()
  }

  func startSession(_ sessionID: UUID) {
    cancelActiveTask()
    clearSessionContent()
    currentSessionID = sessionID
    state = .idle
  }

  func stop() {
    cancelActiveTask()
    currentSessionID = nil
    clearSessionContent()
    state = .stopped
  }

  func cancelCurrentRequest() {
    guard let context = activeExecutionContext else {
      return
    }
    activeTask?.cancel()
    activeTask = nil
    activeExecutionContext = nil
    requestState = .cancelled(requestID: context.requestID)
    providerState = .cancelled(requestID: context.requestID)
    lastError = .cancelled
    state = .idle
  }

  func receive(_ chunk: SemanticChunk) {
    guard let sessionID = currentSessionID else {
      latestChunkAdmission = .skipped(.inactiveSession)
      return
    }

    receivedChunkCount += 1
    latestChunk = chunk

    guard rememberIfNew(chunk.id) else {
      duplicateChunkCount += 1
      latestChunkAdmission = .skipped(.duplicateChunk)
      return
    }

    let admission = admissionDecision(for: chunk)
    latestChunkAdmission = admission
    guard case let .accepted(trigger) = admission else {
      return
    }

    beginRequest(for: chunk, trigger: trigger, sessionID: sessionID)
  }

  /// Explicit user action. It intentionally bypasses automatic low-confidence
  /// admission and duplicate suppression while retaining session ownership.
  func requestExplanation(for chunk: SemanticChunk) {
    guard let sessionID = currentSessionID else {
      latestChunkAdmission = .skipped(.inactiveSession)
      return
    }
    receivedChunkCount += 1
    latestChunk = chunk
    guard chunk.text.contains(where: { !$0.isWhitespace }) else {
      latestChunkAdmission = .skipped(.emptyText)
      return
    }
    latestChunkAdmission = .accepted(.userInitiated)
    beginRequest(for: chunk, trigger: .userInitiated, sessionID: sessionID)
  }

  private func beginRequest(
    for chunk: SemanticChunk,
    trigger: TutorTrigger,
    sessionID: UUID
  ) {
    cancelActiveTask()
    nextSequence += 1

    let request: TutorRequest
    let promptPackage: PromptPackage
    do {
      request = try requestFactory.make(
        from: chunk,
        sessionID: sessionID,
        sequence: nextSequence,
        learner: learner,
        trigger: trigger,
        output: output
      )
      promptPackage = try promptBuilder.build(from: request)
    } catch {
      let tutorError = Self.tutorError(from: error)
      latestRequest = nil
      latestPromptPackage = nil
      latestResponse = nil
      latestPresentation = nil
      latestInteractionInput = nil
      latestInteractionDecision = nil
      activeExecutionContext = nil
      requestState = .failed(requestID: nil, error: tutorError)
      providerState = .idle
      lastError = tutorError
      state = .idle
      onRequestFailure?(tutorError)
      return
    }

    let context = TutorExecutionContext(
      sessionID: sessionID,
      requestID: request.id,
      sequence: request.sequence,
      startedAt: now()
    )
    latestRequest = request
    latestPromptPackage = promptPackage
    latestResponse = nil
    latestPresentation = nil
    latestInteractionInput = nil
    latestInteractionDecision = nil
    activeExecutionContext = context
    requestState = .running(requestID: request.id, sequence: request.sequence)
    providerState = .running(requestID: request.id)
    lastError = nil
    requestCount += 1
    state = .processing

    activeTask = Task { @MainActor
      [weak self, engine, responseValidator, presentationMapper] in
      do {
        let response = try await engine.respond(to: request, prompt: promptPackage)
        let validated = try responseValidator.validate(response, for: request)
        let presentation = presentationMapper.makePresentation(from: validated)
        self?.complete(
          validated,
          presentation: presentation,
          sourceChunk: chunk,
          context: context
        )
      } catch {
        self?.fail(Self.tutorError(from: error), context: context)
      }
    }
  }

  private func beginNewSession() {
    cancelActiveTask()
    clearSessionContent()
    currentSessionID = makeSessionID()
    state = .idle
  }

  private func clearSessionContent() {
    latestChunk = nil
    latestChunkAdmission = nil
    latestRequest = nil
    latestPromptPackage = nil
    latestResponse = nil
    latestPresentation = nil
    latestInteractionInput = nil
    latestInteractionDecision = nil
    requestState = .idle
    providerState = .idle
    activeExecutionContext = nil
    lastError = nil
    receivedChunkCount = 0
    duplicateChunkCount = 0
    requestCount = 0
    nextSequence = 0
    seenChunkIDs.removeAll(keepingCapacity: false)
    seenChunkOrder.removeAll(keepingCapacity: false)
    displayQueue.reset()
  }

  private func cancelActiveTask() {
    activeTask?.cancel()
    activeTask = nil
    activeExecutionContext = nil
  }

  private func admissionDecision(for chunk: SemanticChunk) -> TutorChunkAdmission {
    guard chunk.text.contains(where: { !$0.isWhitespace }) else {
      return .skipped(.emptyText)
    }

    let trigger: TutorTrigger = chunk.flushReason == .manualFlush
      ? .userInitiated
      : .automatic
    if
      chunk.confidence == .low,
      trigger == .automatic,
      !configuration.allowsLowConfidenceAutomaticRequests
    {
      return .skipped(.lowConfidence)
    }
    return .accepted(trigger)
  }

  private func rememberIfNew(_ chunkID: UUID) -> Bool {
    guard seenChunkIDs.insert(chunkID).inserted else {
      return false
    }
    seenChunkOrder.append(chunkID)
    if seenChunkOrder.count > configuration.maximumSeenChunkCount {
      let expiredID = seenChunkOrder.removeFirst()
      seenChunkIDs.remove(expiredID)
    }
    return true
  }

  private func complete(
    _ response: TutorResponse,
    presentation: TutorPresentationModel,
    sourceChunk: SemanticChunk,
    context: TutorExecutionContext
  ) {
    guard owns(context) else {
      return
    }
    activeTask = nil
    activeExecutionContext = nil
    latestResponse = response
    latestPresentation = presentation
    let interactionInput = interactionInputFactory.make(
      presentation: presentation,
      sourceChunk: sourceChunk
    )
    let interactionDecision = latestRequest?.trigger == .userInitiated
      ? TutorInteractionDecision(
        action: .show,
        priority: .normal,
        reason: .conceptExplanation
      )
      : interactionPolicy.decide(interactionInput)
    latestInteractionInput = interactionInput
    latestInteractionDecision = interactionDecision
    displayQueue.submit(
      presentation,
      input: interactionInput,
      decision: interactionDecision
    )
    requestState = .succeeded(
      requestID: context.requestID,
      sequence: context.sequence
    )
    providerState = .succeeded(responseID: response.id)
    lastError = nil
    state = .idle
    onPresentationReady?(presentation, latestRequest?.trigger ?? .automatic)
  }

  private func fail(
    _ error: TutorEngineError,
    context: TutorExecutionContext
  ) {
    guard owns(context) else {
      return
    }
    activeTask = nil
    activeExecutionContext = nil
    latestResponse = nil
    latestPresentation = nil
    latestInteractionInput = nil
    latestInteractionDecision = nil
    if error == .cancelled {
      requestState = .cancelled(requestID: context.requestID)
      providerState = .cancelled(requestID: context.requestID)
    } else {
      requestState = .failed(requestID: context.requestID, error: error)
      providerState = .failed(error: error)
    }
    lastError = error
    state = .idle
    if error != .cancelled {
      onRequestFailure?(error)
    }
  }

  private func owns(_ context: TutorExecutionContext) -> Bool {
    currentSessionID == context.sessionID
      && activeExecutionContext == context
      && latestRequest?.id == context.requestID
      && latestRequest?.sequence == context.sequence
  }

  private static func tutorError(from error: Error) -> TutorEngineError {
    if let tutorError = error as? TutorEngineError {
      return tutorError
    }
    if let providerError = error as? LLMProviderError {
      if providerError == .cancelled {
        return .cancelled
      }
      return .provider(providerError)
    }
    if error is CancellationError {
      return .cancelled
    }
    return .generationFailed
  }
}
