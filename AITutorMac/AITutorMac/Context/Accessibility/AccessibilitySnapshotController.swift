import AppKit
import Foundation
import Observation

protocol AccessibilitySnapshotReading {
  func readSnapshot(
    target: ActiveApplicationSnapshot,
    cancellationToken: AccessibilityReadCancellationToken
  ) throws -> AccessibleTextSnapshot
}

struct AXAccessibilitySnapshotReader: AccessibilitySnapshotReading {
  let applicationReader: AXApplicationReader
  let windowReader: AXWindowReader
  let textExtractor: AXTextExtractor

  init(
    applicationReader: AXApplicationReader = AXApplicationReader(),
    windowReader: AXWindowReader = AXWindowReader(),
    textExtractor: AXTextExtractor = AXTextExtractor()
  ) {
    self.applicationReader = applicationReader
    self.windowReader = windowReader
    self.textExtractor = textExtractor
  }

  func readSnapshot(
    target: ActiveApplicationSnapshot,
    cancellationToken: AccessibilityReadCancellationToken
  ) throws -> AccessibleTextSnapshot {
    let startedAt = CFAbsoluteTimeGetCurrent()
    try cancellationToken.checkCancellation()

    let application = try applicationReader.readApplication(target)
    try cancellationToken.checkCancellation()

    let window = try windowReader.readWindow(
      application: application.application,
      element: application.focusedWindow
    )
    let text = try textExtractor.extract(
      from: application.focusedWindow,
      cancellationToken: cancellationToken
    )
    try cancellationToken.checkCancellation()

    return AccessibleTextSnapshot(
      window: window,
      nodes: text.nodes,
      plainText: text.plainText,
      characterCount: text.plainText.count,
      nodeCount: text.nodes.count,
      visitedNodeCount: text.visitedNodeCount,
      roleCounts: text.roleCounts,
      truncated: text.truncated,
      duration: CFAbsoluteTimeGetCurrent() - startedAt
    )
  }
}

@MainActor
protocol RunningApplicationResolving {
  func isAvailable(_ target: ActiveApplicationSnapshot) -> Bool
}

@MainActor
struct SystemRunningApplicationResolver: RunningApplicationResolving {
  func isAvailable(_ target: ActiveApplicationSnapshot) -> Bool {
    guard
      let application = NSRunningApplication(
        processIdentifier: target.processIdentifier
      ),
      !application.isTerminated
    else {
      return false
    }

    guard let expectedBundleIdentifier = target.bundleIdentifier else {
      return true
    }
    return application.bundleIdentifier == expectedBundleIdentifier
  }
}

@MainActor
@Observable
final class AccessibilitySnapshotController {
  let authorizationController: AccessibilityAuthorizationController

  private(set) var snapshot: AccessibleTextSnapshot?
  private(set) var lastError: AccessibilityReaderError?
  private(set) var isReading = false

  var targetApplication: ActiveApplicationSnapshot? {
    contextState.lastExternalApplication
  }

  var previewText: String {
    snapshot?.preview() ?? ""
  }

  @ObservationIgnored private let contextState: ContextState
  @ObservationIgnored private let reader: AccessibilitySnapshotReading
  @ObservationIgnored private let applicationResolver: RunningApplicationResolving
  @ObservationIgnored private let selfBundleIdentifier: () -> String?
  @ObservationIgnored private let selfProcessIdentifier: () -> pid_t
  @ObservationIgnored private let timeoutNanoseconds: UInt64
  @ObservationIgnored private var readTask: Task<Void, Never>?
  @ObservationIgnored private var cancellationToken: AccessibilityReadCancellationToken?
  @ObservationIgnored private var activeRequestID: UUID?

  init(
    contextState: ContextState,
    authorizationController: AccessibilityAuthorizationController? = nil,
    reader: AccessibilitySnapshotReading? = nil,
    applicationResolver: RunningApplicationResolving? = nil,
    selfBundleIdentifier: @escaping () -> String? = { Bundle.main.bundleIdentifier },
    selfProcessIdentifier: @escaping () -> pid_t = {
      ProcessInfo.processInfo.processIdentifier
    },
    timeout: TimeInterval = 6
  ) {
    self.contextState = contextState
    self.authorizationController = authorizationController
      ?? AccessibilityAuthorizationController()
    self.reader = reader ?? AXAccessibilitySnapshotReader()
    self.applicationResolver = applicationResolver ?? SystemRunningApplicationResolver()
    self.selfBundleIdentifier = selfBundleIdentifier
    self.selfProcessIdentifier = selfProcessIdentifier
    timeoutNanoseconds = UInt64(max(0.01, timeout) * 1_000_000_000)
  }

  func refreshPermissionState() {
    authorizationController.refreshState()
  }

  func requestRead() {
    cancelCurrentRead(clearSnapshot: false)
    snapshot = nil
    lastError = nil
    authorizationController.refreshState()

    guard authorizationController.permissionState == .granted else {
      lastError = .permissionRequired
      authorizationController.beginPermissionRequest()
      return
    }

    guard let target = contextState.lastExternalApplication else {
      lastError = .targetUnavailable
      return
    }

    if target.bundleIdentifier == selfBundleIdentifier()
      || target.processIdentifier == selfProcessIdentifier() {
      lastError = .selfTargetRejected
      return
    }

    guard applicationResolver.isAvailable(target) else {
      lastError = .targetUnavailable
      return
    }

    let requestID = UUID()
    let token = AccessibilityReadCancellationToken()
    activeRequestID = requestID
    cancellationToken = token
    isReading = true

    readTask = Task { [weak self, reader, timeoutNanoseconds] in
      do {
        let result = try await Self.performRead(
          reader: reader,
          target: target,
          token: token,
          timeoutNanoseconds: timeoutNanoseconds
        )
        self?.complete(result, requestID: requestID)
      } catch let error as AccessibilityReaderError {
        self?.complete(error, requestID: requestID)
      } catch is CancellationError {
        self?.complete(.cancelled, requestID: requestID)
      } catch {
        self?.complete(.readFailed, requestID: requestID)
      }
    }
  }

  func cancelCurrentRead(clearSnapshot: Bool = false) {
    cancellationToken?.cancel()
    readTask?.cancel()
    cancellationToken = nil
    readTask = nil
    activeRequestID = nil
    isReading = false

    if clearSnapshot {
      snapshot = nil
      lastError = nil
    }
  }

  func targetApplicationDidChange() {
    cancelCurrentRead(clearSnapshot: true)
  }

  func copyDebugSnapshot() {
    guard let snapshot else {
      return
    }

    let text = """
      App: \(snapshot.window.application.appName ?? "未知")
      Bundle: \(snapshot.window.application.bundleIdentifier ?? "无")
      PID: \(snapshot.window.application.processIdentifier)
      Focused Window: \(snapshot.window.windowTitle ?? "无标题")
      Nodes: \(snapshot.nodeCount)
      Visited Nodes: \(snapshot.visitedNodeCount)
      Characters: \(snapshot.characterCount)
      Truncated: \(snapshot.truncated ? "Yes" : "No")
      Duration: \(String(format: "%.3f", snapshot.duration))s

      \(snapshot.preview())
      """

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func complete(
    _ result: AccessibleTextSnapshot,
    requestID: UUID
  ) {
    guard activeRequestID == requestID else {
      return
    }

    snapshot = result
    lastError = nil
    finish(requestID: requestID)
    AppLogger.accessibility.info(
      "AX snapshot completed nodes=\(result.nodeCount, privacy: .public) characters=\(result.characterCount, privacy: .public) truncated=\(result.truncated, privacy: .public) duration=\(result.duration, privacy: .public)"
    )
  }

  private func complete(
    _ error: AccessibilityReaderError,
    requestID: UUID
  ) {
    guard activeRequestID == requestID else {
      return
    }

    snapshot = nil
    lastError = error
    finish(requestID: requestID)
    AppLogger.accessibility.error(
      "AX snapshot failed: \(error.rawValue, privacy: .public)"
    )
  }

  private func finish(requestID: UUID) {
    guard activeRequestID == requestID else {
      return
    }
    cancellationToken = nil
    readTask = nil
    activeRequestID = nil
    isReading = false
  }

  nonisolated private static func performRead(
    reader: AccessibilitySnapshotReading,
    target: ActiveApplicationSnapshot,
    token: AccessibilityReadCancellationToken,
    timeoutNanoseconds: UInt64
  ) async throws -> AccessibleTextSnapshot {
    try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: AccessibleTextSnapshot.self) { group in
        group.addTask {
          try reader.readSnapshot(target: target, cancellationToken: token)
        }
        group.addTask {
          try await Task.sleep(nanoseconds: timeoutNanoseconds)
          token.cancel()
          throw AccessibilityReaderError.timedOut
        }

        defer { group.cancelAll() }
        guard let result = try await group.next() else {
          throw AccessibilityReaderError.readFailed
        }
        return result
      }
    } onCancel: {
      token.cancel()
    }
  }
}
