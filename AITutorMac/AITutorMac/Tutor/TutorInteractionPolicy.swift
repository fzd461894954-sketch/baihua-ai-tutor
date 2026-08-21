import Foundation

enum TutorInteractionAction: String, Equatable, Sendable {
  /// Eligible for presentation routing. This is not permission to open the
  /// Panel automatically; window visibility remains a user-owned lifecycle.
  case show
  case queue
  case ignore
}

enum TutorInteractionPriority: Int, Equatable, Sendable {
  case low = 0
  case normal = 1
  case high = 2
}

enum TutorInteractionReason: String, Equatable, Sendable {
  case highPriorityTopic
  case conceptExplanation
  case incompleteContent
  case lowConfidence
  case emptySource
  case blockedContent
}

/// Reserved topic boundary for future semantic classification. Version one
/// derives it locally and does not depend on a provider or prompt field.
enum TutorInteractionTopicType: String, Equatable, Sendable {
  case concept
  case error
  case warning
  case security
  case failure
  case incomplete
  case unknown
}

struct TutorInteractionInput: Equatable, Sendable {
  let presentationMetadata: TutorPresentationResponseMetadata
  let outcome: TutorPresentationOutcomeKind
  let confidence: TutorAnswerConfidence?
  let flushReason: SemanticFlushReason
  let textLength: Int
  let topicType: TutorInteractionTopicType?

  init(
    presentationMetadata: TutorPresentationResponseMetadata,
    outcome: TutorPresentationOutcomeKind,
    confidence: TutorAnswerConfidence?,
    flushReason: SemanticFlushReason,
    textLength: Int,
    topicType: TutorInteractionTopicType?
  ) {
    self.presentationMetadata = presentationMetadata
    self.outcome = outcome
    self.confidence = confidence
    self.flushReason = flushReason
    self.textLength = max(0, textLength)
    self.topicType = topicType
  }
}

struct TutorInteractionDecision: Equatable, Sendable {
  let action: TutorInteractionAction
  let priority: TutorInteractionPriority
  let reason: TutorInteractionReason
}

struct TutorInteractionPolicy: Sendable {
  func decide(_ input: TutorInteractionInput) -> TutorInteractionDecision {
    if Self.isHighPriority(input.topicType) {
      return TutorInteractionDecision(
        action: .show,
        priority: .high,
        reason: .highPriorityTopic
      )
    }

    guard input.textLength > 0 else {
      return TutorInteractionDecision(
        action: .ignore,
        priority: .low,
        reason: .emptySource
      )
    }

    if input.confidence == .low {
      return TutorInteractionDecision(
        action: .ignore,
        priority: .low,
        reason: .lowConfidence
      )
    }

    if input.outcome == .needsMoreContext || input.topicType == .incomplete {
      return TutorInteractionDecision(
        action: .queue,
        priority: .low,
        reason: .incompleteContent
      )
    }

    if input.outcome == .lesson {
      return TutorInteractionDecision(
        action: .show,
        priority: .normal,
        reason: .conceptExplanation
      )
    }

    return TutorInteractionDecision(
      action: .ignore,
      priority: .low,
      reason: .blockedContent
    )
  }

  private static func isHighPriority(_ topicType: TutorInteractionTopicType?) -> Bool {
    switch topicType {
    case .error, .warning, .security, .failure:
      return true
    case .concept, .incomplete, .unknown, nil:
      return false
    }
  }
}

struct TutorInteractionInputFactory: Sendable {
  func make(
    presentation: TutorPresentationModel,
    sourceChunk: SemanticChunk
  ) -> TutorInteractionInput {
    TutorInteractionInput(
      presentationMetadata: presentation.responseMetadata,
      outcome: presentation.outcome,
      confidence: presentation.lessonMetadata?.confidence,
      flushReason: sourceChunk.flushReason,
      textLength: sourceChunk.text.count,
      topicType: topicType(for: presentation, sourceText: sourceChunk.text)
    )
  }

  private func topicType(
    for presentation: TutorPresentationModel,
    sourceText: String
  ) -> TutorInteractionTopicType {
    if presentation.outcome == .needsMoreContext {
      return .incomplete
    }
    switch presentation.blockReason {
    case .unsafeInstruction, .privacyRisk:
      return .security
    case .invalidInput, .unsupported, nil:
      break
    }

    let searchableText = "\(sourceText) \(presentation.title)".lowercased()
    let highPriorityTopics: [(TutorInteractionTopicType, [String])] = [
      (.security, ["security", "unsafe", "privacy", "安全", "隐私", "风险"]),
      (.error, ["error", "exception", "错误", "异常"]),
      (.warning, ["warning", "warn", "警告", "告警"]),
      (.failure, ["failure", "failed", "失败"]),
    ]
    for (topic, keywords) in highPriorityTopics
    where keywords.contains(where: searchableText.contains) {
      return topic
    }

    return presentation.outcome == .lesson ? .concept : .unknown
  }
}
