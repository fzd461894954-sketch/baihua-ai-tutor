import Foundation

enum TutorTask: String, Equatable, Sendable {
  case explainInPlainLanguage
}

enum TutorTrigger: String, Equatable, Sendable {
  case automatic
  case userInitiated
}

enum UserKnowledgeLevel: String, Equatable, Sendable {
  case novice
  case beginner
  case intermediate
  case advanced
  case expert
}

enum KnowledgeLevelSelectionSource: String, Equatable, Sendable {
  case productDefault
  case userSelected
}

struct LearnerProfileSnapshot: Equatable, Sendable {
  let level: UserKnowledgeLevel
  let selectionSource: KnowledgeLevelSelectionSource
  let preferredLanguage: String
  let updatedAt: Date

  static func productDefault(at date: Date = Date()) -> LearnerProfileSnapshot {
    LearnerProfileSnapshot(
      level: .novice,
      selectionSource: .productDefault,
      preferredLanguage: "zh-Hans",
      updatedAt: date
    )
  }
}

enum TutorDetailLevel: String, Equatable, Sendable {
  case concise
  case balanced
  case detailed
}

struct TutorOutputPreferences: Equatable, Sendable {
  let language: String
  let detailLevel: TutorDetailLevel
  let includeAnalogy: Bool
  let includeExample: Bool
  let includeCheckQuestion: Bool

  static func `default`(language: String = "zh-Hans") -> TutorOutputPreferences {
    TutorOutputPreferences(
      language: language,
      detailLevel: .concise,
      includeAnalogy: true,
      includeExample: true,
      includeCheckQuestion: false
    )
  }
}

enum TutorSourceCompleteness: String, Equatable, Sendable {
  case completeSentence
  case possiblyIncomplete
  case boundedSegment
  case userForced
}

struct TutorSourceSnapshot: Equatable, Sendable {
  let chunkID: UUID
  let sourceRevisionID: Int
  let text: String
  let diffConfidence: DiffConfidence
  let flushReason: SemanticFlushReason
  let chunkCreatedAt: Date
  let contentLength: SemanticContentLengthMetadata

  init(
    chunkID: UUID,
    sourceRevisionID: Int,
    text: String,
    diffConfidence: DiffConfidence,
    flushReason: SemanticFlushReason,
    chunkCreatedAt: Date,
    contentLength: SemanticContentLengthMetadata? = nil
  ) {
    self.chunkID = chunkID
    self.sourceRevisionID = sourceRevisionID
    self.text = text
    self.diffConfidence = diffConfidence
    self.flushReason = flushReason
    self.chunkCreatedAt = chunkCreatedAt
    self.contentLength = contentLength ?? .complete(characterCount: text.count)
  }

  var completeness: TutorSourceCompleteness {
    switch flushReason {
    case .sentenceComplete:
      return .completeSentence
    case .idleTimeout:
      return .possiblyIncomplete
    case .sizeLimit:
      return .boundedSegment
    case .manualFlush:
      return .userForced
    }
  }
}

struct TutorRequest: Equatable, Sendable {
  static let currentSchemaVersion = 1
  /// A complete medium-sized code example must fit without suffix truncation.
  /// The value remains bounded to limit screen-text exposure and prompt size.
  static let defaultMaximumSourceCharacterCount = 4_000
  static let defaultMaximumLearnerQuestionCharacterCount = 240

  let schemaVersion: Int
  let id: UUID
  let sessionID: UUID
  let sequence: Int
  let createdAt: Date
  let task: TutorTask
  let trigger: TutorTrigger
  let learnerQuestion: String?
  let source: TutorSourceSnapshot
  let learner: LearnerProfileSnapshot
  let output: TutorOutputPreferences
  let policyVersion: String
}
