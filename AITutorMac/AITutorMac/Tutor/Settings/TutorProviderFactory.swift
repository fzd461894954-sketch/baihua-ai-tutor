import Foundation

struct RuntimeCredential: @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let value: String

  init(_ value: String) {
    self.value = value
  }

  var description: String { "<redacted credential>" }
  var debugDescription: String { description }

  func withValue<T>(_ operation: (String) throws -> T) rethrows -> T {
    try operation(value)
  }
}

struct TutorProviderConfigurationSnapshot: Sendable {
  let profileID: String
  let endpoint: URL
  let model: String
  let responseFormat: OpenAICompatibleResponseFormat
  let temperature: Double
  let maxOutputTokens: Int
  let credentialReference: String
  let credential: RuntimeCredential
}

enum TutorProviderFactoryError: Error, Equatable, Sendable {
  case missingSettings
  case invalidSettings(LLMProviderSettingsError)
  case missingCredential
  case credentialUnavailable
}

protocol TutorProviderBuilding: Sendable {
  func configurationSnapshot() throws -> TutorProviderConfigurationSnapshot
  func makeProvider() throws -> any LLMProvider
  func isAvailable() -> Bool
}

final class TutorProviderFactory: TutorProviderBuilding, @unchecked Sendable {
  typealias ProviderBuilder = @Sendable (
    TutorProviderConfigurationSnapshot
  ) -> any LLMProvider

  private let settingsStore: any LLMProviderSettingsStoring
  private let credentialStore: any CredentialStoring
  private let providerBuilder: ProviderBuilder

  init(
    settingsStore: any LLMProviderSettingsStoring,
    credentialStore: any CredentialStoring,
    providerBuilder: @escaping ProviderBuilder = { snapshot in
      TutorProviderFactory.liveProvider(snapshot: snapshot)
    }
  ) {
    self.settingsStore = settingsStore
    self.credentialStore = credentialStore
    self.providerBuilder = providerBuilder
  }

  func configurationSnapshot() throws -> TutorProviderConfigurationSnapshot {
    let settings: LLMProviderSettings
    do {
      guard let stored = try settingsStore.load() else {
        throw TutorProviderFactoryError.missingSettings
      }
      settings = stored
    } catch let error as TutorProviderFactoryError {
      throw error
    } catch {
      throw TutorProviderFactoryError.missingSettings
    }

    let validated: ValidatedLLMProviderSettings
    do {
      validated = try settings.validated()
    } catch let error as LLMProviderSettingsError {
      throw TutorProviderFactoryError.invalidSettings(error)
    }

    let apiKey: String
    do {
      guard
        let storedCredential = try credentialStore.readCredential(for: settings.credentialAccount),
        storedCredential.contains(where: { !$0.isWhitespace })
      else {
        throw TutorProviderFactoryError.missingCredential
      }
      apiKey = storedCredential
    } catch let error as TutorProviderFactoryError {
      throw error
    } catch {
      throw TutorProviderFactoryError.credentialUnavailable
    }

    return TutorProviderConfigurationSnapshot(
      profileID: validated.id,
      endpoint: validated.endpoint,
      model: validated.model,
      responseFormat: responseFormat(
        capability: validated.responseFormatCapability,
        endpoint: validated.endpoint
      ),
      temperature: validated.temperature,
      maxOutputTokens: validated.maxOutputTokens,
      credentialReference: validated.id,
      credential: RuntimeCredential(apiKey)
    )
  }

  func makeProvider() throws -> any LLMProvider {
    providerBuilder(try configurationSnapshot())
  }

  func isAvailable() -> Bool {
    (try? configurationSnapshot()) != nil
  }

  static func liveProvider(
    snapshot: TutorProviderConfigurationSnapshot
  ) -> any LLMProvider {
    snapshot.credential.withValue { apiKey in
      OpenAICompatibleProvider(
        endpoint: snapshot.endpoint,
        model: snapshot.model,
        apiKey: apiKey,
        temperature: snapshot.temperature,
        maxTokens: snapshot.maxOutputTokens,
        responseFormat: snapshot.responseFormat,
        requestTimeout: 60
      )
    }
  }

  private func responseFormat(
    capability: LLMResponseFormatCapability,
    endpoint: URL
  ) -> OpenAICompatibleResponseFormat {
    switch capability {
    case .automatic:
      return endpoint.host?.lowercased().hasSuffix(".volces.com") == true
        ? .jsonObject
        : .jsonSchema
    case .jsonSchema:
      return .jsonSchema
    case .jsonObject:
      return .jsonObject
    case .unsupported:
      return .unsupported
    }
  }
}

/// Builds one immutable provider snapshot per Tutor request. Settings and
/// credentials can change between requests, never during one request.
struct ProductionTutorEngine: TutorEngine, Sendable {
  private let providerFactory: any TutorProviderBuilding

  init(providerFactory: any TutorProviderBuilding) {
    self.providerFactory = providerFactory
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
    let provider: any LLMProvider
    do {
      provider = try providerFactory.makeProvider()
    } catch {
      throw TutorEngineError.unavailable
    }
    return try await LLMTutorEngine(provider: provider).respond(
      to: request,
      prompt: prompt,
      latencyTrace: latencyTrace
    )
  }
}

enum TutorConnectionFailure: Error, Equatable, Sendable {
  case apiKeyInvalid
  case modelUnavailable
  case rateLimited
  case networkUnavailable
  case invalidEndpoint
  case timeout
  case invalidResponse
  case configurationIncomplete
}

struct TutorConnectionResult: Equatable, Sendable {
  let latencyMilliseconds: Int
}

protocol TutorConnectionTesting: Sendable {
  func testConnection() async throws -> TutorConnectionResult
}

struct TutorProviderConnectionTester: TutorConnectionTesting, Sendable {
  private let providerFactory: any TutorProviderBuilding
  private let now: @Sendable () -> Date

  init(
    providerFactory: any TutorProviderBuilding,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.providerFactory = providerFactory
    self.now = now
  }

  func testConnection() async throws -> TutorConnectionResult {
    let provider: any LLMProvider
    do {
      provider = try providerFactory.makeProvider()
    } catch let error as TutorProviderFactoryError {
      switch error {
      case .invalidSettings(.invalidEndpoint): throw TutorConnectionFailure.invalidEndpoint
      default: throw TutorConnectionFailure.configurationIncomplete
      }
    } catch {
      throw TutorConnectionFailure.configurationIncomplete
    }

    let startedAt = now()
    do {
      let response = try await provider.generate(from: Self.minimumPrompt)
      guard
        let object = try? JSONSerialization.jsonObject(with: Data(response.content.utf8)),
        object is [String: Any]
      else {
        throw TutorConnectionFailure.invalidResponse
      }
      return TutorConnectionResult(
        latencyMilliseconds: max(0, Int(now().timeIntervalSince(startedAt) * 1_000))
      )
    } catch let failure as TutorConnectionFailure {
      throw failure
    } catch let error as LLMProviderError {
      switch error {
      case .authenticationFailed: throw TutorConnectionFailure.apiKeyInvalid
      case .modelUnavailable: throw TutorConnectionFailure.modelUnavailable
      case .rateLimited: throw TutorConnectionFailure.rateLimited
      case .networkUnavailable, .unavailable: throw TutorConnectionFailure.networkUnavailable
      case .invalidEndpoint: throw TutorConnectionFailure.invalidEndpoint
      case .timeout: throw TutorConnectionFailure.timeout
      case .cancelled, .invalidResponse, .decodingFailed:
        throw TutorConnectionFailure.invalidResponse
      }
    } catch {
      throw TutorConnectionFailure.networkUnavailable
    }
  }

  private static let minimumPrompt = PromptPackage(
    systemInstruction: "Return only a valid JSON object.",
    userContent: "Reply with a JSON object containing ok=true.",
    outputSchema: #"{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"],"additionalProperties":false}"#,
    constraints: ["No prose", "Keep the response minimal"]
  )
}
