import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import AITutorMac

@MainActor
final class CustomPetTests: XCTestCase {
  private var temporaryRoot: URL!
  private var store: PetLibraryStore!
  private var validator: PetImageValidator!
  private var importer: PetImporter!

  override func setUpWithError() throws {
    temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("CustomPetTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryRoot,
      withIntermediateDirectories: true
    )
    store = PetLibraryStore(
      rootURL: temporaryRoot.appendingPathComponent("Pets", isDirectory: true)
    )
    validator = PetImageValidator()
    importer = PetImporter(validator: validator, store: store)
  }

  override func tearDownWithError() throws {
    if let temporaryRoot {
      try? FileManager.default.removeItem(at: temporaryRoot)
    }
    importer = nil
    validator = nil
    store = nil
    temporaryRoot = nil
  }

  func testManifestEncodeDecodeKeepsPortableFieldsOnly() throws {
    let pet = importedModel(name: "小狐狸", scale: 1.2)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let data = try encoder.encode(PetManifest(pet: pet))
    let decoded = try decoder.decode(PetManifest.self, from: data)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertEqual(decoded.pet, pet)
    XCTAssertEqual(decoded.schemaVersion, 1)
    XCTAssertEqual(decoded.imageFile, "pet.png")
    XCTAssertFalse(json.contains("/Users/"))
  }

  func testLibraryIndexRoundTripRestoresCurrentPet() throws {
    let source = temporaryRoot.appendingPathComponent("roundtrip.png")
    try writePNG(to: source, width: 256, height: 256, transparent: true)
    let pet = try importer.importPet(
      from: importer.prepare(source),
      name: "小猫",
      scale: 1.1
    )
    try store.persist(userPets: [pet], currentPetID: pet.id)

    let snapshot = try store.loadSnapshot()

    XCTAssertEqual(snapshot.currentPetID, pet.id)
    XCTAssertEqual(snapshot.userPets, [pet])
  }

  func testStandardRGBAImagePassesValidation() throws {
    let url = temporaryRoot.appendingPathComponent("standard.png")
    try writePNG(to: url, width: 1_024, height: 1_024, transparent: true)

    let result = try validator.validate(url)

    XCTAssertEqual(result.pixelWidth, 1_024)
    XCTAssertEqual(result.pixelHeight, 1_024)
    XCTAssertTrue(result.hasTransparentPixels)
    XCTAssertFalse(result.requiresOptimization)
  }

  func testWideRGBAImagePassesValidation() throws {
    let url = temporaryRoot.appendingPathComponent("wide.png")
    try writePNG(to: url, width: 1_600, height: 800, transparent: true)

    let result = try validator.validate(url)

    XCTAssertEqual(result.pixelWidth, 1_600)
    XCTAssertEqual(result.pixelHeight, 800)
    XCTAssertTrue(result.hasTransparentPixels)
  }

  func testTallRGBAImagePassesValidation() throws {
    let url = temporaryRoot.appendingPathComponent("tall.png")
    try writePNG(to: url, width: 800, height: 1_600, transparent: true)

    let result = try validator.validate(url)

    XCTAssertEqual(result.pixelWidth, 800)
    XCTAssertEqual(result.pixelHeight, 1_600)
    XCTAssertTrue(result.hasTransparentPixels)
  }

  func testOpaquePNGWarnsButIsNotRejected() throws {
    let url = temporaryRoot.appendingPathComponent("opaque.png")
    try writePNG(to: url, width: 512, height: 512, transparent: false)

    let result = try validator.validate(url)

    XCTAssertFalse(result.hasTransparentPixels)
  }

  func testHugePNGIsAcceptedAndCreatesOptimizedCopy() throws {
    let url = temporaryRoot.appendingPathComponent("large.png")
    try writePNG(to: url, width: 8_000, height: 8_000, transparent: true)
    let prepared = try importer.prepare(url)

    let pet = try importer.importPet(from: prepared, name: "长长老师", scale: 1)
    let internalURL = try XCTUnwrap(store.assetURL(for: pet))
    let internalResult = try validator.validate(internalURL)

    XCTAssertTrue(prepared.validation.requiresOptimization)
    XCTAssertLessThanOrEqual(max(internalResult.pixelWidth, internalResult.pixelHeight), 2_048)
    XCTAssertTrue(FileManager.default.fileExists(atPath: internalURL.path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: try XCTUnwrap(store.thumbnailURL(for: pet)).path)
    )
  }

  func testInvalidOrDisguisedPNGIsRejectedGracefully() throws {
    let corruptURL = temporaryRoot.appendingPathComponent("broken.png")
    try Data("not an image".utf8).write(to: corruptURL)

    XCTAssertThrowsError(try validator.validate(corruptURL)) { error in
      XCTAssertEqual(error as? PetImageValidationError, .notPNG)
    }

    let wrongExtension = temporaryRoot.appendingPathComponent("valid.jpg")
    try writePNG(to: wrongExtension, width: 256, height: 256, transparent: true)
    XCTAssertThrowsError(try validator.validate(wrongExtension)) { error in
      XCTAssertEqual(error as? PetImageValidationError, .notPNG)
    }
  }

  func testTooSmallAndSafetyLimitAreRejected() throws {
    let smallURL = temporaryRoot.appendingPathComponent("small.png")
    try writePNG(to: smallURL, width: 127, height: 128, transparent: true)
    XCTAssertThrowsError(try validator.validate(smallURL)) { error in
      XCTAssertEqual(error as? PetImageValidationError, .tooSmall(minimum: 128))
    }

    let strictValidator = PetImageValidator(
      safetyMaximumDimension: 300,
      safetyMaximumPixelCount: 90_000
    )
    let largeURL = temporaryRoot.appendingPathComponent("unsafe.png")
    try writePNG(to: largeURL, width: 301, height: 300, transparent: true)
    XCTAssertThrowsError(try strictValidator.validate(largeURL)) { error in
      XCTAssertEqual(error as? PetImageValidationError, .exceedsSafetyLimit)
    }
  }

  func testImportDoesNotModifySourceAndPersistsSelectionAcrossRestart() throws {
    let source = temporaryRoot.appendingPathComponent("source.png")
    try writePNG(to: source, width: 512, height: 512, transparent: true)
    let originalData = try Data(contentsOf: source)
    let prepared = try importer.prepare(source)
    let library = PetLibrary(store: store, validator: validator)
    var changedPetID: String?
    library.onCurrentPetChange = { pet, _ in changedPetID = pet.id }

    let pet = try importer.importPet(from: prepared, name: "  我的老师  ", scale: 9)
    try library.addAndSelect(pet)

    XCTAssertEqual(library.currentPet.id, pet.id)
    XCTAssertEqual(changedPetID, pet.id)
    XCTAssertEqual(library.currentPet.name, "我的老师")
    XCTAssertEqual(library.currentPet.scale, 1.4, accuracy: 0.0001)
    XCTAssertEqual(try Data(contentsOf: source), originalData)

    let restoredLibrary = PetLibrary(store: store, validator: validator)
    XCTAssertEqual(restoredLibrary.currentPet.id, pet.id)
    XCTAssertEqual(restoredLibrary.pets.count, 2)
  }

  func testMissingCurrentAssetFallsBackAndRepairsIndex() throws {
    let source = temporaryRoot.appendingPathComponent("will-disappear.png")
    try writePNG(to: source, width: 256, height: 256, transparent: true)
    let pet = try importer.importPet(
      from: importer.prepare(source),
      name: "会消失",
      scale: 1
    )
    try store.persist(userPets: [pet], currentPetID: pet.id)
    try FileManager.default.removeItem(at: try XCTUnwrap(store.assetURL(for: pet)))

    let restoredLibrary = PetLibrary(store: store, validator: validator)
    let repairedSnapshot = try store.loadSnapshot()

    XCTAssertEqual(restoredLibrary.currentPet, .officialFlowerBunny)
    XCTAssertEqual(restoredLibrary.pets, [.officialFlowerBunny])
    XCTAssertEqual(repairedSnapshot.currentPetID, PetModel.officialFlowerBunny.id)
    XCTAssertTrue(repairedSnapshot.userPets.isEmpty)
  }

  func testDeletingCurrentCustomPetSwitchesToOfficialAndKeepsSource() throws {
    let source = temporaryRoot.appendingPathComponent("keep-original.png")
    try writePNG(to: source, width: 256, height: 256, transparent: true)
    let library = PetLibrary(store: store, validator: validator)
    let pet = try importer.importPet(
      from: importer.prepare(source),
      name: "待删除",
      scale: 1
    )
    try library.addAndSelect(pet)
    let internalURL = try XCTUnwrap(store.assetURL(for: pet))

    try library.delete(pet)

    XCTAssertEqual(library.currentPet, .officialFlowerBunny)
    XCTAssertEqual(library.pets, [.officialFlowerBunny])
    XCTAssertFalse(FileManager.default.fileExists(atPath: internalURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }

  func testOfficialPetCannotBeDeleted() throws {
    let library = PetLibrary(store: store, validator: validator)

    XCTAssertThrowsError(try library.delete(.officialFlowerBunny)) { error in
      XCTAssertTrue(error is PetLibraryError)
    }
    XCTAssertEqual(library.pets, [.officialFlowerBunny])
  }

  func testNameValidationAndScaleCompatibility() {
    XCTAssertEqual(PetNameValidator.normalized("  小机器人  "), "小机器人")
    XCTAssertEqual(PetNameValidator.normalized("   "), "我的老师")
    XCTAssertEqual(
      PetNameValidator.normalized(String(repeating: "猫", count: 80)).count,
      PetNameValidator.maximumLength
    )
    XCTAssertEqual(PetConfiguration.default.clampedScale(0), 0.7, accuracy: 0.0001)
    XCTAssertEqual(PetConfiguration.default.clampedScale(9), 1.4, accuracy: 0.0001)
  }

  func testCorruptIndexFallsBackToOfficialWithoutCrash() throws {
    try FileManager.default.createDirectory(
      at: store.rootURL,
      withIntermediateDirectories: true
    )
    try Data("{ definitely not json".utf8).write(
      to: store.rootURL.appendingPathComponent("index.json")
    )

    let library = PetLibrary(store: store, validator: validator)

    XCTAssertEqual(library.currentPet, .officialFlowerBunny)
    XCTAssertEqual(library.pets, [.officialFlowerBunny])
  }

  func testPetLibraryUsesAnIndependentManagementWindow() throws {
    let library = PetLibrary(store: store, validator: validator)
    let controller = PetLibraryWindowController(library: library, importer: importer)

    controller.show()
    let managementWindow = try XCTUnwrap(
      NSApplication.shared.windows.first(where: { $0.title == "我的桌面老师" })
    )

    XCTAssertTrue(managementWindow.isVisible)
    XCTAssertNotEqual(managementWindow.title, "白话 AI")
    XCTAssertNotEqual(managementWindow.title, PetModel.officialFlowerBunny.name)

    controller.stop()
    XCTAssertFalse(managementWindow.isVisible)
  }

  private func importedModel(name: String, scale: Double) -> PetModel {
    PetModel(
      id: "user_\(UUID().uuidString.lowercased())",
      name: name,
      source: .userImported,
      type: .staticImage,
      assetLocation: PetLibraryStore.imageFileName,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      scale: scale
    )
  }

  private func writePNG(
    to url: URL,
    width: Int,
    height: Int,
    transparent: Bool
  ) throws {
    let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
      | CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try XCTUnwrap(
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    )

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.3, green: 0.55, blue: 0.9, alpha: 1))
    if transparent {
      context.fill(
        CGRect(
          x: max(1, width / 10),
          y: max(1, height / 10),
          width: max(1, width * 8 / 10),
          height: max(1, height * 8 / 10)
        )
      )
    } else {
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    let image = try XCTUnwrap(context.makeImage())
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    )
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }
}
