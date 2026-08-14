import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PreparedPetImport: Identifiable {
  let id = UUID()
  let sourceURL: URL
  let suggestedName: String
  let validation: PetImageValidationResult
  let previewImage: NSImage
}

enum PetImporterError: LocalizedError {
  case cannotOptimizeImage
  case cannotSaveImage

  var errorDescription: String? {
    switch self {
    case .cannotOptimizeImage:
      return "无法处理这张 PNG，请换一张图片再试。"
    case .cannotSaveImage:
      return "无法保存角色，请检查磁盘空间后重试。"
    }
  }
}

final class PetImporter: @unchecked Sendable {
  private let validator: PetImageValidator
  private let store: PetLibraryStore
  private let configuration: PetConfiguration

  init(
    validator: PetImageValidator,
    store: PetLibraryStore,
    configuration: PetConfiguration = .default
  ) {
    self.validator = validator
    self.store = store
    self.configuration = configuration
  }

  func prepare(_ sourceURL: URL) throws -> PreparedPetImport {
    let validation = try validator.validate(sourceURL)
    let previewCGImage = try validator.makePreviewImage(sourceURL)
    let previewImage = NSImage(
      cgImage: previewCGImage,
      size: NSSize(width: previewCGImage.width, height: previewCGImage.height)
    )
    return PreparedPetImport(
      sourceURL: sourceURL,
      suggestedName: PetNameValidator.suggestedName(for: sourceURL),
      validation: validation,
      previewImage: previewImage
    )
  }

  func importPet(
    from prepared: PreparedPetImport,
    name: String,
    scale: Double
  ) throws -> PetModel {
    _ = try validator.validate(prepared.sourceURL)

    let id = "user_\(UUID().uuidString.lowercased())"
    let safeScale = Double(
      configuration.clampedScale(CGFloat(scale))
    )
    let pet = PetModel(
      id: id,
      name: PetNameValidator.normalized(name, fallback: prepared.suggestedName),
      source: .userImported,
      type: .staticImage,
      assetLocation: PetLibraryStore.imageFileName,
      createdAt: Date(
        timeIntervalSince1970: floor(Date().timeIntervalSince1970)
      ),
      scale: safeScale
    )

    let temporaryDirectory = try store.makeTemporaryImportDirectory()
    do {
      guard
        let source = CGImageSourceCreateWithURL(
          prepared.sourceURL as CFURL,
          [kCGImageSourceShouldCache: false] as CFDictionary
        ),
        let optimizedImage = validator.makeThumbnail(
          from: source,
          maximumDimension: validator.optimizedMaximumDimension
        ),
        let normalizedImage = normalizedSRGBImage(optimizedImage),
        let thumbnail = resizedImage(normalizedImage, maximumDimension: 256)
      else {
        throw PetImporterError.cannotOptimizeImage
      }

      try writePNG(
        normalizedImage,
        to: temporaryDirectory.appendingPathComponent(
          PetLibraryStore.imageFileName,
          isDirectory: false
        )
      )
      try writePNG(
        thumbnail,
        to: temporaryDirectory.appendingPathComponent(
          PetLibraryStore.thumbnailFileName,
          isDirectory: false
        )
      )
      try store.writeManifest(pet, to: temporaryDirectory)
      try store.installTemporaryDirectory(temporaryDirectory, for: id)
      AppLogger.customPet.info("Imported local pet: \(id, privacy: .public)")
      return pet
    } catch {
      store.removeTemporaryDirectoryIfPresent(temporaryDirectory)
      if error is PetImageValidationError || error is PetLibraryStoreError {
        throw error
      }
      AppLogger.customPet.error("Failed to create optimized local pet copy")
      throw (error as? PetImporterError) ?? PetImporterError.cannotSaveImage
    }
  }

  func discardImportedPet(_ pet: PetModel) {
    try? store.removeAssets(for: pet)
  }

  private func normalizedSRGBImage(_ image: CGImage) -> CGImage? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      return nil
    }
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
      | CGImageAlphaInfo.premultipliedLast.rawValue
    guard
      let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
  }

  private func resizedImage(_ image: CGImage, maximumDimension: Int) -> CGImage? {
    let longestEdge = max(image.width, image.height)
    guard longestEdge > maximumDimension else {
      return image
    }

    let ratio = CGFloat(maximumDimension) / CGFloat(longestEdge)
    let width = max(1, Int((CGFloat(image.width) * ratio).rounded()))
    let height = max(1, Int((CGFloat(image.height) * ratio).rounded()))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      return nil
    }
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
      | CGImageAlphaInfo.premultipliedLast.rawValue
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  private func writePNG(_ image: CGImage, to url: URL) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw PetImporterError.cannotSaveImage
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw PetImporterError.cannotSaveImage
    }
  }
}
