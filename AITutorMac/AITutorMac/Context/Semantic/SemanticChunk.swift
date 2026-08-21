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

struct SemanticChunk: Equatable, Sendable {
  let id: UUID
  let sourceRevisionID: Int
  let text: String
  let confidence: DiffConfidence
  let createdAt: Date
  let flushReason: SemanticFlushReason
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
