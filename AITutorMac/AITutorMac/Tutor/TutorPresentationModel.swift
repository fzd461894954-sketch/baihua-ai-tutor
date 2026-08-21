import Foundation

enum TutorPresentationOutcomeKind: String, Equatable, Sendable {
  case lesson
  case needsMoreContext
  case blocked
}

struct TutorPresentationResponseMetadata: Equatable, Sendable {
  let responseID: UUID
  let requestID: UUID
  let sessionID: UUID
  let sequence: Int
  let sourceChunkID: UUID
  let createdAt: Date
}

struct TutorPresentationLessonMetadata: Equatable, Sendable {
  let confidence: TutorAnswerConfidence
  let keyPointCount: Int
  let termCount: Int
  let caveatCount: Int
  let hasAnalogy: Bool
  let hasExample: Bool
  let hasCheckQuestion: Bool
}

struct TutorPresentationTerm: Equatable, Sendable {
  let term: String
  let plainDefinition: String
}

/// UI-safe representation shared by future Panel, Pet Bubble, and Voice
/// adapters. It contains no provider-specific or prompt-only values.
struct TutorPresentationModel: Equatable, Sendable {
  let responseMetadata: TutorPresentationResponseMetadata
  let outcome: TutorPresentationOutcomeKind
  let lessonMetadata: TutorPresentationLessonMetadata?
  let title: String
  let plainExplanation: String
  let keyPoints: [String]
  let terms: [TutorPresentationTerm]
  let analogy: String?
  let example: String?
  let checkQuestion: String?
  let caveats: [String]
  let suggestedAction: String?
  let blockReason: TutorBlockReason?
  let didTruncateContent: Bool
}

struct TutorPresentationLimits: Equatable, Sendable {
  static let `default` = TutorPresentationLimits(
    maximumTitleCharacters: 80,
    maximumExplanationCharacters: 1_200,
    maximumKeyPoints: 5,
    maximumTerms: 8,
    maximumCaveats: 3,
    maximumListItemCharacters: 300,
    maximumTermCharacters: 80,
    maximumOptionalSectionCharacters: 600,
    maximumStatusCharacters: 500
  )

  let maximumTitleCharacters: Int
  let maximumExplanationCharacters: Int
  let maximumKeyPoints: Int
  let maximumTerms: Int
  let maximumCaveats: Int
  let maximumListItemCharacters: Int
  let maximumTermCharacters: Int
  let maximumOptionalSectionCharacters: Int
  let maximumStatusCharacters: Int

  init(
    maximumTitleCharacters: Int,
    maximumExplanationCharacters: Int,
    maximumKeyPoints: Int,
    maximumTerms: Int,
    maximumCaveats: Int,
    maximumListItemCharacters: Int,
    maximumTermCharacters: Int,
    maximumOptionalSectionCharacters: Int,
    maximumStatusCharacters: Int
  ) {
    self.maximumTitleCharacters = max(1, maximumTitleCharacters)
    self.maximumExplanationCharacters = max(1, maximumExplanationCharacters)
    self.maximumKeyPoints = max(0, maximumKeyPoints)
    self.maximumTerms = max(0, maximumTerms)
    self.maximumCaveats = max(0, maximumCaveats)
    self.maximumListItemCharacters = max(1, maximumListItemCharacters)
    self.maximumTermCharacters = max(1, maximumTermCharacters)
    self.maximumOptionalSectionCharacters = max(1, maximumOptionalSectionCharacters)
    self.maximumStatusCharacters = max(1, maximumStatusCharacters)
  }
}

struct TutorPresentationMapper: Sendable {
  let limits: TutorPresentationLimits

  init(limits: TutorPresentationLimits = .default) {
    self.limits = limits
  }

  func makePresentation(from response: TutorResponse) -> TutorPresentationModel {
    var didTruncate = false
    let responseMetadata = TutorPresentationResponseMetadata(
      responseID: response.id,
      requestID: response.requestID,
      sessionID: response.sessionID,
      sequence: response.sequence,
      sourceChunkID: response.sourceChunkID,
      createdAt: response.createdAt
    )

    switch response.outcome {
    case let .lesson(lesson):
      let title = clipped(
        visibleText(lesson.title) ?? "白话解释",
        maximum: limits.maximumTitleCharacters,
        didTruncate: &didTruncate
      )
      let explanation = clipped(
        visibleText(lesson.plainExplanation) ?? "暂无可展示的解释。",
        maximum: limits.maximumExplanationCharacters,
        didTruncate: &didTruncate
      )
      let keyPoints = mappedStrings(
        lesson.keyPoints,
        maximumCount: limits.maximumKeyPoints,
        maximumCharacters: limits.maximumListItemCharacters,
        didTruncate: &didTruncate
      )
      let terms = mappedTerms(lesson.glossary, didTruncate: &didTruncate)
      let analogy = mappedOptional(
        lesson.analogy,
        maximum: limits.maximumOptionalSectionCharacters,
        didTruncate: &didTruncate
      )
      let example = mappedOptional(
        lesson.example,
        maximum: limits.maximumOptionalSectionCharacters,
        didTruncate: &didTruncate
      )
      let checkQuestion = mappedOptional(
        lesson.checkQuestion,
        maximum: limits.maximumOptionalSectionCharacters,
        didTruncate: &didTruncate
      )
      let caveats = mappedStrings(
        lesson.caveats,
        maximumCount: limits.maximumCaveats,
        maximumCharacters: limits.maximumListItemCharacters,
        didTruncate: &didTruncate
      )
      let lessonMetadata = TutorPresentationLessonMetadata(
        confidence: lesson.confidence,
        keyPointCount: keyPoints.count,
        termCount: terms.count,
        caveatCount: caveats.count,
        hasAnalogy: analogy != nil,
        hasExample: example != nil,
        hasCheckQuestion: checkQuestion != nil
      )

      return TutorPresentationModel(
        responseMetadata: responseMetadata,
        outcome: .lesson,
        lessonMetadata: lessonMetadata,
        title: title,
        plainExplanation: explanation,
        keyPoints: keyPoints,
        terms: terms,
        analogy: analogy,
        example: example,
        checkQuestion: checkQuestion,
        caveats: caveats,
        suggestedAction: nil,
        blockReason: nil,
        didTruncateContent: didTruncate
      )

    case let .needsMoreContext(value):
      let explanation = clipped(
        visibleText(value.reason) ?? "当前没有足够上下文可供展示。",
        maximum: limits.maximumStatusCharacters,
        didTruncate: &didTruncate
      )
      let suggestedAction = mappedOptional(
        value.suggestedAction,
        maximum: limits.maximumStatusCharacters,
        didTruncate: &didTruncate
      )

      return TutorPresentationModel(
        responseMetadata: responseMetadata,
        outcome: .needsMoreContext,
        lessonMetadata: nil,
        title: "需要更多上下文",
        plainExplanation: explanation,
        keyPoints: [],
        terms: [],
        analogy: nil,
        example: nil,
        checkQuestion: nil,
        caveats: [],
        suggestedAction: suggestedAction,
        blockReason: nil,
        didTruncateContent: didTruncate
      )

    case let .blocked(value):
      let explanation = clipped(
        visibleText(value.message) ?? "该内容暂时无法展示。",
        maximum: limits.maximumStatusCharacters,
        didTruncate: &didTruncate
      )

      return TutorPresentationModel(
        responseMetadata: responseMetadata,
        outcome: .blocked,
        lessonMetadata: nil,
        title: "内容未展示",
        plainExplanation: explanation,
        keyPoints: [],
        terms: [],
        analogy: nil,
        example: nil,
        checkQuestion: nil,
        caveats: [],
        suggestedAction: nil,
        blockReason: value.reason,
        didTruncateContent: didTruncate
      )
    }
  }

  private func mappedStrings(
    _ values: [String],
    maximumCount: Int,
    maximumCharacters: Int,
    didTruncate: inout Bool
  ) -> [String] {
    let visibleValues = values.compactMap(visibleText)
    if visibleValues.count > maximumCount {
      didTruncate = true
    }
    return visibleValues.prefix(maximumCount).map {
      clipped($0, maximum: maximumCharacters, didTruncate: &didTruncate)
    }
  }

  private func mappedTerms(
    _ values: [TutorTerm],
    didTruncate: inout Bool
  ) -> [TutorPresentationTerm] {
    let visibleValues = values.compactMap { value -> TutorPresentationTerm? in
      guard
        let term = visibleText(value.term),
        let definition = visibleText(value.plainDefinition)
      else {
        return nil
      }
      return TutorPresentationTerm(
        term: clipped(
          term,
          maximum: limits.maximumTermCharacters,
          didTruncate: &didTruncate
        ),
        plainDefinition: clipped(
          definition,
          maximum: limits.maximumListItemCharacters,
          didTruncate: &didTruncate
        )
      )
    }
    if visibleValues.count > limits.maximumTerms {
      didTruncate = true
    }
    return Array(visibleValues.prefix(limits.maximumTerms))
  }

  private func mappedOptional(
    _ value: String?,
    maximum: Int,
    didTruncate: inout Bool
  ) -> String? {
    guard let value = visibleText(value) else {
      return nil
    }
    return clipped(value, maximum: maximum, didTruncate: &didTruncate)
  }

  private func visibleText(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func clipped(
    _ value: String,
    maximum: Int,
    didTruncate: inout Bool
  ) -> String {
    guard value.count > maximum else {
      return value
    }
    didTruncate = true
    guard maximum > 1 else {
      return "…"
    }
    return String(value.prefix(maximum - 1)) + "…"
  }
}
