import SwiftUI

enum TutorPanelLayoutPolicy {
  static let glossaryStartsExpanded = false
}

struct FloatingPanelView: View {
  let contentStore: TutorPanelContentStore
  let actionHandler: TutorPanelActionHandler

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        Group {
          switch contentStore.state {
          case let .empty(availability): emptyContent(availability)
          case .loading: loadingContent
          case let .presentation(presentation): presentationContent(presentation)
          case let .error(error): errorContent(error)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
      }
#if DEBUG
      Divider()
      debugFixturePicker.padding(.horizontal, 16).padding(.vertical, 10)
#endif
    }
    .frame(minWidth: 360, minHeight: 480)
    .background(.ultraThinMaterial)
  }

  private func emptyContent(_ availability: TutorPanelActionAvailability) -> some View {
    VStack(alignment: .leading, spacing: 24) {
      tutorHeader("花花老师", subtitle: "AI 实时教学伴侣")
      VStack(alignment: .leading, spacing: 10) {
        Text("我可以把 AI 的复杂内容，\n用更容易理解的方式讲给你听。")
          .foregroundStyle(.secondary).textSelection(.enabled)
        if let message = availability.unavailableMessage {
          Label(message, systemImage: "info.circle")
            .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
        }
      }
      Button("解释当前内容") { actionHandler.handle(.explainCurrentContent) }
        .buttonStyle(.borderedProminent).disabled(!availability.isAvailable)
      if availability.isAvailable {
        Label("解释内容会发送给当前配置的 AI 模型服务。", systemImage: "lock.shield")
          .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
    }
  }

  private var loadingContent: some View {
    VStack(alignment: .leading, spacing: 28) {
      tutorHeader("花花老师", subtitle: "正在理解当前内容……")
      HStack(spacing: 12) {
        ProgressView().controlSize(.small)
        Text("正在组织一个好懂的解释。")
          .foregroundStyle(.secondary).textSelection(.enabled)
      }
      Button("取消") { actionHandler.handle(.dismissCurrentPresentation) }
    }
  }

  @ViewBuilder private func presentationContent(_ value: TutorPresentationModel) -> some View {
    switch value.outcome {
    case .lesson:
      TutorLessonView(presentation: value, actionHandler: actionHandler)
        .id(value.responseMetadata.responseID)
    case .needsMoreContext:
      statusContent(value, icon: "text.badge.plus", tint: .blue,
                    actionTitle: "重新解释当前内容", action: .retryCurrentContent)
    case .blocked:
      statusContent(value, icon: blockedIcon(value.blockReason), tint: .orange,
                    actionTitle: "知道了", action: .dismissCurrentPresentation)
    }
  }

  private func statusContent(
    _ value: TutorPresentationModel, icon: String, tint: Color,
    actionTitle: String, action: TutorPanelActionIntent
  ) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      tutorHeader("花花老师", subtitle: "当前内容")
      Label { Text(value.title).font(.title3.weight(.semibold)) }
        icon: { Image(systemName: icon).foregroundStyle(tint) }
      Text(value.plainExplanation).lineSpacing(4).textSelection(.enabled)
      if let suggestion = value.suggestedAction {
        TutorPanelCard(title: "可以这样做", icon: "arrow.right.circle") {
          Text(suggestion).textSelection(.enabled)
        }
      }
      Button(actionTitle) { actionHandler.handle(action) }.buttonStyle(.borderedProminent)
    }
  }

  private func errorContent(_ error: TutorPanelErrorPresentation) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      tutorHeader("花花老师", subtitle: "解释遇到问题")
      Label { Text(error.title).font(.title3.weight(.semibold)) }
        icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.red) }
      Text(error.message).foregroundStyle(.secondary).textSelection(.enabled)
      HStack(spacing: 10) {
        Button("重新解释") { actionHandler.handle(.retryCurrentContent) }
          .buttonStyle(.borderedProminent)
        Button("稍后再说") { actionHandler.handle(.dismissCurrentPresentation) }
      }
    }
  }

  private func tutorHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.title2.bold())
      Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
    }
  }

  private func blockedIcon(_ reason: TutorBlockReason?) -> String {
    switch reason {
    case .privacyRisk: return "hand.raised.fill"
    case .unsafeInstruction: return "shield.fill"
    case .invalidInput, .unsupported, .none: return "exclamationmark.shield.fill"
    }
  }

#if DEBUG
  private var debugFixturePicker: some View {
    HStack {
      Text("DEBUG 状态").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Spacer()
      Menu("切换案例") {
        ForEach(TutorPanelDebugFixture.allCases) { fixture in
          Button(fixture.displayName) { actionHandler.handle(.showDebugFixture(fixture)) }
        }
      }.menuStyle(.borderlessButton).fixedSize()
    }
  }
#endif
}

private struct TutorLessonView: View {
  let presentation: TutorPresentationModel
  let actionHandler: TutorPanelActionHandler
  @State private var isGlossaryExpanded = TutorPanelLayoutPolicy.glossaryStartsExpanded

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 6) {
        Text("花花老师").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        Text(presentation.title).font(.title2.bold()).textSelection(.enabled)
      }
      Text(presentation.plainExplanation).lineSpacing(5).textSelection(.enabled)

      if !presentation.keyPoints.isEmpty {
        section("记住这几点") {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(presentation.keyPoints.enumerated()), id: \.offset) { index, point in
              HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                  .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
                Text(point).textSelection(.enabled)
              }
            }
          }
        }
      }
      if let analogy = presentation.analogy {
        TutorPanelCard(title: "打个比方", icon: "lightbulb") {
          Text(analogy).textSelection(.enabled)
        }
      }
      if let example = presentation.example {
        TutorPanelCard(title: "举个例子", icon: "sparkles") {
          Text(example).textSelection(.enabled)
        }
      }
      if !presentation.terms.isEmpty {
        DisclosureGroup(isExpanded: $isGlossaryExpanded) {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(presentation.terms.enumerated()), id: \.offset) { _, term in
              VStack(alignment: .leading, spacing: 3) {
                Text(term.term).font(.subheadline.weight(.semibold)).textSelection(.enabled)
                Text(term.plainDefinition).foregroundStyle(.secondary).textSelection(.enabled)
              }
            }
          }.padding(.top, 10)
        } label: {
          Label("查看术语（\(presentation.terms.count)）", systemImage: "character.book.closed")
            .font(.headline)
        }
      }
      if !presentation.caveats.isEmpty {
        TutorPanelCard(title: "小提醒", icon: "exclamationmark.circle", tint: .orange) {
          VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(presentation.caveats.enumerated()), id: \.offset) { _, value in
              Text("• \(value)").textSelection(.enabled)
            }
          }
        }
      }
      if let question = presentation.checkQuestion {
        TutorPanelCard(title: "想一想", icon: "questionmark.bubble") {
          Text(question).fontWeight(.medium).textSelection(.enabled)
        }
      }
      if presentation.didTruncateContent {
        Label("内容已适当精简，保留了主要信息。", systemImage: "text.badge.minus")
          .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
      }
      Button("结束本次解释") { actionHandler.handle(.dismissCurrentPresentation) }
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.headline)
      content()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct TutorPanelCard<Content: View>: View {
  let title: String
  let icon: String
  let tint: Color
  let content: Content

  init(title: String, icon: String, tint: Color = .accentColor,
       @ViewBuilder content: () -> Content) {
    self.title = title; self.icon = icon; self.tint = tint; self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label(title, systemImage: icon).font(.headline).foregroundStyle(tint)
      content.lineSpacing(3)
    }
    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.7)))
  }
}

#if DEBUG
#Preview("Lesson") {
  let store = TutorPanelContentStore(availability: .available)
  store.present(TutorPanelPresentationFixtures.apiLesson)
  return FloatingPanelView(contentStore: store, actionHandler: .unavailable)
    .frame(width: 400, height: 600)
}
#endif
