import Foundation

enum PetAssetType: String, Codable, Sendable {
  case staticImage
}

struct PetModel: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let name: String
  let assetName: String
  let type: PetAssetType
}

extension PetModel {
  static let officialFlowerBunny = PetModel(
    id: "official_flower_bunny",
    name: "花花老师",
    assetName: "official_flower_bunny",
    type: .staticImage
  )
}
