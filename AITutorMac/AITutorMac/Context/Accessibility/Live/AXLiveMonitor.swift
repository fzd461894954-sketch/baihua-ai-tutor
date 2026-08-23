import Foundation
import Observation

/// An opt-in, single-target live watcher. It observes one external process and
/// only asks the existing snapshot reader for bounded reads after AX changes.
@MainActor
@Observable
final class AccessibilityLiveMonitor {
  private(set) var state: AccessibilityLiveState = .off
  private(set) var lockedTarget: ActiveApplicationSnapshot?
  private(set) var eventsReceived = 0
  private(set) var eventsCoalesced = 0
  private(set) var snapshotsGenerated = 0
  private(set) var revision = 0
  private(set) var eventCountsByNotification: [String: Int] = [:]
  private(set) var lastEvent: AXChangeEvent?
  private(set) var latestSnapshot: AccessibleTextSnapshot?
  private(set) var latestRevisionMetadata: AccessibilityLiveRevisionMetadata?
  private(set) var lastError: AccessibilityReaderError?
  private(set) var isLatestSnapshotVisible = false

  var supportedNotifications: [String] {
    observerAdapter.supportedNotifications
  }

  var unsupportedNotifications: [String] {
    observerAdapter.unsupportedNotifications
  }

  var observerCreateResult: Int32? {
    observerAdapter.observerCreateResult
  }

  var notificationRegistrationResults: [AXNotificationRegistrationResult] {
    observerAdapter.notificationRegistrationResults
  }

  var contextRevisionPipeline: ContextRevisionPipeline {
    revisionPipeline
  }

  var semanticBuffer: SemanticBuffer {
    semanticBufferStore
  }

  var isLiveSessionActive: Bool {
    switch state {
    case .starting, .watching, .paused:
      return true
    case .off, .targetUnavailable, .permissionRequired, .error:
      return false
    }
  }

  @ObservationIgnored private let contextState: ContextState
  @ObservationIgnored private let authorizationController: AccessibilityAuthorizationController
  @ObservationIgnored private let snapshotRequester: LiveSnapshotRequesting
  @ObservationIgnored private let applicationResolver: RunningApplicationResolving
  @ObservationIgnored private let observerAdapter: AXObserverAdapting
  @ObservationIgnored private let revisionPipeline: ContextRevisionPipeline
  @ObservationIgnored private let semanticBufferStore: SemanticBuffer
  @ObservationIgnored private let selfBundleIdentifier: () -> String?
  @ObservationIgnored private let selfProcessIdentifier: () -> pid_t
  @ObservationIgnored private let configuration: AccessibilityLiveConfiguration
  @ObservationIgnored private let coalescer: AXEventCoalescer
  @ObservationIgnored private var sessionIdentifier: UUID?
  @ObservationIgnored var onLiveSessionChange: (@MainActor (UUID?) -> Void)?
  @ObservationIgnored private var rateLimitTask: Task<Void, Never>?
  @ObservationIgnored private var trailingTask: Task<Void, Never>?

  init(
    contextState: ContextState,
    authorizationController: AccessibilityAuthorizationController,
    snapshotRequester: LiveSnapshotRequesting,
    revisionPipeline: ContextRevisionPipeline? = nil,
    semanticBuffer: SemanticBuffer? = nil,
    applicationResolver: RunningApplicationResolving? = nil,
    observerAdapter: AXObserverAdapting? = nil,
    selfBundleIdentifier: @escaping () -> String? = { Bundle.main.bundleIdentifier },
    selfProcessIdentifier: @escaping () -> pid_t = {
      ProcessInfo.processInfo.processIdentifier
    },
    configuration: AccessibilityLiveConfiguration = .default
  ) {
    self.contextState = contextState
    self.authorizationController = authorizationController
    self.snapshotRequester = snapshotRequester
    self.revisionPipeline = revisionPipeline ?? ContextRevisionPipeline()
    semanticBufferStore = semanticBuffer ?? SemanticBuffer()
    self.applicationResolver = applicationResolver ?? SystemRunningApplicationResolver()
    self.observerAdapter = observerAdapter ?? AXObserverAdapter()
    self.selfBundleIdentifier = selfBundleIdentifier
    self.selfProcessIdentifier = selfProcessIdentifier
    self.configuration = configuration
    coalescer = AXEventCoalescer(configuration: configuration)
  }

  func start() {
    guard !isLiveSessionActive else {
      return
    }

    clearSessionContent()
    lockedTarget = nil
    authorizationController.refreshState()
    let permissionGranted = authorizationController.permissionState == .granted
    let appBundleIdentifier = selfBundleIdentifier() ?? "<nil>"
    AppLogger.accessibility.info(
      "[AX DEBUG] permission=\(permissionGranted, privacy: .public) appBundle=\(appBundleIdentifier, privacy: .public)"
    )
    guard authorizationController.permissionState == .granted else {
      state = .permissionRequired
      return
    }
    guard let target = contextState.lastExternalApplication else {
      state = .targetUnavailable
      return
    }
    guard !isSelfTarget(target), applicationResolver.isAvailable(target) else {
      state = .targetUnavailable
      return
    }
    let targetBundleIdentifier = target.bundleIdentifier ?? "<nil>"
    AppLogger.accessibility.info(
      "[AX DEBUG] target=\(target.displayName, privacy: .public) targetBundle=\(targetBundleIdentifier, privacy: .public) targetPID=\(target.processIdentifier, privacy: .public)"
    )

    state = .starting
    let sessionIdentifier = UUID()
    self.sessionIdentifier = sessionIdentifier
    lockedTarget = target

    do {
      try observerAdapter.start(target: target) { [weak self] event in
        self?.receive(event, sessionIdentifier: sessionIdentifier)
      }
      state = .watching
      onLiveSessionChange?(sessionIdentifier)
      AppLogger.accessibility.info(
        "[AX DEBUG] observerCreate=\(self.observerCreateResult ?? -1, privacy: .public)"
      )
      for registration in notificationRegistrationResults {
        AppLogger.accessibility.info(
          "[AX DEBUG] notification=\(registration.notificationName, privacy: .public) result=\(registration.errorCode, privacy: .public)"
        )
      }
      AppLogger.accessibility.info(
        "AX live watch started pid=\(target.processIdentifier, privacy: .public) supported=\(self.supportedNotifications.count, privacy: .public) unsupported=\(self.unsupportedNotifications.count, privacy: .public)"
      )
    } catch {
      self.sessionIdentifier = nil
      onLiveSessionChange?(nil)
      state = .error
      AppLogger.accessibility.error(
        "[AX DEBUG] observerCreate=\(self.observerCreateResult ?? -1, privacy: .public) failed"
      )
    }
  }

  func stop() {
    stopSession(state: .off, clearTarget: true, clearContent: true)
  }

  func lastExternalApplicationDidChange(_ application: ActiveApplicationSnapshot?) {
    guard let lockedTarget, sessionIdentifier != nil else {
      return
    }

    guard let application else {
      return
    }
    if application.processIdentifier == lockedTarget.processIdentifier {
      if state == .paused {
        authorizationController.refreshState()
        guard authorizationController.permissionState == .granted else {
          stopSession(state: .permissionRequired, clearTarget: false, clearContent: true)
          return
        }
        state = .watching
      }
      return
    }

    // A bundle being relaunched with a new PID is not a valid reason to attach
    // to it. The existing locked process is unavailable instead.
    if application.bundleIdentifier == lockedTarget.bundleIdentifier {
      stopSession(state: .targetUnavailable, clearTarget: false, clearContent: true)
      return
    }

    guard state == .watching || state == .starting else {
      return
    }
    state = .paused
    cancelScheduledSnapshots()
    snapshotRequester.cancelLiveRead()
    coalescer.reset()
  }

  func targetApplicationDidTerminate(_ application: ActiveApplicationSnapshot) {
    guard application.processIdentifier == lockedTarget?.processIdentifier else {
      return
    }
    stopSession(state: .targetUnavailable, clearTarget: false, clearContent: true)
  }

  func showLatestSnapshot() {
    guard latestSnapshot != nil else {
      return
    }
    isLatestSnapshotVisible = true
  }

  func hideLatestSnapshot() {
    isLatestSnapshotVisible = false
  }

  /// Resolves one fresh, bounded snapshot for the explicit Tutor action. This
  /// never retargets the live session and falls back to the latest in-memory
  /// snapshot only when another live read is already in flight.
  func resolveCurrentSnapshot() async throws -> AccessibleTextSnapshot {
    guard
      sessionIdentifier != nil,
      isLiveSessionActive,
      let lockedTarget
    else {
      throw AccessibilityReaderError.targetUnavailable
    }

    authorizationController.refreshState()
    guard authorizationController.permissionState == .granted else {
      throw AccessibilityReaderError.permissionRequired
    }
    guard applicationResolver.isAvailable(lockedTarget) else {
      throw AccessibilityReaderError.targetUnavailable
    }

    if snapshotRequester.isReading {
      guard let latestSnapshot else {
        throw AccessibilityReaderError.readFailed
      }
      return latestSnapshot
    }

    let expectedSessionIdentifier = sessionIdentifier
    return try await withCheckedThrowingContinuation { continuation in
      let didStart = snapshotRequester.requestLiveRead(target: lockedTarget) {
        [weak self] result in
        guard
          let self,
          self.sessionIdentifier == expectedSessionIdentifier
        else {
          continuation.resume(throwing: AccessibilityReaderError.cancelled)
          return
        }

        switch result {
        case let .success(snapshot):
          self.snapshotsGenerated += 1
          self.lastError = nil
          self.record(snapshot)
          continuation.resume(returning: snapshot)
        case let .failure(error):
          self.lastError = error
          continuation.resume(throwing: error)
        }
      }

      guard !didStart else {
        return
      }
      continuation.resume(throwing: AccessibilityReaderError.readFailed)
    }
  }

  private func receive(_ event: AXChangeEvent, sessionIdentifier: UUID) {
    guard
      self.sessionIdentifier == sessionIdentifier,
      let lockedTarget,
      event.processIdentifier == lockedTarget.processIdentifier
    else {
      return
    }

    eventsReceived += 1
    eventCountsByNotification[event.notificationName, default: 0] += 1
    lastEvent = event
    guard state == .watching else {
      return
    }

    authorizationController.refreshState()
    guard authorizationController.permissionState == .granted else {
      stopSession(state: .permissionRequired, clearTarget: false, clearContent: true)
      return
    }

    let decision = coalescer.recordEvent(at: event.observedAt)
    if decision != .startNow {
      eventsCoalesced += 1
    }
    apply(decision, sessionIdentifier: sessionIdentifier)
    scheduleTrailingSnapshot(for: event.observedAt, sessionIdentifier: sessionIdentifier)
  }

  private func apply(_ decision: AXEventCoalescingDecision, sessionIdentifier: UUID) {
    guard self.sessionIdentifier == sessionIdentifier, state == .watching else {
      return
    }

    switch decision {
    case .startNow:
      beginSnapshot(sessionIdentifier: sessionIdentifier)
    case let .wait(until):
      scheduleRateLimitedSnapshot(at: until, sessionIdentifier: sessionIdentifier)
    case .none:
      break
    }
  }

  private func beginSnapshot(sessionIdentifier: UUID) {
    guard
      self.sessionIdentifier == sessionIdentifier,
      state == .watching,
      let lockedTarget
    else {
      return
    }
    guard applicationResolver.isAvailable(lockedTarget) else {
      stopSession(state: .targetUnavailable, clearTarget: false, clearContent: true)
      return
    }
    guard !snapshotRequester.isReading else {
      scheduleRateLimitedSnapshot(
        at: Date().addingTimeInterval(0.15),
        sessionIdentifier: sessionIdentifier
      )
      return
    }

    coalescer.snapshotDidStart(at: Date())
    let didStart = snapshotRequester.requestLiveRead(target: lockedTarget) { [weak self] result in
      self?.completeSnapshot(result, sessionIdentifier: sessionIdentifier)
    }
    if !didStart {
      coalescer.snapshotDidNotStart()
      scheduleRateLimitedSnapshot(
        at: Date().addingTimeInterval(0.15),
        sessionIdentifier: sessionIdentifier
      )
    }
  }

  private func completeSnapshot(
    _ result: Result<AccessibleTextSnapshot, AccessibilityReaderError>,
    sessionIdentifier: UUID
  ) {
    guard self.sessionIdentifier == sessionIdentifier else {
      return
    }

    let decision = coalescer.snapshotDidFinish(at: Date())
    switch result {
    case let .success(snapshot):
      snapshotsGenerated += 1
      lastError = nil
      record(snapshot)
      apply(decision, sessionIdentifier: sessionIdentifier)
    case let .failure(error):
      handleSnapshotFailure(
        error,
        coalescingDecision: decision,
        sessionIdentifier: sessionIdentifier
      )
    }
  }

  private func record(_ snapshot: AccessibleTextSnapshot) {
    guard let sessionIdentifier else {
      return
    }
    latestSnapshot = snapshot
    let contextRevision = revisionPipeline.ingest(
      snapshot: snapshot,
      liveSessionIdentifier: sessionIdentifier
    )
    semanticBufferStore.ingest(contextRevision)
    revision = contextRevision.revisionID

    let metadata = AccessibilityLiveRevisionMetadata(
      revision: revision,
      observedAt: contextRevision.timestamp,
      characterCount: contextRevision.characterCount,
      nodeCount: snapshot.nodeCount,
      truncated: snapshot.truncated,
      fingerprint: contextRevision.fingerprint.rawValue
    )
    latestRevisionMetadata = metadata
  }

  private func handleSnapshotFailure(
    _ error: AccessibilityReaderError,
    coalescingDecision: AXEventCoalescingDecision,
    sessionIdentifier: UUID
  ) {
    switch error {
    case .permissionRequired:
      stopSession(state: .permissionRequired, clearTarget: false, clearContent: true)
    case .targetUnavailable:
      stopSession(state: .targetUnavailable, clearTarget: false, clearContent: true)
    case .cancelled:
      // Cancellation can be caused by an explicit manual STEP 2B read. Do not
      // synchronously start another live read from that callback; an already
      // scheduled event check or the next AX event can safely resume it later.
      break
    case .selfTargetRejected, .focusedWindowUnavailable, .readFailed, .timedOut:
      // Dynamic apps can briefly rebuild or withdraw their focused AX window.
      // Keep the explicit observer session alive and only retry when the
      // coalescer has pending event work; permission and process failures still
      // stop immediately in the cases above.
      lastError = error
      apply(coalescingDecision, sessionIdentifier: sessionIdentifier)
    }
  }

  private func scheduleRateLimitedSnapshot(at date: Date, sessionIdentifier: UUID) {
    rateLimitTask?.cancel()
    let interval = max(0, date.timeIntervalSinceNow)
    rateLimitTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: Self.nanoseconds(for: interval))
      } catch {
        return
      }
      guard let self, !Task.isCancelled else {
        return
      }
      self.rateLimitTask = nil
      self.apply(
        self.coalescer.rateLimitDeadlineDidArrive(at: Date()),
        sessionIdentifier: sessionIdentifier
      )
    }
  }

  private func scheduleTrailingSnapshot(for eventAt: Date, sessionIdentifier: UUID) {
    trailingTask?.cancel()
    let delay = configuration.trailingSnapshotDelay
    trailingTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
      } catch {
        return
      }
      guard let self, !Task.isCancelled else {
        return
      }
      self.trailingTask = nil
      self.apply(
        self.coalescer.trailingDeadlineDidArrive(for: eventAt, at: Date()),
        sessionIdentifier: sessionIdentifier
      )
    }
  }

  private func stopSession(
    state: AccessibilityLiveState,
    clearTarget: Bool,
    clearContent: Bool
  ) {
    let endedSession = sessionIdentifier != nil
    sessionIdentifier = nil
    if endedSession {
      onLiveSessionChange?(nil)
    }
    cancelScheduledSnapshots()
    observerAdapter.stop()
    snapshotRequester.cancelLiveRead()
    coalescer.reset()
    self.state = state
    if clearTarget {
      lockedTarget = nil
    }
    if clearContent {
      clearSessionContent()
    }
  }

  private func clearSessionContent() {
    eventsReceived = 0
    eventsCoalesced = 0
    snapshotsGenerated = 0
    revision = 0
    eventCountsByNotification = [:]
    lastEvent = nil
    latestSnapshot = nil
    latestRevisionMetadata = nil
    revisionPipeline.clear()
    semanticBufferStore.clear()
    lastError = nil
    isLatestSnapshotVisible = false
  }

  private func cancelScheduledSnapshots() {
    rateLimitTask?.cancel()
    rateLimitTask = nil
    trailingTask?.cancel()
    trailingTask = nil
  }

  private func isSelfTarget(_ target: ActiveApplicationSnapshot) -> Bool {
    target.bundleIdentifier == selfBundleIdentifier()
      || target.processIdentifier == selfProcessIdentifier()
  }

  private nonisolated static func nanoseconds(for interval: TimeInterval) -> UInt64 {
    UInt64(max(0, interval) * 1_000_000_000)
  }
}
