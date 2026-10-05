import Foundation

enum DiffConfidence: String, Equatable, Sendable {
  case high
  case medium
  case low
}

enum ContextDiffKind: String, Equatable, Sendable {
  case baseline
  case noChange
  case added
  case ambiguous
  case reset
}

struct ContextDiffResult: Equatable, Sendable {
  let kind: ContextDiffKind
  let confidence: DiffConfidence
  let addedText: String
  let previousFingerprint: ContextFingerprint?
  let currentFingerprint: ContextFingerprint

  var hasAddedText: Bool {
    !addedText.isEmpty
  }
}

/// A conservative, stateless diff. It emits only text that can be supported by
/// exact prefix/insertion evidence or a meaningful viewport-tail overlap.
/// Rewrites do not expose removed text and are reported as ambiguous/reset.
struct ContextDiffEngine: Sendable {
  private let fingerprinter: ContextFingerprinter
  private let minimumOverlapCharacters: Int

  init(
    fingerprinter: ContextFingerprinter = ContextFingerprinter(),
    minimumOverlapCharacters: Int = 8
  ) {
    self.fingerprinter = fingerprinter
    self.minimumOverlapCharacters = max(4, minimumOverlapCharacters)
  }

  func diff(
    previous: NormalizedContextText?,
    current: NormalizedContextText
  ) -> ContextDiffResult {
    let currentFingerprint = fingerprinter.fingerprint(current)
    guard let previous else {
      return result(
        kind: .baseline,
        confidence: .high,
        currentFingerprint: currentFingerprint
      )
    }

    let previousFingerprint = fingerprinter.fingerprint(previous)
    if previousFingerprint == currentFingerprint {
      return result(
        kind: .noChange,
        confidence: .high,
        previousFingerprint: previousFingerprint,
        currentFingerprint: currentFingerprint
      )
    }

    if current.isEmpty {
      return result(
        kind: .reset,
        confidence: .low,
        previousFingerprint: previousFingerprint,
        currentFingerprint: currentFingerprint
      )
    }

    if previous.isEmpty {
      return result(
        kind: .added,
        confidence: .high,
        addedText: current.displayText,
        previousFingerprint: previousFingerprint,
        currentFingerprint: currentFingerprint
      )
    }

    if current.displayText.hasPrefix(previous.displayText) {
      let addedText = cleanAddedText(
        String(current.displayText.dropFirst(previous.displayText.count))
      )
      if !addedText.isEmpty {
        return result(
          kind: .added,
          confidence: .high,
          addedText: addedText,
          previousFingerprint: previousFingerprint,
          currentFingerprint: currentFingerprint
        )
      }
    }

    let previousText = previous.comparisonText
    let currentText = current.comparisonText
    if currentText.hasPrefix(previousText) {
      let addedText = cleanAddedText(
        String(currentText.dropFirst(previousText.count))
      )
      if !addedText.isEmpty {
        return result(
          kind: .added,
          confidence: .high,
          addedText: addedText,
          previousFingerprint: previousFingerprint,
          currentFingerprint: currentFingerprint
        )
      }
    }

    let previousCharacters = Array(previousText)
    let currentCharacters = Array(currentText)
    let prefixCount = commonPrefixCount(previousCharacters, currentCharacters)
    let suffixCount = commonSuffixCount(
      previousCharacters,
      currentCharacters,
      excludingPrefixCount: prefixCount
    )

    let previousMiddleCount = previousCharacters.count - prefixCount - suffixCount
    let currentMiddleEnd = currentCharacters.count - suffixCount
    if previousMiddleCount == 0, prefixCount < currentMiddleEnd {
      let addedText = cleanAddedText(
        String(currentCharacters[prefixCount..<currentMiddleEnd])
      )
      if !addedText.isEmpty {
        return result(
          kind: .added,
          confidence: .high,
          addedText: addedText,
          previousFingerprint: previousFingerprint,
          currentFingerprint: currentFingerprint
        )
      }
    }

    if contains(previousCharacters, currentCharacters) {
      return result(
        kind: .noChange,
        confidence: .medium,
        previousFingerprint: previousFingerprint,
        currentFingerprint: currentFingerprint
      )
    }

    if contains(currentCharacters, previousCharacters) {
      return result(
        kind: .ambiguous,
        confidence: .low,
        previousFingerprint: previousFingerprint,
        currentFingerprint: currentFingerprint
      )
    }

    let forwardOverlap = suffixPrefixOverlap(
      suffixSource: previousCharacters,
      prefixSource: currentCharacters
    )
    if isMeaningfulOverlap(
      forwardOverlap,
      previousCount: previousCharacters.count,
      currentCount: currentCharacters.count
    ) {
      if forwardOverlap == currentCharacters.count {
        return result(
          kind: .noChange,
          confidence: .medium,
          previousFingerprint: previousFingerprint,
          currentFingerprint: currentFingerprint
        )
      }

      let addedText = cleanAddedText(String(currentCharacters.dropFirst(forwardOverlap)))
      if !addedText.isEmpty {
        return result(
          kind: .added,
          confidence: .medium,
          addedText: addedText,
          previousFingerprint: previousFingerprint,
          currentFingerprint: currentFingerprint
        )
      }
    }

    let reverseOverlap = suffixPrefixOverlap(
      suffixSource: currentCharacters,
      prefixSource: previousCharacters
    )
    if isMeaningfulOverlap(
      reverseOverlap,
      previousCount: currentCharacters.count,
      currentCount: previousCharacters.count
    ) {
      return result(
        kind: .noChange,
        confidence: .medium,
        previousFingerprint: previousFingerprint,
        currentFingerprint: currentFingerprint
      )
    }

    let anchoredCharacters = prefixCount + suffixCount
    let longestCount = max(previousCharacters.count, currentCharacters.count)
    let anchoredRatio = longestCount == 0
      ? 1
      : Double(anchoredCharacters) / Double(longestCount)
    return result(
      kind: anchoredRatio >= 0.5 ? .ambiguous : .reset,
      confidence: .low,
      previousFingerprint: previousFingerprint,
      currentFingerprint: currentFingerprint
    )
  }

  private func result(
    kind: ContextDiffKind,
    confidence: DiffConfidence,
    addedText: String = "",
    previousFingerprint: ContextFingerprint? = nil,
    currentFingerprint: ContextFingerprint
  ) -> ContextDiffResult {
    ContextDiffResult(
      kind: kind,
      confidence: confidence,
      addedText: addedText,
      previousFingerprint: previousFingerprint,
      currentFingerprint: currentFingerprint
    )
  }

  private func commonPrefixCount(
    _ lhs: [Character],
    _ rhs: [Character]
  ) -> Int {
    var count = 0
    while count < min(lhs.count, rhs.count), lhs[count] == rhs[count] {
      count += 1
    }
    return count
  }

  private func commonSuffixCount(
    _ lhs: [Character],
    _ rhs: [Character],
    excludingPrefixCount prefixCount: Int
  ) -> Int {
    let maximumCount = min(lhs.count, rhs.count) - prefixCount
    var count = 0
    while count < maximumCount,
          lhs[lhs.count - count - 1] == rhs[rhs.count - count - 1] {
      count += 1
    }
    return count
  }

  private func contains(_ haystack: [Character], _ needle: [Character]) -> Bool {
    guard !needle.isEmpty else {
      return true
    }
    guard haystack.count >= needle.count else {
      return false
    }

    let prefixTable = makePrefixTable(needle)
    var matched = 0
    for character in haystack {
      while matched > 0, needle[matched] != character {
        matched = prefixTable[matched - 1]
      }
      if needle[matched] == character {
        matched += 1
      }
      if matched == needle.count {
        return true
      }
    }
    return false
  }

  private func suffixPrefixOverlap(
    suffixSource: [Character],
    prefixSource: [Character]
  ) -> Int {
    guard !suffixSource.isEmpty, !prefixSource.isEmpty else {
      return 0
    }

    let prefixTable = makePrefixTable(prefixSource)
    var matched = 0
    for (index, character) in suffixSource.enumerated() {
      while matched > 0, prefixSource[matched] != character {
        matched = prefixTable[matched - 1]
      }
      if prefixSource[matched] == character {
        matched += 1
      }
      if matched == prefixSource.count, index != suffixSource.count - 1 {
        matched = prefixTable[matched - 1]
      }
    }
    return matched
  }

  private func makePrefixTable(_ pattern: [Character]) -> [Int] {
    guard !pattern.isEmpty else {
      return []
    }

    var table = Array(repeating: 0, count: pattern.count)
    var matched = 0
    for index in 1..<pattern.count {
      while matched > 0, pattern[index] != pattern[matched] {
        matched = table[matched - 1]
      }
      if pattern[index] == pattern[matched] {
        matched += 1
        table[index] = matched
      }
    }
    return table
  }

  private func isMeaningfulOverlap(
    _ overlap: Int,
    previousCount: Int,
    currentCount: Int
  ) -> Bool {
    guard overlap > 0 else {
      return false
    }
    let shorterCount = min(previousCount, currentCount)
    if overlap == shorterCount || overlap >= minimumOverlapCharacters {
      return true
    }
    return overlap >= 4 && Double(overlap) / Double(shorterCount) >= 0.7
  }

  private func cleanAddedText(_ text: String) -> String {
    var result = text.trimmingCharacters(in: .newlines)
    guard result.contains(where: { !$0.isWhitespace }) else {
      return ""
    }

    if result.first == " ", !result.hasPrefix("  ") {
      result.removeFirst()
    }
    if result.last == " ", !result.hasSuffix("  ") {
      result.removeLast()
    }
    return result
  }
}
