import Foundation
import XCTest

@testable import AITutorMac

final class ProviderSettingsTests: XCTestCase {
  func testKeychainCreateReadUpdateDeleteAndNotFound() throws {
    let service = "com.baihuaai.AITutorMac.tests.\(UUID().uuidString)"
    let account = "test-profile"
    let firstStore = KeychainCredentialStore(service: service)
    defer { try? firstStore.deleteCredential(for: account) }

    XCTAssertNil(try firstStore.readCredential(for: account))
    XCTAssertFalse(try firstStore.credentialExists(for: account))

    try firstStore.storeCredential("test-api-key-one", for: account)
    XCTAssertEqual(try firstStore.readCredential(for: account), "test-api-key-one")
    XCTAssertTrue(try firstStore.credentialExists(for: account))

    try firstStore.storeCredential("test-api-key-two", for: account)
    let restartedStore = KeychainCredentialStore(service: service)
    XCTAssertEqual(try restartedStore.readCredential(for: account), "test-api-key-two")

    try restartedStore.deleteCredential(for: account)
    XCTAssertNil(try firstStore.readCredential(for: account))
    XCTAssertNoThrow(try firstStore.deleteCredential(for: account))
  }

  func testKeychainRejectsEmptyAccountAndCredential() {
    let store = KeychainCredentialStore(
      service: "com.baihuaai.AITutorMac.tests.\(UUID().uuidString)"
    )
    XCTAssertThrowsError(try store.storeCredential("test-api-key", for: ""))
    XCTAssertThrowsError(try store.storeCredential("  ", for: "profile"))
  }

  func testSettingsEncodeDecodeAndDelete() throws {
    let suiteName = "ProviderSettingsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = LLMProviderSettingsStore(defaults: defaults)
    var settings = validSettings()
    settings.model = "test-model-v2"

    XCTAssertNil(try store.load())
    try store.save(settings)
    XCTAssertEqual(try store.load(), settings)
    try store.delete()
    XCTAssertNil(try store.load())
  }

  func testDefaultSettingsContainNoCredentialAndUseArkPreset() throws {
    let settings = LLMProviderSettings.default

    XCTAssertEqual(settings.id, LLMProviderSettings.activeProfileID)
    XCTAssertEqual(settings.preset, .ark)
    XCTAssertTrue(settings.endpoint.hasSuffix("/chat/completions"))
    XCTAssertTrue(settings.model.isEmpty)
    let data = try JSONEncoder().encode(settings)
    let body = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(body.localizedCaseInsensitiveContains("apiKey"))
    XCTAssertFalse(body.contains("test-api-key"))
  }

  func testSettingsRejectInvalidEndpointAndEmptyModel() {
    var settings = validSettings()
    settings.endpoint = "https://example.test/v1/responses"
    XCTAssertThrowsError(try settings.validated()) { error in
      XCTAssertEqual(error as? LLMProviderSettingsError, .invalidEndpoint)
    }

    settings.endpoint = "https://example.test/v1/chat/completions"
    settings.model = "  "
    XCTAssertThrowsError(try settings.validated()) { error in
      XCTAssertEqual(error as? LLMProviderSettingsError, .emptyModel)
    }
  }

  func testFactoryBuildsCompleteConfigurationAndArkCompatibilityMode() throws {
    let settingsStore = MemorySettingsStore(settings: validSettings())
    let credentialStore = MemoryCredentialStore()
    try credentialStore.storeCredential(
      "test-api-key",
      for: LLMProviderSettings.activeProfileID
    )
    let recorder = ProviderSnapshotRecorder()
    let factory = makeFactory(
      settingsStore: settingsStore,
      credentialStore: credentialStore,
      recorder: recorder
    )

    _ = try factory.makeProvider()

    XCTAssertTrue(factory.isAvailable())
    XCTAssertEqual(recorder.models, ["test-model"])
    XCTAssertEqual(recorder.credentials, ["test-api-key"])
    XCTAssertEqual(recorder.responseFormats, [.jsonObject])
  }

  func testFactoryRejectsMissingCredentialMissingModelAndInvalidEndpoint() throws {
    let settingsStore = MemorySettingsStore(settings: validSettings())
    let credentialStore = MemoryCredentialStore()
    let factory = TutorProviderFactory(
      settingsStore: settingsStore,
      credentialStore: credentialStore
    )

    XCTAssertThrowsError(try factory.makeProvider()) { error in
      XCTAssertEqual(error as? TutorProviderFactoryError, .missingCredential)
    }

    try credentialStore.storeCredential(
      "test-api-key",
      for: LLMProviderSettings.activeProfileID
    )
    settingsStore.update { $0?.model = "" }
    XCTAssertThrowsError(try factory.makeProvider()) { error in
      XCTAssertEqual(
        error as? TutorProviderFactoryError,
        .invalidSettings(.emptyModel)
      )
    }

    settingsStore.update {
      $0?.model = "test-model"
      $0?.endpoint = "not-a-url"
    }
    XCTAssertThrowsError(try factory.makeProvider()) { error in
      XCTAssertEqual(
        error as? TutorProviderFactoryError,
        .invalidSettings(.invalidEndpoint)
      )
    }
  }

  func testDeleteCredentialMakesRuntimeUnavailable() throws {
    let settingsStore = MemorySettingsStore(settings: validSettings())
    let credentialStore = MemoryCredentialStore()
    try credentialStore.storeCredential(
      "test-api-key",
      for: LLMProviderSettings.activeProfileID
    )
    let factory = TutorProviderFactory(
      settingsStore: settingsStore,
      credentialStore: credentialStore
    )
    XCTAssertTrue(factory.isAvailable())

    try credentialStore.deleteCredential(for: LLMProviderSettings.activeProfileID)

    XCTAssertFalse(factory.isAvailable())
  }

  func testChangedModelAndCredentialAreUsedOnlyByNextRuntimeRequest() async throws {
    let settingsStore = MemorySettingsStore(settings: validSettings())
    let credentialStore = MemoryCredentialStore()
    try credentialStore.storeCredential(
      "test-api-key-one",
      for: LLMProviderSettings.activeProfileID
    )
    let recorder = ProviderSnapshotRecorder()
    let factory = makeFactory(
      settingsStore: settingsStore,
      credentialStore: credentialStore,
      recorder: recorder
    )
    let engine = ProductionTutorEngine(providerFactory: factory)
    let (request, prompt) = try tutorInput()

    _ = try await engine.respond(to: request, prompt: prompt)
    settingsStore.update { $0?.model = "test-model-v2" }
    try credentialStore.storeCredential(
      "test-api-key-two",
      for: LLMProviderSettings.activeProfileID
    )
    _ = try await engine.respond(to: request, prompt: prompt)

    XCTAssertEqual(recorder.models, ["test-model", "test-model-v2"])
    XCTAssertEqual(recorder.credentials, ["test-api-key-one", "test-api-key-two"])
  }

  @MainActor
  func testSettingsControllerClearsPlaintextAfterSaveAndNeverReadsItBack() throws {
    let settingsStore = MemorySettingsStore(settings: nil)
    let credentialStore = MemoryCredentialStore()
    let controller = AIModelSettingsController(
      settingsStore: settingsStore,
      credentialStore: credentialStore,
      connectionTester: StubConnectionTester(result: .success(.init(latencyMilliseconds: 1)))
    )
    controller.draft = validSettings()
    controller.apiKeyInput = "test-api-key"

    controller.save()

    XCTAssertEqual(controller.apiKeyInput, "")
    XCTAssertTrue(controller.credentialConfigured)
    XCTAssertEqual(controller.saveState, .saved)
    controller.reload()
    XCTAssertEqual(controller.apiKeyInput, "")
    XCTAssertTrue(controller.credentialConfigured)
  }

  @MainActor
  func testCredentialFailureDoesNotFallBackToPreferences() throws {
    let settingsStore = MemorySettingsStore(settings: nil)
    let credentialStore = MemoryCredentialStore(failsWrites: true)
    let controller = AIModelSettingsController(
      settingsStore: settingsStore,
      credentialStore: credentialStore,
      connectionTester: StubConnectionTester(result: .success(.init(latencyMilliseconds: 1)))
    )
    controller.draft = validSettings()
    controller.apiKeyInput = "test-api-key"

    controller.save()

    XCTAssertNil(try settingsStore.load())
    XCTAssertFalse(controller.credentialConfigured)
    guard case .failed = controller.saveState else {
      return XCTFail("Expected a safe-save failure")
    }
  }

  func testConnectionTesterUsesMinimalJSONAndMapsFriendlyFailure() async throws {
    let successFactory = StubProviderFactory(
      provider: StubProvider(result: .success(Self.minimumResponse))
    )
    let clock = SequenceClock(
      dates: [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 1.125)]
    )
    let tester = TutorProviderConnectionTester(
      providerFactory: successFactory,
      now: { clock.now() }
    )
    let result = try await tester.testConnection()
    XCTAssertEqual(result.latencyMilliseconds, 125)

    let failureTester = TutorProviderConnectionTester(
      providerFactory: StubProviderFactory(
        provider: StubProvider(result: .failure(.authenticationFailed))
      )
    )
    do {
      _ = try await failureTester.testConnection()
      XCTFail("Expected connection failure")
    } catch let failure as TutorConnectionFailure {
      XCTAssertEqual(failure, .apiKeyInvalid)
    }
  }

  private func makeFactory(
    settingsStore: MemorySettingsStore,
    credentialStore: MemoryCredentialStore,
    recorder: ProviderSnapshotRecorder
  ) -> TutorProviderFactory {
    TutorProviderFactory(
      settingsStore: settingsStore,
      credentialStore: credentialStore,
      providerBuilder: { snapshot in
        recorder.append(snapshot)
        return FakeLLMProvider(behavior: .success)
      }
    )
  }

  private func validSettings() -> LLMProviderSettings {
    LLMProviderSettings(
      id: LLMProviderSettings.activeProfileID,
      displayName: "Test Provider",
      providerType: .openAICompatible,
      preset: .ark,
      endpoint: "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
      model: "test-model",
      responseFormatCapability: .automatic,
      temperature: 0.2,
      maxOutputTokens: 1_800,
      isEnabled: true
    )
  }

  private func tutorInput() throws -> (TutorRequest, PromptPackage) {
    let chunk = SemanticChunk(
      id: UUID(),
      sourceRevisionID: 1,
      text: "API 是一组让软件互相沟通的约定。",
      confidence: .high,
      createdAt: Date(),
      flushReason: .manualFlush
    )
    let request = try TutorRequestFactory().make(
      from: chunk,
      sessionID: UUID(),
      sequence: 1,
      learner: .productDefault(),
      trigger: .userInitiated
    )
    return (request, try TutorPromptBuilder().build(from: request))
  }

  private static let minimumResponse = RawLLMResponse(
    content: #"{"ok":true}"#,
    finishReason: .stop,
    usage: .unavailable,
    providerMetadata: LLMProviderMetadata(
      providerIdentifier: "stub",
      modelIdentifier: "test-model",
      requestIdentifier: nil,
      values: [:]
    )
  )
}

private final class MemorySettingsStore: LLMProviderSettingsStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var settings: LLMProviderSettings?

  init(settings: LLMProviderSettings?) {
    self.settings = settings
  }

  func load() throws -> LLMProviderSettings? {
    lock.withLock { settings }
  }

  func save(_ settings: LLMProviderSettings) throws {
    lock.withLock { self.settings = settings }
  }

  func delete() throws {
    lock.withLock { settings = nil }
  }

  func update(_ operation: (inout LLMProviderSettings?) -> Void) {
    lock.withLock { operation(&settings) }
  }
}

private final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]
  private let failsWrites: Bool

  init(failsWrites: Bool = false) {
    self.failsWrites = failsWrites
  }

  func storeCredential(_ credential: String, for account: String) throws {
    if failsWrites { throw CredentialStoreError.unavailable }
    lock.withLock { values[account] = credential }
  }

  func readCredential(for account: String) throws -> String? {
    lock.withLock { values[account] }
  }

  func deleteCredential(for account: String) throws {
    _ = lock.withLock { values.removeValue(forKey: account) }
  }

  func credentialExists(for account: String) throws -> Bool {
    lock.withLock { values[account] != nil }
  }
}

private final class ProviderSnapshotRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storedModels: [String] = []
  private var storedCredentials: [String] = []
  private var storedResponseFormats: [OpenAICompatibleResponseFormat] = []

  var models: [String] { lock.withLock { storedModels } }
  var credentials: [String] { lock.withLock { storedCredentials } }
  var responseFormats: [OpenAICompatibleResponseFormat] {
    lock.withLock { storedResponseFormats }
  }

  func append(_ snapshot: TutorProviderConfigurationSnapshot) {
    let credential = snapshot.credential.withValue { $0 }
    lock.withLock {
      storedModels.append(snapshot.model)
      storedCredentials.append(credential)
      storedResponseFormats.append(snapshot.responseFormat)
    }
  }
}

private struct StubConnectionTester: TutorConnectionTesting {
  let result: Result<TutorConnectionResult, TutorConnectionFailure>

  func testConnection() async throws -> TutorConnectionResult {
    try result.get()
  }
}

private struct StubProviderFactory: TutorProviderBuilding {
  let provider: any LLMProvider

  func configurationSnapshot() throws -> TutorProviderConfigurationSnapshot {
    throw TutorProviderFactoryError.missingSettings
  }

  func makeProvider() throws -> any LLMProvider { provider }
  func isAvailable() -> Bool { true }
}

private actor StubProvider: LLMProvider {
  let result: Result<RawLLMResponse, LLMProviderError>

  init(result: Result<RawLLMResponse, LLMProviderError>) {
    self.result = result
  }

  func generate(from prompt: PromptPackage) async throws -> RawLLMResponse {
    try result.get()
  }

  func stream(
    from prompt: PromptPackage
  ) async -> AsyncThrowingStream<RawLLMStreamChunk, Error> {
    AsyncThrowingStream { $0.finish() }
  }

  func cancel() async {}
}

private final class SequenceClock: @unchecked Sendable {
  private let lock = NSLock()
  private var dates: [Date]

  init(dates: [Date]) {
    self.dates = dates
  }

  func now() -> Date {
    lock.withLock { dates.isEmpty ? Date() : dates.removeFirst() }
  }
}
