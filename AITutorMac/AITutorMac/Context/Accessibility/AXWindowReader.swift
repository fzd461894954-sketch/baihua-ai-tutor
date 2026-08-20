import Foundation

struct AXWindowReader {
  func readWindow(
    application: AccessibleApplicationSnapshot,
    element: any AXElementReading
  ) throws -> AccessibleWindowSnapshot {
    AccessibleWindowSnapshot(
      application: application,
      windowTitle: try element.stringValue(for: .title),
      windowRole: try element.stringValue(for: .role),
      windowSubrole: try element.stringValue(for: .subrole),
      observedAt: Date(),
      source: .accessibility
    )
  }
}
