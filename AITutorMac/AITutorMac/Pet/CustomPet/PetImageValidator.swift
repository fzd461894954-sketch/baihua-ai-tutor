import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PetImageValidationResult: Equatable, Sendable {
  let pixelWidth: Int
  let pixelHeight: Int
  let hasTransparentPixels: Bool
  let requiresOptimization: Bool
}

enum PetImageValidationError: LocalizedError, Equatable {
  case fileMissing
  case notPNG
  case unreadableImage
  case animatedPNG
  case tooSmall(minimum: Int)
  case exceedsSafetyLimit

  var errorDescription: String? {
    switch self {
    case .fileMissing:
      return "找不到这张图片，请重新选择。"
    case .notPNG:
      return "请选择 PNG 格式的图片。"
    case .unreadableImage:
      return "无法读取这张 PNG，请换一张图片再试。"
    case .animatedPNG:
      return "当前版本只支持单张静态 PNG，不支持 APNG 动画。"
    case let .tooSmall(minimum):
      return "图片尺寸太小，请选择至少 \(minimum) × \(minimum) 像素的 PNG。"
    case .exceedsSafetyLimit:
      return "图片尺寸过大，无法安全处理，请先缩小图片后再试。"
    }
  }
}

final class PetImageValidator: @unchecked Sendable {
  let minimumDimension: Int
  let optimizedMaximumDimension: Int
  let safetyMaximumDimension: Int
  let safetyMaximumPixelCount: Int

  init(
    minimumDimension: Int = 128,
    optimizedMaximumDimension: Int = 2_048,
    safetyMaximumDimension: Int = 16_000,
    safetyMaximumPixelCount: Int = 100_000_000
  ) {
    self.minimumDimension = minimumDimension
    self.optimizedMaximumDimension = optimizedMaximumDimension
    self.safetyMaximumDimension = safetyMaximumDimension
    self.safetyMaximumPixelCount = safetyMaximumPixelCount
  }

  func validate(_ url: URL) throws -> PetImageValidationResult {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw PetImageValidationError.fileMissing
    }

    guard url.pathExtension.lowercased() == "png", hasPNGSignature(url) else {
      throw PetImageValidationError.notPNG
    }

    guard
      let source = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ),
      let sourceType = CGImageSourceGetType(source),
      UTType(sourceType as String)?.conforms(to: .png) == true
    else {
      throw PetImageValidationError.unreadableImage
    }

    guard CGImageSourceGetCount(source) == 1 else {
      throw PetImageValidationError.animatedPNG
    }

    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      width > 0,
      height > 0
    else {
      throw PetImageValidationError.unreadableImage
    }

    guard width >= minimumDimension, height >= minimumDimension else {
      throw PetImageValidationError.tooSmall(minimum: minimumDimension)
    }

    guard
      width <= safetyMaximumDimension,
      height <= safetyMaximumDimension,
      width * height <= safetyMaximumPixelCount
    else {
      throw PetImageValidationError.exceedsSafetyLimit
    }

    guard let inspectionImage = makeThumbnail(from: source, maximumDimension: 512) else {
      throw PetImageValidationError.unreadableImage
    }

    return PetImageValidationResult(
      pixelWidth: width,
      pixelHeight: height,
      hasTransparentPixels: containsTransparentPixels(inspectionImage),
      requiresOptimization: max(width, height) > optimizedMaximumDimension
    )
  }

  func makePreviewImage(_ url: URL, maximumDimension: Int = 720) throws -> CGImage {
    guard
      let source = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ),
      let image = makeThumbnail(from: source, maximumDimension: maximumDimension)
    else {
      throw PetImageValidationError.unreadableImage
    }
    return image
  }

  func makeThumbnail(from source: CGImageSource, maximumDimension: Int) -> CGImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  private func hasPNGSignature(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return false
    }
    defer { try? handle.close() }
    let signature = try? handle.read(upToCount: 8)
    return signature == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  }

  private func containsTransparentPixels(_ image: CGImage) -> Bool {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
      return false
    case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast:
      break
    @unknown default:
      return false
    }

    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
          | CGImageAlphaInfo.premultipliedFirst.rawValue
      )
    else {
      return false
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 255 }
  }
}
