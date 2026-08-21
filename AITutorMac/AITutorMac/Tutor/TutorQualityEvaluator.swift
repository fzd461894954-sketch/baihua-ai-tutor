import Foundation

enum TutorQualitySignalID: String, CaseIterable, Equatable, Sendable {
  case plainExplanation
  case responseLength
  case teachingStructure
  case glossary
  case analogy
  case sourceAlignment
  case unsupportedFacts
  case substantiveSummary
}

enum TutorQualitySignalStatus: String, Equatable, Sendable {
  case passed
  case warning
  case failed
}

enum TutorQualityRating: String, Equatable, Sendable {
  case passed
  case needsReview
  case failed
}

struct TutorQualitySignal: Identifiable, Equatable, Sendable {
  let id: TutorQualitySignalID
  let status: TutorQualitySignalStatus
  let title: String
  let detail: String
}

/// Optional, case-specific teaching expectations. These values describe the
/// desired shape of a lesson; they never contain user history or provider data.
struct TutorQualityExpectations: Equatable, Sendable {
  static let `default` = TutorQualityExpectations(
    sourceAnchors: [],
    expectedGlossaryTerms: [],
    minimumKeyPointCount: 1,
    requiresGlossary: true,
    requiresAnalogy: nil,
    requiresExample: false,
    maximumExplanationCharacters: nil
  )

  let sourceAnchors: [String]
  let expectedGlossaryTerms: [String]
  let minimumKeyPointCount: Int
  let requiresGlossary: Bool
  /// `nil` follows the request's `includeAnalogy` preference.
  let requiresAnalogy: Bool?
  let requiresExample: Bool
  let maximumExplanationCharacters: Int?

  init(
    sourceAnchors: [String],
    expectedGlossaryTerms: [String],
    minimumKeyPointCount: Int,
    requiresGlossary: Bool,
    requiresAnalogy: Bool?,
    requiresExample: Bool,
    maximumExplanationCharacters: Int?
  ) {
    self.sourceAnchors = sourceAnchors
    self.expectedGlossaryTerms = expectedGlossaryTerms
    self.minimumKeyPointCount = max(0, minimumKeyPointCount)
    self.requiresGlossary = requiresGlossary
    self.requiresAnalogy = requiresAnalogy
    self.requiresExample = requiresExample
    self.maximumExplanationCharacters = maximumExplanationCharacters.map { max(1, $0) }
  }
}

struct TutorQualityEvaluationLimits: Equatable, Sendable {
  static let `default` = TutorQualityEvaluationLimits(
    minimumSubstantiveExplanationCharacters: 24,
    conciseMaximumExplanationCharacters: 500,
    balancedMaximumExplanationCharacters: 1_200,
    detailedMaximumExplanationCharacters: 2_000,
    maximumGlossaryTermCharacters: 80,
    maximumGlossaryDefinitionCharacters: 300
  )

  let minimumSubstantiveExplanationCharacters: Int
  let conciseMaximumExplanationCharacters: Int
  let balancedMaximumExplanationCharacters: Int
  let detailedMaximumExplanationCharacters: Int
  let maximumGlossaryTermCharacters: Int
  let maximumGlossaryDefinitionCharacters: Int

  init(
    minimumSubstantiveExplanationCharacters: Int,
    conciseMaximumExplanationCharacters: Int,
    balancedMaximumExplanationCharacters: Int,
    detailedMaximumExplanationCharacters: Int,
    maximumGlossaryTermCharacters: Int,
    maximumGlossaryDefinitionCharacters: Int
  ) {
    self.minimumSubstantiveExplanationCharacters = max(
      1,
      minimumSubstantiveExplanationCharacters
    )
    self.conciseMaximumExplanationCharacters = max(
      1,
      conciseMaximumExplanationCharacters
    )
    self.balancedMaximumExplanationCharacters = max(
      1,
      balancedMaximumExplanationCharacters
    )
    self.detailedMaximumExplanationCharacters = max(
      1,
      detailedMaximumExplanationCharacters
    )
    self.maximumGlossaryTermCharacters = max(1, maximumGlossaryTermCharacters)
    self.maximumGlossaryDefinitionCharacters = max(
      1,
      maximumGlossaryDefinitionCharacters
    )
  }
}

struct TutorQualityReport: Equatable, Sendable {
  let rating: TutorQualityRating
  let signals: [TutorQualitySignal]
  let explanationCharacterCount: Int
  let chineseCharacterCount: Int
  let glossaryTermCount: Int
  let keyPointCount: Int
  let hasAnalogy: Bool

  var containsChineseExplanation: Bool {
    chineseCharacterCount >= 4
  }

  var meetsDemoBaseline: Bool {
    rating == .passed
  }

  func signal(for id: TutorQualitySignalID) -> TutorQualitySignal? {
    signals.first(where: { $0.id == id })
  }
}

/// A deterministic, offline heuristic evaluator. It never calls a model or a
/// provider. Alignment and unsupported-fact checks are review signals rather
/// than claims of semantic proof.
struct TutorQualityEvaluator: Sendable {
  let limits: TutorQualityEvaluationLimits

  init(limits: TutorQualityEvaluationLimits = .default) {
    self.limits = limits
  }

  func evaluate(
    _ response: TutorResponse?,
    for request: TutorRequest,
    expectations: TutorQualityExpectations = .default
  ) -> TutorQualityReport {
    guard let response else {
      let signals = TutorQualitySignalID.allCases.map { id in
        TutorQualitySignal(
          id: id,
          status: .failed,
          title: title(for: id),
          detail: "没有可评估的 TutorResponse。"
        )
      }
      return report(signals: signals, lesson: nil)
    }

    guard case let .lesson(lesson) = response.outcome else {
      let signals = TutorQualitySignalID.allCases.map { id in
        TutorQualitySignal(
          id: id,
          status: .warning,
          title: title(for: id),
          detail: "返回结果不是 lesson，本项无法按教学正文评估。"
        )
      }
      return report(signals: signals, lesson: nil)
    }

    let explanation = visibleText(lesson.plainExplanation)
    let visibleKeyPoints = lesson.keyPoints.compactMap(visibleText)
    let signals = [
      explanationSignal(explanation),
      lengthSignal(
        explanation,
        detailLevel: request.output.detailLevel,
        expectations: expectations
      ),
      teachingStructureSignal(
        lesson,
        visibleKeyPoints: visibleKeyPoints,
        expectations: expectations
      ),
      glossarySignal(lesson.glossary, expectations: expectations),
      analogySignal(
        lesson.analogy,
        required: expectations.requiresAnalogy ?? request.output.includeAnalogy
      ),
      sourceAlignmentSignal(
        lesson,
        sourceText: request.source.text,
        expectedAnchors: expectations.sourceAnchors
      ),
      unsupportedFactsSignal(lesson, sourceText: request.source.text),
      substantiveSummarySignal(
        explanation,
        visibleKeyPointCount: visibleKeyPoints.count,
        glossaryCount: lesson.glossary.count,
        hasExample: visibleText(lesson.example) != nil,
        hasAnalogy: visibleText(lesson.analogy) != nil
      ),
    ]
    return report(signals: signals, lesson: lesson)
  }

  private func explanationSignal(_ explanation: String?) -> TutorQualitySignal {
    if explanation == nil {
      return signal(
        .plainExplanation,
        .failed,
        "plainExplanation 为空或只有空白字符。"
      )
    }
    return signal(.plainExplanation, .passed, "存在可见的白话解释。")
  }

  private func lengthSignal(
    _ explanation: String?,
    detailLevel: TutorDetailLevel,
    expectations: TutorQualityExpectations
  ) -> TutorQualitySignal {
    guard let explanation else {
      return signal(.responseLength, .failed, "无正文，无法检查长度。")
    }
    let maximum = expectations.maximumExplanationCharacters
      ?? maximumExplanationCharacters(for: detailLevel)
    guard explanation.count <= maximum else {
      return signal(
        .responseLength,
        .failed,
        "解释为 \(explanation.count) 字符，超过 \(maximum) 字符上限。"
      )
    }
    return signal(
      .responseLength,
      .passed,
      "解释为 \(explanation.count) 字符，未超过 \(maximum) 字符上限。"
    )
  }

  private func teachingStructureSignal(
    _ lesson: TutorLesson,
    visibleKeyPoints: [String],
    expectations: TutorQualityExpectations
  ) -> TutorQualitySignal {
    let hasMalformedKeyPoint = visibleKeyPoints.count != lesson.keyPoints.count
    let hasRequiredKeyPoints = visibleKeyPoints.count >= expectations.minimumKeyPointCount
    let hasRequiredExample = !expectations.requiresExample
      || visibleText(lesson.example) != nil
    guard !hasMalformedKeyPoint, hasRequiredKeyPoints, hasRequiredExample else {
      var reasons: [String] = []
      if hasMalformedKeyPoint {
        reasons.append("关键点中存在空项")
      }
      if !hasRequiredKeyPoints {
        reasons.append(
          "需要至少 \(expectations.minimumKeyPointCount) 个关键点，实际为 \(visibleKeyPoints.count)"
        )
      }
      if !hasRequiredExample {
        reasons.append("缺少预期的例子")
      }
      return signal(.teachingStructure, .failed, reasons.joined(separator: "；") + "。")
    }
    return signal(
      .teachingStructure,
      .passed,
      "教学结构完整：\(visibleKeyPoints.count) 个关键点"
        + (expectations.requiresExample ? "，并包含例子。" : "。")
    )
  }

  private func glossarySignal(
    _ glossary: [TutorTerm],
    expectations: TutorQualityExpectations
  ) -> TutorQualitySignal {
    if expectations.requiresGlossary, glossary.isEmpty {
      return signal(.glossary, .failed, "当前 Case 要求术语表，但 glossary 为空。")
    }
    if glossary.isEmpty {
      return signal(.glossary, .passed, "当前 Case 不强制术语表。")
    }

    var normalizedTerms = Set<String>()
    for item in glossary {
      guard
        let term = visibleText(item.term),
        let definition = visibleText(item.plainDefinition),
        !normalized(term).isEmpty,
        !normalized(definition).isEmpty,
        term.count <= limits.maximumGlossaryTermCharacters,
        definition.count <= limits.maximumGlossaryDefinitionCharacters,
        normalized(term) != normalized(definition),
        normalizedTerms.insert(normalized(term)).inserted
      else {
        return signal(
          .glossary,
          .failed,
          "glossary 存在空值、重复术语、过长定义或无效的自我定义。"
        )
      }
    }

    let expected = expectations.expectedGlossaryTerms
      .compactMap(visibleText)
      .map(normalized)
    let coveredExpectedTerms = expected.filter { expectedTerm in
      normalizedTerms.contains(where: {
        $0.contains(expectedTerm) || expectedTerm.contains($0)
      })
    }
    if !expected.isEmpty, coveredExpectedTerms.isEmpty {
      return signal(
        .glossary,
        .warning,
        "术语表形式有效，但未覆盖 Case 的候选核心术语。"
      )
    }
    return signal(.glossary, .passed, "术语表包含 \(glossary.count) 个可用条目。")
  }

  private func analogySignal(
    _ analogy: String?,
    required: Bool
  ) -> TutorQualitySignal {
    guard required else {
      return signal(.analogy, .passed, "当前请求不强制类比。")
    }
    guard visibleText(analogy) != nil else {
      return signal(.analogy, .failed, "当前请求要求类比，但 analogy 缺失。")
    }
    return signal(.analogy, .passed, "已提供类比。")
  }

  private func sourceAlignmentSignal(
    _ lesson: TutorLesson,
    sourceText: String,
    expectedAnchors: [String]
  ) -> TutorQualitySignal {
    let responseText = combinedText(for: lesson)
    let configuredAnchors = expectedAnchors.compactMap(visibleText)
    let anchors = configuredAnchors.isEmpty
      ? automaticallySelectedAnchors(from: sourceText)
      : configuredAnchors
    guard !anchors.isEmpty else {
      return signal(
        .sourceAlignment,
        .warning,
        "源片段中没有足够的可比对锚点，需要人工检查是否偏题。"
      )
    }
    let matched = anchors.filter { contains(responseText, term: $0) }
    guard !matched.isEmpty else {
      return signal(
        .sourceAlignment,
        .failed,
        "回答未命中任一源片段教学锚点，可能已偏离 source chunk。"
      )
    }
    return signal(
      .sourceAlignment,
      .passed,
      "回答命中 \(matched.count)/\(anchors.count) 个源片段教学锚点。"
    )
  }

  private func unsupportedFactsSignal(
    _ lesson: TutorLesson,
    sourceText: String
  ) -> TutorQualitySignal {
    let responseText = combinedText(for: lesson)
    let markers = [
      "[hallucination]",
      "<hallucination>",
      "hallucination:",
      "未提供事实：",
      "虚构事实：",
    ]
    if markers.contains(where: { contains(responseText, term: $0) }) {
      return signal(
        .unsupportedFacts,
        .failed,
        "回答命中未提供事实的显式标记。"
      )
    }

    let responseAnchors = factualAnchors(in: responseText)
    let sourceAnchors = Set(factualAnchors(in: sourceText))
    let unsupported = responseAnchors.filter { !sourceAnchors.contains($0) }
    if !unsupported.isEmpty {
      return signal(
        .unsupportedFacts,
        .warning,
        "回答引入了源片段中没有的数字或 URL 锚点，需人工核对："
          + unsupported.prefix(3).joined(separator: "、")
      )
    }
    return signal(
      .unsupportedFacts,
      .passed,
      "未发现显式幻觉标记或额外数字、URL 事实锚点。"
    )
  }

  private func substantiveSummarySignal(
    _ explanation: String?,
    visibleKeyPointCount: Int,
    glossaryCount: Int,
    hasExample: Bool,
    hasAnalogy: Bool
  ) -> TutorQualitySignal {
    guard let explanation else {
      return signal(.substantiveSummary, .failed, "缺少可评估的总结正文。")
    }
    let compact = normalized(explanation)
    let hollowPhrases = [
      "总的来说这很重要",
      "简单来说这是一个概念",
      "这就是上述内容的总结",
      "希望这能帮助你",
    ]
    let hasSupport = visibleKeyPointCount > 0 || glossaryCount > 0 || hasExample || hasAnalogy
    if hollowPhrases.contains(where: { compact.contains($0) })
      && explanation.count < limits.minimumSubstantiveExplanationCharacters * 2
    {
      return signal(.substantiveSummary, .failed, "解释主要由空洞总结套话组成。")
    }
    if explanation.count < limits.minimumSubstantiveExplanationCharacters, !hasSupport {
      return signal(
        .substantiveSummary,
        .failed,
        "解释过短，且没有关键点、术语、例子或类比支撑。"
      )
    }
    return signal(.substantiveSummary, .passed, "解释包含可用的教学信息。")
  }

  private func report(
    signals: [TutorQualitySignal],
    lesson: TutorLesson?
  ) -> TutorQualityReport {
    let rating: TutorQualityRating
    if signals.contains(where: { $0.status == .failed }) {
      rating = .failed
    } else if signals.contains(where: { $0.status == .warning }) {
      rating = .needsReview
    } else {
      rating = .passed
    }
    let explanation = lesson?.plainExplanation ?? ""
    return TutorQualityReport(
      rating: rating,
      signals: signals,
      explanationCharacterCount: explanation.count,
      chineseCharacterCount: chineseCharacterCount(in: explanation),
      glossaryTermCount: lesson?.glossary.count ?? 0,
      keyPointCount: lesson?.keyPoints.count ?? 0,
      hasAnalogy: visibleText(lesson?.analogy) != nil
    )
  }

  private func signal(
    _ id: TutorQualitySignalID,
    _ status: TutorQualitySignalStatus,
    _ detail: String
  ) -> TutorQualitySignal {
    TutorQualitySignal(id: id, status: status, title: title(for: id), detail: detail)
  }

  private func title(for id: TutorQualitySignalID) -> String {
    switch id {
    case .plainExplanation:
      return "白话解释"
    case .responseLength:
      return "正文长度"
    case .teachingStructure:
      return "教学结构"
    case .glossary:
      return "术语表"
    case .analogy:
      return "类比"
    case .sourceAlignment:
      return "Source 对齐"
    case .unsupportedFacts:
      return "未提供事实"
    case .substantiveSummary:
      return "教学实质"
    }
  }

  private func maximumExplanationCharacters(for level: TutorDetailLevel) -> Int {
    switch level {
    case .concise:
      return limits.conciseMaximumExplanationCharacters
    case .balanced:
      return limits.balancedMaximumExplanationCharacters
    case .detailed:
      return limits.detailedMaximumExplanationCharacters
    }
  }

  private func combinedText(for lesson: TutorLesson) -> String {
    ([lesson.title, lesson.plainExplanation]
      + lesson.keyPoints.map(Optional.some)
      + lesson.glossary.flatMap { [Optional($0.term), Optional($0.plainDefinition)] }
      + [lesson.analogy, lesson.example, lesson.checkQuestion]
      + lesson.caveats.map(Optional.some))
      .compactMap(visibleText)
      .joined(separator: "\n")
  }

  private func automaticallySelectedAnchors(from text: String) -> [String] {
    var anchors: [String] = []
    var seen = Set<String>()
    for token in wordTokens(in: text) where token.count >= 2 {
      let key = normalized(token)
      if seen.insert(key).inserted {
        anchors.append(token)
      }
    }
    return Array(anchors.prefix(12))
  }

  private func wordTokens(in text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var currentIsCJK: Bool?

    func flush() {
      guard !current.isEmpty else {
        return
      }
      if currentIsCJK == true, current.count > 2 {
        let characters = Array(current)
        for index in 0..<(characters.count - 1) {
          tokens.append(String(characters[index...index + 1]))
        }
      } else {
        tokens.append(current)
      }
      current = ""
      currentIsCJK = nil
    }

    for scalar in text.unicodeScalars {
      let isCJK = (0x4E00...0x9FFF).contains(scalar.value)
      let isWord = isCJK || CharacterSet.alphanumerics.contains(scalar)
      guard isWord else {
        flush()
        continue
      }
      if let currentIsCJK, currentIsCJK != isCJK {
        flush()
      }
      currentIsCJK = isCJK
      current.unicodeScalars.append(scalar)
    }
    flush()
    return tokens
  }

  private func factualAnchors(in text: String) -> [String] {
    let tokens = text
      .split(whereSeparator: { $0.isWhitespace || ",;()[]{}。，；（）".contains($0) })
      .map(String.init)
    var values = Set<String>()
    for rawToken in tokens {
      let token = rawToken.trimmingCharacters(in: .punctuationCharacters)
      if token.lowercased().hasPrefix("http://")
        || token.lowercased().hasPrefix("https://") {
        values.insert(normalized(token))
      }

      var digits = ""
      for scalar in token.unicodeScalars {
        if CharacterSet.decimalDigits.contains(scalar) {
          digits.unicodeScalars.append(scalar)
        } else if !digits.isEmpty {
          values.insert(digits)
          digits = ""
        }
      }
      if !digits.isEmpty {
        values.insert(digits)
      }
    }
    return values.sorted()
  }

  private func visibleText(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func normalized(_ value: String) -> String {
    value
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .filter { !$0.isWhitespace && !$0.isPunctuation }
  }

  private func contains(_ text: String, term: String) -> Bool {
    normalized(text).contains(normalized(term))
  }

  private func chineseCharacterCount(in value: String) -> Int {
    value.unicodeScalars.reduce(0) { count, scalar in
      count + ((0x4E00...0x9FFF).contains(scalar.value) ? 1 : 0)
    }
  }
}
