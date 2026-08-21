import Foundation
import Observation

/// Converts incremental revision text into stable, one-shot chunks. Only the
/// current pending body is retained; emitted chunk bodies are never archived.
@MainActor
@Observable
final class SemanticBuffer {
  private(set) var state: SemanticBufferState = .idle
  private(set) var pendingText = ""
  private(set) var currentIdentity: ContextIdentity?
  private(set) var lastFlushReason: SemanticFlushReason?
  private(set) var lastConfidence: DiffConfidence?
  private(set) var chunkCount = 0

  var pendingCharacterCount: Int {
    pendingText.count
  }

  var hasScheduledFlushTask: Bool {
    idleFlushTask != nil
  }

  @ObservationIgnored var onChunk: ((SemanticChunk) -> Void)?
  @ObservationIgnored private let configuration: SemanticBufferConfiguration
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let makeID: () -> UUID
  @ObservationIgnored private var pendingConfidence: DiffConfidence?
  @ObservationIgnored private var sourceRevisionID: Int?
  @ObservationIgnored private var lastObservedCharacterCount: Int?
  @ObservationIgnored private var idleFlushTask: Task<Void, Never>?
  @ObservationIgnored private var idleGeneration = 0

  init(
    configuration: SemanticBufferConfiguration = .default,
    now: @escaping () -> Date = Date.init,
    makeID: @escaping () -> UUID = UUID.init
  ) {
    self.configuration = configuration
    self.now = now
    self.makeID = makeID
  }

  deinit {
    idleFlushTask?.cancel()
  }

  func ingest(_ revision: ContextRevision) {
    let identityChanged = currentIdentity.map { $0 != revision.identity } ?? false
    let previousCharacterCount = identityChanged ? nil : lastObservedCharacterCount

    if currentIdentity == nil || identityChanged {
      discardPending()
      currentIdentity = revision.identity
    }

    defer {
      lastObservedCharacterCount = revision.characterCount
    }

    switch revision.changeType {
    case .baseline, .reset:
      discardPending()
    case .noChange, .ambiguous:
      break
    case .added:
      append(
        revision.addedText,
        revisionID: revision.revisionID,
        confidence: revision.confidence,
        previousCharacterCount: previousCharacterCount,
        currentCharacterCount: revision.characterCount
      )
    }
  }

  @discardableResult
  func manualFlush() -> SemanticChunk? {
    cancelIdleFlush()
    return flushAll(reason: .manualFlush)
  }

  /// Clears pending body, metadata, counters, and all scheduled work. Live
  /// Watch calls this on stop so no session-derived content survives.
  func clear() {
    discardPending()
    currentIdentity = nil
    lastObservedCharacterCount = nil
    lastFlushReason = nil
    lastConfidence = nil
    chunkCount = 0
  }

  private func append(
    _ fragment: String,
    revisionID: Int,
    confidence: DiffConfidence,
    previousCharacterCount: Int?,
    currentCharacterCount: Int
  ) {
    guard fragment.contains(where: { !$0.isWhitespace }) else {
      return
    }

    if shouldRestoreSeparator(
      before: fragment,
      previousCharacterCount: previousCharacterCount,
      currentCharacterCount: currentCharacterCount
    ) {
      pendingText.append(" ")
    }
    pendingText.append(fragment)
    sourceRevisionID = revisionID
    pendingConfidence = mergedConfidence(pendingConfidence, confidence)
    state = .buffering

    flushSizeLimitedPrefixes()
    flushCompletedSentences()

    if pendingText.isEmpty {
      cancelIdleFlush()
      state = .idle
    } else {
      scheduleIdleFlush()
    }
  }

  private func shouldRestoreSeparator(
    before fragment: String,
    previousCharacterCount: Int?,
    currentCharacterCount: Int
  ) -> Bool {
    guard
      !pendingText.isEmpty,
      pendingText.last?.isWhitespace != true,
      fragment.first?.isWhitespace != true,
      let previousCharacterCount,
      currentCharacterCount - previousCharacterCount > fragment.count
    else {
      return false
    }
    return true
  }

  private func flushSizeLimitedPrefixes() {
    let limit = configuration.maximumCharacterCount
    while pendingText.count >= limit {
      let boundary = sentenceBoundaryCounts(in: pendingText, maximumCount: limit).last
      let prefixCount = boundary ?? limit
      guard emitPrefix(characterCount: prefixCount, reason: .sizeLimit) != nil else {
        return
      }
    }
  }

  private func flushCompletedSentences() {
    while let boundary = sentenceBoundaryCounts(in: pendingText).first {
      guard emitPrefix(characterCount: boundary, reason: .sentenceComplete) != nil else {
        return
      }
    }
  }

  @discardableResult
  private func flushAll(reason: SemanticFlushReason) -> SemanticChunk? {
    guard !pendingText.isEmpty else {
      state = .idle
      return nil
    }
    return emitPrefix(characterCount: pendingText.count, reason: reason)
  }

  @discardableResult
  private func emitPrefix(
    characterCount: Int,
    reason: SemanticFlushReason
  ) -> SemanticChunk? {
    guard
      characterCount > 0,
      let sourceRevisionID,
      let pendingConfidence
    else {
      return nil
    }

    let rawChunkText = String(pendingText.prefix(characterCount))
    let chunkText = rawChunkText.trimmingCharacters(in: .whitespacesAndNewlines)
    pendingText = String(pendingText.dropFirst(characterCount))
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !chunkText.isEmpty else {
      if pendingText.isEmpty {
        clearPendingMetadata()
      }
      return nil
    }

    state = .flushing
    let chunk = SemanticChunk(
      id: makeID(),
      sourceRevisionID: sourceRevisionID,
      text: chunkText,
      confidence: pendingConfidence,
      createdAt: now(),
      flushReason: reason
    )
    chunkCount += 1
    lastFlushReason = reason
    lastConfidence = pendingConfidence

    if pendingText.isEmpty {
      clearPendingMetadata()
      state = .idle
    } else {
      state = .buffering
    }
    AppLogger.tutorRuntime.debug(
      "Semantic chunk emitted id=\(chunk.id.uuidString, privacy: .public) revision=\(chunk.sourceRevisionID, privacy: .public) confidence=\(chunk.confidence.rawValue, privacy: .public) flush=\(chunk.flushReason.rawValue, privacy: .public) characters=\(chunk.text.count, privacy: .public) emitted=\(self.chunkCount, privacy: .public)"
    )
    onChunk?(chunk)
    return chunk
  }

  private func scheduleIdleFlush() {
    cancelIdleFlush()
    idleGeneration += 1
    let generation = idleGeneration
    let stabilityDelay = configuration.stabilityCheckDelay
    let remainingDelay = configuration.idleFlushDelay - stabilityDelay

    idleFlushTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: Self.nanoseconds(for: stabilityDelay))
      } catch {
        return
      }
      guard
        let self,
        !Task.isCancelled,
        self.idleGeneration == generation,
        !self.pendingText.isEmpty
      else {
        return
      }

      self.state = .ready
      do {
        try await Task.sleep(nanoseconds: Self.nanoseconds(for: remainingDelay))
      } catch {
        return
      }
      guard
        !Task.isCancelled,
        self.idleGeneration == generation,
        !self.pendingText.isEmpty
      else {
        return
      }

      self.idleFlushTask = nil
      _ = self.flushAll(reason: .idleTimeout)
    }
  }

  private func discardPending() {
    cancelIdleFlush()
    pendingText = ""
    clearPendingMetadata()
    state = .idle
  }

  private func clearPendingMetadata() {
    pendingConfidence = nil
    sourceRevisionID = nil
  }

  private func cancelIdleFlush() {
    idleGeneration += 1
    idleFlushTask?.cancel()
    idleFlushTask = nil
  }

  private func mergedConfidence(
    _ current: DiffConfidence?,
    _ incoming: DiffConfidence
  ) -> DiffConfidence {
    guard let current else {
      return incoming
    }
    if current == .low || incoming == .low {
      return .low
    }
    if current == .medium || incoming == .medium {
      return .medium
    }
    return .high
  }

  /// Returns sentence end offsets as Character counts. Fenced code is treated
  /// as opaque so punctuation inside code does not split the block.
  private func sentenceBoundaryCounts(
    in text: String,
    maximumCount: Int? = nil
  ) -> [Int] {
    let characters = Array(text)
    let scanLimit = min(maximumCount ?? characters.count, characters.count)
    var boundaries: [Int] = []
    var fenceMarker: Character?
    var isAtLineStart = true
    var index = 0

    while index < scanLimit {
      if isAtLineStart {
        var markerIndex = index
        while markerIndex < scanLimit,
              characters[markerIndex] == " " || characters[markerIndex] == "\t" {
          markerIndex += 1
        }
        if markerIndex + 2 < scanLimit {
          let candidate = characters[markerIndex]
          if (candidate == "`" || candidate == "~"),
             characters[markerIndex + 1] == candidate,
             characters[markerIndex + 2] == candidate {
            fenceMarker = fenceMarker == nil
              ? candidate
              : (fenceMarker == candidate ? nil : fenceMarker)
            index = markerIndex + 3
            isAtLineStart = false
            continue
          }
        }
      }

      let character = characters[index]
      if character == "\n" {
        isAtLineStart = true
        index += 1
        continue
      }
      isAtLineStart = false

      if fenceMarker == nil, isSentenceTerminator(character, at: index, in: characters) {
        var end = index + 1
        while end < scanLimit, Self.sentenceClosers.contains(characters[end]) {
          end += 1
        }
        boundaries.append(end)
        index = end
      } else {
        index += 1
      }
    }
    return boundaries
  }

  private func isSentenceTerminator(
    _ character: Character,
    at index: Int,
    in characters: [Character]
  ) -> Bool {
    if character == "。" || character == "？" || character == "！"
      || character == "?" || character == "!" {
      return true
    }
    guard character == "." else {
      return false
    }
    let previousIsNumber = index > 0 && characters[index - 1].isNumber
    let nextIsNumber = index + 1 < characters.count && characters[index + 1].isNumber
    return !(previousIsNumber && nextIsNumber)
  }

  private nonisolated static func nanoseconds(for interval: TimeInterval) -> UInt64 {
    UInt64(max(0, interval) * 1_000_000_000)
  }

  private static let sentenceClosers: Set<Character> = [
    "\"", "'", "”", "’", "」", "』", "】", "）", ")", "]",
  ]
}
