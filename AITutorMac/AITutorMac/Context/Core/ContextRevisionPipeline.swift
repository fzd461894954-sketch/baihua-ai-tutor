import Foundation
import Observation

struct ContextRevision: Equatable, Sendable {
  let revisionID: Int
  let timestamp: Date
  let changeType: ContextDiffKind
  let addedText: String
  let confidence: DiffConfidence
  let fingerprint: ContextFingerprint
  let characterCount: Int
  let identity: ContextIdentity
}

#if DEBUG
struct TutorContextPipelineDebugSnapshot: Equatable, Sendable {
  let sourceApplication: String?
  let bundleIdentifier: String?
  let processIdentifier: pid_t
  let focusedWindow: String?
  let focusedWindowToken: String
  let snapshotSource: String
  let contextRevisionID: Int
  let timestamp: Date
  let rawSnapshot: String
  let normalizedText: String
  let previousBaseline: String
  let currentSnapshot: String
  let detectedAddedText: String
  let detectedRemovedText: String
  let detectedStableText: String
  let diffKind: ContextDiffKind
  let truncated: Bool
}
#endif

/// Owns one live session's latest normalized context. Previous text is used as
/// the next diff baseline and then replaced; no revision body history is kept.
@MainActor
@Observable
final class ContextRevisionPipeline {
  private(set) var currentIdentity: ContextIdentity?
  private(set) var latestNormalizedText: NormalizedContextText?
  private(set) var latestRevision: ContextRevision?

  var latestFingerprint: ContextFingerprint? {
    latestRevision?.fingerprint
  }

  @ObservationIgnored var onRevision: ((ContextRevision) -> Void)?
#if DEBUG
  @ObservationIgnored var onDebugSnapshot:
    ((TutorContextPipelineDebugSnapshot) -> Void)?
#endif
  @ObservationIgnored private let identityFactory: ContextIdentityFactory
  @ObservationIgnored private let normalizer: TextNormalizer
  @ObservationIgnored private let fingerprinter: ContextFingerprinter
  @ObservationIgnored private let diffEngine: ContextDiffEngine
  @ObservationIgnored private var revisionSequence = 0

  init(
    identityFactory: ContextIdentityFactory = ContextIdentityFactory(),
    normalizer: TextNormalizer = TextNormalizer(),
    fingerprinter: ContextFingerprinter = ContextFingerprinter(),
    diffEngine: ContextDiffEngine = ContextDiffEngine()
  ) {
    self.identityFactory = identityFactory
    self.normalizer = normalizer
    self.fingerprinter = fingerprinter
    self.diffEngine = diffEngine
  }

  @discardableResult
  func ingest(
    snapshot: AccessibleTextSnapshot,
    liveSessionIdentifier: UUID
  ) -> ContextRevision {
    let identity = identityFactory.makeIdentity(
      snapshot: snapshot,
      liveSessionIdentifier: liveSessionIdentifier
    )
    let normalizedText = normalizer.normalize(snapshot.plainText)
    let fingerprint = fingerprinter.fingerprint(normalizedText)

    guard let currentIdentity, let previousText = latestNormalizedText else {
      revisionSequence = 0
      let revision = publish(
        revisionID: revisionSequence,
        timestamp: snapshot.window.observedAt,
        changeType: .baseline,
        addedText: "",
        confidence: .high,
        fingerprint: fingerprint,
        normalizedText: normalizedText,
        identity: identity
      )
#if DEBUG
      publishDebug(
        snapshot: snapshot,
        previousText: nil,
        normalizedText: normalizedText,
        revision: revision
      )
#endif
      return revision
    }

    guard currentIdentity == identity else {
      revisionSequence = 0
      let revision = publish(
        revisionID: revisionSequence,
        timestamp: snapshot.window.observedAt,
        changeType: .reset,
        addedText: "",
        confidence: .high,
        fingerprint: fingerprint,
        normalizedText: normalizedText,
        identity: identity
      )
#if DEBUG
      publishDebug(
        snapshot: snapshot,
        previousText: previousText,
        normalizedText: normalizedText,
        revision: revision
      )
#endif
      return revision
    }

    let diff = diffEngine.diff(previous: previousText, current: normalizedText)
    if diff.kind != .noChange && diff.kind != .baseline {
      revisionSequence += 1
    }

    let revision = publish(
      revisionID: revisionSequence,
      timestamp: snapshot.window.observedAt,
      changeType: diff.kind,
      addedText: diff.addedText,
      confidence: diff.confidence,
      fingerprint: diff.currentFingerprint,
      normalizedText: normalizedText,
      identity: identity
    )
#if DEBUG
    publishDebug(
      snapshot: snapshot,
      previousText: previousText,
      normalizedText: normalizedText,
      revision: revision
    )
#endif
    return revision
  }

  func clear() {
    currentIdentity = nil
    latestNormalizedText = nil
    latestRevision = nil
    revisionSequence = 0
  }

  private func publish(
    revisionID: Int,
    timestamp: Date,
    changeType: ContextDiffKind,
    addedText: String,
    confidence: DiffConfidence,
    fingerprint: ContextFingerprint,
    normalizedText: NormalizedContextText,
    identity: ContextIdentity
  ) -> ContextRevision {
    let revision = ContextRevision(
      revisionID: revisionID,
      timestamp: timestamp,
      changeType: changeType,
      addedText: addedText,
      confidence: confidence,
      fingerprint: fingerprint,
      characterCount: normalizedText.displayText.count,
      identity: identity
    )
    currentIdentity = identity
    latestNormalizedText = normalizedText
    latestRevision = revision
    onRevision?(revision)
    return revision
  }

#if DEBUG
  private func publishDebug(
    snapshot: AccessibleTextSnapshot,
    previousText: NormalizedContextText?,
    normalizedText: NormalizedContextText,
    revision: ContextRevision
  ) {
    let diagnostic = Self.debugMiddleDiff(
      previous: previousText?.displayText ?? "",
      current: normalizedText.displayText
    )
    onDebugSnapshot?(
      TutorContextPipelineDebugSnapshot(
        sourceApplication: snapshot.window.application.appName,
        bundleIdentifier: snapshot.window.application.bundleIdentifier,
        processIdentifier: snapshot.window.application.processIdentifier,
        focusedWindow: snapshot.window.windowTitle,
        focusedWindowToken: revision.identity.focusedWindowIdentity.rawValue,
        snapshotSource: snapshot.window.source.rawValue,
        contextRevisionID: revision.revisionID,
        timestamp: revision.timestamp,
        rawSnapshot: snapshot.plainText,
        normalizedText: normalizedText.displayText,
        previousBaseline: previousText?.displayText ?? "",
        currentSnapshot: normalizedText.displayText,
        detectedAddedText: revision.addedText,
        detectedRemovedText: diagnostic.removed,
        detectedStableText: diagnostic.stable,
        diffKind: revision.changeType,
        truncated: snapshot.truncated
      )
    )
  }

  private static func debugMiddleDiff(
    previous: String,
    current: String
  ) -> (removed: String, stable: String) {
    let previousCharacters = Array(previous)
    let currentCharacters = Array(current)
    var prefixCount = 0
    while
      prefixCount < min(previousCharacters.count, currentCharacters.count),
      previousCharacters[prefixCount] == currentCharacters[prefixCount]
    {
      prefixCount += 1
    }

    var suffixCount = 0
    let suffixLimit = min(previousCharacters.count, currentCharacters.count) - prefixCount
    while
      suffixCount < suffixLimit,
      previousCharacters[previousCharacters.count - suffixCount - 1]
        == currentCharacters[currentCharacters.count - suffixCount - 1]
    {
      suffixCount += 1
    }

    let removedEnd = previousCharacters.count - suffixCount
    let removed = prefixCount < removedEnd
      ? String(previousCharacters[prefixCount..<removedEnd])
      : ""
    let prefix = String(previousCharacters.prefix(prefixCount))
    let suffix = suffixCount > 0
      ? String(previousCharacters.suffix(suffixCount))
      : ""
    let stable = [prefix, suffix]
      .filter { !$0.isEmpty }
      .joined(separator: prefix.isEmpty || suffix.isEmpty ? "" : "\n…\n")
    return (removed, stable)
  }
#endif
}
