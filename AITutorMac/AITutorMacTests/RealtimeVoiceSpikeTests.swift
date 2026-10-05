import XCTest

@testable import AITutorMac

@MainActor
final class RealtimeVoiceSpikeTests: XCTestCase {
  func testLegalStateTransitionsAreCentralized() throws {
    var machine = RealtimeVoiceStateMachine()

    try machine.transition(to: .authorizing)
    try machine.transition(to: .bootstrapping)
    try machine.transition(to: .connecting)
    try machine.transition(to: .ready)
    try machine.transition(to: .listening)
    try machine.transition(to: .thinking)
    try machine.transition(to: .speaking)
    try machine.transition(to: .interrupting)
    try machine.transition(to: .listening)
    try machine.transition(to: .ending)
    try machine.transition(to: .idle)

    XCTAssertEqual(machine.state, .idle)
    XCTAssertThrowsError(try machine.transition(to: .speaking))
  }

  func testDuplicateStartIsRejected() async throws {
    let fixture = makeFixture()
    try await fixture.coordinator.start()

    do {
      try await fixture.coordinator.start()
      XCTFail("Expected duplicate start to fail")
    } catch let failure as RealtimeVoiceFailure {
      XCTAssertEqual(failure, .duplicateStart)
    }

    await fixture.coordinator.stop()
  }

  func testStopIsIdempotentAndStopsRemoteTaskOnce() async throws {
    let fixture = makeFixture()
    try await fixture.coordinator.start()

    async let firstStop: Void = fixture.coordinator.stop()
    async let secondStop: Void = fixture.coordinator.stop()
    _ = await (firstStop, secondStop)
    let stoppedTaskCount = await fixture.bootstrapProvider.stoppedTaskIDs.count

    XCTAssertEqual(fixture.coordinator.state, .idle)
    XCTAssertEqual(stoppedTaskCount, 1)
    XCTAssertEqual(fixture.rtcClient.disconnectCount, 1)
  }

  func testBootstrapFailureCleansUpWithoutRTCConnect() async {
    let fixture = makeFixture(
      bootstrapBehavior: .failure(.bootstrapUnavailable)
    )

    await XCTAssertThrowsErrorAsync {
      try await fixture.coordinator.start()
    }
    let stoppedTaskCount = await fixture.bootstrapProvider.stoppedTaskIDs.count

    XCTAssertEqual(fixture.coordinator.state, .idle)
    XCTAssertEqual(fixture.rtcClient.connectAttemptCount, 0)
    XCTAssertEqual(stoppedTaskCount, 0)
    XCTAssertEqual(
      fixture.coordinator.lastError,
      RealtimeVoiceFailure.bootstrapUnavailable.displayMessage
    )
  }

  func testExpiredBootstrapIsRejectedBeforeRTCConnect() async {
    let fixture = makeFixture(expiresAfter: -1)

    await XCTAssertThrowsErrorAsync {
      try await fixture.coordinator.start()
    }
    let stoppedTaskCount = await fixture.bootstrapProvider.stoppedTaskIDs.count

    XCTAssertEqual(fixture.coordinator.state, .idle)
    XCTAssertEqual(fixture.rtcClient.connectAttemptCount, 0)
    XCTAssertEqual(stoppedTaskCount, 1)
  }

  func testRTCFailureStopsStartedAITask() async {
    let fixture = makeFixture()
    fixture.rtcClient.connectFailures = [
      .rtcConnectionFailed(message: "fatal", retryable: false)
    ]

    await XCTAssertThrowsErrorAsync {
      try await fixture.coordinator.start()
    }
    let stoppedTaskCount = await fixture.bootstrapProvider.stoppedTaskIDs.count

    XCTAssertEqual(fixture.rtcClient.connectAttemptCount, 1)
    XCTAssertEqual(stoppedTaskCount, 1)
    XCTAssertEqual(fixture.coordinator.state, .idle)
  }

  func testAITaskStartFailureDoesNotPretendRTCConnected() async {
    let fixture = makeFixture(
      bootstrapBehavior: .failure(
        .aiTaskStartFailed(message: "StartVoiceChat failed")
      )
    )

    await XCTAssertThrowsErrorAsync {
      try await fixture.coordinator.start()
    }

    XCTAssertEqual(fixture.coordinator.rtcStatus, .disconnected)
    XCTAssertEqual(fixture.rtcClient.connectAttemptCount, 0)
    XCTAssertEqual(fixture.coordinator.lastError, "StartVoiceChat failed")
  }

  func testManualInterruptStopsRemoteGenerationAndFlushesAudio() async throws {
    let fixture = makeFixture()
    try await fixture.coordinator.start()
    fixture.rtcClient.emit(.aiSpeaking)
    XCTAssertEqual(fixture.coordinator.state, .speaking)

    try await fixture.coordinator.interrupt()
    let interruptedTaskCount = await fixture.bootstrapProvider.interruptedTaskIDs.count

    XCTAssertEqual(fixture.coordinator.state, .listening)
    XCTAssertFalse(fixture.coordinator.isAISpeaking)
    XCTAssertEqual(fixture.rtcClient.discardRemoteAudioCount, 1)
    XCTAssertEqual(interruptedTaskCount, 1)
    await fixture.coordinator.stop()
  }

  func testAutomaticBargeInFlushesOldRemoteAudio() async throws {
    let fixture = makeFixture()
    try await fixture.coordinator.start()
    fixture.rtcClient.emit(.aiSpeaking)

    fixture.rtcClient.emit(.userBargeIn)

    XCTAssertEqual(fixture.coordinator.state, .listening)
    XCTAssertFalse(fixture.coordinator.isAISpeaking)
    XCTAssertEqual(fixture.rtcClient.discardRemoteAudioCount, 1)
    await fixture.coordinator.stop()
  }

  func testStopWhileSpeakingEndsSessionAndMicrophone() async throws {
    let fixture = makeFixture()
    try await fixture.coordinator.start()
    fixture.rtcClient.emit(.aiSpeaking)

    await fixture.coordinator.stop()

    XCTAssertEqual(fixture.coordinator.state, .idle)
    XCTAssertFalse(fixture.coordinator.isAISpeaking)
    XCTAssertFalse(fixture.coordinator.isMicrophoneActive)
    XCTAssertEqual(fixture.coordinator.lastStopReason, .user)
  }

  func testAppTerminationCleanupUsesExplicitStopReason() async throws {
    let fixture = makeFixture()
    try await fixture.coordinator.start()

    await fixture.coordinator.stop(reason: .appTermination)
    let stoppedTaskCount = await fixture.bootstrapProvider.stoppedTaskIDs.count

    XCTAssertEqual(fixture.coordinator.state, .idle)
    XCTAssertEqual(fixture.coordinator.lastStopReason, .appTermination)
    XCTAssertEqual(stoppedTaskCount, 1)
  }

  func testSessionTimeoutAutomaticallyStops() async throws {
    let fixture = makeFixture(
      maximumSessionDuration: 0.03,
      timerInterval: 0.01
    )
    try await fixture.coordinator.start()

    try await Task.sleep(nanoseconds: 120_000_000)
    let stoppedTaskCount = await fixture.bootstrapProvider.stoppedTaskIDs.count

    XCTAssertEqual(fixture.coordinator.state, .idle)
    XCTAssertEqual(fixture.coordinator.lastStopReason, .sessionTimeout)
    XCTAssertEqual(stoppedTaskCount, 1)
  }

  func testTokenExpiryAutomaticallyStops() async throws {
    let fixture = makeFixture(
      expiresAfter: 0.04,
      maximumSessionDuration: 10,
      timerInterval: 0.01
    )
    try await fixture.coordinator.start()

    try await Task.sleep(nanoseconds: 150_000_000)
    let stoppedTaskCount = await fixture.bootstrapProvider.stoppedTaskIDs.count

    XCTAssertEqual(fixture.coordinator.state, .idle)
    XCTAssertEqual(fixture.coordinator.lastStopReason, .bootstrapExpired)
    XCTAssertEqual(stoppedTaskCount, 1)
  }

  func testBoundedRetryStopsAfterConfiguredAttempts() async {
    let fixture = makeFixture(
      retryPolicy: RealtimeVoiceRetryPolicy(
        maximumAttempts: 3,
        initialBackoff: 0.001,
        multiplier: 1
      )
    )
    fixture.rtcClient.connectFailures = [
      .rtcConnectionFailed(message: "one", retryable: true),
      .rtcConnectionFailed(message: "two", retryable: true),
      .rtcConnectionFailed(message: "three", retryable: true),
      .rtcConnectionFailed(message: "must not run", retryable: true),
    ]

    await XCTAssertThrowsErrorAsync {
      try await fixture.coordinator.start()
    }
    let stoppedTaskCount = await fixture.bootstrapProvider.stoppedTaskIDs.count

    XCTAssertEqual(fixture.rtcClient.connectAttemptCount, 3)
    XCTAssertEqual(stoppedTaskCount, 1)
  }

  func testNonRetryableFailureDoesNotRetry() async {
    let fixture = makeFixture()
    fixture.rtcClient.connectFailures = [
      .rtcConnectionFailed(message: "authentication", retryable: false)
    ]

    await XCTAssertThrowsErrorAsync {
      try await fixture.coordinator.start()
    }

    XCTAssertEqual(fixture.rtcClient.connectAttemptCount, 1)
  }

  func testStaleSessionEventIsRejected() async throws {
    let fixture = makeFixture()
    try await fixture.coordinator.start()

    fixture.rtcClient.emit(.aiSpeaking, sessionID: UUID())

    XCTAssertEqual(fixture.coordinator.state, .listening)
    XCTAssertFalse(fixture.coordinator.isAISpeaking)
    await fixture.coordinator.stop()
  }

  func testForbiddenSceneIdentifierCannotBecomeS2SModel() {
    XCTAssertThrowsError(
      try DoubaoS2SConfiguration(
        model: DoubaoS2SConfiguration.forbiddenSceneIdentifier
      )
    )
  }

  private func makeFixture(
    bootstrapBehavior: MockRealtimeVoiceBootstrapProvider.Behavior = .success,
    expiresAfter: TimeInterval = 10,
    retryPolicy: RealtimeVoiceRetryPolicy = RealtimeVoiceRetryPolicy(
      maximumAttempts: 3,
      initialBackoff: 0,
      multiplier: 1
    ),
    maximumSessionDuration: TimeInterval = 10,
    timerInterval: TimeInterval = 1
  ) -> Fixture {
    let bootstrapProvider = MockRealtimeVoiceBootstrapProvider(
      behavior: bootstrapBehavior,
      expiresAfter: expiresAfter
    )
    let rtcClient = MockVolcRTCClientAdapter()
    let session = DoubaoRTCSession(
      bootstrapProvider: bootstrapProvider,
      commandProvider: bootstrapProvider,
      rtcClient: rtcClient,
      retryPolicy: retryPolicy,
      maximumSessionDuration: maximumSessionDuration,
      timerInterval: timerInterval
    )
    return Fixture(
      bootstrapProvider: bootstrapProvider,
      rtcClient: rtcClient,
      coordinator: DoubaoRealtimeVoiceCoordinator(session: session)
    )
  }
}

private struct Fixture {
  let bootstrapProvider: MockRealtimeVoiceBootstrapProvider
  let rtcClient: MockVolcRTCClientAdapter
  let coordinator: DoubaoRealtimeVoiceCoordinator
}

private func XCTAssertThrowsErrorAsync(
  _ expression: () async throws -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    try await expression()
    XCTFail("Expected expression to throw", file: file, line: line)
  } catch {
    // Expected.
  }
}
