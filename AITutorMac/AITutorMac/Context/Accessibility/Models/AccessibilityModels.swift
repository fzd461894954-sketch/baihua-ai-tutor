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
  case selectedText
  case title
  case value
  case accessibilityDescription = "description"
  case help
}

struct AccessibleFrameSnapshot: Equatable, Sendable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double

  init(_ frame: CGRect) {
    x = frame.origin.x
    y = frame.origin.y
    width = frame.size.width
    height = frame.size.height
  }

  var cgRect: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }

  var debugDescription: String {
    String(format: "x=%.1f y=%.1f w=%.1f h=%.1f", x, y, width, height)
  }
}

enum AccessibleWindowGeometryRelationship: String, Equatable, Sendable {
  case containedInWindow = "contained-in-window"
  case intersectsWindow = "intersects-window"
  case outsideWindow = "outside-window"
  case unknown
}

struct AccessibleNodePathComponent: Equatable, Sendable {
  let debugNodeID: String
  let role: String?
  let subrole: String?
  let identifier: String?
  let traversalIndex: Int
  let childIndex: Int
  let frame: AccessibleFrameSnapshot?
  let isFocused: Bool?
  let isSelected: Bool?
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
  let debugNodeID: String
  let fingerprint: String
  let role: String?
  let subrole: String?
  let identifier: String?
  let elementTitle: String?
  let elementDescription: String?
  let text: String
  let rawText: String
  let depth: Int
  let traversalIndex: Int
  let parentDebugNodeID: String?
  let ancestorPath: [AccessibleNodePathComponent]
  let frame: AccessibleFrameSnapshot?
  let isFocused: Bool?
  let isSelected: Bool?
  let isEnabled: Bool?
  let isVisible: Bool?
  let windowGeometryRelationship: AccessibleWindowGeometryRelationship
  let sourceApplication: String?
  let sourceBundleIdentifier: String?
  let sourceProcessIdentifier: pid_t?
  let sourceWindowIdentity: String?
  let sourceAttribute: AccessibilityTextSourceAttribute

  init(
    role: String?,
    text: String,
    depth: Int,
    sourceAttribute: AccessibilityTextSourceAttribute,
    debugNodeID: String = "legacy-node",
    fingerprint: String = "legacy-node",
    subrole: String? = nil,
    identifier: String? = nil,
    elementTitle: String? = nil,
    elementDescription: String? = nil,
    rawText: String? = nil,
    traversalIndex: Int = 0,
    parentDebugNodeID: String? = nil,
    ancestorPath: [AccessibleNodePathComponent] = [],
    frame: AccessibleFrameSnapshot? = nil,
    isFocused: Bool? = nil,
    isSelected: Bool? = nil,
    isEnabled: Bool? = nil,
    isVisible: Bool? = nil,
    windowGeometryRelationship: AccessibleWindowGeometryRelationship = .unknown,
    sourceApplication: String? = nil,
    sourceBundleIdentifier: String? = nil,
    sourceProcessIdentifier: pid_t? = nil,
    sourceWindowIdentity: String? = nil
  ) {
    self.debugNodeID = debugNodeID
    self.fingerprint = fingerprint
    self.role = role
    self.subrole = subrole
    self.identifier = identifier
    self.elementTitle = elementTitle
    self.elementDescription = elementDescription
    self.text = text
    self.rawText = rawText ?? text
    self.depth = depth
    self.traversalIndex = traversalIndex
    self.parentDebugNodeID = parentDebugNodeID
    self.ancestorPath = ancestorPath
    self.frame = frame
    self.isFocused = isFocused
    self.isSelected = isSelected
    self.isEnabled = isEnabled
    self.isVisible = isVisible
    self.windowGeometryRelationship = windowGeometryRelationship
    self.sourceApplication = sourceApplication
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.sourceProcessIdentifier = sourceProcessIdentifier
    self.sourceWindowIdentity = sourceWindowIdentity
    self.sourceAttribute = sourceAttribute
  }
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
      return "花花老师不会读取自己的窗口。"
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
