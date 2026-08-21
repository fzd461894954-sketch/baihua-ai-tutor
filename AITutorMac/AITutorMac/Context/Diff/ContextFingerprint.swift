import CryptoKit
import Foundation

struct ContextFingerprint: Equatable, Hashable, Sendable {
  let rawValue: String
}

struct ContextFingerprinter: Sendable {
  func fingerprint(_ text: NormalizedContextText) -> ContextFingerprint {
    let versionedText = "context-normalization-v\(NormalizedContextText.normalizationVersion)\u{0}\(text.comparisonText)"
    let digest = SHA256.hash(data: Data(versionedText.utf8))
    return ContextFingerprint(
      rawValue: digest.map { String(format: "%02x", $0) }.joined()
    )
  }
}
