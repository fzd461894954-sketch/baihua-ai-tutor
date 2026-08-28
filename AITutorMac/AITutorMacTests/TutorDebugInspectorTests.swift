import Darwin
import XCTest

@testable import AITutorMac

#if DEBUG
@MainActor
final class TutorDebugInspectorTests: XCTestCase {
  func testClearingTraceMemoryDoesNotReuseReadableRequestID() throws {
    let store = TutorDebugTraceStore()
    let first = makeRequest(text: "first", sequence: 1)
    store.recordRequest(first, prompt: try TutorPromptBuilder().build(from: first))
    let firstDisplayID = try XCTUnwrap(store.selectedTrace?.tutorRequestID)

    store.clear()
    let second = makeRequest(text: "second", sequence: 1)
    store.recordRequest(second, prompt: try TutorPromptBuilder().build(from: second))
    let secondDisplayID = try XCTUnwrap(store.selectedTrace?.tutorRequestID)

    XCTAssertNotEqual(firstDisplayID, secondDisplayID)
    XCTAssertTrue(firstDisplayID.hasSuffix("-0001"))
    XCTAssertTrue(secondDisplayID.hasSuffix("-0002"))
  }

  func testCompleteStudentProgramSurvivesCurrentSnapshotWithoutSuffixTruncation() throws {
    XCTAssertGreaterThan(studentProgram.count, 1_000)
    XCTAssertLessThan(studentProgram.count, TutorRequest.defaultMaximumSourceCharacterCount)

    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)
    let snapshot = makeSnapshot(text: studentProgram)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 7, sessionID: sessionID),
      .accepted
    )
    let chunk = try provider.currentSemanticChunk()

    XCTAssertEqual(chunk.text, studentProgram)
    XCTAssertTrue(chunk.text.hasPrefix("const students = ["))
    XCTAssertTrue(chunk.text.contains("async function main()"))
    XCTAssertTrue(chunk.text.contains("await delay(1000);"))
  }

  func testCurrentContentBoundaryContainsOnlyCurrentTurn() throws {
    let previousCode = "const result = add(3, 5);\nconsole.log(result);"
    let previousResponse = "程序让电脑显示 result，所以屏幕显示 8。"
    let request = makeRequest(text: studentProgram, sequence: 2)
    let package = try TutorPromptBuilder().build(
      from: request,
      history: [
        TutorPromptMessage(role: .user, content: previousCode),
        TutorPromptMessage(role: .assistant, content: previousResponse),
      ]
    )
    let bounded = try currentContent(in: package)

    XCTAssertEqual(bounded, studentProgram)
    XCTAssertEqual(request.source.text, studentProgram)
    for oldFragment in ["add(3, 5)", "console.log(result)", "屏幕显示 8"] {
      XCTAssertFalse(request.source.text.contains(oldFragment))
      XCTAssertFalse(bounded.contains(oldFragment))
    }
    XCTAssertEqual(package.history.map(\.content), [previousCode, previousResponse])
    XCTAssertTrue(package.systemInstruction.contains("Explain only CURRENT_CONTENT"))
  }

  func testCurrentTurnOnlyStripsTutorBodyHistory() throws {
    let package = try TutorPromptBuilder().build(
      from: makeRequest(text: studentProgram, sequence: 2),
      history: [
        TutorPromptMessage(role: .user, content: "const result = add(3, 5);"),
        TutorPromptMessage(role: .assistant, content: "屏幕上出现 8。"),
      ],
      conversationMode: .currentTurnOnly
    )

    XCTAssertEqual(package.conversationMode, .currentTurnOnly)
    XCTAssertTrue(package.history.isEmpty)
    XCTAssertEqual(try currentContent(in: package), studentProgram)
  }

  func testDeterministicDetectorFlagsPriorTurnFragmentInFinalRequest() throws {
    let store = TutorDebugTraceStore()
    let turnA = makeRequest(
      text: "function add(a, b) { return a + b; }\nconst result = add(3, 5);",
      sequence: 1
    )
    let promptA = try TutorPromptBuilder().build(from: turnA)
    store.recordRequest(turnA, prompt: promptA)
    complete(
      turnA,
      prompt: promptA,
      apiUserContent: promptA.userContent,
      responseText: "程序会输出 8。",
      in: store
    )

    let turnB = makeRequest(text: studentProgram, sequence: 2)
    let promptB = try TutorPromptBuilder().build(from: turnB)
    store.recordRequest(turnB, prompt: promptB)
    complete(
      turnB,
      prompt: promptB,
      apiUserContent: promptB.userContent + "\nconst result = add(3, 5);",
      responseText: "",
      in: store
    )

    let warnings = try XCTUnwrap(store.selectedTrace?.contaminationWarnings)
    XCTAssertTrue(warnings.contains(where: { $0.contains("Possible Context Contamination") }))
    XCTAssertTrue(warnings.contains(where: { $0.contains("add(3, 5)") }))
  }

  func testCodeSymbolsAndAsyncSyntaxSurviveNormalizer() {
    let code = """
    const list = [];
    const result = list.map((student) => {
      return {
        name: student.name,
        score: student.score
      };
    });

    async function main() {
      await delay(1000);
    }
    """

    let normalized = TextNormalizer().normalize(code).displayText

    for symbol in ["()", "{", "}", "[", "]", ":", ";", ","] {
      XCTAssertTrue(normalized.contains(symbol), "Missing symbol: \(symbol)")
    }
    XCTAssertTrue(normalized.contains("async function main()"))
    XCTAssertTrue(normalized.contains("await delay(1000);"))
  }

  func testWindowChangeDiscardsOldSemanticBufferBody() {
    let buffer = SemanticBuffer()
    var chunks: [SemanticChunk] = []
    buffer.onChunk = { chunks.append($0) }
    buffer.ingest(makeRevision(text: "const result = add(3, 5)", window: "window-a"))
    buffer.ingest(
      makeRevision(
        text: "const students = [];",
        window: "window-b",
        characterCount: 20
      )
    )
    _ = buffer.manualFlush()

    XCTAssertEqual(chunks.map(\.text), ["const students = [];"])
    XCTAssertFalse(chunks.contains(where: { $0.text.contains("add(3, 5)") }))
  }

  func testSameConversationWithoutUserDirectedEvidenceFailsClosed() throws {
    let oldCode = """
    function add(a, b) {
      return a + b;
    }

    const result = add(3, 5);
    console.log(result);
    """
    let snapshot = makeConversationSnapshot(
      messages: [oldCode, "3 + 5 = 8", studentProgram]
    )
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 12, sessionID: sessionID),
      .rejected(.ambiguousContent)
    )
    let selection = try XCTUnwrap(provider.latestContentSelection)
    XCTAssertEqual(selection.reason, .latestVisibleContentContainer)
    XCTAssertEqual(selection.candidates.count, 3)
    XCTAssertFalse(selection.usedWholeSnapshotFallback)
    XCTAssertEqual(selection.transportTrust, .ambiguous)
    XCTAssertTrue(selection.evidence.inferredOnly)
    XCTAssertEqual(selection.evidence.candidateCount, 3)
    XCTAssertFalse(provider.hasStableContent)
    XCTAssertThrowsError(try provider.currentSemanticChunk())

    let store = TutorDebugTraceStore()
    store.recordBlockedManualSnapshot(snapshot, selection: selection, revisionID: 12)

    let trace = try XCTUnwrap(store.selectedTrace)
    XCTAssertTrue(trace.currentTutorInput.isEmpty)
    XCTAssertTrue(trace.currentUserInput.isEmpty)
    XCTAssertTrue(trace.systemInstruction.isEmpty)
    XCTAssertEqual(trace.contentSelection?.selectedCandidateID, selection.selectedCandidateID)
    XCTAssertEqual(trace.axNodes.count, snapshot.nodes.count)
    XCTAssertNil(trace.transportRequest)
    XCTAssertNil(trace.transportResponse)
    XCTAssertEqual(trace.transportDecision, .blockedAmbiguousContent)
    XCTAssertEqual(trace.qaOutcome, .blockedAmbiguousContent)
    let report = try XCTUnwrap(store.completedConsoleReport())
    XCTAssertTrue(report.contains("transport_trust=ambiguous"))
    XCTAssertTrue(report.contains("selection_inferred_only=yes"))
    XCTAssertTrue(report.contains("blocked · ambiguous content · provider not called"))
  }

  func testExplicitlyFocusedStudentMessageRemainsTheOnlyTutorInput() throws {
    let snapshot = makeConversationSnapshot(
      messages: [
        "AX_OLD_ONLY_MARKER const result = add(3, 5);",
        "AX_OTHER_ONLY_MARKER 3 + 5 = 8",
        "AX_CURRENT_ONLY_MARKER\n\(studentProgram)",
      ],
      focusedMessageIndex: 2
    )
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 13, sessionID: sessionID),
      .accepted
    )
    let selection = try XCTUnwrap(provider.latestContentSelection)
    let chunk = try provider.currentSemanticChunk()
    XCTAssertEqual(selection.reason, .focusedElement)
    XCTAssertEqual(selection.transportTrust, .strong)
    XCTAssertEqual(chunk.text, "AX_CURRENT_ONLY_MARKER\n\(studentProgram)")
    XCTAssertFalse(chunk.text.contains("AX_OLD_ONLY_MARKER"))
    XCTAssertFalse(chunk.text.contains("AX_OTHER_ONLY_MARKER"))
    XCTAssertFalse(chunk.text.contains("add(3, 5)"))
    XCTAssertFalse(chunk.text.contains("3 + 5 = 8"))
  }

  func testCleanConversationSelectsOnlyCoherentCurrentMessage() throws {
    let snapshot = makeConversationSnapshot(messages: [studentProgram])
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)

    XCTAssertEqual(selection.reason, .singleCoherentCandidate)
    XCTAssertEqual(selection.candidates.count, 1)
    XCTAssertEqual(selection.selectedText, studentProgram)
    XCTAssertFalse(selection.usedWholeSnapshotFallback)
  }

  func testCandidateBoundaryDoesNotSanitizeLegitimateResultOrEight() throws {
    let current = """
    const result = calculateScore();
    console.log(result);
    console.log(8);
    """
    let snapshot = makeConversationSnapshot(
      messages: ["older unrelated explanation", current]
    )
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)

    XCTAssertEqual(selection.selectedText, current)
    XCTAssertTrue(selection.selectedText.contains("const result ="))
    XCTAssertTrue(selection.selectedText.contains("console.log(8)"))
  }

  func testMultipleCodeBlocksInsideOneMessageRemainOneCandidate() throws {
    let messageFrame = CGRect(x: 380, y: 130, width: 650, height: 420)
    let messagePath = conversationPath(
      messageIndex: 0,
      messageFrame: messageFrame
    )
    let nodes = [
      makeProvenanceNode(
        id: "intro",
        text: "下面两个代码块一起说明同一个流程。",
        traversalIndex: 4,
        ancestors: messagePath + [
          pathComponent(id: "paragraph-a", role: "AXGroup", index: 3, frame: messageFrame)
        ],
        frame: CGRect(x: 400, y: 150, width: 600, height: 35)
      ),
      makeProvenanceNode(
        id: "code-a",
        text: "function first() {\n  return 1;\n}",
        traversalIndex: 6,
        ancestors: messagePath + [
          pathComponent(id: "block-a", role: "AXGroup", index: 5, frame: messageFrame)
        ],
        frame: CGRect(x: 400, y: 195, width: 600, height: 100)
      ),
      makeProvenanceNode(
        id: "middle",
        text: "然后继续第二步。",
        traversalIndex: 8,
        ancestors: messagePath + [
          pathComponent(id: "paragraph-b", role: "AXGroup", index: 7, frame: messageFrame)
        ],
        frame: CGRect(x: 400, y: 305, width: 600, height: 35)
      ),
      makeProvenanceNode(
        id: "code-b",
        text: "function second() {\n  return 2;\n}",
        traversalIndex: 10,
        ancestors: messagePath + [
          pathComponent(id: "block-b", role: "AXGroup", index: 9, frame: messageFrame)
        ],
        frame: CGRect(x: 400, y: 350, width: 600, height: 100)
      ),
    ]
    let selection = AXCurrentContentCandidateSelector().select(
      from: makeSnapshot(nodes: nodes)
    )

    XCTAssertEqual(selection.candidates.count, 1)
    XCTAssertEqual(selection.reason, .singleCoherentCandidate)
    XCTAssertTrue(selection.selectedText.contains("function first()"))
    XCTAssertTrue(selection.selectedText.contains("然后继续第二步。"))
    XCTAssertTrue(selection.selectedText.contains("function second()"))
  }

  func testExplicitSelectionCanTargetOlderCandidate() throws {
    let snapshot = makeConversationSnapshot(
      messages: ["older message user explicitly selected", "newer message"],
      selectedMessageIndex: 0,
      selectedText: "older message user explicitly selected"
    )
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)

    XCTAssertEqual(selection.reason, .selectedText)
    XCTAssertEqual(selection.confidence, .explicit)
    XCTAssertEqual(selection.selectedText, "older message user explicitly selected")
  }

  func testFocusedMeaningfulElementWinsOverNewerCandidate() throws {
    let snapshot = makeConversationSnapshot(
      messages: ["focused older content", "newer content"],
      focusedMessageIndex: 0
    )
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)

    XCTAssertEqual(selection.reason, .focusedElement)
    XCTAssertEqual(selection.selectedText, "focused older content")
  }

  func testFocusedContainerWinsWhenLeafItselfIsNotFocused() throws {
    let snapshot = makeConversationSnapshot(
      messages: ["content inside focused container", "newer content"],
      focusedContainerMessageIndex: 0
    )
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)

    XCTAssertEqual(selection.reason, .focusedContainer)
    XCTAssertEqual(selection.selectedText, "content inside focused container")
  }

  func testGenericControlRolesExcludeComposerAndButtonLabels() throws {
    var snapshot = makeConversationSnapshot(messages: ["coherent article body"])
    let rootPath = conversationPath(
      messageIndex: 0,
      messageFrame: CGRect(x: 380, y: 140, width: 650, height: 180)
    )
    let button = makeProvenanceNode(
      id: "copy-label",
      text: "Copy",
      traversalIndex: 90,
      ancestors: Array(rootPath.prefix(2)) + [
        pathComponent(id: "copy-button", role: "AXButton", index: 89, frame: nil)
      ],
      frame: nil
    )
    let composer = makeProvenanceNode(
      id: "composer",
      text: "message composer placeholder",
      traversalIndex: 91,
      ancestors: Array(rootPath.prefix(2)),
      frame: CGRect(x: 400, y: 700, width: 600, height: 60),
      role: "AXTextArea"
    )
    snapshot = makeSnapshot(nodes: snapshot.nodes + [button, composer])
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)

    XCTAssertEqual(selection.selectedText, "coherent article body")
    XCTAssertFalse(selection.selectedText.contains("Copy"))
    XCTAssertFalse(selection.selectedText.contains("composer"))
    XCTAssertEqual(selection.exclusionSummary["control-role-or-ancestor"], 2)
  }

  func testFocusedMultilineEditorWinsOverNewerPageContent() throws {
    let olderFrame = CGRect(x: 380, y: 140, width: 650, height: 280)
    let messageHeading = makeProvenanceNode(
      id: "focused-message-heading",
      text: "你说：",
      traversalIndex: 19,
      ancestors: conversationPath(messageIndex: 0, messageFrame: olderFrame),
      frame: CGRect(x: 380, y: 140, width: 100, height: 30)
    )
    let focusedEditor = makeProvenanceNode(
      id: "focused-message-editor",
      text: studentProgram,
      traversalIndex: 20,
      ancestors: conversationPath(messageIndex: 0, messageFrame: olderFrame),
      frame: olderFrame,
      role: "AXTextArea",
      sourceAttribute: .value,
      focused: true
    )
    let newerExplanation = makeProvenanceNode(
      id: "newer-assistant-response",
      text: "ChatGPT 说：这里是更晚出现、但不是用户当前目标的长篇解释。",
      traversalIndex: 40,
      ancestors: conversationPath(
        messageIndex: 1,
        messageFrame: CGRect(x: 380, y: 450, width: 650, height: 160)
      ),
      frame: CGRect(x: 380, y: 450, width: 650, height: 160)
    )

    let selection = AXCurrentContentCandidateSelector().select(
      from: makeSnapshot(nodes: [messageHeading, focusedEditor, newerExplanation])
    )

    XCTAssertEqual(selection.reason, .focusedElement)
    XCTAssertEqual(selection.confidence, .explicit)
    XCTAssertEqual(selection.selectedText, studentProgram)
    XCTAssertTrue(selection.selectedText.hasPrefix("const students = ["))
    XCTAssertFalse(selection.selectedText.contains("你说："))
    XCTAssertFalse(selection.selectedText.contains("ChatGPT 说"))
  }

  func testAmbiguousCandidatesUseObservableWholeSnapshotFallback() throws {
    let snapshot = makeConversationSnapshot(
      messages: ["first unknown geometry", "second unknown geometry"],
      geometryRelationship: .unknown,
      explicitlyVisible: nil
    )
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)

    XCTAssertEqual(selection.reason, .wholeSnapshotFallback)
    XCTAssertEqual(selection.confidence, .fallback)
    XCTAssertTrue(selection.usedWholeSnapshotFallback)
    XCTAssertNil(selection.selectedCandidateID)
    XCTAssertEqual(selection.candidates.count, 2)
    XCTAssertTrue(selection.warnings.contains(where: { $0.contains("Whole Snapshot Fallback") }))
    XCTAssertTrue(selection.selectedText.contains("first unknown geometry"))
    XCTAssertTrue(selection.selectedText.contains("second unknown geometry"))
  }

  func testBlockedFallbackTraceRetainsWholeSnapshotDebugPreview() throws {
    let snapshot = makeConversationSnapshot(
      messages: ["first unknown geometry", "second unknown geometry"],
      geometryRelationship: .unknown,
      explicitlyVisible: nil
    )
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)
    let store = TutorDebugTraceStore()

    store.recordBlockedManualSnapshot(snapshot, selection: selection, revisionID: 17)

    let trace = try XCTUnwrap(store.selectedTrace)
    XCTAssertEqual(trace.rawSnapshot, snapshot.plainText)
    XCTAssertEqual(trace.axNodes, snapshot.nodes)
    XCTAssertEqual(trace.contentSelection, selection)
    XCTAssertTrue(trace.contentSelection?.usedWholeSnapshotFallback == true)
    XCTAssertTrue(trace.contentSelection?.selectedText.contains("first unknown geometry") == true)
    XCTAssertTrue(trace.contentSelection?.selectedText.contains("second unknown geometry") == true)
  }

  func testBlockedFallbackTraceHasNoTutorInputPromptOrTransport() throws {
    let snapshot = makeConversationSnapshot(
      messages: ["first unknown geometry", "second unknown geometry"],
      geometryRelationship: .unknown,
      explicitlyVisible: nil
    )
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)
    let store = TutorDebugTraceStore()
    store.currentTurnOnly = true

    store.recordBlockedManualSnapshot(snapshot, selection: selection, revisionID: 18)

    let trace = try XCTUnwrap(store.selectedTrace)
    XCTAssertEqual(trace.transportDecision, .blockedAmbiguousContent)
    XCTAssertEqual(trace.conversationMode, .currentTurnOnly)
    XCTAssertTrue(trace.currentTutorInput.isEmpty)
    XCTAssertTrue(trace.currentUserInput.isEmpty)
    XCTAssertTrue(trace.systemInstruction.isEmpty)
    XCTAssertNil(trace.transportRequest)
    XCTAssertNil(trace.transportResponse)
    let report = try XCTUnwrap(store.completedConsoleReport())
    XCTAssertTrue(report.contains("transport_decision=BLOCKED · ambiguous content"))
    XCTAssertTrue(report.contains("RAW AX SNAPSHOT PREVIEW"))
    XCTAssertTrue(report.contains("first unknown geometry"))
    XCTAssertTrue(report.contains("second unknown geometry"))
    XCTAssertTrue(report.contains("blocked · ambiguous content · provider not called"))
    XCTAssertTrue(report.contains("not_started · provider not called"))
  }

  func testQAOutcomeClassificationCoversAllowedBlockedEmptyAndUnsupported() {
    XCTAssertEqual(
      TutorCurrentContentQAOutcome.classify(
        transportDecision: .allowed,
        selection: nil,
        currentTutorInput: ""
      ),
      .emptyNoExplainableContent
    )
    XCTAssertEqual(
      TutorCurrentContentQAOutcome.classify(
        transportDecision: .allowed,
        selection: nil,
        currentTutorInput: "unsupported body"
      ),
      .rejectedUnsupported
    )

    let focused = AXCurrentContentCandidateSelector().select(
      from: makeConversationSnapshot(
        messages: ["focused body"],
        focusedMessageIndex: 0
      )
    )
    XCTAssertEqual(
      TutorCurrentContentQAOutcome.classify(
        transportDecision: .allowed,
        selection: focused,
        currentTutorInput: focused.selectedText
      ),
      .allowedFocusedElement
    )

    let fallback = AXCurrentContentCandidateSelector().select(
      from: makeConversationSnapshot(
        messages: ["ambiguous one", "ambiguous two"],
        geometryRelationship: .unknown,
        explicitlyVisible: nil
      )
    )
    XCTAssertEqual(
      TutorCurrentContentQAOutcome.classify(
        transportDecision: .blockedAmbiguousContent,
        selection: fallback,
        currentTutorInput: ""
      ),
      .blockedWholeSnapshotFallback
    )
  }

  func testSelectedTextCreatesExactTutorBoundaryAndMarkerMatches() throws {
    let selected = "function currentOnly() { return \"AX_CURRENT_ONLY_MARKER\"; }"
    let snapshot = makeConversationSnapshot(
      messages: [
        "old body AX_OLD_ONLY_MARKER",
        "larger current message that must not be transported",
        "other body AX_OTHER_ONLY_MARKER",
      ],
      selectedMessageIndex: 1,
      selectedText: selected
    )
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 31, sessionID: sessionID),
      .accepted
    )
    let chunk = try provider.currentSemanticChunk()
    let selection = try XCTUnwrap(provider.latestContentSelection)
    XCTAssertEqual(selection.reason, .selectedText)
    XCTAssertEqual(chunk.text, selected)
    XCTAssertEqual(chunk.contentLength.contentType, .explicitSelectedText)
    XCTAssertEqual(chunk.contentLength.completeness, .complete)
    XCTAssertEqual(chunk.contentLength.lengthPolicy, .complete)

    let store = TutorDebugTraceStore()
    store.recordManualSnapshot(snapshot, selection: selection, chunk: chunk)
    let request = makeRequest(text: chunk.text, sequence: 31, chunkID: chunk.id)
    store.recordRequest(request, prompt: try TutorPromptBuilder().build(from: request))

    let trace = try XCTUnwrap(store.selectedTrace)
    XCTAssertEqual(trace.qaOutcome, .allowedSelectedText)
    XCTAssertEqual(trace.currentTutorInput, selected)
    XCTAssertEqual(trace.currentContentSourceCharacterCount, selected.count)
    XCTAssertFalse(trace.currentContentWasTruncated)
    XCTAssertEqual(trace.qaMarkerMatches["AX_CURRENT_ONLY_MARKER"], 1)
    XCTAssertEqual(trace.qaMarkerMatches["AX_OLD_ONLY_MARKER"], 0)
    XCTAssertEqual(trace.qaMarkerMatches["AX_OTHER_ONLY_MARKER"], 0)
  }

  func testSelectedOnlyMarkerRemainsExactAndStrong() throws {
    let selected = "AX_SELECTED_ONLY_MARKER"
    let snapshot = makeConversationSnapshot(
      messages: [
        "AX_OLD_ONLY_MARKER older message",
        "prefix \(selected) suffix",
        "AX_OTHER_ONLY_MARKER other message",
      ],
      selectedMessageIndex: 1,
      selectedText: selected
    )
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 32, sessionID: sessionID),
      .accepted
    )
    let selection = try XCTUnwrap(provider.latestContentSelection)
    XCTAssertEqual(selection.reason, .selectedText)
    XCTAssertEqual(selection.transportTrust, .strong)
    XCTAssertTrue(selection.evidence.userSelectedText)
    XCTAssertFalse(selection.evidence.inferredOnly)
    XCTAssertEqual(try provider.currentSemanticChunk().text, selected)
  }

  func testWeakAmbiguousBlockImmediatelyRecoversWithSelectedText() throws {
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)
    let ambiguous = makeConversationSnapshot(messages: [
      "AX_OLD_ONLY_MARKER old",
      "AX_CURRENT_ONLY_MARKER current",
      "AX_OTHER_ONLY_MARKER other",
    ])

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(ambiguous, revisionID: 36, sessionID: sessionID),
      .rejected(.ambiguousContent)
    )
    XCTAssertEqual(provider.latestContentSelection?.transportTrust, .ambiguous)

    let selected = makeConversationSnapshot(
      messages: [
        "AX_OLD_ONLY_MARKER old",
        "AX_SELECTED_ONLY_MARKER",
        "AX_OTHER_ONLY_MARKER other",
      ],
      selectedMessageIndex: 1,
      selectedText: "AX_SELECTED_ONLY_MARKER"
    )
    XCTAssertEqual(
      provider.receiveCurrentSnapshot(selected, revisionID: 37, sessionID: sessionID),
      .accepted
    )
    XCTAssertEqual(provider.latestContentSelection?.transportTrust, .strong)
    XCTAssertEqual(try provider.currentSemanticChunk().text, "AX_SELECTED_ONLY_MARKER")
  }

  func testArticleAndCommentRegionsWithoutFocusFailClosed() throws {
    let snapshot = makeArticleAndCommentSnapshot()
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 33, sessionID: sessionID),
      .rejected(.ambiguousContent)
    )
    let selection = try XCTUnwrap(provider.latestContentSelection)
    XCTAssertEqual(selection.reason, .singleCoherentCandidate)
    XCTAssertEqual(selection.evidence.independentRegionCount, 2)
    XCTAssertEqual(selection.transportTrust, .ambiguous)
    XCTAssertFalse(provider.hasStableContent)
  }

  func testFocusedArticleTextExcludesCommentRegion() throws {
    let snapshot = makeArticleAndCommentSnapshot(focusArticleText: true)
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 34, sessionID: sessionID),
      .accepted
    )
    let selection = try XCTUnwrap(provider.latestContentSelection)
    let chunk = try provider.currentSemanticChunk()
    XCTAssertEqual(selection.reason, .focusedElement)
    XCTAssertEqual(selection.transportTrust, .strong)
    XCTAssertEqual(chunk.text, "AX_CURRENT_ONLY_MARKER article body")
    XCTAssertFalse(chunk.text.contains("AX_OTHER_ONLY_MARKER"))
  }

  func testTwoIndependentContentRegionsWithoutFocusFailClosed() throws {
    let snapshot = makeIndependentRegionSnapshot()
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 35, sessionID: sessionID),
      .rejected(.ambiguousContent)
    )
    let selection = try XCTUnwrap(provider.latestContentSelection)
    XCTAssertEqual(selection.evidence.independentRegionCount, 2)
    XCTAssertEqual(selection.transportTrust, .ambiguous)
    XCTAssertFalse(provider.hasStableContent)
  }

  func testSingleTextCandidateWithFocusPropagatedFromExcludedControlRemainsWeaklyTrusted() {
    let candidate = AXContentCandidate(
      id: "modal-body",
      containerNodeID: "modal-container",
      containerRole: "AXGroup",
      containerSubrole: nil,
      nodeIDs: ["modal-text"],
      text: "人工浮层解释内容。",
      firstTraversalIndex: 3,
      lastTraversalIndex: 3,
      frame: nil,
      containsSelectedText: false,
      containsSelectedElement: false,
      containsFocusedElement: false,
      containsFocusedContainer: true,
      containsDirectlyFocusedContainer: false,
      independentRegionCount: 1,
      isVisibleInWindow: true,
      relevanceScore: 4
    )
    let selection = AXContentSelection(
      candidates: [candidate],
      selectedCandidateID: candidate.id,
      selectedText: candidate.text,
      reason: .focusedContainer,
      confidence: .high,
      usedWholeSnapshotFallback: false,
      warnings: [],
      evaluations: [],
      excludedNodeCount: 1,
      exclusionSummary: ["control-role-or-ancestor": 1]
    )

    XCTAssertEqual(selection.transportTrust, .weak)
    XCTAssertTrue(selection.evidence.inferredOnly)
    XCTAssertFalse(selection.evidence.directlyFocusedContainer)
    XCTAssertEqual(selection.evidence.candidateNodeCount, 1)
  }

  func testFocusedMessagesABCRemainExactlyIsolated() throws {
    let messages = [
      "Message A AX_OLD_ONLY_MARKER",
      "Message B AX_CURRENT_ONLY_MARKER",
      "Message C AX_OTHER_ONLY_MARKER",
    ]

    for index in messages.indices {
      let provider = CurrentExplainableContentProvider()
      let sessionID = UUID()
      provider.beginSession(sessionID)
      let snapshot = makeConversationSnapshot(
        messages: messages,
        focusedMessageIndex: index
      )

      XCTAssertEqual(
        provider.receiveCurrentSnapshot(
          snapshot,
          revisionID: 40 + index,
          sessionID: sessionID
        ),
        .accepted
      )
      let selection = try XCTUnwrap(provider.latestContentSelection)
      let chunk = try provider.currentSemanticChunk()
      XCTAssertEqual(selection.reason, .focusedElement)
      XCTAssertEqual(chunk.text, messages[index])
      for otherIndex in messages.indices where otherIndex != index {
        XCTAssertFalse(chunk.text.contains(messages[otherIndex]))
      }
    }
  }

  func testLongContentMatrixPreservesLimitAndExposesTutorTruncation() throws {
    for length in [500, 1_100, 2_500, 3_900, 4_100] {
      let text = String(repeating: "x", count: length)
      let snapshot = makeConversationSnapshot(messages: [text])
      let provider = CurrentExplainableContentProvider()
      let sessionID = UUID()
      provider.beginSession(sessionID)

      XCTAssertEqual(
        provider.receiveCurrentSnapshot(snapshot, revisionID: length, sessionID: sessionID),
        .accepted
      )
      let chunk = try provider.currentSemanticChunk()
      let selection = try XCTUnwrap(provider.latestContentSelection)
      let expected = length <= TutorRequest.defaultMaximumSourceCharacterCount
        ? text
        : String(text.prefix(TutorRequest.defaultMaximumSourceCharacterCount))
      XCTAssertEqual(chunk.text, expected)
      XCTAssertEqual(
        chunk.contentLength.completeness,
        length > 4_000 ? .excerpt : .complete
      )
      XCTAssertEqual(chunk.contentLength.originalCharacterCount, length)
      XCTAssertEqual(chunk.contentLength.normalizedCharacterCount, length)
      XCTAssertEqual(chunk.contentLength.sentCharacterCount, min(length, 4_000))
      XCTAssertEqual(chunk.contentLength.droppedPrefixCount, 0)
      XCTAssertEqual(chunk.contentLength.droppedSuffixCount, max(0, length - 4_000))

      let store = TutorDebugTraceStore()
      store.recordManualSnapshot(snapshot, selection: selection, chunk: chunk)
      let request = makeRequest(
        text: chunk.text,
        sequence: length,
        chunkID: chunk.id,
        contentLength: chunk.contentLength
      )
      store.recordRequest(request, prompt: try TutorPromptBuilder().build(from: request))
      let trace = try XCTUnwrap(store.selectedTrace)

      XCTAssertEqual(trace.currentContentSourceCharacterCount, length)
      XCTAssertEqual(trace.currentTutorInput.count, min(length, 4_000))
      XCTAssertEqual(trace.currentContentWasTruncated, length > 4_000)
      let report = store.incompleteConsoleReport()
      XCTAssertTrue(report.contains("current_content_source_characters=\(length)"))
      XCTAssertTrue(
        report.contains("current_content_truncated=\(length > 4_000 ? "yes" : "no")")
      )
      XCTAssertTrue(
        report.contains(
          "content_completeness=\(length > 4_000 ? "excerpt" : "complete")"
        )
      )
    }
  }

  func testStructureAwareCodeExcerptKeepsPrefixAndEndsAtBalancedBlock() {
    for targetLength in [4_100, 8_000] {
      let code = makeLongCode(targetLength: targetLength)
      let decision = StructureAwareLongContentPolicy().apply(
        to: code,
        selectionReason: .focusedElement
      )

      XCTAssertEqual(decision.metadata.contentType, .focusedCodeLike)
      XCTAssertEqual(decision.metadata.completeness, .excerpt)
      XCTAssertEqual(decision.metadata.lengthPolicy, .structureAwareCodeExcerpt)
      XCTAssertEqual(decision.metadata.structureBoundary, .codeBlock)
      XCTAssertTrue(decision.text.hasPrefix("// AX_CODE_PREFIX_MARKER"))
      XCTAssertFalse(decision.text.contains("AX_CODE_SUFFIX_MARKER"))
      XCTAssertLessThanOrEqual(decision.text.count, 4_000)
      XCTAssertEqual(decision.metadata.droppedPrefixCount, 0)
      XCTAssertGreaterThan(decision.metadata.droppedSuffixCount, 0)
      XCTAssertEqual(simpleBraceBalance(decision.text), 0)
      XCTAssertEqual(
        decision.metadata.sentCharacterCount + decision.metadata.droppedSuffixCount,
        decision.metadata.normalizedCharacterCount
      )
    }
  }

  func testBraceHeavyCodeDoesNotBeginInTheMiddleOfStructure() {
    let code = makeLongCode(targetLength: 8_000, nestedBraces: true)
    let decision = StructureAwareLongContentPolicy().apply(
      to: code,
      selectionReason: .focusedElement
    )

    XCTAssertTrue(decision.text.hasPrefix("// AX_CODE_PREFIX_MARKER"))
    XCTAssertEqual(decision.metadata.excerptStart, 0)
    XCTAssertEqual(decision.metadata.structureBoundary, .codeBlock)
    XCTAssertEqual(simpleBraceBalance(decision.text), 0)
  }

  func testLongProseUsesParagraphBoundaryAndDeclaresExcerpt() {
    let prose = makeLongProse(targetLength: 6_000)
    let decision = StructureAwareLongContentPolicy().apply(
      to: prose,
      selectionReason: .focusedElement
    )

    XCTAssertEqual(decision.metadata.contentType, .focusedNaturalLanguage)
    XCTAssertEqual(decision.metadata.completeness, .excerpt)
    XCTAssertEqual(decision.metadata.lengthPolicy, .structureAwareProseExcerpt)
    XCTAssertEqual(decision.metadata.structureBoundary, .paragraph)
    XCTAssertTrue(decision.text.hasPrefix("AX_PROSE_PREFIX_MARKER"))
    XCTAssertTrue(decision.text.hasSuffix("。"))
    XCTAssertFalse(decision.text.contains("AX_PROSE_SUFFIX_MARKER"))
    XCTAssertEqual(decision.metadata.droppedPrefixCount, 0)
    XCTAssertGreaterThan(decision.metadata.droppedSuffixCount, 0)
  }

  func testLongSelectedTextNeverUsesSilentTailTruncation() {
    let selected = makeLongCode(targetLength: 8_000)
    let decision = StructureAwareLongContentPolicy().apply(
      to: selected,
      selectionReason: .selectedText
    )

    XCTAssertEqual(decision.metadata.contentType, .explicitSelectedText)
    XCTAssertEqual(decision.metadata.completeness, .excerpt)
    XCTAssertEqual(decision.metadata.lengthPolicy, .longSelectionExcerpt)
    XCTAssertTrue(decision.text.contains("AX_CODE_PREFIX_MARKER"))
    XCTAssertFalse(decision.text.contains("AX_CODE_SUFFIX_MARKER"))
    XCTAssertEqual(decision.metadata.excerptStart, 0)
    XCTAssertEqual(decision.metadata.droppedPrefixCount, 0)
    XCTAssertGreaterThan(decision.metadata.droppedSuffixCount, 0)
  }

  func testLongSelectedTextDoesNotExpandParentContent() throws {
    let selected = makeLongCode(targetLength: 8_000)
    let snapshot = makeConversationSnapshot(
      messages: ["AX_PARENT_PREFIX\n\(selected)\nAX_PARENT_SUFFIX"],
      selectedMessageIndex: 0,
      selectedText: selected
    )
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 87, sessionID: sessionID),
      .accepted
    )
    let chunk = try provider.currentSemanticChunk()
    XCTAssertEqual(provider.latestContentSelection?.reason, .selectedText)
    XCTAssertEqual(provider.latestContentSelection?.transportTrust, .strong)
    XCTAssertEqual(chunk.contentLength.contentType, .explicitSelectedText)
    XCTAssertEqual(chunk.contentLength.completeness, .excerpt)
    XCTAssertFalse(chunk.text.contains("AX_PARENT_PREFIX"))
    XCTAssertFalse(chunk.text.contains("AX_PARENT_SUFFIX"))
    XCTAssertTrue(chunk.text.contains("AX_CODE_PREFIX_MARKER"))
  }

  func testAmbiguousLongContentRemainsBlockedBeforeLengthPolicy() {
    let snapshot = makeConversationSnapshot(
      messages: [
        makeLongCode(targetLength: 4_500),
        makeLongProse(targetLength: 4_500),
      ],
      geometryRelationship: .unknown,
      explicitlyVisible: nil
    )
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 88, sessionID: sessionID),
      .rejected(.ambiguousContent)
    )
    XCTAssertEqual(provider.latestContentSelection?.transportTrust, .ambiguous)
    XCTAssertFalse(provider.hasStableContent)
    XCTAssertThrowsError(try provider.currentSemanticChunk())
  }

  func testWindowIdentityChangeDoesNotCarryPreviousMarkerIntoAllowedTrace() throws {
    let store = TutorDebugTraceStore()
    let fixtures = [
      (window: "QA Window A", text: "AX_OLD_ONLY_MARKER window A"),
      (window: "QA Window B", text: "AX_CURRENT_ONLY_MARKER window B"),
    ]

    for (index, fixture) in fixtures.enumerated() {
      let snapshot = makeConversationSnapshot(
        messages: [fixture.text],
        focusedMessageIndex: 0,
        windowTitle: fixture.window
      )
      let provider = CurrentExplainableContentProvider()
      let sessionID = UUID()
      provider.beginSession(sessionID)
      XCTAssertEqual(
        provider.receiveCurrentSnapshot(snapshot, revisionID: 50 + index, sessionID: sessionID),
        .accepted
      )
      let chunk = try provider.currentSemanticChunk()
      store.recordManualSnapshot(
        snapshot,
        selection: provider.latestContentSelection,
        chunk: chunk
      )
      let request = makeRequest(text: chunk.text, sequence: 50 + index, chunkID: chunk.id)
      store.recordRequest(request, prompt: try TutorPromptBuilder().build(from: request))
    }

    let trace = try XCTUnwrap(store.selectedTrace)
    XCTAssertEqual(trace.focusedWindow, "QA Window B")
    XCTAssertEqual(trace.currentTutorInput, "AX_CURRENT_ONLY_MARKER window B")
    XCTAssertEqual(trace.qaMarkerMatches["AX_CURRENT_ONLY_MARKER"], 1)
    XCTAssertEqual(trace.qaMarkerMatches["AX_OLD_ONLY_MARKER"], 0)
  }

  func testQAMetricsUseOnlyHumanGroundTruthForAccuracy() throws {
    let store = TutorDebugTraceStore()
    for (index, judgment) in [
      TutorCurrentContentQAJudgment.correct,
      .incorrect,
    ].enumerated() {
      let snapshot = makeConversationSnapshot(
        messages: ["focused QA body \(index)"],
        focusedMessageIndex: 0
      )
      let provider = CurrentExplainableContentProvider()
      let sessionID = UUID()
      provider.beginSession(sessionID)
      XCTAssertEqual(
        provider.receiveCurrentSnapshot(snapshot, revisionID: 60 + index, sessionID: sessionID),
        .accepted
      )
      let chunk = try provider.currentSemanticChunk()
      store.recordManualSnapshot(
        snapshot,
        selection: provider.latestContentSelection,
        chunk: chunk
      )
      let request = makeRequest(text: chunk.text, sequence: 60 + index, chunkID: chunk.id)
      store.recordRequest(request, prompt: try TutorPromptBuilder().build(from: request))
      store.setQAJudgment(judgment, for: request.id)
    }

    let fallbackSnapshot = makeConversationSnapshot(
      messages: ["ambiguous A", "ambiguous B"],
      geometryRelationship: .unknown,
      explicitlyVisible: nil
    )
    let fallback = AXCurrentContentCandidateSelector().select(from: fallbackSnapshot)
    store.recordBlockedManualSnapshot(fallbackSnapshot, selection: fallback, revisionID: 62)
    let blockedID = try XCTUnwrap(store.selectedTrace?.id)
    store.setQAJudgment(.blockedAsExpected, for: blockedID)

    let metrics = store.qaMetrics
    XCTAssertEqual(metrics.totalAttempts, 3)
    XCTAssertEqual(metrics.evaluableAttempts, 3)
    XCTAssertEqual(metrics.allowedCount, 2)
    XCTAssertEqual(metrics.blockedAmbiguousCount, 1)
    XCTAssertEqual(metrics.correctSelectionCount, 1)
    XCTAssertEqual(metrics.incorrectSelectionCount, 1)
    XCTAssertEqual(metrics.selectionAccuracy, 0.5)
    XCTAssertEqual(metrics.directExplainCoverage, 2.0 / 3.0)
    XCTAssertEqual(metrics.ambiguousRejectionRate, 1.0 / 3.0)
    XCTAssertEqual(metrics.unexpectedBlockRate, 0)
  }

  func testCandidateProvenanceMapsEveryIncludedNodeToOneCandidate() throws {
    let snapshot = makeConversationSnapshot(messages: ["first", "second", "third"])
    let selection = AXCurrentContentCandidateSelector().select(from: snapshot)
    let mappedNodeIDs = selection.candidates.flatMap(\.nodeIDs)

    XCTAssertEqual(Set(mappedNodeIDs), Set(snapshot.nodes.map(\.debugNodeID)))
    XCTAssertEqual(mappedNodeIDs.count, Set(mappedNodeIDs).count)
    XCTAssertEqual(selection.evaluations.count, selection.candidates.count)
    XCTAssertEqual(selection.evaluations.filter(\.isSelected).count, 1)
  }

  private func complete(
    _ request: TutorRequest,
    prompt: PromptPackage,
    apiUserContent: String,
    responseText: String,
    in store: TutorDebugTraceStore
  ) {
    let latency = TutorLatencyTrace(userActionAt: request.createdAt)
    latency.markRequestCreated(requestID: request.id, at: request.createdAt)
    latency.recordDebugAPIRequest(
      TutorTransportRequestDebugSnapshot(
        tutorRequestID: request.id,
        provider: "mock-openai-compatible",
        model: "fixture-model",
        conversationMode: prompt.conversationMode,
        messages: [
          TutorTransportMessageDebugSnapshot(
            role: "system",
            content: prompt.systemInstruction
          ),
          TutorTransportMessageDebugSnapshot(role: "user", content: apiUserContent),
        ],
        inputCharacterCount: prompt.systemInstruction.count + apiUserContent.count,
        estimatedTokenCount: 1,
        streamingEnabled: false,
        redactedPayload: "{\"messages\":\"fixture\"}",
        recordedAt: request.createdAt
      )
    )
    latency.recordDebugAPIResponse(
      RawLLMResponse(
        content: responseText.isEmpty ? "{}" : responseText,
        finishReason: .stop,
        usage: .unavailable,
        providerMetadata: LLMProviderMetadata(
          providerIdentifier: "mock-openai-compatible",
          modelIdentifier: "fixture-model",
          requestIdentifier: "provider-fixture",
          values: [:]
        )
      )
    )
    store.recordCompletion(
      requestID: request.id,
      metrics: latency.snapshot,
      exchange: latency.debugExchangeSnapshot
    )
  }

  private func currentContent(in package: PromptPackage) throws -> String {
    let data = try XCTUnwrap(package.userContent.data(using: .utf8))
    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let source = try XCTUnwrap(root["source"] as? [String: Any])
    let bounded = try XCTUnwrap(source["text"] as? String)
    let prefix = "<CURRENT_CONTENT>\n"
    let suffix = "\n</CURRENT_CONTENT>"
    XCTAssertTrue(bounded.hasPrefix(prefix))
    XCTAssertTrue(bounded.hasSuffix(suffix))
    return String(bounded.dropFirst(prefix.count).dropLast(suffix.count))
  }

  private func makeArticleAndCommentSnapshot(
    focusArticleText: Bool = false
  ) -> AccessibleTextSnapshot {
    let root = pathComponent(
      id: "article-root",
      role: "AXWebArea",
      index: 0,
      frame: CGRect(x: 100, y: 80, width: 800, height: 700)
    )
    let main = pathComponent(
      id: "article-main",
      role: "AXGroup",
      index: 1,
      frame: CGRect(x: 180, y: 100, width: 700, height: 560)
    )
    let article = pathComponent(
      id: "article-region",
      role: "AXArticle",
      index: 2,
      frame: CGRect(x: 200, y: 130, width: 620, height: 300)
    )
    let comments = pathComponent(
      id: "comment-region",
      role: "AXSection",
      index: 5,
      frame: CGRect(x: 200, y: 470, width: 620, height: 140)
    )
    return makeSnapshot(nodes: [
      makeProvenanceNode(
        id: "article-body",
        text: "AX_CURRENT_ONLY_MARKER article body",
        traversalIndex: 3,
        ancestors: [root, main, article],
        frame: CGRect(x: 220, y: 150, width: 580, height: 220),
        focused: focusArticleText
      ),
      makeProvenanceNode(
        id: "comment-body",
        text: "AX_OTHER_ONLY_MARKER comment body",
        traversalIndex: 6,
        ancestors: [root, main, comments],
        frame: CGRect(x: 220, y: 490, width: 580, height: 80)
      ),
    ], windowTitle: "Article Reliability Fixture")
  }

  private func makeIndependentRegionSnapshot() -> AccessibleTextSnapshot {
    let root = pathComponent(
      id: "regions-root",
      role: "AXWebArea",
      index: 0,
      frame: CGRect(x: 100, y: 80, width: 800, height: 700)
    )
    let page = pathComponent(
      id: "regions-page",
      role: "AXGroup",
      index: 1,
      frame: CGRect(x: 180, y: 100, width: 700, height: 560)
    )
    let first = pathComponent(
      id: "region-a",
      role: "AXSection",
      index: 2,
      frame: CGRect(x: 200, y: 130, width: 620, height: 180)
    )
    let second = pathComponent(
      id: "region-b",
      role: "AXSection",
      index: 5,
      frame: CGRect(x: 200, y: 410, width: 620, height: 180)
    )
    return makeSnapshot(nodes: [
      makeProvenanceNode(
        id: "region-a-body",
        text: "AX_OLD_ONLY_MARKER independent region A",
        traversalIndex: 3,
        ancestors: [root, page, first],
        frame: CGRect(x: 220, y: 150, width: 580, height: 100)
      ),
      makeProvenanceNode(
        id: "region-b-body",
        text: "AX_OTHER_ONLY_MARKER independent region B",
        traversalIndex: 6,
        ancestors: [root, page, second],
        frame: CGRect(x: 220, y: 430, width: 580, height: 100)
      ),
    ], windowTitle: "Independent Regions Fixture")
  }

  private func makeConversationSnapshot(
    messages: [String],
    selectedMessageIndex: Int? = nil,
    selectedText: String? = nil,
    focusedMessageIndex: Int? = nil,
    focusedContainerMessageIndex: Int? = nil,
    geometryRelationship: AccessibleWindowGeometryRelationship = .containedInWindow,
    explicitlyVisible: Bool? = true,
    windowTitle: String = "ChatGPT Conversation Fixture"
  ) -> AccessibleTextSnapshot {
    let nodes = messages.enumerated().map { index, message in
      let frame = CGRect(
        x: 390,
        y: 110 + CGFloat(index * 190),
        width: 640,
        height: 150
      )
      let isSelected = selectedMessageIndex == index
      return makeProvenanceNode(
        id: "message-text-\(index)",
        text: isSelected ? (selectedText ?? message) : message,
        traversalIndex: 3 + index * 3,
        ancestors: conversationPath(
          messageIndex: index,
          messageFrame: frame,
          focused: focusedContainerMessageIndex == index
        ),
        frame: frame,
        role: "AXStaticText",
        sourceAttribute: isSelected ? .selectedText : .value,
        focused: focusedMessageIndex == index,
        selected: isSelected,
        visible: explicitlyVisible,
        geometryRelationship: geometryRelationship
      )
    }
    return makeSnapshot(nodes: nodes, windowTitle: windowTitle)
  }

  private func conversationPath(
    messageIndex: Int,
    messageFrame: CGRect,
    focused: Bool? = nil
  ) -> [AccessibleNodePathComponent] {
    [
      pathComponent(
        id: "conversation-root",
        role: "AXWebArea",
        index: 0,
        frame: CGRect(x: 300, y: 80, width: 800, height: 700)
      ),
      pathComponent(
        id: "conversation-main",
        role: "AXGroup",
        index: 1,
        frame: CGRect(x: 320, y: 90, width: 760, height: 680)
      ),
      pathComponent(
        id: "message-container-\(messageIndex)",
        role: "AXGroup",
        index: 2 + messageIndex * 3,
        childIndex: messageIndex,
        frame: messageFrame,
        focused: focused
      ),
    ]
  }

  private func pathComponent(
    id: String,
    role: String,
    index: Int,
    childIndex: Int = 0,
    frame: CGRect?,
    focused: Bool? = nil,
    selected: Bool? = nil
  ) -> AccessibleNodePathComponent {
    AccessibleNodePathComponent(
      debugNodeID: id,
      role: role,
      subrole: nil,
      identifier: id,
      traversalIndex: index,
      childIndex: childIndex,
      frame: frame.map(AccessibleFrameSnapshot.init),
      isFocused: focused,
      isSelected: selected
    )
  }

  private func makeProvenanceNode(
    id: String,
    text: String,
    traversalIndex: Int,
    ancestors: [AccessibleNodePathComponent],
    frame: CGRect?,
    role: String = "AXStaticText",
    sourceAttribute: AccessibilityTextSourceAttribute = .value,
    focused: Bool? = nil,
    selected: Bool? = nil,
    visible: Bool? = true,
    geometryRelationship: AccessibleWindowGeometryRelationship = .containedInWindow
  ) -> AccessibleTextNode {
    AccessibleTextNode(
      role: role,
      text: text,
      depth: ancestors.count,
      sourceAttribute: sourceAttribute,
      debugNodeID: id,
      fingerprint: "fingerprint-\(id)",
      subrole: nil,
      identifier: id,
      rawText: text,
      traversalIndex: traversalIndex,
      parentDebugNodeID: ancestors.last?.debugNodeID,
      ancestorPath: ancestors,
      frame: frame.map(AccessibleFrameSnapshot.init),
      isFocused: focused,
      isSelected: selected,
      isEnabled: true,
      isVisible: visible,
      windowGeometryRelationship: geometryRelationship,
      sourceApplication: "Chrome",
      sourceBundleIdentifier: "com.google.Chrome",
      sourceProcessIdentifier: 900,
      sourceWindowIdentity: "com.google.Chrome|900|AXWindow|fixture"
    )
  }

  private func makeSnapshot(
    nodes: [AccessibleTextNode],
    windowTitle: String = "ChatGPT Conversation Fixture"
  ) -> AccessibleTextSnapshot {
    let text = nodes.map(\.text).joined(separator: "\n")
    let date = Date(timeIntervalSince1970: 2_100)
    return AccessibleTextSnapshot(
      window: AccessibleWindowSnapshot(
        application: AccessibleApplicationSnapshot(
          appName: "Chrome",
          bundleIdentifier: "com.google.Chrome",
          processIdentifier: 900,
          observedAt: date,
          source: .accessibility
        ),
        windowTitle: windowTitle,
        windowRole: "AXWindow",
        windowSubrole: "AXStandardWindow",
        observedAt: date,
        source: .accessibility
      ),
      nodes: nodes,
      plainText: text,
      characterCount: text.count,
      nodeCount: nodes.count,
      visitedNodeCount: nodes.count + 3,
      roleCounts: Dictionary(grouping: nodes, by: { $0.role ?? "unknown" })
        .mapValues(\.count),
      truncated: false,
      duration: 0.01
    )
  }

  private func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    return haystack.components(separatedBy: needle).count - 1
  }

  private func makeRequest(
    text: String,
    sequence: Int,
    chunkID: UUID = UUID(),
    contentLength: SemanticContentLengthMetadata? = nil
  ) -> TutorRequest {
    let date = Date(timeIntervalSince1970: TimeInterval(2_000 + sequence))
    return TutorRequest(
      schemaVersion: TutorRequest.currentSchemaVersion,
      id: UUID(),
      sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000009001")!,
      sequence: sequence,
      createdAt: date,
      task: .explainInPlainLanguage,
      trigger: .userInitiated,
      learnerQuestion: nil,
      source: TutorSourceSnapshot(
        chunkID: chunkID,
        sourceRevisionID: sequence,
        text: text,
        diffConfidence: .high,
        flushReason: .manualFlush,
        chunkCreatedAt: date,
        contentLength: contentLength
      ),
      learner: .productDefault(at: date),
      output: .default(),
      policyVersion: TutorRequestFactory.defaultPolicyVersion
    )
  }

  private func makeLongCode(
    targetLength: Int,
    nestedBraces: Bool = false
  ) -> String {
    var code = "// AX_CODE_PREFIX_MARKER\n\n"
    var index = 0
    while code.count < max(1, targetLength - 80) {
      if code.count >= targetLength / 2,
         !code.contains("AX_CODE_MIDDLE_MARKER") {
        code += "// AX_CODE_MIDDLE_MARKER\n\n"
      }
      if nestedBraces {
        code += """
        func generatedFunction\(index)(_ values: [Int]) -> Int {
          var total = 0
          for value in values {
            if value.isMultiple(of: 2) {
              total += value
            } else {
              total += value * 2
            }
          }
          return total
        }

        """
      } else {
        code += """
        func generatedFunction\(index)(_ value: Int) -> Int {
          let adjusted = value + \(index)
          return adjusted * 2
        }

        """
      }
      index += 1
    }
    code += "// AX_CODE_SUFFIX_MARKER\n"
    return code
  }

  private func makeLongProse(targetLength: Int) -> String {
    var prose = "AX_PROSE_PREFIX_MARKER\n\n"
    var index = 0
    while prose.count < max(1, targetLength - 80) {
      if prose.count >= targetLength / 2,
         !prose.contains("AX_PROSE_MIDDLE_MARKER") {
        prose += "AX_PROSE_MIDDLE_MARKER\n\n"
      }
      prose += "第\(index)段用于验证长文章的结构边界。每一段都包含完整句子，长度策略应当在段落结束后停止，而不是从词语或句子的中间切开。\n\n"
      index += 1
    }
    prose += "AX_PROSE_SUFFIX_MARKER。"
    return prose
  }

  private func simpleBraceBalance(_ text: String) -> Int {
    text.reduce(into: 0) { balance, character in
      if "{[(".contains(character) {
        balance += 1
      } else if "}])".contains(character) {
        balance -= 1
      }
    }
  }

  private func makeSnapshot(text: String) -> AccessibleTextSnapshot {
    let date = Date(timeIntervalSince1970: 2_100)
    return AccessibleTextSnapshot(
      window: AccessibleWindowSnapshot(
        application: AccessibleApplicationSnapshot(
          appName: "ChatGPT",
          bundleIdentifier: "com.openai.chat",
          processIdentifier: 900,
          observedAt: date,
          source: .accessibility
        ),
        windowTitle: "Student Analysis",
        windowRole: "AXWindow",
        windowSubrole: "AXStandardWindow",
        observedAt: date,
        source: .accessibility
      ),
      nodes: [
        AccessibleTextNode(
          role: "AXStaticText",
          text: text,
          depth: 3,
          sourceAttribute: .value
        )
      ],
      plainText: text,
      characterCount: text.count,
      nodeCount: 1,
      visitedNodeCount: 1,
      roleCounts: ["AXStaticText": 1],
      truncated: false,
      duration: 0.01
    )
  }

  private func makeRevision(
    text: String,
    window: String,
    characterCount: Int? = nil
  ) -> ContextRevision {
    ContextRevision(
      revisionID: 1,
      timestamp: Date(timeIntervalSince1970: 2_200),
      changeType: .added,
      addedText: text,
      confidence: .high,
      fingerprint: ContextFingerprint(rawValue: window),
      characterCount: characterCount ?? text.count,
      identity: ContextIdentity(
        bundleIdentifier: "com.openai.chat",
        processIdentifier: 900,
        focusedWindowIdentity: FocusedWindowIdentity(rawValue: window),
        liveSessionIdentifier: UUID(
          uuidString: "00000000-0000-0000-0000-000000009002"
        )!
      )
    )
  }

  private var studentProgram: String {
    """
    const students = [
      { name: "小明", score: 82 },
      { name: "小红", score: 95 },
      { name: "小刚", score: 67 },
      { name: "小雨", score: 88 }
    ];

    function getLevel(score) {
      if (score >= 90) {
        return "优秀";
      } else if (score >= 80) {
        return "良好";
      } else if (score >= 60) {
        return "及格";
      } else {
        return "不及格";
      }
    }

    function analyzeStudents(list) {
      let totalScore = 0;

      const result = list.map((student) => {
        totalScore += student.score;

        return {
          name: student.name,
          score: student.score,
          level: getLevel(student.score)
        };
      });

      const average = totalScore / list.length;

      return {
        average,
        students: result
      };
    }

    function delay(ms) {
      return new Promise((resolve) => {
        setTimeout(resolve, ms);
      });
    }

    async function main() {
      console.log("开始分析学生成绩...");

      await delay(1000);

      const report = analyzeStudents(students);

      console.log("平均分：", report.average);

      for (const student of report.students) {
        console.log(
          `${student.name}：${student.score}分，等级：${student.level}`
        );
      }

      console.log("分析完成");
    }

    main();
    """
  }
}
#endif
