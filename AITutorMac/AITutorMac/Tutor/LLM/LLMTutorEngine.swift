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
    try await respond(to: request, prompt: prompt, latencyTrace: nil)
  }

  func respond(
    to request: TutorRequest,
    prompt: PromptPackage,
    latencyTrace: TutorLatencyTrace?
  ) async throws -> TutorResponse {
    try await withTaskCancellationHandler {
      let rawResponse: RawLLMResponse
      do {
        latencyTrace?.markHTTPStarted()
        rawResponse = try await provider.generate(
          from: prompt,
          latencyTrace: latencyTrace
        )
        latencyTrace?.markNetworkCompleted()
        latencyTrace?.recordUsage(rawResponse.usage)
        latencyTrace?.recordModelIdentifier(
          rawResponse.providerMetadata.modelIdentifier
        )
      } catch is CancellationError {
        throw LLMProviderError.cancelled
      }

      let response = try decoder.decode(rawResponse)
      latencyTrace?.markDecoded()
      return response
    } onCancel: {
      Task {
        await provider.cancel()
      }
    }
  }
}
