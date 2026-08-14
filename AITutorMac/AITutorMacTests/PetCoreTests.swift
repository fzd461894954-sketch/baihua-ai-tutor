import XCTest

@testable import AITutorMac

final class PetCoreTests: XCTestCase {
  func testScaleClampUsesConfiguredSafetyRange() {
    let configuration = PetConfiguration.default

    XCTAssertEqual(configuration.clampedScale(0.1), 0.7, accuracy: 0.0001)
    XCTAssertEqual(configuration.clampedScale(1.1), 1.1, accuracy: 0.0001)
    XCTAssertEqual(configuration.clampedScale(3), 1.4, accuracy: 0.0001)
  }

  func testDefaultConfigurationMatchesDesktopPetBaseline() {
    let configuration = PetConfiguration.default

    XCTAssertEqual(configuration.defaultSize.width, 180, accuracy: 0.0001)
    XCTAssertEqual(configuration.defaultSize.height, 180, accuracy: 0.0001)
    XCTAssertEqual(configuration.defaultScale, 1, accuracy: 0.0001)
    XCTAssertEqual(configuration.minimumScale, 0.7, accuracy: 0.0001)
    XCTAssertEqual(configuration.maximumScale, 1.4, accuracy: 0.0001)
    XCTAssertEqual(PetModel.officialFlowerBunny.id, "official_flower_bunny")
    XCTAssertEqual(PetModel.officialFlowerBunny.name, "花花老师")
  }

  func testPositionScaleAndVisibilityRoundTripThroughStore() throws {
    let suiteName = "PetCoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PetStore(defaults: defaults)
    XCTAssertNil(store.loadPosition())
    XCTAssertEqual(store.loadScale(default: 1), 1, accuracy: 0.0001)
    XCTAssertTrue(store.loadVisibility())

    store.savePosition(PetWindowPosition(x: 321.5, y: 87.25))
    store.saveScale(1.2)
    store.saveVisibility(false)

    let restoredStore = PetStore(defaults: defaults)
    XCTAssertEqual(
      restoredStore.loadPosition(),
      PetWindowPosition(x: 321.5, y: 87.25)
    )
    XCTAssertEqual(restoredStore.loadScale(default: 1), 1.2, accuracy: 0.0001)
    XCTAssertFalse(restoredStore.loadVisibility())
  }

  func testOffscreenSavedPositionFallsBackToMainScreenLowerRight() {
    let configuration = PetConfiguration.default
    let visibleFrame = CGRect(x: 0, y: 40, width: 1_440, height: 860)
    let size = configuration.size(for: 1)

    let restored = configuration.restoredOrigin(
      savedPosition: PetWindowPosition(x: 4_000, y: 4_000),
      size: size,
      visibleFrames: [visibleFrame],
      fallbackVisibleFrame: visibleFrame
    )

    XCTAssertEqual(restored.x, visibleFrame.maxX - size.width - 24, accuracy: 0.0001)
    XCTAssertEqual(restored.y, visibleFrame.minY + 24, accuracy: 0.0001)
  }

  func testMeaningfullyVisibleSavedPositionIsPreserved() {
    let configuration = PetConfiguration.default
    let visibleFrame = CGRect(x: 0, y: 40, width: 1_440, height: 860)
    let saved = PetWindowPosition(x: 1_400, y: 120)

    let restored = configuration.restoredOrigin(
      savedPosition: saved,
      size: configuration.defaultSize,
      visibleFrames: [visibleFrame],
      fallbackVisibleFrame: visibleFrame
    )

    XCTAssertEqual(restored, saved.point)
  }
}
