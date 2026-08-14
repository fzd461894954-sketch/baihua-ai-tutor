import Darwin
import Foundation

struct ActiveApplicationSnapshot: Equatable, Sendable {
  let localizedName: String?
  let bundleIdentifier: String?
  let processIdentifier: pid_t
  let observedAt: Date

  var displayName: String {
    localizedName ?? bundleIdentifier ?? "未知应用"
  }
}
