#if DEBUG
import Foundation
import Observation

/// Process-memory-only configuration for Real LLM Demo. Production Tutor
/// Runtime uses Preferences + Keychain and never reads this store.
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
#endif
