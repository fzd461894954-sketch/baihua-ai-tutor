import SwiftUI

#if DEBUG
struct ContextDebugView: View {
  let contextState: ContextState
  let classifier: TargetApplicationClassifier
  let accessibilitySnapshotController: AccessibilitySnapshotController

  var body: some View {
    let raw = contextState.rawFrontmostApplication
    let external = contextState.lastExternalApplication
    let classifiedApplication = contextState.userContextApplication

    Group {
      Text("Context Debug")
      Text("Raw Frontmost App: \(raw?.displayName ?? "无")")
      Text("Last External App: \(external?.displayName ?? "无")")
      Text("Bundle Identifier: \(classifiedApplication?.bundleIdentifier ?? "无")")
      Text("PID: \(classifiedApplication.map { String($0.processIdentifier) } ?? "无")")
      Text("Observed Time: \(observedTime(classifiedApplication))")
      Text("Classification: \(classifier.classify(classifiedApplication).rawValue)")
      Text(
        "Accessibility: "
          + accessibilitySnapshotController.authorizationController.permissionState.displayName
      )
    }
  }

  private func observedTime(_ application: ActiveApplicationSnapshot?) -> String {
    guard let observedAt = application?.observedAt else {
      return "无"
    }

    return observedAt.formatted(date: .omitted, time: .standard)
  }
}
#endif
