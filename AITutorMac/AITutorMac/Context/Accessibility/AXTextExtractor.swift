import Foundation

struct AXTextExtractionResult {
  let nodes: [AccessibleTextNode]
  let plainText: String
  let visitedNodeCount: Int
  let roleCounts: [String: Int]
  let truncated: Bool
}
struct AXTextExtractor {
  let limits: AccessibilityTraversalLimits

  init(limits: AccessibilityTraversalLimits = .default) {
    self.limits = limits
  }

  func extract(
    from root: any AXElementReading,
    cancellationToken: AccessibilityReadCancellationToken
  ) throws -> AXTextExtractionResult {
    var stack: [(element: any AXElementReading, depth: Int)] = [(root, 0)]
    var nodes: [AccessibleTextNode] = []
    var seenText: Set<String> = []
    var visitedNodeCount = 0
    var roleCounts: [String: Int] = [:]
    var plainCharacterCount = 0
    var truncated = false

    while let item = stack.popLast() {
      try cancellationToken.checkCancellation()

      if visitedNodeCount >= limits.maxNodes {
        truncated = true
        break
      }

      visitedNodeCount += 1
      let role = try readString(item.element, .role)
      let subrole = try readString(item.element, .subrole)
      if let role {
        roleCounts[role, default: 0] += 1
      }

      if Self.isSecure(role: role, subrole: subrole) {
        continue
      }

      for (attribute, source) in Self.textAttributes {
        try cancellationToken.checkCancellation()
        guard
          let rawText = try readString(item.element, attribute),
          !rawText.isEmpty
        else {
          continue
        }

        let text = Self.normalize(rawText)
        guard !text.isEmpty, seenText.insert(text).inserted else {
          continue
        }

        let separatorCost = nodes.isEmpty ? 0 : 1
        let available = limits.maxCharacters - plainCharacterCount - separatorCost
        guard available > 0 else {
          truncated = true
          break
        }

        let storedText = String(text.prefix(available))
        nodes.append(
          AccessibleTextNode(
            role: role,
            text: storedText,
            depth: item.depth,
            sourceAttribute: source
          )
        )
        plainCharacterCount += separatorCost + storedText.count

        if storedText.count < text.count {
          truncated = true
          break
        }
      }

      if truncated && plainCharacterCount >= limits.maxCharacters {
        break
      }

      let children = try readChildren(item.element)
      if item.depth >= limits.maxDepth {
        if !children.isEmpty {
          truncated = true
        }
        continue
      }

      for child in children.reversed() {
        stack.append((child, item.depth + 1))
      }
    }

    let plainText = nodes.map(\.text).joined(separator: "\n")
    return AXTextExtractionResult(
      nodes: nodes,
      plainText: plainText,
      visitedNodeCount: visitedNodeCount,
      roleCounts: roleCounts,
      truncated: truncated
    )
  }

  private func readString(
    _ element: any AXElementReading,
    _ attribute: AXReadableAttribute
  ) throws -> String? {
    do {
      return try element.stringValue(for: attribute)
    } catch {
      throw AccessibilityReaderError.readFailed
    }
  }

  private func readChildren(
    _ element: any AXElementReading
  ) throws -> [any AXElementReading] {
    do {
      return try element.childElements()
    } catch {
      throw AccessibilityReaderError.readFailed
    }
  }

  private static let textAttributes: [
    (AXReadableAttribute, AccessibilityTextSourceAttribute)
  ] = [
    (.title, .title),
    (.value, .value),
    (.accessibilityDescription, .accessibilityDescription),
    (.help, .help),
  ]

  private static func isSecure(role: String?, subrole: String?) -> Bool {
    role == "AXSecureTextField"
      || subrole?.localizedCaseInsensitiveContains("secure") == true
      || subrole?.localizedCaseInsensitiveContains("password") == true
  }

  private static func normalize(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { line in
        line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
      }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
