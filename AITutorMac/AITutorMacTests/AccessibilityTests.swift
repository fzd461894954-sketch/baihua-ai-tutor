import Darwin
import ApplicationServices
import Foundation
import XCTest

@testable import AITutorMac

@MainActor
final class AccessibilityTests: XCTestCase {
  private let selfBundleIdentifier = "test.baihua-ai"

  func testPermissionRequiredShowsExplanationWithoutPromptingSystem() {
    let trust = MockAccessibilityTrustProvider(isTrusted: false)
    let authorization = AccessibilityAuthorizationController(
      trustProvider: trust,
      settingsOpener: {}
    )
    let context = contextWithExternalApplication()
    let reader = MockAccessibilitySnapshotReader()
    let controller = makeController(
      context: context,
      authorization: authorization,
      reader: reader
    )

    controller.requestRead()

    XCTAssertEqual(controller.lastError, .permissionRequired)
    XCTAssertTrue(authorization.isShowingPermissionExplanation)
    XCTAssertEqual(trust.promptCount, 0)
    XCTAssertEqual(reader.callCount, 0)
  }

#if DEBUG
  func testAXReadTracePreservesStageOperationAttributeRawErrorAndIdentity() throws {
    let target = application(
      name: "Trace Fixture",
      bundleIdentifier: "test.expected",
      pid: 777
    )
    let store = AXReadTraceStore.shared
    store.begin(target: target, resolvedBundleIdentifier: "test.actual")
    store.setStage(.treeTraversal)
    store.record(
      outcome: .failure,
      operation: "AXUIElementCopyAttributeValue",
      attribute: "AXDescription",
      axError: .failure,
      elementRole: "AXMenuButton"
    )
    store.finish(result: "FAILED · readFailed")

    let trace = try XCTUnwrap(store.latestTrace)
    XCTAssertEqual(trace.targetBundleIdentifier, "test.expected")
    XCTAssertEqual(trace.resolvedBundleIdentifier, "test.actual")
    XCTAssertEqual(trace.events.first?.stage, .identityValidation)
    XCTAssertEqual(trace.events.first?.outcome, .failure)
    let failure = try XCTUnwrap(trace.events.last)
    XCTAssertEqual(failure.stage, .treeTraversal)
    XCTAssertEqual(failure.operation, "AXUIElementCopyAttributeValue")
    XCTAssertEqual(failure.attribute, "AXDescription")
    XCTAssertEqual(failure.axErrorRawValue, AXError.failure.rawValue)
    XCTAssertEqual(failure.axErrorDescription, "failure")
    XCTAssertEqual(failure.elementRole, "AXMenuButton")
  }
#endif

  func testPermissionPromptRequiresContinueAndDoesNotRepeatInSession() {
    let trust = MockAccessibilityTrustProvider(isTrusted: false)
    let authorization = AccessibilityAuthorizationController(
      trustProvider: trust,
      settingsOpener: {}
    )

    authorization.beginPermissionRequest()
    XCTAssertEqual(trust.promptCount, 0)
    authorization.continuePermissionRequest()
    XCTAssertEqual(trust.promptCount, 1)

    authorization.beginPermissionRequest()
    authorization.continuePermissionRequest()
    XCTAssertEqual(trust.promptCount, 1)
  }

  func testSelfTargetIsRejectedBeforeReaderRuns() {
    let context = ContextState()
    context.recordActivation(
      application(
        name: "白话 AI",
        bundleIdentifier: selfBundleIdentifier,
        pid: 201
      ),
      isSelfApplication: false
    )
    let reader = MockAccessibilitySnapshotReader()
    let controller = makeController(context: context, reader: reader)

    controller.requestRead()

    XCTAssertEqual(controller.lastError, .selfTargetRejected)
    XCTAssertEqual(reader.callCount, 0)
  }

  func testSelfPIDIsRejectedWhenBundleIdentifierDoesNotMatch() {
    let context = ContextState()
    context.recordActivation(
      application(
        name: "White-label build",
        bundleIdentifier: "test.unknown",
        pid: 202
      ),
      isSelfApplication: false
    )
    let reader = MockAccessibilitySnapshotReader()
    let controller = makeController(
      context: context,
      reader: reader,
      selfProcessIdentifier: { 202 }
    )

    controller.requestRead()

    XCTAssertEqual(controller.lastError, .selfTargetRejected)
    XCTAssertEqual(reader.callCount, 0)
  }

  func testStalePIDReturnsTargetUnavailableBeforeReaderRuns() {
    let context = contextWithExternalApplication()
    let reader = MockAccessibilitySnapshotReader()
    let controller = makeController(
      context: context,
      reader: reader,
      resolver: MockRunningApplicationResolver(isAvailable: false)
    )

    controller.requestRead()

    XCTAssertEqual(controller.lastError, .targetUnavailable)
    XCTAssertEqual(reader.callCount, 0)
  }

  func testIdentityMismatchBlocksBeforeReaderAndCannotSendWrongApplicationContent() {
    let context = ContextState()
    context.recordActivation(
      application(name: "Expected App", bundleIdentifier: "test.expected", pid: 203),
      isSelfApplication: false
    )
    let reader = MockAccessibilitySnapshotReader()
    let controller = makeController(
      context: context,
      reader: reader,
      resolver: MockRunningApplicationResolver(isAvailable: false)
    )

    controller.requestRead()

    XCTAssertEqual(controller.lastError, .targetUnavailable)
    XCTAssertEqual(reader.callCount, 0)
    XCTAssertNil(controller.snapshot)
  }

  func testTraversalStopsAtDepthLimit() throws {
    let grandchild = MockAXElement(
      values: [.role: "AXStaticText", .value: "grandchild"]
    )
    let child = MockAXElement(
      values: [.role: "AXGroup", .value: "child"],
      children: [grandchild]
    )
    let root = MockAXElement(values: [.role: "AXWindow"], children: [child])
    let result = try extract(
      root,
      limits: AccessibilityTraversalLimits(maxDepth: 1, maxNodes: 20, maxCharacters: 100)
    )

    XCTAssertEqual(result.nodes.map(\.text), ["child"])
    XCTAssertEqual(result.visitedNodeCount, 2)
    XCTAssertTrue(result.truncated)
  }

  func testTraversalStopsAtNodeLimit() throws {
    let third = MockAXElement(values: [.role: "AXStaticText", .value: "third"])
    let second = MockAXElement(values: [.role: "AXStaticText", .value: "second"])
    let root = MockAXElement(
      values: [.role: "AXWindow", .title: "first"],
      children: [second, third]
    )
    let result = try extract(
      root,
      limits: AccessibilityTraversalLimits(maxDepth: 5, maxNodes: 2, maxCharacters: 100)
    )

    XCTAssertEqual(result.nodes.map(\.text), ["first", "second"])
    XCTAssertEqual(result.visitedNodeCount, 2)
    XCTAssertTrue(result.truncated)
  }

  func testTraversalStopsAtCharacterLimit() throws {
    let root = MockAXElement(
      values: [.role: "AXStaticText", .value: "123456"]
    )
    let result = try extract(
      root,
      limits: AccessibilityTraversalLimits(maxDepth: 5, maxNodes: 5, maxCharacters: 4)
    )

    XCTAssertEqual(result.plainText, "1234")
    XCTAssertEqual(result.plainText.count, 4)
    XCTAssertTrue(result.truncated)
  }

  func testExactDuplicateTextIsKeptOnce() throws {
    let child = MockAXElement(
      values: [.role: "AXStaticText", .value: " repeated text "]
    )
    let root = MockAXElement(
      values: [
        .role: "AXGroup",
        .title: "repeated text",
        .value: "repeated text",
      ],
      children: [child]
    )

    let result = try extract(root)

    XCTAssertEqual(result.nodes.count, 1)
    XCTAssertEqual(result.plainText, "repeated text")
    XCTAssertFalse(result.truncated)
  }

  func testSecureTextFieldAndChildrenAreNeverRead() throws {
    let child = MockAXElement(
      values: [.role: "AXStaticText", .value: "nested secret"]
    )
    let secure = MockAXElement(
      values: [.role: "AXSecureTextField", .value: "secret"],
      children: [child]
    )

    let result = try extract(secure)

    XCTAssertTrue(result.nodes.isEmpty)
    XCTAssertEqual(result.plainText, "")
    XCTAssertFalse(secure.readAttributes.contains(.value))
    XCTAssertEqual(secure.childrenReadCount, 0)
  }

  func testOptionalDescriptionFailureDoesNotDiscardReliableFocusedValue() throws {
    let editor = MockAXElement(
      values: [
        .role: "AXTextArea",
        .value: "AX_FOCUSED_RELIABLE_MARKER",
      ],
      booleans: [.focused: true],
      attributeErrors: [.accessibilityDescription: MockAXFailure.unreadable]
    )

    let result = try extract(editor)

    XCTAssertEqual(result.plainText, "AX_FOCUSED_RELIABLE_MARKER")
    XCTAssertEqual(result.nodes.first?.isFocused, true)
    XCTAssertTrue(editor.readAttributes.contains(.accessibilityDescription))
  }

  func testRequiredRoleFailureStillFailsClosed() {
    let editor = MockAXElement(
      values: [.value: "must not escape"],
      attributeErrors: [.role: MockAXFailure.unreadable]
    )

    XCTAssertThrowsError(try extract(editor)) { error in
      XCTAssertEqual(error as? AccessibilityReaderError, .readFailed)
    }
  }

  func testSelectedTextRemainsExactWhenOptionalDescriptionFails() throws {
    let selected = "AX_SELECTED_ONLY_MARKER"
    let editor = MockAXElement(
      values: [
        .role: "AXTextArea",
        .value: "prefix \(selected) suffix",
        .selectedText: selected,
      ],
      booleans: [.focused: true, .selected: true],
      attributeErrors: [.accessibilityDescription: MockAXFailure.unreadable]
    )
    let result = try extract(editor)
    let selectedNode = try XCTUnwrap(
      result.nodes.first(where: { $0.sourceAttribute == .selectedText })
    )

    XCTAssertEqual(selectedNode.text, selected)
    XCTAssertEqual(selectedNode.rawText, selected)
  }

  func testChildFailureAfterReliableFocusedTextDoesNotDiscardContent() throws {
    let editor = MockAXElement(
      values: [
        .role: "AXTextArea",
        .value: "AX_CHILD_FAILURE_TARGET",
      ],
      booleans: [.focused: true],
      childrenError: MockAXFailure.unreadable
    )

    let result = try extract(editor)

    XCTAssertEqual(result.plainText, "AX_CHILD_FAILURE_TARGET")
    XCTAssertEqual(result.nodes.first?.isFocused, true)
  }

  func testChildFailureWithoutReliableTextStillFailsClosed() {
    let container = MockAXElement(
      values: [.role: "AXGroup"],
      childrenError: MockAXFailure.unreadable
    )

    XCTAssertThrowsError(try extract(container)) { error in
      XCTAssertEqual(error as? AccessibilityReaderError, .readFailed)
    }
  }

  func testReaderSuccessStillPassesThroughExistingSelectionTrustGate() throws {
    let editor = MockAXElement(
      values: [
        .role: "AXTextArea",
        .value: "AX_READER_TO_SELECTOR_MARKER",
      ],
      booleans: [.focused: true],
      attributeErrors: [.accessibilityDescription: MockAXFailure.unreadable]
    )
    let extraction = try extract(editor)
    let date = Date(timeIntervalSince1970: 2_200)
    let application = AccessibleApplicationSnapshot(
      appName: "Fixture Editor",
      bundleIdentifier: "test.fixture-editor",
      processIdentifier: 220,
      observedAt: date,
      source: .accessibility
    )
    let snapshot = AccessibleTextSnapshot(
      window: AccessibleWindowSnapshot(
        application: application,
        windowTitle: "Fixture",
        windowRole: "AXWindow",
        windowSubrole: "AXStandardWindow",
        observedAt: date,
        source: .accessibility
      ),
      nodes: extraction.nodes,
      plainText: extraction.plainText,
      characterCount: extraction.plainText.count,
      nodeCount: extraction.nodes.count,
      visitedNodeCount: extraction.visitedNodeCount,
      roleCounts: extraction.roleCounts,
      truncated: extraction.truncated,
      duration: 0.01
    )
    let provider = CurrentExplainableContentProvider()
    let sessionID = UUID()
    provider.beginSession(sessionID)

    XCTAssertEqual(
      provider.receiveCurrentSnapshot(snapshot, revisionID: 1, sessionID: sessionID),
      .accepted
    )
    XCTAssertEqual(provider.latestContentSelection?.reason, .focusedElement)
    XCTAssertEqual(provider.latestContentSelection?.transportTrust, .strong)
    XCTAssertEqual(
      try provider.currentSemanticChunk().text,
      "AX_READER_TO_SELECTOR_MARKER"
    )
  }

  func testEmptyTreeProducesStructuredEmptySnapshot() throws {
    let root = MockAXElement()

    let result = try extract(root)

    XCTAssertTrue(result.nodes.isEmpty)
    XCTAssertEqual(result.plainText, "")
    XCTAssertEqual(result.visitedNodeCount, 1)
    XCTAssertFalse(result.truncated)
  }

  func testCancelledTraversalStopsBeforeReadingTree() {
    let root = MockAXElement(values: [.role: "AXStaticText", .value: "text"])
    let token = AccessibilityReadCancellationToken()
    token.cancel()

    XCTAssertThrowsError(
      try AXTextExtractor().extract(from: root, cancellationToken: token)
    ) { error in
      XCTAssertEqual(error as? AccessibilityReaderError, .cancelled)
    }
    XCTAssertTrue(root.readAttributes.isEmpty)
  }

  func testPlainTextCompositionPreservesTraversalOrderAndLineBreaks() throws {
    let first = MockAXElement(
      values: [.role: "AXStaticText", .value: "First   line"]
    )
    let second = MockAXElement(
      values: [.role: "AXStaticText", .value: "Second\nline"]
    )
    let root = MockAXElement(values: [.role: "AXWindow"], children: [first, second])

    let result = try extract(root)

    XCTAssertEqual(result.nodes.map(\.depth), [1, 1])
    XCTAssertEqual(result.plainText, "First   line\nSecond\nline")
    XCTAssertEqual(result.roleCounts["AXStaticText"], 2)
  }

  func testTextExtractionCapturesStableAXNodeProvenanceBeforeFlattening() throws {
    let text = MockAXElement(
      values: [
        .role: "AXStaticText",
        .subrole: "AXContent",
        .identifier: "fixture-current-code",
        .value: "const value = 8;",
        .selectedText: "value = 8",
        .accessibilityDescription: "current code",
      ],
      booleans: [
        .focused: true,
        .selected: true,
        .enabled: true,
        .visible: true,
      ],
      frame: CGRect(x: 420, y: 180, width: 500, height: 80)
    )
    let container = MockAXElement(
      values: [.role: "AXGroup", .identifier: "fixture-message"],
      children: [text],
      frame: CGRect(x: 400, y: 140, width: 540, height: 150)
    )
    let root = MockAXElement(
      values: [.role: "AXWebArea"],
      children: [container],
      frame: CGRect(x: 300, y: 80, width: 800, height: 700)
    )
    let date = Date(timeIntervalSince1970: 123)
    let application = AccessibleApplicationSnapshot(
      appName: "Chrome",
      bundleIdentifier: "com.google.Chrome",
      processIdentifier: 321,
      observedAt: date,
      source: .accessibility
    )
    let window = AccessibleWindowSnapshot(
      application: application,
      windowTitle: "Fixture Conversation",
      windowRole: "AXWindow",
      windowSubrole: "AXStandardWindow",
      observedAt: date,
      source: .accessibility
    )
    let extractor = AXTextExtractor()
    let first = try extractor.extract(
      from: root,
      cancellationToken: AccessibilityReadCancellationToken(),
      sourceApplication: application,
      sourceWindow: window,
      windowFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
    )
    let second = try extractor.extract(
      from: root,
      cancellationToken: AccessibilityReadCancellationToken(),
      sourceApplication: application,
      sourceWindow: window,
      windowFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
    )
    let node = try XCTUnwrap(first.nodes.first(where: { $0.sourceAttribute == .value }))
    let selectedNode = try XCTUnwrap(
      first.nodes.first(where: { $0.sourceAttribute == .selectedText })
    )

    XCTAssertEqual(node.debugNodeID, second.nodes.first(where: {
      $0.sourceAttribute == .value
    })?.debugNodeID)
    XCTAssertTrue(node.debugNodeID.hasPrefix("AXN-0002-"))
    XCTAssertEqual(node.identifier, "fixture-current-code")
    XCTAssertEqual(node.subrole, "AXContent")
    XCTAssertEqual(node.traversalIndex, 2)
    XCTAssertEqual(node.parentDebugNodeID, node.ancestorPath.last?.debugNodeID)
    XCTAssertEqual(node.ancestorPath.map(\.role), ["AXWebArea", "AXGroup"])
    XCTAssertEqual(node.frame?.cgRect, CGRect(x: 420, y: 180, width: 500, height: 80))
    XCTAssertEqual(node.windowGeometryRelationship, .containedInWindow)
    XCTAssertEqual(node.isFocused, true)
    XCTAssertEqual(node.isSelected, true)
    XCTAssertEqual(node.isEnabled, true)
    XCTAssertEqual(node.isVisible, true)
    XCTAssertEqual(node.sourceApplication, "Chrome")
    XCTAssertEqual(node.sourceBundleIdentifier, "com.google.Chrome")
    XCTAssertEqual(node.sourceProcessIdentifier, 321)
    XCTAssertTrue(node.sourceWindowIdentity?.contains("Fixture Conversation") == true)
    XCTAssertEqual(node.rawText, "const value = 8;")
    XCTAssertFalse(node.fingerprint.isEmpty)
    XCTAssertEqual(selectedNode.text, "value = 8")
  }

  func testWorkBuddyContentRootExcludesSidebarAndKeepsConversationPane() throws {
    let sidebarText = MockAXElement(
      values: [.role: "AXStaticText", .value: "旧任务列表"]
    )
    let sidebar = MockAXElement(
      values: [.role: "AXGroup"],
      children: [sidebarText],
      frame: CGRect(x: 0, y: 0, width: 280, height: 800)
    )
    let conversationText = MockAXElement(
      values: [.role: "AXStaticText", .value: "当前 WorkBuddy 对话内容"]
    )
    let composer = MockAXElement(
      values: [.role: "AXTextArea", .value: "今天帮你做些什么？"],
      frame: CGRect(x: 380, y: 700, width: 620, height: 70)
    )
    let conversationPane = MockAXElement(
      values: [.role: "AXGroup"],
      children: [conversationText, composer],
      frame: CGRect(x: 300, y: 80, width: 780, height: 700)
    )
    let window = MockAXElement(
      values: [.role: "AXWindow", .title: "WorkBuddy"],
      children: [sidebar, conversationPane],
      frame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
    )
    let target = application(
      name: "WorkBuddy",
      bundleIdentifier: "com.workbuddy.workbuddy",
      pid: 41526
    )

    let selected = AXContentRootSelector().selectRoot(
      for: target,
      focusedWindow: window
    )
    let result = try AXTextExtractor().extract(
      from: selected,
      cancellationToken: AccessibilityReadCancellationToken()
    )

    XCTAssertTrue((selected as? MockAXElement) === conversationPane)
    XCTAssertTrue(result.plainText.contains("当前 WorkBuddy 对话内容"))
    XCTAssertFalse(result.plainText.contains("旧任务列表"))
  }

  func testRegularApplicationKeepsFocusedWindowAsContentRoot() {
    let window = MockAXElement(
      values: [.role: "AXWindow"],
      frame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
    )
    let target = application(
      name: "Xcode",
      bundleIdentifier: "com.apple.dt.Xcode",
      pid: 200
    )

    let selected = AXContentRootSelector().selectRoot(
      for: target,
      focusedWindow: window
    )

    XCTAssertTrue((selected as? MockAXElement) === window)
  }

  func testBrowserConversationRootExcludesToolbarAndHistorySidebar() throws {
    let toolbarText = MockAXElement(
      values: [.role: "AXStaticText", .value: "地址和搜索栏"]
    )
    let toolbar = MockAXElement(
      values: [.role: "AXToolbar"],
      children: [toolbarText],
      frame: CGRect(x: 0, y: 0, width: 1_200, height: 80)
    )
    let historyText = MockAXElement(
      values: [.role: "AXStaticText", .value: "历史聊天记录"]
    )
    let sidebar = MockAXElement(
      values: [.role: "AXGroup"],
      children: [historyText],
      frame: CGRect(x: 0, y: 80, width: 280, height: 720)
    )
    let answer = MockAXElement(
      values: [.role: "AXStaticText", .value: "浏览器页面中的当前回答"]
    )
    let composer = MockAXElement(
      values: [.role: "AXTextArea", .value: "问问 ChatGPT"],
      frame: CGRect(x: 390, y: 700, width: 650, height: 60)
    )
    let conversationPane = MockAXElement(
      values: [.role: "AXGroup"],
      children: [answer, composer],
      frame: CGRect(x: 300, y: 90, width: 800, height: 690)
    )
    let webArea = MockAXElement(
      values: [.role: "AXWebArea"],
      children: [sidebar, conversationPane],
      frame: CGRect(x: 0, y: 80, width: 1_200, height: 720)
    )
    let window = MockAXElement(
      values: [.role: "AXWindow"],
      children: [toolbar, webArea],
      frame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
    )
    let target = application(
      name: "Chrome",
      bundleIdentifier: "com.google.Chrome",
      pid: 201
    )

    let selected = AXContentRootSelector().selectRoot(
      for: target,
      focusedWindow: window
    )
    let result = try AXTextExtractor().extract(
      from: selected,
      cancellationToken: AccessibilityReadCancellationToken()
    )

    XCTAssertTrue((selected as? MockAXElement) === conversationPane)
    XCTAssertTrue(result.plainText.contains("浏览器页面中的当前回答"))
    XCTAssertFalse(result.plainText.contains("历史聊天记录"))
    XCTAssertFalse(result.plainText.contains("地址和搜索栏"))
  }

  func testBrowserWithoutComposerFallsBackToLargestWebArea() {
    let webArea = MockAXElement(
      values: [.role: "AXWebArea"],
      children: [MockAXElement(values: [.role: "AXStaticText", .value: "网页正文"])],
      frame: CGRect(x: 0, y: 80, width: 1_200, height: 720)
    )
    let window = MockAXElement(
      values: [.role: "AXWindow"],
      children: [webArea],
      frame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
    )
    let target = application(
      name: "Safari",
      bundleIdentifier: "com.apple.Safari",
      pid: 202
    )

    let selected = AXContentRootSelector().selectRoot(
      for: target,
      focusedWindow: window
    )

    XCTAssertTrue((selected as? MockAXElement) === webArea)
  }

  func testTargetChangeCancelsLongReadAndDiscardsResult() async {
    let context = contextWithExternalApplication()
    let reader = MockAccessibilitySnapshotReader(delay: 0.15)
    let controller = makeController(context: context, reader: reader, timeout: 1)
    controller.requestRead()
    XCTAssertTrue(controller.isReading)

    controller.targetApplicationDidChange()
    try? await Task.sleep(nanoseconds: 250_000_000)

    XCTAssertFalse(controller.isReading)
    XCTAssertNil(controller.snapshot)
    XCTAssertNil(controller.lastError)
  }

  func testTimeoutReturnsFriendlyErrorWithoutBlockingMainActor() async {
    let context = contextWithExternalApplication()
    let reader = MockAccessibilitySnapshotReader(delay: 0.08)
    let controller = makeController(context: context, reader: reader, timeout: 0.01)
    controller.requestRead()

    for _ in 0..<30 where controller.isReading {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertFalse(controller.isReading)
    XCTAssertEqual(controller.lastError, .timedOut)
    XCTAssertNil(controller.snapshot)
  }

  func testExplicitResolveReadsExternalTargetWithoutLiveSession() async throws {
    let context = contextWithExternalApplication()
    let target = try XCTUnwrap(context.lastExternalApplication)
    let expectedSnapshot = AccessibleTextSnapshot(
      window: AccessibleWindowSnapshot(
        application: AccessibleApplicationSnapshot(
          appName: target.localizedName,
          bundleIdentifier: target.bundleIdentifier,
          processIdentifier: target.processIdentifier,
          observedAt: Date(),
          source: .accessibility
        ),
        windowTitle: "ChatGPT",
        windowRole: "AXWindow",
        windowSubrole: "AXStandardWindow",
        observedAt: Date(),
        source: .accessibility
      ),
      nodes: [],
      plainText: "当前 ChatGPT 回答",
      characterCount: 12,
      nodeCount: 0,
      visitedNodeCount: 1,
      roleCounts: [:],
      truncated: false,
      duration: 0.01
    )
    let reader = SuccessfulAccessibilitySnapshotReader(snapshot: expectedSnapshot)
    let controller = makeController(context: context, reader: reader)

    let snapshot = try await controller.resolveSnapshot(target: target)

    XCTAssertEqual(snapshot, expectedSnapshot)
    XCTAssertEqual(reader.callCount, 1)
    XCTAssertFalse(controller.isReading)
  }

  private func makeController(
    context: ContextState,
    authorization: AccessibilityAuthorizationController? = nil,
    reader: any AccessibilitySnapshotReading,
    resolver: MockRunningApplicationResolver? = nil,
    selfProcessIdentifier: @escaping () -> pid_t = {
      ProcessInfo.processInfo.processIdentifier
    },
    timeout: TimeInterval = 1
  ) -> AccessibilitySnapshotController {
    AccessibilitySnapshotController(
      contextState: context,
      authorizationController: authorization ?? AccessibilityAuthorizationController(
        trustProvider: MockAccessibilityTrustProvider(isTrusted: true),
        settingsOpener: {}
      ),
      reader: reader,
      applicationResolver: resolver ?? MockRunningApplicationResolver(isAvailable: true),
      selfBundleIdentifier: { [selfBundleIdentifier] in selfBundleIdentifier },
      selfProcessIdentifier: selfProcessIdentifier,
      timeout: timeout
    )
  }

  private func contextWithExternalApplication() -> ContextState {
    let context = ContextState()
    context.recordActivation(
      application(name: "ChatGPT", bundleIdentifier: "com.openai.codex", pid: 200),
      isSelfApplication: false
    )
    return context
  }

  private func application(
    name: String,
    bundleIdentifier: String,
    pid: pid_t
  ) -> ActiveApplicationSnapshot {
    ActiveApplicationSnapshot(
      localizedName: name,
      bundleIdentifier: bundleIdentifier,
      processIdentifier: pid,
      observedAt: Date(timeIntervalSince1970: TimeInterval(pid))
    )
  }

  private func extract(
    _ root: MockAXElement,
    limits: AccessibilityTraversalLimits = .default
  ) throws -> AXTextExtractionResult {
    try AXTextExtractor(limits: limits).extract(
      from: root,
      cancellationToken: AccessibilityReadCancellationToken()
    )
  }
}

private final class MockAccessibilityTrustProvider: AccessibilityTrustProviding {
  var trusted: Bool
  private(set) var promptCount = 0

  init(isTrusted: Bool) {
    trusted = isTrusted
  }

  func isTrusted() -> Bool {
    trusted
  }

  func requestSystemPrompt() {
    promptCount += 1
  }
}

@MainActor
private struct MockRunningApplicationResolver: RunningApplicationResolving {
  let isAvailableValue: Bool

  init(isAvailable: Bool) {
    isAvailableValue = isAvailable
  }

  func isAvailable(_ target: ActiveApplicationSnapshot) -> Bool {
    isAvailableValue
  }
}

private final class MockAccessibilitySnapshotReader: AccessibilitySnapshotReading {
  private let lock = NSLock()
  private let delay: TimeInterval
  private var storedCallCount = 0

  var callCount: Int {
    lock.withLock { storedCallCount }
  }

  init(delay: TimeInterval = 0) {
    self.delay = delay
  }

  func readSnapshot(
    target: ActiveApplicationSnapshot,
    cancellationToken: AccessibilityReadCancellationToken
  ) throws -> AccessibleTextSnapshot {
    lock.withLock { storedCallCount += 1 }
    if delay > 0 {
      Thread.sleep(forTimeInterval: delay)
    }
    try cancellationToken.checkCancellation()
    throw AccessibilityReaderError.readFailed
  }
}

private final class SuccessfulAccessibilitySnapshotReader: AccessibilitySnapshotReading {
  private let lock = NSLock()
  private let snapshot: AccessibleTextSnapshot
  private var storedCallCount = 0

  var callCount: Int {
    lock.withLock { storedCallCount }
  }

  init(snapshot: AccessibleTextSnapshot) {
    self.snapshot = snapshot
  }

  func readSnapshot(
    target: ActiveApplicationSnapshot,
    cancellationToken: AccessibilityReadCancellationToken
  ) throws -> AccessibleTextSnapshot {
    lock.withLock { storedCallCount += 1 }
    try cancellationToken.checkCancellation()
    return snapshot
  }
}

private final class MockAXElement: AXElementReading {
  let values: [AXReadableAttribute: String]
  let booleans: [AXReadableBooleanAttribute: Bool]
  let children: [MockAXElement]
  let frame: CGRect?
  let attributeErrors: [AXReadableAttribute: Error]
  let childrenError: Error?
  private(set) var readAttributes: [AXReadableAttribute] = []
  private(set) var childrenReadCount = 0

  init(
    values: [AXReadableAttribute: String] = [:],
    children: [MockAXElement] = [],
    booleans: [AXReadableBooleanAttribute: Bool] = [:],
    frame: CGRect? = nil,
    attributeErrors: [AXReadableAttribute: Error] = [:],
    childrenError: Error? = nil
  ) {
    self.values = values
    self.children = children
    self.booleans = booleans
    self.frame = frame
    self.attributeErrors = attributeErrors
    self.childrenError = childrenError
  }

  func stringValue(for attribute: AXReadableAttribute) throws -> String? {
    readAttributes.append(attribute)
    if let error = attributeErrors[attribute] {
      throw error
    }
    return values[attribute]
  }

  func childElements() throws -> [any AXElementReading] {
    childrenReadCount += 1
    if let childrenError {
      throw childrenError
    }
    return children
  }

  func booleanValue(for attribute: AXReadableBooleanAttribute) throws -> Bool? {
    booleans[attribute]
  }

  func elementFrame() throws -> CGRect? {
    frame
  }
}

private enum MockAXFailure: Error {
  case unreadable
}
