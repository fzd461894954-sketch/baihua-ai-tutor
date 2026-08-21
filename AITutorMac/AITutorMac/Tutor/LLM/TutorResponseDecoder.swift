import Foundation

struct TutorResponseDecoder: Sendable {
  func decode(_ rawResponse: RawLLMResponse) throws -> TutorResponse {
    switch rawResponse.finishReason {
    case .cancelled:
      throw LLMProviderError.cancelled
    case .length:
      throw LLMProviderError.invalidResponse
    case .stop, .other, nil:
      break
    }

    guard rawResponse.content.contains(where: { !$0.isWhitespace }) else {
      throw LLMProviderError.invalidResponse
    }
    guard let data = rawResponse.content.data(using: .utf8) else {
      throw LLMProviderError.decodingFailed
    }

    let jsonObject: Any
    do {
      jsonObject = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw LLMProviderError.decodingFailed
    }

    guard
      let root = jsonObject as? [String: Any],
      Self.hasStrictSchemaShape(root)
    else {
      throw LLMProviderError.invalidResponse
    }

    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let wireResponse = try decoder.decode(TutorResponseWire.self, from: data)
      guard wireResponse.schemaVersion == TutorResponse.currentSchemaVersion else {
        throw LLMProviderError.invalidResponse
      }
      return try wireResponse.domainValue()
    } catch let error as LLMProviderError {
      throw error
    } catch {
      throw LLMProviderError.invalidResponse
    }
  }

  private static func hasStrictSchemaShape(_ root: [String: Any]) -> Bool {
    let rootKeys: Set<String> = [
      "schemaVersion",
      "id",
      "requestID",
      "sessionID",
      "sequence",
      "sourceChunkID",
      "createdAt",
      "outcome",
    ]
    guard
      Set(root.keys) == rootKeys,
      let outcome = root["outcome"] as? [String: Any],
      let type = outcome["type"] as? String
    else {
      return false
    }

    switch type {
    case "lesson":
      return hasStrictLessonShape(outcome)
    case "needsMoreContext":
      return hasStrictNeedsMoreContextShape(outcome)
    case "blocked":
      return hasStrictBlockedShape(outcome)
    default:
      return false
    }
  }

  private static func hasStrictLessonShape(_ outcome: [String: Any]) -> Bool {
    guard
      Set(outcome.keys) == ["type", "lesson"],
      let lesson = outcome["lesson"] as? [String: Any],
      Set(lesson.keys) == [
        "title",
        "plainExplanation",
        "keyPoints",
        "glossary",
        "analogy",
        "example",
        "checkQuestion",
        "caveats",
        "confidence",
      ],
      let glossary = lesson["glossary"] as? [[String: Any]]
    else {
      return false
    }

    return glossary.allSatisfy {
      Set($0.keys) == ["term", "plainDefinition"]
    }
  }

  private static func hasStrictNeedsMoreContextShape(
    _ outcome: [String: Any]
  ) -> Bool {
    guard
      Set(outcome.keys) == ["type", "needsMoreContext"],
      let value = outcome["needsMoreContext"] as? [String: Any]
    else {
      return false
    }
    return Set(value.keys) == ["reason", "suggestedAction"]
  }

  private static func hasStrictBlockedShape(_ outcome: [String: Any]) -> Bool {
    guard
      Set(outcome.keys) == ["type", "blocked"],
      let value = outcome["blocked"] as? [String: Any]
    else {
      return false
    }
    return Set(value.keys) == ["reason", "message"]
  }
}

private struct TutorResponseWire: Decodable {
  let schemaVersion: Int
  let id: UUID
  let requestID: UUID
  let sessionID: UUID
  let sequence: Int
  let sourceChunkID: UUID
  let createdAt: Date
  let outcome: TutorOutcomeWire

  func domainValue() throws -> TutorResponse {
    TutorResponse(
      schemaVersion: schemaVersion,
      id: id,
      requestID: requestID,
      sessionID: sessionID,
      sequence: sequence,
      sourceChunkID: sourceChunkID,
      createdAt: createdAt,
      outcome: try outcome.domainValue()
    )
  }
}

private struct TutorOutcomeWire: Decodable {
  let type: String
  let lesson: TutorLessonWire?
  let needsMoreContext: TutorNeedsMoreContextWire?
  let blocked: TutorBlockWire?

  func domainValue() throws -> TutorOutcome {
    switch type {
    case "lesson":
      guard
        let lesson,
        needsMoreContext == nil,
        blocked == nil
      else {
        throw LLMProviderError.invalidResponse
      }
      return .lesson(try lesson.domainValue())
    case "needsMoreContext":
      guard
        lesson == nil,
        let needsMoreContext,
        blocked == nil
      else {
        throw LLMProviderError.invalidResponse
      }
      return .needsMoreContext(needsMoreContext.domainValue())
    case "blocked":
      guard
        lesson == nil,
        needsMoreContext == nil,
        let blocked
      else {
        throw LLMProviderError.invalidResponse
      }
      return .blocked(try blocked.domainValue())
    default:
      throw LLMProviderError.invalidResponse
    }
  }
}

private struct TutorLessonWire: Decodable {
  let title: String?
  let plainExplanation: String
  let keyPoints: [String]
  let glossary: [TutorTermWire]
  let analogy: String?
  let example: String?
  let checkQuestion: String?
  let caveats: [String]
  let confidence: String

  func domainValue() throws -> TutorLesson {
    guard let confidence = TutorAnswerConfidence(rawValue: confidence) else {
      throw LLMProviderError.invalidResponse
    }
    return TutorLesson(
      title: title,
      plainExplanation: plainExplanation,
      keyPoints: keyPoints,
      glossary: glossary.map { $0.domainValue() },
      analogy: analogy,
      example: example,
      checkQuestion: checkQuestion,
      caveats: caveats,
      confidence: confidence
    )
  }
}

private struct TutorTermWire: Decodable {
  let term: String
  let plainDefinition: String

  func domainValue() -> TutorTerm {
    TutorTerm(term: term, plainDefinition: plainDefinition)
  }
}

private struct TutorNeedsMoreContextWire: Decodable {
  let reason: String
  let suggestedAction: String?

  func domainValue() -> TutorNeedsMoreContext {
    TutorNeedsMoreContext(reason: reason, suggestedAction: suggestedAction)
  }
}

private struct TutorBlockWire: Decodable {
  let reason: String
  let message: String

  func domainValue() throws -> TutorBlock {
    guard let reason = TutorBlockReason(rawValue: reason) else {
      throw LLMProviderError.invalidResponse
    }
    return TutorBlock(reason: reason, message: message)
  }
}
