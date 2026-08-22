import Foundation

struct TutorPromptSizeMetrics: Equatable, Sendable {
  let systemInstructionCharacters: Int
  let constraintsCharacters: Int
  let outputSchemaCharacters: Int
  let userContentCharacters: Int
  let sourceCharacters: Int

  var totalPromptCharacters: Int {
    systemInstructionCharacters
      + constraintsCharacters
      + outputSchemaCharacters
      + userContentCharacters
  }

  /// A planning estimate only. Provider usage remains authoritative when present.
  var estimatedInputTokens: Int {
    guard totalPromptCharacters > 0 else {
      return 0
    }
    return Int(ceil(Double(totalPromptCharacters) / 4.0))
  }

  static func measure(
    _ prompt: PromptPackage,
    sourceCharacterCount: Int
  ) -> TutorPromptSizeMetrics {
    TutorPromptSizeMetrics(
      systemInstructionCharacters: prompt.systemInstruction.count,
      constraintsCharacters: prompt.constraints.reduce(0) { $0 + $1.count },
      outputSchemaCharacters: prompt.outputSchema.count,
      userContentCharacters: prompt.userContent.count,
      sourceCharacters: max(0, sourceCharacterCount)
    )
  }
}

struct TutorLatencyMetrics: Equatable, Sendable {
  let traceID: UUID
  let requestID: UUID?
  let modelIdentifier: String?

  let userActionAt: Date
  let contentResolvedAt: Date?
  let requestCreatedAt: Date?
  let promptBuiltAt: Date?
  let httpStartedAt: Date?
  let firstResponseByteAt: Date?
  let firstSSEContentAt: Date?
  let networkCompletedAt: Date?
  let decodedAt: Date?
  let validatedAt: Date?
  let presentationReadyAt: Date?
  let panelPresentedAt: Date?

  let inputTokens: Int?
  let outputTokens: Int?
  let totalTokens: Int?
  let promptSize: TutorPromptSizeMetrics?

  var currentContentLatency: TimeInterval? {
    duration(from: userActionAt, to: contentResolvedAt)
  }

  var promptBuildLatency: TimeInterval? {
    duration(from: requestCreatedAt, to: promptBuiltAt)
  }

  var requestSetupLatency: TimeInterval? {
    duration(from: promptBuiltAt ?? requestCreatedAt, to: httpStartedAt)
  }

  var timeToFirstByte: TimeInterval? {
    duration(from: httpStartedAt, to: firstResponseByteAt)
  }

  var timeToFirstModelContent: TimeInterval? {
    duration(from: httpStartedAt, to: firstSSEContentAt)
  }

  var generationDuration: TimeInterval? {
    // A non-streaming response exposes no trustworthy model-generation
    // boundary: provider queueing and generation are folded into TTFB.
    duration(from: firstSSEContentAt, to: networkCompletedAt)
  }

  var responseTransferDuration: TimeInterval? {
    duration(from: firstResponseByteAt, to: networkCompletedAt)
  }

  var decodeLatency: TimeInterval? {
    duration(from: networkCompletedAt, to: decodedAt)
  }

  var validationLatency: TimeInterval? {
    duration(from: decodedAt, to: validatedAt)
  }

  var presentationLatency: TimeInterval? {
    duration(from: validatedAt, to: presentationReadyAt)
  }

  var totalTutorLatency: TimeInterval? {
    duration(from: userActionAt, to: panelPresentedAt)
  }

  private func duration(from start: Date?, to end: Date?) -> TimeInterval? {
    guard let start, let end else {
      return nil
    }
    return max(0, end.timeIntervalSince(start))
  }
}

/// One privacy-safe trace per explicit Tutor request. Only timestamps, counts,
/// opaque identifiers, model metadata, and provider-reported usage are retained.
final class TutorLatencyTrace: @unchecked Sendable {
  private struct State {
    var requestID: UUID?
    var modelIdentifier: String?
    var contentResolvedAt: Date?
    var requestCreatedAt: Date?
    var promptBuiltAt: Date?
    var httpStartedAt: Date?
    var firstResponseByteAt: Date?
    var firstSSEContentAt: Date?
    var networkCompletedAt: Date?
    var decodedAt: Date?
    var validatedAt: Date?
    var presentationReadyAt: Date?
    var panelPresentedAt: Date?
    var usage = LLMUsageMetadata.unavailable
    var promptSize: TutorPromptSizeMetrics?
  }

  let id: UUID
  let userActionAt: Date

  private let lock = NSLock()
  private let now: @Sendable () -> Date
  private var state = State()

  init(
    id: UUID = UUID(),
    userActionAt: Date = Date(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.id = id
    self.userActionAt = userActionAt
    self.now = now
  }

  func markContentResolved(at date: Date? = nil) {
    update { setOnce(&$0.contentResolvedAt, date ?? now()) }
  }

  func markRequestCreated(requestID: UUID, at date: Date? = nil) {
    update {
      $0.requestID = $0.requestID ?? requestID
      setOnce(&$0.requestCreatedAt, date ?? now())
    }
  }

  func markPromptBuilt(
    _ prompt: PromptPackage,
    sourceCharacterCount: Int,
    at date: Date? = nil
  ) {
    update {
      setOnce(&$0.promptBuiltAt, date ?? now())
      if $0.promptSize == nil {
        $0.promptSize = .measure(
          prompt,
          sourceCharacterCount: sourceCharacterCount
        )
      }
    }
  }

  func markHTTPStarted(at date: Date? = nil) {
    update { setOnce(&$0.httpStartedAt, date ?? now()) }
  }

  func markFirstResponseByte(at date: Date? = nil) {
    update { setEarliest(&$0.firstResponseByteAt, date ?? now()) }
  }

  func markFirstSSEContent(at date: Date? = nil) {
    update { setOnce(&$0.firstSSEContentAt, date ?? now()) }
  }

  func markNetworkCompleted(at date: Date? = nil) {
    update { setOnce(&$0.networkCompletedAt, date ?? now()) }
  }

  func markDecoded(at date: Date? = nil) {
    update { setOnce(&$0.decodedAt, date ?? now()) }
  }

  func markValidated(at date: Date? = nil) {
    update { setOnce(&$0.validatedAt, date ?? now()) }
  }

  func markPresentationReady(at date: Date? = nil) {
    update { setOnce(&$0.presentationReadyAt, date ?? now()) }
  }

  func markPanelPresented(at date: Date? = nil) {
    update { setOnce(&$0.panelPresentedAt, date ?? now()) }
  }

  func recordUsage(_ usage: LLMUsageMetadata) {
    update { $0.usage = usage }
  }

  func recordModelIdentifier(_ modelIdentifier: String?) {
    guard let modelIdentifier, !modelIdentifier.isEmpty else {
      return
    }
    update { $0.modelIdentifier = $0.modelIdentifier ?? modelIdentifier }
  }

  var snapshot: TutorLatencyMetrics {
    lock.lock()
    let value = state
    lock.unlock()
    return TutorLatencyMetrics(
      traceID: id,
      requestID: value.requestID,
      modelIdentifier: value.modelIdentifier,
      userActionAt: userActionAt,
      contentResolvedAt: value.contentResolvedAt,
      requestCreatedAt: value.requestCreatedAt,
      promptBuiltAt: value.promptBuiltAt,
      httpStartedAt: value.httpStartedAt,
      firstResponseByteAt: value.firstResponseByteAt,
      firstSSEContentAt: value.firstSSEContentAt,
      networkCompletedAt: value.networkCompletedAt,
      decodedAt: value.decodedAt,
      validatedAt: value.validatedAt,
      presentationReadyAt: value.presentationReadyAt,
      panelPresentedAt: value.panelPresentedAt,
      inputTokens: value.usage.inputTokenCount,
      outputTokens: value.usage.outputTokenCount,
      totalTokens: value.usage.totalTokenCount,
      promptSize: value.promptSize
    )
  }

  private func update(_ operation: (inout State) -> Void) {
    lock.lock()
    operation(&state)
    lock.unlock()
  }

  private func setOnce(_ value: inout Date?, _ date: Date) {
    if value == nil {
      value = date
    }
  }

  private func setEarliest(_ value: inout Date?, _ date: Date) {
    if let current = value, current <= date {
      return
    } else {
      value = date
    }
  }
}

struct TutorResponseBudget: Equatable, Sendable {
  static let compactLesson = TutorResponseBudget(
    targetExplanationCharacters: 80...250,
    maximumKeyPoints: 3,
    maximumGlossaryTerms: 3,
    includesCheckQuestion: false,
    maximumOutputTokens: 900
  )

  let targetExplanationCharacters: ClosedRange<Int>
  let maximumKeyPoints: Int
  let maximumGlossaryTerms: Int
  let includesCheckQuestion: Bool
  let maximumOutputTokens: Int

  var promptConstraint: String {
    "For the first compact lesson, keep zh-Hans plainExplanation around "
      + "\(targetExplanationCharacters.lowerBound)-\(targetExplanationCharacters.upperBound) Chinese characters; "
      + "use at most \(maximumKeyPoints) key points and \(maximumGlossaryTerms) glossary terms; "
      + "include analogy or example only when it materially improves understanding; "
      + "set checkQuestion to null; include caveats only when the source makes them necessary."
  }
}

struct TutorLatencyDistribution: Equatable, Sendable {
  let sampleCount: Int
  let minimum: TimeInterval
  let p50: TimeInterval
  let median: TimeInterval
  let maximum: TimeInterval

  init?(samples: [TimeInterval]) {
    let sorted = samples.filter { $0.isFinite && $0 >= 0 }.sorted()
    guard let minimum = sorted.first, let maximum = sorted.last else {
      return nil
    }
    let middle = sorted.count / 2
    let median = sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2
      : sorted[middle]
    sampleCount = sorted.count
    self.minimum = minimum
    p50 = median
    self.median = median
    self.maximum = maximum
  }
}

struct TutorLatencyBenchmarkSummary: Equatable, Sendable {
  let total: TutorLatencyDistribution?
  let timeToFirstByte: TutorLatencyDistribution?
  let generation: TutorLatencyDistribution?

  init(metrics: [TutorLatencyMetrics]) {
    total = TutorLatencyDistribution(samples: metrics.compactMap(\.totalTutorLatency))
    timeToFirstByte = TutorLatencyDistribution(
      samples: metrics.compactMap(\.timeToFirstByte)
    )
    generation = TutorLatencyDistribution(
      samples: metrics.compactMap(\.generationDuration)
    )
  }
}
