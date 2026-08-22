#if DEBUG
import SwiftUI

struct TutorLatencyBenchmarkView: View {
  let controller: TutorLatencyBenchmarkController

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
}
#endif
