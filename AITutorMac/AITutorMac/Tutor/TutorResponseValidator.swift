import Foundation

enum TutorLessonOptionalField: String, Equatable, Sendable {
  case title
  case analogy
  case example
  case checkQuestion
}

enum TutorResponseValidationIssue: Equatable, Sendable {
  case unsupportedSchemaVersion(expected: Int, actual: Int)
  case requestIDMismatch
  case sessionIDMismatch
  case sequenceMismatch
  case sourceChunkIDMismatch
  case emptyPlainExplanation
  case plainExplanationTooLong(maximum: Int, actual: Int)
  case tooManyKeyPoints(maximum: Int, actual: Int)
  case emptyKeyPoint(index: Int)
  case keyPointTooLong(index: Int, maximum: Int, actual: Int)
  case tooManyGlossaryTerms(maximum: Int, actual: Int)
  case emptyGlossaryTerm(index: Int)
  case emptyGlossaryDefinition(index: Int)
  case glossaryDefinitionTooLong(index: Int, maximum: Int, actual: Int)
  case tooManyCaveats(maximum: Int, actual: Int)
  case emptyCaveat(index: Int)
  case caveatTooLong(index: Int, maximum: Int, actual: Int)
  case emptyOptionalLessonField(TutorLessonOptionalField)
  case optionalLessonFieldTooLong(
    field: TutorLessonOptionalField,
    maximum: Int,
    actual: Int
  )
  case emptyNeedsMoreContextReason
  case needsMoreContextReasonTooLong(maximum: Int, actual: Int)
  case emptySuggestedAction
  case suggestedActionTooLong(maximum: Int, actual: Int)
  case emptyBlockMessage
  case blockMessageTooLong(maximum: Int, actual: Int)
}

struct TutorResponseValidationLimits: Equatable, Sendable {
  static let `default` = TutorResponseValidationLimits(
    maximumTitleCharacters: 80,
    maximumExplanationCharacters: 2_000,
    maximumKeyPoints: 5,
    maximumGlossaryTerms: 8,
    maximumCaveats: 3,
    maximumListItemCharacters: 500,
    maximumOptionalFieldCharacters: 1_000,
    maximumStatusMessageCharacters: 500
  )

  let maximumTitleCharacters: Int
  let maximumExplanationCharacters: Int
  let maximumKeyPoints: Int
  let maximumGlossaryTerms: Int
  let maximumCaveats: Int
  let maximumListItemCharacters: Int
  let maximumOptionalFieldCharacters: Int
  let maximumStatusMessageCharacters: Int

  init(
    maximumTitleCharacters: Int,
    maximumExplanationCharacters: Int,
    maximumKeyPoints: Int,
    maximumGlossaryTerms: Int,
    maximumCaveats: Int,
    maximumListItemCharacters: Int,
    maximumOptionalFieldCharacters: Int,
    maximumStatusMessageCharacters: Int
  ) {
    self.maximumTitleCharacters = max(1, maximumTitleCharacters)
    self.maximumExplanationCharacters = max(1, maximumExplanationCharacters)
    self.maximumKeyPoints = max(0, maximumKeyPoints)
    self.maximumGlossaryTerms = max(0, maximumGlossaryTerms)
    self.maximumCaveats = max(0, maximumCaveats)
    self.maximumListItemCharacters = max(1, maximumListItemCharacters)
    self.maximumOptionalFieldCharacters = max(1, maximumOptionalFieldCharacters)
    self.maximumStatusMessageCharacters = max(1, maximumStatusMessageCharacters)
  }
}

struct TutorResponseValidator: Sendable {
  let limits: TutorResponseValidationLimits

  init(limits: TutorResponseValidationLimits = .default) {
    self.limits = limits
  }

  @discardableResult
  func validate(
    _ response: TutorResponse,
    for request: TutorRequest
  ) throws -> TutorResponse {
    var issues: [TutorResponseValidationIssue] = []

    if response.schemaVersion != TutorResponse.currentSchemaVersion {
      issues.append(
        .unsupportedSchemaVersion(
          expected: TutorResponse.currentSchemaVersion,
          actual: response.schemaVersion
        )
      )
    }
    if response.requestID != request.id {
      issues.append(.requestIDMismatch)
    }
    if response.sessionID != request.sessionID {
      issues.append(.sessionIDMismatch)
    }
    if response.sequence != request.sequence {
      issues.append(.sequenceMismatch)
    }
    if response.sourceChunkID != request.source.chunkID {
      issues.append(.sourceChunkIDMismatch)
    }

    switch response.outcome {
    case let .lesson(lesson):
      validate(lesson, issues: &issues)
    case let .needsMoreContext(value):
      validate(value, issues: &issues)
    case let .blocked(value):
      validate(value, issues: &issues)
    }

    guard issues.isEmpty else {
      throw TutorEngineError.invalidResponse(issues)
    }
    return response
  }

  private func validate(
    _ lesson: TutorLesson,
    issues: inout [TutorResponseValidationIssue]
  ) {
    if !Self.hasVisibleText(lesson.plainExplanation) {
      issues.append(.emptyPlainExplanation)
    } else if lesson.plainExplanation.count > limits.maximumExplanationCharacters {
      issues.append(
        .plainExplanationTooLong(
          maximum: limits.maximumExplanationCharacters,
          actual: lesson.plainExplanation.count
        )
      )
    }

    validateOptional(
      lesson.title,
      field: .title,
      maximum: limits.maximumTitleCharacters,
      issues: &issues
    )
    validateOptional(
      lesson.analogy,
      field: .analogy,
      maximum: limits.maximumOptionalFieldCharacters,
      issues: &issues
    )
    validateOptional(
      lesson.example,
      field: .example,
      maximum: limits.maximumOptionalFieldCharacters,
      issues: &issues
    )
    validateOptional(
      lesson.checkQuestion,
      field: .checkQuestion,
      maximum: limits.maximumOptionalFieldCharacters,
      issues: &issues
    )

    if lesson.keyPoints.count > limits.maximumKeyPoints {
      issues.append(
        .tooManyKeyPoints(
          maximum: limits.maximumKeyPoints,
          actual: lesson.keyPoints.count
        )
      )
    }
    for (index, keyPoint) in lesson.keyPoints.enumerated() {
      if !Self.hasVisibleText(keyPoint) {
        issues.append(.emptyKeyPoint(index: index))
      } else if keyPoint.count > limits.maximumListItemCharacters {
        issues.append(
          .keyPointTooLong(
            index: index,
            maximum: limits.maximumListItemCharacters,
            actual: keyPoint.count
          )
        )
      }
    }

    if lesson.glossary.count > limits.maximumGlossaryTerms {
      issues.append(
        .tooManyGlossaryTerms(
          maximum: limits.maximumGlossaryTerms,
          actual: lesson.glossary.count
        )
      )
    }
    for (index, item) in lesson.glossary.enumerated() {
      if !Self.hasVisibleText(item.term) {
        issues.append(.emptyGlossaryTerm(index: index))
      }
      if !Self.hasVisibleText(item.plainDefinition) {
        issues.append(.emptyGlossaryDefinition(index: index))
      } else if item.plainDefinition.count > limits.maximumListItemCharacters {
        issues.append(
          .glossaryDefinitionTooLong(
            index: index,
            maximum: limits.maximumListItemCharacters,
            actual: item.plainDefinition.count
          )
        )
      }
    }

    if lesson.caveats.count > limits.maximumCaveats {
      issues.append(
        .tooManyCaveats(
          maximum: limits.maximumCaveats,
          actual: lesson.caveats.count
        )
      )
    }
    for (index, caveat) in lesson.caveats.enumerated() {
      if !Self.hasVisibleText(caveat) {
        issues.append(.emptyCaveat(index: index))
      } else if caveat.count > limits.maximumListItemCharacters {
        issues.append(
          .caveatTooLong(
            index: index,
            maximum: limits.maximumListItemCharacters,
            actual: caveat.count
          )
        )
      }
    }
  }

  private func validate(
    _ value: TutorNeedsMoreContext,
    issues: inout [TutorResponseValidationIssue]
  ) {
    if !Self.hasVisibleText(value.reason) {
      issues.append(.emptyNeedsMoreContextReason)
    } else if value.reason.count > limits.maximumStatusMessageCharacters {
      issues.append(
        .needsMoreContextReasonTooLong(
          maximum: limits.maximumStatusMessageCharacters,
          actual: value.reason.count
        )
      )
    }

    guard let action = value.suggestedAction else {
      return
    }
    if !Self.hasVisibleText(action) {
      issues.append(.emptySuggestedAction)
    } else if action.count > limits.maximumStatusMessageCharacters {
      issues.append(
        .suggestedActionTooLong(
          maximum: limits.maximumStatusMessageCharacters,
          actual: action.count
        )
      )
    }
  }

  private func validate(
    _ value: TutorBlock,
    issues: inout [TutorResponseValidationIssue]
  ) {
    if !Self.hasVisibleText(value.message) {
      issues.append(.emptyBlockMessage)
    } else if value.message.count > limits.maximumStatusMessageCharacters {
      issues.append(
        .blockMessageTooLong(
          maximum: limits.maximumStatusMessageCharacters,
          actual: value.message.count
        )
      )
    }
  }

  private func validateOptional(
    _ value: String?,
    field: TutorLessonOptionalField,
    maximum: Int,
    issues: inout [TutorResponseValidationIssue]
  ) {
    guard let value else {
      return
    }
    if !Self.hasVisibleText(value) {
      issues.append(.emptyOptionalLessonField(field))
    } else if value.count > maximum {
      issues.append(
        .optionalLessonFieldTooLong(
          field: field,
          maximum: maximum,
          actual: value.count
        )
      )
    }
  }

  private static func hasVisibleText(_ value: String) -> Bool {
    value.contains(where: { !$0.isWhitespace })
  }
}
