import Foundation

enum LLMProviderType: String, Codable, CaseIterable, Sendable {
  case openAICompatible

  var displayName: String {
    "OpenAI-compatible"
  }
}

enum LLMProviderPreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case ark
  case custom

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .ark: return "火山方舟 Ark"
    case .custom: return "自定义 OpenAI-compatible"
    }
  }

  var suggestedEndpoint: String? {
    switch self {
    case .ark: return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
    case .custom: return nil
    }
  }
}

enum LLMResponseFormatCapability: String, Codable, CaseIterable, Sendable {
  case automatic
  case jsonSchema
  case jsonObject
  case unsupported

  var displayName: String {
    switch self {
    case .automatic: return "自动"
    case .jsonSchema: return "JSON Schema"
    case .jsonObject: return "JSON Object"
    case .unsupported: return "无结构化输出"
    }
  }
}

struct LLMProviderSettings: Codable, Equatable, Sendable {
  static let activeProfileID = "active-openai-compatible"

  var id: String
  var displayName: String
  var providerType: LLMProviderType
  var preset: LLMProviderPreset
  var endpoint: String
  var model: String
  var responseFormatCapability: LLMResponseFormatCapability
  var temperature: Double
  var maxOutputTokens: Int
  var isEnabled: Bool

  static let `default` = LLMProviderSettings(
    id: activeProfileID,
    displayName: "火山方舟 Ark",
    providerType: .openAICompatible,
    preset: .ark,
    endpoint: LLMProviderPreset.ark.suggestedEndpoint ?? "",
    model: "",
    responseFormatCapability: .automatic,
    temperature: 0.2,
    maxOutputTokens: 1_800,
    isEnabled: true
  )

  var credentialAccount: String { id }

  func validated() throws -> ValidatedLLMProviderSettings {
    let profileID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let profileName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let endpointText = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let modelText = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !profileID.isEmpty else {
      throw LLMProviderSettingsError.invalidProfile
    }
    guard isEnabled else {
      throw LLMProviderSettingsError.disabled
    }
    guard
      let endpointURL = URL(string: endpointText),
      ["http", "https"].contains(endpointURL.scheme?.lowercased() ?? ""),
      endpointURL.host != nil,
      endpointURL.path.lowercased().hasSuffix("/chat/completions")
    else {
      throw LLMProviderSettingsError.invalidEndpoint
    }
    guard !modelText.isEmpty else {
      throw LLMProviderSettingsError.emptyModel
    }
    guard temperature.isFinite, (0...2).contains(temperature) else {
      throw LLMProviderSettingsError.invalidTemperature
    }
    guard (1...32_000).contains(maxOutputTokens) else {
      throw LLMProviderSettingsError.invalidMaxOutputTokens
    }
    return ValidatedLLMProviderSettings(
      id: profileID,
      displayName: profileName.isEmpty ? providerType.displayName : profileName,
      providerType: providerType,
      preset: preset,
      endpoint: endpointURL,
      model: modelText,
      responseFormatCapability: responseFormatCapability,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens
    )
  }
}

struct ValidatedLLMProviderSettings: Equatable, Sendable {
  let id: String
  let displayName: String
  let providerType: LLMProviderType
  let preset: LLMProviderPreset
  let endpoint: URL
  let model: String
  let responseFormatCapability: LLMResponseFormatCapability
  let temperature: Double
  let maxOutputTokens: Int
}

enum LLMProviderSettingsError: Error, Equatable, Sendable {
  case invalidProfile
  case disabled
  case invalidEndpoint
  case emptyModel
  case invalidTemperature
  case invalidMaxOutputTokens
  case persistenceFailed
}

protocol LLMProviderSettingsStoring: Sendable {
  func load() throws -> LLMProviderSettings?
  func save(_ settings: LLMProviderSettings) throws
  func delete() throws
}

final class LLMProviderSettingsStore: LLMProviderSettingsStoring, @unchecked Sendable {
  private enum Key {
    static let activeProvider = "llm.provider.active.settings.v1"
  }

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() throws -> LLMProviderSettings? {
    guard let data = defaults.data(forKey: Key.activeProvider) else {
      return nil
    }
    do {
      return try decoder.decode(LLMProviderSettings.self, from: data)
    } catch {
      throw LLMProviderSettingsError.persistenceFailed
    }
  }

  func save(_ settings: LLMProviderSettings) throws {
    do {
      defaults.set(try encoder.encode(settings), forKey: Key.activeProvider)
    } catch {
      throw LLMProviderSettingsError.persistenceFailed
    }
  }

  func delete() throws {
    defaults.removeObject(forKey: Key.activeProvider)
  }
}
