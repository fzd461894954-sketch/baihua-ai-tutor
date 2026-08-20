import SwiftUI

struct FloatingPanelView: View {
  let showAccessibilityDebug: () -> Void

  init(showAccessibilityDebug: @escaping () -> Void = {}) {
    self.showAccessibilityDebug = showAccessibilityDebug
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      header
      status

      Divider()

      teachingSection(
        title: "AI 正在做什么",
        placeholder: "等待 AI 内容……"
      )

      Divider()

      teachingSection(
        title: "为什么这样做",
        placeholder: "等待解释……"
      )

      Divider()

      teachingSection(
        title: "你需要做什么",
        placeholder: "暂时无需操作。"
      )

      Spacer(minLength: 0)
#if DEBUG
      Button("Context Debug · Accessibility…", action: showAccessibilityDebug)
#endif
      disabledTeachingActions
    }
    .padding(24)
    .frame(minWidth: 360, minHeight: 480)
    .background(.ultraThinMaterial)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("白话 AI")
        .font(.title2.bold())
      Text("AI 实时教学伴侣")
        .font(.headline)
        .foregroundStyle(.secondary)
      Text("这里以后会把 AI 的复杂回答，\n翻译成你能理解的大白话。")
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var status: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(.green)
        .frame(width: 8, height: 8)
      Text("状态")
        .font(.subheadline.weight(.semibold))
      Text("准备就绪")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  private func teachingSection(title: String, placeholder: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      Text(placeholder)
        .font(.body)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var disabledTeachingActions: some View {
    HStack(spacing: 8) {
      Button("我还是没懂") {}
        .disabled(true)
      Button("举个例子") {}
        .disabled(true)
      Button("讲深一点") {}
        .disabled(true)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }
}

#Preview {
  FloatingPanelView()
    .frame(width: 400, height: 600)
}
