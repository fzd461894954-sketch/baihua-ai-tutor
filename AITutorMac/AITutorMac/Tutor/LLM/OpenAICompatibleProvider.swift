import Foundation

enum OpenAICompatibleResponseFormat: Equatable, Sendable {
  case jsonSchema
  case jsonObject
  case unsupported
}

/// A provider-neutral Chat Completions HTTP adapter.
///
/// Credentials are accepted only at runtime and remain in memory for the
/// lifetime of this instance. This type performs no persistence of any kind.
final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {
  private let endpoint: URL
  private let model: String
  private let apiKey: String
  private let temperature: Double
  private let maxTokens: Int
  private let responseFormat: OpenAICompatibleResponseFormat
  private let requestTimeout: TimeInterval
  private let sessionConfiguration: URLSessionConfiguration
  private let session: URLSession
  private let taskRegistry = OpenAICompatibleTaskRegistry()

  init(
    endpoint: URL,
    model: String,
    apiKey: String,
    temperature: Double = 0.2,
    maxTokens: Int = 1_200,
    responseFormat: OpenAICompatibleResponseFormat = .jsonSchema,
    requestTimeout: TimeInterval = 60,
    sessionConfiguration: URLSessionConfiguration = .ephemeral
  ) {
    self.endpoint = endpoint
    self.model = model
    self.apiKey = apiKey
    self.temperature = temperature
    self.maxTokens = maxTokens
    self.responseFormat = responseFormat
    self.requestTimeout = requestTimeout

    let configuration = sessionConfiguration.copy() as! URLSessionConfiguration
    configuration.timeoutIntervalForRequest = requestTimeout
    configuration.timeoutIntervalForResource = requestTimeout
    self.sessionConfiguration = configuration
    session = URLSession(configuration: configuration)
  }

  deinit {
    taskRegistry.cancelAll()
    session.invalidateAndCancel()
  }

  func generate(from prompt: PromptPackage) async throws -> RawLLMResponse {
    do {
      let request = try makeRequest(from: prompt, stream: false)
      let (data, response) = try await perform(request)
      try Self.validate(response)
      return try Self.decodeResponse(data, fallbackModel: model)
    } catch {
      throw Self.normalized(error)
    }
  }

  func stream(
    from prompt: PromptPackage
  ) async -> AsyncThrowingStream<RawLLMStreamChunk, Error> {
    let request: URLRequest
    do {
      request = try makeRequest(from: prompt, stream: true)
    } catch {
      return Self.failedStream(with: Self.normalized(error))
    }

    let (stream, continuation) = AsyncThrowingStream<
      RawLLMStreamChunk,
      Error
    >.makeStream()
    let delegate = OpenAICompatibleSSEDelegate(
      continuation: continuation,
      fallbackModel: model,
      taskRegistry: taskRegistry
    )
    let configuration = sessionConfiguration.copy() as! URLSessionConfiguration
    let delegateQueue = OperationQueue()
    delegateQueue.maxConcurrentOperationCount = 1
    let streamSession = URLSession(
      configuration: configuration,
      delegate: delegate,
      delegateQueue: delegateQueue
    )
    delegate.attach(session: streamSession)

    let task = streamSession.dataTask(with: request)
    delegate.attach(task: task)
    taskRegistry.insert(task)
    continuation.onTermination = { @Sendable termination in
      guard case .cancelled = termination else {
        return
      }
      delegate.cancel()
    }
    task.resume()
    return stream
  }

  func cancel() async {
    taskRegistry.cancelAll()
  }

  private func makeRequest(
    from prompt: PromptPackage,
    stream: Bool
  ) throws -> URLRequest {
    guard
      ["http", "https"].contains(endpoint.scheme?.lowercased() ?? ""),
      model.contains(where: { !$0.isWhitespace }),
      apiKey.contains(where: { !$0.isWhitespace }),
      temperature.isFinite,
      (0...2).contains(temperature),
      maxTokens > 0,
      requestTimeout > 0
    else {
      throw LLMProviderError.unavailable
    }

    var body: [String: Any] = [
      "model": model,
      "messages": [
        ["role": "system", "content": systemContent(for: prompt)],
        ["role": "user", "content": prompt.userContent],
      ],
      "temperature": temperature,
      "max_tokens": maxTokens,
      "stream": stream,
    ]

    switch responseFormat {
    case .jsonSchema:
      let schema = try Self.jsonObject(from: prompt.outputSchema)
      body["response_format"] = [
        "type": "json_schema",
        "json_schema": [
          "name": "TutorResponse",
          "strict": true,
          "schema": schema,
        ],
      ]
    case .jsonObject:
      body["response_format"] = ["type": "json_object"]
    case .unsupported:
      break
    }

    let encodedBody: Data
    do {
      encodedBody = try JSONSerialization.data(
        withJSONObject: body,
        options: [.sortedKeys]
      )
    } catch {
      throw LLMProviderError.invalidResponse
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = encodedBody
    request.timeoutInterval = requestTimeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(
      stream ? "text/event-stream" : "application/json",
      forHTTPHeaderField: "Accept"
    )
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    return request
  }

  private func systemContent(for prompt: PromptPackage) -> String {
    var sections = [prompt.systemInstruction]
    if !prompt.constraints.isEmpty {
      let constraints = prompt.constraints
        .enumerated()
        .map { "\($0.offset + 1). \($0.element)" }
        .joined(separator: "\n")
      sections.append("Constraints:\n\(constraints)")
    }
    if responseFormat != .jsonSchema {
      sections.append("Output JSON Schema:\n\(prompt.outputSchema)")
    }
    return sections.joined(separator: "\n\n")
  }

  private func perform(
    _ request: URLRequest
  ) async throws -> (Data, HTTPURLResponse) {
    let cancellation = OpenAICompatibleCancellationBox()

    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        let token = UUID()
        let task = session.dataTask(with: request) {
          [taskRegistry] data, response, error in
          taskRegistry.remove(token: token)

          if let error {
            continuation.resume(throwing: Self.normalized(error))
            return
          }
          guard let response = response as? HTTPURLResponse else {
            continuation.resume(throwing: LLMProviderError.invalidResponse)
            return
          }
          continuation.resume(returning: (data ?? Data(), response))
        }
        taskRegistry.insert(task, token: token)
        cancellation.set(task)
        task.resume()
      }
    } onCancel: {
      cancellation.cancel()
    }
  }

  fileprivate static func validate(_ response: HTTPURLResponse) throws {
    switch response.statusCode {
    case 200...299:
      return
    case 401, 403:
      throw LLMProviderError.authenticationFailed
    case 400, 404:
      throw LLMProviderError.modelUnavailable
    case 429:
      throw LLMProviderError.rateLimited
    default:
      throw LLMProviderError.unavailable
    }
  }

  private static func decodeResponse(
    _ data: Data,
    fallbackModel: String
  ) throws -> RawLLMResponse {
    guard !data.isEmpty else {
      throw LLMProviderError.invalidResponse
    }
    do {
      _ = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw LLMProviderError.decodingFailed
    }

    let response: OpenAICompatibleChatResponse
    do {
      response = try JSONDecoder().decode(OpenAICompatibleChatResponse.self, from: data)
    } catch {
      throw LLMProviderError.invalidResponse
    }

    guard
      let choice = response.choices.first,
      let content = choice.message.content,
      content.contains(where: { !$0.isWhitespace })
    else {
      throw LLMProviderError.invalidResponse
    }

    return RawLLMResponse(
      content: content,
      finishReason: finishReason(from: choice.finishReason),
      usage: usage(from: response.usage),
      providerMetadata: metadata(
        id: response.id,
        model: response.model ?? fallbackModel,
        object: response.object,
        systemFingerprint: response.systemFingerprint
      )
    )
  }

  fileprivate static func decodeStreamEvent(
    _ data: Data,
    fallbackModel: String,
    sequence: Int
  ) throws -> RawLLMStreamChunk? {
    do {
      _ = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw LLMProviderError.decodingFailed
    }

    let event: OpenAICompatibleChatStreamEvent
    do {
      event = try JSONDecoder().decode(
        OpenAICompatibleChatStreamEvent.self,
        from: data
      )
    } catch {
      throw LLMProviderError.invalidResponse
    }

    let choice = event.choices.first
    let content = choice?.delta.content ?? ""
    let finishReason = finishReason(from: choice?.finishReason)
    let usage = event.usage.map(usage(from:))
    guard !content.isEmpty || finishReason != nil || usage != nil else {
      return nil
    }

    return RawLLMStreamChunk(
      sequence: sequence,
      contentDelta: content,
      finishReason: finishReason,
      usage: usage,
      providerMetadata: metadata(
        id: event.id,
        model: event.model ?? fallbackModel,
        object: event.object,
        systemFingerprint: event.systemFingerprint
      )
    )
  }

  fileprivate static func finishReason(from value: String?) -> LLMFinishReason? {
    guard let value else {
      return nil
    }
    switch value {
    case "stop":
      return .stop
    case "length":
      return .length
    case "cancelled", "canceled":
      return .cancelled
    default:
      return .other(value)
    }
  }

  private static func usage(
    from value: OpenAICompatibleUsage?
  ) -> LLMUsageMetadata {
    guard let value else {
      return .unavailable
    }
    return LLMUsageMetadata(
      inputTokenCount: value.promptTokens,
      outputTokenCount: value.completionTokens,
      totalTokenCount: value.totalTokens
    )
  }

  private static func metadata(
    id: String?,
    model: String,
    object: String?,
    systemFingerprint: String?
  ) -> LLMProviderMetadata {
    var values: [String: String] = [:]
    if let object {
      values["object"] = object
    }
    if let systemFingerprint {
      values["systemFingerprint"] = systemFingerprint
    }
    return LLMProviderMetadata(
      providerIdentifier: "openai-compatible",
      modelIdentifier: model,
      requestIdentifier: id,
      values: values
    )
  }

  private static func jsonObject(from value: String) throws -> [String: Any] {
    guard let data = value.data(using: .utf8) else {
      throw LLMProviderError.invalidResponse
    }
    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        throw LLMProviderError.invalidResponse
      }
      guard let compatibleSchema = structuredOutputSchema(object) as? [String: Any]
      else {
        throw LLMProviderError.invalidResponse
      }
      return compatibleSchema
    } catch let error as LLMProviderError {
      throw error
    } catch {
      throw LLMProviderError.invalidResponse
    }
  }

  /// Keeps the stable, provider-neutral Prompt schema intact while adapting
  /// its transport copy to the Structured Outputs JSON Schema subset.
  private static func structuredOutputSchema(_ value: Any) -> Any {
    if let object = value as? [String: Any] {
      return object.reduce(into: [String: Any]()) { result, entry in
        guard entry.key != "$schema" else {
          return
        }
        let key = entry.key == "oneOf" ? "anyOf" : entry.key
        result[key] = structuredOutputSchema(entry.value)
      }
    }
    if let array = value as? [Any] {
      return array.map(structuredOutputSchema)
    }
    return value
  }

  fileprivate static func normalized(_ error: Error) -> LLMProviderError {
    if let providerError = error as? LLMProviderError {
      return providerError
    }
    if error is CancellationError {
      return .cancelled
    }
    guard let urlError = error as? URLError else {
      return .unavailable
    }
    switch urlError.code {
    case .cancelled:
      return .cancelled
    case .timedOut:
      return .timeout
    case .notConnectedToInternet,
         .networkConnectionLost,
         .cannotFindHost,
         .cannotConnectToHost,
         .dnsLookupFailed,
         .internationalRoamingOff,
         .dataNotAllowed,
         .resourceUnavailable:
      return .networkUnavailable
    case .badURL, .unsupportedURL:
      return .invalidEndpoint
    default:
      return .unavailable
    }
  }

  private static func failedStream(
    with error: LLMProviderError
  ) -> AsyncThrowingStream<RawLLMStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      continuation.finish(throwing: error)
    }
  }
}

private struct OpenAICompatibleChatResponse: Decodable {
  let id: String?
  let object: String?
  let model: String?
  let choices: [Choice]
  let usage: OpenAICompatibleUsage?
  let systemFingerprint: String?

  enum CodingKeys: String, CodingKey {
    case id
    case object
    case model
    case choices
    case usage
    case systemFingerprint = "system_fingerprint"
  }

  struct Choice: Decodable {
    let message: Message
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
      case message
      case finishReason = "finish_reason"
    }
  }

  struct Message: Decodable {
    let content: String?
  }
}

private struct OpenAICompatibleChatStreamEvent: Decodable {
  let id: String?
  let object: String?
  let model: String?
  let choices: [Choice]
  let usage: OpenAICompatibleUsage?
  let systemFingerprint: String?

  enum CodingKeys: String, CodingKey {
    case id
    case object
    case model
    case choices
    case usage
    case systemFingerprint = "system_fingerprint"
  }

  struct Choice: Decodable {
    let delta: Delta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
      case delta
      case finishReason = "finish_reason"
    }
  }

  struct Delta: Decodable {
    let content: String?
  }
}

private struct OpenAICompatibleUsage: Decodable {
  let promptTokens: Int?
  let completionTokens: Int?
  let totalTokens: Int?

  enum CodingKeys: String, CodingKey {
    case promptTokens = "prompt_tokens"
    case completionTokens = "completion_tokens"
    case totalTokens = "total_tokens"
  }
}

private final class OpenAICompatibleSSEDelegate: NSObject,
  URLSessionDataDelegate,
  @unchecked Sendable
{
  private let continuation: AsyncThrowingStream<RawLLMStreamChunk, Error>.Continuation
  private let fallbackModel: String
  private let taskRegistry: OpenAICompatibleTaskRegistry
  private let finishLock = NSLock()

  private var session: URLSession?
  private var dataTask: URLSessionDataTask?
  private var lineBuffer = Data()
  private var eventDataLines: [String] = []
  private var nextSequence = 0
  private var terminalError: LLMProviderError?
  private var isFinished = false

  init(
    continuation: AsyncThrowingStream<RawLLMStreamChunk, Error>.Continuation,
    fallbackModel: String,
    taskRegistry: OpenAICompatibleTaskRegistry
  ) {
    self.continuation = continuation
    self.fallbackModel = fallbackModel
    self.taskRegistry = taskRegistry
  }

  func attach(session: URLSession) {
    self.session = session
  }

  func attach(task: URLSessionDataTask) {
    dataTask = task
  }

  func cancel() {
    dataTask?.cancel()
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let response = response as? HTTPURLResponse else {
      terminalError = .invalidResponse
      completionHandler(.cancel)
      return
    }
    do {
      try OpenAICompatibleProvider.validate(response)
      completionHandler(.allow)
    } catch {
      terminalError = OpenAICompatibleProvider.normalized(error)
      completionHandler(.cancel)
    }
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    guard !finished else {
      return
    }
    lineBuffer.append(data)
    do {
      try consumeCompleteLines(task: dataTask)
    } catch {
      finish(throwing: OpenAICompatibleProvider.normalized(error), task: dataTask)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard !finished else {
      return
    }
    if let terminalError {
      finish(throwing: terminalError, task: task)
      return
    }
    if let error {
      finish(throwing: OpenAICompatibleProvider.normalized(error), task: task)
      return
    }

    do {
      try consumeEndOfFile(task: task)
      if !finished {
        finish(throwing: .invalidResponse, task: task)
      }
    } catch {
      finish(throwing: OpenAICompatibleProvider.normalized(error), task: task)
    }
  }

  private var finished: Bool {
    finishLock.lock()
    defer { finishLock.unlock() }
    return isFinished
  }

  private func consumeCompleteLines(task: URLSessionTask) throws {
    while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
      var lineData = lineBuffer[..<newlineIndex]
      lineBuffer.removeSubrange(...newlineIndex)
      if lineData.last == 0x0D {
        lineData = lineData.dropLast()
      }
      guard let line = String(data: Data(lineData), encoding: .utf8) else {
        throw LLMProviderError.decodingFailed
      }
      try consume(line: line, task: task)
      if finished {
        return
      }
    }
  }

  private func consumeEndOfFile(task: URLSessionTask) throws {
    if !lineBuffer.isEmpty {
      var lineData = lineBuffer
      lineBuffer.removeAll(keepingCapacity: false)
      if lineData.last == 0x0D {
        lineData.removeLast()
      }
      guard let line = String(data: lineData, encoding: .utf8) else {
        throw LLMProviderError.decodingFailed
      }
      try consume(line: line, task: task)
    }
    if !eventDataLines.isEmpty, !finished {
      try dispatchEvent(task: task)
    }
  }

  private func consume(line: String, task: URLSessionTask) throws {
    if line.isEmpty {
      if !eventDataLines.isEmpty {
        try dispatchEvent(task: task)
      }
      return
    }
    if line.hasPrefix(":") {
      return
    }

    let field: Substring
    var value: Substring
    if let colonIndex = line.firstIndex(of: ":") {
      field = line[..<colonIndex]
      value = line[line.index(after: colonIndex)...]
      if value.first == " " {
        value = value.dropFirst()
      }
    } else {
      field = Substring(line)
      value = ""
    }
    if field == "data" {
      eventDataLines.append(String(value))
    }
  }

  private func dispatchEvent(task: URLSessionTask) throws {
    let payload = eventDataLines.joined(separator: "\n")
    eventDataLines.removeAll(keepingCapacity: true)
    guard payload.contains(where: { !$0.isWhitespace }) else {
      throw LLMProviderError.invalidResponse
    }
    if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
      finishSuccessfully(task: task)
      return
    }
    guard let data = payload.data(using: .utf8) else {
      throw LLMProviderError.decodingFailed
    }
    if let chunk = try OpenAICompatibleProvider.decodeStreamEvent(
      data,
      fallbackModel: fallbackModel,
      sequence: nextSequence
    ) {
      continuation.yield(chunk)
      nextSequence += 1
    }
  }

  private func finishSuccessfully(task: URLSessionTask) {
    guard markFinished() else {
      return
    }
    taskRegistry.remove(task)
    continuation.finish()
    task.cancel()
    session?.invalidateAndCancel()
    session = nil
  }

  private func finish(throwing error: LLMProviderError, task: URLSessionTask) {
    guard markFinished() else {
      return
    }
    taskRegistry.remove(task)
    continuation.finish(throwing: error)
    task.cancel()
    session?.invalidateAndCancel()
    session = nil
  }

  private func markFinished() -> Bool {
    finishLock.lock()
    defer { finishLock.unlock() }
    guard !isFinished else {
      return false
    }
    isFinished = true
    return true
  }
}

private final class OpenAICompatibleTaskRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var tasks: [UUID: URLSessionTask] = [:]

  func insert(_ task: URLSessionTask, token: UUID = UUID()) {
    lock.lock()
    tasks[token] = task
    lock.unlock()
  }

  func remove(token: UUID) {
    lock.lock()
    tasks[token] = nil
    lock.unlock()
  }

  func remove(_ task: URLSessionTask) {
    lock.lock()
    if let token = tasks.first(where: { $0.value === task })?.key {
      tasks[token] = nil
    }
    lock.unlock()
  }

  func cancelAll() {
    lock.lock()
    let activeTasks = Array(tasks.values)
    tasks.removeAll()
    lock.unlock()
    activeTasks.forEach { $0.cancel() }
  }
}

private final class OpenAICompatibleCancellationBox: @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionTask?
  private var isCancelled = false

  func set(_ task: URLSessionTask) {
    lock.lock()
    if isCancelled {
      lock.unlock()
      task.cancel()
      return
    }
    self.task = task
    lock.unlock()
  }

  func cancel() {
    lock.lock()
    isCancelled = true
    let task = task
    lock.unlock()
    task?.cancel()
  }
}
