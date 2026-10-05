import Foundation

struct NormalizedContextText: Equatable, Sendable {
  static let normalizationVersion = 2

  let displayText: String
  let comparisonText: String

  var isEmpty: Bool {
    comparisonText.isEmpty
  }
}

/// Canonicalizes snapshot text for cross-snapshot comparison without changing
/// the Accessibility extraction policy. Display text keeps useful line and code
/// structure; comparison text ignores soft wrapping outside fenced code blocks.
struct TextNormalizer: Sendable {
  func normalize(_ rawText: String) -> NormalizedContextText {
    let canonicalText = sanitize(rawText)
    let displayLines = normalizeDisplayLines(
      canonicalText.components(separatedBy: "\n")
    )

    return NormalizedContextText(
      displayText: displayLines.joined(separator: "\n"),
      comparisonText: makeComparisonText(from: displayLines)
    )
  }

  private func sanitize(_ text: String) -> String {
    text
      .precomposedStringWithCanonicalMapping
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\u{FEFF}", with: "")
      .replacingOccurrences(of: "\u{200B}", with: "")
      .replacingOccurrences(of: "\u{2060}", with: "")
      .replacingOccurrences(of: "\u{180E}", with: "")
      .replacingOccurrences(of: "\u{00A0}", with: " ")
      .replacingOccurrences(of: "\u{202F}", with: " ")
  }

  private func normalizeDisplayLines(_ rawLines: [String]) -> [String] {
    var lines: [String] = []
    var activeFence: String?

    for rawLine in rawLines {
      if let marker = activeFence {
        let line = trimTrailingHorizontalWhitespace(rawLine)
        lines.append(line)
        if fenceMarker(in: line) == marker {
          activeFence = nil
        }
        continue
      }

      // Display text is also the Tutor source. Preserve leading indentation
      // and internal horizontal whitespace so unfenced code is not rewritten.
      // Comparison text performs its own whitespace folding below.
      let line = trimTrailingHorizontalWhitespace(rawLine)
      if let marker = fenceMarker(in: line) {
        lines.append(line)
        activeFence = marker
      } else if line.allSatisfy(\.isWhitespace) {
        if !lines.isEmpty, lines.last != "" {
          lines.append("")
        }
      } else {
        lines.append(line)
      }
    }

    while lines.last == "" {
      lines.removeLast()
    }
    return lines
  }

  private func makeComparisonText(from displayLines: [String]) -> String {
    var components: [String] = []
    var paragraphLines: [String] = []
    var codeLines: [String]? = nil
    var activeFence: String?

    func flushParagraph() {
      guard !paragraphLines.isEmpty else {
        return
      }
      components.append(paragraphLines.joined(separator: " "))
      paragraphLines.removeAll(keepingCapacity: true)
    }

    func flushCode() {
      guard let codeLines else {
        return
      }
      components.append(codeLines.joined(separator: "\n"))
    }

    for line in displayLines {
      if activeFence != nil {
        codeLines?.append(line)
        if fenceMarker(in: line) == activeFence {
          activeFence = nil
          flushCode()
          codeLines = nil
        }
        continue
      }

      if let marker = fenceMarker(in: line) {
        flushParagraph()
        activeFence = marker
        codeLines = [line]
      } else if line.isEmpty {
        flushParagraph()
      } else {
        paragraphLines.append(collapseWhitespace(line))
      }
    }

    flushParagraph()
    flushCode()
    return components.joined(separator: "\n\n")
  }

  private func collapseWhitespace(_ line: String) -> String {
    line
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }

  private func trimTrailingHorizontalWhitespace(_ line: String) -> String {
    var result = line
    while result.last == " " || result.last == "\t" {
      result.removeLast()
    }
    return result
  }

  private func fenceMarker(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("```") {
      return "```"
    }
    if trimmed.hasPrefix("~~~") {
      return "~~~"
    }
    return nil
  }
}
