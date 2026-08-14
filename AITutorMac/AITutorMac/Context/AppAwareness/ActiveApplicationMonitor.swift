import AppKit
import Foundation

@MainActor
final class ApplicationWorkspaceObservation {
  private var cancellation: (() -> Void)?

  init(cancellation: @escaping () -> Void) {
    self.cancellation = cancellation
  }

  func cancel() {
    cancellation?()
    cancellation = nil
  }

  deinit {
    cancellation?()
  }
}

@MainActor
protocol ApplicationWorkspaceProviding: AnyObject {
  var frontmostApplication: ActiveApplicationSnapshot? { get }

  func observeApplicationActivations(
    _ handler: @escaping (ActiveApplicationSnapshot) -> Void
  ) -> ApplicationWorkspaceObservation

  func observeApplicationTerminations(
    _ handler: @escaping (ActiveApplicationSnapshot) -> Void
  ) -> ApplicationWorkspaceObservation
}

@MainActor
final class SystemApplicationWorkspace: ApplicationWorkspaceProviding {
  private let workspace: NSWorkspace
  private let notificationCenter: NotificationCenter

  init(workspace: NSWorkspace = .shared) {
    self.workspace = workspace
    notificationCenter = workspace.notificationCenter
  }

  var frontmostApplication: ActiveApplicationSnapshot? {
    guard let application = workspace.frontmostApplication else {
      return nil
    }

    return Self.makeSnapshot(application)
  }

  func observeApplicationActivations(
    _ handler: @escaping (ActiveApplicationSnapshot) -> Void
  ) -> ApplicationWorkspaceObservation {
    observe(NSWorkspace.didActivateApplicationNotification, handler: handler)
  }

  func observeApplicationTerminations(
    _ handler: @escaping (ActiveApplicationSnapshot) -> Void
  ) -> ApplicationWorkspaceObservation {
    observe(NSWorkspace.didTerminateApplicationNotification, handler: handler)
  }

  private func observe(
    _ name: Notification.Name,
    handler: @escaping (ActiveApplicationSnapshot) -> Void
  ) -> ApplicationWorkspaceObservation {
    let token = notificationCenter.addObserver(
      forName: name,
      object: nil,
      queue: .main
    ) { notification in
      guard
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication
      else {
        return
      }

      handler(Self.makeSnapshot(application))
    }

    return ApplicationWorkspaceObservation { [notificationCenter] in
      notificationCenter.removeObserver(token)
    }
  }

  nonisolated private static func makeSnapshot(
    _ application: NSRunningApplication
  ) -> ActiveApplicationSnapshot {
    ActiveApplicationSnapshot(
      localizedName: application.localizedName,
      bundleIdentifier: application.bundleIdentifier,
      processIdentifier: application.processIdentifier,
      observedAt: Date()
    )
  }
}

@MainActor
final class ActiveApplicationMonitor {
  private let contextState: ContextState
  private let workspace: ApplicationWorkspaceProviding
  private let selfBundleIdentifier: () -> String?
  private var observations: [ApplicationWorkspaceObservation] = []

  private(set) var isMonitoring = false

  var currentApplication: ActiveApplicationSnapshot? {
    contextState.rawFrontmostApplication
  }

  var lastExternalApplication: ActiveApplicationSnapshot? {
    contextState.lastExternalApplication
  }

  init(
    contextState: ContextState,
    workspace: ApplicationWorkspaceProviding? = nil,
    selfBundleIdentifier: @escaping () -> String? = { Bundle.main.bundleIdentifier }
  ) {
    self.contextState = contextState
    self.workspace = workspace ?? SystemApplicationWorkspace()
    self.selfBundleIdentifier = selfBundleIdentifier
  }

  func start() {
    guard !isMonitoring else {
      return
    }

    isMonitoring = true
    observations = [
      workspace.observeApplicationActivations { [weak self] application in
        self?.recordActivation(application)
      },
      workspace.observeApplicationTerminations { [weak self] application in
        self?.recordTermination(application)
      },
    ]

    if let application = workspace.frontmostApplication {
      recordActivation(application)
    }
  }

  func stop() {
    guard isMonitoring else {
      return
    }

    observations.forEach { $0.cancel() }
    observations.removeAll()
    isMonitoring = false
  }

  private func recordActivation(_ application: ActiveApplicationSnapshot) {
    let isSelfApplication = application.bundleIdentifier == selfBundleIdentifier()
    contextState.recordActivation(application, isSelfApplication: isSelfApplication)

    let bundleIdentifier = application.bundleIdentifier ?? "<unknown>"
    AppLogger.context.info("Active app changed: \(bundleIdentifier, privacy: .public)")
  }

  private func recordTermination(_ application: ActiveApplicationSnapshot) {
    contextState.removeTerminatedApplication(
      processIdentifier: application.processIdentifier
    )
  }
}
