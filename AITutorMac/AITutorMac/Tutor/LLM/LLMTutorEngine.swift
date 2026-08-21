import Foundation

struct LLMTutorEngine: TutorEngine, Sendable {
  private let provider: any LLMProvider
  private let decoder: TutorResponseDecoder

  init(
    provider: any LLMProvider,
    decoder: TutorResponseDecoder = TutorResponseDecoder()
  ) {
    self.provider = provider
    self.decoder = decoder
  }

  func respond(
    to request: TutorRequest,
    prompt: PromptPackage
  ) async throws -> TutorResponse {
    try await withTaskCancellationHandler {
      let rawResponse: RawLLMResponse
      do {
        rawResponse = try await provider.generate(from: prompt)
      } catch is CancellationError {
        throw LLMProviderError.cancelled
      }

      return try decoder.decode(rawResponse)
    } onCancel: {
      Task {
        await provider.cancel()
      }
    }
  }
}
