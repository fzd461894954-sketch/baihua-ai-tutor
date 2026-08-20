import SwiftUI

struct AccessibilityDebugView: View {
  let controller: AccessibilitySnapshotController

  var body: some View {
    @Bindable var controller = controller

    VStack(alignment: .leading, spacing: 14) {
      Text("Accessibility Snapshot")
        .font(.title2.bold())

      permissionSection
      Divider()
      targetSection
      Divider()
      resultSection

      if controller.authorizationController.isShowingPermissionExplanation {
        permissionExplanation
      } else {
        actionButtons
      }
    }
    .padding(20)
    .frame(minWidth: 540, minHeight: 600, alignment: .topLeading)
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

      Text("预览（最多 3,000 字符）")
        .font(.headline)
      ScrollView {
        Text(controller.previewText.isEmpty ? "未读到可用文字" : controller.previewText)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(10)
      }
      .frame(minHeight: 180)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
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
}
