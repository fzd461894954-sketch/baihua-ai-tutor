import Foundation

enum ApplicationCategory: String, Equatable, Sendable {
  case chatGPT
  case codex
  case browser
  case xcode
  case other
}

struct TargetApplicationClassifier {
  private let categoriesByBundleIdentifier: [String: ApplicationCategory]

  init(
    categoriesByBundleIdentifier: [String: ApplicationCategory] = [
      "com.openai.codex": .codex,
      "com.apple.Safari": .browser,
      "com.google.Chrome": .browser,
      "com.apple.dt.Xcode": .xcode,
    ]
  ) {
    self.categoriesByBundleIdentifier = categoriesByBundleIdentifier
  }

  func classify(_ application: ActiveApplicationSnapshot?) -> ApplicationCategory {
    guard let bundleIdentifier = application?.bundleIdentifier else {
      return .other
    }

    return categoriesByBundleIdentifier[bundleIdentifier] ?? .other
  }
}
