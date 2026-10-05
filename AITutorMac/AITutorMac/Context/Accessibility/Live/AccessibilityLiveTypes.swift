import Darwin
import Foundation

enum AccessibilityLiveState: String, Equatable, Sendable {
  case off
  case starting
  case watching
  case paused
  case targetUnavailable
  case permissionRequired
  case error

  var displayName: String {
    switch self {
    case .off:
      return "未开启"
    case .starting:
      return "正在启动"
    case .watching:
      return "实时跟随中"
    case .paused:
      return "已暂停（目标不在前台）"
    case .targetUnavailable:
      return "目标应用不可用"
    case .permissionRequired:
      return "需要辅助功能权限"
    case .error:
      return "发生错误"
    }
  }
}

struct AXChangeEvent: Equatable, Sendable {
  let processIdentifier: pid_t
  let notificationName: String
  let observedAt: Date
  let role: String?
  let subrole: String?
}

struct AXNotificationRegistrationResult: Equatable, Sendable {
  let notificationName: String
  let errorCode: Int32

  var succeeded: Bool {
    errorCode == 0
  }
}

struct AccessibilityLiveConfiguration: Equatable, Sendable {
  static let `default` = AccessibilityLiveConfiguration(
    minimumSnapshotInterval: 0.9,
    trailingSnapshotDelay: 0.6
  )

  let minimumSnapshotInterval: TimeInterval
  let trailingSnapshotDelay: TimeInterval

  init(
    minimumSnapshotInterval: TimeInterval,
    trailingSnapshotDelay: TimeInterval
  ) {
    self.minimumSnapshotInterval = max(0.1, minimumSnapshotInterval)
    self.trailingSnapshotDelay = max(0.1, trailingSnapshotDelay)
  }
}

struct AccessibilityLiveRevisionMetadata: Equatable, Sendable {
  let revision: Int
  let observedAt: Date
  let characterCount: Int
  let nodeCount: Int
  let truncated: Bool
  let fingerprint: String
}

enum AXObserverAdapterError: Error, Equatable, Sendable {
  case observerCreationFailed(Int32)
}
