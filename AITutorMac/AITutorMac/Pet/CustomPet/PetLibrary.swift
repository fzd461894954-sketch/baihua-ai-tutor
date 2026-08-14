import AppKit
import Observation

enum PetLibraryError: LocalizedError {
  case cannotUsePet
  case cannotDeleteOfficial

  var errorDescription: String? {
    switch self {
    case .cannotUsePet:
      return "这个角色的本地图片已经损坏或丢失，已恢复为花花老师。"
    case .cannotDeleteOfficial:
      return "花花老师是默认角色，不能删除。"
    }
  }
}

@MainActor
@Observable
final class PetLibrary {
  private(set) var pets: [PetModel] = [.officialFlowerBunny]
  private(set) var currentPet: PetModel = .officialFlowerBunny

  @ObservationIgnored
  var onCurrentPetChange: ((PetModel, NSImage?) -> Void)?

  @ObservationIgnored
  private let store: PetLibraryStore

  @ObservationIgnored
  private let storedAssetValidator: PetImageValidator

  @ObservationIgnored
  private let configuration: PetConfiguration

  @ObservationIgnored
  private let imageCache = NSCache<NSString, NSImage>()

  var storageLocation: URL {
    store.rootURL
  }

  init(
    store: PetLibraryStore,
    validator: PetImageValidator,
    configuration: PetConfiguration = .default
  ) {
    self.store = store
    storedAssetValidator = PetImageValidator(
      minimumDimension: 1,
      optimizedMaximumDimension: validator.optimizedMaximumDimension,
      safetyMaximumDimension: validator.safetyMaximumDimension,
      safetyMaximumPixelCount: validator.safetyMaximumPixelCount
    )
    self.configuration = configuration
    restoreLibrary()
  }

  @discardableResult
  func select(_ id: String) throws -> PetModel {
    guard let pet = pets.first(where: { $0.id == id }) else {
      return try fallBackFromInvalidPet(invalidPetID: nil)
    }
    guard isUsable(pet) else {
      return try fallBackFromInvalidPet(invalidPetID: pet.id)
    }

    try store.persist(userPets: userPets, currentPetID: pet.id)
    currentPet = pet
    onCurrentPetChange?(pet, image(for: pet))
    AppLogger.customPet.info("Current pet changed: \(pet.id, privacy: .public)")
    return pet
  }

  func addAndSelect(_ pet: PetModel) throws {
    guard pet.source == .userImported, isUsable(pet) else {
      throw PetLibraryError.cannotUsePet
    }

    let normalizedPet = normalized(pet)
    var newUserPets = userPets.filter { $0.id != normalizedPet.id }
    newUserPets.append(normalizedPet)
    try store.persist(userPets: newUserPets, currentPetID: normalizedPet.id)

    pets = [.officialFlowerBunny] + newUserPets
    currentPet = normalizedPet
    onCurrentPetChange?(normalizedPet, image(for: normalizedPet))
  }

  func updateScale(for id: String, scale: Double) {
    let safeScale = Double(configuration.clampedScale(CGFloat(scale)))
    guard let index = pets.firstIndex(where: { $0.id == id }) else {
      return
    }

    pets[index].scale = safeScale
    if currentPet.id == id {
      currentPet.scale = safeScale
    }

    guard pets[index].source == .userImported else {
      return
    }
    do {
      try store.persist(userPets: userPets, currentPetID: currentPet.id)
    } catch {
      AppLogger.customPet.error("Failed to persist custom pet scale")
    }
  }

  func delete(_ pet: PetModel) throws {
    guard pet.source == .userImported else {
      throw PetLibraryError.cannotDeleteOfficial
    }
    guard pets.contains(where: { $0.id == pet.id }) else {
      return
    }

    if currentPet.id == pet.id {
      try store.persist(
        userPets: userPets,
        currentPetID: PetModel.officialFlowerBunny.id
      )
      currentPet = .officialFlowerBunny
      onCurrentPetChange?(.officialFlowerBunny, image(for: .officialFlowerBunny))
    }

    try store.removeAssets(for: pet)
    let remaining = userPets.filter { $0.id != pet.id }
    try store.persist(userPets: remaining, currentPetID: currentPet.id)
    pets = [.officialFlowerBunny] + remaining
    imageCache.removeObject(forKey: pet.id as NSString)
    imageCache.removeObject(forKey: "thumbnail:\(pet.id)" as NSString)
    AppLogger.customPet.info("Deleted local pet copy: \(pet.id, privacy: .public)")
  }

  func image(for pet: PetModel) -> NSImage? {
    let key = pet.id as NSString
    if let cached = imageCache.object(forKey: key) {
      return cached
    }

    let image: NSImage?
    switch pet.source {
    case .bundled:
      image = NSImage(named: NSImage.Name(pet.assetLocation))
    case .userImported:
      image = store.assetURL(for: pet).flatMap(NSImage.init(contentsOf:))
    }

    guard let image, image.isValid else {
      return nil
    }
    imageCache.setObject(image, forKey: key)
    return image
  }

  func thumbnail(for pet: PetModel) -> NSImage? {
    guard pet.source == .userImported else {
      return image(for: pet)
    }
    let key = "thumbnail:\(pet.id)" as NSString
    if let cached = imageCache.object(forKey: key) {
      return cached
    }
    guard
      let url = store.thumbnailURL(for: pet),
      let image = NSImage(contentsOf: url),
      image.isValid
    else {
      return image(for: pet)
    }
    imageCache.setObject(image, forKey: key)
    return image
  }

  private var userPets: [PetModel] {
    pets.filter { $0.source == .userImported }
  }

  private func restoreLibrary() {
    let snapshot: PetLibrarySnapshot
    do {
      snapshot = try store.loadSnapshot()
    } catch {
      AppLogger.customPet.error("Pet library index was unreadable; using official fallback")
      try? store.persist(
        userPets: [],
        currentPetID: PetModel.officialFlowerBunny.id
      )
      return
    }

    let validPets = snapshot.userPets.compactMap { pet -> PetModel? in
      let normalizedPet = normalized(pet)
      guard isUsable(normalizedPet) else {
        AppLogger.customPet.error(
          "Removed invalid local pet from index: \(pet.id, privacy: .public)"
        )
        return nil
      }
      return normalizedPet
    }

    pets = [.officialFlowerBunny] + validPets
    currentPet = pets.first(where: { $0.id == snapshot.currentPetID })
      ?? .officialFlowerBunny

    do {
      try store.persist(userPets: validPets, currentPetID: currentPet.id)
    } catch {
      AppLogger.customPet.error("Failed to repair local pet library index")
    }
  }

  private func normalized(_ pet: PetModel) -> PetModel {
    var value = pet
    value.name = PetNameValidator.normalized(pet.name)
    value.scale = Double(configuration.clampedScale(CGFloat(pet.scale)))
    return value
  }

  private func isUsable(_ pet: PetModel) -> Bool {
    if pet.source == .bundled {
      return pet.id == PetModel.officialFlowerBunny.id
    }
    guard let url = store.assetURL(for: pet) else {
      return false
    }
    return (try? storedAssetValidator.validate(url)) != nil
  }

  private func fallBackFromInvalidPet(invalidPetID: String?) throws -> PetModel {
    let remaining = userPets.filter { $0.id != invalidPetID }
    try store.persist(
      userPets: remaining,
      currentPetID: PetModel.officialFlowerBunny.id
    )
    pets = [.officialFlowerBunny] + remaining
    currentPet = .officialFlowerBunny
    onCurrentPetChange?(.officialFlowerBunny, image(for: .officialFlowerBunny))
    throw PetLibraryError.cannotUsePet
  }
}
