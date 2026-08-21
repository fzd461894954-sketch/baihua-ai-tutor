#if DEBUG
import SwiftUI

struct RealtimeVoiceSpikeView: View {
  let coordinator: DoubaoRealtimeVoiceCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Realtime Voice Spike")
          .font(.title2.bold())
        Text("CODE CONTRACT / MOCK RTC · E2E PENDING")
          .font(.caption.monospaced())
          .foregroundStyle(.orange)
        Text("No Volcengine credential is present in this Mac build.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if coordinator.isMicrophoneActive {
        Label("豆包实时语音正在使用麦克风", systemImage: "mic.fill")
          .font(.headline)
          .foregroundStyle(.red)
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      } else {
        Label("麦克风未使用", systemImage: "mic.slash")
          .foregroundStyle(.secondary)
      }

      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
        statusRow("RTC", coordinator.rtcStatus.rawValue)
        statusRow("AI Task", coordinator.aiTaskStatus.rawValue)
        statusRow("Session State", coordinator.state.displayName)
        statusRow("Microphone", coordinator.isMicrophoneActive ? "active" : "inactive")
        statusRow("Speaking", coordinator.isAISpeaking ? "yes" : "no")
        statusRow("Duration", durationText)
        statusRow("Stop Reason", coordinator.lastStopReason?.rawValue ?? "—")
        statusRow("Last Error", coordinator.lastError ?? "—")
      }

      HStack(spacing: 12) {
        Button("Start Session") {
          Task {
            try? await coordinator.start()
          }
        }
        .disabled(coordinator.isActive)

        Button("Interrupt") {
          Task {
            try? await coordinator.interrupt()
          }
        }
        .disabled(!canInterrupt)

        Button("Stop Session", role: .destructive) {
          Task {
            await coordinator.stop()
          }
        }
        .disabled(!coordinator.isActive)
      }

      Spacer()
    }
    .padding(20)
    .frame(minWidth: 560, minHeight: 430)
  }

  @ViewBuilder
  private func statusRow(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.body.monospaced())
        .textSelection(.enabled)
    }
  }

  private var canInterrupt: Bool {
    [.listening, .thinking, .speaking].contains(coordinator.state)
  }

  private var durationText: String {
    String(format: "%.1f s", coordinator.duration)
  }
}
#endif
