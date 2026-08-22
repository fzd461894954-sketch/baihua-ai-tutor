import AppKit
import Testing
@testable import AITutorMac

struct MenuBarIntentTests {
  @Test("Every production menu item maps to its expected intent", arguments: [
    (MenuBarItem.panel, MenuBarIntent.togglePanel),
    (MenuBarItem.petVisibility, MenuBarIntent.togglePetVisibility),
    (MenuBarItem.petLibrary, MenuBarIntent.openPetLibrary),
    (MenuBarItem.settings, MenuBarIntent.openSettings),
    (MenuBarItem.voiceSettings, MenuBarIntent.openVoiceSettings),
    (MenuBarItem.quit, MenuBarIntent.quit),
  ])
  func mapsMenuItem(_ item: MenuBarItem, to expected: MenuBarIntent) {
    #expect(item.intent == expected)
  }

  @Test("Each menu item dispatches once")
  func dispatchesOnce() {
    var received: [MenuBarIntent] = []

    for item in MenuBarItem.allCases {
      received.append(item.intent)
    }

    #expect(received.count == MenuBarItem.allCases.count)
    #expect(received == [
      .togglePanel,
      .togglePetVisibility,
      .openPetLibrary,
      .openSettings,
      .openVoiceSettings,
      .quit,
    ])
  }

  @MainActor
  @Test("Focused push-to-talk uses Space key down and key up")
  func pushToTalkKeyboardPath() throws {
    let view = HoldToTalkCaptureNSView()
    var pressCount = 0
    var releaseCount = 0
    view.onPress = { pressCount += 1 }
    view.onRelease = { releaseCount += 1 }

    view.keyDown(with: try #require(spaceEvent(type: .keyDown)))
    view.keyDown(with: try #require(spaceEvent(type: .keyDown, isRepeat: true)))
    view.keyUp(with: try #require(spaceEvent(type: .keyUp)))

    #expect(pressCount == 1)
    #expect(releaseCount == 1)
  }

  @MainActor
  @Test("Disabled push-to-talk ignores Space")
  func disabledPushToTalkKeyboardPath() throws {
    let view = HoldToTalkCaptureNSView()
    var pressCount = 0
    var releaseCount = 0
    view.onPress = { pressCount += 1 }
    view.onRelease = { releaseCount += 1 }
    view.isEnabled = false

    view.keyDown(with: try #require(spaceEvent(type: .keyDown)))
    view.keyUp(with: try #require(spaceEvent(type: .keyUp)))

    #expect(pressCount == 0)
    #expect(releaseCount == 0)
  }

  @MainActor
  private func spaceEvent(type: NSEvent.EventType, isRepeat: Bool = false) -> NSEvent? {
    NSEvent.keyEvent(
      with: type,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: " ",
      charactersIgnoringModifiers: " ",
      isARepeat: isRepeat,
      keyCode: 49
    )
  }
}
