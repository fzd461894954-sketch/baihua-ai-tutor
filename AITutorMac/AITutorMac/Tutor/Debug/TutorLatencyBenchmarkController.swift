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

enum TutorLatencyBenchmarkFormat: String, CaseIterable, Identifiable, Sendable, Hashable {
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

enum TutorBenchmarkTransportMode: String, CaseIterable, Identifiable, Sendable, Hashable {
  case nonStreaming
  case streaming

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .nonStreaming: return "non-stream"
    case .streaming: return "stream"
    }
  }
}

struct TutorBenchmarkQualitySignals: Equatable, Sendable {
  let unsupportedFacts: TutorQualitySignalStatus
  let missingStructure: TutorQualitySignalStatus
  let verbosity: TutorQualitySignalStatus
  let sourceAlignment: TutorQualitySignalStatus

  init(report: TutorQualityReport) {
    unsupportedFacts = report.signal(for: .unsupportedFacts)?.status ?? .failed
    missingStructure = report.signal(for: .teachingStructure)?.status ?? .failed
    verbosity = report.signal(for: .responseLength)?.status ?? .failed
    sourceAlignment = report.signal(for: .sourceAlignment)?.status ?? .failed
  }
}

struct TutorStreamModelBenchmarkRecord: Identifiable, Equatable, Sendable {
  let id: UUID
  let requestID: UUID
  let runNumber: Int
  let caseID: String
  let caseName: String
  let model: String
  let responseFormat: TutorLatencyBenchmarkFormat
  let mode: TutorBenchmarkTransportMode
  let maxOutputTokens: Int
  let metrics: TutorLatencyMetrics
  let qualityRating: TutorQualityRating?
  let qualitySignals: TutorBenchmarkQualitySignals?
  let succeeded: Bool
}

struct TutorStreamModelBenchmarkConfigurationSummary: Identifiable, Equatable, Sendable {
  let model: String
  let responseFormat: TutorLatencyBenchmarkFormat
  let mode: TutorBenchmarkTransportMode
  let successfulRuns: Int
  let failedRuns: Int
  let qualityPasses: Int
  let qualityNeedsReview: Int
  let qualityFailures: Int
  let latency: TutorLatencyBenchmarkSummary

  var id: String {
    "\(model)|\(responseFormat.rawValue)|\(mode.rawValue)"
  }
}

/// Debug-only streaming/model benchmark. Response content exists only in a
/// stack-local accumulator until the complete JSON is decoded and validated.
/// Observable state and logs contain metadata and quality signals only.
@MainActor
@Observable
final class TutorStreamModelBenchmarkController {
  static let defaultRunCount = 5

  var selectedCaseID = TutorEvaluationDataset.cases.first?.id ?? ""
  var modelOverride = ""
  var candidateModelsText = ""
  var responseFormat = TutorLatencyBenchmarkFormat.providerDefault
  var selectedMode = TutorBenchmarkTransportMode.streaming
  var maxOutputTokens = TutorResponseBudget.compactLesson.maximumOutputTokens

  private(set) var state = TutorLatencyBenchmarkState.idle
  private(set) var records: [TutorStreamModelBenchmarkRecord] = []
  private(set) var completedRuns = 0
  private(set) var targetRuns = 0
  private(set) var failureMessage: String?
  private(set) var activeModel: String?

  var isRunning: Bool { state == .running }

  var configurationSummaries: [TutorStreamModelBenchmarkConfigurationSummary] {
    let grouped = Dictionary(grouping: records) {
      ConfigurationKey(
        model: $0.model,
        responseFormat: $0.responseFormat,
        mode: $0.mode
      )
    }
    return grouped.map { key, values in
      let successful = values.filter(\.succeeded)
      return TutorStreamModelBenchmarkConfigurationSummary(
        model: key.model,
        responseFormat: key.responseFormat,
        mode: key.mode,
        successfulRuns: successful.count,
        failedRuns: values.count - successful.count,
        qualityPasses: values.filter { $0.qualityRating == .passed }.count,
        qualityNeedsReview: values.filter { $0.qualityRating == .needsReview }.count,
        qualityFailures: values.filter { $0.qualityRating == .failed }.count,
        latency: TutorLatencyBenchmarkSummary(metrics: successful.map(\.metrics))
      )
    }
    .sorted { $0.id < $1.id }
  }

  @ObservationIgnored private let providerFactory: any TutorProviderBuilding
  @ObservationIgnored private let providerBuilder: TutorLatencyBenchmarkProviderBuilder
  @ObservationIgnored private let requestFactory: TutorRequestFactory
  @ObservationIgnored private let promptBuilder: TutorPromptBuilder
  @ObservationIgnored private let decoder: TutorResponseDecoder
  @ObservationIgnored private let validator: TutorResponseValidator
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
    decoder: TutorResponseDecoder = TutorResponseDecoder(),
    validator: TutorResponseValidator = TutorResponseValidator(),
    qualityEvaluator: TutorQualityEvaluator = TutorQualityEvaluator(),
    now: @escaping @Sendable () -> Date = { Date() },
    makeID: @escaping @Sendable () -> UUID = { UUID() },
    sessionID: UUID = UUID()
  ) {
    self.providerFactory = providerFactory
    self.providerBuilder = providerBuilder
    self.requestFactory = requestFactory
    self.promptBuilder = promptBuilder
    self.decoder = decoder
    self.validator = validator
    self.qualityEvaluator = qualityEvaluator
    self.now = now
    self.makeID = makeID
    self.sessionID = sessionID
  }

  deinit {
    activeTask?.cancel()
  }

  func runModeComparison() {
    guard let evaluationCase = selectedCase else { return }
    start { base in
      let model = self.effectivePrimaryModel(base: base)
      let format = self.effectiveFormat(base: base)
      return (0..<Self.defaultRunCount).map { _ in
        WorkItem(
          evaluationCase: evaluationCase,
          configurations: [
            Configuration(model: model, responseFormat: format, mode: .nonStreaming),
            Configuration(model: model, responseFormat: format, mode: .streaming),
          ]
        )
      }
    }
  }

  func runModelComparison() {
    guard let evaluationCase = selectedCase else { return }
    start { base in
      let models = self.candidateModels(base: base)
      guard models.count >= 2 else {
        throw BenchmarkSetupError.missingCandidateModel
      }
      let format = self.effectiveFormat(base: base)
      let configurations = models.map {
        Configuration(model: $0, responseFormat: format, mode: self.selectedMode)
      }
      return (0..<Self.defaultRunCount).map { _ in
        WorkItem(evaluationCase: evaluationCase, configurations: configurations)
      }
    }
  }

  func runFormatComparison() {
    guard let evaluationCase = selectedCase else { return }
    start { base in
      let model = self.effectivePrimaryModel(base: base)
      let configurations = [
        Configuration(model: model, responseFormat: .jsonObject, mode: self.selectedMode),
        Configuration(model: model, responseFormat: .jsonSchema, mode: self.selectedMode),
      ]
      return (0..<Self.defaultRunCount).map { _ in
        WorkItem(evaluationCase: evaluationCase, configurations: configurations)
      }
    }
  }

  func runQualityMatrix() {
    start { base in
      let models = self.candidateModels(base: base)
      let format = self.effectiveFormat(base: base)
      let configurations = models.map { model in
        Configuration(model: model, responseFormat: format, mode: self.selectedMode)
      }
      return TutorEvaluationDataset.cases.map {
        WorkItem(evaluationCase: $0, configurations: configurations)
      }
    }
  }

  func cancel() {
    guard isRunning else { return }
    cancelActiveWork()
    state = .cancelled
  }

  func reset() {
    cancelActiveWork()
    records.removeAll(keepingCapacity: false)
    completedRuns = 0
    targetRuns = 0
    failureMessage = nil
    activeModel = nil
    state = .idle
  }

  private var selectedCase: TutorEvaluationCase? {
    TutorEvaluationDataset.caseWithID(selectedCaseID)
  }

  private func start(
    makeWorkItems: @escaping (TutorProviderConfigurationSnapshot) throws -> [WorkItem]
  ) {
    guard !isRunning else { return }
    let base: TutorProviderConfigurationSnapshot
    do {
      base = try providerFactory.configurationSnapshot()
      guard (128...4_096).contains(maxOutputTokens) else {
        throw BenchmarkSetupError.invalidOutputBudget
      }
      let workItems = try makeWorkItems(base)
      guard !workItems.isEmpty else { return }
      begin(workItems: workItems, base: base)
    } catch BenchmarkSetupError.missingCandidateModel {
      failSetup("请先输入当前 Ark 账号已确认可用的候选模型；模型名只保存在内存。")
    } catch BenchmarkSetupError.invalidOutputBudget {
      failSetup("Max Output Tokens 必须在 128–4096 之间。")
    } catch {
      failSetup("无法读取已保存的 Provider Settings / Keychain。")
    }
  }

  private func begin(
    workItems: [WorkItem],
    base: TutorProviderConfigurationSnapshot
  ) {
    cancelActiveWork()
    records.removeAll(keepingCapacity: true)
    completedRuns = 0
    targetRuns = workItems.reduce(0) { $0 + $1.configurations.count }
    failureMessage = nil
    activeModel = base.model
    state = .running
    AppLogger.tutorRuntime.info(
      "Tutor stream/model benchmark started runs=\(self.targetRuns, privacy: .public) active_model=\(base.model, privacy: .public)"
    )

    let tokenBudget = maxOutputTokens
    activeTask = Task { @MainActor [weak self] in
      guard let self else { return }
      var runNumber = 0
      for item in workItems {
        guard !Task.isCancelled else {
          self.state = .cancelled
          return
        }
        let prepared: PreparedCase
        do {
          prepared = try self.prepare(item.evaluationCase)
        } catch {
          self.failureMessage = "Benchmark request preparation failed."
          self.state = .failed
          self.clearActiveWork()
          return
        }
        for configuration in item.configurations {
          guard !Task.isCancelled else {
            self.state = .cancelled
            return
          }
          runNumber += 1
          let record = await self.execute(
            prepared: prepared,
            base: base,
            configuration: configuration,
            tokenBudget: tokenBudget,
            runNumber: runNumber
          )
          self.records.append(record)
          self.completedRuns = runNumber
          self.log(record)
        }
      }
      self.state = self.records.allSatisfy(\.succeeded) ? .completed : .failed
      if self.state == .failed, self.failureMessage == nil {
        self.failureMessage = "至少一个配置未通过完整 Decode / Validate pipeline。"
      }
      AppLogger.tutorRuntime.info(
        "Tutor stream/model benchmark completed runs=\(self.completedRuns, privacy: .public) succeeded=\(self.records.filter(\.succeeded).count, privacy: .public) failed=\(self.records.filter { !$0.succeeded }.count, privacy: .public)"
      )
      self.clearActiveWork()
    }
  }

  private func prepare(_ evaluationCase: TutorEvaluationCase) throws -> PreparedCase {
    let startedAt = now()
    nextSequence += 1
    let request = try requestFactory.make(
      from: evaluationCase.semanticChunk,
      sessionID: sessionID,
      sequence: nextSequence,
      learner: .productDefault(at: startedAt),
      trigger: .userInitiated,
      output: .default(language: "zh-Hans")
    )
    return PreparedCase(
      evaluationCase: evaluationCase,
      request: request,
      prompt: try promptBuilder.build(from: request)
    )
  }

  private func execute(
    prepared: PreparedCase,
    base: TutorProviderConfigurationSnapshot,
    configuration: Configuration,
    tokenBudget: Int,
    runNumber: Int
  ) async -> TutorStreamModelBenchmarkRecord {
    let trace = TutorLatencyTrace(id: makeID(), userActionAt: now(), now: now)
    trace.markContentResolved()
    trace.markRequestCreated(requestID: prepared.request.id)
    trace.markPromptBuilt(
      prepared.prompt,
      sourceCharacterCount: prepared.request.source.text.count
    )
    let snapshot = makeSnapshot(
      from: base,
      configuration: configuration,
      tokenBudget: tokenBudget
    )
    let provider = providerBuilder(snapshot)
    activeProvider = provider

    do {
      let raw = try await rawResponse(
        provider: provider,
        prompt: prepared.prompt,
        mode: configuration.mode,
        trace: trace,
        fallbackModel: configuration.model
      )
      try Task.checkCancellation()
      let decoded = try decoder.decode(raw)
      trace.markDecoded()
      let validated = try validator.validate(decoded, for: prepared.request)
      trace.markValidated()
      trace.markPresentationReady()
      trace.markPanelPresented()
      let quality = qualityEvaluator.evaluate(
        validated,
        for: prepared.request,
        expectations: prepared.evaluationCase.expectations
      )
      activeProvider = nil
      return makeRecord(
        prepared: prepared,
        configuration: configuration,
        tokenBudget: tokenBudget,
        runNumber: runNumber,
        trace: trace,
        quality: quality,
        succeeded: true
      )
    } catch {
      activeProvider = nil
      return makeRecord(
        prepared: prepared,
        configuration: configuration,
        tokenBudget: tokenBudget,
        runNumber: runNumber,
        trace: trace,
        quality: nil,
        succeeded: false
      )
    }
  }

  private func rawResponse(
    provider: any LLMProvider,
    prompt: PromptPackage,
    mode: TutorBenchmarkTransportMode,
    trace: TutorLatencyTrace,
    fallbackModel: String
  ) async throws -> RawLLMResponse {
    trace.markHTTPStarted()
    switch mode {
    case .nonStreaming:
      let raw = try await provider.generate(from: prompt, latencyTrace: trace)
      trace.markNetworkCompleted()
      trace.recordUsage(raw.usage)
      trace.recordModelIdentifier(raw.providerMetadata.modelIdentifier)
      return raw
    case .streaming:
      let stream = await provider.stream(from: prompt, latencyTrace: trace)
      var content = ""
      var finishReason: LLMFinishReason?
      var usage = LLMUsageMetadata.unavailable
      var metadata = LLMProviderMetadata(
        providerIdentifier: "openai-compatible",
        modelIdentifier: fallbackModel,
        requestIdentifier: nil,
        values: [:]
      )
      for try await chunk in stream {
        trace.markFirstSSEEvent()
        if !chunk.contentDelta.isEmpty {
          trace.markFirstSSEContent()
          content.append(chunk.contentDelta)
        }
        if let value = chunk.finishReason { finishReason = value }
        if let value = chunk.usage {
          usage = value
          trace.recordUsage(value)
        }
        metadata = chunk.providerMetadata
        trace.recordModelIdentifier(chunk.providerMetadata.modelIdentifier)
      }
      trace.markNetworkCompleted()
      guard content.contains(where: { !$0.isWhitespace }) else {
        throw LLMProviderError.invalidResponse
      }
      return RawLLMResponse(
        content: content,
        finishReason: finishReason,
        usage: usage,
        providerMetadata: metadata
      )
    }
  }

  private func makeRecord(
    prepared: PreparedCase,
    configuration: Configuration,
    tokenBudget: Int,
    runNumber: Int,
    trace: TutorLatencyTrace,
    quality: TutorQualityReport?,
    succeeded: Bool
  ) -> TutorStreamModelBenchmarkRecord {
    let metrics = trace.snapshot
    return TutorStreamModelBenchmarkRecord(
      id: trace.id,
      requestID: prepared.request.id,
      runNumber: runNumber,
      caseID: prepared.evaluationCase.id,
      caseName: prepared.evaluationCase.name,
      model: configuration.model,
      responseFormat: configuration.responseFormat,
      mode: configuration.mode,
      maxOutputTokens: tokenBudget,
      metrics: metrics,
      qualityRating: quality?.rating,
      qualitySignals: quality.map(TutorBenchmarkQualitySignals.init(report:)),
      succeeded: succeeded
    )
  }

  private func makeSnapshot(
    from base: TutorProviderConfigurationSnapshot,
    configuration: Configuration,
    tokenBudget: Int
  ) -> TutorProviderConfigurationSnapshot {
    let format: OpenAICompatibleResponseFormat
    switch configuration.responseFormat {
    case .providerDefault: format = base.responseFormat
    case .jsonSchema: format = .jsonSchema
    case .jsonObject: format = .jsonObject
    }
    return TutorProviderConfigurationSnapshot(
      profileID: base.profileID,
      endpoint: base.endpoint,
      model: configuration.model,
      responseFormat: format,
      temperature: base.temperature,
      maxOutputTokens: tokenBudget,
      credentialReference: base.credentialReference,
      credential: base.credential
    )
  }

  private func effectivePrimaryModel(
    base: TutorProviderConfigurationSnapshot
  ) -> String {
    let value = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? base.model : value
  }

  private func effectiveFormat(
    base: TutorProviderConfigurationSnapshot
  ) -> TutorLatencyBenchmarkFormat {
    guard responseFormat == .providerDefault else { return responseFormat }
    switch base.responseFormat {
    case .jsonSchema: return .jsonSchema
    case .jsonObject: return .jsonObject
    case .unsupported: return .providerDefault
    }
  }

  private func candidateModels(
    base: TutorProviderConfigurationSnapshot
  ) -> [String] {
    let rawCandidates = candidateModelsText
      .components(separatedBy: CharacterSet(charactersIn: ",\n"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    var seen = Set<String>()
    return ([base.model] + rawCandidates).filter { seen.insert($0).inserted }
  }

  private func failSetup(_ message: String) {
    failureMessage = message
    state = .failed
    AppLogger.tutorRuntime.error("Tutor stream/model benchmark setup failed")
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

  private func log(_ record: TutorStreamModelBenchmarkRecord) {
    let metrics = record.metrics
    let signals = record.qualitySignals
    AppLogger.tutorRuntime.info(
      "Tutor stream/model benchmark run=\(record.runNumber, privacy: .public) case=\(record.caseID, privacy: .public) model=\(record.model, privacy: .public) format=\(record.responseFormat.rawValue, privacy: .public) mode=\(record.mode.rawValue, privacy: .public) ttfb_ms=\(Self.ms(metrics.timeToFirstByte), privacy: .public) first_event_ms=\(Self.ms(metrics.timeToFirstSSEEvent), privacy: .public) first_content_ms=\(Self.ms(metrics.timeToFirstModelContent), privacy: .public) full_ms=\(Self.ms(metrics.totalTutorLatency), privacy: .public) input_tokens=\(metrics.inputTokens.map(String.init) ?? "unavailable", privacy: .public) output_tokens=\(metrics.outputTokens.map(String.init) ?? "unavailable", privacy: .public) quality=\(record.qualityRating?.rawValue ?? "failed", privacy: .public) unsupported_facts=\(signals?.unsupportedFacts.rawValue ?? "unavailable", privacy: .public) missing_structure=\(signals?.missingStructure.rawValue ?? "unavailable", privacy: .public) verbosity=\(signals?.verbosity.rawValue ?? "unavailable", privacy: .public) source_alignment=\(signals?.sourceAlignment.rawValue ?? "unavailable", privacy: .public)"
    )
  }

  private static func ms(_ duration: TimeInterval?) -> String {
    duration.map { String(Int(($0 * 1_000).rounded())) } ?? "unavailable"
  }

  private struct Configuration: Sendable {
    let model: String
    let responseFormat: TutorLatencyBenchmarkFormat
    let mode: TutorBenchmarkTransportMode
  }

  private struct ConfigurationKey: Hashable {
    let model: String
    let responseFormat: TutorLatencyBenchmarkFormat
    let mode: TutorBenchmarkTransportMode
  }

  private struct WorkItem: Sendable {
    let evaluationCase: TutorEvaluationCase
    let configurations: [Configuration]
  }

  private struct PreparedCase: Sendable {
    let evaluationCase: TutorEvaluationCase
    let request: TutorRequest
    let prompt: PromptPackage
  }

  private enum BenchmarkSetupError: Error {
    case missingCandidateModel
    case invalidOutputBudget
  }
}
#endif
