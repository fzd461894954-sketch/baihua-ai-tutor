import Foundation
import Observation

enum CurrentExplainableContentError: Error, Equatable, Sendable {
  case noStableContent
  case ambiguousContent
}

enum CurrentExplainableContentRejectionReason: String, Equatable, Sendable {
  case noActiveSession
  case invalidatedSession
  case wrongSession
  case emptyText
  case textTooLong
  case staleChunk
  case ambiguousContent
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

enum AXContentSelectionReason: String, Equatable, Sendable {
  case selectedText = "selected-text"
  case focusedElement = "focused-element"
  case focusedContainer = "focused-container"
  case latestVisibleContentContainer = "latest-visible-content-container"
  case singleCoherentCandidate = "single-coherent-candidate"
  case wholeSnapshotFallback = "whole-snapshot-fallback"
}

enum AXContentSelectionConfidence: String, Equatable, Sendable {
  case explicit
  case high
  case medium
  case fallback
}

enum AXContentTransportTrust: String, Equatable, Sendable {
  case strong
  case weak
  case ambiguous
}

struct AXContentSelectionEvidence: Equatable, Sendable {
  let userSelectedText: Bool
  let focusedElement: Bool
  let directlyFocusedContainer: Bool
  let provenance: AXContentSelectionReason
  let candidateCount: Int
  let candidateNodeCount: Int
  let independentRegionCount: Int
  let inferredOnly: Bool
}

struct AXContentCandidate: Equatable, Sendable {
  let id: String
  let containerNodeID: String
  let containerRole: String?
  let containerSubrole: String?
  let nodeIDs: [String]
  let text: String
  let firstTraversalIndex: Int
  let lastTraversalIndex: Int
  let frame: AccessibleFrameSnapshot?
  let containsSelectedText: Bool
  let containsSelectedElement: Bool
  let containsFocusedElement: Bool
  let containsFocusedContainer: Bool
  let containsDirectlyFocusedContainer: Bool
  let independentRegionCount: Int
  let isVisibleInWindow: Bool
  let relevanceScore: Int
}

struct AXContentCandidateEvaluation: Equatable, Sendable {
  let candidateID: String
  let score: Int
  let isSelected: Bool
  let reason: String
}

struct AXContentSelection: Equatable, Sendable {
  let candidates: [AXContentCandidate]
  let selectedCandidateID: String?
  let selectedText: String
  let reason: AXContentSelectionReason
  let confidence: AXContentSelectionConfidence
  let usedWholeSnapshotFallback: Bool
  let warnings: [String]
  let evaluations: [AXContentCandidateEvaluation]
  let excludedNodeCount: Int
  let exclusionSummary: [String: Int]

  var evidence: AXContentSelectionEvidence {
    let candidate = selectedCandidateID.flatMap { selectedID in
      candidates.first(where: { $0.id == selectedID })
    }
    let directlyFocusedContainer = candidate?.containsDirectlyFocusedContainer == true
    let userDirected = reason == .selectedText
      || reason == .focusedElement
      || (reason == .focusedContainer && directlyFocusedContainer)
    return AXContentSelectionEvidence(
      userSelectedText: reason == .selectedText,
      focusedElement: reason == .focusedElement,
      directlyFocusedContainer: directlyFocusedContainer,
      provenance: reason,
      candidateCount: candidates.count,
      candidateNodeCount: candidate?.nodeIDs.count ?? 0,
      independentRegionCount: candidate?.independentRegionCount ?? candidates.count,
      inferredOnly: !userDirected
    )
  }

  var transportTrust: AXContentTransportTrust {
    let evidence = evidence
    if usedWholeSnapshotFallback || selectedCandidateID == nil {
      return .ambiguous
    }
    if evidence.userSelectedText || evidence.focusedElement {
      return .strong
    }
    if evidence.independentRegionCount > 1 {
      return .ambiguous
    }
    if evidence.inferredOnly && evidence.candidateCount > 1 {
      return .ambiguous
    }
    if reason == .focusedContainer {
      if evidence.directlyFocusedContainer,
         let selectedCandidateID,
         let candidate = candidates.first(where: { $0.id == selectedCandidateID }) {
        if evidence.candidateCount == 1
          || Self.userDirectedContainerRoles.contains(candidate.containerRole ?? "") {
          return .strong
        }
        return .ambiguous
      }
      if evidence.candidateCount == 1,
         evidence.candidateNodeCount == 1,
         evidence.independentRegionCount == 1 {
        return .weak
      }
      return .ambiguous
    }
    return .weak
  }

  private static let userDirectedContainerRoles: Set<String> = [
    "AXArticle",
    "AXCell",
    "AXListItem",
    "AXRow",
    "AXSection",
  ]
}

/// Segments flattened AX text by structural provenance before deciding what a
/// user meant by "current content". It uses generic AX roles, ancestry,
/// traversal order, focus/selection and window geometry only.
struct AXCurrentContentCandidateSelector {
  func select(from snapshot: AccessibleTextSnapshot) -> AXContentSelection {
    let classified = classifyNodes(snapshot.nodes)
    let candidates = makeCandidates(from: classified.included)

    guard !candidates.isEmpty else {
      return fallback(
        snapshot: snapshot,
        candidates: [],
        excludedNodeCount: classified.excludedCount,
        exclusionSummary: classified.exclusionSummary,
        warning: "No explainable AX content candidate remained after generic role filtering."
      )
    }

    let selectedTextCandidates = candidates.filter(\.containsSelectedText)
    if let candidate = mostRecent(selectedTextCandidates) {
      let selectedText = selectedText(in: candidate, nodes: classified.included)
      return selected(
        candidate,
        text: selectedText.isEmpty ? candidate.text : selectedText,
        reason: .selectedText,
        confidence: .explicit,
        candidates: candidates,
        excludedNodeCount: classified.excludedCount,
        exclusionSummary: classified.exclusionSummary
      )
    }

    if let candidate = mostRecent(candidates.filter(\.containsSelectedElement)) {
      return selected(
        candidate,
        reason: .selectedText,
        confidence: .explicit,
        candidates: candidates,
        excludedNodeCount: classified.excludedCount,
        exclusionSummary: classified.exclusionSummary
      )
    }

    if let candidate = mostRecent(candidates.filter(\.containsFocusedElement)) {
      let focusedText = focusedText(in: candidate, nodes: classified.included)
      return selected(
        candidate,
        text: focusedText.isEmpty ? candidate.text : focusedText,
        reason: .focusedElement,
        confidence: .explicit,
        candidates: candidates,
        excludedNodeCount: classified.excludedCount,
        exclusionSummary: classified.exclusionSummary
      )
    }

    if let candidate = mostRecent(candidates.filter(\.containsFocusedContainer)) {
      return selected(
        candidate,
        reason: .focusedContainer,
        confidence: .high,
        candidates: candidates,
        excludedNodeCount: classified.excludedCount,
        exclusionSummary: classified.exclusionSummary
      )
    }

    if candidates.count == 1, let candidate = candidates.first {
      return selected(
        candidate,
        reason: .singleCoherentCandidate,
        confidence: .high,
        candidates: candidates,
        excludedNodeCount: classified.excludedCount,
        exclusionSummary: classified.exclusionSummary
      )
    }

    let visibleCandidates = candidates.filter(\.isVisibleInWindow)
    if let winner = rankedVisibleWinner(visibleCandidates) {
      return selected(
        winner,
        reason: .latestVisibleContentContainer,
        confidence: .medium,
        candidates: candidates,
        excludedNodeCount: classified.excludedCount,
        exclusionSummary: classified.exclusionSummary
      )
    }

    return fallback(
      snapshot: snapshot,
      candidates: candidates,
      excludedNodeCount: classified.excludedCount,
      exclusionSummary: classified.exclusionSummary,
      warning: "Multiple coherent candidates had no reliable selection, focus, or window-visibility evidence."
    )
  }

  private typealias ClassifiedNodes = (
    included: [AccessibleTextNode],
    excludedCount: Int,
    exclusionSummary: [String: Int]
  )

  private func classifyNodes(_ nodes: [AccessibleTextNode]) -> ClassifiedNodes {
    let containerNodeIDs = Set(
      nodes.flatMap { $0.ancestorPath.map(\.debugNodeID) }
    )
    var included: [AccessibleTextNode] = []
    var summary: [String: Int] = [:]

    for node in nodes {
      let reason: String?
      if !node.text.contains(where: { !$0.isWhitespace }) {
        reason = "empty-text"
      } else if node.sourceAttribute == .help {
        reason = "help-attribute"
      } else if (Self.controlRoles.contains(node.role ?? "")
        || node.ancestorPath.contains(where: { Self.controlRoles.contains($0.role ?? "") }))
        && !Self.isFocusedExplainableTextEntry(node) {
        reason = "control-role-or-ancestor"
      } else if containerNodeIDs.contains(node.debugNodeID)
        && Self.containerRoles.contains(node.role ?? "") {
        // Container values in Chromium often repeat the text later exposed by
        // their descendants. Descendant segments carry the finer provenance.
        reason = "aggregate-container-text"
      } else {
        reason = nil
      }

      if let reason {
        summary[reason, default: 0] += 1
      } else {
        included.append(node)
      }
    }
    return (included, nodes.count - included.count, summary)
  }

  private func makeCandidates(from nodes: [AccessibleTextNode]) -> [AXContentCandidate] {
    guard !nodes.isEmpty else {
      return []
    }

    let commonPath = commonAncestorPath(nodes)
    let sharedContainerIsCoherent = isCoherentSharedContainer(commonPath)
    var groups: [String: [AccessibleTextNode]] = [:]
    var containers: [String: AccessibleNodePathComponent] = [:]
    var order: [String] = []

    for node in nodes {
      let container: AccessibleNodePathComponent?
      if sharedContainerIsCoherent {
        container = commonPath.last
      } else if node.ancestorPath.count > commonPath.count {
        container = node.ancestorPath[commonPath.count]
      } else if let strongContainer = node.ancestorPath.dropFirst().first(where: {
        Self.strongContainerRoles.contains($0.role ?? "")
      }) {
        container = strongContainer
      } else {
        container = nil
      }

      let key = container?.debugNodeID ?? node.debugNodeID
      if groups[key] == nil {
        order.append(key)
      }
      if let container {
        containers[key] = container
      }
      groups[key, default: []].append(node)
    }

    return order.compactMap { key in
      guard let groupNodes = groups[key], !groupNodes.isEmpty else {
        return nil
      }
      return makeCandidate(
        containerNodeID: key,
        container: containers[key],
        nodes: groupNodes
      )
    }
  }

  private func makeCandidate(
    containerNodeID: String,
    container: AccessibleNodePathComponent?,
    nodes: [AccessibleTextNode]
  ) -> AXContentCandidate {
    let ordered = nodes.sorted {
      if $0.traversalIndex == $1.traversalIndex {
        return Self.attributeOrder($0.sourceAttribute)
          < Self.attributeOrder($1.sourceAttribute)
      }
      return $0.traversalIndex < $1.traversalIndex
    }
    let selectedNodeIDs = Set(
      ordered.lazy.filter { $0.sourceAttribute == .selectedText }.map(\.debugNodeID)
    )
    let regularNodeIDs = Set(
      ordered.lazy.filter { $0.sourceAttribute != .selectedText }.map(\.debugNodeID)
    )
    var seenAttributeTextByNode: [String: Set<String>] = [:]
    let textSegments = ordered.compactMap { node -> String? in
      if node.sourceAttribute == .selectedText,
         regularNodeIDs.contains(node.debugNodeID) {
        return nil
      }
      if seenAttributeTextByNode[node.debugNodeID, default: []].contains(node.text) {
        return nil
      }
      seenAttributeTextByNode[node.debugNodeID, default: []].insert(node.text)
      return node.text
    }
    let text = textSegments.joined(separator: "\n")
    let frame = ordered.compactMap(\.frame).reduce(nil as CGRect?) { partial, next in
      partial.map { $0.union(next.cgRect) } ?? next.cgRect
    }.map(AccessibleFrameSnapshot.init)
    let nodeIDs = ordered.map(\.debugNodeID).reduce(into: [String]()) { result, id in
      if result.last != id, !result.contains(id) {
        result.append(id)
      }
    }
    let containsFocusedElement = ordered.contains { $0.isFocused == true }
    let containsFocusedContainer = ordered.contains { node in
      node.ancestorPath.contains(where: { $0.isFocused == true })
    }
    let containsDirectlyFocusedContainer = ordered.contains { node in
      node.ancestorPath.contains(where: {
        $0.debugNodeID == containerNodeID && $0.isFocused == true
      })
    }
    let containsSelectedElement = ordered.contains { node in
      node.isSelected == true
        || node.ancestorPath.contains(where: { $0.isSelected == true })
    }
    let isVisible = ordered.contains { node in
      guard node.isVisible != false else {
        return false
      }
      return node.isVisible == true
        || node.windowGeometryRelationship == .containedInWindow
        || node.windowGeometryRelationship == .intersectsWindow
    }
    let relevanceScore = Self.relevanceScore(text)
    let suffix = Self.fingerprint(containerNodeID + "\u{1f}" + nodeIDs.joined(separator: "|"))

    return AXContentCandidate(
      id: "AXC-\(String(suffix.prefix(10)))",
      containerNodeID: containerNodeID,
      containerRole: container?.role
        ?? ordered.first(where: { $0.debugNodeID == containerNodeID })?.role,
      containerSubrole: container?.subrole
        ?? ordered.first(where: { $0.debugNodeID == containerNodeID })?.subrole,
      nodeIDs: nodeIDs,
      text: text,
      firstTraversalIndex: ordered.map(\.traversalIndex).min() ?? 0,
      lastTraversalIndex: ordered.map(\.traversalIndex).max() ?? 0,
      frame: frame,
      containsSelectedText: !selectedNodeIDs.isEmpty,
      containsSelectedElement: containsSelectedElement,
      containsFocusedElement: containsFocusedElement,
      containsFocusedContainer: containsFocusedContainer,
      containsDirectlyFocusedContainer: containsDirectlyFocusedContainer,
      independentRegionCount: independentRegionCount(
        containerNodeID: containerNodeID,
        containerRole: container?.role,
        nodes: ordered
      ),
      isVisibleInWindow: isVisible,
      relevanceScore: relevanceScore
    )
  }

  private func independentRegionCount(
    containerNodeID: String,
    containerRole: String?,
    nodes: [AccessibleTextNode]
  ) -> Int {
    if Self.strongContainerRoles.contains(containerRole ?? "") {
      return 1
    }

    var structuralRegionIDs: Set<String> = []
    var hasContentOutsideStructuralRegion = false
    for node in nodes {
      guard let containerIndex = node.ancestorPath.firstIndex(where: {
        $0.debugNodeID == containerNodeID
      }) else {
        hasContentOutsideStructuralRegion = true
        continue
      }
      let descendants = node.ancestorPath.dropFirst(containerIndex + 1)
      if let region = descendants.first(where: {
        Self.independentRegionRoles.contains($0.role ?? "")
      }) {
        structuralRegionIDs.insert(region.debugNodeID)
      } else {
        hasContentOutsideStructuralRegion = true
      }
    }

    guard !structuralRegionIDs.isEmpty else {
      return 1
    }
    return structuralRegionIDs.count + (hasContentOutsideStructuralRegion ? 1 : 0)
  }

  private func commonAncestorPath(
    _ nodes: [AccessibleTextNode]
  ) -> [AccessibleNodePathComponent] {
    guard var common = nodes.first?.ancestorPath else {
      return []
    }
    for node in nodes.dropFirst() {
      let limit = min(common.count, node.ancestorPath.count)
      var matchingCount = 0
      while matchingCount < limit,
            common[matchingCount].debugNodeID
              == node.ancestorPath[matchingCount].debugNodeID {
        matchingCount += 1
      }
      common = Array(common.prefix(matchingCount))
      if common.isEmpty {
        break
      }
    }
    return common
  }

  private func isCoherentSharedContainer(
    _ commonPath: [AccessibleNodePathComponent]
  ) -> Bool {
    guard commonPath.count > 1, let candidate = commonPath.last else {
      return false
    }
    if Self.strongContainerRoles.contains(candidate.role ?? "") {
      return true
    }
    guard
      Self.containerRoles.contains(candidate.role ?? ""),
      let rootFrame = commonPath.first?.frame?.cgRect,
      let candidateFrame = candidate.frame?.cgRect,
      rootFrame.width > 0,
      rootFrame.height > 0
    else {
      return false
    }
    let rootArea = rootFrame.width * rootFrame.height
    let candidateArea = candidateFrame.width * candidateFrame.height
    return candidateArea / rootArea <= 0.78
  }

  private func selectedText(
    in candidate: AXContentCandidate,
    nodes: [AccessibleTextNode]
  ) -> String {
    nodes
      .filter {
        candidate.nodeIDs.contains($0.debugNodeID)
          && $0.sourceAttribute == .selectedText
      }
      .sorted { $0.traversalIndex < $1.traversalIndex }
      .map(\.text)
      .joined(separator: "\n")
  }

  private func focusedText(
    in candidate: AXContentCandidate,
    nodes: [AccessibleTextNode]
  ) -> String {
    nodes
      .filter {
        candidate.nodeIDs.contains($0.debugNodeID)
          && $0.isFocused == true
          && $0.sourceAttribute != .help
          && $0.sourceAttribute != .accessibilityDescription
      }
      .sorted { $0.traversalIndex < $1.traversalIndex }
      .map(\.text)
      .reduce(into: [String]()) { result, text in
        if !result.contains(text) {
          result.append(text)
        }
      }
      .joined(separator: "\n")
  }

  private func mostRecent(_ candidates: [AXContentCandidate]) -> AXContentCandidate? {
    candidates.max { lhs, rhs in
      lhs.lastTraversalIndex < rhs.lastTraversalIndex
    }
  }

  private func rankedVisibleWinner(
    _ candidates: [AXContentCandidate]
  ) -> AXContentCandidate? {
    guard !candidates.isEmpty else {
      return nil
    }
    let traversalOrder = candidates.sorted {
      $0.lastTraversalIndex < $1.lastTraversalIndex
    }
    let ranked = traversalOrder.enumerated().map { index, candidate in
      (candidate: candidate, score: candidate.relevanceScore + index * 45)
    }.sorted {
      if $0.score == $1.score {
        return $0.candidate.lastTraversalIndex > $1.candidate.lastTraversalIndex
      }
      return $0.score > $1.score
    }
    guard let winner = ranked.first else {
      return nil
    }
    if ranked.count == 1 {
      return winner.candidate
    }
    return winner.score - ranked[1].score >= 20 ? winner.candidate : nil
  }

  private func selected(
    _ candidate: AXContentCandidate,
    text: String? = nil,
    reason: AXContentSelectionReason,
    confidence: AXContentSelectionConfidence,
    candidates: [AXContentCandidate],
    excludedNodeCount: Int,
    exclusionSummary: [String: Int]
  ) -> AXContentSelection {
    AXContentSelection(
      candidates: candidates,
      selectedCandidateID: candidate.id,
      selectedText: text ?? candidate.text,
      reason: reason,
      confidence: confidence,
      usedWholeSnapshotFallback: false,
      warnings: [],
      evaluations: evaluations(
        candidates: candidates,
        selectedID: candidate.id,
        selectedReason: reason.rawValue
      ),
      excludedNodeCount: excludedNodeCount,
      exclusionSummary: exclusionSummary
    )
  }

  private func fallback(
    snapshot: AccessibleTextSnapshot,
    candidates: [AXContentCandidate],
    excludedNodeCount: Int,
    exclusionSummary: [String: Int],
    warning: String
  ) -> AXContentSelection {
    AXContentSelection(
      candidates: candidates,
      selectedCandidateID: nil,
      selectedText: snapshot.plainText,
      reason: .wholeSnapshotFallback,
      confidence: .fallback,
      usedWholeSnapshotFallback: true,
      warnings: ["Whole Snapshot Fallback: \(warning)"],
      evaluations: evaluations(
        candidates: candidates,
        selectedID: nil,
        selectedReason: AXContentSelectionReason.wholeSnapshotFallback.rawValue
      ),
      excludedNodeCount: excludedNodeCount,
      exclusionSummary: exclusionSummary
    )
  }

  private func evaluations(
    candidates: [AXContentCandidate],
    selectedID: String?,
    selectedReason: String
  ) -> [AXContentCandidateEvaluation] {
    let ordered = candidates.sorted { $0.lastTraversalIndex < $1.lastTraversalIndex }
    return ordered.enumerated().map { index, candidate in
      let score = candidate.relevanceScore + (candidate.isVisibleInWindow ? index * 45 : 0)
      let selected = candidate.id == selectedID
      return AXContentCandidateEvaluation(
        candidateID: candidate.id,
        score: score,
        isSelected: selected,
        reason: selected
          ? selectedReason
          : (selectedID == nil
            ? "rejected · insufficient deterministic evidence"
            : "rejected · lower selection priority or rank")
      )
    }
  }

  private static func attributeOrder(
    _ attribute: AccessibilityTextSourceAttribute
  ) -> Int {
    switch attribute {
    case .title: return 0
    case .value: return 1
    case .accessibilityDescription: return 2
    case .help: return 3
    case .selectedText: return 4
    }
  }

  private static func relevanceScore(_ text: String) -> Int {
    let lineScore = min(text.components(separatedBy: "\n").count * 3, 90)
    let structureCharacters = text.reduce(into: 0) { count, character in
      if "{}[]();,:".contains(character) {
        count += 1
      }
    }
    let structureScore = min(structureCharacters * 2, 140)
    let lengthScore = min(text.count / 5, 180)
    return lineScore + structureScore + lengthScore
  }

  /// A focused multiline editor is an explicit user target, not ambient UI.
  /// Keep unfocused composers, placeholders, address fields and other controls
  /// excluded so they cannot compete with page content.
  private static func isFocusedExplainableTextEntry(
    _ node: AccessibleTextNode
  ) -> Bool {
    guard
      node.role == "AXTextArea",
      node.isFocused == true,
      node.sourceAttribute == .value || node.sourceAttribute == .selectedText
    else {
      return false
    }
    return node.text.contains(where: { !$0.isWhitespace })
  }

  private static func fingerprint(_ text: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
  }

  private static let containerRoles: Set<String> = [
    "AXArticle",
    "AXCell",
    "AXGroup",
    "AXList",
    "AXListItem",
    "AXRow",
    "AXScrollArea",
    "AXSection",
    "AXWebArea",
  ]

  private static let strongContainerRoles: Set<String> = [
    "AXArticle",
    "AXCell",
    "AXListItem",
    "AXRow",
    "AXSection",
  ]

  private static let independentRegionRoles: Set<String> = strongContainerRoles.union([
    "AXList",
  ])

  private static let controlRoles: Set<String> = [
    "AXButton",
    "AXCheckBox",
    "AXComboBox",
    "AXImage",
    "AXMenu",
    "AXMenuBar",
    "AXMenuItem",
    "AXPopUpButton",
    "AXRadioButton",
    "AXScrollBar",
    "AXSecureTextField",
    "AXSplitter",
    "AXTab",
    "AXTabGroup",
    "AXTextArea",
    "AXTextField",
    "AXToolbar",
  ]
}

struct StructureAwareLongContentDecision: Equatable, Sendable {
  let text: String
  let metadata: SemanticContentLengthMetadata
}

/// Applies the Tutor transport budget only after Current Content selection and
/// trust have succeeded. V1 intentionally uses no language parser and no
/// inferred caret position: it chooses a deterministic prefix ending at the
/// strongest supported structural boundary and labels every shortened result
/// as an excerpt.
struct StructureAwareLongContentPolicy: Sendable {
  private enum ContentShape {
    case codeLike
    case naturalLanguage
    case mixed
  }

  let maximumCharacterCount: Int

  init(
    maximumCharacterCount: Int = TutorRequest.defaultMaximumSourceCharacterCount
  ) {
    self.maximumCharacterCount = max(1, maximumCharacterCount)
  }

  func apply(
    to candidate: String,
    selectionReason: AXContentSelectionReason
  ) -> StructureAwareLongContentDecision {
    let normalized = TextNormalizer().normalize(candidate).displayText
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let shape = Self.contentShape(of: normalized)
    let contentType = Self.contentType(
      selectionReason: selectionReason,
      shape: shape
    )

    guard normalized.count > maximumCharacterCount else {
      return StructureAwareLongContentDecision(
        text: normalized,
        metadata: SemanticContentLengthMetadata(
          contentType: contentType,
          completeness: .complete,
          lengthPolicy: .complete,
          originalCharacterCount: candidate.count,
          normalizedCharacterCount: normalized.count,
          sentCharacterCount: normalized.count,
          excerptStart: 0,
          excerptEnd: normalized.count,
          droppedPrefixCount: 0,
          droppedSuffixCount: 0,
          structureBoundary: .complete
        )
      )
    }

    let characters = Array(normalized)
    let boundary = Self.excerptBoundary(
      in: characters,
      maximumCharacterCount: maximumCharacterCount,
      shape: shape
    )
    let excerptEnd = max(1, min(boundary.end, maximumCharacterCount))
    let excerpt = String(characters[..<excerptEnd])
    let lengthPolicy: SemanticContentLengthPolicy
    if selectionReason == .selectedText {
      lengthPolicy = .longSelectionExcerpt
    } else {
      switch shape {
      case .codeLike:
        lengthPolicy = .structureAwareCodeExcerpt
      case .naturalLanguage:
        lengthPolicy = .structureAwareProseExcerpt
      case .mixed:
        lengthPolicy = .boundedMixedExcerpt
      }
    }

    return StructureAwareLongContentDecision(
      text: excerpt,
      metadata: SemanticContentLengthMetadata(
        contentType: contentType,
        completeness: .excerpt,
        lengthPolicy: lengthPolicy,
        originalCharacterCount: candidate.count,
        normalizedCharacterCount: normalized.count,
        sentCharacterCount: excerpt.count,
        excerptStart: 0,
        excerptEnd: excerptEnd,
        droppedPrefixCount: 0,
        droppedSuffixCount: normalized.count - excerptEnd,
        structureBoundary: boundary.kind
      )
    )
  }

  private static func contentType(
    selectionReason: AXContentSelectionReason,
    shape: ContentShape
  ) -> SemanticContentType {
    if selectionReason == .selectedText {
      return .explicitSelectedText
    }
    guard selectionReason == .focusedElement else {
      return .unknownMixed
    }
    switch shape {
    case .codeLike:
      return .focusedCodeLike
    case .naturalLanguage:
      return .focusedNaturalLanguage
    case .mixed:
      return .unknownMixed
    }
  }

  private static func contentShape(of text: String) -> ContentShape {
    let lines = text.components(separatedBy: .newlines)
    let declarationPrefixes = [
      "func ", "function ", "class ", "struct ", "enum ", "protocol ",
      "interface ", "def ", "async func ", "async function ", "import ",
      "from ", "let ", "var ", "const ", "#include ", "public ",
      "private ", "internal ", "extension ",
    ]
    var codeScore = text.contains("```") ? 5 : 0
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if declarationPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
        codeScore += 2
      }
      if trimmed.hasSuffix(";") || trimmed.hasSuffix("{") || trimmed == "}" {
        codeScore += 1
      }
      if line.first?.isWhitespace == true, !trimmed.isEmpty {
        codeScore += 1
      }
      if codeScore >= 6 {
        return .codeLike
      }
    }

    let sentenceCount = text.reduce(into: 0) { count, character in
      if ".。！？!?".contains(character) {
        count += 1
      }
    }
    let paragraphCount = text.components(separatedBy: "\n\n").count
    if sentenceCount >= 2 || paragraphCount >= 2 {
      return .naturalLanguage
    }
    return .mixed
  }

  private static func excerptBoundary(
    in characters: [Character],
    maximumCharacterCount: Int,
    shape: ContentShape
  ) -> (end: Int, kind: SemanticContentStructureBoundary) {
    switch shape {
    case .codeLike:
      if let end = codeBlockBoundary(
        in: characters,
        maximumCharacterCount: maximumCharacterCount
      ) {
        return (end, .codeBlock)
      }
    case .naturalLanguage:
      if let end = paragraphBoundary(
        in: characters,
        maximumCharacterCount: maximumCharacterCount
      ) {
        return (end, .paragraph)
      }
      if let end = sentenceBoundary(
        in: characters,
        maximumCharacterCount: maximumCharacterCount
      ) {
        return (end, .sentence)
      }
    case .mixed:
      if let end = paragraphBoundary(
        in: characters,
        maximumCharacterCount: maximumCharacterCount
      ), end >= maximumCharacterCount / 2 {
        return (end, .paragraph)
      }
      if let end = sentenceBoundary(
        in: characters,
        maximumCharacterCount: maximumCharacterCount
      ), end >= maximumCharacterCount / 2 {
        return (end, .sentence)
      }
    }

    if let end = newlineBoundary(
      in: characters,
      maximumCharacterCount: maximumCharacterCount
    ) {
      return (end, .newline)
    }
    if let end = wordBoundary(
      in: characters,
      maximumCharacterCount: maximumCharacterCount
    ) {
      return (end, .word)
    }
    return (maximumCharacterCount, .characterBudget)
  }

  private static func codeBlockBoundary(
    in characters: [Character],
    maximumCharacterCount: Int
  ) -> Int? {
    var braceDepth = 0
    var lastSignificantCharacter: Character?
    var lastSignificantEnd = 0
    var boundaries: [Int] = []
    let upperBound = min(maximumCharacterCount, characters.count)

    for index in 0..<upperBound {
      let character = characters[index]
      if "{[(".contains(character) {
        braceDepth += 1
      } else if "}])".contains(character) {
        braceDepth = max(0, braceDepth - 1)
      }
      if !character.isWhitespace {
        lastSignificantCharacter = character
        lastSignificantEnd = index + 1
      }
      if character == "\n", braceDepth == 0,
         lastSignificantCharacter == "}" || lastSignificantCharacter == ";" {
        boundaries.append(lastSignificantEnd)
      }
    }

    guard let boundary = boundaries.last,
          boundary >= maximumCharacterCount / 2 else {
      return nil
    }
    return boundary
  }

  private static func paragraphBoundary(
    in characters: [Character],
    maximumCharacterCount: Int
  ) -> Int? {
    let upperBound = min(maximumCharacterCount, characters.count)
    guard upperBound > 1 else { return nil }
    var lastNonWhitespaceEnd = 0
    var boundary: Int?
    for index in 0..<upperBound {
      if !characters[index].isWhitespace {
        lastNonWhitespaceEnd = index + 1
      }
      if index > 0, characters[index] == "\n", characters[index - 1] == "\n" {
        boundary = lastNonWhitespaceEnd
      }
    }
    return boundary
  }

  private static func sentenceBoundary(
    in characters: [Character],
    maximumCharacterCount: Int
  ) -> Int? {
    let terminators = ".。！？!?"
    let upperBound = min(maximumCharacterCount, characters.count)
    return (0..<upperBound).last(where: { terminators.contains(characters[$0]) })
      .map { $0 + 1 }
  }

  private static func newlineBoundary(
    in characters: [Character],
    maximumCharacterCount: Int
  ) -> Int? {
    let upperBound = min(maximumCharacterCount, characters.count)
    var lastNonWhitespaceEnd = 0
    var boundary: Int?
    for index in 0..<upperBound {
      if !characters[index].isWhitespace {
        lastNonWhitespaceEnd = index + 1
      }
      if characters[index] == "\n", lastNonWhitespaceEnd > 0 {
        boundary = lastNonWhitespaceEnd
      }
    }
    return boundary
  }

  private static func wordBoundary(
    in characters: [Character],
    maximumCharacterCount: Int
  ) -> Int? {
    let upperBound = min(maximumCharacterCount, characters.count)
    guard upperBound > 0 else { return nil }
    for index in (0..<upperBound).reversed() where characters[index].isWhitespace {
      if index > 0 {
        return index
      }
    }
    return nil
  }
}

/// Keeps only the latest stable SemanticChunk owned by the active AX live
/// session. It has no history, snapshot body, revision archive, or persistence.
@MainActor
@Observable
final class CurrentExplainableContentProvider: TutorCurrentContentProviding {
  private(set) var activeSessionID: UUID?
  private(set) var hasStableContent = false
  private(set) var latestContentSelection: AXContentSelection?

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
    self.maximumCharacterCount = min(
      TutorRequest.defaultMaximumSourceCharacterCount,
      max(1, maximumCharacterCount)
    )
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
    latestContentSelection = nil
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
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)
    latestContentSelection = selection
    if selection.transportTrust == .ambiguous {
      return rejectAmbiguousSnapshot(
        sessionID: sessionID,
        characterCount: snapshot.characterCount
      )
    }
    let lengthDecision = StructureAwareLongContentPolicy(
      maximumCharacterCount: maximumCharacterCount
    ).apply(
      to: selection.selectedText,
      selectionReason: selection.reason
    )
    return receive(
      SemanticChunk(
        id: UUID(),
        sourceRevisionID: revisionID,
        text: lengthDecision.text,
        confidence: .high,
        createdAt: createdAt,
        flushReason: .manualFlush,
        contentLength: lengthDecision.metadata
      ),
      sessionID: sessionID
    )
  }

  private func rejectAmbiguousSnapshot(
    sessionID: UUID,
    characterCount: Int
  ) -> CurrentExplainableContentReceiveResult {
#if DEBUG
    chunksReceived += 1
#endif
    let reason: CurrentExplainableContentRejectionReason
    if activeSessionID == nil {
      reason = lastInvalidatedSessionID == sessionID
        ? .invalidatedSession
        : .noActiveSession
    } else if activeSessionID != sessionID {
      reason = .wrongSession
    } else {
      reason = .ambiguousContent
      currentChunk = nil
      hasStableContent = false
    }
#if DEBUG
    chunksRejected += 1
    lastRejectionReason = reason
#endif
    AppLogger.tutorRuntime.notice(
      "Current snapshot rejected session=\(sessionID.uuidString, privacy: .public) reason=\(reason.rawValue, privacy: .public) characters=\(characterCount, privacy: .public) available=\(self.hasStableContent, privacy: .public)"
    )
    return .rejected(reason)
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
    latestContentSelection = nil
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
