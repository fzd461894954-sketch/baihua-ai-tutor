import Foundation

/// Provider-neutral prompt input. It contains no transport, credentials, or
/// model-specific settings.
struct PromptPackage: Equatable, Sendable {
  let systemInstruction: String
  let userContent: String
  let outputSchema: String
  let constraints: [String]
}
