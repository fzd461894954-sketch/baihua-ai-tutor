#if DEBUG
import Darwin
import Foundation
import Observation
import SwiftUI

enum TutorDebugTransportDecision: String, Equatable, Sendable {
  case allowed = "ALLOWED"
  case blockedAmbiguousContent = "BLOCKED · ambiguous content"
}

enum TutorCurrentContentQAOutcome: String, CaseIterable, Equatable, Sendable {
  case allowedSelectedText = "allowed · selected-text"
  case allowedFocusedElement = "allowed · focused-element"
  case allowedExplicitCandidate = "allowed · explicit candidate"
  case blockedAmbiguousContent = "blocked · ambiguous content"
  case blockedWholeSnapshotFallback = "blocked · whole snapshot fallback"
  case emptyNoExplainableContent = "empty · no explainable content"
  case rejectedUnsupported = "rejected · unsupported"

  static func classify(
    transportDecision: TutorDebugTransportDecision,
    selection: AXContentSelection?,
    currentTutorInput: String
  ) -> Self {
    if transportDecision == .blockedAmbiguousContent {
      return selection?.usedWholeSnapshotFallback == true
        ? .blockedWholeSnapshotFallback
        : .blockedAmbiguousContent
    }
    guard currentTutorInput.contains(where: { !$0.isWhitespace }) else {
      return selection == nil ? .emptyNoExplainableContent : .rejectedUnsupported
    }
    guard let selection else {
      return .rejectedUnsupported
    }
    switch selection.reason {
    case .selectedText:
      return .allowedSelectedText
    case .focusedElement:
      return .allowedFocusedElement
    case .focusedContainer, .latestVisibleContentContainer, .singleCoherentCandidate:
      return .allowedExplicitCandidate
    case .wholeSnapshotFallback:
      return .rejectedUnsupported
    }
  }

  var isAllowed: Bool {
    switch self {
    case .allowedSelectedText, .allowedFocusedElement, .allowedExplicitCandidate:
      return true
    case .blockedAmbiguousContent, .blockedWholeSnapshotFallback,
         .emptyNoExplainableContent, .rejectedUnsupported:
      return false
    }
  }

  var isAmbiguousBlock: Bool {
    self == .blockedAmbiguousContent || self == .blockedWholeSnapshotFallback
  }
}

enum TutorCurrentContentQAJudgment: String, CaseIterable, Equatable, Identifiable, Sendable {
  case correct
  case incorrect
  case blockedAsExpected = "blocked-as-expected"
  case unexpectedBlock = "unexpected-block"
  case notEvaluable = "not-evaluable"

  var id: String { rawValue }

  var isEvaluable: Bool { self != .notEvaluable }
}

struct TutorCurrentContentQAMetrics: Equatable, Sendable {
  let totalAttempts: Int
  let evaluableAttempts: Int
  let allowedCount: Int
  let blockedAmbiguousCount: Int
  let emptyCount: Int
  let correctSelectionCount: Int
  let incorrectSelectionCount: Int
  let unexpectedBlockCount: Int
  let selectionAccuracy: Double?
  let directExplainCoverage: Double?
  let ambiguousRejectionRate: Double?
  let unexpectedBlockRate: Double?

  init(traces: [TutorDebugTrace]) {
    let evaluable = traces.filter { $0.qaJudgment.isEvaluable }
    totalAttempts = traces.count
    evaluableAttempts = evaluable.count
    allowedCount = traces.filter { $0.qaOutcome.isAllowed }.count
    blockedAmbiguousCount = traces.filter { $0.qaOutcome.isAmbiguousBlock }.count
    emptyCount = traces.filter { $0.qaOutcome == .emptyNoExplainableContent }.count
    correctSelectionCount = traces.filter { $0.qaJudgment == .correct }.count
    incorrectSelectionCount = traces.filter { $0.qaJudgment == .incorrect }.count
    unexpectedBlockCount = traces.filter { $0.qaJudgment == .unexpectedBlock }.count

    let selectionDenominator = correctSelectionCount + incorrectSelectionCount
    selectionAccuracy = Self.ratio(correctSelectionCount, selectionDenominator)
    directExplainCoverage = Self.ratio(
      evaluable.filter { $0.qaOutcome.isAllowed }.count,
      evaluableAttempts
    )
    ambiguousRejectionRate = Self.ratio(
      evaluable.filter { $0.qaOutcome.isAmbiguousBlock }.count,
      evaluableAttempts
    )
    unexpectedBlockRate = Self.ratio(unexpectedBlockCount, evaluableAttempts)
  }

  private static func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
    denominator == 0 ? nil : Double(numerator) / Double(denominator)
  }
}

enum TutorCurrentContentQAMarker {
  static let markers = [
    "AX_OLD_ONLY_MARKER",
    "AX_CURRENT_ONLY_MARKER",
    "AX_OTHER_ONLY_MARKER",
    "AX_BLOCK_A",
    "AX_BLOCK_B",
  ]

  static func matches(in text: String) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: markers.map { marker in
      (marker, occurrences(of: marker, in: text))
    })
  }

  static func description(in text: String) -> String {
    let counts = matches(in: text)
    return markers.map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: " ")
  }

  private static func occurrences(of needle: String, in text: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchRange = text.startIndex..<text.endIndex
    while let range = text.range(of: needle, range: searchRange) {
      count += 1
      searchRange = range.upperBound..<text.endIndex
    }
    return count
  }
}

struct TutorDebugTrace: Identifiable, Equatable {
  let id: UUID
  let tutorRequestID: String
  let requestCreatedAt: Date
  let requestSequence: Int

  let sourceApplication: String?
  let bundleIdentifier: String?
  let processIdentifier: pid_t?
  let focusedWindow: String?
  let focusedWindowToken: String?
  let snapshotSource: String
  let contextRevisionID: Int
  let snapshotTimestamp: Date?
  let snapshotWasTruncated: Bool

  let rawSnapshot: String
  let axNodes: [AccessibleTextNode]
  let contentSelection: AXContentSelection?
  let normalizedText: String
  let previousBaseline: String
  let currentSnapshot: String
  let detectedAddedText: String
  let detectedRemovedText: String
  let detectedStableText: String
  let diffKind: String

  let bufferBefore: String
  let incomingDiff: String
  let bufferAfter: String
  let commitReason: String
  let commitTimestamp: Date?
  let bufferTransitionReason: String?

  let currentTutorInput: String
  let currentContentSourceCharacterCount: Int
  let currentContentWasTruncated: Bool
  let contentLength: SemanticContentLengthMetadata?
  let systemInstruction: String
  let internalConstraints: [String]
  let history: [TutorPromptMessage]
  let currentUserInput: String
  let conversationMode: TutorConversationMode
  let transportDecision: TutorDebugTransportDecision
  var qaJudgment: TutorCurrentContentQAJudgment

  var transportRequest: TutorTransportRequestDebugSnapshot?
  var transportResponse: TutorTransportResponseDebugSnapshot?
  var latencyMetrics: TutorLatencyMetrics?
  var contaminationWarnings: [String]

  var qaOutcome: TutorCurrentContentQAOutcome {
    TutorCurrentContentQAOutcome.classify(
      transportDecision: transportDecision,
      selection: contentSelection,
      currentTutorInput: currentTutorInput
    )
  }

  var qaMarkerMatches: [String: Int] {
    TutorCurrentContentQAMarker.matches(in: currentTutorInput)
  }
}

@MainActor
@Observable
final class TutorDebugTraceStore {
  var currentTurnOnly = false
  var selectedRequestID: UUID?
  private(set) var traces: [TutorDebugTrace] = []

  var selectedTrace: TutorDebugTrace? {
    if let selectedRequestID,
       let selected = traces.first(where: { $0.id == selectedRequestID }) {
      return selected
    }
    return traces.last
  }

  var qaMetrics: TutorCurrentContentQAMetrics {
    TutorCurrentContentQAMetrics(traces: traces)
  }

  private struct CapturedPipeline {
    let context: TutorContextPipelineDebugSnapshot
    let buffer: TutorSemanticBufferDebugEvent?
    let axNodes: [AccessibleTextNode]
    let contentSelection: AXContentSelection?
  }

  private let maximumTraceCount: Int
  private var requestSequence = 0
  private var latestPipeline: TutorContextPipelineDebugSnapshot?
  private var pipelineByChunkID: [UUID: CapturedPipeline] = [:]
  private var manualPipelineByChunkID: [UUID: CapturedPipeline] = [:]

  init(maximumTraceCount: Int = 12) {
    self.maximumTraceCount = max(1, maximumTraceCount)
  }

  func recordPipeline(_ snapshot: TutorContextPipelineDebugSnapshot) {
    latestPipeline = snapshot
  }

  func recordBuffer(_ event: TutorSemanticBufferDebugEvent) {
    guard let chunkID = event.chunkID, let latestPipeline else {
      return
    }
    pipelineByChunkID[chunkID] = CapturedPipeline(
      context: latestPipeline,
      buffer: event,
      axNodes: [],
      contentSelection: nil
    )
    trimWorkingCaptures()
  }

  /// Records the actual explicit Tutor path. Diff and SemanticBuffer are
  /// intentionally marked as bypassed because the production action performs
  /// a fresh AX read and directly creates a manual chunk.
  func recordManualSnapshot(
    _ snapshot: AccessibleTextSnapshot,
    selection: AXContentSelection?,
    chunk: SemanticChunk
  ) {
    let normalized = TextNormalizer().normalize(snapshot.plainText).displayText
    let identity = ContextIdentityFactory().makeIdentity(
      snapshot: snapshot,
      liveSessionIdentifier: UUID()
    )
    let context = TutorContextPipelineDebugSnapshot(
      sourceApplication: snapshot.window.application.appName,
      bundleIdentifier: snapshot.window.application.bundleIdentifier,
      processIdentifier: snapshot.window.application.processIdentifier,
      focusedWindow: snapshot.window.windowTitle,
      focusedWindowToken: identity.focusedWindowIdentity.rawValue,
      snapshotSource: "\(snapshot.window.source.rawValue) · explicit-current-read",
      contextRevisionID: chunk.sourceRevisionID,
      timestamp: snapshot.window.observedAt,
      rawSnapshot: snapshot.plainText,
      normalizedText: normalized,
      previousBaseline: "(bypassed by explicit current-content read)",
      currentSnapshot: normalized,
      detectedAddedText: "(bypassed by explicit current-content read)",
      detectedRemovedText: "(bypassed by explicit current-content read)",
      detectedStableText: "(bypassed by explicit current-content read)",
      diffKind: .baseline,
      truncated: snapshot.truncated
    )
    let buffer = TutorSemanticBufferDebugEvent(
      revisionID: chunk.sourceRevisionID,
      bufferBefore: "",
      incomingDiff: chunk.text,
      bufferAfter: "",
      commitReason: chunk.flushReason.rawValue,
      transitionReason: "bypassed · direct manual chunk",
      commitTimestamp: chunk.createdAt,
      chunkID: chunk.id
    )
    manualPipelineByChunkID[chunk.id] = CapturedPipeline(
      context: context,
      buffer: buffer,
      axNodes: snapshot.nodes,
      contentSelection: selection
    )
    trimWorkingCaptures()
  }

  /// Retains the AX and selection preview in memory while proving that no
  /// Tutor input, prompt, or Provider request was created.
  func recordBlockedManualSnapshot(
    _ snapshot: AccessibleTextSnapshot,
    selection: AXContentSelection,
    revisionID: Int
  ) {
    requestSequence += 1
    let recordedAt = Date()
    let normalized = TextNormalizer().normalize(snapshot.plainText).displayText
    let identity = ContextIdentityFactory().makeIdentity(
      snapshot: snapshot,
      liveSessionIdentifier: UUID()
    )
    let trace = TutorDebugTrace(
      id: UUID(),
      tutorRequestID: Self.displayRequestID(
        date: recordedAt,
        sequence: requestSequence
      ) + "-BLOCKED",
      requestCreatedAt: recordedAt,
      requestSequence: 0,
      sourceApplication: snapshot.window.application.appName,
      bundleIdentifier: snapshot.window.application.bundleIdentifier,
      processIdentifier: snapshot.window.application.processIdentifier,
      focusedWindow: snapshot.window.windowTitle,
      focusedWindowToken: identity.focusedWindowIdentity.rawValue,
      snapshotSource: "\(snapshot.window.source.rawValue) · explicit-current-read",
      contextRevisionID: revisionID,
      snapshotTimestamp: snapshot.window.observedAt,
      snapshotWasTruncated: snapshot.truncated,
      rawSnapshot: snapshot.plainText,
      axNodes: snapshot.nodes,
      contentSelection: selection,
      normalizedText: normalized,
      previousBaseline: "(bypassed by explicit current-content read)",
      currentSnapshot: normalized,
      detectedAddedText: "(bypassed by explicit current-content read)",
      detectedRemovedText: "(bypassed by explicit current-content read)",
      detectedStableText: "(bypassed by explicit current-content read)",
      diffKind: "baseline",
      bufferBefore: "",
      incomingDiff: "",
      bufferAfter: "",
      commitReason: "blocked · ambiguous content",
      commitTimestamp: nil,
      bufferTransitionReason: "blocked before Tutor Current Input",
      currentTutorInput: "",
      currentContentSourceCharacterCount: selection.selectedText.count,
      currentContentWasTruncated: false,
      contentLength: nil,
      systemInstruction: "",
      internalConstraints: [],
      history: [],
      currentUserInput: "",
      conversationMode: currentTurnOnly ? .currentTurnOnly : .normalContext,
      transportDecision: .blockedAmbiguousContent,
      qaJudgment: .notEvaluable,
      transportRequest: nil,
      transportResponse: nil,
      latencyMetrics: nil,
      contaminationWarnings: []
    )
    traces.append(trace)
    if traces.count > maximumTraceCount {
      traces.removeFirst(traces.count - maximumTraceCount)
    }
    selectedRequestID = trace.id
  }

  func recordRequest(
    _ request: TutorRequest,
    prompt: PromptPackage
  ) {
    requestSequence += 1
    let capture = manualPipelineByChunkID.removeValue(forKey: request.source.chunkID)
      ?? pipelineByChunkID[request.source.chunkID]
    let context = capture?.context
    let buffer = capture?.buffer
    let sourceCharacterCount = request.source.contentLength.normalizedCharacterCount
    let trace = TutorDebugTrace(
      id: request.id,
      tutorRequestID: Self.displayRequestID(
        date: request.createdAt,
        sequence: requestSequence
      ),
      requestCreatedAt: request.createdAt,
      requestSequence: request.sequence,
      sourceApplication: context?.sourceApplication,
      bundleIdentifier: context?.bundleIdentifier,
      processIdentifier: context?.processIdentifier,
      focusedWindow: context?.focusedWindow,
      focusedWindowToken: context?.focusedWindowToken,
      snapshotSource: context?.snapshotSource ?? "unavailable · no linked AX capture",
      contextRevisionID: request.source.sourceRevisionID,
      snapshotTimestamp: context?.timestamp,
      snapshotWasTruncated: context?.truncated ?? false,
      rawSnapshot: context?.rawSnapshot ?? "(no linked AX snapshot)",
      axNodes: capture?.axNodes ?? [],
      contentSelection: capture?.contentSelection,
      normalizedText: context?.normalizedText ?? "(no linked normalized snapshot)",
      previousBaseline: context?.previousBaseline ?? "(unavailable)",
      currentSnapshot: context?.currentSnapshot ?? "(unavailable)",
      detectedAddedText: context?.detectedAddedText ?? "(unavailable)",
      detectedRemovedText: context?.detectedRemovedText ?? "(unavailable)",
      detectedStableText: context?.detectedStableText ?? "(unavailable)",
      diffKind: context?.diffKind.rawValue ?? "bypassed-or-unavailable",
      bufferBefore: buffer?.bufferBefore ?? "(unavailable)",
      incomingDiff: buffer?.incomingDiff ?? "(unavailable)",
      bufferAfter: buffer?.bufferAfter ?? "(unavailable)",
      commitReason: buffer?.commitReason ?? request.source.flushReason.rawValue,
      commitTimestamp: buffer?.commitTimestamp ?? request.source.chunkCreatedAt,
      bufferTransitionReason: buffer?.transitionReason,
      currentTutorInput: request.source.text,
      currentContentSourceCharacterCount: sourceCharacterCount,
      currentContentWasTruncated: request.source.contentLength.wasTruncated,
      contentLength: request.source.contentLength,
      systemInstruction: prompt.systemInstruction,
      internalConstraints: prompt.constraints,
      history: prompt.history,
      currentUserInput: prompt.userContent,
      conversationMode: prompt.conversationMode,
      transportDecision: .allowed,
      qaJudgment: .notEvaluable,
      transportRequest: nil,
      transportResponse: nil,
      latencyMetrics: nil,
      contaminationWarnings: []
    )
    traces.append(trace)
    if traces.count > maximumTraceCount {
      traces.removeFirst(traces.count - maximumTraceCount)
    }
    selectedRequestID = request.id
  }

  func setQAJudgment(_ judgment: TutorCurrentContentQAJudgment, for traceID: UUID) {
    guard let index = traces.firstIndex(where: { $0.id == traceID }) else {
      return
    }
    traces[index].qaJudgment = judgment
  }

  func recordCompletion(
    requestID: UUID,
    metrics: TutorLatencyMetrics,
    exchange: TutorTransportExchangeDebugSnapshot
  ) {
    guard let index = traces.firstIndex(where: { $0.id == requestID }) else {
      return
    }
    traces[index].transportRequest = exchange.request
    traces[index].transportResponse = exchange.response
    traces[index].latencyMetrics = metrics
    traces[index].contaminationWarnings = contaminationWarnings(at: index)
  }

  func clear() {
    traces.removeAll(keepingCapacity: false)
    selectedRequestID = nil
    latestPipeline = nil
    pipelineByChunkID.removeAll(keepingCapacity: false)
    manualPipelineByChunkID.removeAll(keepingCapacity: false)
  }

  func completedConsoleReport() -> String? {
    guard let trace = selectedTrace else {
      return nil
    }
    if trace.transportDecision == .blockedAmbiguousContent {
      return Self.consoleReport(trace)
    }
    guard trace.transportResponse != nil else { return nil }
    return Self.consoleReport(trace)
  }

  func incompleteConsoleReport() -> String {
    guard let trace = selectedTrace else {
      return "TUTOR AX CONSOLE CAPTURE FAILED\nNo Tutor trace was recorded."
    }
    return Self.consoleReport(trace)
      + "\nCAPTURE WARNING\nTransport completion was not observed before timeout."
  }

  private static func consoleReport(_ trace: TutorDebugTrace) -> String {
    let selection = trace.contentSelection
    let selectedID = selection?.selectedCandidateID
    let evidence = selection?.evidence
    var lines: [String] = [
      "TUTOR AX CONSOLE CAPTURE",
      "request_id=\(trace.tutorRequestID)",
      "source_app=\(trace.sourceApplication ?? "unavailable")",
      "source_bundle=\(trace.bundleIdentifier ?? "unavailable")",
      "focused_window=\(trace.focusedWindow ?? "unavailable")",
      "raw_characters=\(trace.rawSnapshot.count)",
      markerSummary(label: "raw", text: trace.rawSnapshot),
      "ax_node_count=\(trace.axNodes.count)",
      "candidate_count=\(selection?.candidates.count ?? 0)",
      "selection_reason=\(selection?.reason.rawValue ?? "unavailable")",
      "selection_confidence=\(selection?.confidence.rawValue ?? "unavailable")",
      "selection_user_selected_text=\(yesNo(evidence?.userSelectedText))",
      "selection_focused_element=\(yesNo(evidence?.focusedElement))",
      "selection_directly_focused_container=\(yesNo(evidence?.directlyFocusedContainer))",
      "selection_candidate_node_count=\(evidence?.candidateNodeCount ?? 0)",
      "selection_independent_region_count=\(evidence?.independentRegionCount ?? 0)",
      "selection_inferred_only=\(yesNo(evidence?.inferredOnly))",
      "transport_trust=\(selection?.transportTrust.rawValue ?? "unavailable")",
      "whole_snapshot_fallback=\(selection?.usedWholeSnapshotFallback == true ? "yes" : "no")",
      "selected_candidate=\(selectedID ?? "none")",
      "excluded_nodes=\(selection?.excludedNodeCount ?? 0)",
      "exclusion_summary=\(selection?.exclusionSummary.description ?? "unavailable")",
      "selection_warnings=\(selection?.warnings.joined(separator: " | ") ?? "none")",
      "transport_decision=\(trace.transportDecision.rawValue)",
      "qa_outcome=\(trace.qaOutcome.rawValue)",
      "qa_judgment=\(trace.qaJudgment.rawValue)",
      "current_content_source_characters=\(trace.currentContentSourceCharacterCount)",
      "current_content_truncated=\(trace.currentContentWasTruncated ? "yes" : "no")",
      "content_type=\(trace.contentLength?.contentType.rawValue ?? "unavailable")",
      "content_completeness=\(trace.contentLength?.completeness.rawValue ?? "unavailable")",
      "length_policy=\(trace.contentLength?.lengthPolicy.rawValue ?? "unavailable")",
      "original_content_characters=\(trace.contentLength?.originalCharacterCount ?? 0)",
      "normalized_content_characters=\(trace.contentLength?.normalizedCharacterCount ?? 0)",
      "sent_content_characters=\(trace.contentLength?.sentCharacterCount ?? 0)",
      "excerpt_start=\(trace.contentLength?.excerptStart ?? 0)",
      "excerpt_end=\(trace.contentLength?.excerptEnd ?? 0)",
      "dropped_prefix_characters=\(trace.contentLength?.droppedPrefixCount ?? 0)",
      "dropped_suffix_characters=\(trace.contentLength?.droppedSuffixCount ?? 0)",
      "structure_boundary=\(trace.contentLength?.structureBoundary.rawValue ?? "unavailable")",
      "qa_marker_matches=\(TutorCurrentContentQAMarker.description(in: trace.currentTutorInput))",
    ]

    if let selection {
      lines.append("CANDIDATE EVALUATIONS")
      lines.append(contentsOf: selection.evaluations.map {
        "\($0.candidateID) score=\($0.score) selected=\($0.isSelected) reason=\($0.reason)"
      })

      for candidate in selection.candidates where
        candidate.id == selectedID || containsDiagnosticMarker(candidate.text)
      {
        lines.append("CANDIDATE \(candidate.id)")
        lines.append(
          "selected=\(candidate.id == selectedID) traversal=\(candidate.firstTraversalIndex)...\(candidate.lastTraversalIndex) visible=\(candidate.isVisibleInWindow) focused_element=\(candidate.containsFocusedElement) focused_container=\(candidate.containsFocusedContainer) directly_focused_container=\(candidate.containsDirectlyFocusedContainer) selected_text=\(candidate.containsSelectedText) container_role=\(candidate.containerRole ?? "unknown") independent_regions=\(candidate.independentRegionCount) relevance=\(candidate.relevanceScore)"
        )
        lines.append(markerSummary(label: "candidate", text: candidate.text))
        lines.append(clipped(candidate.text, limit: 4_000))
      }
    }

    lines.append("RAW AX SNAPSHOT PREVIEW")
    lines.append(clipped(trace.rawSnapshot, limit: 8_000))

    lines.append("RELEVANT AX NODE PROVENANCE")
    let selectedNodeIDs = Set(
      selection?.candidates.first(where: { $0.id == selectedID })?.nodeIDs ?? []
    )
    let relevantNodes = trace.axNodes.filter {
      selectedNodeIDs.contains($0.debugNodeID) || containsDiagnosticMarker($0.text)
    }
    lines.append(contentsOf: relevantNodes.prefix(80).map { node in
      let ancestry = node.ancestorPath.suffix(5).map {
        "\($0.debugNodeID)[\($0.role ?? "unknown")#\($0.childIndex)]"
      }.joined(separator: " -> ")
      return [
        "node=\(node.debugNodeID) role=\(node.role ?? "unavailable") attribute=\(node.sourceAttribute.rawValue) traversal=\(node.traversalIndex) focused=\(optional(node.isFocused)) selected=\(optional(node.isSelected)) visible=\(optional(node.isVisible)) frame=\(node.frame?.debugDescription ?? "unavailable")",
        "ancestors=\(ancestry)",
        "text=\(clipped(node.text, limit: 600))",
      ].joined(separator: "\n")
    })

    lines.append("CURRENT TUTOR INPUT")
    lines.append("characters=\(trace.currentTutorInput.count)")
    lines.append(markerSummary(label: "current_input", text: trace.currentTutorInput))
    lines.append("ui_noise=\(uiNoiseSummary(trace.currentTutorInput))")
    lines.append(trace.currentTutorInput)

    lines.append("FINAL API REQUEST")
    if let request = trace.transportRequest {
      let finalText = request.messages.map(\.content).joined(separator: "\n")
      lines.append(
        "provider=\(request.provider) model=\(request.model) messages=\(request.messages.count) characters=\(request.inputCharacterCount) streaming=\(request.streamingEnabled)"
      )
      lines.append(markerSummary(label: "final_api", text: finalText))
      lines.append("ui_noise=\(uiNoiseSummary(finalText))")
      for message in request.messages {
        lines.append("MESSAGE role=\(message.role)")
        lines.append(clipped(message.content, limit: 8_000))
      }
    } else if trace.transportDecision == .blockedAmbiguousContent {
      lines.append("blocked · ambiguous content · provider not called")
    } else {
      lines.append("unavailable")
    }

    lines.append("TRANSPORT RESULT")
    if trace.transportDecision == .blockedAmbiguousContent {
      lines.append("not_started · provider not called")
    } else {
      lines.append("error=\(trace.transportResponse?.error ?? "none")")
    }
    return lines.joined(separator: "\n")
  }

  private static func yesNo(_ value: Bool?) -> String {
    value.map { $0 ? "yes" : "no" } ?? "unavailable"
  }

  private static func markerSummary(label: String, text: String) -> String {
    [
      "\(label).add_call=\(occurrences(of: "add(3, 5)", in: text) + occurrences(of: "add ( 3 ,  5 )", in: text))",
      "\(label).old_eight=\(occurrences(of: "3 + 5 = 8", in: text))",
      "\(label).students=\(occurrences(of: "const students", in: text))",
      "\(label).analyze_students=\(occurrences(of: "analyzeStudents", in: text))",
      "\(label).analysis_start=\(occurrences(of: "开始分析学生成绩", in: text))",
    ].joined(separator: " ")
  }

  private static func containsDiagnosticMarker(_ text: String) -> Bool {
    ["add(3, 5)", "add ( 3 ,  5 )", "3 + 5 = 8", "const students", "analyzeStudents"]
      .contains { text.contains($0) }
  }

  private static func occurrences(of needle: String, in text: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchRange = text.startIndex..<text.endIndex
    while let range = text.range(of: needle, range: searchRange) {
      count += 1
      searchRange = range.upperBound..<text.endIndex
    }
    return count
  }

  private static func clipped(_ text: String, limit: Int) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit)) + "\n…(clipped \(text.count - limit) characters)"
  }

  private static func optional(_ value: Bool?) -> String {
    value.map { $0 ? "yes" : "no" } ?? "unavailable"
  }

  private static func uiNoiseSummary(_ text: String) -> String {
    ["问问 ChatGPT", "复制", "发送", "Send", "Copy", "Sidebar", "Toolbar"]
      .filter { text.localizedCaseInsensitiveContains($0) }
      .joined(separator: ",")
  }

  private func contaminationWarnings(at index: Int) -> [String] {
    let trace = traces[index]
    guard let request = trace.transportRequest else {
      return []
    }
    let apiText = request.messages.map(\.content).joined(separator: "\n")
    var warnings: [String] = []

    if trace.conversationMode == .currentTurnOnly, request.messages.count != 2 {
      warnings.append(
        "Current Turn Only expected exactly system + current user messages, but found \(request.messages.count)."
      )
    }

    if !apiText.contains(trace.currentTutorInput) {
      warnings.append("Final API Request does not contain the complete CURRENT INPUT.")
    }

    if let bounded = Self.currentContent(from: trace.currentUserInput),
       bounded != trace.currentTutorInput {
      warnings.append("<CURRENT_CONTENT> differs from CURRENT TUTOR INPUT.")
    }

    var priorBodies: [String] = trace.history.map(\.content)
    if index > 0 {
      let previous = traces[index - 1]
      priorBodies.append(previous.currentTutorInput)
      if let response = previous.transportResponse?.responseText {
        priorBodies.append(response)
      }
    }
    let candidates = priorBodies.flatMap(Self.distinctiveFragments)
    for fragment in candidates {
      if trace.currentTutorInput.contains(fragment) {
        warnings.append(
          "Possible Source Context Contamination: prior-turn fragment appears in CURRENT INPUT: \(fragment)"
        )
      } else if apiText.contains(fragment) {
        warnings.append(
          "Possible Context Contamination: prior-turn fragment appears in Final API Request: \(fragment)"
        )
      }
      if warnings.count >= 6 { break }
    }
    var seen: Set<String> = []
    return warnings.filter { seen.insert($0).inserted }
  }

  private static func currentContent(from userContent: String) -> String? {
    guard
      let data = userContent.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let source = root["source"] as? [String: Any],
      let bounded = source["text"] as? String,
      bounded.hasPrefix("<CURRENT_CONTENT>\n"),
      bounded.hasSuffix("\n</CURRENT_CONTENT>")
    else {
      return nil
    }
    return String(
      bounded
        .dropFirst("<CURRENT_CONTENT>\n".count)
        .dropLast("\n</CURRENT_CONTENT>".count)
    )
  }

  private static func distinctiveFragments(in body: String) -> [String] {
    var fragments = body
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { $0.count >= 8 && $0.count <= 160 }
    if let expression = try? NSRegularExpression(
      pattern: #"[A-Za-z_$][A-Za-z0-9_$]*\([^\n)]{1,80}\)"#
    ) {
      let range = NSRange(body.startIndex..<body.endIndex, in: body)
      fragments.append(contentsOf: expression.matches(in: body, range: range).compactMap {
        Range($0.range, in: body).map { String(body[$0]) }
      })
    }
    return Array(fragments.prefix(40))
  }

  private func trimWorkingCaptures() {
    let limit = maximumTraceCount * 3
    if pipelineByChunkID.count > limit {
      pipelineByChunkID.removeAll(keepingCapacity: false)
    }
    if manualPipelineByChunkID.count > limit {
      manualPipelineByChunkID.removeAll(keepingCapacity: false)
    }
  }

  private static func displayRequestID(date: Date, sequence: Int) -> String {
    "TUTOR-\(requestIDDateFormatter.string(from: date))-"
      + String(format: "%04d", sequence)
  }

  private static let requestIDDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()
}

private enum TutorDebugInspectorPage: String, CaseIterable, Identifiable {
  case requestChain = "Request Chain"
  case axNodes = "AX Nodes"
  case contentCandidates = "Content Candidates"
  case selection = "Selection"

  var id: String { rawValue }
}

struct TutorDebugInspectorView: View {
  let store: TutorDebugTraceStore
  @State private var page: TutorDebugInspectorPage = .requestChain
  @State private var axReadTrace: AXReadTrace?

  var body: some View {
    @Bindable var store = store
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Tutor Request Chain Inspector")
          .font(.title2.bold())
        Spacer()
        Toggle("Current Turn Only", isOn: $store.currentTurnOnly)
          .toggleStyle(.switch)
        Button("刷新 AX Read Trace") {
          axReadTrace = AXReadTraceStore.shared.latestTrace
        }
        Button("清空内存 Trace") { store.clear() }
      }
      Text("只保留最多 12 次内存 Trace；不落盘、不上传，且从不捕获 Authorization 或 API Key。")
        .font(.caption)
        .foregroundStyle(.secondary)

      if let axReadTrace {
        axReadTraceSection(axReadTrace)
      }

      if store.traces.isEmpty {
        ContentUnavailableView(
          "暂无 Tutor 请求",
          systemImage: "waveform.path.ecg",
          description: Text("在花花老师中执行一次“解释当前内容”后查看完整链路。")
        )
      } else {
        Picker("Tutor Request", selection: $store.selectedRequestID) {
          ForEach(store.traces) { trace in
            Text(trace.tutorRequestID).tag(Optional(trace.id))
          }
        }
        .pickerStyle(.menu)

        Picker("Inspector Page", selection: $page) {
          ForEach(TutorDebugInspectorPage.allCases) { page in
            Text(page.rawValue).tag(page)
          }
        }
        .pickerStyle(.segmented)

        if let trace = store.selectedTrace {
          ScrollView {
            pageContent(trace)
            .padding(.vertical, 6)
          }
        }
      }
    }
    .padding(18)
    .frame(minWidth: 900, minHeight: 760)
    .onAppear {
      axReadTrace = AXReadTraceStore.shared.latestTrace
    }
  }

  private func axReadTraceSection(_ trace: AXReadTrace) -> some View {
    inspectorSection("AX Read Trace · in memory") {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
        inspectorRow("Application", trace.targetBundleIdentifier ?? "unavailable")
        inspectorRow("Target PID", String(trace.targetProcessIdentifier))
        inspectorRow("Resolved Bundle", trace.resolvedBundleIdentifier ?? "unavailable")
        inspectorRow("AXIsProcessTrusted", trace.axIsProcessTrusted ? "true" : "false")
        inspectorRow(
          "Focused Window",
          trace.focusedWindowAvailable.map { $0 ? "PASS" : "FAIL" } ?? "not attempted"
        )
        inspectorRow(
          "Focused Element",
          trace.focusedElementAvailable.map { $0 ? "PASS" : "FAIL" } ?? "not attempted"
        )
        inspectorRow("Result", trace.result ?? "in progress")
      }
      ForEach(Array(trace.events.enumerated()), id: \.offset) { _, event in
        let error = event.axErrorRawValue.map {
          " · AXError \($0) \(event.axErrorDescription ?? "")"
        } ?? ""
        Text(
          "\(event.stage.rawValue) · \(event.outcome.rawValue) · \(event.operation) · \(event.attribute ?? "no attribute")\(error) · role \(event.elementRole ?? "unknown") · \(event.isMainThread ? "main" : "background")"
        )
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
      }
    }
  }

  @ViewBuilder
  private func pageContent(_ trace: TutorDebugTrace) -> some View {
    switch page {
    case .requestChain:
      VStack(alignment: .leading, spacing: 16) {
        warningSection(trace)
        sourceSection(trace)
        qaSection(trace)
        transportDecisionSection(trace)
        textSection("① RAW AX SNAPSHOT", trace.rawSnapshot)
        textSection("② NORMALIZED TEXT", trace.normalizedText)
        diffSection(trace)
        bufferSection(trace)
        textSection("⑤ CURRENT TUTOR INPUT", trace.currentTutorInput)
        promptSection(trace)
        requestSection(trace)
        responseSection(trace)
      }
    case .axNodes:
      axNodesPage(trace)
    case .contentCandidates:
      candidatesPage(trace)
    case .selection:
      selectionPage(trace)
    }
  }

  private func axNodesPage(_ trace: TutorDebugTrace) -> some View {
    LazyVStack(alignment: .leading, spacing: 12) {
      inspectorSection("AX Nodes · \(trace.axNodes.count) text segments") {
        Text("每个 segment 保留原始 AX 来源；相同 Debug Node ID 表示同一 AX element 的不同文本属性。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ForEach(Array(trace.axNodes.enumerated()), id: \.offset) { _, node in
        inspectorSection(node.debugNodeID) {
          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            inspectorRow("Candidate", candidateID(for: node, in: trace) ?? "excluded / unavailable")
            inspectorRow("Fingerprint", node.fingerprint)
            inspectorRow("Role", node.role ?? "unavailable")
            inspectorRow("Subrole", node.subrole ?? "unavailable")
            inspectorRow("Identifier", node.identifier ?? "unavailable")
            inspectorRow("Attribute", node.sourceAttribute.rawValue)
            inspectorRow("Traversal / Depth", "\(node.traversalIndex) / \(node.depth)")
            inspectorRow("Parent", node.parentDebugNodeID ?? "root")
            inspectorRow("Ancestor Path", pathDescription(node.ancestorPath))
            inspectorRow("Frame", node.frame?.debugDescription ?? "unavailable")
            inspectorRow("Window Geometry", node.windowGeometryRelationship.rawValue)
            inspectorRow("Focused", optionalBoolean(node.isFocused))
            inspectorRow("Selected", optionalBoolean(node.isSelected))
            inspectorRow("Enabled", optionalBoolean(node.isEnabled))
            inspectorRow("Visible", optionalBoolean(node.isVisible))
            inspectorRow("Source App", node.sourceApplication ?? "unavailable")
            inspectorRow("Window Identity", node.sourceWindowIdentity ?? "unavailable")
          }
          textBlock("RAW \(node.sourceAttribute.rawValue.uppercased())", node.rawText)
        }
      }
    }
  }

  private func candidatesPage(_ trace: TutorDebugTrace) -> some View {
    LazyVStack(alignment: .leading, spacing: 12) {
      if let selection = trace.contentSelection {
        inspectorSection("Content Candidates · \(selection.candidates.count)") {
          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            inspectorRow("Excluded AX Segments", String(selection.excludedNodeCount))
            inspectorRow("Exclusion Summary", exclusionDescription(selection.exclusionSummary))
          }
        }
        ForEach(selection.candidates, id: \.id) { candidate in
          inspectorSection(candidate.id) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
              inspectorRow(
                "Status",
                candidate.id == selection.selectedCandidateID ? "SELECTED" : "not selected"
              )
              inspectorRow("Container Node", candidate.containerNodeID)
              inspectorRow("Container Role", candidate.containerRole ?? "unavailable")
              inspectorRow("Container Subrole", candidate.containerSubrole ?? "unavailable")
              inspectorRow("Text Nodes", candidate.nodeIDs.joined(separator: ", "))
              inspectorRow(
                "Traversal Range",
                "\(candidate.firstTraversalIndex)...\(candidate.lastTraversalIndex)"
              )
              inspectorRow("Frame", candidate.frame?.debugDescription ?? "unavailable")
              inspectorRow("Visible", candidate.isVisibleInWindow ? "yes" : "no / unknown")
              inspectorRow("Selected Text", candidate.containsSelectedText ? "yes" : "no")
              inspectorRow("Focused Element", candidate.containsFocusedElement ? "yes" : "no")
              inspectorRow("Focused Container", candidate.containsFocusedContainer ? "yes" : "no")
              inspectorRow(
                "Directly Focused Container",
                candidate.containsDirectlyFocusedContainer ? "yes" : "no"
              )
              inspectorRow("Independent Regions", String(candidate.independentRegionCount))
              inspectorRow("Content Relevance", String(candidate.relevanceScore))
            }
            textBlock("CANDIDATE TEXT", candidate.text)
          }
        }
      } else {
        inspectorSection("Content Candidates") {
          Text("本次请求没有关联 explicit AX Candidate capture。")
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func selectionPage(_ trace: TutorDebugTrace) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let selection = trace.contentSelection {
        inspectorSection("Current Content Selection") {
          if selection.usedWholeSnapshotFallback {
            Label("Whole Snapshot Fallback", systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }
          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            inspectorRow("Reason", selection.reason.rawValue)
            inspectorRow("Confidence", selection.confidence.rawValue)
            inspectorRow("Transport Trust", selection.transportTrust.rawValue)
            inspectorRow("Candidate Count", String(selection.candidates.count))
            inspectorRow("Selected Candidate", selection.selectedCandidateID ?? "none · whole snapshot")
            inspectorRow("Selected Characters", String(selection.selectedText.count))
          }
          let evidence = selection.evidence
          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            inspectorRow("User Selected Text", evidence.userSelectedText ? "yes" : "no")
            inspectorRow("Focused Element", evidence.focusedElement ? "yes" : "no")
            inspectorRow(
              "Directly Focused Container",
              evidence.directlyFocusedContainer ? "yes" : "no"
            )
            inspectorRow("Provenance", evidence.provenance.rawValue)
            inspectorRow("Candidate Node Count", String(evidence.candidateNodeCount))
            inspectorRow("Independent Region Count", String(evidence.independentRegionCount))
            inspectorRow("Inferred Only", evidence.inferredOnly ? "yes" : "no")
          }
          if !selection.warnings.isEmpty {
            ForEach(selection.warnings, id: \.self) { warning in
              Text("⚠ \(warning)").foregroundStyle(.orange)
            }
          }
        }
        inspectorSection("Candidate Evaluations") {
          ForEach(selection.evaluations, id: \.candidateID) { evaluation in
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
              inspectorRow("Candidate", evaluation.candidateID)
              inspectorRow("Score", String(evaluation.score))
              inspectorRow("Decision", evaluation.reason)
            }
            if evaluation.candidateID != selection.evaluations.last?.candidateID {
              Divider()
            }
          }
        }
        transportDecisionSection(trace)
        qaSection(trace)
        textSection("SELECTED CONTENT", selection.selectedText)
        textSection("CURRENT TUTOR INPUT", trace.currentTutorInput)
      } else {
        inspectorSection("Selection") {
          Text("本次请求没有关联 explicit AX Candidate selection。")
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func warningSection(_ trace: TutorDebugTrace) -> some View {
    if trace.contaminationWarnings.isEmpty {
      Label("未检测到 deterministic 上下文污染信号", systemImage: "checkmark.shield")
        .foregroundStyle(.green)
    } else {
      VStack(alignment: .leading, spacing: 5) {
        Label("Possible Context Contamination", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundStyle(.orange)
        ForEach(trace.contaminationWarnings, id: \.self) { Text("• \($0)") }
      }
    }
  }

  private func sourceSection(_ trace: TutorDebugTrace) -> some View {
    inspectorSection("Source Context") {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
        inspectorRow("Tutor Request ID", trace.tutorRequestID)
        inspectorRow("UUID", trace.id.uuidString)
        inspectorRow("Source Application", trace.sourceApplication ?? "unavailable")
        inspectorRow("Bundle ID", trace.bundleIdentifier ?? "unavailable")
        inspectorRow("PID", trace.processIdentifier.map(String.init) ?? "unavailable")
        inspectorRow("Focused Window", trace.focusedWindow ?? "unavailable")
        inspectorRow("Focused Window Token", trace.focusedWindowToken ?? "unavailable")
        inspectorRow("Snapshot Source", trace.snapshotSource)
        inspectorRow("Context Revision ID", String(trace.contextRevisionID))
        inspectorRow("Timestamp", Self.timestamp(trace.snapshotTimestamp))
        inspectorRow("AX Truncated", trace.snapshotWasTruncated ? "yes" : "no")
      }
    }
  }

  private func qaSection(_ trace: TutorDebugTrace) -> some View {
    let metrics = store.qaMetrics
    return inspectorSection("Current Content Reliability QA") {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
        inspectorRow("QA Outcome", trace.qaOutcome.rawValue)
        inspectorRow(
          "Selection Source",
          trace.contentSelection?.reason.rawValue ?? "unavailable"
        )
        inspectorRow(
          "Transport Trust",
          trace.contentSelection?.transportTrust.rawValue ?? "unavailable"
        )
        inspectorRow(
          "Independent Regions",
          String(trace.contentSelection?.evidence.independentRegionCount ?? 0)
        )
        inspectorRow(
          "Inferred Only",
          trace.contentSelection?.evidence.inferredOnly == true ? "yes" : "no"
        )
        inspectorRow("Transport Decision", trace.transportDecision.rawValue)
        inspectorRow(
          "Current Content Character Count",
          String(trace.currentTutorInput.count)
        )
        inspectorRow(
          "Selected Source Character Count",
          String(trace.currentContentSourceCharacterCount)
        )
        inspectorRow(
          "Original Content Length",
          String(trace.contentLength?.originalCharacterCount ?? 0)
        )
        inspectorRow(
          "Normalized Length",
          String(trace.contentLength?.normalizedCharacterCount ?? 0)
        )
        inspectorRow(
          "Content Type",
          trace.contentLength?.contentType.rawValue ?? "unavailable"
        )
        inspectorRow(
          "Content Completeness",
          trace.contentLength?.completeness.rawValue ?? "unavailable"
        )
        inspectorRow(
          "Length Policy",
          trace.contentLength?.lengthPolicy.rawValue ?? "unavailable"
        )
        inspectorRow("Truncated", trace.currentContentWasTruncated ? "yes" : "no")
        inspectorRow(
          "Excerpt Start / End",
          "\(trace.contentLength?.excerptStart ?? 0) / \(trace.contentLength?.excerptEnd ?? 0)"
        )
        inspectorRow(
          "Dropped Prefix / Suffix",
          "\(trace.contentLength?.droppedPrefixCount ?? 0) / \(trace.contentLength?.droppedSuffixCount ?? 0)"
        )
        inspectorRow(
          "Structure Boundary Used",
          trace.contentLength?.structureBoundary.rawValue ?? "unavailable"
        )
        inspectorRow(
          "Whole Snapshot Fallback",
          trace.contentSelection?.usedWholeSnapshotFallback == true ? "yes" : "no"
        )
        inspectorRow(
          "QA Marker Matches",
          TutorCurrentContentQAMarker.description(in: trace.currentTutorInput)
        )
      }
      if trace.currentContentWasTruncated {
        Text("CURRENT_CONTENT is an explicit excerpt of a longer source; see the range and dropped-character metadata above.")
          .font(.caption)
          .foregroundStyle(.orange)
      }
      Picker(
        "Human Ground Truth",
        selection: Binding(
          get: { trace.qaJudgment },
          set: { store.setQAJudgment($0, for: trace.id) }
        )
      ) {
        ForEach(TutorCurrentContentQAJudgment.allCases) { judgment in
          Text(judgment.rawValue).tag(judgment)
        }
      }
      .pickerStyle(.menu)

      Divider()
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
        inspectorRow("QA Attempts / Evaluable", "\(metrics.totalAttempts) / \(metrics.evaluableAttempts)")
        inspectorRow("Allowed", String(metrics.allowedCount))
        inspectorRow("Blocked Ambiguous", String(metrics.blockedAmbiguousCount))
        inspectorRow("Empty", String(metrics.emptyCount))
        inspectorRow("Correct / Incorrect", "\(metrics.correctSelectionCount) / \(metrics.incorrectSelectionCount)")
        inspectorRow("Unexpected Block", String(metrics.unexpectedBlockCount))
        inspectorRow("Selection Accuracy", percentage(metrics.selectionAccuracy))
        inspectorRow("Direct Explain Coverage", percentage(metrics.directExplainCoverage))
        inspectorRow("Ambiguous Rejection Rate", percentage(metrics.ambiguousRejectionRate))
        inspectorRow("Unexpected Block Rate", percentage(metrics.unexpectedBlockRate))
      }
      Text("Accuracy uses only correct/incorrect human judgments; blocked attempts are excluded from its denominator. All QA state is memory-only.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func transportDecisionSection(_ trace: TutorDebugTrace) -> some View {
    inspectorSection("Production Transport Decision") {
      let blocked = trace.transportDecision == .blockedAmbiguousContent
      Label(
        trace.transportDecision.rawValue,
        systemImage: blocked ? "hand.raised.fill" : "checkmark.shield.fill"
      )
      .foregroundStyle(blocked ? .red : .green)
      if blocked {
        Text("Debug Preview remains visible, but no Current Tutor Input, prompt, or Provider request was created.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func diffSection(_ trace: TutorDebugTrace) -> some View {
    inspectorSection("③ CONTEXT DIFF · revision \(trace.contextRevisionID) · \(trace.diffKind)") {
      textBlock("PREVIOUS BASELINE", trace.previousBaseline)
      textBlock("CURRENT SNAPSHOT", trace.currentSnapshot)
      textBlock("NEW CONTENT (engine output)", trace.detectedAddedText)
      textBlock("REMOVED TEXT (diagnostic)", trace.detectedRemovedText)
      textBlock("STABLE TEXT (diagnostic)", trace.detectedStableText)
    }
  }

  private func bufferSection(_ trace: TutorDebugTrace) -> some View {
    inspectorSection("④ SEMANTIC BUFFER") {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
        inspectorRow("Commit Reason", trace.commitReason)
        inspectorRow("Commit Timestamp", Self.timestamp(trace.commitTimestamp))
        inspectorRow("Transition", trace.bufferTransitionReason ?? "none")
      }
      textBlock("BUFFER BEFORE", trace.bufferBefore)
      textBlock("INCOMING DIFF", trace.incomingDiff)
      textBlock("BUFFER AFTER", trace.bufferAfter)
    }
  }

  private func promptSection(_ trace: TutorDebugTrace) -> some View {
    inspectorSection("⑥ PROMPT ASSEMBLY") {
      if trace.transportDecision == .blockedAmbiguousContent {
        Text("BLOCKED · Prompt assembly was not started.")
          .foregroundStyle(.red)
      } else {
        inspectorRow("Conversation Mode", trace.conversationMode.rawValue)
        textBlock("SYSTEM", trace.systemInstruction)
        textBlock(
          "DEVELOPER / INTERNAL CONSTRAINTS",
          trace.internalConstraints.joined(separator: "\n")
        )
        textBlock(
          "HISTORY",
          trace.history.isEmpty
            ? "(empty · current architecture has no Tutor body history)"
            : trace.history.map { "\($0.role.rawValue): \($0.content)" }
              .joined(separator: "\n\n")
        )
        textBlock("CURRENT USER INPUT", trace.currentUserInput)
      }
    }
  }

  private func requestSection(_ trace: TutorDebugTrace) -> some View {
    inspectorSection("⑦ FINAL API REQUEST") {
      if let request = trace.transportRequest {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
          inspectorRow("Provider", request.provider)
          inspectorRow("Model", request.model)
          inspectorRow("Conversation Mode", request.conversationMode.rawValue)
          inspectorRow("Message Count", String(request.messages.count))
          inspectorRow("Input Characters", String(request.inputCharacterCount))
          inspectorRow("Estimated Tokens", String(request.estimatedTokenCount))
          inspectorRow("Streaming", request.streamingEnabled ? "enabled" : "disabled")
        }
        textBlock("REDACTED REQUEST PAYLOAD", request.redactedPayload)
      } else if trace.transportDecision == .blockedAmbiguousContent {
        Text("BLOCKED · ambiguous content · Provider was not called.")
          .foregroundStyle(.red)
      } else {
        Text("Provider 尚未生成 transport payload，或本次使用的 Provider 不支持 Debug capture。")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func responseSection(_ trace: TutorDebugTrace) -> some View {
    inspectorSection("⑧ AI RESPONSE") {
      let metrics = trace.latencyMetrics
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
        inspectorRow("Tutor Request ID", trace.tutorRequestID)
        inspectorRow("Provider Request ID", trace.transportResponse?.providerRequestID ?? "unavailable")
        inspectorRow("Model", trace.transportResponse?.model ?? metrics?.modelIdentifier ?? "unavailable")
        inspectorRow("Start Time", Self.timestamp(metrics?.httpStartedAt))
        inspectorRow(
          "First Token / Byte Time",
          Self.timestamp(metrics?.firstSSEContentAt ?? metrics?.firstResponseByteAt)
        )
        inspectorRow("Finish Time", Self.timestamp(metrics?.networkCompletedAt))
        inspectorRow("Finish Reason", trace.transportResponse?.finishReason ?? "unavailable")
        inspectorRow("Error", trace.transportResponse?.error ?? "none")
      }
      textBlock("RESPONSE TEXT", trace.transportResponse?.responseText ?? "(no response body)")
    }
  }

  private func textSection(_ title: String, _ text: String) -> some View {
    inspectorSection(title) { textBlock(title, text) }
  }

  private func inspectorSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline)
      content()
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
  }

  private func inspectorRow(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
    }
  }

  private func textBlock(_ label: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("===== \(label) =====").font(.caption.bold())
      ScrollView([.horizontal, .vertical]) {
        Text(text.isEmpty ? "(empty)" : text)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(8)
      }
      .frame(minHeight: 44, maxHeight: 220)
      .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
      Text("===== END \(label) =====").font(.caption2).foregroundStyle(.secondary)
    }
  }

  private func candidateID(
    for node: AccessibleTextNode,
    in trace: TutorDebugTrace
  ) -> String? {
    trace.contentSelection?.candidates.first(where: {
      $0.nodeIDs.contains(node.debugNodeID)
    })?.id
  }

  private func pathDescription(_ path: [AccessibleNodePathComponent]) -> String {
    guard !path.isEmpty else {
      return "root"
    }
    return path.map { component in
      let role = component.role ?? "unknown"
      return "\(component.debugNodeID)[\(role)#\(component.childIndex)]"
    }.joined(separator: " → ")
  }

  private func optionalBoolean(_ value: Bool?) -> String {
    value.map { $0 ? "yes" : "no" } ?? "unavailable"
  }

  private func exclusionDescription(_ summary: [String: Int]) -> String {
    guard !summary.isEmpty else {
      return "none"
    }
    return summary.keys.sorted().map { key in
      "\(key)=\(summary[key] ?? 0)"
    }.joined(separator: ", ")
  }

  private static func timestamp(_ date: Date?) -> String {
    guard let date else { return "unavailable" }
    return timestampFormatter.string(from: date)
  }

  private func percentage(_ value: Double?) -> String {
    guard let value else { return "not evaluable" }
    return String(format: "%.1f%%", value * 100)
  }

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
  }()
}

struct TutorDebugView: View {
  let coordinator: TutorCoordinator

  @State private var isChunkBodyVisible = false
  @State private var isRequestBodyVisible = false
  @State private var isPromptBodyVisible = false
  @State private var isResponseBodyVisible = false

  var body: some View {
    @Bindable var coordinator = coordinator

    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Tutor Coordinator · Fake Flow")
          .font(.title2.bold())

        sessionSection
        Divider()
        semanticChunkSection
        Divider()
        requestSection
        Divider()
        promptSection
        Divider()
        providerSection
        Divider()
        responseSection
        Divider()
        interactionSection
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: 680, minHeight: 760)
    .onChange(of: coordinator.latestChunk?.id) {
      isChunkBodyVisible = false
    }
    .onChange(of: coordinator.latestRequest?.id) {
      isRequestBodyVisible = false
      isPromptBodyVisible = false
    }
    .onChange(of: coordinator.latestPresentation?.responseMetadata.responseID) {
      isResponseBodyVisible = false
    }
  }

  private var sessionSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Tutor Session")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        row("Coordinator", coordinator.state.rawValue)
        row("Session", shortID(coordinator.currentSessionID))
        row("Received Chunks", String(coordinator.receivedChunkCount))
        row("Duplicate Chunks", String(coordinator.duplicateChunkCount))
        row("Requests", String(coordinator.requestCount))
      }

      HStack {
        Button("启动 Session") {
          coordinator.start()
        }
        .disabled(coordinator.isSessionActive)

        Button("重置 Session") {
          hideAllBodies()
          coordinator.resetSession()
        }

        Button("取消当前请求") {
          coordinator.cancelCurrentRequest()
        }
        .disabled(coordinator.activeExecutionContext == nil)

        Button("停止并清理") {
          hideAllBodies()
          coordinator.stop()
        }
        .disabled(!coordinator.isSessionActive)
      }
      .controlSize(.small)
    }
  }

  private var semanticChunkSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Latest SemanticChunk Metadata")
        .font(.headline)
      if let chunk = coordinator.latestChunk {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
          row("Chunk ID", shortID(chunk.id))
          row("Revision ID", String(chunk.sourceRevisionID))
          row("Characters", String(chunk.text.count))
          row("Confidence", chunk.confidence.rawValue)
          row("Flush Reason", chunk.flushReason.rawValue)
          row("Created At", Self.timeFormatter.string(from: chunk.createdAt))
          row("Admission", admissionText(coordinator.latestChunkAdmission))
        }

        bodyButton(
          isVisible: $isChunkBodyVisible,
          showTitle: "查看 Chunk 正文",
          hideTitle: "隐藏 Chunk 正文"
        )
        if isChunkBodyVisible {
          bodyBox(chunk.text)
        } else {
          hiddenBodyHint
        }
      } else {
        Text("尚未收到 SemanticChunk。")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var requestSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("TutorRequest State")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        row("State", requestStateText(coordinator.requestState))
        if let request = coordinator.latestRequest {
          row("Request ID", shortID(request.id))
          row("Session", shortID(request.sessionID))
          row("Sequence", String(request.sequence))
          row("Task", request.task.rawValue)
          row("Trigger", request.trigger.rawValue)
          row("Completeness", request.source.completeness.rawValue)
          row("Learner Level", request.learner.level.rawValue)
          row("Created At", Self.timeFormatter.string(from: request.createdAt))
        }
      }

      if let request = coordinator.latestRequest {
        bodyButton(
          isVisible: $isRequestBodyVisible,
          showTitle: "查看 Request 正文",
          hideTitle: "隐藏 Request 正文"
        )
        if isRequestBodyVisible {
          bodyBox(request.source.text)
        } else {
          hiddenBodyHint
        }
      }
    }
  }

  private var providerSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Provider State")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        row("Provider", "FakeLLMProvider · Debug only")
        row("State", providerStateText(coordinator.providerState))
        if let context = coordinator.activeExecutionContext {
          row("Active Request", shortID(context.requestID))
          row("Sequence", String(context.sequence))
          row("Started At", Self.timeFormatter.string(from: context.startedAt))
        }
        row("Last Error", coordinator.lastError.map(errorText) ?? "无")
      }
      Text("本地确定性 Fake；无网络、无凭据、无 Provider SDK。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var promptSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Fake Prompt Preview")
        .font(.headline)
      if
        let request = coordinator.latestRequest,
        let package = coordinator.latestPromptPackage
      {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
          row("Rules Version", PromptRules.currentVersion)
          row("Request Schema", String(request.schemaVersion))
          row("Response Schema", String(TutorResponse.currentSchemaVersion))
          row("Learner Level", request.learner.level.rawValue)
          row("Language", request.output.language)
          row("Detail Level", request.output.detailLevel.rawValue)
          row("Source Characters", String(request.source.text.count))
          row("System Characters", String(package.systemInstruction.count))
          row("User Characters", String(package.userContent.count))
          row("Schema Characters", String(package.outputSchema.count))
          row("Constraints", String(package.constraints.count))
          row("Dispatch", "none · local preview only")
        }

        bodyButton(
          isVisible: $isPromptBodyVisible,
          showTitle: "查看 Prompt 正文",
          hideTitle: "隐藏 Prompt 正文"
        )
        if isPromptBodyVisible {
          bodyBox(promptBody(package))
        } else {
          hiddenBodyHint
        }
      } else {
        Text("尚未生成 PromptPackage。")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var responseSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("TutorResponse Outcome")
        .font(.headline)
      if let presentation = coordinator.latestPresentation {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
          row("Response ID", shortID(presentation.responseMetadata.responseID))
          row("Request ID", shortID(presentation.responseMetadata.requestID))
          row("Session", shortID(presentation.responseMetadata.sessionID))
          row("Sequence", String(presentation.responseMetadata.sequence))
          row("Outcome", presentation.outcome.rawValue)
          row(
            "Created At",
            Self.timeFormatter.string(from: presentation.responseMetadata.createdAt)
          )
          row("Presentation Truncated", presentation.didTruncateContent ? "yes" : "no")
        }

        Text("Lesson Metadata")
          .font(.subheadline.weight(.semibold))
          .padding(.top, 3)
        if let metadata = presentation.lessonMetadata {
          Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            row("Confidence", metadata.confidence.rawValue)
            row("Key Points", String(metadata.keyPointCount))
            row("Terms", String(metadata.termCount))
            row("Caveats", String(metadata.caveatCount))
            row("Has Analogy", metadata.hasAnalogy ? "yes" : "no")
            row("Has Example", metadata.hasExample ? "yes" : "no")
            row("Has Check Question", metadata.hasCheckQuestion ? "yes" : "no")
          }
        } else {
          Text("当前 outcome 不是 lesson。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text("Presentation Sections")
          .font(.subheadline.weight(.semibold))
          .padding(.top, 3)
        bodyButton(
          isVisible: $isResponseBodyVisible,
          showTitle: "查看 Presentation 正文",
          hideTitle: "隐藏 Presentation 正文"
        )
        if isResponseBodyVisible {
          bodyBox(presentationBody(presentation))
        } else {
          hiddenBodyHint
        }
      } else {
        Text("尚无 TutorResponse。")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var interactionSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Tutor Interaction Policy")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        if let decision = coordinator.latestInteractionDecision {
          row("Policy Decision", decision.action.rawValue)
          row("Priority", interactionPriorityText(decision.priority))
          row("Decision Reason", decision.reason.rawValue)
        } else {
          row("Policy Decision", "尚无决策")
        }

        if let input = coordinator.latestInteractionInput {
          row("Topic Type", input.topicType?.rawValue ?? "unknown")
          row("Confidence", input.confidence?.rawValue ?? "无")
          row("Flush Reason", input.flushReason.rawValue)
          row("Source Characters", String(input.textLength))
        }

        row("Queue Count", String(coordinator.displayQueue.queueCount))
        row("Duplicate Merges", String(coordinator.displayQueue.duplicateMergeCount))
      }

      Text("Current Display Item")
        .font(.subheadline.weight(.semibold))
        .padding(.top, 3)
      if let item = coordinator.displayQueue.currentDisplayItem {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
          row("Response ID", shortID(item.id))
          row("Source Chunk", shortID(item.sourceChunkID))
          row("Outcome", item.presentation.outcome.rawValue)
          row("Priority", interactionPriorityText(item.decision.priority))
        }
      } else {
        Text("当前没有展示项。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }

  private func bodyButton(
    isVisible: Binding<Bool>,
    showTitle: String,
    hideTitle: String
  ) -> some View {
    Button(isVisible.wrappedValue ? hideTitle : showTitle) {
      isVisible.wrappedValue.toggle()
    }
    .controlSize(.small)
  }

  private func bodyBox(_ text: String) -> some View {
    ScrollView {
      Text(text)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(8)
    }
    .frame(maxHeight: 180)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }

  private var hiddenBodyHint: some View {
    Text("正文默认隐藏；仅在主动点击后显示当前最新值。")
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  private func admissionText(_ admission: TutorChunkAdmission?) -> String {
    switch admission {
    case let .accepted(trigger):
      return "accepted · \(trigger.rawValue)"
    case let .skipped(reason):
      return "skipped · \(reason.rawValue)"
    case nil:
      return "无"
    }
  }

  private func requestStateText(_ state: TutorRequestState) -> String {
    switch state {
    case .idle:
      return "idle"
    case let .running(requestID, sequence):
      return "running · \(shortID(requestID)) · #\(sequence)"
    case let .succeeded(requestID, sequence):
      return "succeeded · \(shortID(requestID)) · #\(sequence)"
    case let .failed(requestID, error):
      return "failed · \(shortID(requestID)) · \(errorText(error))"
    case let .cancelled(requestID):
      return "cancelled · \(shortID(requestID))"
    }
  }

  private func providerStateText(_ state: TutorProviderState) -> String {
    switch state {
    case .idle:
      return "idle"
    case let .running(requestID):
      return "running · \(shortID(requestID))"
    case let .succeeded(responseID):
      return "succeeded · \(shortID(responseID))"
    case let .failed(error):
      return "failed · \(errorText(error))"
    case let .cancelled(requestID):
      return "cancelled · \(shortID(requestID))"
    }
  }

  private func interactionPriorityText(_ priority: TutorInteractionPriority) -> String {
    switch priority {
    case .high:
      return "high"
    case .normal:
      return "normal"
    case .low:
      return "low"
    }
  }

  private func presentationBody(_ presentation: TutorPresentationModel) -> String {
    var sections = ["标题\n\(presentation.title)"]
    sections.append("大白话解释\n\(presentation.plainExplanation)")
    if !presentation.keyPoints.isEmpty {
      sections.append(
        "关键点\n" + presentation.keyPoints.map { "• \($0)" }.joined(separator: "\n")
      )
    }
    if !presentation.terms.isEmpty {
      sections.append(
        "术语\n" + presentation.terms
          .map { "\($0.term)：\($0.plainDefinition)" }
          .joined(separator: "\n")
      )
    }
    if let analogy = presentation.analogy {
      sections.append("类比\n\(analogy)")
    }
    if let example = presentation.example {
      sections.append("示例\n\(example)")
    }
    if let checkQuestion = presentation.checkQuestion {
      sections.append("检查问题\n\(checkQuestion)")
    }
    if !presentation.caveats.isEmpty {
      sections.append("注意事项\n" + presentation.caveats.joined(separator: "\n"))
    }
    if let suggestedAction = presentation.suggestedAction {
      sections.append("建议下一步\n\(suggestedAction)")
    }
    if let blockReason = presentation.blockReason {
      sections.append("阻止原因\n\(blockReason.rawValue)")
    }
    return sections.joined(separator: "\n\n")
  }

  private func promptBody(_ package: PromptPackage) -> String {
    """
    SYSTEM INSTRUCTION
    \(package.systemInstruction)

    CONSTRAINTS
    \(package.constraints.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

    USER CONTENT
    \(package.userContent)

    OUTPUT SCHEMA
    \(package.outputSchema)
    """
  }

  private func errorText(_ error: TutorEngineError) -> String {
    String(describing: error)
  }

  private func shortID(_ id: UUID?) -> String {
    id.map { String($0.uuidString.prefix(8)) } ?? "无"
  }

  private func hideAllBodies() {
    isChunkBodyVisible = false
    isRequestBodyVisible = false
    isPromptBodyVisible = false
    isResponseBodyVisible = false
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()
}
#endif
