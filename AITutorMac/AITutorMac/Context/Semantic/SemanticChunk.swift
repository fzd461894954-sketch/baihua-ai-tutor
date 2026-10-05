import Foundation

enum SemanticFlushReason: String, Equatable, Sendable {
  case sentenceComplete
  case idleTimeout
  case sizeLimit
  case manualFlush
}

enum SemanticBufferState: String, Equatable, Sendable {
  case idle
  case buffering
  case ready
  case flushing
}

enum SemanticContentCompleteness: String, Equatable, Sendable {
  case complete
  case excerpt
}

enum SemanticContentType: String, Equatable, Sendable {
  case explicitSelectedText = "explicit-selected-text"
  case focusedCodeLike = "focused-code-like"
  case focusedNaturalLanguage = "focused-natural-language"
  case unknownMixed = "unknown-or-mixed"
}

enum SemanticContentLengthPolicy: String, Equatable, Sendable {
  case complete
  case structureAwareCodeExcerpt = "structure-aware-code-excerpt"
  case structureAwareProseExcerpt = "structure-aware-prose-excerpt"
  case boundedMixedExcerpt = "bounded-mixed-excerpt"
  case longSelectionExcerpt = "long-selection-structure-aware-excerpt"
}

enum SemanticContentStructureBoundary: String, Equatable, Sendable {
  case complete
  case codeBlock = "code-block"
  case paragraph
  case sentence
  case newline
  case word
  case characterBudget = "character-budget"
}

struct SemanticContentLengthMetadata: Equatable, Sendable {
  let contentType: SemanticContentType
  let completeness: SemanticContentCompleteness
  let lengthPolicy: SemanticContentLengthPolicy
  let originalCharacterCount: Int
  let normalizedCharacterCount: Int
  let sentCharacterCount: Int
  let excerptStart: Int
  let excerptEnd: Int
  let droppedPrefixCount: Int
  let droppedSuffixCount: Int
  let structureBoundary: SemanticContentStructureBoundary

  var wasTruncated: Bool {
    completeness == .excerpt
  }

  static func complete(
    characterCount: Int,
    contentType: SemanticContentType = .unknownMixed
  ) -> SemanticContentLengthMetadata {
    SemanticContentLengthMetadata(
      contentType: contentType,
      completeness: .complete,
      lengthPolicy: .complete,
      originalCharacterCount: characterCount,
      normalizedCharacterCount: characterCount,
      sentCharacterCount: characterCount,
      excerptStart: 0,
      excerptEnd: characterCount,
      droppedPrefixCount: 0,
      droppedSuffixCount: 0,
      structureBoundary: .complete
    )
  }
}

struct SemanticChunk: Equatable, Sendable {
  let id: UUID
  let sourceRevisionID: Int
  let text: String
  let confidence: DiffConfidence
  let createdAt: Date
  let flushReason: SemanticFlushReason
  let contentLength: SemanticContentLengthMetadata

  init(
    id: UUID,
    sourceRevisionID: Int,
    text: String,
    confidence: DiffConfidence,
    createdAt: Date,
    flushReason: SemanticFlushReason,
    contentLength: SemanticContentLengthMetadata? = nil
  ) {
    self.id = id
    self.sourceRevisionID = sourceRevisionID
    self.text = text
    self.confidence = confidence
    self.createdAt = createdAt
    self.flushReason = flushReason
    self.contentLength = contentLength ?? .complete(characterCount: text.count)
  }
}

struct SemanticBufferConfiguration: Equatable, Sendable {
  static let `default` = SemanticBufferConfiguration(
    stabilityCheckDelay: 0.7,
    idleFlushDelay: 1.5,
    maximumCharacterCount: 1_000
  )

  let stabilityCheckDelay: TimeInterval
  let idleFlushDelay: TimeInterval
  let maximumCharacterCount: Int

  init(
    stabilityCheckDelay: TimeInterval,
    idleFlushDelay: TimeInterval,
    maximumCharacterCount: Int
  ) {
    let stabilityCheckDelay = max(0, stabilityCheckDelay)
    self.stabilityCheckDelay = stabilityCheckDelay
    self.idleFlushDelay = max(stabilityCheckDelay, idleFlushDelay)
    self.maximumCharacterCount = max(1, maximumCharacterCount)
  }
}
