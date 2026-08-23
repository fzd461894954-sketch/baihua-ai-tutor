import Foundation
import Observation

enum CurrentExplainableContentError: Error, Equatable, Sendable {
  case noStableContent
}

enum CurrentExplainableContentRejectionReason: String, Equatable, Sendable {
  case noActiveSession
  case invalidatedSession
  case wrongSession
  case emptyText
  case textTooLong
  case staleChunk
}

enum CurrentExplainableContentReceiveResult: Equatable, Sendable {
  case accepted
  case rejected(CurrentExplainableContentRejectionReason)
}

enum CurrentExplainableContentInvalidationReason: String, Equatable, Sendable {
  case liveSessionEnded
  case newSessionReplaced
  case contextReset
  case permissionLoss
  case targetUnavailable
  case applicationShutdown
}

enum CurrentExplainableContentRetrievalResult: String, Equatable, Sendable {
  case available
  case noActiveSession
  case noStableChunk
  case invalidCurrentChunk
}

#if DEBUG
struct CurrentExplainableContentDiagnosticSnapshot: Equatable, Sendable {
  let providerInstanceIdentity: UUID
  let activeSessionID: UUID?
  let latestChunkID: UUID?
  let latestChunkRevision: Int?
  let latestConfidence: DiffConfidence?
  let latestFlushReason: SemanticFlushReason?
  let latestCharacterCount: Int?
  let isAvailable: Bool
  let lastInvalidationReason: CurrentExplainableContentInvalidationReason?
  let lastRejectionReason: CurrentExplainableContentRejectionReason?
  let lastRetrievalResult: CurrentExplainableContentRetrievalResult?
  let chunksReceived: Int
  let chunksAccepted: Int
  let chunksRejected: Int
  let explainRequests: Int
}
#endif

/// Keeps only the latest stable SemanticChunk owned by the active AX live
/// session. It has no history, snapshot body, revision archive, or persistence.
@MainActor
@Observable
final class CurrentExplainableContentProvider: TutorCurrentContentProviding {
  private(set) var activeSessionID: UUID?
  private(set) var hasStableContent = false

  @ObservationIgnored private var currentChunk: SemanticChunk?
  @ObservationIgnored private let maximumCharacterCount: Int
  @ObservationIgnored private var lastInvalidatedSessionID: UUID?
#if DEBUG
  @ObservationIgnored private let diagnosticInstanceIdentity = UUID()
  @ObservationIgnored private var lastInvalidationReason:
    CurrentExplainableContentInvalidationReason?
  @ObservationIgnored private var lastRejectionReason: CurrentExplainableContentRejectionReason?
  @ObservationIgnored private var lastRetrievalResult: CurrentExplainableContentRetrievalResult?
  @ObservationIgnored private var chunksReceived = 0
  @ObservationIgnored private var chunksAccepted = 0
  @ObservationIgnored private var chunksRejected = 0
  @ObservationIgnored private var explainRequests = 0
#endif

  init(
    maximumCharacterCount: Int = TutorRequest.defaultMaximumSourceCharacterCount
  ) {
    self.maximumCharacterCount = maximumCharacterCount
  }

  func beginSession(_ sessionID: UUID) {
    if activeSessionID == sessionID {
      AppLogger.tutorRuntime.debug(
        "Current content session already active session=\(sessionID.uuidString, privacy: .public)"
      )
      return
    }
#if DEBUG
    if activeSessionID != nil {
      lastInvalidationReason = .newSessionReplaced
    }
#endif
    activeSessionID = sessionID
    lastInvalidatedSessionID = nil
    currentChunk = nil
    hasStableContent = false
    AppLogger.tutorRuntime.info(
      "Current content session started session=\(sessionID.uuidString, privacy: .public) available=false"
    )
  }

  @discardableResult
  func receive(
    _ chunk: SemanticChunk,
    sessionID: UUID
  ) -> CurrentExplainableContentReceiveResult {
#if DEBUG
    chunksReceived += 1
#endif
    let rejectionReason: CurrentExplainableContentRejectionReason?
    if activeSessionID == nil {
      rejectionReason = lastInvalidatedSessionID == sessionID
        ? .invalidatedSession
        : .noActiveSession
    } else if activeSessionID != sessionID {
      rejectionReason = .wrongSession
    } else if !Self.hasVisibleText(chunk.text) {
      rejectionReason = .emptyText
    } else if chunk.text.count > maximumCharacterCount {
      rejectionReason = .textTooLong
    } else if let currentChunk, chunk.createdAt < currentChunk.createdAt {
      rejectionReason = .staleChunk
    } else {
      rejectionReason = nil
    }

    if let rejectionReason {
#if DEBUG
      chunksRejected += 1
      lastRejectionReason = rejectionReason
#endif
      AppLogger.tutorRuntime.notice(
        "Current content rejected id=\(chunk.id.uuidString, privacy: .public) session=\(sessionID.uuidString, privacy: .public) reason=\(rejectionReason.rawValue, privacy: .public) characters=\(chunk.text.count, privacy: .public) available=\(self.hasStableContent, privacy: .public)"
      )
      return .rejected(rejectionReason)
    }

    currentChunk = chunk
    hasStableContent = true
    lastInvalidatedSessionID = nil
#if DEBUG
    chunksAccepted += 1
    lastRejectionReason = nil
#endif
    AppLogger.tutorRuntime.debug(
      "Current content accepted id=\(chunk.id.uuidString, privacy: .public) session=\(sessionID.uuidString, privacy: .public) revision=\(chunk.sourceRevisionID, privacy: .public) confidence=\(chunk.confidence.rawValue, privacy: .public) flush=\(chunk.flushReason.rawValue, privacy: .public) characters=\(chunk.text.count, privacy: .public) available=true"
    )
    return .accepted
  }

  /// Converts the current Accessibility snapshot into one bounded, generic
  /// content excerpt for an explicit user request. Browser chrome and control
  /// descriptions are excluded without adding app-specific parsing rules.
  @discardableResult
  func receiveCurrentSnapshot(
    _ snapshot: AccessibleTextSnapshot,
    revisionID: Int,
    sessionID: UUID,
    createdAt: Date = Date()
  ) -> CurrentExplainableContentReceiveResult {
    let text = Self.boundedContentText(
      from: snapshot,
      maximumCharacterCount: maximumCharacterCount
    )
    return receive(
      SemanticChunk(
        id: UUID(),
        sourceRevisionID: revisionID,
        text: text,
        confidence: .high,
        createdAt: createdAt,
        flushReason: .manualFlush
      ),
      sessionID: sessionID
    )
  }

  func invalidateSession(
    _ sessionID: UUID? = nil,
    reason: CurrentExplainableContentInvalidationReason = .liveSessionEnded
  ) {
    if let sessionID, activeSessionID != sessionID {
      return
    }
    lastInvalidatedSessionID = activeSessionID
    activeSessionID = nil
    currentChunk = nil
    hasStableContent = false
#if DEBUG
    lastInvalidationReason = reason
#endif
    AppLogger.tutorRuntime.info(
      "Current content invalidated reason=\(reason.rawValue, privacy: .public) available=false"
    )
  }

  func currentSemanticChunk() throws -> SemanticChunk {
 #if DEBUG
    explainRequests += 1
 #endif
    guard activeSessionID != nil else {
      recordRetrieval(.noActiveSession)
      throw CurrentExplainableContentError.noStableContent
    }
    guard let currentChunk else {
      recordRetrieval(.noStableChunk)
      throw CurrentExplainableContentError.noStableContent
    }
    guard
      Self.hasVisibleText(currentChunk.text),
      currentChunk.text.count <= maximumCharacterCount
    else {
      recordRetrieval(.invalidCurrentChunk)
      throw CurrentExplainableContentError.noStableContent
    }
    recordRetrieval(.available, chunk: currentChunk)
    return currentChunk
  }

#if DEBUG
  var diagnosticSnapshot: CurrentExplainableContentDiagnosticSnapshot {
    CurrentExplainableContentDiagnosticSnapshot(
      providerInstanceIdentity: diagnosticInstanceIdentity,
      activeSessionID: activeSessionID,
      latestChunkID: currentChunk?.id,
      latestChunkRevision: currentChunk?.sourceRevisionID,
      latestConfidence: currentChunk?.confidence,
      latestFlushReason: currentChunk?.flushReason,
      latestCharacterCount: currentChunk?.text.count,
      isAvailable: hasStableContent,
      lastInvalidationReason: lastInvalidationReason,
      lastRejectionReason: lastRejectionReason,
      lastRetrievalResult: lastRetrievalResult,
      chunksReceived: chunksReceived,
      chunksAccepted: chunksAccepted,
      chunksRejected: chunksRejected,
      explainRequests: explainRequests
    )
  }
#endif

  private static func hasVisibleText(_ text: String) -> Bool {
    text.contains(where: { !$0.isWhitespace })
  }

  private static func boundedContentText(
    from snapshot: AccessibleTextSnapshot,
    maximumCharacterCount: Int
  ) -> String {
    let contentNodeText = snapshot.nodes.compactMap { node -> String? in
      guard
        !excludedControlRoles.contains(node.role ?? ""),
        node.sourceAttribute == .title
          || node.sourceAttribute == .value
          || node.sourceAttribute == .accessibilityDescription,
        hasVisibleText(node.text)
      else {
        return nil
      }
      return node.text
    }
    let candidate = contentNodeText.isEmpty
      ? snapshot.plainText
      : contentNodeText.joined(separator: "\n")
    let normalized = TextNormalizer().normalize(candidate).displayText
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard normalized.count > maximumCharacterCount else {
      return normalized
    }

    let suffix = String(normalized.suffix(maximumCharacterCount))
    guard
      let firstLineBreak = suffix.firstIndex(of: "\n"),
      firstLineBreak < suffix.index(before: suffix.endIndex)
    else {
      return suffix
    }
    let afterFirstLine = suffix[suffix.index(after: firstLineBreak)...]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return afterFirstLine.count >= maximumCharacterCount / 2
      ? afterFirstLine
      : suffix
  }

  private static let excludedControlRoles: Set<String> = [
    "AXButton",
    "AXCheckBox",
    "AXComboBox",
    "AXImage",
    "AXMenuItem",
    "AXPopUpButton",
    "AXRadioButton",
    "AXSecureTextField",
    "AXTab",
    "AXTextField",
    "AXToolbar",
  ]

  private func recordRetrieval(
    _ result: CurrentExplainableContentRetrievalResult,
    chunk: SemanticChunk? = nil
  ) {
#if DEBUG
    lastRetrievalResult = result
#endif
    if let chunk {
      AppLogger.tutorRuntime.info(
        "Current content retrieval result=\(result.rawValue, privacy: .public) id=\(chunk.id.uuidString, privacy: .public) revision=\(chunk.sourceRevisionID, privacy: .public) characters=\(chunk.text.count, privacy: .public)"
      )
    } else {
      AppLogger.tutorRuntime.notice(
        "Current content retrieval result=\(result.rawValue, privacy: .public) available=\(self.hasStableContent, privacy: .public)"
      )
    }
  }
}
