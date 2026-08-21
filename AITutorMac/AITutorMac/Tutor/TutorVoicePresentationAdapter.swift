import Foundation

struct TutorVoiceScript: Equatable, Sendable {
  let presentationID: UUID
  let text: String
  let language: String
}

/// Maps the UI-safe presentation into a short, local-TTS script. It never
/// reads TutorResponse, Prompt, Provider, SemanticChunk, or AX content.
struct TutorVoicePresentationAdapter: Sendable {
  static let defaultMaximumCharacterCount = 420

  private let maximumCharacterCount: Int
  private let shortExplanationThreshold: Int
  private let maximumAppendedKeyPoints: Int
  private let language: String

  init(
    maximumCharacterCount: Int = Self.defaultMaximumCharacterCount,
    shortExplanationThreshold: Int = 40,
    maximumAppendedKeyPoints: Int = 3,
    language: String = "zh-CN"
  ) {
    self.maximumCharacterCount = max(1, maximumCharacterCount)
    self.shortExplanationThreshold = max(0, shortExplanationThreshold)
    self.maximumAppendedKeyPoints = max(0, maximumAppendedKeyPoints)
    self.language = language
  }

  func makeScript(from presentation: TutorPresentationModel) -> TutorVoiceScript? {
    guard presentation.outcome == .lesson,
          let explanation = visibleText(presentation.plainExplanation) else {
      return nil
    }

    var scriptText = clipped(explanation)
    if explanation.count < shortExplanationThreshold,
       scriptText.count < maximumCharacterCount {
      for point in presentation.keyPoints
        .compactMap(visibleText)
        .prefix(maximumAppendedKeyPoints) {
        let candidate = scriptText + " 重点是，" + point
        guard candidate.count <= maximumCharacterCount else {
          break
        }
        scriptText = candidate
      }
    }

    return TutorVoiceScript(
      presentationID: presentation.responseMetadata.responseID,
      text: scriptText,
      language: language
    )
  }

  private func visibleText(_ value: String) -> String? {
    let collapsed = value
      .split(whereSeparator: \Character.isWhitespace)
      .joined(separator: " ")
    return collapsed.isEmpty ? nil : collapsed
  }

  private func clipped(_ value: String) -> String {
    guard value.count > maximumCharacterCount else {
      return value
    }
    guard maximumCharacterCount > 1 else {
      return "…"
    }
    return String(value.prefix(maximumCharacterCount - 1)) + "…"
  }
}
