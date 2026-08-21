#if DEBUG
import Foundation
import Observation

/// Process-memory-only Debug configuration shared by Real LLM Demo and the
/// manually triggered Tutor Panel runtime. It is never persisted or logged.
@MainActor
@Observable
final class DebugLLMConfigurationStore {
  var configuration = DebugLLMConfiguration()

  func validatedConfiguration() -> DebugLLMConfiguration? {
    let endpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let url = URL(string: endpoint),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil,
      url.path.lowercased().hasSuffix("/chat/completions"),
      !model.isEmpty,
      !apiKey.isEmpty
    else {
      return nil
    }
    return DebugLLMConfiguration(
      endpoint: url.absoluteString,
      model: model,
      apiKey: apiKey
    )
  }

  func clear() {
    configuration = DebugLLMConfiguration()
  }
}

actor DebugConfiguredTutorEngine: TutorEngine {
  private var configuration: DebugLLMConfiguration?

  func configure(_ configuration: DebugLLMConfiguration) {
    self.configuration = configuration
  }

  func respond(
    to request: TutorRequest,
    prompt: PromptPackage
  ) async throws -> TutorResponse {
    guard let configuration else {
      throw TutorEngineError.unavailable
    }
    let provider: any LLMProvider
    do {
      provider = try tutorRealDemoLiveProvider(configuration)
    } catch {
      throw TutorEngineError.unavailable
    }
    return try await LLMTutorEngine(provider: provider).respond(to: request, prompt: prompt)
  }
}
#endif
