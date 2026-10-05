#if DEBUG
import SwiftUI

struct TutorLatencyBenchmarkView: View {
  let controller: TutorLatencyBenchmarkController
  let streamModelController: TutorStreamModelBenchmarkController?

  init(
    controller: TutorLatencyBenchmarkController,
    streamModelController: TutorStreamModelBenchmarkController? = nil
  ) {
    self.controller = controller
    self.streamModelController = streamModelController
  }

  var body: some View {
    @Bindable var controller = controller

    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 5) {
          Text("Tutor Latency Benchmark")
            .font(.title2.bold())
          Text("同一合成 Case 连续 5 次 · Saved Provider + Keychain · Metadata only")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        GroupBox("临时 Benchmark 配置") {
          VStack(alignment: .leading, spacing: 10) {
            Picker("Case", selection: $controller.selectedCaseID) {
              ForEach(TutorEvaluationDataset.cases) { item in
                Text(item.name).tag(item.id)
              }
            }
            .disabled(controller.isRunning)

            TextField("Model override（留空使用正式 active model）", text: $controller.modelOverride)
              .textFieldStyle(.roundedBorder)
              .disabled(controller.isRunning)

            Picker("Structured Output", selection: $controller.responseFormat) {
              ForEach(TutorLatencyBenchmarkFormat.allCases) { format in
                Text(format.displayName).tag(format)
              }
            }
            .disabled(controller.isRunning)

            Stepper(
              "Max Output Tokens: \(controller.maxOutputTokens)",
              value: $controller.maxOutputTokens,
              in: 128...4_096,
              step: 64
            )
            .disabled(controller.isRunning)

            Text("Model / format / token budget 仅用于本次 Debug 运行，不保存，不修改正式设置。")
              .font(.caption)
              .foregroundStyle(.secondary)

            HStack {
              Button("取消", action: controller.cancel)
                .disabled(!controller.isRunning)
              Spacer()
              Button("运行 6 Case 质量回归", action: controller.runQualitySuite)
                .disabled(controller.isRunning)
              Button("连续运行 5 次", action: controller.runFiveTimes)
                .buttonStyle(.borderedProminent)
                .disabled(controller.isRunning)
            }
          }
          .padding(.top, 5)
        }

        GroupBox("Benchmark Summary") {
          VStack(alignment: .leading, spacing: 8) {
            metricRow("State", controller.state.rawValue)
            metricRow(
              "Runs",
              "\(controller.completedRuns) / \(controller.targetRuns)"
            )
            distributionRow("Total", controller.summary.total)
            distributionRow("TTFB", controller.summary.timeToFirstByte)
            distributionRow("Generation", controller.summary.generation)
            if let failure = controller.failureMessage {
              Label(failure, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            }
            if controller.isRunning {
              ProgressView()
                .controlSize(.small)
            }
          }
          .padding(.top, 5)
        }

        if let latest = controller.records.last {
          promptBudgetSection(latest)
        }

        if !controller.records.isEmpty {
          GroupBox("Runs · No Body") {
            VStack(alignment: .leading, spacing: 7) {
              ForEach(controller.records) { record in
                HStack(spacing: 9) {
                  Text("#\(record.runNumber)").frame(width: 28, alignment: .leading)
                  Text(record.caseName).frame(width: 92, alignment: .leading)
                  Text(ms(record.metrics.totalTutorLatency)).monospacedDigit()
                  Text("TTFB \(ms(record.metrics.timeToFirstByte))").monospacedDigit()
                  Text("gen \(ms(record.metrics.generationDuration))").monospacedDigit()
                  Text("in \(token(record.metrics.inputTokens))")
                  Text("out \(token(record.metrics.outputTokens))")
                  Text(record.qualityRating?.rawValue ?? "FAIL")
                }
                .font(.caption)
              }
            }
            .padding(.top, 5)
          }
        }

        if let streamModelController {
          streamModelSection(streamModelController)
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: 820, minHeight: 820)
  }

  private func promptBudgetSection(
    _ record: TutorLatencyBenchmarkRecord
  ) -> some View {
    GroupBox("Prompt / Output Budget") {
      VStack(alignment: .leading, spacing: 7) {
        metricRow("Model", record.model)
        metricRow("Format", record.responseFormat.displayName)
        metricRow("Max output", String(record.maxOutputTokens))
        if let size = record.metrics.promptSize {
          metricRow("System chars", String(size.systemInstructionCharacters))
          metricRow("Rules chars", String(size.constraintsCharacters))
          metricRow("Schema chars", String(size.outputSchemaCharacters))
          metricRow("User chars", String(size.userContentCharacters))
          metricRow("Source chars", String(size.sourceCharacters))
          metricRow("Estimated input", "~\(size.estimatedInputTokens) tokens")
        }
        metricRow("Provider input", token(record.metrics.inputTokens))
        metricRow("Provider output", token(record.metrics.outputTokens))
      }
      .padding(.top, 5)
    }
  }

  private func distributionRow(
    _ title: String,
    _ distribution: TutorLatencyDistribution?
  ) -> some View {
    metricRow(
      title,
      distribution.map {
        "min \(ms($0.minimum)) · p50 \(ms($0.p50)) · median \(ms($0.median)) · max \(ms($0.maximum))"
      } ?? "unavailable"
    )
  }

  private func metricRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .foregroundStyle(.secondary)
        .frame(width: 115, alignment: .leading)
      Text(value).textSelection(.enabled)
    }
    .font(.callout)
  }

  private func ms(_ duration: TimeInterval?) -> String {
    duration.map { "\(Int(($0 * 1_000).rounded())) ms" } ?? "n/a"
  }

  private func token(_ count: Int?) -> String {
    count.map(String.init) ?? "n/a"
  }

  private func streamModelSection(
    _ streamController: TutorStreamModelBenchmarkController
  ) -> some View {
    @Bindable var streamController = streamController
    return GroupBox("PERF-02 · Streaming + Model") {
      VStack(alignment: .leading, spacing: 9) {
        Picker("Case", selection: $streamController.selectedCaseID) {
          ForEach(TutorEvaluationDataset.cases) { item in
            Text(item.name).tag(item.id)
          }
        }
        TextField(
          "Primary model override（留空使用 active model）",
          text: $streamController.modelOverride
        )
        .textFieldStyle(.roundedBorder)
        TextField(
          "已确认可用候选模型（逗号分隔，仅内存）",
          text: $streamController.candidateModelsText
        )
        .textFieldStyle(.roundedBorder)
        HStack {
          Picker("Format", selection: $streamController.responseFormat) {
            ForEach(TutorLatencyBenchmarkFormat.allCases) { format in
              Text(format.displayName).tag(format)
            }
          }
          Picker("Mode", selection: $streamController.selectedMode) {
            ForEach(TutorBenchmarkTransportMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
        }
        HStack {
          Button("取消", action: streamController.cancel)
            .disabled(!streamController.isRunning)
          Button("Stream / Non-stream 5×", action: streamController.runModeComparison)
          Button("Model 5×", action: streamController.runModelComparison)
          Button("Format 5×", action: streamController.runFormatComparison)
          Button("6 Case Quality", action: streamController.runQualityMatrix)
        }
        .disabled(streamController.isRunning)
        metricRow("State", streamController.state.rawValue)
        metricRow(
          "Runs",
          "\(streamController.completedRuns) / \(streamController.targetRuns)"
        )
        if let failure = streamController.failureMessage {
          Label(failure, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
        ForEach(streamController.configurationSummaries) { summary in
          VStack(alignment: .leading, spacing: 3) {
            Text(
              "\(summary.model) · \(summary.responseFormat.displayName) · \(summary.mode.displayName)"
            )
            .font(.caption.bold())
            distributionRow("TTFB", summary.latency.timeToFirstByte)
            distributionRow("First content", summary.latency.timeToFirstModelContent)
            distributionRow("Full", summary.latency.total)
            metricRow(
              "Quality",
              "PASS \(summary.qualityPasses) · REVIEW \(summary.qualityNeedsReview) · FAIL \(summary.qualityFailures)"
            )
          }
        }
      }
      .padding(.top, 5)
    }
  }
}

struct TutorStreamModelBenchmarkView: View {
  let controller: TutorStreamModelBenchmarkController

  var body: some View {
    @Bindable var controller = controller

    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 5) {
          Text("Tutor Streaming + Model Benchmark")
            .font(.title2.bold())
          Text("Debug only · full JSON gate · metadata only · no partial Panel UI")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        GroupBox("临时 Benchmark 配置") {
          VStack(alignment: .leading, spacing: 10) {
            Picker("Case", selection: $controller.selectedCaseID) {
              ForEach(TutorEvaluationDataset.cases) { item in
                Text(item.name).tag(item.id)
              }
            }

            TextField(
              "Primary model override（留空使用 active model）",
              text: $controller.modelOverride
            )
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
              Text("已由当前 Ark 账号确认的候选模型（逗号分隔）")
                .font(.caption)
                .foregroundStyle(.secondary)
              TextField("model-a, model-b", text: $controller.candidateModelsText)
                .textFieldStyle(.roundedBorder)
            }

            HStack {
              Picker("Format", selection: $controller.responseFormat) {
                ForEach(TutorLatencyBenchmarkFormat.allCases) { format in
                  Text(format.displayName).tag(format)
                }
              }
              Picker("Mode", selection: $controller.selectedMode) {
                ForEach(TutorBenchmarkTransportMode.allCases) { mode in
                  Text(mode.displayName).tag(mode)
                }
              }
            }

            Stepper(
              "Max Output Tokens: \(controller.maxOutputTokens)",
              value: $controller.maxOutputTokens,
              in: 128...4_096,
              step: 64
            )

            Text("所有 override 仅存在当前进程内存；不会保存或修改 active Provider Settings。")
              .font(.caption)
              .foregroundStyle(.secondary)

            HStack {
              Button("取消", action: controller.cancel)
                .disabled(!controller.isRunning)
              Spacer()
              Button("Stream / Non-stream 5×", action: controller.runModeComparison)
              Button("Model 5×", action: controller.runModelComparison)
              Button("Format 5×", action: controller.runFormatComparison)
              Button("6 Case Quality Matrix", action: controller.runQualityMatrix)
                .buttonStyle(.borderedProminent)
            }
          }
          .disabled(controller.isRunning)
          .padding(.top, 5)
        }

        GroupBox("Progress") {
          VStack(alignment: .leading, spacing: 8) {
            metricRow("State", controller.state.rawValue)
            metricRow("Runs", "\(controller.completedRuns) / \(controller.targetRuns)")
            metricRow("Active model", controller.activeModel ?? "not loaded")
            if let failure = controller.failureMessage {
              Label(failure, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            }
            if controller.isRunning { ProgressView().controlSize(.small) }
          }
          .padding(.top, 5)
        }

        ForEach(controller.configurationSummaries) { summary in
          GroupBox(
            "\(summary.model) · \(summary.responseFormat.displayName) · \(summary.mode.displayName)"
          ) {
            VStack(alignment: .leading, spacing: 6) {
              metricRow(
                "Runs",
                "\(summary.successfulRuns) pass / \(summary.failedRuns) fail"
              )
              distributionRow("TTFB", summary.latency.timeToFirstByte)
              distributionRow(
                "First content",
                summary.latency.timeToFirstModelContent
              )
              distributionRow("Full latency", summary.latency.total)
              distributionRow("Generation", summary.latency.generation)
              metricRow(
                "Quality",
                "PASS \(summary.qualityPasses) · REVIEW \(summary.qualityNeedsReview) · FAIL \(summary.qualityFailures)"
              )
            }
            .padding(.top, 5)
          }
        }

        if !controller.records.isEmpty {
          GroupBox("Runs · No Body") {
            VStack(alignment: .leading, spacing: 7) {
              ForEach(controller.records) { record in
                VStack(alignment: .leading, spacing: 3) {
                  HStack(spacing: 8) {
                    Text("#\(record.runNumber)").frame(width: 32, alignment: .leading)
                    Text(record.caseName).frame(width: 90, alignment: .leading)
                    Text(record.model).lineLimit(1)
                    Text(record.responseFormat.displayName)
                    Text(record.mode.displayName)
                    Spacer()
                    Text(record.qualityRating?.rawValue ?? "FAIL")
                  }
                  .font(.caption)
                  HStack(spacing: 10) {
                    Text("TTFB \(ms(record.metrics.timeToFirstByte))")
                    Text("event \(ms(record.metrics.timeToFirstSSEEvent))")
                    Text("content \(ms(record.metrics.timeToFirstModelContent))")
                    Text("full \(ms(record.metrics.totalTutorLatency))")
                    Text("in \(token(record.metrics.inputTokens))")
                    Text("out \(token(record.metrics.outputTokens))")
                  }
                  .font(.caption2.monospacedDigit())
                  if let signals = record.qualitySignals {
                    Text(
                      "facts \(signals.unsupportedFacts.rawValue) · structure \(signals.missingStructure.rawValue) · verbosity \(signals.verbosity.rawValue) · alignment \(signals.sourceAlignment.rawValue)"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                  }
                }
                Divider()
              }
            }
            .padding(.top, 5)
          }
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: 980, minHeight: 860)
  }

  private func distributionRow(
    _ title: String,
    _ distribution: TutorLatencyDistribution?
  ) -> some View {
    metricRow(
      title,
      distribution.map {
        "min \(ms($0.minimum)) · p50 \(ms($0.p50)) · p90 \(ms($0.p90)) · max \(ms($0.maximum))"
      } ?? "unavailable"
    )
  }

  private func metricRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .foregroundStyle(.secondary)
        .frame(width: 115, alignment: .leading)
      Text(value).textSelection(.enabled)
    }
    .font(.callout)
  }

  private func ms(_ duration: TimeInterval?) -> String {
    duration.map { "\(Int(($0 * 1_000).rounded())) ms" } ?? "n/a"
  }

  private func token(_ count: Int?) -> String {
    count.map(String.init) ?? "n/a"
  }
}
#endif
