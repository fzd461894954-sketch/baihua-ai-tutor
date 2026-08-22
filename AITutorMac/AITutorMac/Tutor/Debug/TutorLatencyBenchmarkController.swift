#if DEBUG
import Foundation
import Observation

enum TutorLatencyBenchmarkState: String, Equatable, Sendable {
  case idle
  case running
  case completed
  case failed
  case cancelled
}

enum TutorLatencyBenchmarkFormat: String, CaseIterable, Identifiable, Sendable {
  case providerDefault
  case jsonSchema
  case jsonObject

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .providerDefault: return "Provider 默认"
    case .jsonSchema: return "json_schema"
    case .jsonObject: return "json_object"
    }
  }
}

struct TutorLatencyBenchmarkRecord: Identifiable, Equatable, Sendable {
  let id: UUID
  let runNumber: Int
  let caseID: String
  let caseName: String
  let model: String
  let responseFormat: TutorLatencyBenchmarkFormat
  let maxOutputTokens: Int
  let metrics: TutorLatencyMetrics
  let qualityRating: TutorQualityRating?
  let succeeded: Bool
}

typealias TutorLatencyBenchmarkProviderBuilder = @Sendable (
  TutorProviderConfigurationSnapshot
) -> any LLMProvider

/// Debug-only, metadata-only real provider benchmark. It uses the saved
/// credential by reference and never copies it into an observable UI field.
@MainActor
@Observable
final class TutorLatencyBenchmarkController {
  static let defaultRunCount = 5

  var selectedCaseID = TutorEvaluationDataset.cases.first?.id ?? ""
  var modelOverride = ""
  var responseFormat = TutorLatencyBenchmarkFormat.providerDefault
  var maxOutputTokens = TutorResponseBudget.compactLesson.maximumOutputTokens

  private(set) var state = TutorLatencyBenchmarkState.idle
  private(set) var records: [TutorLatencyBenchmarkRecord] = []
  private(set) var completedRuns = 0
  private(set) var targetRuns = 0
  private(set) var failureMessage: String?

  var selectedCase: TutorEvaluationCase? {
    TutorEvaluationDataset.caseWithID(selectedCaseID)
  }

  var summary: TutorLatencyBenchmarkSummary {
    TutorLatencyBenchmarkSummary(
      metrics: records.filter(\.succeeded).map(\.metrics)
    )
  }

  var isRunning: Bool { state == .running }

  @ObservationIgnored private let providerFactory: any TutorProviderBuilding
  @ObservationIgnored private let providerBuilder: TutorLatencyBenchmarkProviderBuilder
  @ObservationIgnored private let requestFactory: TutorRequestFactory
  @ObservationIgnored private let promptBuilder: TutorPromptBuilder
  @ObservationIgnored private let validator: TutorResponseValidator
  @ObservationIgnored private let presentationMapper: TutorPresentationMapper
  @ObservationIgnored private let qualityEvaluator: TutorQualityEvaluator
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let makeID: @Sendable () -> UUID
  @ObservationIgnored private let sessionID: UUID
  @ObservationIgnored private var nextSequence = 0
  @ObservationIgnored private var activeProvider: (any LLMProvider)?
  @ObservationIgnored private var activeTask: Task<Void, Never>?

  init(
    providerFactory: any TutorProviderBuilding,
    providerBuilder: @escaping TutorLatencyBenchmarkProviderBuilder = {
      TutorProviderFactory.liveProvider(snapshot: $0)
    },
    requestFactory: TutorRequestFactory = TutorRequestFactory(),
    promptBuilder: TutorPromptBuilder = TutorPromptBuilder(),
    validator: TutorResponseValidator = TutorResponseValidator(),
    presentationMapper: TutorPresentationMapper = TutorPresentationMapper(),
    qualityEvaluator: TutorQualityEvaluator = TutorQualityEvaluator(),
    now: @escaping @Sendable () -> Date = { Date() },
    makeID: @escaping @Sendable () -> UUID = { UUID() },
    sessionID: UUID = UUID()
  ) {
    self.providerFactory = providerFactory
    self.providerBuilder = providerBuilder
    self.requestFactory = requestFactory
    self.promptBuilder = promptBuilder
    self.validator = validator
    self.presentationMapper = presentationMapper
    self.qualityEvaluator = qualityEvaluator
    self.now = now
    self.makeID = makeID
    self.sessionID = sessionID
  }

  deinit {
    activeTask?.cancel()
  }

  func runFiveTimes() {
    run(repetitions: Self.defaultRunCount)
  }

  func runQualitySuite() {
    start(evaluationCases: TutorEvaluationDataset.cases)
  }

  func run(repetitions: Int) {
    guard !isRunning, let evaluationCase = selectedCase else {
      return
    }
    let count = min(20, max(1, repetitions))
    start(evaluationCases: Array(repeating: evaluationCase, count: count))
  }

  private func start(evaluationCases: [TutorEvaluationCase]) {
    guard !isRunning, !evaluationCases.isEmpty else {
      return
    }
    let baseSnapshot: TutorProviderConfigurationSnapshot
    do {
      baseSnapshot = try providerFactory.configurationSnapshot()
    } catch {
      failureMessage = "无法读取已保存的 Provider Settings / Keychain。"
      state = .failed
      AppLogger.tutorRuntime.error(
        "Tutor benchmark setup failed reason=provider_configuration_unavailable"
      )
      return
    }
    guard (128...4_096).contains(maxOutputTokens) else {
      failureMessage = "Max Output Tokens 必须在 128–4096 之间。"
      state = .failed
      AppLogger.tutorRuntime.error(
        "Tutor benchmark setup failed reason=invalid_output_budget"
      )
      return
    }

    cancelActiveWork()
    records.removeAll(keepingCapacity: true)
    completedRuns = 0
    targetRuns = evaluationCases.count
    failureMessage = nil
    state = .running
    AppLogger.tutorRuntime.info(
      "Tutor benchmark started runs=\(evaluationCases.count, privacy: .public) format=\(self.responseFormat.rawValue, privacy: .public) max_output_tokens=\(self.maxOutputTokens, privacy: .public)"
    )

    let effectiveSnapshot = makeSnapshot(from: baseSnapshot)
    let selectedFormat = responseFormat
    let tokenBudget = maxOutputTokens
    activeTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      for (index, evaluationCase) in evaluationCases.enumerated() {
        let runNumber = index + 1
        guard !Task.isCancelled else {
          self.state = .cancelled
          return
        }
        let succeeded = await self.runOnce(
          evaluationCase: evaluationCase,
          snapshot: effectiveSnapshot,
          selectedFormat: selectedFormat,
          tokenBudget: tokenBudget,
          runNumber: runNumber
        )
        self.completedRuns = runNumber
        if !succeeded {
          self.state = .failed
          self.clearActiveWork()
          return
        }
      }
      self.state = .completed
      AppLogger.tutorRuntime.info(
        "Tutor benchmark completed runs=\(self.completedRuns, privacy: .public)"
      )
      self.clearActiveWork()
    }
  }

  func cancel() {
    guard isRunning else {
      return
    }
    cancelActiveWork()
    state = .cancelled
  }

  func reset() {
    cancelActiveWork()
    records.removeAll(keepingCapacity: false)
    completedRuns = 0
    targetRuns = 0
    failureMessage = nil
    state = .idle
  }

  private func runOnce(
    evaluationCase: TutorEvaluationCase,
    snapshot: TutorProviderConfigurationSnapshot,
    selectedFormat: TutorLatencyBenchmarkFormat,
    tokenBudget: Int,
    runNumber: Int
  ) async -> Bool {
    let startedAt = now()
    let trace = TutorLatencyTrace(
      id: makeID(),
      userActionAt: startedAt,
      now: now
    )
    trace.markContentResolved()
    nextSequence += 1

    do {
      let request = try requestFactory.make(
        from: evaluationCase.semanticChunk,
        sessionID: sessionID,
        sequence: nextSequence,
        learner: .productDefault(at: startedAt),
        trigger: .userInitiated,
        output: .default(language: "zh-Hans")
      )
      trace.markRequestCreated(requestID: request.id)
      let prompt = try promptBuilder.build(from: request)
      trace.markPromptBuilt(
        prompt,
        sourceCharacterCount: request.source.text.count
      )

      let provider = providerBuilder(snapshot)
      activeProvider = provider
      let response = try await LLMTutorEngine(provider: provider).respond(
        to: request,
        prompt: prompt,
        latencyTrace: trace
      )
      try Task.checkCancellation()
      let validated = try validator.validate(response, for: request)
      trace.markValidated()
      _ = presentationMapper.makePresentation(from: validated)
      trace.markPresentationReady()
      trace.markPanelPresented()
      let quality = qualityEvaluator.evaluate(
        validated,
        for: request,
        expectations: evaluationCase.expectations
      )
      let nonPassingSignals = quality.signals
        .filter { $0.status != .passed }
        .map { "\($0.id.rawValue):\($0.status.rawValue)" }
        .joined(separator: ",")
      let metrics = trace.snapshot
      records.append(
        TutorLatencyBenchmarkRecord(
          id: trace.id,
          runNumber: runNumber,
          caseID: evaluationCase.id,
          caseName: evaluationCase.name,
          model: metrics.modelIdentifier ?? snapshot.model,
          responseFormat: selectedFormat,
          maxOutputTokens: tokenBudget,
          metrics: metrics,
          qualityRating: quality.rating,
          succeeded: true
        )
      )
      log(
        record: records.last!,
        nonPassingSignals: nonPassingSignals.isEmpty ? "none" : nonPassingSignals
      )
      activeProvider = nil
      return true
    } catch is CancellationError {
      return false
    } catch {
      let metrics = trace.snapshot
      records.append(
        TutorLatencyBenchmarkRecord(
          id: trace.id,
          runNumber: runNumber,
          caseID: evaluationCase.id,
          caseName: evaluationCase.name,
          model: metrics.modelIdentifier ?? snapshot.model,
          responseFormat: selectedFormat,
          maxOutputTokens: tokenBudget,
          metrics: metrics,
          qualityRating: nil,
          succeeded: false
        )
      )
      failureMessage = Self.failureDescription(error)
      AppLogger.tutorRuntime.error(
        "Tutor benchmark failed run=\(runNumber, privacy: .public) stage=pipeline error=\(String(describing: error), privacy: .public)"
      )
      activeProvider = nil
      return false
    }
  }

  private func makeSnapshot(
    from base: TutorProviderConfigurationSnapshot
  ) -> TutorProviderConfigurationSnapshot {
    let override = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    let format: OpenAICompatibleResponseFormat
    switch responseFormat {
    case .providerDefault: format = base.responseFormat
    case .jsonSchema: format = .jsonSchema
    case .jsonObject: format = .jsonObject
    }
    return TutorProviderConfigurationSnapshot(
      profileID: base.profileID,
      endpoint: base.endpoint,
      model: override.isEmpty ? base.model : override,
      responseFormat: format,
      temperature: base.temperature,
      maxOutputTokens: maxOutputTokens,
      credentialReference: base.credentialReference,
      credential: base.credential
    )
  }

  private func cancelActiveWork() {
    activeTask?.cancel()
    activeTask = nil
    if let activeProvider {
      Task { await activeProvider.cancel() }
    }
    activeProvider = nil
  }

  private func clearActiveWork() {
    activeTask = nil
    activeProvider = nil
  }

  private func log(
    record: TutorLatencyBenchmarkRecord,
    nonPassingSignals: String
  ) {
    let metrics = record.metrics
    let prompt = metrics.promptSize
    AppLogger.tutorRuntime.info(
      "Tutor benchmark run=\(record.runNumber, privacy: .public) case=\(record.caseID, privacy: .public) model=\(record.model, privacy: .public) total_ms=\(Self.ms(metrics.totalTutorLatency), privacy: .public) ttfb_ms=\(Self.ms(metrics.timeToFirstByte), privacy: .public) generation_ms=\(Self.ms(metrics.generationDuration), privacy: .public) content_ms=\(Self.ms(metrics.currentContentLatency), privacy: .public) prompt_ms=\(Self.ms(metrics.promptBuildLatency), privacy: .public) setup_ms=\(Self.ms(metrics.requestSetupLatency), privacy: .public) decode_ms=\(Self.ms(metrics.decodeLatency), privacy: .public) validation_ms=\(Self.ms(metrics.validationLatency), privacy: .public) presentation_ms=\(Self.ms(metrics.presentationLatency), privacy: .public) input_tokens=\(metrics.inputTokens.map(String.init) ?? "unavailable", privacy: .public) output_tokens=\(metrics.outputTokens.map(String.init) ?? "unavailable", privacy: .public) system_chars=\(prompt.map { String($0.systemInstructionCharacters) } ?? "unavailable", privacy: .public) rules_chars=\(prompt.map { String($0.constraintsCharacters) } ?? "unavailable", privacy: .public) schema_chars=\(prompt.map { String($0.outputSchemaCharacters) } ?? "unavailable", privacy: .public) user_chars=\(prompt.map { String($0.userContentCharacters) } ?? "unavailable", privacy: .public) source_chars=\(prompt.map { String($0.sourceCharacters) } ?? "unavailable", privacy: .public) quality=\(record.qualityRating?.rawValue ?? "unavailable", privacy: .public) review_signals=\(nonPassingSignals, privacy: .public)"
    )
  }

  private static func ms(_ duration: TimeInterval?) -> String {
    duration.map { String(Int(($0 * 1_000).rounded())) } ?? "unavailable"
  }

  private static func failureDescription(_ error: Error) -> String {
    if let providerError = error as? LLMProviderError {
      return "Provider failure: \(String(describing: providerError))"
    }
    if let engineError = error as? TutorEngineError {
      return "Tutor pipeline failure: \(String(describing: engineError))"
    }
    return "Benchmark request failed."
  }
}
#endif
