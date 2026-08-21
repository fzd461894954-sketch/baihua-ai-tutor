#if DEBUG
import Foundation

struct TutorEvaluationCase: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let semanticChunk: SemanticChunk
  let expectedTeachingCharacteristics: [String]
  let expectations: TutorQualityExpectations
}

/// Synthetic, checked-in Debug fixtures only. No entry is derived from a real
/// user session, captured application text, or provider response.
enum TutorEvaluationDataset {
  static let cases: [TutorEvaluationCase] = [
    makeCase(
      id: "api",
      revision: 1,
      name: "API",
      text: "API 是一组让不同软件互相沟通的约定。调用方按约定发出请求，提供方返回响应。",
      characteristics: [
        "先说清 API 是软件之间的约定",
        "区分请求与响应",
        "使用日常生活类比和一个具体例子",
      ],
      anchors: ["API", "请求", "响应"],
      glossary: ["API", "请求", "响应"]
    ),
    makeCase(
      id: "http",
      revision: 2,
      name: "HTTP",
      text: "HTTP 是客户端和服务器之间传递请求与响应的规则。状态码用数字概括处理结果。",
      characteristics: [
        "说清客户端请求与服务器响应的方向",
        "解释状态码的用途，不自行补充具体码值",
        "类比应帮助区分传输规则和业务处理",
      ],
      anchors: ["HTTP", "客户端", "服务器", "状态码"],
      glossary: ["HTTP", "状态码"]
    ),
    makeCase(
      id: "json",
      revision: 3,
      name: "JSON",
      text: "JSON 是用文本表示结构化数据的格式。对象由键值对组成，数组表示有顺序的多个值。",
      characteristics: [
        "将 JSON 解释为数据格式，而不是编程语言",
        "区分对象、键值对与数组",
        "提供简短、可读的 JSON 例子",
      ],
      anchors: ["JSON", "键值对", "数组"],
      glossary: ["JSON", "键值对", "数组"]
    ),
    makeCase(
      id: "error",
      revision: 4,
      name: "Error",
      text: "Error 表示程序没有按预期完成当前操作。错误信息用来定位失败发生在哪里。",
      characteristics: [
        "区分错误现象与错误信息",
        "给出先读错误、再定位场景、最后重试验证的教学顺序",
        "不猜测源片段没有的具体根因",
      ],
      anchors: ["Error", "错误信息", "定位"],
      glossary: ["Error", "错误信息"]
    ),
    makeCase(
      id: "database-migration",
      revision: 5,
      name: "Database Migration",
      text: "Database Migration 是按版本改变数据库结构或数据的过程。迁移需要考虑执行顺序、回滚和已有数据。",
      characteristics: [
        "解释迁移为什么要按顺序执行",
        "说清结构变更、数据处理与回滚的关系",
        "不声称迁移已经成功或失败",
      ],
      anchors: ["Database Migration", "数据库", "迁移", "回滚"],
      glossary: ["Migration", "回滚", "数据库结构"]
    ),
    makeCase(
      id: "permission-error",
      revision: 6,
      name: "Permission Error",
      text: "Permission Error 表示当前用户或进程没有执行某个操作所需的权限。需要检查操作对象和授权范围。",
      characteristics: [
        "区分身份、操作对象与授权范围",
        "给出检查方向，不默认建议放宽全部权限",
        "不编造具体文件、账户或系统设置",
      ],
      anchors: ["Permission Error", "用户", "进程", "权限", "授权"],
      glossary: ["Permission", "授权", "进程"]
    ),
  ]

  static func caseWithID(_ id: String?) -> TutorEvaluationCase? {
    guard let id else {
      return nil
    }
    return cases.first(where: { $0.id == id })
  }

  private static func makeCase(
    id: String,
    revision: Int,
    name: String,
    text: String,
    characteristics: [String],
    anchors: [String],
    glossary: [String]
  ) -> TutorEvaluationCase {
    TutorEvaluationCase(
      id: id,
      name: name,
      semanticChunk: SemanticChunk(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", revision))!,
        sourceRevisionID: revision,
        text: text,
        confidence: .high,
        createdAt: Date(timeIntervalSince1970: TimeInterval(2_000 + revision)),
        flushReason: .sentenceComplete
      ),
      expectedTeachingCharacteristics: characteristics,
      expectations: TutorQualityExpectations(
        sourceAnchors: anchors,
        expectedGlossaryTerms: glossary,
        minimumKeyPointCount: 2,
        requiresGlossary: true,
        requiresAnalogy: true,
        requiresExample: true,
        maximumExplanationCharacters: 1_200
      )
    )
  }
}
#endif
