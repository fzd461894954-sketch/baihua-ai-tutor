import Darwin
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
    XCTAssertEqual(result.plainText, "First line\nSecond\nline")
    XCTAssertEqual(result.roleCounts["AXStaticText"], 2)
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

  private func makeController(
    context: ContextState,
    authorization: AccessibilityAuthorizationController? = nil,
    reader: MockAccessibilitySnapshotReader,
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

private final class MockAXElement: AXElementReading {
  let values: [AXReadableAttribute: String]
  let children: [MockAXElement]
  private(set) var readAttributes: [AXReadableAttribute] = []
  private(set) var childrenReadCount = 0

  init(
    values: [AXReadableAttribute: String] = [:],
    children: [MockAXElement] = []
  ) {
    self.values = values
    self.children = children
  }

  func stringValue(for attribute: AXReadableAttribute) throws -> String? {
    readAttributes.append(attribute)
    return values[attribute]
  }

  func childElements() throws -> [any AXElementReading] {
    childrenReadCount += 1
    return children
  }
}
