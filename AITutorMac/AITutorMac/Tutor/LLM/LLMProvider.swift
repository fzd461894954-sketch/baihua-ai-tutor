import Foundation

protocol LLMProvider: Sendable {
  func generate(from prompt: PromptPackage) async throws -> RawLLMResponse

  func stream(
    from prompt: PromptPackage
  ) async -> AsyncThrowingStream<RawLLMStreamChunk, Error>

  func cancel() async
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
