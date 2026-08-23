import XCTest

@testable import AITutorMac

final class TutorQualityEvaluatorTests: XCTestCase {
  private let evaluator = TutorQualityEvaluator()

  func testSameChunkMultipleRunsProduceIndependentDeterministicReports() {
    let request = makeRequest()
    let first = evaluator.evaluate(
      makeResponse(for: request, responseID: uuid(901), lesson: validLesson()),
      for: request,
      expectations: expectations
    )
    let second = evaluator.evaluate(
      makeResponse(for: request, responseID: uuid(902), lesson: validLesson()),
      for: request,
      expectations: expectations
    )

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.rating, .passed, "\(first.signals)")
  }

  func testEmptyResponseFailsEverySignalWithoutCrashing() {
    let report = evaluator.evaluate(
      nil,
      for: makeRequest(),
      expectations: expectations
    )

    XCTAssertEqual(report.rating, .failed)
    XCTAssertEqual(report.signals.count, TutorQualitySignalID.allCases.count)
    XCTAssertTrue(report.signals.allSatisfy { $0.status == .failed })
    XCTAssertEqual(report.explanationCharacterCount, 0)
  }

  func testMalformedLessonFailsBodyStructureAndGlossary() throws {
    let request = makeRequest()
    let lesson = TutorLesson(
      title: " ",
      plainExplanation: "\n",
      keyPoints: ["", "可见关键点"],
      glossary: [TutorTerm(term: "API", plainDefinition: " ")],
      analogy: " ",
      example: nil,
      checkQuestion: nil,
      caveats: [],
      confidence: .low
    )

    let report = evaluator.evaluate(
      makeResponse(for: request, lesson: lesson),
      for: request,
      expectations: expectations
    )

    XCTAssertEqual(try status(.plainExplanation, in: report), .failed)
    XCTAssertEqual(try status(.teachingStructure, in: report), .failed)
    XCTAssertEqual(try status(.glossary, in: report), .failed)
  }

  func testTooLongResponseFailsLengthSignal() throws {
    let request = makeRequest()
    let lesson = replacing(
      validLesson(),
      plainExplanation: String(repeating: "API解释", count: 260)
    )

    let report = evaluator.evaluate(
      makeResponse(for: request, lesson: lesson),
      for: request,
      expectations: expectations
    )

    XCTAssertGreaterThan(report.explanationCharacterCount, 1_200)
    XCTAssertEqual(try status(.responseLength, in: report), .failed)
  }

  func testHallucinationMarkerFailsUnsupportedFactsSignal() throws {
    let request = makeRequest()
    let lesson = replacing(
      validLesson(),
      plainExplanation: "API 是软件之间的沟通约定。[HALLUCINATION] 这是未提供的断言。"
    )

    let report = evaluator.evaluate(
      makeResponse(for: request, lesson: lesson),
      for: request,
      expectations: expectations
    )

    XCTAssertEqual(try status(.unsupportedFacts, in: report), .failed)
  }

  func testOffTopicLessonFailsSourceAlignmentSignal() throws {
    let request = makeRequest()
    let lesson = TutorLesson(
      title: "天气说明",
      plainExplanation: "今天的天气可能会变化，出门前可以查看当地预报并准备合适的衣物。",
      keyPoints: ["出门前看预报。", "根据气温选衣物。"],
      glossary: [TutorTerm(term: "预报", plainDefinition: "对天气变化的预测。")],
      analogy: "像出门前看地图。",
      example: "下雨时带伞。",
      checkQuestion: nil,
      caveats: [],
      confidence: .low
    )

    let report = evaluator.evaluate(
      makeResponse(for: request, lesson: lesson),
      for: request,
      expectations: expectations
    )

    XCTAssertEqual(try status(.sourceAlignment, in: report), .failed)
  }

  func testHollowSummaryFailsSubstantiveSignal() throws {
    let request = makeRequest()
    let lesson = replacing(
      validLesson(),
      plainExplanation: "总的来说，这很重要。"
    )

    let report = evaluator.evaluate(
      makeResponse(for: request, lesson: lesson),
      for: request,
      expectations: expectations
    )

    XCTAssertEqual(try status(.substantiveSummary, in: report), .failed)
  }

  func testMissingGlossaryFailsWhenCaseRequiresGlossary() throws {
    let request = makeRequest()
    let source = validLesson()
    let lesson = TutorLesson(
      title: source.title,
      plainExplanation: source.plainExplanation,
      keyPoints: source.keyPoints,
      glossary: [],
      analogy: source.analogy,
      example: source.example,
      checkQuestion: source.checkQuestion,
      caveats: source.caveats,
      confidence: source.confidence
    )

    let report = evaluator.evaluate(
      makeResponse(for: request, lesson: lesson),
      for: request,
      expectations: expectations
    )

    XCTAssertEqual(try status(.glossary, in: report), .failed)
  }

  func testMissingAnalogyFailsWhenRequested() throws {
    let request = makeRequest(includeAnalogy: true)
    let source = validLesson()
    let lesson = TutorLesson(
      title: source.title,
      plainExplanation: source.plainExplanation,
      keyPoints: source.keyPoints,
      glossary: source.glossary,
      analogy: nil,
      example: source.example,
      checkQuestion: source.checkQuestion,
      caveats: source.caveats,
      confidence: source.confidence
    )

    let report = evaluator.evaluate(
      makeResponse(for: request, lesson: lesson),
      for: request,
      expectations: expectations
    )

    XCTAssertEqual(try status(.analogy, in: report), .failed)
  }

  func testValidLessonPassesAllQualitySignals() {
    let request = makeRequest()
    let report = evaluator.evaluate(
      makeResponse(for: request, lesson: validLesson()),
      for: request,
      expectations: expectations
    )

    XCTAssertEqual(report.rating, .passed, "\(report.signals)")
    XCTAssertTrue(
      report.signals.allSatisfy { $0.status == .passed },
      "\(report.signals)"
    )
    XCTAssertTrue(report.hasAnalogy)
    XCTAssertEqual(report.glossaryTermCount, 2)
  }

#if DEBUG
  func testDebugDatasetContainsEveryRequiredSyntheticCase() {
    XCTAssertEqual(
      Set(TutorEvaluationDataset.cases.map(\.name)),
      Set(["API", "HTTP", "JSON", "Error", "Database Migration", "Permission Error"])
    )
    XCTAssertTrue(
      TutorEvaluationDataset.cases.allSatisfy {
        !$0.semanticChunk.text.isEmpty
          && !$0.expectedTeachingCharacteristics.isEmpty
          && $0.semanticChunk.confidence == .high
      }
    )
  }
#endif

  private var expectations: TutorQualityExpectations {
    TutorQualityExpectations(
      sourceAnchors: ["API", "请求", "响应"],
      expectedGlossaryTerms: ["API", "请求"],
      minimumKeyPointCount: 2,
      requiresGlossary: true,
      requiresAnalogy: true,
      requiresExample: true,
      maximumExplanationCharacters: 1_200
    )
  }

  private func makeRequest(includeAnalogy: Bool = true) -> TutorRequest {
    TutorRequest(
      schemaVersion: TutorRequest.currentSchemaVersion,
      id: uuid(701),
      sessionID: uuid(702),
      sequence: 1,
      createdAt: Date(timeIntervalSince1970: 2_000),
      task: .explainInPlainLanguage,
      trigger: .userInitiated,
      learnerQuestion: nil,
      source: TutorSourceSnapshot(
        chunkID: uuid(703),
        sourceRevisionID: 1,
        text: "API 是软件之间的沟通约定：调用方发出请求，提供方返回响应。",
        diffConfidence: .high,
        flushReason: .sentenceComplete,
        chunkCreatedAt: Date(timeIntervalSince1970: 1_900)
      ),
      learner: .productDefault(at: Date(timeIntervalSince1970: 1_800)),
      output: TutorOutputPreferences(
        language: "zh-Hans",
        detailLevel: .balanced,
        includeAnalogy: includeAnalogy,
        includeExample: true,
        includeCheckQuestion: false
      ),
      policyVersion: TutorRequestFactory.defaultPolicyVersion
    )
  }

  private func makeResponse(
    for request: TutorRequest,
    responseID: UUID? = nil,
    lesson: TutorLesson
  ) -> TutorResponse {
    TutorResponse(
      schemaVersion: TutorResponse.currentSchemaVersion,
      id: responseID ?? uuid(801),
      requestID: request.id,
      sessionID: request.sessionID,
      sequence: request.sequence,
      sourceChunkID: request.source.chunkID,
      createdAt: Date(timeIntervalSince1970: 2_100),
      outcome: .lesson(lesson)
    )
  }

  private func validLesson() -> TutorLesson {
    TutorLesson(
      title: "API 的白话解释",
      plainExplanation: "API 是两个软件商量好的沟通方式。调用方按照约定发出请求，提供方再返回响应。",
      keyPoints: [
        "请求说明调用方想做什么。",
        "响应返回提供方的处理结果。",
      ],
      glossary: [
        TutorTerm(term: "API", plainDefinition: "软件对外提供功能时共同遵守的约定。"),
        TutorTerm(term: "请求", plainDefinition: "调用方发出的办事说明。"),
      ],
      analogy: "它像餐厅菜单：顾客按菜单点餐，厨房按约定出餐。",
      example: "天气应用发出查询请求，天气服务返回结构化响应。",
      checkQuestion: nil,
      caveats: ["不同 API 的请求格式可能不同。"],
      confidence: .high
    )
  }

  private func replacing(
    _ lesson: TutorLesson,
    plainExplanation: String
  ) -> TutorLesson {
    TutorLesson(
      title: lesson.title,
      plainExplanation: plainExplanation,
      keyPoints: lesson.keyPoints,
      glossary: lesson.glossary,
      analogy: lesson.analogy,
      example: lesson.example,
      checkQuestion: lesson.checkQuestion,
      caveats: lesson.caveats,
      confidence: lesson.confidence
    )
  }

  private func status(
    _ id: TutorQualitySignalID,
    in report: TutorQualityReport
  ) throws -> TutorQualitySignalStatus {
    try XCTUnwrap(report.signal(for: id)).status
  }

  private func uuid(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
  }
}
