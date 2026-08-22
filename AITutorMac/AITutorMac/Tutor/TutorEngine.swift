import Foundation

protocol TutorEngine: Sendable {
  func respond(
    to request: TutorRequest,
    prompt: PromptPackage
  ) async throws -> TutorResponse

  func respond(
    to request: TutorRequest,
    prompt: PromptPackage,
    latencyTrace: TutorLatencyTrace?
  ) async throws -> TutorResponse
}

extension TutorEngine {
  func respond(
    to request: TutorRequest,
    prompt: PromptPackage,
    latencyTrace: TutorLatencyTrace?
  ) async throws -> TutorResponse {
    try await respond(to: request, prompt: prompt)
  }
}

enum TutorRequestValidationIssue: Equatable, Sendable {
  case unsupportedSchemaVersion(expected: Int, actual: Int)
  case invalidSequence(Int)
  case invalidSourceRevisionID(Int)
  case emptySourceText
  case sourceTextTooLong(maximum: Int, actual: Int)
  case emptyLearnerLanguage
  case emptyOutputLanguage
  case emptyPolicyVersion
}

enum TutorEngineError: Error, Equatable, Sendable {
  case cancelled
  case provider(LLMProviderError)
  case invalidRequest(TutorRequestValidationIssue)
  case unavailable
  case generationFailed
  case invalidResponse([TutorResponseValidationIssue])
}
