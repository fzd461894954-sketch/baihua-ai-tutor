import Foundation

#if DEBUG
enum FakeLLMProviderBehavior: Equatable, Sendable {
  case success
  case needsMoreContext
  case blocked
  case malformedJSON
  case timeout
  case unavailable
  case response(RawLLMResponse)
}

/// Deterministic local provider used to exercise the raw provider boundary.
/// It performs no I/O and never returns a TutorResponse directly.
actor FakeLLMProvider: LLMProvider {
  let behavior: FakeLLMProviderBehavior

  private(set) var generateCallCount = 0
  private(set) var streamCallCount = 0
  private(set) var cancelCallCount = 0

  private let responseDelayNanoseconds: UInt64
  private let streamDelayNanoseconds: UInt64
  private let configuredStreamChunks: [String]?
  private let now: @Sendable () -> Date
  private let makeID: @Sendable () -> UUID

  private var activeGenerationID: UUID?
  private var activeGenerationTask: Task<RawLLMResponse, Error>?
  private var activeStreamTask: Task<Void, Never>?

  init(
    behavior: FakeLLMProviderBehavior = .success,
    responseDelayNanoseconds: UInt64 = 0,
    streamDelayNanoseconds: UInt64 = 0,
    streamChunks: [String]? = nil,
    now: @escaping @Sendable () -> Date = { Date() },
    makeID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.behavior = behavior
    self.responseDelayNanoseconds = responseDelayNanoseconds
    self.streamDelayNanoseconds = streamDelayNanoseconds
    configuredStreamChunks = streamChunks
    self.now = now
    self.makeID = makeID
  }

  func generate(from prompt: PromptPackage) async throws -> RawLLMResponse {
    generateCallCount += 1
    activeGenerationTask?.cancel()

    let generationID = UUID()
    let behavior = behavior
    let delay = responseDelayNanoseconds
    let createdAt = now()
    let responseID = makeID()
    let task = Task<RawLLMResponse, Error> {
      if delay > 0 {
        try await Task.sleep(nanoseconds: delay)
      }
      try Task.checkCancellation()

      switch behavior {
      case .success, .needsMoreContext, .blocked:
        return try Self.makeRawResponse(
          prompt: prompt,
          behavior: behavior,
          responseID: responseID,
          createdAt: createdAt
        )
      case .malformedJSON:
        return RawLLMResponse(
          content: "{ malformed-json",
          finishReason: .stop,
          usage: .unavailable,
          providerMetadata: Self.metadata
        )
      case .timeout:
        throw LLMProviderError.timeout
      case .unavailable:
        throw LLMProviderError.unavailable
      case let .response(response):
        return response
      }
    }

    activeGenerationID = generationID
    activeGenerationTask = task
    do {
      let response = try await task.value
      clearGeneration(ifOwnedBy: generationID)
      return response
    } catch is CancellationError {
      clearGeneration(ifOwnedBy: generationID)
      throw LLMProviderError.cancelled
    } catch let error as LLMProviderError {
      clearGeneration(ifOwnedBy: generationID)
      throw error
    } catch {
      clearGeneration(ifOwnedBy: generationID)
      throw LLMProviderError.unavailable
    }
  }

  func stream(
    from prompt: PromptPackage
  ) async -> AsyncThrowingStream<RawLLMStreamChunk, Error> {
    streamCallCount += 1
    activeStreamTask?.cancel()

    let (stream, continuation) = AsyncThrowingStream<
      RawLLMStreamChunk,
      Error
    >.makeStream()
    let behavior = behavior
    let delay = streamDelayNanoseconds
    let configuredChunks = configuredStreamChunks
    let createdAt = now()
    let responseID = makeID()

    let task = Task {
      do {
        switch behavior {
        case .timeout:
          if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
          }
          throw LLMProviderError.timeout
        case .unavailable:
          throw LLMProviderError.unavailable
        default:
          let rawResponse: RawLLMResponse
          if case let .response(response) = behavior {
            rawResponse = response
          } else if behavior == .malformedJSON {
            rawResponse = RawLLMResponse(
              content: "{ malformed-json",
              finishReason: .stop,
              usage: .unavailable,
              providerMetadata: Self.metadata
            )
          } else {
            rawResponse = try Self.makeRawResponse(
              prompt: prompt,
              behavior: behavior,
              responseID: responseID,
              createdAt: createdAt
            )
          }

          let chunks = configuredChunks
            ?? Self.chunks(from: rawResponse.content, maximumCharacterCount: 80)
          for (index, content) in chunks.enumerated() {
            if delay > 0 {
              try await Task.sleep(nanoseconds: delay)
            }
            try Task.checkCancellation()
            let isLast = index == chunks.count - 1
            continuation.yield(
              RawLLMStreamChunk(
                sequence: index,
                contentDelta: content,
                finishReason: isLast ? rawResponse.finishReason : nil,
                usage: isLast ? rawResponse.usage : nil,
                providerMetadata: rawResponse.providerMetadata
              )
            )
          }
          continuation.finish()
        }
      } catch is CancellationError {
        continuation.finish(throwing: LLMProviderError.cancelled)
      } catch let error as LLMProviderError {
        continuation.finish(throwing: error)
      } catch {
        continuation.finish(throwing: LLMProviderError.unavailable)
      }
    }
    activeStreamTask = task
    continuation.onTermination = { @Sendable _ in
      task.cancel()
    }
    return stream
  }

  func cancel() async {
    cancelCallCount += 1
    activeGenerationTask?.cancel()
    activeGenerationTask = nil
    activeGenerationID = nil
    activeStreamTask?.cancel()
    activeStreamTask = nil
  }

  private func clearGeneration(ifOwnedBy generationID: UUID) {
    guard activeGenerationID == generationID else {
      return
    }
    activeGenerationID = nil
    activeGenerationTask = nil
  }

  private static func makeRawResponse(
    prompt: PromptPackage,
    behavior: FakeLLMProviderBehavior,
    responseID: UUID,
    createdAt: Date
  ) throws -> RawLLMResponse {
    let context = try FakePromptContext(prompt: prompt)
    let outcome: [String: Any]

    switch behavior {
    case .success:
      let sample = lessonSample(for: context.sourceText)
      let analogy: Any = context.includeAnalogy ? sample.analogy as Any : NSNull()
      let example: Any = context.includeExample ? sample.example as Any : NSNull()
      let checkQuestion: Any = context.includeCheckQuestion
        ? sample.checkQuestion as Any
        : NSNull()
      outcome = [
        "type": "lesson",
        "lesson": [
          "title": sample.title,
          "plainExplanation": sample.plainExplanation,
          "keyPoints": sample.keyPoints,
          "glossary": sample.glossary.map {
            ["term": $0.term, "plainDefinition": $0.plainDefinition]
          },
          "analogy": analogy,
          "example": example,
          "checkQuestion": checkQuestion,
          "caveats": sample.caveats,
          "confidence": context.confidence,
        ],
      ]
    case .needsMoreContext:
      outcome = [
        "type": "needsMoreContext",
        "needsMoreContext": [
          "reason": "当前片段不足以形成可靠解释。",
          "suggestedAction": "等待更多稳定文本后重试。",
        ],
      ]
    case .blocked:
      outcome = [
        "type": "blocked",
        "blocked": [
          "reason": "unsupported",
          "message": "该输入被本地 Fake 行为配置阻止。",
        ],
      ]
    case .malformedJSON, .timeout, .unavailable, .response:
      throw LLMProviderError.invalidResponse
    }

    let dateFormatter = ISO8601DateFormatter()
    let object: [String: Any] = [
      "schemaVersion": TutorResponse.currentSchemaVersion,
      "id": responseID.uuidString,
      "requestID": context.requestID,
      "sessionID": context.sessionID,
      "sequence": context.sequence,
      "sourceChunkID": context.sourceChunkID,
      "createdAt": dateFormatter.string(from: createdAt),
      "outcome": outcome,
    ]

    guard JSONSerialization.isValidJSONObject(object) else {
      throw LLMProviderError.invalidResponse
    }
    let data: Data
    do {
      data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    } catch {
      throw LLMProviderError.invalidResponse
    }
    guard let content = String(data: data, encoding: .utf8) else {
      throw LLMProviderError.invalidResponse
    }

    return RawLLMResponse(
      content: content,
      finishReason: .stop,
      usage: .unavailable,
      providerMetadata: LLMProviderMetadata(
        providerIdentifier: metadata.providerIdentifier,
        modelIdentifier: metadata.modelIdentifier,
        requestIdentifier: context.requestID,
        values: [:]
      )
    )
  }

  private static func chunks(
    from content: String,
    maximumCharacterCount: Int
  ) -> [String] {
    guard !content.isEmpty else {
      return [""]
    }

    var chunks: [String] = []
    var start = content.startIndex
    while start < content.endIndex {
      let end = content.index(
        start,
        offsetBy: maximumCharacterCount,
        limitedBy: content.endIndex
      ) ?? content.endIndex
      chunks.append(String(content[start..<end]))
      start = end
    }
    return chunks
  }

  private static func lessonSample(for text: String) -> FakeLLMLessonSample {
    if text.range(of: "API", options: .caseInsensitive) != nil {
      return .api
    }
    if text.range(of: "HTTP", options: .caseInsensitive) != nil {
      return .http
    }
    if text.range(of: "JSON", options: .caseInsensitive) != nil {
      return .json
    }
    if text.range(of: "Error", options: .caseInsensitive) != nil {
      return .error
    }
    return .general
  }

  private static let metadata = LLMProviderMetadata(
    providerIdentifier: "fake.local",
    modelIdentifier: "fake-deterministic",
    requestIdentifier: nil,
    values: [:]
  )
}

private struct FakePromptContext {
  let requestID: String
  let sessionID: String
  let sequence: Int
  let sourceChunkID: String
  let sourceText: String
  let confidence: String
  let includeAnalogy: Bool
  let includeExample: Bool
  let includeCheckQuestion: Bool

  init(prompt: PromptPackage) throws {
    guard
      let userData = prompt.userContent.data(using: .utf8),
      let user = try? JSONSerialization.jsonObject(with: userData) as? [String: Any],
      let source = user["source"] as? [String: Any],
      let sourceText = source["text"] as? String,
      let confidence = source["diffConfidence"] as? String,
      let output = user["outputPreferences"] as? [String: Any],
      let includeAnalogy = output["includeAnalogy"] as? Bool,
      let includeExample = output["includeExample"] as? Bool,
      let includeCheckQuestion = output["includeCheckQuestion"] as? Bool,
      let schemaData = prompt.outputSchema.data(using: .utf8),
      let schema = try? JSONSerialization.jsonObject(with: schemaData) as? [String: Any],
      let properties = schema["properties"] as? [String: Any],
      let requestProperty = properties["requestID"] as? [String: Any],
      let requestID = requestProperty["const"] as? String,
      let sessionProperty = properties["sessionID"] as? [String: Any],
      let sessionID = sessionProperty["const"] as? String,
      let sequenceProperty = properties["sequence"] as? [String: Any],
      let sequence = sequenceProperty["const"] as? Int,
      let sourceChunkProperty = properties["sourceChunkID"] as? [String: Any],
      let sourceChunkID = sourceChunkProperty["const"] as? String
    else {
      throw LLMProviderError.invalidResponse
    }

    self.requestID = requestID
    self.sessionID = sessionID
    self.sequence = sequence
    self.sourceChunkID = sourceChunkID
    self.sourceText = sourceText
    self.confidence = confidence
    self.includeAnalogy = includeAnalogy
    self.includeExample = includeExample
    self.includeCheckQuestion = includeCheckQuestion
  }
}

private struct FakeLLMLessonSample: Sendable {
  let title: String
  let plainExplanation: String
  let keyPoints: [String]
  let glossary: [TutorTerm]
  let analogy: String
  let example: String
  let checkQuestion: String
  let caveats: [String]

  static let api = FakeLLMLessonSample(
    title: "API：程序之间的服务窗口",
    plainExplanation: "API 是两个程序商量好的沟通方式。一方按照约定发出请求，另一方按照约定返回结果。",
    keyPoints: [
      "API 定义可以请求什么。",
      "请求需要遵守固定格式。",
      "返回结果也有约定好的结构。",
    ],
    glossary: [
      TutorTerm(term: "API", plainDefinition: "程序对外提供功能的使用约定。"),
      TutorTerm(term: "请求", plainDefinition: "一个程序发给另一个程序的办事说明。"),
      TutorTerm(term: "响应", plainDefinition: "接收方处理后返回的结果。"),
    ],
    analogy: "它像餐厅菜单：菜单写明能点什么和怎么点，后厨再按订单出餐。",
    example: "天气应用调用天气 API，传入城市名称，得到温度和天气状态。",
    checkQuestion: "如果 API 像菜单，那么请求更像什么？",
    caveats: ["不同 API 的地址、参数和权限要求可能完全不同。"]
  )

  static let http = FakeLLMLessonSample(
    title: "HTTP：浏览器和服务器的传话规则",
    plainExplanation: "HTTP 是网络上传递请求和响应的一套规则。它说明消息怎么写，但不规定业务具体怎么处理。",
    keyPoints: [
      "客户端先发出 HTTP 请求。",
      "服务器处理后返回 HTTP 响应。",
      "状态码用数字概括处理结果。",
    ],
    glossary: [
      TutorTerm(term: "HTTP", plainDefinition: "用于传输网页和 API 消息的应用层协议。"),
      TutorTerm(term: "状态码", plainDefinition: "服务器用来表示成功或失败类型的三位数字。"),
    ],
    analogy: "它像快递单格式：大家按同一套格子填写，运输系统才知道怎么转交。",
    example: "打开网页时，浏览器发出 GET 请求；服务器成功时常返回 200。",
    checkQuestion: "HTTP 404 更可能表示传输失败，还是服务器找不到资源？",
    caveats: ["HTTP 本身不等于加密；HTTPS 才在 HTTP 之上增加加密保护。"]
  )

  static let json = FakeLLMLessonSample(
    title: "JSON：给数据贴上清楚标签",
    plainExplanation: "JSON 是一种用文本表示结构化数据的格式。它常用“名字对应值”的方式，让程序知道每项数据是什么。",
    keyPoints: [
      "对象使用大括号表示。",
      "数组使用方括号表示。",
      "字符串需要放在双引号中。",
    ],
    glossary: [
      TutorTerm(term: "JSON", plainDefinition: "易于人阅读，也易于程序解析的文本数据格式。"),
      TutorTerm(term: "键值对", plainDefinition: "一个名字和它对应数据的组合。"),
    ],
    analogy: "它像贴好标签的收纳盒：看到“姓名”标签，就知道旁边放的是姓名数据。",
    example: "{\"name\": \"小白\", \"age\": 3} 表示名字是小白、年龄是 3。",
    checkQuestion: "JSON 里的“name”是键，还是值？",
    caveats: ["JSON 不允许随意写注释，引号和逗号的位置也必须正确。"]
  )

  static let error = FakeLLMLessonSample(
    title: "Error：程序发出的问题线索",
    plainExplanation: "Error 表示程序没能按预期完成当前操作。错误信息不只是说“失败了”，它还应该帮助定位发生了什么。",
    keyPoints: [
      "先找到第一条明确的错误信息。",
      "再确认错误发生时正在做什么。",
      "修复后需要重新验证原来的操作。",
    ],
    glossary: [
      TutorTerm(term: "Error", plainDefinition: "一次操作无法正常完成时产生的失败信息。"),
      TutorTerm(term: "堆栈", plainDefinition: "记录代码经过哪些调用才到达错误位置的路线。"),
    ],
    analogy: "它像汽车仪表盘的故障灯：灯号提醒你有问题，具体故障码则帮助继续检查。",
    example: "读取不存在的文件时，错误信息可能指出文件路径找不到。",
    checkQuestion: "看到 Error 时，第一步应该是猜测，还是先阅读错误信息？",
    caveats: ["不要只删除或隐藏错误信息；需要解决导致错误的原因。"]
  )

  static let general = FakeLLMLessonSample(
    title: "本地教学样例",
    plainExplanation: "这是 FakeLLMProvider 通过 RawLLMResponse 返回的固定本地教学结果。",
    keyPoints: [
      "PromptPackage 已经通过 Provider 合同。",
      "原始 JSON 会解码并验证后再进入展示层。",
    ],
    glossary: [
      TutorTerm(term: "Fake Provider", plainDefinition: "只在本地 Debug 环境中使用的确定性模型替身。"),
    ],
    analogy: "它像消防演练：用固定剧本检查每个环节能否正常衔接。",
    example: "输入不包含预设关键词时，返回这个通用样例。",
    checkQuestion: "这个结果是网络模型生成的吗？",
    caveats: ["这不是模型生成结果，也不会访问网络。"]
  )
}
#endif
