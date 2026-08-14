import Foundation

enum PetAssetType: String, Codable, Sendable {
  case staticImage
}

enum PetSource: String, Codable, Sendable {
  case bundled
  case userImported
}

struct PetModel: Identifiable, Codable, Equatable, Sendable {
  let id: String
  var name: String
  let source: PetSource
  let type: PetAssetType
  let assetLocation: String
  let createdAt: Date
  var scale: Double

  var assetName: String {
    assetLocation
  }
}

extension PetModel {
  static let officialFlowerBunny = PetModel(
    id: "official_flower_bunny",
    name: "花花老师",
    source: .bundled,
    type: .staticImage,
    assetLocation: "official_flower_bunny",
    createdAt: Date(timeIntervalSince1970: 0),
    scale: 1
  )
}
