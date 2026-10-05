import Darwin
import Observation

@MainActor
@Observable
final class ContextState {
  private(set) var rawFrontmostApplication: ActiveApplicationSnapshot?
  private(set) var lastExternalApplication: ActiveApplicationSnapshot?

  var userContextApplication: ActiveApplicationSnapshot? {
    lastExternalApplication ?? rawFrontmostApplication
  }

  func recordActivation(
    _ application: ActiveApplicationSnapshot,
    isSelfApplication: Bool
  ) {
    rawFrontmostApplication = application

    if !isSelfApplication {
      lastExternalApplication = application
    }
  }

  func removeTerminatedApplication(processIdentifier: pid_t) {
    if rawFrontmostApplication?.processIdentifier == processIdentifier {
      rawFrontmostApplication = nil
    }

    if lastExternalApplication?.processIdentifier == processIdentifier {
      lastExternalApplication = nil
    }
  }
}
