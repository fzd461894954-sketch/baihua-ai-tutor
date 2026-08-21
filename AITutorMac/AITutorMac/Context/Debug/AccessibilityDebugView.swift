import SwiftUI

struct AccessibilityDebugView: View {
  let controller: AccessibilitySnapshotController
  let liveMonitor: AccessibilityLiveMonitor
  @State private var isSemanticBufferVisible = false

  var body: some View {
    @Bindable var controller = controller
    @Bindable var liveMonitor = liveMonitor
    @Bindable var revisionPipeline = liveMonitor.contextRevisionPipeline
    @Bindable var semanticBuffer = liveMonitor.semanticBuffer

    VStack(alignment: .leading, spacing: 14) {
      Text("Accessibility Snapshot")
        .font(.title2.bold())

      permissionSection
      Divider()
      targetSection
      Divider()
      liveWatchSection
      Divider()
      contextRevisionSection(revisionPipeline)
      Divider()
      semanticBufferSection(semanticBuffer)
      Divider()
      resultSection

      if controller.authorizationController.isShowingPermissionExplanation {
        permissionExplanation
      } else {
        actionButtons
      }
    }
    .padding(20)
    .frame(minWidth: 620, minHeight: 980, alignment: .topLeading)
  }

  @ViewBuilder
  private func semanticBufferSection(_ buffer: SemanticBuffer) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Semantic Buffer Debug")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        row("State", buffer.state.rawValue)
        row("Pending Characters", String(buffer.pendingCharacterCount))
        row("Last Flush Reason", buffer.lastFlushReason?.rawValue ?? "无")
        row("Confidence", buffer.lastConfidence?.rawValue ?? "无")
        row("Chunk Count", String(buffer.chunkCount))
      }

      HStack {
        if isSemanticBufferVisible {
          Button("隐藏当前 Buffer") {
            isSemanticBufferVisible = false
          }
        } else {
          Button("查看当前 Buffer") {
            isSemanticBufferVisible = true
          }
          .disabled(buffer.pendingCharacterCount == 0)
        }
      }
      .controlSize(.small)

      if isSemanticBufferVisible {
        ScrollView {
          Text(buffer.pendingText.isEmpty ? "当前 Buffer 为空" : buffer.pendingText)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(8)
        }
        .frame(maxHeight: 120)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      } else {
        Text("正文默认隐藏；仅在主动点击后显示当前 pending buffer。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func contextRevisionSection(
    _ pipeline: ContextRevisionPipeline
  ) -> some View {
    let identity = pipeline.currentIdentity
    let revision = pipeline.latestRevision

    return VStack(alignment: .leading, spacing: 7) {
      Text("Context Revision Debug")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        row(
          "Current Identity",
          identity.map {
            "\($0.bundleIdentifier ?? "<nil>") · PID \($0.processIdentifier) · Window \($0.focusedWindowIdentity.rawValue.prefix(12)) · Session \($0.liveSessionIdentifier.uuidString.prefix(8))"
          } ?? "无"
        )
        row("Revision ID", revision.map { String($0.revisionID) } ?? "无")
        row("Change Type", revision?.changeType.rawValue ?? "无")
        row("Added Characters", revision.map { String($0.addedText.count) } ?? "0")
        row("Confidence", revision?.confidence.rawValue ?? "无")
        row("Fingerprint", revision?.fingerprint.rawValue ?? "无")
      }
      Text("本区域只显示 Revision 元数据，不默认显示正文。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var permissionSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Permission")
        .font(.headline)
      Text(controller.authorizationController.permissionState.displayName)

      if controller.authorizationController.permissionState == .notGranted,
         !controller.authorizationController.isShowingPermissionExplanation {
        Text("需要开启辅助功能权限，才能读取当前窗口文字。")
          .font(.callout)
          .foregroundStyle(.secondary)
        Button("打开系统设置") {
          controller.authorizationController.openSystemSettings()
        }
      }
    }
  }

  private var targetSection: some View {
    let target = controller.targetApplication

    return VStack(alignment: .leading, spacing: 5) {
      Text("Target App")
        .font(.headline)
      Text(target?.displayName ?? "无")
      Text("Bundle: \(target?.bundleIdentifier ?? "无")")
      Text("PID: \(target.map { String($0.processIdentifier) } ?? "无")")
    }
  }

  private var liveWatchSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Accessibility Live Watch")
        .font(.headline)
      Text("状态：\(liveMonitor.state.displayName)")
      Text("锁定目标：\(liveMonitor.lockedTarget?.displayName ?? "无")")
      Text("PID：\(liveMonitor.lockedTarget.map { String($0.processIdentifier) } ?? "无")")

      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        row("Events", String(liveMonitor.eventsReceived))
        row("Coalesced", String(liveMonitor.eventsCoalesced))
        row("Snapshots", String(liveMonitor.snapshotsGenerated))
        row("Revision", String(liveMonitor.revision))
        row(
          "Notification Counts",
          notificationCountsSummary(liveMonitor.eventCountsByNotification)
        )
        row(
          "AXIsProcessTrusted",
          controller.authorizationController.permissionState == .granted ? "true" : "false"
        )
        row(
          "ObserverCreate",
          liveMonitor.observerCreateResult.map { resultCode($0) } ?? "尚未调用"
        )
        row("Last Event", liveMonitor.lastEvent?.notificationName ?? "无")
        row(
          "Last Event At",
          liveMonitor.lastEvent.map { Self.timeFormatter.string(from: $0.observedAt) } ?? "无"
        )
        row(
          "Supported",
          notificationsSummary(liveMonitor.supportedNotifications)
        )
        row(
          "Unsupported",
          notificationsSummary(liveMonitor.unsupportedNotifications)
        )
        row(
          "Registration Results",
          registrationResultsSummary(liveMonitor.notificationRegistrationResults)
        )
      }

      if let metadata = liveMonitor.latestRevisionMetadata {
        Text(
          "最新元数据：\(metadata.characterCount) 字符 · \(metadata.nodeCount) 节点 · \(metadata.truncated ? "已截断" : "未截断") · 指纹 \(metadata.fingerprint.prefix(12))"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if let error = liveMonitor.lastError {
        Text(error.userMessage)
          .foregroundStyle(.orange)
      }

      HStack {
        Button("开始实时跟随") {
          liveMonitor.start()
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          liveMonitor.isLiveSessionActive
            || controller.authorizationController.permissionState != .granted
        )

        Button("停止实时跟随") {
          liveMonitor.stop()
        }
        .disabled(!liveMonitor.isLiveSessionActive)

        Button("查看最新 Snapshot") {
          liveMonitor.showLatestSnapshot()
        }
        .disabled(liveMonitor.latestSnapshot == nil || liveMonitor.isLatestSnapshotVisible)

        if liveMonitor.isLatestSnapshotVisible {
          Button("隐藏最新 Snapshot") {
            liveMonitor.hideLatestSnapshot()
          }
        }
      }
      .controlSize(.small)
    }
  }

  @ViewBuilder
  private var resultSection: some View {
    if controller.isReading {
      HStack {
        ProgressView()
        Text("正在读取一次当前窗口…")
      }
    } else if let error = controller.lastError {
      Text(error.userMessage)
        .foregroundStyle(.orange)
    }

    if let snapshot = controller.snapshot {
      snapshotDetails(snapshot, previewText: controller.previewText, heading: "手动读取预览")
    }

    if liveMonitor.isLatestSnapshotVisible, let snapshot = liveMonitor.latestSnapshot {
      snapshotDetails(snapshot, previewText: snapshot.preview(), heading: "实时 Snapshot（仅本次显式查看）")
    }
  }

  @ViewBuilder
  private func snapshotDetails(
    _ snapshot: AccessibleTextSnapshot,
    previewText: String,
    heading: String
  ) -> some View {
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
        row("Focused Window", snapshot.window.windowTitle ?? "无标题")
        row("Role", snapshot.window.windowRole ?? "无")
        row("Subrole", snapshot.window.windowSubrole ?? "无")
        row("Nodes", String(snapshot.nodeCount))
        row("Visited", String(snapshot.visitedNodeCount))
        row("Characters", String(snapshot.characterCount))
        row("Role Counts", roleCountsSummary(snapshot.roleCounts))
        row("Truncated", snapshot.truncated ? "Yes" : "No")
        row("Duration", String(format: "%.3fs", snapshot.duration))
      }

      Text("\(heading)（最多 3,000 字符）")
        .font(.headline)
      ScrollView {
        Text(previewText.isEmpty ? "未读到可用文字" : previewText)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(10)
      }
      .frame(minHeight: 180)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }

  private var permissionExplanation: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(AccessibilityAuthorizationController.permissionExplanation)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        Button("暂不开启") {
          controller.authorizationController.cancelPermissionRequest()
        }
        Button("继续") {
          controller.authorizationController.continuePermissionRequest()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(12)
    .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
  }

  private var actionButtons: some View {
    HStack {
      Button(
        controller.authorizationController.permissionState == .granted
          ? "读取当前窗口"
          : "允许读取当前 AI 窗口"
      ) {
        controller.requestRead()
      }
      .buttonStyle(.borderedProminent)
      .disabled(controller.isReading)

      if controller.isReading {
        Button("取消") {
          controller.cancelCurrentRead()
        }
      }

      Button("复制 Debug Snapshot") {
        controller.copyDebugSnapshot()
      }
      .disabled(controller.snapshot == nil)
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }

  private func roleCountsSummary(_ roleCounts: [String: Int]) -> String {
    let summary = roleCounts
      .sorted { lhs, rhs in
        if lhs.value == rhs.value {
          return lhs.key < rhs.key
        }
        return lhs.value > rhs.value
      }
      .prefix(8)
      .map { "\($0.key): \($0.value)" }
      .joined(separator: ", ")
    return summary.isEmpty ? "None" : summary
  }

  private func notificationsSummary(_ notifications: [String]) -> String {
    notifications.isEmpty ? "无" : notifications.joined(separator: ", ")
  }

  private func notificationCountsSummary(_ counts: [String: Int]) -> String {
    let summary = counts
      .sorted { lhs, rhs in
        if lhs.value == rhs.value {
          return lhs.key < rhs.key
        }
        return lhs.value > rhs.value
      }
      .map { "\($0.key): \($0.value)" }
      .joined(separator: ", ")
    return summary.isEmpty ? "无" : summary
  }

  private func registrationResultsSummary(
    _ results: [AXNotificationRegistrationResult]
  ) -> String {
    guard !results.isEmpty else {
      return "无"
    }
    return results
      .map { "\($0.notificationName): \(resultCode($0.errorCode))" }
      .joined(separator: ", ")
  }

  private func resultCode(_ code: Int32) -> String {
    code == 0 ? "success (0)" : "failed (\(code))"
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()
}
