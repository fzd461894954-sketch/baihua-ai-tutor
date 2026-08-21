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
      return publish(
        revisionID: revisionSequence,
        timestamp: snapshot.window.observedAt,
        changeType: .baseline,
        addedText: "",
        confidence: .high,
        fingerprint: fingerprint,
        normalizedText: normalizedText,
        identity: identity
      )
    }

    guard currentIdentity == identity else {
      revisionSequence = 0
      return publish(
        revisionID: revisionSequence,
        timestamp: snapshot.window.observedAt,
        changeType: .reset,
        addedText: "",
        confidence: .high,
        fingerprint: fingerprint,
        normalizedText: normalizedText,
        identity: identity
      )
    }

    let diff = diffEngine.diff(previous: previousText, current: normalizedText)
    if diff.kind != .noChange && diff.kind != .baseline {
      revisionSequence += 1
    }

    return publish(
      revisionID: revisionSequence,
      timestamp: snapshot.window.observedAt,
      changeType: diff.kind,
      addedText: diff.addedText,
      confidence: diff.confidence,
      fingerprint: diff.currentFingerprint,
      normalizedText: normalizedText,
      identity: identity
    )
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
}
