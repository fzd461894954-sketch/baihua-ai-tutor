import SwiftUI

struct BubbleChrome<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isPresented = false

  private let alignment: Alignment
  private let content: Content

  init(
    alignment: Alignment = .topLeading,
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.content = content()
  }

  var body: some View {
    content
      .padding(.horizontal, AppSpacing.md)
      .padding(.vertical, AppSpacing.sm)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
      .background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: AppRadius.bubble, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: AppRadius.bubble, style: .continuous)
          .stroke(.primary.opacity(0.08), lineWidth: 1)
      }
      .shadow(
        color: AppShadow.bubble.color,
        radius: AppShadow.bubble.radius,
        y: AppShadow.bubble.y
      )
      .opacity(isPresented ? 1 : 0)
      .offset(y: reduceMotion || isPresented ? 0 : AppSpacing.xs)
      .transition(bubbleTransition)
      .transaction { transaction in
        if reduceMotion {
          transaction.animation = nil
        }
      }
      .onAppear {
        if reduceMotion {
          isPresented = true
        } else {
          withAnimation(.easeInOut(duration: AppMotion.bubble)) {
            isPresented = true
          }
        }
      }
      .onChange(of: reduceMotion) { _, shouldReduceMotion in
        if shouldReduceMotion {
          isPresented = true
        }
      }
  }

  private var bubbleTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .asymmetric(
        insertion: .opacity.combined(with: .offset(y: AppSpacing.xs)),
        removal: .opacity
      )
  }
}

#if DEBUG
private struct BubbleChromePreviewMatrix: View {
  var body: some View {
    VStack(spacing: AppSpacing.md) {
      previewBubble(title: "你好，我是花花老师。", detail: "点一下我，就能看解释或直接提问。")
      previewBubble(title: "解释已经准备好了", detail: "点按查看这次教学解释。")
      previewBubble(title: "正在听…", detail: "说完后点一下“结束并提问”。")
    }
    .frame(width: 320)
    .padding()
  }

  private func previewBubble(title: String, detail: String) -> some View {
    BubbleChrome {
      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(title).font(AppTypography.bubbleTitle)
        Text(detail).font(AppTypography.bubbleBody).foregroundStyle(.secondary)
      }
    }
  }
}

#Preview("Bubble · Pet / Tutor / Voice · Light") {
  BubbleChromePreviewMatrix()
}

#Preview("Bubble · Pet / Tutor / Voice · Dark") {
  BubbleChromePreviewMatrix()
    .preferredColorScheme(.dark)
}
#endif
