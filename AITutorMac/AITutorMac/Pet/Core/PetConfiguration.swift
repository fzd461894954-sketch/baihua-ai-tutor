import CoreGraphics
import Foundation

struct PetConfiguration: Equatable, Sendable {
  let defaultSize: CGSize
  let defaultScale: CGFloat
  let minimumScale: CGFloat
  let maximumScale: CGFloat
  let scaleStep: CGFloat
  let screenMargin: CGFloat
  let minimumVisibleLength: CGFloat
  let bubbleDuration: TimeInterval

  static let `default` = PetConfiguration(
    defaultSize: CGSize(width: 180, height: 180),
    defaultScale: 1,
    minimumScale: 0.7,
    maximumScale: 1.4,
    scaleStep: 0.1,
    screenMargin: 24,
    minimumVisibleLength: 40,
    bubbleDuration: 3
  )

  func clampedScale(_ scale: CGFloat) -> CGFloat {
    min(max(scale, minimumScale), maximumScale)
  }

  func size(for scale: CGFloat) -> CGSize {
    let safeScale = clampedScale(scale)
    return CGSize(
      width: defaultSize.width * safeScale,
      height: defaultSize.height * safeScale
    )
  }

  func defaultOrigin(for size: CGSize, in visibleFrame: CGRect) -> CGPoint {
    CGPoint(
      x: visibleFrame.maxX - size.width - screenMargin,
      y: visibleFrame.minY + screenMargin
    )
  }

  func restoredOrigin(
    savedPosition: PetWindowPosition?,
    size: CGSize,
    visibleFrames: [CGRect],
    fallbackVisibleFrame: CGRect?
  ) -> CGPoint {
    if let savedPosition {
      let savedOrigin = savedPosition.point
      let savedFrame = CGRect(origin: savedOrigin, size: size)

      if visibleFrames.contains(where: { isMeaningfullyVisible(savedFrame, in: $0) }) {
        return savedOrigin
      }
    }

    guard let fallbackVisibleFrame else {
      return .zero
    }

    return defaultOrigin(for: size, in: fallbackVisibleFrame)
  }

  func clampedOrigin(_ origin: CGPoint, size: CGSize, in visibleFrame: CGRect) -> CGPoint {
    let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
    let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)

    return CGPoint(
      x: min(max(origin.x, visibleFrame.minX), maximumX),
      y: min(max(origin.y, visibleFrame.minY), maximumY)
    )
  }

  private func isMeaningfullyVisible(_ windowFrame: CGRect, in visibleFrame: CGRect) -> Bool {
    let intersection = windowFrame.intersection(visibleFrame)
    guard !intersection.isNull else {
      return false
    }

    return intersection.width >= min(minimumVisibleLength, windowFrame.width)
      && intersection.height >= min(minimumVisibleLength, windowFrame.height)
  }
}
