import AppKit
import SwiftUI

struct PetView: View {
  let pet: PetModel
  let petImage: NSImage?
  let stateController: PetStateController
  let speechInputController: SpeechInputController

  var body: some View {
    ZStack {
      petArtwork

      VStack {
        HStack {
          if speechInputController.isMicrophoneActive {
            VoiceInputBadgeView()
          }

          Spacer()

          if let symbolName = stateController.currentState.badgeSystemImageName {
            PetStateBadgeView(
              state: stateController.currentState,
              symbolName: symbolName
            )
          }
        }
        Spacer()
      }
      .padding(4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("桌面吉祥物，\(pet.name)")
    .accessibilityValue(stateController.currentState.displayName)
    .accessibilityHint("单击打开语音操作，双击打开教学窗口")
  }

  @ViewBuilder
  private var petArtwork: some View {
    if pet.type == .staticImage, let petImage, petImage.isValid {
      Image(nsImage: petImage)
        .resizable()
        .interpolation(.high)
        .antialiased(true)
        .scaledToFit()
    } else {
      PetAssetPlaceholder(petName: pet.name)
    }
  }
}

private struct VoiceInputBadgeView: View {
  var body: some View {
    Image(systemName: "mic.fill")
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: 27, height: 27)
      .background(.red, in: Circle())
      .overlay {
        Circle()
          .stroke(.white.opacity(0.8), lineWidth: 1.5)
      }
      .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
      .accessibilityLabel("正在使用麦克风")
  }
}

struct PetBubble: Equatable {
  let title: String
  let detail: String?

  static let welcome = PetBubble(
    title: "你好，我是你的 AI 老师。",
    detail: "双击我可以打开教学窗口。"
  )

  static let understanding = PetBubble(title: "我正在理解当前内容。", detail: nil)
  static let speaking = PetBubble(title: "我正在给你解释。", detail: nil)
  static let needsInput = PetBubble(title: "这里需要你操作一下。", detail: nil)
  static let warning = PetBubble(title: "这一步需要你注意。", detail: nil)
  static let success = PetBubble(title: "完成啦。", detail: nil)
  static let error = PetBubble(title: "刚才这一步没有成功。", detail: nil)

  static func automatic(for state: PetState) -> PetBubble? {
    switch state {
    case .needsInput:
      return .needsInput
    case .warning:
      return .warning
    case .success:
      return .success
    case .error:
      return .error
    case .idle, .watching, .thinking, .speaking:
      return nil
    }
  }
}

struct PetBubbleView: View {
  let bubble: PetBubble

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(bubble.title)
        .font(.system(size: 14, weight: .semibold))

      if let detail = bubble.detail {
        Text(detail)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.primary.opacity(0.08), lineWidth: 1)
    }
    .padding(5)
  }
}

private struct PetStateBadgeView: View {
  let state: PetState
  let symbolName: String

  var body: some View {
    Image(systemName: symbolName)
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: 27, height: 27)
      .background(badgeColor, in: Circle())
      .overlay {
        Circle()
          .stroke(.white.opacity(0.8), lineWidth: 1.5)
      }
      .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
      .accessibilityHidden(true)
  }

  private var badgeColor: Color {
    switch state {
    case .idle:
      return .clear
    case .watching:
      return .blue
    case .thinking:
      return .purple
    case .speaking:
      return .indigo
    case .needsInput:
      return .cyan
    case .warning:
      return .orange
    case .success:
      return .green
    case .error:
      return .red
    }
  }
}

private struct PetAssetPlaceholder: View {
  let petName: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "photo.badge.exclamationmark")
        .font(.system(size: 48, weight: .light))
      Text(petName)
        .font(.system(size: 13, weight: .semibold))
      Text("等待透明素材")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
    .foregroundStyle(.purple)
    .padding(8)
  }
}
