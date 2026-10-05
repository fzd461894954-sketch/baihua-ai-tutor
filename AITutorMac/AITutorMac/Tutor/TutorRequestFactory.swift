import Foundation

struct TutorRequestFactory: Sendable {
  static let defaultPolicyVersion = "tutor-policy-v1"

  let maximumSourceCharacterCount: Int

  private let now: @Sendable () -> Date
  private let makeID: @Sendable () -> UUID

  init(
    maximumSourceCharacterCount: Int = TutorRequest.defaultMaximumSourceCharacterCount,
    now: @escaping @Sendable () -> Date = { Date() },
    makeID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.maximumSourceCharacterCount = min(
      TutorRequest.defaultMaximumSourceCharacterCount,
      max(1, maximumSourceCharacterCount)
    )
    self.now = now
    self.makeID = makeID
  }

  func make(
    from chunk: SemanticChunk,
    sessionID: UUID,
    sequence: Int,
    learner: LearnerProfileSnapshot,
    task: TutorTask = .explainInPlainLanguage,
    trigger: TutorTrigger = .automatic,
    learnerQuestion: String? = nil,
    output: TutorOutputPreferences? = nil,
    policyVersion: String = TutorRequestFactory.defaultPolicyVersion
  ) throws -> TutorRequest {
    guard sequence > 0 else {
      throw TutorEngineError.invalidRequest(.invalidSequence(sequence))
    }
    guard chunk.sourceRevisionID >= 0 else {
      throw TutorEngineError.invalidRequest(
        .invalidSourceRevisionID(chunk.sourceRevisionID)
      )
    }
    guard Self.hasVisibleText(chunk.text) else {
      throw TutorEngineError.invalidRequest(.emptySourceText)
    }
    guard chunk.text.count <= maximumSourceCharacterCount else {
      throw TutorEngineError.invalidRequest(
        .sourceTextTooLong(
          maximum: maximumSourceCharacterCount,
          actual: chunk.text.count
        )
      )
    }
    guard Self.hasVisibleText(learner.preferredLanguage) else {
      throw TutorEngineError.invalidRequest(.emptyLearnerLanguage)
    }

    let effectiveOutput = output ?? .default(language: learner.preferredLanguage)
    let effectiveQuestion = learnerQuestion?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(TutorRequest.defaultMaximumLearnerQuestionCharacterCount)
    let boundedQuestion = effectiveQuestion.map(String.init).flatMap {
      Self.hasVisibleText($0) ? $0 : nil
    }
    guard Self.hasVisibleText(effectiveOutput.language) else {
      throw TutorEngineError.invalidRequest(.emptyOutputLanguage)
    }
    guard Self.hasVisibleText(policyVersion) else {
      throw TutorEngineError.invalidRequest(.emptyPolicyVersion)
    }

    return TutorRequest(
      schemaVersion: TutorRequest.currentSchemaVersion,
      id: makeID(),
      sessionID: sessionID,
      sequence: sequence,
      createdAt: now(),
      task: task,
      trigger: trigger,
      learnerQuestion: boundedQuestion,
      source: TutorSourceSnapshot(
        chunkID: chunk.id,
        sourceRevisionID: chunk.sourceRevisionID,
        text: chunk.text,
        diffConfidence: chunk.confidence,
        flushReason: chunk.flushReason,
        chunkCreatedAt: chunk.createdAt,
        contentLength: chunk.contentLength
      ),
      learner: learner,
      output: effectiveOutput,
      policyVersion: policyVersion
    )
  }

  private static func hasVisibleText(_ value: String) -> Bool {
    value.contains(where: { !$0.isWhitespace })
  }
}
