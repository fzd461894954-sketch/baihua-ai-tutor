import CryptoKit
import Darwin
import Foundation

struct FocusedWindowIdentity: Equatable, Hashable, Sendable {
  let rawValue: String
}

struct ContextIdentity: Equatable, Hashable, Sendable {
  let bundleIdentifier: String?
  let processIdentifier: pid_t
  let focusedWindowIdentity: FocusedWindowIdentity
  let liveSessionIdentifier: UUID
}

/// Builds a privacy-safe identity from metadata already present in the
/// Accessibility snapshot. No new AX attributes are requested.
struct ContextIdentityFactory: Sendable {
  func makeIdentity(
    snapshot: AccessibleTextSnapshot,
    liveSessionIdentifier: UUID
  ) -> ContextIdentity {
    let window = snapshot.window
    let descriptor = [
      "focused-window-v1",
      normalizeMetadata(window.windowTitle),
      normalizeMetadata(window.windowRole),
      normalizeMetadata(window.windowSubrole),
    ].joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(descriptor.utf8))
    let windowIdentity = FocusedWindowIdentity(
      rawValue: digest.map { String(format: "%02x", $0) }.joined()
    )

    return ContextIdentity(
      bundleIdentifier: window.application.bundleIdentifier,
      processIdentifier: window.application.processIdentifier,
      focusedWindowIdentity: windowIdentity,
      liveSessionIdentifier: liveSessionIdentifier
    )
  }

  private func normalizeMetadata(_ value: String?) -> String {
    guard let value else {
      return "<nil>"
    }
    return value
      .precomposedStringWithCanonicalMapping
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }
}
