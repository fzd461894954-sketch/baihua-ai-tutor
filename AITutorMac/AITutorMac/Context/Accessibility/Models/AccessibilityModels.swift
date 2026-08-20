import Darwin
import Foundation

enum AccessibilityPermissionState: String, Equatable, Sendable {
  case granted
  case notGranted

  var displayName: String {
    switch self {
    case .granted:
      return "已开启"
    case .notGranted:
      return "未开启"
    }
  }
}

enum AccessibleSnapshotSource: String, Equatable, Sendable {
  case accessibility
}

enum AccessibilityTextSourceAttribute: String, Equatable, Sendable {
  case title
  case value
  case accessibilityDescription = "description"
  case help
}

struct AccessibleApplicationSnapshot: Equatable, Sendable {
  let appName: String?
  let bundleIdentifier: String?
  let processIdentifier: pid_t
  let observedAt: Date
  let source: AccessibleSnapshotSource
}

struct AccessibleWindowSnapshot: Equatable, Sendable {
  let application: AccessibleApplicationSnapshot
  let windowTitle: String?
  let windowRole: String?
  let windowSubrole: String?
  let observedAt: Date
  let source: AccessibleSnapshotSource
}

struct AccessibleTextNode: Equatable, Sendable {
  let role: String?
  let text: String
  let depth: Int
  let sourceAttribute: AccessibilityTextSourceAttribute
}

struct AccessibleTextSnapshot: Equatable, Sendable {
  let window: AccessibleWindowSnapshot
  let nodes: [AccessibleTextNode]
  let plainText: String
  let characterCount: Int
  let nodeCount: Int
  let visitedNodeCount: Int
  let roleCounts: [String: Int]
  let truncated: Bool
  let duration: TimeInterval

  func preview(maxCharacters: Int = 3_000) -> String {
    guard maxCharacters > 0 else {
      return ""
    }
    return String(plainText.prefix(maxCharacters))
  }
}

struct AccessibilityTraversalLimits: Equatable, Sendable {
  static let `default` = AccessibilityTraversalLimits(
    maxDepth: 40,
    maxNodes: 2_000,
    maxCharacters: 100_000
  )

  let maxDepth: Int
  let maxNodes: Int
  let maxCharacters: Int

  init(maxDepth: Int, maxNodes: Int, maxCharacters: Int) {
    self.maxDepth = max(0, maxDepth)
    self.maxNodes = max(1, maxNodes)
    self.maxCharacters = max(1, maxCharacters)
  }
}

enum AccessibilityReaderError: String, Error, Equatable, Sendable {
  case permissionRequired
  case selfTargetRejected
  case targetUnavailable
  case focusedWindowUnavailable
  case readFailed
  case timedOut
  case cancelled

  var userMessage: String {
    switch self {
    case .permissionRequired:
      return "需要开启辅助功能权限，才能读取当前窗口文字。"
    case .selfTargetRejected:
      return "白话 AI 不会读取自己的窗口。"
    case .targetUnavailable:
      return "刚才的应用已不可用，请切换到目标应用后再试。"
    case .focusedWindowUnavailable:
      return "当前应用没有可读取的聚焦窗口。"
    case .readFailed:
      return "当前应用暂时无法通过辅助功能读取文字。"
    case .timedOut:
      return "当前应用响应较慢，本次读取已安全结束。"
    case .cancelled:
      return "本次读取已取消。"
    }
  }
}

final class AccessibilityReadCancellationToken: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool {
    lock.withLock { cancelled }
  }

  func cancel() {
    lock.withLock {
      cancelled = true
    }
  }

  func checkCancellation() throws {
    if isCancelled || Task.isCancelled {
      throw AccessibilityReaderError.cancelled
    }
  }
}
