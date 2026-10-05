import ApplicationServices
import Foundation

#if DEBUG
enum AXReadStage: String, Equatable, Sendable {
  case identityValidation = "identity-validation"
  case application = "application"
  case focusedWindow = "focused-window"
  case focusedElement = "focused-element"
  case windowMetadata = "window-metadata"
  case contentRootSelection = "content-root-selection"
  case treeTraversal = "tree-traversal"
  case textExtraction = "text-extraction"
  case snapshotAssembly = "snapshot-assembly"
}

enum AXReadTraceOutcome: String, Equatable, Sendable {
  case pass = "PASS"
  case warning = "WARN"
  case failure = "FAIL"
}

struct AXReadTraceEvent: Equatable, Sendable {
  let timestamp: Date
  let stage: AXReadStage
  let outcome: AXReadTraceOutcome
  let operation: String
  let attribute: String?
  let axErrorRawValue: Int32?
  let axErrorDescription: String?
  let elementRole: String?
  let elementSubrole: String?
  let detail: String?
  let isMainThread: Bool
}

struct AXReadTrace: Equatable, Sendable {
  let startedAt: Date
  let targetApplicationName: String?
  let targetBundleIdentifier: String?
  let targetProcessIdentifier: pid_t
  let resolvedBundleIdentifier: String?
  let axIsProcessTrusted: Bool
  var currentStage: AXReadStage
  var focusedWindowAvailable: Bool?
  var focusedElementAvailable: Bool?
  var result: String?
  var events: [AXReadTraceEvent]
}

final class AXReadTraceStore: @unchecked Sendable {
  static let shared = AXReadTraceStore()

  private let lock = NSLock()
  private var trace: AXReadTrace?

  var latestTrace: AXReadTrace? {
    lock.withLock { trace }
  }

  var currentStage: AXReadStage {
    lock.withLock { trace?.currentStage ?? .application }
  }

  func begin(
    target: ActiveApplicationSnapshot,
    resolvedBundleIdentifier: String?
  ) {
    let matchesIdentity = target.bundleIdentifier == nil
      || target.bundleIdentifier == resolvedBundleIdentifier
    lock.withLock {
      trace = AXReadTrace(
        startedAt: Date(),
        targetApplicationName: target.localizedName,
        targetBundleIdentifier: target.bundleIdentifier,
        targetProcessIdentifier: target.processIdentifier,
        resolvedBundleIdentifier: resolvedBundleIdentifier,
        axIsProcessTrusted: AXIsProcessTrusted(),
        currentStage: .identityValidation,
        focusedWindowAvailable: nil,
        focusedElementAvailable: nil,
        result: nil,
        events: []
      )
    }
    record(
      stage: .identityValidation,
      outcome: matchesIdentity ? .pass : .failure,
      operation: "resolve-target-identity",
      detail: "expected=\(target.bundleIdentifier ?? "unavailable") resolved=\(resolvedBundleIdentifier ?? "unavailable")"
    )
  }

  func setStage(_ stage: AXReadStage) {
    lock.withLock { trace?.currentStage = stage }
  }

  func setFocusedWindowAvailable(_ value: Bool) {
    lock.withLock { trace?.focusedWindowAvailable = value }
  }

  func setFocusedElementAvailable(_ value: Bool) {
    lock.withLock { trace?.focusedElementAvailable = value }
  }

  func finish(result: String) {
    lock.withLock { trace?.result = result }
  }

  func record(
    stage: AXReadStage? = nil,
    outcome: AXReadTraceOutcome,
    operation: String,
    attribute: String? = nil,
    axError: AXError? = nil,
    elementRole: String? = nil,
    elementSubrole: String? = nil,
    detail: String? = nil
  ) {
    lock.withLock {
      guard var current = trace else { return }
      let resolvedStage = stage ?? current.currentStage
      current.events.append(
        AXReadTraceEvent(
          timestamp: Date(),
          stage: resolvedStage,
          outcome: outcome,
          operation: operation,
          attribute: attribute,
          axErrorRawValue: axError.map { Int32($0.rawValue) },
          axErrorDescription: axError.map(Self.axErrorName),
          elementRole: elementRole,
          elementSubrole: elementSubrole,
          detail: detail,
          isMainThread: Thread.isMainThread
        )
      )
      trace = current
    }
  }

  func consoleReport() -> String {
    guard let trace = latestTrace else {
      return "AX READ TRACE\nunavailable"
    }
    var lines = [
      "AX READ TRACE",
      "target_app=\(trace.targetApplicationName ?? "unavailable")",
      "target_bundle=\(trace.targetBundleIdentifier ?? "unavailable")",
      "target_pid=\(trace.targetProcessIdentifier)",
      "resolved_bundle=\(trace.resolvedBundleIdentifier ?? "unavailable")",
      "ax_is_process_trusted=\(trace.axIsProcessTrusted ? "yes" : "no")",
      "focused_window_available=\(Self.optional(trace.focusedWindowAvailable))",
      "focused_element_available=\(Self.optional(trace.focusedElementAvailable))",
      "result=\(trace.result ?? "in-progress")",
    ]
    lines.append(contentsOf: trace.events.map { event in
      [
        "stage=\(event.stage.rawValue)",
        "outcome=\(event.outcome.rawValue)",
        "operation=\(event.operation)",
        "attribute=\(event.attribute ?? "none")",
        "ax_error_raw=\(event.axErrorRawValue.map(String.init) ?? "none")",
        "ax_error=\(event.axErrorDescription ?? "none")",
        "role=\(event.elementRole ?? "unavailable")",
        "subrole=\(event.elementSubrole ?? "unavailable")",
        "thread=\(event.isMainThread ? "main" : "background")",
        "detail=\(event.detail ?? "none")",
      ].joined(separator: " ")
    })
    return lines.joined(separator: "\n")
  }

  private static func optional(_ value: Bool?) -> String {
    value.map { $0 ? "yes" : "no" } ?? "unavailable"
  }

  private static func axErrorName(_ error: AXError) -> String {
    switch error {
    case .success: "success"
    case .failure: "failure"
    case .illegalArgument: "illegalArgument"
    case .invalidUIElement: "invalidUIElement"
    case .invalidUIElementObserver: "invalidUIElementObserver"
    case .cannotComplete: "cannotComplete"
    case .attributeUnsupported: "attributeUnsupported"
    case .actionUnsupported: "actionUnsupported"
    case .notificationUnsupported: "notificationUnsupported"
    case .notImplemented: "notImplemented"
    case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
    case .notificationNotRegistered: "notificationNotRegistered"
    case .apiDisabled: "apiDisabled"
    case .noValue: "noValue"
    case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: "notEnoughPrecision"
    @unknown default: "unknown(\(error.rawValue))"
    }
  }
}
#endif

enum AXReadableAttribute: String, CaseIterable {
  case role = "AXRole"
  case subrole = "AXSubrole"
  case identifier = "AXIdentifier"
  case title = "AXTitle"
  case value = "AXValue"
  case selectedText = "AXSelectedText"
  case accessibilityDescription = "AXDescription"
  case help = "AXHelp"
  case children = "AXChildren"
}

enum AXReadableBooleanAttribute: String, CaseIterable {
  case focused = "AXFocused"
  case selected = "AXSelected"
  case enabled = "AXEnabled"
  case visible = "AXVisible"
}

protocol AXElementReading: AnyObject {
  func stringValue(for attribute: AXReadableAttribute) throws -> String?
  func booleanValue(for attribute: AXReadableBooleanAttribute) throws -> Bool?
  func childElements() throws -> [any AXElementReading]
  func elementFrame() throws -> CGRect?
}

extension AXElementReading {
  func booleanValue(for attribute: AXReadableBooleanAttribute) throws -> Bool? {
    nil
  }

  func elementFrame() throws -> CGRect? {
    nil
  }
}

private enum AXElementReadFailure: Error {
  case accessibility(AXError)
}

final class SystemAXElement: AXElementReading {
  private let element: AXUIElement
  private let messagingTimeout: Float
#if DEBUG
  private var knownRole: String?
  private var knownSubrole: String?
#endif

  init(element: AXUIElement, messagingTimeout: Float) {
    self.element = element
    self.messagingTimeout = messagingTimeout
    AXUIElementSetMessagingTimeout(element, messagingTimeout)
  }

  func stringValue(for attribute: AXReadableAttribute) throws -> String? {
    guard let value = try copyValue(for: attribute) else {
      return nil
    }

    if let string = value as? String {
#if DEBUG
      if attribute == .role { knownRole = string }
      if attribute == .subrole { knownSubrole = string }
#endif
      return string
    }
    if let attributedString = value as? NSAttributedString {
      return attributedString.string
    }
    return nil
  }

  func childElements() throws -> [any AXElementReading] {
    guard let value = try copyValue(for: .children) else {
      return []
    }
    guard let children = value as? [AXUIElement] else {
      return []
    }
    return children.map {
      SystemAXElement(element: $0, messagingTimeout: messagingTimeout)
    }
  }

  func booleanValue(for attribute: AXReadableBooleanAttribute) throws -> Bool? {
    guard let value = try copyRawValue(for: attribute.rawValue as CFString) else {
      return nil
    }
    if let boolean = value as? Bool {
      return boolean
    }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    return nil
  }

  func elementFrame() throws -> CGRect? {
    guard
      let positionValue = try copyRawValue(for: kAXPositionAttribute as CFString),
      CFGetTypeID(positionValue) == AXValueGetTypeID(),
      let sizeValue = try copyRawValue(for: kAXSizeAttribute as CFString),
      CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else {
      return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard
      AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else {
      return nil
    }
    return CGRect(origin: position, size: size)
  }

  private func copyValue(for attribute: AXReadableAttribute) throws -> CFTypeRef? {
    try copyRawValue(for: attribute.rawValue as CFString)
  }

  private func copyRawValue(for attribute: CFString) throws -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      element,
      attribute,
      &value
    )

    switch error {
    case .success:
      return value
    case .attributeUnsupported, .noValue:
      return nil
    default:
#if DEBUG
      AXReadTraceStore.shared.record(
        outcome: .failure,
        operation: "AXUIElementCopyAttributeValue",
        attribute: attribute as String,
        axError: error,
        elementRole: knownRole,
        elementSubrole: knownSubrole
      )
#endif
      throw AXElementReadFailure.accessibility(error)
    }
  }
}

struct AXApplicationReadResult {
  let application: AccessibleApplicationSnapshot
  let focusedWindow: any AXElementReading
  let contentRoot: any AXElementReading
}

struct AXApplicationReader {
  let messagingTimeout: Float
  let classifier: TargetApplicationClassifier

  init(
    messagingTimeout: Float = 0.5,
    classifier: TargetApplicationClassifier = TargetApplicationClassifier()
  ) {
    self.messagingTimeout = messagingTimeout
    self.classifier = classifier
  }

  func readApplication(
    _ target: ActiveApplicationSnapshot
  ) throws -> AXApplicationReadResult {
#if DEBUG
    AXReadTraceStore.shared.setStage(.application)
#endif
    let applicationElement = AXUIElementCreateApplication(target.processIdentifier)
    AXUIElementSetMessagingTimeout(applicationElement, messagingTimeout)
#if DEBUG
    AXReadTraceStore.shared.record(
      stage: .application,
      outcome: .pass,
      operation: "AXUIElementCreateApplication"
    )
#endif
    prepareApplicationForReading(applicationElement, target: target)

#if DEBUG
    AXReadTraceStore.shared.setStage(.focusedWindow)
#endif
    var focusedWindowValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      applicationElement,
      kAXFocusedWindowAttribute as CFString,
      &focusedWindowValue
    )

    switch error {
    case .success:
#if DEBUG
      AXReadTraceStore.shared.setFocusedWindowAvailable(true)
      AXReadTraceStore.shared.record(
        stage: .focusedWindow,
        outcome: .pass,
        operation: "AXUIElementCopyAttributeValue",
        attribute: kAXFocusedWindowAttribute
      )
#endif
      break
    case .attributeUnsupported, .noValue:
#if DEBUG
      AXReadTraceStore.shared.setFocusedWindowAvailable(false)
      AXReadTraceStore.shared.record(
        stage: .focusedWindow,
        outcome: .failure,
        operation: "AXUIElementCopyAttributeValue",
        attribute: kAXFocusedWindowAttribute,
        axError: error
      )
#endif
      throw AccessibilityReaderError.focusedWindowUnavailable
    default:
#if DEBUG
      AXReadTraceStore.shared.setFocusedWindowAvailable(false)
      AXReadTraceStore.shared.record(
        stage: .focusedWindow,
        outcome: .failure,
        operation: "AXUIElementCopyAttributeValue",
        attribute: kAXFocusedWindowAttribute,
        axError: error
      )
#endif
      throw AccessibilityReaderError.readFailed
    }

    guard
      let focusedWindowValue,
      CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
    else {
      throw AccessibilityReaderError.focusedWindowUnavailable
    }

    let focusedWindow = focusedWindowValue as! AXUIElement
#if DEBUG
    probeFocusedElement(applicationElement)
#endif
    let application = AccessibleApplicationSnapshot(
      appName: target.localizedName,
      bundleIdentifier: target.bundleIdentifier,
      processIdentifier: target.processIdentifier,
      observedAt: Date(),
      source: .accessibility
    )

    let focusedWindowElement = SystemAXElement(
      element: focusedWindow,
      messagingTimeout: messagingTimeout
    )
#if DEBUG
    AXReadTraceStore.shared.setStage(.contentRootSelection)
#endif
    let contentRoot = AXContentRootSelector(classifier: classifier).selectRoot(
      for: target,
      focusedWindow: focusedWindowElement
    )
#if DEBUG
    AXReadTraceStore.shared.record(
      stage: .contentRootSelection,
      outcome: .pass,
      operation: "select-content-root"
    )
#endif

    return AXApplicationReadResult(
      application: application,
      focusedWindow: focusedWindowElement,
      contentRoot: contentRoot
    )
  }

#if DEBUG
  private func probeFocusedElement(_ applicationElement: AXUIElement) {
    AXReadTraceStore.shared.setStage(.focusedElement)
    var focusedElementValue: CFTypeRef?
    let focusedError = AXUIElementCopyAttributeValue(
      applicationElement,
      kAXFocusedUIElementAttribute as CFString,
      &focusedElementValue
    )
    guard focusedError == .success,
          let focusedElementValue,
          CFGetTypeID(focusedElementValue) == AXUIElementGetTypeID()
    else {
      AXReadTraceStore.shared.setFocusedElementAvailable(false)
      AXReadTraceStore.shared.record(
        stage: .focusedElement,
        outcome: .failure,
        operation: "AXUIElementCopyAttributeValue",
        attribute: kAXFocusedUIElementAttribute,
        axError: focusedError
      )
      return
    }

    AXReadTraceStore.shared.setFocusedElementAvailable(true)
    AXReadTraceStore.shared.record(
      stage: .focusedElement,
      outcome: .pass,
      operation: "AXUIElementCopyAttributeValue",
      attribute: kAXFocusedUIElementAttribute
    )

    let focusedElement = focusedElementValue as! AXUIElement
    AXUIElementSetMessagingTimeout(focusedElement, messagingTimeout)
    let attributes: [CFString] = [
      kAXRoleAttribute,
      kAXSubroleAttribute,
      kAXIdentifierAttribute,
      kAXDescriptionAttribute,
      kAXHelpAttribute,
      kAXValueAttribute,
      kAXSelectedTextAttribute,
      kAXSelectedTextRangeAttribute,
      kAXChildrenAttribute,
      kAXVisibleChildrenAttribute,
      kAXParentAttribute,
      kAXFocusedAttribute,
    ].map { $0 as CFString }
    var role: String?
    var subrole: String?

    for attribute in attributes {
      var value: CFTypeRef?
      let error = AXUIElementCopyAttributeValue(focusedElement, attribute, &value)
      if attribute == kAXRoleAttribute as CFString {
        role = value as? String
      } else if attribute == kAXSubroleAttribute as CFString {
        subrole = value as? String
      }
      let outcome: AXReadTraceOutcome = switch error {
      case .success: .pass
      case .attributeUnsupported, .noValue: .warning
      default: .failure
      }
      AXReadTraceStore.shared.record(
        stage: .focusedElement,
        outcome: outcome,
        operation: "probe-focused-element-attribute",
        attribute: attribute as String,
        axError: error == .success ? nil : error,
        elementRole: role,
        elementSubrole: subrole,
        detail: Self.debugValueSummary(value)
      )
    }
  }

  private static func debugValueSummary(_ value: CFTypeRef?) -> String {
    guard let value else { return "unavailable" }
    if let string = value as? String {
      return "string-characters=\(string.count)"
    }
    if let array = value as? [Any] {
      return "array-count=\(array.count)"
    }
    if CFGetTypeID(value) == AXUIElementGetTypeID() {
      return "AXUIElement"
    }
    if CFGetTypeID(value) == AXValueGetTypeID() {
      return "AXValue"
    }
    return String(describing: CFGetTypeID(value))
  }
#endif

  private func prepareApplicationForReading(
    _ applicationElement: AXUIElement,
    target: ActiveApplicationSnapshot
  ) {
    guard classifier.classify(target) == .workBuddy else {
      return
    }

    let attribute = "AXManualAccessibility" as CFString
    var currentValue: CFTypeRef?
    let readResult = AXUIElementCopyAttributeValue(
      applicationElement,
      attribute,
      &currentValue
    )
    if readResult == .success, (currentValue as? Bool) == true {
      return
    }

    let writeResult = AXUIElementSetAttributeValue(
      applicationElement,
      attribute,
      kCFBooleanTrue
    )
    if writeResult == .success {
      // Chromium creates its AXWebArea asynchronously after manual
      // accessibility is enabled. This runs off the main actor and only once
      // per WorkBuddy process, before the first explicit read.
      Thread.sleep(forTimeInterval: 0.5)
    }
  }
}

struct AXContentRootSelector {
  private let classifier: TargetApplicationClassifier
  private let maximumVisitedNodeCount: Int

  init(
    classifier: TargetApplicationClassifier = TargetApplicationClassifier(),
    maximumVisitedNodeCount: Int = 2_000
  ) {
    self.classifier = classifier
    self.maximumVisitedNodeCount = max(1, maximumVisitedNodeCount)
  }

  func selectRoot(
    for target: ActiveApplicationSnapshot,
    focusedWindow: any AXElementReading
  ) -> any AXElementReading {
    switch classifier.classify(target) {
    case .chatGPT, .codex, .workBuddy, .browser:
      return selectConversationOrWebContentRoot(from: focusedWindow) ?? focusedWindow
    case .xcode, .other:
      return focusedWindow
    }
  }

  private func selectConversationOrWebContentRoot(
    from focusedWindow: any AXElementReading
  ) -> (any AXElementReading)? {
    guard
      let windowFrame = try? focusedWindow.elementFrame(),
      windowFrame.width > 0,
      windowFrame.height > 0
    else {
      return nil
    }

    typealias TraversalItem = (
      element: any AXElementReading,
      ancestors: [any AXElementReading]
    )
    var stack: [TraversalItem] = [(focusedWindow, [])]
    var candidates: [(score: CGFloat, path: [any AXElementReading])] = []
    var webAreaCandidates: [(area: CGFloat, element: any AXElementReading)] = []
    var visitedNodeCount = 0

    while let item = stack.popLast(), visitedNodeCount < maximumVisitedNodeCount {
      visitedNodeCount += 1
      let role = try? item.element.stringValue(for: .role)
      if Self.isComposerRole(role),
         let frame = try? item.element.elementFrame(),
         Self.isLikelyComposer(frame, in: windowFrame) {
        let verticalPosition = (frame.midY - windowFrame.minY) / windowFrame.height
        let widthRatio = frame.width / windowFrame.width
        candidates.append((
          score: verticalPosition * 2 + widthRatio,
          path: item.ancestors + [item.element]
        ))
      }
      if role == "AXWebArea",
         let frame = try? item.element.elementFrame(),
         frame.width > 0,
         frame.height > 0,
         windowFrame.intersects(frame) {
        webAreaCandidates.append((area: frame.width * frame.height, element: item.element))
      }

      let children = (try? item.element.childElements()) ?? []
      for child in children.reversed() {
        stack.append((child, item.ancestors + [item.element]))
      }
    }

    if let composerPath = candidates.max(by: { $0.score < $1.score })?.path,
       let conversationPane = composerPath.reversed().first(where: { candidate in
         guard let frame = try? candidate.elementFrame() else {
           return false
         }
         return Self.isConversationPane(frame, in: windowFrame)
       }) {
      return conversationPane
    }

    return webAreaCandidates.max(by: { $0.area < $1.area })?.element
  }

  private static func isComposerRole(_ role: String?) -> Bool {
    role == "AXTextArea" || role == "AXTextField"
  }

  private static func isLikelyComposer(_ frame: CGRect, in window: CGRect) -> Bool {
    frame.width >= window.width * 0.2
      && frame.height > 0
      && frame.midY >= window.minY + window.height * 0.55
      && window.intersects(frame)
  }

  private static func isConversationPane(_ frame: CGRect, in window: CGRect) -> Bool {
    let widthRatio = frame.width / window.width
    let heightRatio = frame.height / window.height
    let leadingInsetRatio = (frame.minX - window.minX) / window.width
    return widthRatio >= 0.35
      && widthRatio <= 0.92
      && heightRatio >= 0.6
      && leadingInsetRatio >= 0.07
      && leadingInsetRatio <= 0.6
      && window.intersects(frame)
  }
}
