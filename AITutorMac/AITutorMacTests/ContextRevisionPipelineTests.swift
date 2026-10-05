import Darwin
import XCTest

@testable import AITutorMac

@MainActor
final class ContextRevisionPipelineTests: XCTestCase {
  private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

  func testFirstSnapshotEstablishesBaselineWithoutWholeScreenAddedText() {
    let pipeline = ContextRevisionPipeline()
    let revision = pipeline.ingest(
      snapshot: snapshot(text: "Existing full window"),
      liveSessionIdentifier: sessionID
    )

    XCTAssertEqual(revision.revisionID, 0)
    XCTAssertEqual(revision.changeType, .baseline)
    XCTAssertEqual(revision.addedText, "")
    XCTAssertEqual(revision.confidence, .high)
    XCTAssertEqual(revision.characterCount, "Existing full window".count)
    XCTAssertEqual(revision.identity.bundleIdentifier, "com.openai.codex")
    XCTAssertEqual(revision.identity.processIdentifier, 200)
    XCTAssertEqual(revision.identity.liveSessionIdentifier, sessionID)
    XCTAssertEqual(pipeline.latestRevision, revision)
  }

  func testSameSnapshotProducesNoChangeWithoutIncrementingRevision() {
    let pipeline = ContextRevisionPipeline()
    let first = snapshot(text: "Build is running")
    pipeline.ingest(snapshot: first, liveSessionIdentifier: sessionID)

    let revision = pipeline.ingest(
      snapshot: first,
      liveSessionIdentifier: sessionID
    )

    XCTAssertEqual(revision.revisionID, 0)
    XCTAssertEqual(revision.changeType, .noChange)
    XCTAssertEqual(revision.addedText, "")
    XCTAssertEqual(revision.confidence, .high)
  }

  func testAppendIncrementsRevisionAndPublishesOnlyAddedText() {
    let pipeline = ContextRevisionPipeline()
    pipeline.ingest(
      snapshot: snapshot(text: "Build"),
      liveSessionIdentifier: sessionID
    )

    let revision = pipeline.ingest(
      snapshot: snapshot(text: "Build succeeded"),
      liveSessionIdentifier: sessionID
    )

    XCTAssertEqual(revision.revisionID, 1)
    XCTAssertEqual(revision.changeType, .added)
    XCTAssertEqual(revision.addedText, "succeeded")
    XCTAssertEqual(revision.confidence, .high)
  }

  func testInsertIncrementsRevisionAndPublishesInsertedText() {
    let pipeline = ContextRevisionPipeline()
    pipeline.ingest(
      snapshot: snapshot(text: "alpha gamma"),
      liveSessionIdentifier: sessionID
    )

    let revision = pipeline.ingest(
      snapshot: snapshot(text: "alpha beta gamma"),
      liveSessionIdentifier: sessionID
    )

    XCTAssertEqual(revision.revisionID, 1)
    XCTAssertEqual(revision.changeType, .added)
    XCTAssertEqual(revision.addedText, "beta")
    XCTAssertEqual(revision.confidence, .high)
  }

  func testUnrelatedTextResetsBaselineWithoutPublishingWholeScreen() {
    let pipeline = ContextRevisionPipeline()
    pipeline.ingest(
      snapshot: snapshot(text: "Installing dependencies"),
      liveSessionIdentifier: sessionID
    )

    let revision = pipeline.ingest(
      snapshot: snapshot(text: "Database migration status"),
      liveSessionIdentifier: sessionID
    )

    XCTAssertEqual(revision.revisionID, 1)
    XCTAssertEqual(revision.changeType, .reset)
    XCTAssertEqual(revision.addedText, "")
    XCTAssertEqual(revision.confidence, .low)
    XCTAssertEqual(pipeline.latestNormalizedText?.displayText, "Database migration status")
  }

  func testPIDChangeResetsIdentityAndRevisionSequence() {
    let pipeline = ContextRevisionPipeline()
    pipeline.ingest(
      snapshot: snapshot(text: "Before", pid: 200),
      liveSessionIdentifier: sessionID
    )
    pipeline.ingest(
      snapshot: snapshot(text: "Before plus", pid: 200),
      liveSessionIdentifier: sessionID
    )

    let revision = pipeline.ingest(
      snapshot: snapshot(text: "Replacement process", pid: 201),
      liveSessionIdentifier: sessionID
    )

    XCTAssertEqual(revision.revisionID, 0)
    XCTAssertEqual(revision.changeType, .reset)
    XCTAssertEqual(revision.addedText, "")
    XCTAssertEqual(revision.confidence, .high)
    XCTAssertEqual(revision.identity.processIdentifier, 201)
  }

  func testFocusedWindowChangeResetsIdentityWithoutEmittingContent() {
    let pipeline = ContextRevisionPipeline()
    let first = pipeline.ingest(
      snapshot: snapshot(text: "First window", windowTitle: "Chat A"),
      liveSessionIdentifier: sessionID
    )

    let revision = pipeline.ingest(
      snapshot: snapshot(text: "Second window", windowTitle: "Chat B"),
      liveSessionIdentifier: sessionID
    )

    XCTAssertNotEqual(
      first.identity.focusedWindowIdentity,
      revision.identity.focusedWindowIdentity
    )
    XCTAssertEqual(revision.revisionID, 0)
    XCTAssertEqual(revision.changeType, .reset)
    XCTAssertEqual(revision.addedText, "")
    XCTAssertEqual(revision.confidence, .high)
  }

  func testSessionChangeResetsIdentityWithoutEmittingContent() {
    let pipeline = ContextRevisionPipeline()
    pipeline.ingest(
      snapshot: snapshot(text: "Session one"),
      liveSessionIdentifier: sessionID
    )
    let nextSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!

    let revision = pipeline.ingest(
      snapshot: snapshot(text: "Session two"),
      liveSessionIdentifier: nextSessionID
    )

    XCTAssertEqual(revision.revisionID, 0)
    XCTAssertEqual(revision.changeType, .reset)
    XCTAssertEqual(revision.addedText, "")
    XCTAssertEqual(revision.identity.liveSessionIdentifier, nextSessionID)
  }

  func testClearRemovesAllSnapshotDerivedState() {
    let pipeline = ContextRevisionPipeline()
    pipeline.ingest(
      snapshot: snapshot(text: "Sensitive in-memory context"),
      liveSessionIdentifier: sessionID
    )

    pipeline.clear()

    XCTAssertNil(pipeline.currentIdentity)
    XCTAssertNil(pipeline.latestNormalizedText)
    XCTAssertNil(pipeline.latestFingerprint)
    XCTAssertNil(pipeline.latestRevision)
  }

  func testOneHundredRevisionsKeepOnlyLatestStateAndRemainSequential() {
    let pipeline = ContextRevisionPipeline()
    var events: [ContextRevision] = []
    pipeline.onRevision = { events.append($0) }
    var text = "stream"
    pipeline.ingest(
      snapshot: snapshot(text: text),
      liveSessionIdentifier: sessionID
    )

    for index in 1...100 {
      text += " \(index)"
      pipeline.ingest(
        snapshot: snapshot(text: text),
        liveSessionIdentifier: sessionID
      )
    }

    XCTAssertEqual(events.count, 101)
    XCTAssertEqual(events.first?.revisionID, 0)
    XCTAssertEqual(events.last?.revisionID, 100)
    XCTAssertEqual(pipeline.latestRevision?.revisionID, 100)
    XCTAssertEqual(pipeline.latestNormalizedText?.displayText, text)
    XCTAssertEqual(pipeline.latestRevision?.addedText, "100")
  }

  private func snapshot(
    text: String,
    bundleIdentifier: String = "com.openai.codex",
    pid: pid_t = 200,
    windowTitle: String = "ChatGPT"
  ) -> AccessibleTextSnapshot {
    let observedAt = Date(timeIntervalSince1970: 2_000)
    return AccessibleTextSnapshot(
      window: AccessibleWindowSnapshot(
        application: AccessibleApplicationSnapshot(
          appName: "ChatGPT",
          bundleIdentifier: bundleIdentifier,
          processIdentifier: pid,
          observedAt: observedAt,
          source: .accessibility
        ),
        windowTitle: windowTitle,
        windowRole: "AXWindow",
        windowSubrole: "AXStandardWindow",
        observedAt: observedAt,
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
}
