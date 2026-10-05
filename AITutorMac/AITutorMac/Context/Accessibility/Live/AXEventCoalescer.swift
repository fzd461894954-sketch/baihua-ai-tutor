import Foundation

enum AXEventCoalescingDecision: Equatable {
  case startNow
  case wait(until: Date)
  case none
}

/// Keeps a live session responsive without turning a stream of AX notifications
/// into one expensive accessibility tree traversal per notification.
final class AXEventCoalescer {
  private let configuration: AccessibilityLiveConfiguration

  private(set) var isDirty = false
  private(set) var isSnapshotInFlight = false
  private(set) var lastEventAt: Date?
  private(set) var lastSnapshotStartedAt: Date?

  init(configuration: AccessibilityLiveConfiguration = .default) {
    self.configuration = configuration
  }

  func recordEvent(at date: Date) -> AXEventCoalescingDecision {
    isDirty = true
    lastEventAt = date
    return decisionForDirtyState(at: date)
  }

  func snapshotDidStart(at date: Date) {
    isSnapshotInFlight = true
    isDirty = false
    lastSnapshotStartedAt = date
  }

  func snapshotDidFinish(at date: Date) -> AXEventCoalescingDecision {
    isSnapshotInFlight = false
    return decisionForDirtyState(at: date)
  }

  func snapshotDidNotStart() {
    isSnapshotInFlight = false
    isDirty = true
    lastSnapshotStartedAt = nil
  }

  func rateLimitDeadlineDidArrive(at date: Date) -> AXEventCoalescingDecision {
    decisionForDirtyState(at: date)
  }

  func trailingDeadlineDidArrive(
    for eventAt: Date,
    at date: Date
  ) -> AXEventCoalescingDecision {
    guard lastEventAt == eventAt else {
      return .none
    }
    return decisionForDirtyState(at: date)
  }

  func reset() {
    isDirty = false
    isSnapshotInFlight = false
    lastEventAt = nil
    lastSnapshotStartedAt = nil
  }

  private func decisionForDirtyState(at date: Date) -> AXEventCoalescingDecision {
    guard isDirty, !isSnapshotInFlight else {
      return .none
    }

    guard let lastSnapshotStartedAt else {
      return .startNow
    }

    let earliestNextSnapshot = lastSnapshotStartedAt.addingTimeInterval(
      configuration.minimumSnapshotInterval
    )
    return date >= earliestNextSnapshot ? .startNow : .wait(until: earliestNextSnapshot)
  }
}
