#if DEBUG
import SwiftUI

struct TutorRealDemoView: View {
  let controller: TutorRealDemoController

  @State private var isSourceBodyExpanded = false
  @State private var isResponseBodyExpanded = false

  var body: some View {
    @Bindable var controller = controller

    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        configurationSection(controller: controller)
        caseSection(controller: controller)
        metricsSection(controller: controller)

        if let presentation = controller.latestPresentation {
          responseSection(presentation)
        }

        if let quality = controller.latestQualityReport {
          qualitySection(quality)
        }

        if !controller.runRecords.isEmpty {
          historySection(controller: controller)
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: 760, minHeight: 820)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Tutor Quality Evaluation")
        .font(.title2.bold())
      Text(
        "Synthetic Case → SemanticChunk → TutorRequest → 真实 Provider → TutorResponse → 离线质量信号"
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      Label(
        "Debug only · 不保存配置或正文 · 不连接自动跟随、Pet 或 Voice",
        systemImage: "hammer.fill"
      )
      .font(.caption)
      .foregroundStyle(.orange)
    }
  }

  private func configurationSection(
    controller: TutorRealDemoController
  ) -> some View {
    @Bindable var controller = controller

    return GroupBox("Debug LLM Configuration") {
      VStack(alignment: .leading, spacing: 10) {
        TextField(
          "https://provider.example/v1/chat/completions",
          text: $controller.configuration.endpoint
        )
        .textFieldStyle(.roundedBorder)

        TextField("Model", text: $controller.configuration.model)
          .textFieldStyle(.roundedBorder)

        SecureField("API Key", text: $controller.configuration.apiKey)
          .textFieldStyle(.roundedBorder)

        Text("仅存在当前进程内存；退出应用后立即清空。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 5)
    }
  }

  private func caseSection(
    controller: TutorRealDemoController
  ) -> some View {
    @Bindable var controller = controller
    let caseBinding = Binding(
      get: { controller.selectedCaseID },
      set: { id in
        controller.selectCase(id: id)
        isSourceBodyExpanded = false
        isResponseBodyExpanded = false
      }
    )

    return GroupBox("Case") {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Evaluation Case", selection: caseBinding) {
          ForEach(TutorEvaluationDataset.cases) { evaluationCase in
            Text(evaluationCase.name).tag(evaluationCase.id)
          }
        }
        .pickerStyle(.menu)
        .disabled(controller.isRunning)

        if let evaluationCase = controller.selectedCase {
          VStack(alignment: .leading, spacing: 5) {
            Text("Expected teaching characteristics")
              .font(.subheadline.bold())
            ForEach(
              Array(evaluationCase.expectedTeachingCharacteristics.enumerated()),
              id: \.offset
            ) { index, value in
              Text("\(index + 1). \(value)")
            }
            .font(.callout)
          }
        }

        Button(isSourceBodyExpanded ? "收起 SemanticChunk 正文" : "手动展开 SemanticChunk 正文") {
          isSourceBodyExpanded.toggle()
        }
        .controlSize(.small)

        if isSourceBodyExpanded {
          TextEditor(text: $controller.sourceText)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(7)
            .frame(minHeight: 120)
            .background(.background)
            .overlay {
              RoundedRectangle(cornerRadius: 6)
                .stroke(.separator, lineWidth: 1)
            }
        } else {
          Text("正文默认隐藏；只有主动点击后才显示当前内容。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if !controller.isUsingSelectedCaseBody {
          Label(
            "正文已手动修改；本次使用通用教学 expectations。",
            systemImage: "pencil"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }

        HStack {
          Text(
            "\(controller.sourceText.count) / \(TutorRealDemoController.maximumSourceCharacterCount) 字符"
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(
            controller.sourceText.count > TutorRealDemoController.maximumSourceCharacterCount
              ? .red
              : .secondary
          )

          Spacer()

          Button("取消") {
            controller.cancel()
          }
          .disabled(!controller.isRunning)

          Button("运行当前 Case") {
            isResponseBodyExpanded = false
            controller.explain()
          }
          .buttonStyle(.borderedProminent)
          .disabled(controller.isRunning)
        }

        Text("保持同一 Case 不变可重复运行；每次都会产生新请求，但复用同一个固定 SemanticChunk。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 5)
    }
  }

  private func metricsSection(
    controller: TutorRealDemoController
  ) -> some View {
    GroupBox("Run Metrics · No User Body") {
      VStack(alignment: .leading, spacing: 8) {
        metricRow("State", controller.state.rawValue)
        if let record = controller.latestRunRecord {
          metricRow("Latency", "\(record.latencyMilliseconds) ms")
          metricRow("Input Tokens", tokenText(record.inputTokenCount))
          metricRow("Output Tokens", tokenText(record.outputTokenCount))
          metricRow("Total Tokens", tokenText(record.totalTokenCount))
          metricRow("Result", record.outcome.rawValue)
        }
        if let failure = controller.latestFailure {
          Label(failure.displayText, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.callout)
        }
        if controller.isRunning {
          ProgressView()
            .controlSize(.small)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 5)
    }
  }

  private func responseSection(
    _ presentation: TutorPresentationModel
  ) -> some View {
    GroupBox("Response") {
      VStack(alignment: .leading, spacing: 10) {
        metricRow("Outcome", presentation.outcome.rawValue)
        metricRow("Title", presentation.title)
        metricRow("Response ID", shortID(presentation.responseMetadata.responseID))

        Button(isResponseBodyExpanded ? "收起 Response 正文" : "手动展开 Response 正文") {
          isResponseBodyExpanded.toggle()
        }
        .controlSize(.small)

        if isResponseBodyExpanded {
          responseBody(presentation)
        } else {
          Text("正文默认隐藏；每次新运行后需要再次手动展开。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 5)
    }
  }

  @ViewBuilder
  private func responseBody(
    _ presentation: TutorPresentationModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(presentation.plainExplanation)
        .textSelection(.enabled)

      if !presentation.keyPoints.isEmpty {
        responseList("关键点", values: presentation.keyPoints)
      }
      if !presentation.terms.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text("术语表").font(.subheadline.bold())
          ForEach(
            Array(presentation.terms.enumerated()),
            id: \.offset
          ) { _, value in
            Text("\(value.term)：\(value.plainDefinition)")
          }
        }
      }
      if let analogy = presentation.analogy {
        responseText("类比", value: analogy)
      }
      if let example = presentation.example {
        responseText("例子", value: example)
      }
      if !presentation.caveats.isEmpty {
        responseList("注意", values: presentation.caveats)
      }
      if presentation.didTruncateContent {
        Label(
          "PresentationModel 已按 UI 限制截断超长内容",
          systemImage: "scissors"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
  }

  private func qualitySection(
    _ quality: TutorQualityReport
  ) -> some View {
    GroupBox("Quality Signals") {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("总评")
            .foregroundStyle(.secondary)
          Spacer()
          Label(ratingText(quality.rating), systemImage: ratingIcon(quality.rating))
            .foregroundStyle(ratingColor(quality.rating))
        }
        .font(.callout.bold())

        Divider()

        ForEach(quality.signals) { qualitySignal in
          HStack(alignment: .top, spacing: 9) {
            Image(systemName: signalIcon(qualitySignal.status))
              .foregroundStyle(signalColor(qualitySignal.status))
              .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
              Text(qualitySignal.title)
                .font(.callout.bold())
              Text(qualitySignal.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
        }

        Divider()
        metricRow("解释字符", String(quality.explanationCharacterCount))
        metricRow("关键点", String(quality.keyPointCount))
        metricRow("术语", String(quality.glossaryTermCount))

        Label(
          "Source 对齐与未提供事实是离线启发式信号，warning 需人工复核。",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 5)
    }
  }

  private func historySection(
    controller: TutorRealDemoController
  ) -> some View {
    GroupBox("Same Case Runs · Metadata Only") {
      VStack(alignment: .leading, spacing: 7) {
        ForEach(controller.runRecords.prefix(8)) { record in
          HStack(spacing: 10) {
            Text(record.outcome.rawValue)
              .frame(width: 72, alignment: .leading)
            Text("\(record.latencyMilliseconds) ms")
              .monospacedDigit()
            Text("tokens \(tokenText(record.totalTokenCount))")
              .monospacedDigit()
            if let rating = record.qualityRating {
              Text(ratingText(rating))
                .foregroundStyle(ratingColor(rating))
            }
            if let failure = record.failure {
              Text(failure.rawValue)
                .foregroundStyle(.red)
            }
          }
          .font(.caption)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 5)
    }
  }

  private func metricRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .foregroundStyle(.secondary)
        .frame(width: 110, alignment: .leading)
      Text(value)
        .textSelection(.enabled)
    }
    .font(.callout)
  }

  private func responseText(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline.bold())
      Text(value).textSelection(.enabled)
    }
  }

  private func responseList(_ title: String, values: [String]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline.bold())
      ForEach(Array(values.enumerated()), id: \.offset) { index, value in
        Text("\(index + 1). \(value)")
      }
    }
  }

  private func ratingText(_ rating: TutorQualityRating) -> String {
    switch rating {
    case .passed:
      return "passed"
    case .needsReview:
      return "needs review"
    case .failed:
      return "failed"
    }
  }

  private func ratingIcon(_ rating: TutorQualityRating) -> String {
    switch rating {
    case .passed:
      return "checkmark.seal.fill"
    case .needsReview:
      return "exclamationmark.triangle.fill"
    case .failed:
      return "xmark.octagon.fill"
    }
  }

  private func ratingColor(_ rating: TutorQualityRating) -> Color {
    switch rating {
    case .passed:
      return .green
    case .needsReview:
      return .orange
    case .failed:
      return .red
    }
  }

  private func signalIcon(_ status: TutorQualitySignalStatus) -> String {
    switch status {
    case .passed:
      return "checkmark.circle.fill"
    case .warning:
      return "exclamationmark.triangle.fill"
    case .failed:
      return "xmark.circle.fill"
    }
  }

  private func signalColor(_ status: TutorQualitySignalStatus) -> Color {
    switch status {
    case .passed:
      return .green
    case .warning:
      return .orange
    case .failed:
      return .red
    }
  }

  private func tokenText(_ value: Int?) -> String {
    value.map(String.init) ?? "unavailable"
  }

  private func shortID(_ id: UUID) -> String {
    String(id.uuidString.prefix(8))
  }
}
#endif
