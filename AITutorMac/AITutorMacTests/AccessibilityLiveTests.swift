import Darwin
import Foundation
import XCTest

@testable import AITutorMac

@MainActor
final class AccessibilityLiveTests: XCTestCase {
  private let selfBundleIdentifier = "test.baihua-ai"

  func testObserverLifecycleIgnoresDuplicateStartAndStopsCleanly() {
    let harness = makeHarness()

    harness.monitor.start()
    harness.monitor.start()

    XCTAssertEqual(harness.monitor.state, .watching)
    XCTAssertEqual(harness.observer.startCallCount, 1)
    XCTAssertTrue(harness.observer.isRunning)

    harness.monitor.stop()

    XCTAssertEqual(harness.monitor.state, .off)
    XCTAssertEqual(harness.observer.stopCallCount, 1)
    XCTAssertFalse(harness.observer.isRunning)
  }

  func testUnsupportedNotificationsDoNotPreventWatching() {
    let observer = FakeAXObserverAdapter(
      supportedNotifications: ["AXValueChanged"],
      unsupportedNotifications: ["AXCreated", "AXLayoutChanged"]
    )
    let harness = makeHarness(observer: observer)

    harness.monitor.start()

    XCTAssertEqual(harness.monitor.state, .watching)
    XCTAssertEqual(harness.monitor.observerCreateResult, 0)
    XCTAssertEqual(harness.monitor.supportedNotifications, ["AXValueChanged"])
    XCTAssertEqual(harness.monitor.unsupportedNotifications, ["AXCreated", "AXLayoutChanged"])
    XCTAssertEqual(harness.monitor.notificationRegistrationResults.count, 3)
  }

  func testObserverCreateFailureKeepsTargetAndErrorCodeForDiagnosis() {
    let observer = FakeAXObserverAdapter(observerCreateErrorCode: -25204)
    let harness = makeHarness(observer: observer)

    harness.monitor.start()

    XCTAssertEqual(harness.monitor.state, .error)
    XCTAssertEqual(harness.monitor.lockedTarget?.bundleIdentifier, "com.openai.codex")
    XCTAssertEqual(harness.monitor.lockedTarget?.processIdentifier, 200)
    XCTAssertEqual(harness.monitor.observerCreateResult, -25204)
    XCTAssertFalse(observer.isRunning)
  }

  func testPermissionAndSelfTargetAreRejectedBeforeObserverStarts() {
    let deniedHarness = makeHarness(isTrusted: false)
    deniedHarness.monitor.start()
    XCTAssertEqual(deniedHarness.monitor.state, .permissionRequired)
    XCTAssertEqual(deniedHarness.observer.startCallCount, 0)

    let selfContext = ContextState()
    selfContext.recordActivation(
      application(name: "白话 AI", bundleIdentifier: selfBundleIdentifier, pid: 900),
      isSelfApplication: false
    )
    let selfHarness = makeHarness(context: selfContext, selfPID: 900)
    selfHarness.monitor.start()
    XCTAssertEqual(selfHarness.monitor.state, .targetUnavailable)
    XCTAssertEqual(selfHarness.observer.startCallCount, 0)
  }

  func testPermissionRevocationStopsAnActiveObserverSafely() {
    let harness = makeHarness()
    harness.monitor.start()

    harness.trustProvider.trusted = false
    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)

    XCTAssertEqual(harness.monitor.state, .permissionRequired)
    XCTAssertFalse(harness.observer.isRunning)
    XCTAssertEqual(harness.requester.startCallCount, 0)
  }

  func testTerminationAndPIDReplacementNeverRetargetTheSession() {
    let harness = makeHarness()
    harness.monitor.start()
    let originalTarget = try! XCTUnwrap(harness.monitor.lockedTarget)

    harness.monitor.lastExternalApplicationDidChange(
      application(
        name: "ChatGPT",
        bundleIdentifier: "com.openai.codex",
        pid: originalTarget.processIdentifier + 1
      )
    )

    XCTAssertEqual(harness.monitor.state, .targetUnavailable)
    XCTAssertEqual(harness.monitor.lockedTarget?.processIdentifier, originalTarget.processIdentifier)
    XCTAssertEqual(harness.observer.stopCallCount, 1)

    let secondHarness = makeHarness()
    secondHarness.monitor.start()
    secondHarness.monitor.targetApplicationDidTerminate(
      application(name: "ChatGPT", bundleIdentifier: "com.openai.codex", pid: 200)
    )
    XCTAssertEqual(secondHarness.monitor.state, .targetUnavailable)
    XCTAssertFalse(secondHarness.observer.isRunning)
  }

  func testLeavingTargetPausesAndReturningResumesWithoutRetargeting() {
    let harness = makeHarness()
    harness.monitor.start()

    harness.monitor.lastExternalApplicationDidChange(
      application(name: "Safari", bundleIdentifier: "com.apple.Safari", pid: 201)
    )
    XCTAssertEqual(harness.monitor.state, .paused)
    XCTAssertEqual(harness.monitor.lockedTarget?.processIdentifier, 200)

    harness.monitor.lastExternalApplicationDidChange(
      application(name: "ChatGPT", bundleIdentifier: "com.openai.codex", pid: 200)
    )
    XCTAssertEqual(harness.monitor.state, .watching)
    XCTAssertEqual(harness.monitor.lockedTarget?.processIdentifier, 200)
  }

  func testCoalescerAppliesRateLimitAndTrailingEventRules() {
    let configuration = AccessibilityLiveConfiguration(
      minimumSnapshotInterval: 1,
      trailingSnapshotDelay: 0.5
    )
    let coalescer = AXEventCoalescer(configuration: configuration)
    let start = Date(timeIntervalSince1970: 1_000)

    XCTAssertEqual(coalescer.recordEvent(at: start), .startNow)
    coalescer.snapshotDidStart(at: start)
    XCTAssertEqual(
      coalescer.recordEvent(at: start.addingTimeInterval(0.1)),
      .none
    )
    XCTAssertEqual(
      coalescer.snapshotDidFinish(at: start.addingTimeInterval(0.2)),
      .wait(until: start.addingTimeInterval(1))
    )
    XCTAssertEqual(
      coalescer.rateLimitDeadlineDidArrive(at: start.addingTimeInterval(1)),
      .startNow
    )
    XCTAssertEqual(
      coalescer.trailingDeadlineDidArrive(
        for: start.addingTimeInterval(0.05),
        at: start.addingTimeInterval(1.1)
      ),
      .none
    )
  }

  func testSingleFlightCoalescesDirtyEventsThenPerformsTrailingRead() async {
    let harness = makeHarness(configuration: fastConfiguration)
    harness.monitor.start()

    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    XCTAssertEqual(harness.requester.startCallCount, 1)
    XCTAssertTrue(harness.requester.isReading)

    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    XCTAssertEqual(harness.requester.startCallCount, 1)
    XCTAssertGreaterThanOrEqual(harness.monitor.eventsCoalesced, 1)

    harness.requester.complete(.success(snapshot(text: "first")))
    await waitFor { harness.requester.startCallCount == 2 }

    XCTAssertEqual(harness.requester.maximumConcurrentRequests, 1)
  }

  func testNotificationDistributionTracksObservedEventTypes() {
    let harness = makeHarness()
    harness.monitor.start()

    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    harness.observer.emit(notificationName: "AXCreated", processIdentifier: 200)

    XCTAssertEqual(
      harness.monitor.eventCountsByNotification,
      ["AXValueChanged": 2, "AXCreated": 1]
    )
  }

  func testTransientSnapshotFailureKeepsWatchingAndNextSuccessRecovers() async {
    let harness = makeHarness(configuration: fastConfiguration)
    harness.monitor.start()

    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    harness.requester.complete(.failure(.readFailed))

    XCTAssertEqual(harness.monitor.state, .watching)
    XCTAssertTrue(harness.observer.isRunning)
    XCTAssertEqual(harness.monitor.lastError, .readFailed)

    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    await waitFor { harness.requester.isReading }
    harness.requester.complete(.success(snapshot(text: "recovered")))

    XCTAssertEqual(harness.monitor.state, .watching)
    XCTAssertNil(harness.monitor.lastError)
    XCTAssertEqual(harness.monitor.snapshotsGenerated, 1)
    XCTAssertEqual(harness.monitor.revision, 0)
  }

  func testIdenticalFingerprintKeepsRevisionAndDifferentTextCreatesNewRevision() async {
    let harness = makeHarness(configuration: fastConfiguration)
    harness.monitor.start()

    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    harness.requester.complete(.success(snapshot(text: "same")))
    XCTAssertEqual(harness.monitor.revision, 0)
    XCTAssertFalse(harness.monitor.isLatestSnapshotVisible)

    try? await Task.sleep(nanoseconds: 30_000_000)
    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    await waitFor { harness.requester.isReading }
    harness.requester.complete(.success(snapshot(text: "same")))
    XCTAssertEqual(harness.monitor.revision, 0)

    try? await Task.sleep(nanoseconds: 30_000_000)
    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    await waitFor { harness.requester.isReading }
    harness.requester.complete(.success(snapshot(text: "different")))
    XCTAssertEqual(harness.monitor.revision, 1)

    harness.monitor.showLatestSnapshot()
    XCTAssertTrue(harness.monitor.isLatestSnapshotVisible)
    harness.monitor.hideLatestSnapshot()
    XCTAssertFalse(harness.monitor.isLatestSnapshotVisible)
  }

  func testLiveRevisionFlowsIntoSemanticChunkWithoutRetainingHistory() async {
    let harness = makeHarness(configuration: fastConfiguration)
    var chunks: [SemanticChunk] = []
    harness.monitor.semanticBuffer.onChunk = { chunks.append($0) }
    harness.monitor.start()

    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    harness.requester.complete(.success(snapshot(text: "Answer")))
    XCTAssertTrue(chunks.isEmpty)

    try? await Task.sleep(nanoseconds: 30_000_000)
    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    await waitFor { harness.requester.isReading }
    harness.requester.complete(.success(snapshot(text: "Answer completed.")))

    XCTAssertEqual(chunks.map(\.text), ["completed."])
    XCTAssertEqual(chunks.first?.flushReason, .sentenceComplete)
    XCTAssertEqual(harness.monitor.semanticBuffer.chunkCount, 1)
    XCTAssertEqual(harness.monitor.semanticBuffer.pendingCharacterCount, 0)
  }

  func testThirtyStartStopCyclesLeaveNoObserverRunning() {
    let harness = makeHarness()

    for _ in 0..<30 {
      harness.monitor.start()
      harness.monitor.stop()
    }

    XCTAssertEqual(harness.observer.startCallCount, 30)
    XCTAssertEqual(harness.observer.stopCallCount, 30)
    XCTAssertEqual(harness.monitor.state, .off)
    XCTAssertFalse(harness.observer.isRunning)
  }

  func testStopClearsRevisionAndSemanticBufferState() {
    let harness = makeHarness()
    harness.monitor.start()
    harness.observer.emit(notificationName: "AXValueChanged", processIdentifier: 200)
    harness.requester.complete(.success(snapshot(text: "in-memory context")))

    XCTAssertNotNil(harness.monitor.contextRevisionPipeline.currentIdentity)
    XCTAssertNotNil(harness.monitor.contextRevisionPipeline.latestRevision)
    let baseline = try! XCTUnwrap(harness.monitor.contextRevisionPipeline.latestRevision)
    harness.monitor.semanticBuffer.ingest(
      ContextRevision(
        revisionID: 1,
        timestamp: Date(),
        changeType: .added,
        addedText: "pending semantic content",
        confidence: .high,
        fingerprint: ContextFingerprint(rawValue: "pending"),
        characterCount: baseline.characterCount + 24,
        identity: baseline.identity
      )
    )
    XCTAssertGreaterThan(harness.monitor.semanticBuffer.pendingCharacterCount, 0)
    XCTAssertTrue(harness.monitor.semanticBuffer.hasScheduledFlushTask)

    harness.monitor.stop()

    XCTAssertNil(harness.monitor.contextRevisionPipeline.currentIdentity)
    XCTAssertNil(harness.monitor.contextRevisionPipeline.latestNormalizedText)
    XCTAssertNil(harness.monitor.contextRevisionPipeline.latestFingerprint)
    XCTAssertNil(harness.monitor.contextRevisionPipeline.latestRevision)
    XCTAssertNil(harness.monitor.semanticBuffer.currentIdentity)
    XCTAssertEqual(harness.monitor.semanticBuffer.pendingCharacterCount, 0)
    XCTAssertEqual(harness.monitor.semanticBuffer.chunkCount, 0)
    XCTAssertFalse(harness.monitor.semanticBuffer.hasScheduledFlushTask)
  }

  private var fastConfiguration: AccessibilityLiveConfiguration {
    AccessibilityLiveConfiguration(
      minimumSnapshotInterval: 0.02,
      trailingSnapshotDelay: 0.01
    )
  }

  private func makeHarness(
    context: ContextState? = nil,
    isTrusted: Bool = true,
    observer: FakeAXObserverAdapter? = nil,
    configuration: AccessibilityLiveConfiguration = .default,
    selfPID: pid_t = 999
  ) -> LiveHarness {
    let actualContext = context ?? ContextState()
    let actualObserver = observer ?? FakeAXObserverAdapter()
    if actualContext.lastExternalApplication == nil {
      actualContext.recordActivation(
        application(name: "ChatGPT", bundleIdentifier: "com.openai.codex", pid: 200),
        isSelfApplication: false
      )
    }
    let trustProvider = LiveTestTrustProvider(isTrusted: isTrusted)
    let authorization = AccessibilityAuthorizationController(
      trustProvider: trustProvider,
      settingsOpener: {}
    )
    let requester = FakeLiveSnapshotRequester()
    let monitor = AccessibilityLiveMonitor(
      contextState: actualContext,
      authorizationController: authorization,
      snapshotRequester: requester,
      applicationResolver: LiveTestApplicationResolver(),
      observerAdapter: actualObserver,
      selfBundleIdentifier: { [selfBundleIdentifier] in selfBundleIdentifier },
      selfProcessIdentifier: { selfPID },
      configuration: configuration
    )
    return LiveHarness(
      monitor: monitor,
      observer: actualObserver,
      requester: requester,
      trustProvider: trustProvider
    )
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
      observedAt: Date()
    )
  }

  private func snapshot(text: String) -> AccessibleTextSnapshot {
    AccessibleTextSnapshot(
      window: AccessibleWindowSnapshot(
        application: AccessibleApplicationSnapshot(
          appName: "ChatGPT",
          bundleIdentifier: "com.openai.codex",
          processIdentifier: 200,
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
      plainText: text,
      characterCount: text.count,
      nodeCount: 0,
      visitedNodeCount: 1,
      roleCounts: [:],
      truncated: false,
      duration: 0.01
    )
  }

  private func waitFor(
    _ condition: @escaping @MainActor () -> Bool
  ) async {
    for _ in 0..<100 {
      if condition() {
        return
      }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for live watch state")
  }
}

@MainActor
private struct LiveHarness {
  let monitor: AccessibilityLiveMonitor
  let observer: FakeAXObserverAdapter
  let requester: FakeLiveSnapshotRequester
  let trustProvider: LiveTestTrustProvider
}

private final class LiveTestTrustProvider: AccessibilityTrustProviding {
  var trusted: Bool

  init(isTrusted: Bool) {
    trusted = isTrusted
  }

  func isTrusted() -> Bool {
    trusted
  }

  func requestSystemPrompt() {}
}

@MainActor
private struct LiveTestApplicationResolver: RunningApplicationResolving {
  func isAvailable(_ target: ActiveApplicationSnapshot) -> Bool {
    true
  }
}

@MainActor
private final class FakeAXObserverAdapter: AXObserverAdapting {
  private(set) var isRunning = false
  let supportedNotifications: [String]
  let unsupportedNotifications: [String]
  private(set) var observerCreateResult: Int32?
  private(set) var notificationRegistrationResults: [AXNotificationRegistrationResult] = []
  private(set) var startCallCount = 0
  private(set) var stopCallCount = 0
  private var onEvent: ((AXChangeEvent) -> Void)?
  private let observerCreateErrorCode: Int32?

  init(
    supportedNotifications: [String] = ["AXValueChanged"],
    unsupportedNotifications: [String] = [],
    observerCreateErrorCode: Int32? = nil
  ) {
    self.supportedNotifications = supportedNotifications
    self.unsupportedNotifications = unsupportedNotifications
    self.observerCreateErrorCode = observerCreateErrorCode
  }

  func start(
    target: ActiveApplicationSnapshot,
    onEvent: @escaping (AXChangeEvent) -> Void
  ) throws {
    guard !isRunning else {
      return
    }
    startCallCount += 1
    observerCreateResult = observerCreateErrorCode ?? 0
    if let observerCreateErrorCode {
      throw AXObserverAdapterError.observerCreationFailed(observerCreateErrorCode)
    }
    isRunning = true
    notificationRegistrationResults = supportedNotifications.map {
      AXNotificationRegistrationResult(notificationName: $0, errorCode: 0)
    } + unsupportedNotifications.map {
      AXNotificationRegistrationResult(notificationName: $0, errorCode: -25205)
    }
    self.onEvent = onEvent
  }

  func stop() {
    guard isRunning else {
      return
    }
    isRunning = false
    stopCallCount += 1
    onEvent = nil
  }

  func emit(notificationName: String, processIdentifier: pid_t) {
    onEvent?(
      AXChangeEvent(
        processIdentifier: processIdentifier,
        notificationName: notificationName,
        observedAt: Date(),
        role: "AXTextArea",
        subrole: nil
      )
    )
  }
}

@MainActor
private final class FakeLiveSnapshotRequester: LiveSnapshotRequesting {
  private(set) var isReading = false
  private(set) var startCallCount = 0
  private(set) var maximumConcurrentRequests = 0
  private var completion: ((Result<AccessibleTextSnapshot, AccessibilityReaderError>) -> Void)?

  @discardableResult
  func requestLiveRead(
    target: ActiveApplicationSnapshot,
    completion: @escaping (Result<AccessibleTextSnapshot, AccessibilityReaderError>) -> Void
  ) -> Bool {
    guard !isReading else {
      return false
    }
    isReading = true
    startCallCount += 1
    maximumConcurrentRequests = max(maximumConcurrentRequests, isReading ? 1 : 0)
    self.completion = completion
    return true
  }

  func cancelLiveRead() {
    guard isReading else {
      return
    }
    isReading = false
    let completion = completion
    self.completion = nil
    completion?(.failure(.cancelled))
  }

  func complete(_ result: Result<AccessibleTextSnapshot, AccessibilityReaderError>) {
    guard isReading else {
      return
    }
    isReading = false
    let completion = completion
    self.completion = nil
    completion?(result)
  }
}
