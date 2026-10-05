#if DEBUG
import Foundation
import Observation

struct DebugLLMConfiguration: Equatable, Sendable {
  var endpoint = ""
  var model = ""
  var apiKey = ""
}

enum TutorRealDemoState: String, Equatable, Sendable {
  case idle
  case running
  case succeeded
  case failed
  case cancelled
}

enum TutorRealDemoFailure: String, Equatable, Sendable {
  case invalidEndpoint
  case unsupportedEndpoint
  case emptyModel
  case emptyAPIKey
  case emptySource
  case sourceTooLong
  case timeout
  case unavailable
  case invalidJSON
  case invalidModelOutput
  case validationFailed
  case requestFailed

  var displayText: String {
    switch self {
    case .invalidEndpoint:
      return "Endpoint 必须是有效的 HTTP(S) URL"
    case .unsupportedEndpoint:
      return "Endpoint 必须使用 Chat Completions 地址"
    case .emptyModel:
      return "Model 不能为空"
    case .emptyAPIKey:
      return "API Key 不能为空"
    case .emptySource:
      return "待解释内容不能为空"
    case .sourceTooLong:
      return "待解释内容超过当前 1,000 字符限制"
    case .timeout:
      return "模型请求超时"
    case .unavailable:
      return "模型服务或网络不可用"
    case .invalidJSON:
      return "模型未返回可解码的 JSON"
    case .invalidModelOutput:
      return "模型输出不完整或不符合响应形状"
    case .validationFailed:
      return "TutorResponse 未通过业务校验"
    case .requestFailed:
      return "无法构建或完成本次 Tutor 请求"
    }
  }
}

enum TutorRealDemoRunOutcome: String, Equatable, Sendable {
  case success
  case failure
  case cancelled
}

/// Privacy-safe run telemetry. It intentionally has no source, prompt, endpoint,
/// model, credential, raw response, or rendered response field.
struct TutorRealDemoRunRecord: Identifiable, Equatable, Sendable {
  let id: UUID
  let startedAt: Date
  let latencyMilliseconds: Int
  let inputTokenCount: Int?
  let outputTokenCount: Int?
  let totalTokenCount: Int?
  let outcome: TutorRealDemoRunOutcome
  let failure: TutorRealDemoFailure?
  let qualityRating: TutorQualityRating?
}

typealias TutorRealDemoProviderFactory = @Sendable (
  DebugLLMConfiguration
) throws -> any LLMProvider

let tutorRealDemoLiveProvider: TutorRealDemoProviderFactory = { configuration in
  guard let endpoint = URL(string: configuration.endpoint) else {
    throw TutorRealDemoFailureError(.invalidEndpoint)
  }
  return OpenAICompatibleProvider(
    endpoint: endpoint,
    model: configuration.model,
    apiKey: configuration.apiKey,
    temperature: 0.2,
    maxTokens: 1_800,
    responseFormat: tutorRealDemoResponseFormat(for: endpoint),
    requestTimeout: 60
  )
}

/// Ark Chat Completions accepts JSON mode, but its structured-output schema
/// subset rejects parts of the full TutorResponse contract. JSON mode keeps the
/// schema in the prompt while Decoder and Validator remain authoritative.
func tutorRealDemoResponseFormat(
  for endpoint: URL
) -> OpenAICompatibleResponseFormat {
  guard endpoint.host?.lowercased().hasSuffix(".volces.com") == true else {
    return .jsonSchema
  }
  return .jsonObject
}

@MainActor
@Observable
final class TutorRealDemoController {
  static let maximumSourceCharacterCount = TutorRequest.defaultMaximumSourceCharacterCount
  static let maximumRunRecordCount = 20

  var configuration: DebugLLMConfiguration {
    get { configurationStore.configuration }
    set { configurationStore.configuration = newValue }
  }
  var selectedCaseID = TutorEvaluationDataset.cases.first?.id ?? ""
  var sourceText = TutorEvaluationDataset.cases.first?.semanticChunk.text ?? ""

  private(set) var state: TutorRealDemoState = .idle
  private(set) var latestResponse: TutorResponse?
  private(set) var latestPresentation: TutorPresentationModel?
  private(set) var latestQualityReport: TutorQualityReport?
  private(set) var latestFailure: TutorRealDemoFailure?
  private(set) var runRecords: [TutorRealDemoRunRecord] = []

  var isRunning: Bool {
    state == .running
  }

  var latestRunRecord: TutorRealDemoRunRecord? {
    runRecords.first
  }

  var selectedCase: TutorEvaluationCase? {
    TutorEvaluationDataset.caseWithID(selectedCaseID)
  }

  var isUsingSelectedCaseBody: Bool {
    selectedCase?.semanticChunk.text == sourceText
  }

  @ObservationIgnored private let requestFactory: TutorRequestFactory
  @ObservationIgnored private let configurationStore: DebugLLMConfigurationStore
  @ObservationIgnored private let promptBuilder: TutorPromptBuilder
  @ObservationIgnored private let decoder: TutorResponseDecoder
  @ObservationIgnored private let validator: TutorResponseValidator
  @ObservationIgnored private let presentationMapper: TutorPresentationMapper
  @ObservationIgnored private let qualityEvaluator: TutorQualityEvaluator
  @ObservationIgnored private let providerFactory: TutorRealDemoProviderFactory
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let makeID: @Sendable () -> UUID
  @ObservationIgnored private let sessionID: UUID
  @ObservationIgnored private var nextSequence = 0
  @ObservationIgnored private var activeRunID: UUID?
  @ObservationIgnored private var activeStartedAt: Date?
  @ObservationIgnored private var activeProvider: (any LLMProvider)?
  @ObservationIgnored private var activeTask: Task<Void, Never>?

  init(
    configurationStore: DebugLLMConfigurationStore? = nil,
    requestFactory: TutorRequestFactory = TutorRequestFactory(),
    promptBuilder: TutorPromptBuilder = TutorPromptBuilder(),
    decoder: TutorResponseDecoder = TutorResponseDecoder(),
    validator: TutorResponseValidator = TutorResponseValidator(),
    presentationMapper: TutorPresentationMapper = TutorPresentationMapper(),
    qualityEvaluator: TutorQualityEvaluator = TutorQualityEvaluator(),
    providerFactory: @escaping TutorRealDemoProviderFactory = tutorRealDemoLiveProvider,
    now: @escaping @Sendable () -> Date = { Date() },
    makeID: @escaping @Sendable () -> UUID = { UUID() },
    sessionID: UUID = UUID()
  ) {
    self.configurationStore = configurationStore ?? DebugLLMConfigurationStore()
    self.requestFactory = requestFactory
    self.promptBuilder = promptBuilder
    self.decoder = decoder
    self.validator = validator
    self.presentationMapper = presentationMapper
    self.qualityEvaluator = qualityEvaluator
    self.providerFactory = providerFactory
    self.now = now
    self.makeID = makeID
    self.sessionID = sessionID
  }

  deinit {
    activeTask?.cancel()
  }

  func prepareForDisplay() {
    guard !sourceText.contains(where: { !$0.isWhitespace }) else {
      return
    }
    let caseID = TutorEvaluationDataset.caseWithID(selectedCaseID)?.id
      ?? TutorEvaluationDataset.cases.first?.id
    if let caseID {
      selectCase(id: caseID)
    }
  }

  func selectCase(id: String) {
    guard !isRunning, let evaluationCase = TutorEvaluationDataset.caseWithID(id) else {
      return
    }
    selectedCaseID = evaluationCase.id
    sourceText = evaluationCase.semanticChunk.text
    latestResponse = nil
    latestPresentation = nil
    latestQualityReport = nil
    latestFailure = nil
    runRecords.removeAll(keepingCapacity: true)
  }

  func explain() {
    guard !isRunning else {
      return
    }

    let startedAt = now()
    let runID = makeID()
    latestResponse = nil
    latestPresentation = nil
    latestQualityReport = nil
    latestFailure = nil

    let effectiveConfiguration: DebugLLMConfiguration
    do {
      effectiveConfiguration = try Self.validated(configuration)
      try Self.validateSource(sourceText)
    } catch let failure as TutorRealDemoFailureError {
      finishFailure(failure.value, runID: runID, startedAt: startedAt)
      return
    } catch {
      finishFailure(.requestFailed, runID: runID, startedAt: startedAt)
      return
    }

    let provider: any LLMProvider
    do {
      provider = try providerFactory(effectiveConfiguration)
    } catch {
      finishFailure(
        Self.failure(from: error) ?? .requestFailed,
        runID: runID,
        startedAt: startedAt
      )
      return
    }

    nextSequence += 1
    let sequence = nextSequence
    let evaluationCase = selectedCase
    let usesEvaluationCase = evaluationCase?.semanticChunk.text == sourceText
    let expectations = usesEvaluationCase
      ? evaluationCase?.expectations ?? .default
      : .default
    let chunk = usesEvaluationCase
      ? evaluationCase?.semanticChunk ?? makeManualChunk(sequence: sequence, createdAt: startedAt)
      : makeManualChunk(sequence: sequence, createdAt: startedAt)

    activeRunID = runID
    activeStartedAt = startedAt
    activeProvider = provider
    state = .running
    activeTask = Task { [weak self] in
      guard let self else {
        return
      }
      var usage = LLMUsageMetadata.unavailable
      do {
        let request = try requestFactory.make(
          from: chunk,
          sessionID: sessionID,
          sequence: sequence,
          learner: .productDefault(at: startedAt),
          trigger: .userInitiated,
          output: .default(language: "zh-Hans")
        )
        let prompt = try promptBuilder.build(from: request)
        let rawResponse = try await provider.generate(from: prompt)
        usage = rawResponse.usage
        try Task.checkCancellation()
        let decodedResponse = try decoder.decode(rawResponse)
        let response = try validator.validate(decodedResponse, for: request)
        let presentation = presentationMapper.makePresentation(from: response)
        let quality = qualityEvaluator.evaluate(
          response,
          for: request,
          expectations: expectations
        )
        finishSuccess(
          response: response,
          presentation: presentation,
          usage: rawResponse.usage,
          quality: quality,
          runID: runID,
          startedAt: startedAt
        )
      } catch {
        guard activeRunID == runID else {
          return
        }
        let failure = Self.failure(from: error)
        if failure == nil {
          finishCancellation(runID: runID, startedAt: startedAt)
        } else {
          finishFailure(
            failure ?? .requestFailed,
            runID: runID,
            startedAt: startedAt,
            usage: usage
          )
        }
      }
    }
  }

  func cancel() {
    guard
      let runID = activeRunID,
      let startedAt = activeStartedAt
    else {
      return
    }
    cancelActiveProvider()
    finishCancellation(runID: runID, startedAt: startedAt)
  }

  func shutdown() {
    dismiss()
    configurationStore.clear()
  }

  /// Closing the Debug window must not destroy the process-memory provider
  /// configuration needed by Tutor Panel. App shutdown remains authoritative.
  func dismiss() {
    cancelActiveProvider()
    activeRunID = nil
    activeStartedAt = nil
    sourceText = ""
    latestResponse = nil
    latestPresentation = nil
    latestQualityReport = nil
    latestFailure = nil
    runRecords.removeAll(keepingCapacity: false)
    state = .idle
  }

  private func finishSuccess(
    response: TutorResponse,
    presentation: TutorPresentationModel,
    usage: LLMUsageMetadata,
    quality: TutorQualityReport,
    runID: UUID,
    startedAt: Date
  ) {
    guard activeRunID == runID else {
      return
    }
    latestResponse = response
    latestPresentation = presentation
    latestQualityReport = quality
    latestFailure = nil
    appendRecord(
      TutorRealDemoRunRecord(
        id: runID,
        startedAt: startedAt,
        latencyMilliseconds: latency(from: startedAt),
        inputTokenCount: usage.inputTokenCount,
        outputTokenCount: usage.outputTokenCount,
        totalTokenCount: usage.totalTokenCount,
        outcome: .success,
        failure: nil,
        qualityRating: quality.rating
      )
    )
    clearActiveRun()
    state = .succeeded
  }

  private func finishFailure(
    _ failure: TutorRealDemoFailure,
    runID: UUID,
    startedAt: Date,
    usage: LLMUsageMetadata = .unavailable
  ) {
    if let activeRunID, activeRunID != runID {
      return
    }
    latestFailure = failure
    appendRecord(
      TutorRealDemoRunRecord(
        id: runID,
        startedAt: startedAt,
        latencyMilliseconds: latency(from: startedAt),
        inputTokenCount: usage.inputTokenCount,
        outputTokenCount: usage.outputTokenCount,
        totalTokenCount: usage.totalTokenCount,
        outcome: .failure,
        failure: failure,
        qualityRating: nil
      )
    )
    clearActiveRun()
    state = .failed
  }

  private func finishCancellation(runID: UUID, startedAt: Date) {
    guard activeRunID == runID else {
      return
    }
    latestFailure = nil
    appendRecord(
      TutorRealDemoRunRecord(
        id: runID,
        startedAt: startedAt,
        latencyMilliseconds: latency(from: startedAt),
        inputTokenCount: nil,
        outputTokenCount: nil,
        totalTokenCount: nil,
        outcome: .cancelled,
        failure: nil,
        qualityRating: nil
      )
    )
    clearActiveRun()
    state = .cancelled
  }

  private func cancelActiveProvider() {
    activeTask?.cancel()
    activeTask = nil
    if let provider = activeProvider {
      Task {
        await provider.cancel()
      }
    }
  }

  private func clearActiveRun() {
    activeTask = nil
    activeProvider = nil
    activeRunID = nil
    activeStartedAt = nil
  }

  private func appendRecord(_ record: TutorRealDemoRunRecord) {
    runRecords.insert(record, at: 0)
    if runRecords.count > Self.maximumRunRecordCount {
      runRecords.removeLast(runRecords.count - Self.maximumRunRecordCount)
    }
  }

  private func latency(from startedAt: Date) -> Int {
    max(0, Int((now().timeIntervalSince(startedAt) * 1_000).rounded()))
  }

  private func makeManualChunk(
    sequence: Int,
    createdAt: Date
  ) -> SemanticChunk {
    SemanticChunk(
      id: makeID(),
      sourceRevisionID: sequence,
      text: sourceText,
      confidence: .high,
      createdAt: createdAt,
      flushReason: .manualFlush
    )
  }

  private static func validated(
    _ configuration: DebugLLMConfiguration
  ) throws -> DebugLLMConfiguration {
    let endpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let url = URL(string: endpoint),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil
    else {
      throw TutorRealDemoFailureError(.invalidEndpoint)
    }
    guard url.path.lowercased().hasSuffix("/chat/completions") else {
      throw TutorRealDemoFailureError(.unsupportedEndpoint)
    }
    guard !model.isEmpty else {
      throw TutorRealDemoFailureError(.emptyModel)
    }
    guard !apiKey.isEmpty else {
      throw TutorRealDemoFailureError(.emptyAPIKey)
    }
    return DebugLLMConfiguration(endpoint: url.absoluteString, model: model, apiKey: apiKey)
  }

  private static func validateSource(_ sourceText: String) throws {
    guard sourceText.contains(where: { !$0.isWhitespace }) else {
      throw TutorRealDemoFailureError(.emptySource)
    }
    guard sourceText.count <= maximumSourceCharacterCount else {
      throw TutorRealDemoFailureError(.sourceTooLong)
    }
  }

  private static func failure(from error: Error) -> TutorRealDemoFailure? {
    if error is CancellationError {
      return nil
    }
    if let inputFailure = error as? TutorRealDemoFailureError {
      return inputFailure.value
    }
    if let providerError = error as? LLMProviderError {
      switch providerError {
      case .timeout:
        return .timeout
      case .cancelled:
        return nil
      case .invalidResponse:
        return .invalidModelOutput
      case .unavailable:
        return .unavailable
      case .decodingFailed:
        return .invalidJSON
      case .authenticationFailed,
           .modelUnavailable,
           .rateLimited,
           .networkUnavailable:
        return .unavailable
      case .invalidEndpoint:
        return .invalidEndpoint
      }
    }
    if let engineError = error as? TutorEngineError {
      switch engineError {
      case .cancelled:
        return nil
      case let .provider(providerError):
        return failure(from: providerError)
      case let .invalidRequest(issue):
      switch issue {
        case .emptySourceText:
          return .emptySource
        case .sourceTextTooLong:
          return .sourceTooLong
        default:
          return .requestFailed
        }
      case .invalidResponse:
        return .validationFailed
      case .unavailable:
        return .unavailable
      case .generationFailed:
        return .requestFailed
      }
    }
    return .requestFailed
  }

}

private struct TutorRealDemoFailureError: Error, Equatable, Sendable {
  let value: TutorRealDemoFailure

  init(_ value: TutorRealDemoFailure) {
    self.value = value
  }
}
#endif
