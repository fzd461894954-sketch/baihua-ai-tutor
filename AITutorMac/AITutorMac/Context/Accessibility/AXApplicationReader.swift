import ApplicationServices
import Foundation

enum AXReadableAttribute: String, CaseIterable {
  case role = "AXRole"
  case subrole = "AXSubrole"
  case title = "AXTitle"
  case value = "AXValue"
  case accessibilityDescription = "AXDescription"
  case help = "AXHelp"
  case children = "AXChildren"
}
protocol AXElementReading: AnyObject {
  func stringValue(for attribute: AXReadableAttribute) throws -> String?
  func childElements() throws -> [any AXElementReading]
}

private enum AXElementReadFailure: Error {
  case accessibility(AXError)
}

final class SystemAXElement: AXElementReading {
  private let element: AXUIElement
  private let messagingTimeout: Float

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

  private func copyValue(for attribute: AXReadableAttribute) throws -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      element,
      attribute.rawValue as CFString,
      &value
    )

    switch error {
    case .success:
      return value
    case .attributeUnsupported, .noValue:
      return nil
    default:
      throw AXElementReadFailure.accessibility(error)
    }
  }
}

struct AXApplicationReadResult {
  let application: AccessibleApplicationSnapshot
  let focusedWindow: any AXElementReading
}

struct AXApplicationReader {
  let messagingTimeout: Float

  init(messagingTimeout: Float = 0.5) {
    self.messagingTimeout = messagingTimeout
  }

  func readApplication(
    _ target: ActiveApplicationSnapshot
  ) throws -> AXApplicationReadResult {
    let applicationElement = AXUIElementCreateApplication(target.processIdentifier)
    AXUIElementSetMessagingTimeout(applicationElement, messagingTimeout)

    var focusedWindowValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      applicationElement,
      kAXFocusedWindowAttribute as CFString,
      &focusedWindowValue
    )

    switch error {
    case .success:
      break
    case .attributeUnsupported, .noValue:
      throw AccessibilityReaderError.focusedWindowUnavailable
    default:
      throw AccessibilityReaderError.readFailed
    }

    guard
      let focusedWindowValue,
      CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
    else {
      throw AccessibilityReaderError.focusedWindowUnavailable
    }

    let focusedWindow = focusedWindowValue as! AXUIElement
    let application = AccessibleApplicationSnapshot(
      appName: target.localizedName,
      bundleIdentifier: target.bundleIdentifier,
      processIdentifier: target.processIdentifier,
      observedAt: Date(),
      source: .accessibility
    )

    return AXApplicationReadResult(
      application: application,
      focusedWindow: SystemAXElement(
        element: focusedWindow,
        messagingTimeout: messagingTimeout
      )
    )
  }
}
