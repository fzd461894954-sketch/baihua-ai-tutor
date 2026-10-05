import Darwin
import XCTest

@testable import AITutorMac

@MainActor
final class ContextTests: XCTestCase {
  private let selfBundleIdentifier = "test.baihua-ai"

  func testInitialSnapshotIsRecordedWhenMonitoringStarts() {
    let initial = snapshot(name: "Finder", bundleIdentifier: "com.apple.finder", pid: 100)
    let (monitor, state, workspace) = makeMonitor(initial: initial)

    monitor.start()

    XCTAssertEqual(monitor.currentApplication, initial)
    XCTAssertEqual(monitor.lastExternalApplication, initial)
    XCTAssertEqual(state.rawFrontmostApplication, initial)
    XCTAssertEqual(workspace.frontmostReadCount, 1)
  }

  func testExternalApplicationActivationUpdatesBothStates() {
    let (monitor, state, workspace) = makeMonitor()
    let safari = snapshot(name: "Safari", bundleIdentifier: "com.apple.Safari", pid: 101)
    monitor.start()

    workspace.sendActivation(safari)

    XCTAssertEqual(state.rawFrontmostApplication, safari)
    XCTAssertEqual(state.lastExternalApplication, safari)
  }

  func testSelfApplicationDoesNotOverwriteLastExternalApplication() {
    let codex = snapshot(name: "ChatGPT", bundleIdentifier: "com.openai.codex", pid: 102)
    let selfApplication = snapshot(
      name: "白话 AI",
      bundleIdentifier: selfBundleIdentifier,
      pid: 103
    )
    let (monitor, state, workspace) = makeMonitor(initial: codex)
    monitor.start()

    workspace.sendActivation(selfApplication)

    XCTAssertEqual(state.rawFrontmostApplication, selfApplication)
    XCTAssertEqual(state.lastExternalApplication, codex)
  }

  func testExternalAToSelfToExternalBLeavesExternalBAsContext() {
    let finder = snapshot(name: "Finder", bundleIdentifier: "com.apple.finder", pid: 104)
    let selfApplication = snapshot(
      name: "白话 AI",
      bundleIdentifier: selfBundleIdentifier,
      pid: 105
    )
    let safari = snapshot(name: "Safari", bundleIdentifier: "com.apple.Safari", pid: 106)
    let (monitor, state, workspace) = makeMonitor()
    monitor.start()

    workspace.sendActivation(finder)
    workspace.sendActivation(selfApplication)
    workspace.sendActivation(safari)

    XCTAssertEqual(state.rawFrontmostApplication, safari)
    XCTAssertEqual(state.lastExternalApplication, safari)
  }

  func testDuplicateStartDoesNotInstallDuplicateObserversOrReadAgain() {
    let finder = snapshot(name: "Finder", bundleIdentifier: "com.apple.finder", pid: 107)
    let (monitor, _, workspace) = makeMonitor(initial: finder)

    monitor.start()
    monitor.start()

    XCTAssertTrue(monitor.isMonitoring)
    XCTAssertEqual(workspace.activationObservationCount, 1)
    XCTAssertEqual(workspace.terminationObservationCount, 1)
    XCTAssertEqual(workspace.frontmostReadCount, 1)
  }

  func testStopRemovesObserversAndPreventsFurtherUpdates() {
    let finder = snapshot(name: "Finder", bundleIdentifier: "com.apple.finder", pid: 108)
    let safari = snapshot(name: "Safari", bundleIdentifier: "com.apple.Safari", pid: 109)
    let (monitor, state, workspace) = makeMonitor(initial: finder)
    monitor.start()

    monitor.stop()
    workspace.sendActivation(safari)

    XCTAssertFalse(monitor.isMonitoring)
    XCTAssertEqual(workspace.activationObservationCount, 0)
    XCTAssertEqual(workspace.terminationObservationCount, 0)
    XCTAssertEqual(state.rawFrontmostApplication, finder)
    XCTAssertEqual(state.lastExternalApplication, finder)
  }

  func testTerminatedExternalApplicationIsRemovedFromContext() {
    let codex = snapshot(name: "ChatGPT", bundleIdentifier: "com.openai.codex", pid: 110)
    let selfApplication = snapshot(
      name: "白话 AI",
      bundleIdentifier: selfBundleIdentifier,
      pid: 111
    )
    let (monitor, state, workspace) = makeMonitor(initial: codex)
    monitor.start()
    workspace.sendActivation(selfApplication)

    workspace.sendTermination(codex)

    XCTAssertEqual(state.rawFrontmostApplication, selfApplication)
    XCTAssertNil(state.lastExternalApplication)
  }

  func testClassifierFallsBackToOtherForUnknownOrMissingBundleIdentifier() {
    let classifier = TargetApplicationClassifier()
    let unknown = snapshot(name: "Unknown", bundleIdentifier: "example.unknown", pid: 112)
    let missing = snapshot(name: "Missing", bundleIdentifier: nil, pid: 113)

    XCTAssertEqual(classifier.classify(unknown), .other)
    XCTAssertEqual(classifier.classify(missing), .other)
    XCTAssertEqual(classifier.classify(nil), .other)
  }

  func testClassifierUsesObservedBundleIdentifiers() {
    let classifier = TargetApplicationClassifier()

    XCTAssertEqual(
      classifier.classify(
        snapshot(name: "ChatGPT", bundleIdentifier: "com.openai.codex", pid: 114)
      ),
      .codex
    )
    XCTAssertEqual(
      classifier.classify(
        snapshot(
          name: "WorkBuddy",
          bundleIdentifier: "com.workbuddy.workbuddy",
          pid: 117
        )
      ),
      .workBuddy
    )
    XCTAssertEqual(
      classifier.classify(
        snapshot(name: "Safari", bundleIdentifier: "com.apple.Safari", pid: 115)
      ),
      .browser
    )
    XCTAssertEqual(
      classifier.classify(
        snapshot(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", pid: 116)
      ),
      .xcode
    )
  }

  func testRapidThirtyActivationEventsFinishOnLastApplication() {
    let (monitor, state, workspace) = makeMonitor()
    monitor.start()
    var expected: ActiveApplicationSnapshot?

    for index in 0..<30 {
      let application = snapshot(
        name: "Application \(index)",
        bundleIdentifier: "test.external.\(index)",
        pid: pid_t(200 + index)
      )
      expected = application
      workspace.sendActivation(application)
    }

    XCTAssertEqual(state.rawFrontmostApplication, expected)
    XCTAssertEqual(state.lastExternalApplication, expected)
    XCTAssertEqual(workspace.activationObservationCount, 1)
  }

  private func makeMonitor(
    initial: ActiveApplicationSnapshot? = nil
  ) -> (ActiveApplicationMonitor, ContextState, MockApplicationWorkspace) {
    let state = ContextState()
    let workspace = MockApplicationWorkspace(frontmostApplication: initial)
    let monitor = ActiveApplicationMonitor(
      contextState: state,
      workspace: workspace,
      selfBundleIdentifier: { [selfBundleIdentifier] in selfBundleIdentifier }
    )
    return (monitor, state, workspace)
  }

  private func snapshot(
    name: String,
    bundleIdentifier: String?,
    pid: pid_t
  ) -> ActiveApplicationSnapshot {
    ActiveApplicationSnapshot(
      localizedName: name,
      bundleIdentifier: bundleIdentifier,
      processIdentifier: pid,
      observedAt: Date(timeIntervalSince1970: TimeInterval(pid))
    )
  }
}

@MainActor
private final class MockApplicationWorkspace: ApplicationWorkspaceProviding {
  private var storedFrontmostApplication: ActiveApplicationSnapshot?
  private var activationHandlers: [UUID: (ActiveApplicationSnapshot) -> Void] = [:]
  private var terminationHandlers: [UUID: (ActiveApplicationSnapshot) -> Void] = [:]

  private(set) var frontmostReadCount = 0

  var activationObservationCount: Int {
    activationHandlers.count
  }

  var terminationObservationCount: Int {
    terminationHandlers.count
  }

  init(frontmostApplication: ActiveApplicationSnapshot?) {
    storedFrontmostApplication = frontmostApplication
  }

  var frontmostApplication: ActiveApplicationSnapshot? {
    frontmostReadCount += 1
    return storedFrontmostApplication
  }

  func observeApplicationActivations(
    _ handler: @escaping (ActiveApplicationSnapshot) -> Void
  ) -> ApplicationWorkspaceObservation {
    let id = UUID()
    activationHandlers[id] = handler
    return ApplicationWorkspaceObservation { [weak self] in
      self?.activationHandlers[id] = nil
    }
  }

  func observeApplicationTerminations(
    _ handler: @escaping (ActiveApplicationSnapshot) -> Void
  ) -> ApplicationWorkspaceObservation {
    let id = UUID()
    terminationHandlers[id] = handler
    return ApplicationWorkspaceObservation { [weak self] in
      self?.terminationHandlers[id] = nil
    }
  }

  func sendActivation(_ application: ActiveApplicationSnapshot) {
    activationHandlers.values.forEach { $0(application) }
  }

  func sendTermination(_ application: ActiveApplicationSnapshot) {
    terminationHandlers.values.forEach { $0(application) }
  }
}
