import Foundation

enum PetNameValidator {
  static let maximumLength = 40

  static func normalized(_ value: String, fallback: String = "我的老师") -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = trimmed.isEmpty ? fallback : trimmed
    return String(candidate.prefix(maximumLength))
  }

  static func suggestedName(for fileURL: URL) -> String {
    normalized(fileURL.deletingPathExtension().lastPathComponent)
  }

  static func isValid(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && value.count <= maximumLength
  }
}
