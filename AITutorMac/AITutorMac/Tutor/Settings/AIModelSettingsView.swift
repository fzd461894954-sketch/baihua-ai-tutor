import AppKit
import Observation
import SwiftUI

enum AIModelSettingsSaveState: Equatable, Sendable {
  case idle
  case saved
  case failed(String)
}

enum AIModelConnectionState: Equatable, Sendable {
  case idle
  case testing
  case succeeded(latencyMilliseconds: Int)
  case failed(String)
}

@MainActor
@Observable
final class AIModelSettingsController {
  var draft: LLMProviderSettings
  var apiKeyInput = ""
  var isEditingCredential = false
  private(set) var credentialConfigured = false
  private(set) var saveState: AIModelSettingsSaveState = .idle
  private(set) var connectionState: AIModelConnectionState = .idle

  var onConfigurationDidChange: (@MainActor @Sendable () -> Void)?

  @ObservationIgnored private let settingsStore: any LLMProviderSettingsStoring
  @ObservationIgnored private let credentialStore: any CredentialStoring
  @ObservationIgnored private let connectionTester: any TutorConnectionTesting
  @ObservationIgnored private var connectionTask: Task<Void, Never>?

  init(
    settingsStore: any LLMProviderSettingsStoring,
    credentialStore: any CredentialStoring,
    connectionTester: any TutorConnectionTesting
  ) {
    self.settingsStore = settingsStore
    self.credentialStore = credentialStore
    self.connectionTester = connectionTester
    draft = (try? settingsStore.load()) ?? .default
    reloadCredentialState()
  }

  deinit {
    connectionTask?.cancel()
  }

  func reload() {
    connectionTask?.cancel()
    connectionTask = nil
    draft = (try? settingsStore.load()) ?? .default
    apiKeyInput = ""
    isEditingCredential = false
    saveState = .idle
    connectionState = .idle
    reloadCredentialState()
  }

  func selectPreset(_ preset: LLMProviderPreset) {
    let previousPreset = draft.preset
    draft.preset = preset
    draft.displayName = preset.displayName
    if
      preset == .ark,
      draft.endpoint.isEmpty || draft.endpoint == previousPreset.suggestedEndpoint
    {
      draft.endpoint = preset.suggestedEndpoint ?? draft.endpoint
    }
    saveState = .idle
    connectionState = .idle
  }

  func save() {
    connectionTask?.cancel()
    connectionTask = nil
    connectionState = .idle

    do {
      _ = try draft.validated()
      let account = draft.credentialAccount
      let previousCredential = try credentialStore.readCredential(for: account)
      let newCredential = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
      let replacesCredential = !newCredential.isEmpty

      if replacesCredential {
        try credentialStore.storeCredential(newCredential, for: account)
      }

      do {
        try settingsStore.save(draft)
      } catch {
        if replacesCredential {
          if let previousCredential {
            try? credentialStore.storeCredential(previousCredential, for: account)
          } else {
            try? credentialStore.deleteCredential(for: account)
          }
        }
        throw error
      }

      apiKeyInput = ""
      isEditingCredential = false
      credentialConfigured = try credentialStore.credentialExists(for: account)
      saveState = .saved
      onConfigurationDidChange?()
    } catch let error as LLMProviderSettingsError {
      saveState = .failed(Self.settingsMessage(error))
    } catch {
      saveState = .failed("无法安全保存 API Key，请稍后重试。")
    }
  }

  func beginCredentialReplacement() {
    apiKeyInput = ""
    isEditingCredential = true
    saveState = .idle
  }

  func deleteCredential() {
    do {
      try credentialStore.deleteCredential(for: draft.credentialAccount)
      apiKeyInput = ""
      isEditingCredential = false
      credentialConfigured = false
      saveState = .saved
      connectionState = .idle
      onConfigurationDidChange?()
    } catch {
      saveState = .failed("无法安全删除 API Key，请稍后重试。")
    }
  }

  func deleteConfiguration() {
    connectionTask?.cancel()
    connectionTask = nil
    do {
      try credentialStore.deleteCredential(for: draft.credentialAccount)
      try settingsStore.delete()
      draft = .default
      apiKeyInput = ""
      isEditingCredential = false
      credentialConfigured = false
      saveState = .idle
      connectionState = .idle
      onConfigurationDidChange?()
    } catch {
      saveState = .failed("无法安全删除模型配置，请稍后重试。")
    }
  }

  func testConnection() {
    connectionTask?.cancel()
    connectionState = .testing
    connectionTask = Task { [weak self] in
      guard let self else { return }
      do {
        let result = try await connectionTester.testConnection()
        try Task.checkCancellation()
        connectionState = .succeeded(latencyMilliseconds: result.latencyMilliseconds)
      } catch is CancellationError {
        connectionState = .idle
      } catch let failure as TutorConnectionFailure {
        connectionState = .failed(Self.connectionMessage(failure))
      } catch {
        connectionState = .failed("网络连接失败。")
      }
      connectionTask = nil
    }
  }

  private func reloadCredentialState() {
    credentialConfigured = (try? credentialStore.credentialExists(
      for: draft.credentialAccount
    )) ?? false
  }

  private static func settingsMessage(_ error: LLMProviderSettingsError) -> String {
    switch error {
    case .invalidEndpoint: return "请输入有效的 Chat Completions 服务地址。"
    case .emptyModel: return "请填写你的账号可用的模型名称。"
    case .invalidTemperature: return "Temperature 需要在 0 到 2 之间。"
    case .invalidMaxOutputTokens: return "Max Output Tokens 需要在 1 到 32,000 之间。"
    case .invalidProfile, .disabled, .persistenceFailed:
      return "模型配置无法保存，请检查后重试。"
    }
  }

  private static func connectionMessage(_ failure: TutorConnectionFailure) -> String {
    switch failure {
    case .apiKeyInvalid: return "API Key 无效。"
    case .modelUnavailable: return "当前账号无法使用该模型。"
    case .rateLimited: return "请求过于频繁，请稍后重试。"
    case .networkUnavailable: return "网络连接失败。"
    case .invalidEndpoint: return "服务地址无效。"
    case .timeout: return "请求超时，请稍后重试。"
    case .invalidResponse: return "服务返回了无法识别的响应。"
    case .configurationIncomplete: return "请先保存完整的模型配置和 API Key。"
    }
  }
}

struct AIModelSettingsView: View {
  @Bindable var controller: AIModelSettingsController
  @State private var showsDeleteConfirmation = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          Text("AI 模型服务").font(.title2.bold())
          Text("配置花花老师用来解释内容的模型。")
            .foregroundStyle(.secondary)
        }

        GroupBox {
          Form {
            Picker("Provider", selection: presetBinding) {
              ForEach(LLMProviderPreset.allCases) { preset in
                Text(preset.displayName).tag(preset)
              }
            }
            TextField("Endpoint", text: $controller.draft.endpoint)
              .textFieldStyle(.roundedBorder)
            TextField("Model", text: $controller.draft.model)
              .textFieldStyle(.roundedBorder)

            LabeledContent("API Key") {
              HStack(spacing: 10) {
                Label(
                  controller.credentialConfigured ? "已配置" : "未配置",
                  systemImage: controller.credentialConfigured
                    ? "checkmark.shield.fill" : "shield.slash"
                )
                .foregroundStyle(controller.credentialConfigured ? .green : .secondary)
                if controller.credentialConfigured {
                  Button("更换 API Key") { controller.beginCredentialReplacement() }
                  Button("删除 API Key", role: .destructive) {
                    controller.deleteCredential()
                  }
                }
              }
            }
            if controller.isEditingCredential || !controller.credentialConfigured {
              SecureField("输入新 API Key", text: $controller.apiKeyInput)
                .textFieldStyle(.roundedBorder)
            }
          }
          .formStyle(.grouped)
        }

        DisclosureGroup("Advanced") {
          Form {
            Picker("Response Format", selection: $controller.draft.responseFormatCapability) {
              ForEach(LLMResponseFormatCapability.allCases, id: \.self) { capability in
                Text(capability.displayName).tag(capability)
              }
            }
            HStack {
              Text("Temperature")
              Slider(value: $controller.draft.temperature, in: 0...2, step: 0.1)
              Text(controller.draft.temperature.formatted(.number.precision(.fractionLength(1))))
                .monospacedDigit().frame(width: 32)
            }
            Stepper(
              "Max Output Tokens: \(controller.draft.maxOutputTokens)",
              value: $controller.draft.maxOutputTokens,
              in: 256...32_000,
              step: 256
            )
          }
          .formStyle(.grouped)
          .padding(.top, 8)
        }

        privacyNotice
        statusContent

        HStack(spacing: 10) {
          Button("保存") { controller.save() }
            .buttonStyle(.borderedProminent)
          Button("测试连接") { controller.testConnection() }
            .disabled(!controller.credentialConfigured || isTesting)
          Spacer()
          Button("删除模型配置", role: .destructive) {
            showsDeleteConfirmation = true
          }
        }
      }
      .padding(24)
    }
    .frame(minWidth: 560, minHeight: 600)
    .alert("删除模型配置？", isPresented: $showsDeleteConfirmation) {
      Button("删除", role: .destructive) { controller.deleteConfiguration() }
      Button("取消", role: .cancel) {}
    } message: {
      Text("这会删除 AI 模型设置和 Keychain 中的 API Key，不会影响老师形象、内容跟随或语音设置。")
    }
  }

  private var presetBinding: Binding<LLMProviderPreset> {
    Binding(
      get: { controller.draft.preset },
      set: { controller.selectPreset($0) }
    )
  }

  private var isTesting: Bool {
    if case .testing = controller.connectionState { return true }
    return false
  }

  private var privacyNotice: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("隐私说明", systemImage: "lock.shield")
        .font(.headline)
      Text("当你主动请求解释时，需要解释的当前文本会发送给你配置的 AI 模型服务。")
      Text("花花老师不会把完整屏幕自动上传给模型。")
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  @ViewBuilder private var statusContent: some View {
    switch controller.saveState {
    case .idle: EmptyView()
    case .saved:
      Label("设置已保存。", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    }
    switch controller.connectionState {
    case .idle: EmptyView()
    case .testing:
      HStack { ProgressView().controlSize(.small); Text("正在测试连接……") }
    case let .succeeded(latency):
      Label("连接成功·\(latency) ms", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    }
  }
}

@MainActor
final class AIModelSettingsWindowController: NSObject, NSWindowDelegate {
  private let controller: AIModelSettingsController
  private var window: NSWindow?

  init(controller: AIModelSettingsController) {
    self.controller = controller
  }

  func show() {
    controller.reload()
    let window = window ?? makeWindow()
    self.window = window
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func stop() {
    window?.orderOut(nil)
    window?.contentViewController = nil
    window = nil
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "设置 · AI 模型"
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName("AIModelSettingsWindow")
    window.contentMinSize = NSSize(width: 560, height: 600)
    window.delegate = self
    window.contentViewController = NSHostingController(
      rootView: AIModelSettingsView(controller: controller)
    )
    window.center()
    return window
  }
}

#if DEBUG
private final class PreviewModelSettingsStore: LLMProviderSettingsStoring, @unchecked Sendable {
  private var value: LLMProviderSettings?

  init(_ value: LLMProviderSettings?) {
    self.value = value
  }

  func load() throws -> LLMProviderSettings? { value }
  func save(_ settings: LLMProviderSettings) throws { value = settings }
  func delete() throws { value = nil }
}

private final class PreviewCredentialStore: CredentialStoring, @unchecked Sendable {
  private var isConfigured: Bool

  init(configured: Bool) {
    isConfigured = configured
  }

  func storeCredential(_ credential: String, for account: String) throws {
    isConfigured = !credential.isEmpty
  }

  func readCredential(for account: String) throws -> String? { nil }
  func deleteCredential(for account: String) throws { isConfigured = false }
  func credentialExists(for account: String) throws -> Bool { isConfigured }
}

private struct PreviewConnectionTester: TutorConnectionTesting {
  func testConnection() async throws -> TutorConnectionResult {
    TutorConnectionResult(latencyMilliseconds: 128)
  }
}

#Preview("AI Model Settings · Configured") {
  var settings = LLMProviderSettings.default
  settings.model = "doubao-seed-preview"
  let controller = AIModelSettingsController(
    settingsStore: PreviewModelSettingsStore(settings),
    credentialStore: PreviewCredentialStore(configured: true),
    connectionTester: PreviewConnectionTester()
  )
  return AIModelSettingsView(controller: controller)
}

#Preview("AI Model Settings · Needs Setup") {
  AIModelSettingsView(
    controller: AIModelSettingsController(
      settingsStore: PreviewModelSettingsStore(nil),
      credentialStore: PreviewCredentialStore(configured: false),
      connectionTester: PreviewConnectionTester()
    )
  )
}
#endif
