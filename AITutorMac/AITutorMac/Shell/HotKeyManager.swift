import Carbon
import Foundation

final class HotKeyManager {
  private static let signature: OSType = 0x4241_4948  // "BAIH"
  private static let identifier: UInt32 = 1

  private var hotKeyReference: EventHotKeyRef?
  private var eventHandlerReference: EventHandlerRef?
  private var callback: (() -> Void)?

  @discardableResult
  func registerOptionSpace(callback: @escaping () -> Void) -> Bool {
    unregister()
    self.callback = callback

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      Self.eventHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandlerReference
    )

    guard handlerStatus == noErr else {
      AppLogger.hotKey.error(
        "Hotkey registration failed while installing handler: \(handlerStatus, privacy: .public)")
      self.callback = nil
      return false
    }

    let hotKeyID = EventHotKeyID(
      signature: Self.signature,
      id: Self.identifier
    )

    let registrationStatus = RegisterEventHotKey(
      UInt32(kVK_Space),
      UInt32(optionKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyReference
    )

    guard registrationStatus == noErr else {
      AppLogger.hotKey.error("Hotkey registration failed: \(registrationStatus, privacy: .public)")
      removeEventHandler()
      self.callback = nil
      return false
    }

    AppLogger.hotKey.info("Option-Space hotkey registered")
    return true
  }

  func unregister() {
    if let hotKeyReference {
      UnregisterEventHotKey(hotKeyReference)
      self.hotKeyReference = nil
    }

    removeEventHandler()
    callback = nil
  }

  deinit {
    unregister()
  }

  private func removeEventHandler() {
    if let eventHandlerReference {
      RemoveEventHandler(eventHandlerReference)
      self.eventHandlerReference = nil
    }
  }

  private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
    guard let event else {
      return OSStatus(eventNotHandledErr)
    }

    var pressedHotKeyID = EventHotKeyID()
    let parameterStatus = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &pressedHotKeyID
    )

    guard parameterStatus == noErr,
      pressedHotKeyID.signature == Self.signature,
      pressedHotKeyID.id == Self.identifier
    else {
      return OSStatus(eventNotHandledErr)
    }

    DispatchQueue.main.async { [weak self] in
      self?.callback?()
    }
    return noErr
  }

  private static let eventHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else {
      return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<HotKeyManager>
      .fromOpaque(userData)
      .takeUnretainedValue()
    return manager.handleHotKeyEvent(event)
  }
}
