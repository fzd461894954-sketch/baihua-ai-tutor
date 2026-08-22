import Foundation

protocol LLMProvider: Sendable {
  func generate(from prompt: PromptPackage) async throws -> RawLLMResponse

  func generate(
    from prompt: PromptPackage,
    latencyTrace: TutorLatencyTrace?
  ) async throws -> RawLLMResponse

  func stream(
    from prompt: PromptPackage
  ) async -> AsyncThrowingStream<RawLLMStreamChunk, Error>

  func stream(
    from prompt: PromptPackage,
    latencyTrace: TutorLatencyTrace?
  ) async -> AsyncThrowingStream<RawLLMStreamChunk, Error>

  func cancel() async
}

extension LLMProvider {
  func generate(
    from prompt: PromptPackage,
    latencyTrace: TutorLatencyTrace?
  ) async throws -> RawLLMResponse {
    try await generate(from: prompt)
  }

  func stream(
    from prompt: PromptPackage,
    latencyTrace: TutorLatencyTrace?
  ) async -> AsyncThrowingStream<RawLLMStreamChunk, Error> {
    await stream(from: prompt)
  }
}

enum LLMProviderError: Error, Equatable, Sendable {
  case timeout
  case cancelled
  case invalidResponse
  case unavailable
  case decodingFailed
  case authenticationFailed
  case modelUnavailable
  case rateLimited
  case networkUnavailable
  case invalidEndpoint
}
