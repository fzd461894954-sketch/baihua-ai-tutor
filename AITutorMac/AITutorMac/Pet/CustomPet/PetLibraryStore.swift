import Foundation

struct PetManifest: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let id: String
  let name: String
  let source: PetSource
  let assetType: PetAssetType
  let imageFile: String
  let createdAt: Date
  let scale: Double

  init(pet: PetModel) {
    schemaVersion = 1
    id = pet.id
    name = pet.name
    source = pet.source
    assetType = pet.type
    imageFile = pet.assetLocation
    createdAt = pet.createdAt
    scale = pet.scale
  }

  var pet: PetModel {
    PetModel(
      id: id,
      name: name,
      source: source,
      type: assetType,
      assetLocation: imageFile,
      createdAt: createdAt,
      scale: scale
    )
  }
}

struct PetLibraryIndex: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let currentPetID: String
  let petIDs: [String]

  init(currentPetID: String, petIDs: [String]) {
    schemaVersion = 1
    self.currentPetID = currentPetID
    self.petIDs = petIDs
  }
}

struct PetLibrarySnapshot: Equatable, Sendable {
  let currentPetID: String
  let userPets: [PetModel]
}

enum PetLibraryStoreError: LocalizedError {
  case invalidIdentifier
  case invalidManifest
  case cannotReadLibrary
  case cannotSaveLibrary
  case cannotDeletePet

  var errorDescription: String? {
    switch self {
    case .invalidIdentifier, .invalidManifest, .cannotReadLibrary:
      return "无法读取本地角色资料，已恢复为花花老师。"
    case .cannotSaveLibrary:
      return "无法保存角色，请检查磁盘空间后重试。"
    case .cannotDeletePet:
      return "无法删除这个角色，请稍后再试。"
    }
  }
}

final class PetLibraryStore: @unchecked Sendable {
  static let imageFileName = "pet.png"
  static let thumbnailFileName = "thumbnail.png"
  static let manifestFileName = "manifest.json"

  let rootURL: URL

  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    bundleIdentifier: String? = Bundle.main.bundleIdentifier
  ) {
    self.fileManager = fileManager

    if let rootURL {
      self.rootURL = rootURL
    } else {
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? fileManager.temporaryDirectory
      let appDirectoryName = bundleIdentifier ?? "com.baihuaai.AITutorMac"
      self.rootURL = applicationSupport
        .appendingPathComponent(appDirectoryName, isDirectory: true)
        .appendingPathComponent("Pets", isDirectory: true)
    }

    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  func loadSnapshot() throws -> PetLibrarySnapshot {
    let indexURL = rootURL.appendingPathComponent("index.json", isDirectory: false)
    guard fileManager.fileExists(atPath: indexURL.path) else {
      return PetLibrarySnapshot(
        currentPetID: PetModel.officialFlowerBunny.id,
        userPets: []
      )
    }

    guard
      let data = try? Data(contentsOf: indexURL),
      let index = try? decoder.decode(PetLibraryIndex.self, from: data),
      index.schemaVersion == 1
    else {
      throw PetLibraryStoreError.cannotReadLibrary
    }

    var pets: [PetModel] = []
    var seenIDs = Set<String>()
    for id in index.petIDs where !seenIDs.contains(id) {
      seenIDs.insert(id)
      guard isValidImportedIdentifier(id) else {
        continue
      }

      let manifestURL = try directoryURL(for: id)
        .appendingPathComponent(Self.manifestFileName, isDirectory: false)
      guard
        let manifestData = try? Data(contentsOf: manifestURL),
        let manifest = try? decoder.decode(PetManifest.self, from: manifestData),
        isValid(manifest: manifest, expectedID: id)
      else {
        continue
      }
      pets.append(manifest.pet)
    }

    return PetLibrarySnapshot(currentPetID: index.currentPetID, userPets: pets)
  }

  func persist(userPets: [PetModel], currentPetID: String) throws {
    do {
      try ensureRootDirectory()
      for pet in userPets {
        guard isValidImportedPet(pet) else {
          throw PetLibraryStoreError.invalidManifest
        }
        let directory = try directoryURL(for: pet.id)
        try fileManager.createDirectory(
          at: directory,
          withIntermediateDirectories: true
        )
        try writeManifest(pet, to: directory)
      }

      let index = PetLibraryIndex(
        currentPetID: currentPetID,
        petIDs: userPets.map(\.id)
      )
      let indexData = try encoder.encode(index)
      try indexData.write(
        to: rootURL.appendingPathComponent("index.json", isDirectory: false),
        options: .atomic
      )
    } catch let error as PetLibraryStoreError {
      throw error
    } catch {
      throw PetLibraryStoreError.cannotSaveLibrary
    }
  }

  func makeTemporaryImportDirectory() throws -> URL {
    do {
      try ensureRootDirectory()
      let url = rootURL.appendingPathComponent(
        ".importing-\(UUID().uuidString.lowercased())",
        isDirectory: true
      )
      try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
      return url
    } catch {
      throw PetLibraryStoreError.cannotSaveLibrary
    }
  }

  func installTemporaryDirectory(_ temporaryURL: URL, for id: String) throws {
    do {
      let destination = try directoryURL(for: id)
      guard !fileManager.fileExists(atPath: destination.path) else {
        throw PetLibraryStoreError.cannotSaveLibrary
      }
      try fileManager.moveItem(at: temporaryURL, to: destination)
    } catch let error as PetLibraryStoreError {
      throw error
    } catch {
      throw PetLibraryStoreError.cannotSaveLibrary
    }
  }

  func writeManifest(_ pet: PetModel, to directory: URL) throws {
    guard isValidImportedPet(pet) else {
      throw PetLibraryStoreError.invalidManifest
    }
    do {
      let data = try encoder.encode(PetManifest(pet: pet))
      try data.write(
        to: directory.appendingPathComponent(Self.manifestFileName, isDirectory: false),
        options: .atomic
      )
    } catch {
      throw PetLibraryStoreError.cannotSaveLibrary
    }
  }

  func assetURL(for pet: PetModel) -> URL? {
    guard isValidImportedPet(pet), let directory = try? directoryURL(for: pet.id) else {
      return nil
    }
    return directory.appendingPathComponent(pet.assetLocation, isDirectory: false)
  }

  func thumbnailURL(for pet: PetModel) -> URL? {
    guard isValidImportedPet(pet), let directory = try? directoryURL(for: pet.id) else {
      return nil
    }
    return directory.appendingPathComponent(Self.thumbnailFileName, isDirectory: false)
  }

  func removeAssets(for pet: PetModel) throws {
    guard pet.source == .userImported else {
      throw PetLibraryStoreError.invalidIdentifier
    }
    do {
      let directory = try directoryURL(for: pet.id)
      if fileManager.fileExists(atPath: directory.path) {
        try fileManager.removeItem(at: directory)
      }
    } catch {
      throw PetLibraryStoreError.cannotDeletePet
    }
  }

  func removeTemporaryDirectoryIfPresent(_ url: URL) {
    guard url.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL else {
      return
    }
    try? fileManager.removeItem(at: url)
  }

  func directoryURL(for id: String) throws -> URL {
    guard isValidImportedIdentifier(id) else {
      throw PetLibraryStoreError.invalidIdentifier
    }
    return rootURL.appendingPathComponent(id, isDirectory: true)
  }

  func isValidImportedIdentifier(_ id: String) -> Bool {
    guard id.hasPrefix("user_") else {
      return false
    }
    return UUID(uuidString: String(id.dropFirst("user_".count))) != nil
  }

  private func ensureRootDirectory() throws {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
  }

  private func isValid(manifest: PetManifest, expectedID: String) -> Bool {
    manifest.schemaVersion == 1
      && manifest.id == expectedID
      && manifest.source == .userImported
      && manifest.assetType == .staticImage
      && manifest.imageFile == Self.imageFileName
      && manifest.scale.isFinite
  }

  private func isValidImportedPet(_ pet: PetModel) -> Bool {
    pet.source == .userImported
      && pet.type == .staticImage
      && pet.assetLocation == Self.imageFileName
      && pet.scale.isFinite
      && isValidImportedIdentifier(pet.id)
  }
}
