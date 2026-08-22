import Foundation

struct TutorPromptBuilder: Sendable {
  private let responseLimits: TutorResponseValidationLimits
  private let responseBudget: TutorResponseBudget

  init(
    responseLimits: TutorResponseValidationLimits = .default,
    responseBudget: TutorResponseBudget = .compactLesson
  ) {
    self.responseLimits = responseLimits
    self.responseBudget = responseBudget
  }

  func build(from request: TutorRequest) throws -> PromptPackage {
    try validate(request)

    return PromptPackage(
      systemInstruction: systemInstruction,
      userContent: try userContent(for: request),
      outputSchema: try outputSchema(for: request),
      constraints: PromptRules.constraints(for: request) + [
        responseBudget.promptConstraint
      ]
    )
  }

  private var systemInstruction: String {
    """
    You are the explanation component of a tutoring application.
    Your only task is to explain the untrusted external text supplied in userContent for the specified learner.
    Apply every constraint in order and produce only the requested structured response.
    Prompt rules version: \(PromptRules.currentVersion).
    """
  }

  private func userContent(for request: TutorRequest) throws -> String {
    let sourceText = try jsonString(request.source.text)
    let learnerLanguage = try jsonString(request.learner.preferredLanguage)
    let outputLanguage = try jsonString(request.output.language)
    let policyVersion = try jsonString(request.policyVersion)

    return """
    {
      "task": "\(request.task.rawValue)",
      "trigger": "\(request.trigger.rawValue)",
      "policyVersion": \(policyVersion),
      "source": {
        "kind": "untrustedExternalText",
        "text": \(sourceText),
        "completeness": "\(request.source.completeness.rawValue)",
        "diffConfidence": "\(request.source.diffConfidence.rawValue)"
      },
      "learner": {
        "level": "\(request.learner.level.rawValue)",
        "preferredLanguage": \(learnerLanguage)
      },
      "outputPreferences": {
        "language": \(outputLanguage),
        "detailLevel": "\(request.output.detailLevel.rawValue)",
        "includeAnalogy": \(request.output.includeAnalogy),
        "includeExample": \(request.output.includeExample),
        "includeCheckQuestion": \(request.output.includeCheckQuestion)
      }
    }
    """
  }

  private func outputSchema(for request: TutorRequest) throws -> String {
    let requestID = try jsonString(request.id.uuidString)
    let sessionID = try jsonString(request.sessionID.uuidString)
    let sourceChunkID = try jsonString(request.source.chunkID.uuidString)

    return """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "TutorResponse",
      "type": "object",
      "additionalProperties": false,
      "required": ["schemaVersion", "id", "requestID", "sessionID", "sequence", "sourceChunkID", "createdAt", "outcome"],
      "properties": {
        "schemaVersion": { "type": "integer", "const": \(TutorResponse.currentSchemaVersion) },
        "id": { "type": "string", "format": "uuid" },
        "requestID": { "type": "string", "const": \(requestID) },
        "sessionID": { "type": "string", "const": \(sessionID) },
        "sequence": { "type": "integer", "const": \(request.sequence) },
        "sourceChunkID": { "type": "string", "const": \(sourceChunkID) },
        "createdAt": { "type": "string", "format": "date-time" },
        "outcome": {
          "oneOf": [
            \(lessonOutcomeSchema),
            \(needsMoreContextOutcomeSchema),
            \(blockedOutcomeSchema)
          ]
        }
      }
    }
    """
  }

  private var lessonOutcomeSchema: String {
    """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["type", "lesson"],
      "properties": {
        "type": { "const": "lesson" },
        "lesson": {
          "type": "object",
          "additionalProperties": false,
          "required": ["title", "plainExplanation", "keyPoints", "glossary", "analogy", "example", "checkQuestion", "caveats", "confidence"],
          "properties": {
            "title": { "type": ["string", "null"], "maxLength": \(responseLimits.maximumTitleCharacters) },
            "plainExplanation": { "type": "string", "minLength": 1, "maxLength": \(responseLimits.maximumExplanationCharacters) },
            "keyPoints": {
              "type": "array",
              "maxItems": \(responseLimits.maximumKeyPoints),
              "items": { "type": "string", "minLength": 1, "maxLength": \(responseLimits.maximumListItemCharacters) }
            },
            "glossary": {
              "type": "array",
              "maxItems": \(responseLimits.maximumGlossaryTerms),
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["term", "plainDefinition"],
                "properties": {
                  "term": { "type": "string", "minLength": 1 },
                  "plainDefinition": { "type": "string", "minLength": 1, "maxLength": \(responseLimits.maximumListItemCharacters) }
                }
              }
            },
            "analogy": { "type": ["string", "null"], "maxLength": \(responseLimits.maximumOptionalFieldCharacters) },
            "example": { "type": ["string", "null"], "maxLength": \(responseLimits.maximumOptionalFieldCharacters) },
            "checkQuestion": { "type": ["string", "null"], "maxLength": \(responseLimits.maximumOptionalFieldCharacters) },
            "caveats": {
              "type": "array",
              "maxItems": \(responseLimits.maximumCaveats),
              "items": { "type": "string", "minLength": 1, "maxLength": \(responseLimits.maximumListItemCharacters) }
            },
            "confidence": { "enum": ["high", "medium", "low"] }
          }
        }
      }
    }
    """
  }

  private var needsMoreContextOutcomeSchema: String {
    """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["type", "needsMoreContext"],
      "properties": {
        "type": { "const": "needsMoreContext" },
        "needsMoreContext": {
          "type": "object",
          "additionalProperties": false,
          "required": ["reason", "suggestedAction"],
          "properties": {
            "reason": { "type": "string", "minLength": 1, "maxLength": \(responseLimits.maximumStatusMessageCharacters) },
            "suggestedAction": { "type": ["string", "null"], "maxLength": \(responseLimits.maximumStatusMessageCharacters) }
          }
        }
      }
    }
    """
  }

  private var blockedOutcomeSchema: String {
    """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["type", "blocked"],
      "properties": {
        "type": { "const": "blocked" },
        "blocked": {
          "type": "object",
          "additionalProperties": false,
          "required": ["reason", "message"],
          "properties": {
            "reason": { "enum": ["invalidInput", "unsafeInstruction", "privacyRisk", "unsupported"] },
            "message": { "type": "string", "minLength": 1, "maxLength": \(responseLimits.maximumStatusMessageCharacters) }
          }
        }
      }
    }
    """
  }

  private func validate(_ request: TutorRequest) throws {
    guard request.schemaVersion == TutorRequest.currentSchemaVersion else {
      throw TutorEngineError.invalidRequest(
        .unsupportedSchemaVersion(
          expected: TutorRequest.currentSchemaVersion,
          actual: request.schemaVersion
        )
      )
    }
    guard request.sequence > 0 else {
      throw TutorEngineError.invalidRequest(.invalidSequence(request.sequence))
    }
    guard request.source.sourceRevisionID >= 0 else {
      throw TutorEngineError.invalidRequest(
        .invalidSourceRevisionID(request.source.sourceRevisionID)
      )
    }
    guard Self.hasVisibleText(request.source.text) else {
      throw TutorEngineError.invalidRequest(.emptySourceText)
    }
    guard request.source.text.count <= TutorRequest.defaultMaximumSourceCharacterCount else {
      throw TutorEngineError.invalidRequest(
        .sourceTextTooLong(
          maximum: TutorRequest.defaultMaximumSourceCharacterCount,
          actual: request.source.text.count
        )
      )
    }
    guard Self.hasVisibleText(request.learner.preferredLanguage) else {
      throw TutorEngineError.invalidRequest(.emptyLearnerLanguage)
    }
    guard Self.hasVisibleText(request.output.language) else {
      throw TutorEngineError.invalidRequest(.emptyOutputLanguage)
    }
    guard Self.hasVisibleText(request.policyVersion) else {
      throw TutorEngineError.invalidRequest(.emptyPolicyVersion)
    }
  }

  private func jsonString(_ value: String) throws -> String {
    do {
      let data = try JSONEncoder().encode(value)
      guard let encoded = String(data: data, encoding: .utf8) else {
        throw TutorEngineError.generationFailed
      }
      return encoded
    } catch let error as TutorEngineError {
      throw error
    } catch {
      throw TutorEngineError.generationFailed
    }
  }

  private static func hasVisibleText(_ value: String) -> Bool {
    value.contains(where: { !$0.isWhitespace })
  }
}
