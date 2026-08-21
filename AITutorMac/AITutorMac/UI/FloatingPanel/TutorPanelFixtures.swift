#if DEBUG
import Foundation

enum TutorPanelDebugFixture: String, CaseIterable, Identifiable, Equatable, Sendable {
  case empty
  case loading
  case lesson
  case needsMoreContext
  case blocked
  case error
  case longLesson

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .empty:
      return "Empty"
    case .loading:
      return "Loading"
    case .lesson:
      return "API Lesson"
    case .needsMoreContext:
      return "Needs More Context"
    case .blocked:
      return "Blocked"
    case .error:
      return "Error"
    case .longLesson:
      return "Long Lesson"
    }
  }
}

enum TutorPanelPresentationFixtures {
  static let apiLesson = TutorPresentationModel(
    responseMetadata: metadata(1),
    outcome: .lesson,
    lessonMetadata: TutorPresentationLessonMetadata(
      confidence: .high,
      keyPointCount: 3,
      termCount: 3,
      caveatCount: 1,
      hasAnalogy: true,
      hasExample: true,
      hasCheckQuestion: true
    ),
    title: "API：软件之间的服务窗口",
    plainExplanation: "API 是两个软件商量好的沟通方式。一方按照约定发出请求，另一方再按约定返回结果。",
    keyPoints: [
      "API 会说明可以请求什么。",
      "请求需要遵守约定好的格式。",
      "返回结果也有稳定的结构。",
    ],
    terms: [
      TutorPresentationTerm(term: "API", plainDefinition: "软件对外提供功能时的使用约定。"),
      TutorPresentationTerm(term: "请求", plainDefinition: "一个软件发给另一个软件的办事说明。"),
      TutorPresentationTerm(term: "响应", plainDefinition: "接收方处理后返回的结果。"),
    ],
    analogy: "它像餐厅菜单：菜单写明能点什么和怎么点，后厨再按订单出餐。",
    example: "天气应用请求某个城市的天气，天气服务返回温度和天气状态。",
    checkQuestion: "如果 API 像菜单，那么“请求”更像什么？",
    caveats: ["不同 API 的地址、参数和权限要求可能完全不同。"],
    suggestedAction: nil,
    blockReason: nil,
    didTruncateContent: false
  )

  static let minimalLesson = TutorPresentationModel(
    responseMetadata: metadata(2),
    outcome: .lesson,
    lessonMetadata: TutorPresentationLessonMetadata(
      confidence: .medium,
      keyPointCount: 0,
      termCount: 0,
      caveatCount: 0,
      hasAnalogy: false,
      hasExample: false,
      hasCheckQuestion: false
    ),
    title: "白话解释",
    plainExplanation: "这是一段不需要额外教学模块的简短解释。",
    keyPoints: [],
    terms: [],
    analogy: nil,
    example: nil,
    checkQuestion: nil,
    caveats: [],
    suggestedAction: nil,
    blockReason: nil,
    didTruncateContent: false
  )

  static let needsMoreContext = TutorPresentationModel(
    responseMetadata: metadata(3),
    outcome: .needsMoreContext,
    lessonMetadata: nil,
    title: "需要更多上下文",
    plainExplanation: "当前内容只是一个没有结束的片段，现在解释容易造成误解。",
    keyPoints: [],
    terms: [],
    analogy: nil,
    example: nil,
    checkQuestion: nil,
    caveats: [],
    suggestedAction: "等待内容完整后，再重新解释当前内容。",
    blockReason: nil,
    didTruncateContent: false
  )

  static let blocked = TutorPresentationModel(
    responseMetadata: metadata(4),
    outcome: .blocked,
    lessonMetadata: nil,
    title: "内容未展示",
    plainExplanation: "为了保护你的隐私，这段内容暂时不会用于生成解释。",
    keyPoints: [],
    terms: [],
    analogy: nil,
    example: nil,
    checkQuestion: nil,
    caveats: [],
    suggestedAction: nil,
    blockReason: .privacyRisk,
    didTruncateContent: false
  )

  static let longLesson: TutorPresentationModel = {
    let paragraph = "这一段用来检查较长教学内容在可调整大小的面板中是否保持清晰换行和稳定滚动。"
    return TutorPresentationModel(
      responseMetadata: metadata(5),
      outcome: .lesson,
      lessonMetadata: TutorPresentationLessonMetadata(
        confidence: .medium,
        keyPointCount: 5,
        termCount: 8,
        caveatCount: 3,
        hasAnalogy: true,
        hasExample: true,
        hasCheckQuestion: true
      ),
      title: "一篇需要滚动阅读的长教学内容",
      plainExplanation: String(String(repeating: paragraph, count: 30).prefix(1_150)),
      keyPoints: (1...5).map { "关键点 \($0)：保持每一部分都是短小、清晰且能够独立阅读的。" },
      terms: (1...8).map {
        TutorPresentationTerm(
          term: "术语 \($0)",
          plainDefinition: "这是第 \($0) 个用于检查折叠术语表的简明定义。"
        )
      },
      analogy: "长内容像一本有目录的小册子，需要用清晰的层级帮助阅读。",
      example: "当解释包含正文、关键点、类比、例子和术语表时，面板应该滚动而不是扩大窗口。",
      checkQuestion: "为什么长内容需要分层，而不是全部挤在一段里？",
      caveats: [
        "信息层级不应该依赖动画。",
        "窗口缩小时应保留合理换行。",
        "辅助内容不应挤压白话解释。",
      ],
      suggestedAction: nil,
      blockReason: nil,
      didTruncateContent: true
    )
  }()

  private static func metadata(_ sequence: Int) -> TutorPresentationResponseMetadata {
    TutorPresentationResponseMetadata(
      responseID: uuid(100 + sequence),
      requestID: uuid(200 + sequence),
      sessionID: debugSessionID,
      sequence: sequence,
      sourceChunkID: uuid(300 + sequence),
      createdAt: Date(timeIntervalSince1970: TimeInterval(4_000 + sequence))
    )
  }

  private static let debugSessionID = uuid(1)

  private static func uuid(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
  }
}

@MainActor
final class TutorPanelDebugFixtureController {
  private let contentStore: TutorPanelContentStore
  private var presentationTask: Task<Void, Never>?

  init(contentStore: TutorPanelContentStore) {
    self.contentStore = contentStore
  }

  deinit {
    presentationTask?.cancel()
  }

  func handle(_ intent: TutorPanelActionIntent) {
    switch intent {
    case .explainCurrentContent, .retryCurrentContent:
      showLessonAfterLoading()
    case .dismissCurrentPresentation:
      presentationTask?.cancel()
      presentationTask = nil
      contentStore.clear()
    case .openModelSettings:
      break
    case .playTutorVoice, .stopTutorVoice:
      break
    case let .showDebugFixture(fixture):
      presentationTask?.cancel()
      presentationTask = nil
      show(fixture)
    }
  }

  private func showLessonAfterLoading() {
    presentationTask?.cancel()
    contentStore.setLoading()
    presentationTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: 450_000_000)
      } catch {
        return
      }
      guard !Task.isCancelled else {
        return
      }
      self?.contentStore.present(TutorPanelPresentationFixtures.apiLesson)
      self?.presentationTask = nil
    }
  }

  private func show(_ fixture: TutorPanelDebugFixture) {
    switch fixture {
    case .empty:
      contentStore.clear()
    case .loading:
      contentStore.setLoading()
    case .lesson:
      contentStore.present(TutorPanelPresentationFixtures.apiLesson)
    case .needsMoreContext:
      contentStore.present(TutorPanelPresentationFixtures.needsMoreContext)
    case .blocked:
      contentStore.present(TutorPanelPresentationFixtures.blocked)
    case .error:
      contentStore.presentError()
    case .longLesson:
      contentStore.present(TutorPanelPresentationFixtures.longLesson)
    }
  }
}
#endif
