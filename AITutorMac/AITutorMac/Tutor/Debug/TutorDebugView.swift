#if DEBUG
import SwiftUI

struct TutorDebugView: View {
  let coordinator: TutorCoordinator

  @State private var isChunkBodyVisible = false
  @State private var isRequestBodyVisible = false
  @State private var isPromptBodyVisible = false
  @State private var isResponseBodyVisible = false

  var body: some View {
    @Bindable var coordinator = coordinator

    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Tutor Coordinator · Fake Flow")
          .font(.title2.bold())

        sessionSection
        Divider()
        semanticChunkSection
        Divider()
        requestSection
        Divider()
        promptSection
        Divider()
        providerSection
        Divider()
        responseSection
        Divider()
        interactionSection
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: 680, minHeight: 760)
    .onChange(of: coordinator.latestChunk?.id) {
      isChunkBodyVisible = false
    }
    .onChange(of: coordinator.latestRequest?.id) {
      isRequestBodyVisible = false
      isPromptBodyVisible = false
    }
    .onChange(of: coordinator.latestPresentation?.responseMetadata.responseID) {
      isResponseBodyVisible = false
    }
  }

  private var sessionSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Tutor Session")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        row("Coordinator", coordinator.state.rawValue)
        row("Session", shortID(coordinator.currentSessionID))
        row("Received Chunks", String(coordinator.receivedChunkCount))
        row("Duplicate Chunks", String(coordinator.duplicateChunkCount))
        row("Requests", String(coordinator.requestCount))
      }

      HStack {
        Button("启动 Session") {
          coordinator.start()
        }
        .disabled(coordinator.isSessionActive)

        Button("重置 Session") {
          hideAllBodies()
          coordinator.resetSession()
        }

        Button("取消当前请求") {
          coordinator.cancelCurrentRequest()
        }
        .disabled(coordinator.activeExecutionContext == nil)

        Button("停止并清理") {
          hideAllBodies()
          coordinator.stop()
        }
        .disabled(!coordinator.isSessionActive)
      }
      .controlSize(.small)
    }
  }

  private var semanticChunkSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Latest SemanticChunk Metadata")
        .font(.headline)
      if let chunk = coordinator.latestChunk {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
          row("Chunk ID", shortID(chunk.id))
          row("Revision ID", String(chunk.sourceRevisionID))
          row("Characters", String(chunk.text.count))
          row("Confidence", chunk.confidence.rawValue)
          row("Flush Reason", chunk.flushReason.rawValue)
          row("Created At", Self.timeFormatter.string(from: chunk.createdAt))
          row("Admission", admissionText(coordinator.latestChunkAdmission))
        }

        bodyButton(
          isVisible: $isChunkBodyVisible,
          showTitle: "查看 Chunk 正文",
          hideTitle: "隐藏 Chunk 正文"
        )
        if isChunkBodyVisible {
          bodyBox(chunk.text)
        } else {
          hiddenBodyHint
        }
      } else {
        Text("尚未收到 SemanticChunk。")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var requestSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("TutorRequest State")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        row("State", requestStateText(coordinator.requestState))
        if let request = coordinator.latestRequest {
          row("Request ID", shortID(request.id))
          row("Session", shortID(request.sessionID))
          row("Sequence", String(request.sequence))
          row("Task", request.task.rawValue)
          row("Trigger", request.trigger.rawValue)
          row("Completeness", request.source.completeness.rawValue)
          row("Learner Level", request.learner.level.rawValue)
          row("Created At", Self.timeFormatter.string(from: request.createdAt))
        }
      }

      if let request = coordinator.latestRequest {
        bodyButton(
          isVisible: $isRequestBodyVisible,
          showTitle: "查看 Request 正文",
          hideTitle: "隐藏 Request 正文"
        )
        if isRequestBodyVisible {
          bodyBox(request.source.text)
        } else {
          hiddenBodyHint
        }
      }
    }
  }

  private var providerSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Provider State")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        row("Provider", "FakeLLMProvider · Debug only")
        row("State", providerStateText(coordinator.providerState))
        if let context = coordinator.activeExecutionContext {
          row("Active Request", shortID(context.requestID))
          row("Sequence", String(context.sequence))
          row("Started At", Self.timeFormatter.string(from: context.startedAt))
        }
        row("Last Error", coordinator.lastError.map(errorText) ?? "无")
      }
      Text("本地确定性 Fake；无网络、无凭据、无 Provider SDK。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var promptSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Fake Prompt Preview")
        .font(.headline)
      if
        let request = coordinator.latestRequest,
        let package = coordinator.latestPromptPackage
      {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
          row("Rules Version", PromptRules.currentVersion)
          row("Request Schema", String(request.schemaVersion))
          row("Response Schema", String(TutorResponse.currentSchemaVersion))
          row("Learner Level", request.learner.level.rawValue)
          row("Language", request.output.language)
          row("Detail Level", request.output.detailLevel.rawValue)
          row("Source Characters", String(request.source.text.count))
          row("System Characters", String(package.systemInstruction.count))
          row("User Characters", String(package.userContent.count))
          row("Schema Characters", String(package.outputSchema.count))
          row("Constraints", String(package.constraints.count))
          row("Dispatch", "none · local preview only")
        }

        bodyButton(
          isVisible: $isPromptBodyVisible,
          showTitle: "查看 Prompt 正文",
          hideTitle: "隐藏 Prompt 正文"
        )
        if isPromptBodyVisible {
          bodyBox(promptBody(package))
        } else {
          hiddenBodyHint
        }
      } else {
        Text("尚未生成 PromptPackage。")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var responseSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("TutorResponse Outcome")
        .font(.headline)
      if let presentation = coordinator.latestPresentation {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
          row("Response ID", shortID(presentation.responseMetadata.responseID))
          row("Request ID", shortID(presentation.responseMetadata.requestID))
          row("Session", shortID(presentation.responseMetadata.sessionID))
          row("Sequence", String(presentation.responseMetadata.sequence))
          row("Outcome", presentation.outcome.rawValue)
          row(
            "Created At",
            Self.timeFormatter.string(from: presentation.responseMetadata.createdAt)
          )
          row("Presentation Truncated", presentation.didTruncateContent ? "yes" : "no")
        }

        Text("Lesson Metadata")
          .font(.subheadline.weight(.semibold))
          .padding(.top, 3)
        if let metadata = presentation.lessonMetadata {
          Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            row("Confidence", metadata.confidence.rawValue)
            row("Key Points", String(metadata.keyPointCount))
            row("Terms", String(metadata.termCount))
            row("Caveats", String(metadata.caveatCount))
            row("Has Analogy", metadata.hasAnalogy ? "yes" : "no")
            row("Has Example", metadata.hasExample ? "yes" : "no")
            row("Has Check Question", metadata.hasCheckQuestion ? "yes" : "no")
          }
        } else {
          Text("当前 outcome 不是 lesson。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text("Presentation Sections")
          .font(.subheadline.weight(.semibold))
          .padding(.top, 3)
        bodyButton(
          isVisible: $isResponseBodyVisible,
          showTitle: "查看 Presentation 正文",
          hideTitle: "隐藏 Presentation 正文"
        )
        if isResponseBodyVisible {
          bodyBox(presentationBody(presentation))
        } else {
          hiddenBodyHint
        }
      } else {
        Text("尚无 TutorResponse。")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var interactionSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Tutor Interaction Policy")
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
        if let decision = coordinator.latestInteractionDecision {
          row("Policy Decision", decision.action.rawValue)
          row("Priority", interactionPriorityText(decision.priority))
          row("Decision Reason", decision.reason.rawValue)
        } else {
          row("Policy Decision", "尚无决策")
        }

        if let input = coordinator.latestInteractionInput {
          row("Topic Type", input.topicType?.rawValue ?? "unknown")
          row("Confidence", input.confidence?.rawValue ?? "无")
          row("Flush Reason", input.flushReason.rawValue)
          row("Source Characters", String(input.textLength))
        }

        row("Queue Count", String(coordinator.displayQueue.queueCount))
        row("Duplicate Merges", String(coordinator.displayQueue.duplicateMergeCount))
      }

      Text("Current Display Item")
        .font(.subheadline.weight(.semibold))
        .padding(.top, 3)
      if let item = coordinator.displayQueue.currentDisplayItem {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
          row("Response ID", shortID(item.id))
          row("Source Chunk", shortID(item.sourceChunkID))
          row("Outcome", item.presentation.outcome.rawValue)
          row("Priority", interactionPriorityText(item.decision.priority))
        }
      } else {
        Text("当前没有展示项。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }

  private func bodyButton(
    isVisible: Binding<Bool>,
    showTitle: String,
    hideTitle: String
  ) -> some View {
    Button(isVisible.wrappedValue ? hideTitle : showTitle) {
      isVisible.wrappedValue.toggle()
    }
    .controlSize(.small)
  }

  private func bodyBox(_ text: String) -> some View {
    ScrollView {
      Text(text)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(8)
    }
    .frame(maxHeight: 180)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }

  private var hiddenBodyHint: some View {
    Text("正文默认隐藏；仅在主动点击后显示当前最新值。")
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  private func admissionText(_ admission: TutorChunkAdmission?) -> String {
    switch admission {
    case let .accepted(trigger):
      return "accepted · \(trigger.rawValue)"
    case let .skipped(reason):
      return "skipped · \(reason.rawValue)"
    case nil:
      return "无"
    }
  }

  private func requestStateText(_ state: TutorRequestState) -> String {
    switch state {
    case .idle:
      return "idle"
    case let .running(requestID, sequence):
      return "running · \(shortID(requestID)) · #\(sequence)"
    case let .succeeded(requestID, sequence):
      return "succeeded · \(shortID(requestID)) · #\(sequence)"
    case let .failed(requestID, error):
      return "failed · \(shortID(requestID)) · \(errorText(error))"
    case let .cancelled(requestID):
      return "cancelled · \(shortID(requestID))"
    }
  }

  private func providerStateText(_ state: TutorProviderState) -> String {
    switch state {
    case .idle:
      return "idle"
    case let .running(requestID):
      return "running · \(shortID(requestID))"
    case let .succeeded(responseID):
      return "succeeded · \(shortID(responseID))"
    case let .failed(error):
      return "failed · \(errorText(error))"
    case let .cancelled(requestID):
      return "cancelled · \(shortID(requestID))"
    }
  }

  private func interactionPriorityText(_ priority: TutorInteractionPriority) -> String {
    switch priority {
    case .high:
      return "high"
    case .normal:
      return "normal"
    case .low:
      return "low"
    }
  }

  private func presentationBody(_ presentation: TutorPresentationModel) -> String {
    var sections = ["标题\n\(presentation.title)"]
    sections.append("大白话解释\n\(presentation.plainExplanation)")
    if !presentation.keyPoints.isEmpty {
      sections.append(
        "关键点\n" + presentation.keyPoints.map { "• \($0)" }.joined(separator: "\n")
      )
    }
    if !presentation.terms.isEmpty {
      sections.append(
        "术语\n" + presentation.terms
          .map { "\($0.term)：\($0.plainDefinition)" }
          .joined(separator: "\n")
      )
    }
    if let analogy = presentation.analogy {
      sections.append("类比\n\(analogy)")
    }
    if let example = presentation.example {
      sections.append("示例\n\(example)")
    }
    if let checkQuestion = presentation.checkQuestion {
      sections.append("检查问题\n\(checkQuestion)")
    }
    if !presentation.caveats.isEmpty {
      sections.append("注意事项\n" + presentation.caveats.joined(separator: "\n"))
    }
    if let suggestedAction = presentation.suggestedAction {
      sections.append("建议下一步\n\(suggestedAction)")
    }
    if let blockReason = presentation.blockReason {
      sections.append("阻止原因\n\(blockReason.rawValue)")
    }
    return sections.joined(separator: "\n\n")
  }

  private func promptBody(_ package: PromptPackage) -> String {
    """
    SYSTEM INSTRUCTION
    \(package.systemInstruction)

    CONSTRAINTS
    \(package.constraints.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

    USER CONTENT
    \(package.userContent)

    OUTPUT SCHEMA
    \(package.outputSchema)
    """
  }

  private func errorText(_ error: TutorEngineError) -> String {
    String(describing: error)
  }

  private func shortID(_ id: UUID?) -> String {
    id.map { String($0.uuidString.prefix(8)) } ?? "无"
  }

  private func hideAllBodies() {
    isChunkBodyVisible = false
    isRequestBodyVisible = false
    isPromptBodyVisible = false
    isResponseBodyVisible = false
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()
}
#endif
