import XCTest

@testable import AITutorMac

@MainActor
final class AppStateTests: XCTestCase {
  func testInitialShellStateIsReadyAndPanelIsHidden() {
    let state = AppState()

    XCTAssertEqual(state.shellStatus, .ready)
    XCTAssertEqual(state.shellStatus.displayText, "准备就绪")
    XCTAssertFalse(state.isPanelVisible)
    XCTAssertFalse(state.isPetVisible)
  }

  func testHotKeyFailureHasAnHonestStatus() {
    let state = AppState()

    state.shellStatus = .hotKeyUnavailable

    XCTAssertEqual(state.shellStatus.displayText, "快捷键不可用")
  }
}
