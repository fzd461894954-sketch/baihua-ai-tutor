@preconcurrency import ApplicationServices
import Foundation

@MainActor
protocol AXObserverAdapting: AnyObject {
  var isRunning: Bool { get }
  var supportedNotifications: [String] { get }
  var unsupportedNotifications: [String] { get }
  var observerCreateResult: Int32? { get }
  var notificationRegistrationResults: [AXNotificationRegistrationResult] { get }

  func start(
    target: ActiveApplicationSnapshot,
    onEvent: @escaping (AXChangeEvent) -> Void
  ) throws
  func stop()
}

@MainActor
final class AXObserverAdapter: AXObserverAdapting {
  private static let notificationNames: [String] = [
    kAXFocusedWindowChangedNotification as String,
    kAXFocusedUIElementChangedNotification as String,
    kAXValueChangedNotification as String,
    kAXCreatedNotification as String,
    kAXLayoutChangedNotification as String,
    kAXUIElementDestroyedNotification as String,
    kAXTitleChangedNotification as String,
  ]

  private(set) var isRunning = false
  private(set) var supportedNotifications: [String] = []
  private(set) var unsupportedNotifications: [String] = []
  private(set) var observerCreateResult: Int32?
  private(set) var notificationRegistrationResults: [AXNotificationRegistrationResult] = []

  private var observer: AXObserver?
  private var applicationElement: AXUIElement?
  private var runLoopSource: CFRunLoopSource?
  private var onEvent: ((AXChangeEvent) -> Void)?
  private var targetProcessIdentifier: pid_t?

  func start(
    target: ActiveApplicationSnapshot,
    onEvent: @escaping (AXChangeEvent) -> Void
  ) throws {
    if isRunning {
      guard targetProcessIdentifier == target.processIdentifier else {
        stop()
        return try start(target: target, onEvent: onEvent)
      }
      self.onEvent = onEvent
      return
    }

    var createdObserver: AXObserver?
    let createResult = AXObserverCreate(
      target.processIdentifier,
      Self.callback,
      &createdObserver
    )
    observerCreateResult = createResult.rawValue
    notificationRegistrationResults = []
    guard createResult == .success, let createdObserver else {
      throw AXObserverAdapterError.observerCreationFailed(createResult.rawValue)
    }

    let applicationElement = AXUIElementCreateApplication(target.processIdentifier)
    let source = AXObserverGetRunLoopSource(createdObserver)

    observer = createdObserver
    self.applicationElement = applicationElement
    runLoopSource = source
    self.onEvent = onEvent
    targetProcessIdentifier = target.processIdentifier
    supportedNotifications = []
    unsupportedNotifications = []

    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

    for notificationName in Self.notificationNames {
      let result = AXObserverAddNotification(
        createdObserver,
        applicationElement,
        notificationName as CFString,
        Unmanaged.passUnretained(self).toOpaque()
      )
      notificationRegistrationResults.append(
        AXNotificationRegistrationResult(
          notificationName: notificationName,
          errorCode: result.rawValue
        )
      )
      if result == .success {
        supportedNotifications.append(notificationName)
      } else {
        unsupportedNotifications.append(notificationName)
      }
    }

    isRunning = true
  }

  func stop() {
    guard let observer, let applicationElement else {
      reset()
      return
    }

    for notificationName in supportedNotifications {
      AXObserverRemoveNotification(observer, applicationElement, notificationName as CFString)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    reset()
  }

  private func reset() {
    observer = nil
    applicationElement = nil
    runLoopSource = nil
    onEvent = nil
    targetProcessIdentifier = nil
    isRunning = false
  }

  private func deliver(_ event: AXChangeEvent) {
    onEvent?(event)
  }

  private nonisolated static let callback: AXObserverCallback = {
    _, element, notification, refcon in
    guard let refcon else {
      return
    }

    var processIdentifier: pid_t = 0
    AXUIElementGetPid(element, &processIdentifier)
    let event = AXChangeEvent(
      processIdentifier: processIdentifier,
      notificationName: notification as String,
      observedAt: Date(),
      role: copyStringAttribute(kAXRoleAttribute as CFString, from: element),
      subrole: copyStringAttribute(kAXSubroleAttribute as CFString, from: element)
    )
    let adapter = Unmanaged<AXObserverAdapter>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor [weak adapter] in
      adapter?.deliver(event)
    }
  }

  private nonisolated static func copyStringAttribute(
    _ attribute: CFString,
    from element: AXUIElement
  ) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
      return nil
    }
    return value as? String
  }
}
