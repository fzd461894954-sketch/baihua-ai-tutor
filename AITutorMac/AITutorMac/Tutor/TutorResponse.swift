import Foundation

enum TutorAnswerConfidence: String, Equatable, Sendable {
  case high
  case medium
  case low
}

struct TutorTerm: Equatable, Sendable {
  let term: String
  let plainDefinition: String
}

struct TutorLesson: Equatable, Sendable {
  let title: String?
  let plainExplanation: String
  let keyPoints: [String]
  let glossary: [TutorTerm]
  let analogy: String?
  let example: String?
  let checkQuestion: String?
  let caveats: [String]
  let confidence: TutorAnswerConfidence
}

struct TutorNeedsMoreContext: Equatable, Sendable {
  let reason: String
  let suggestedAction: String?
}

enum TutorBlockReason: String, Equatable, Sendable {
  case invalidInput
  case unsafeInstruction
  case privacyRisk
  case unsupported
}

struct TutorBlock: Equatable, Sendable {
  let reason: TutorBlockReason
  let message: String
}

enum TutorOutcome: Equatable, Sendable {
  case lesson(TutorLesson)
  case needsMoreContext(TutorNeedsMoreContext)
  case blocked(TutorBlock)
}

struct TutorResponse: Equatable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let id: UUID
  let requestID: UUID
  let sessionID: UUID
  let sequence: Int
  let sourceChunkID: UUID
  let createdAt: Date
  let outcome: TutorOutcome
}
