import CoreGraphics
import Foundation

struct PetWindowPosition: Codable, Equatable, Sendable {
  let x: CGFloat
  let y: CGFloat

  init(x: CGFloat, y: CGFloat) {
    self.x = x
    self.y = y
  }

  init(point: CGPoint) {
    self.init(x: point.x, y: point.y)
  }

  var point: CGPoint {
    CGPoint(x: x, y: y)
  }
}

final class PetStore {
  private enum Key {
    static let position = "PetWindowPosition"
    static let scale = "PetScale"
    static let visible = "PetVisible"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func loadPosition() -> PetWindowPosition? {
    guard
      let value = defaults.dictionary(forKey: Key.position),
      let x = value["x"] as? NSNumber,
      let y = value["y"] as? NSNumber,
      x.doubleValue.isFinite,
      y.doubleValue.isFinite
    else {
      return nil
    }

    return PetWindowPosition(
      x: CGFloat(x.doubleValue),
      y: CGFloat(y.doubleValue)
    )
  }

  func savePosition(_ position: PetWindowPosition) {
    defaults.set(
      ["x": Double(position.x), "y": Double(position.y)],
      forKey: Key.position
    )
  }

  func loadScale(default defaultScale: CGFloat) -> CGFloat {
    guard let value = defaults.object(forKey: Key.scale) as? NSNumber else {
      return defaultScale
    }

    let scale = value.doubleValue
    return scale.isFinite ? CGFloat(scale) : defaultScale
  }

  func saveScale(_ scale: CGFloat) {
    defaults.set(Double(scale), forKey: Key.scale)
  }

  func loadVisibility(default defaultVisibility: Bool = true) -> Bool {
    guard defaults.object(forKey: Key.visible) != nil else {
      return defaultVisibility
    }

    return defaults.bool(forKey: Key.visible)
  }

  func saveVisibility(_ isVisible: Bool) {
    defaults.set(isVisible, forKey: Key.visible)
  }
}
