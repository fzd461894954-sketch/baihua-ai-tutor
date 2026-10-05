import Foundation

enum LLMFinishReason: Equatable, Sendable {
  case stop
  case length
  case cancelled
  case other(String)
}

struct LLMUsageMetadata: Equatable, Sendable {
  let inputTokenCount: Int?
  let outputTokenCount: Int?
  let totalTokenCount: Int?

  static let unavailable = LLMUsageMetadata(
    inputTokenCount: nil,
    outputTokenCount: nil,
    totalTokenCount: nil
  )
}

struct LLMProviderMetadata: Equatable, Sendable {
  let providerIdentifier: String
  let modelIdentifier: String?
  let requestIdentifier: String?
  let values: [String: String]
}

struct RawLLMResponse: Equatable, Sendable {
  let content: String
  let finishReason: LLMFinishReason?
  let usage: LLMUsageMetadata
  let providerMetadata: LLMProviderMetadata
}

struct RawLLMStreamChunk: Equatable, Sendable {
  let sequence: Int
  let contentDelta: String
  let finishReason: LLMFinishReason?
  let usage: LLMUsageMetadata?
  let providerMetadata: LLMProviderMetadata
}
