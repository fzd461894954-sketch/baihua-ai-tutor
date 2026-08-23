import AppKit
import SwiftUI

struct PetView: View {
  let pet: PetModel
  let petImage: NSImage?
  let stateController: PetStateController
  let speechInputController: SpeechInputController
  let tutorNotificationCenter: TutorPetNotificationCenter

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
          } else if tutorNotificationCenter.hasUnreadTutorPresentation,
                    !speechInputController.isMicrophoneActive {
            TutorUnreadBadgeView()
          }
        }
        Spacer()
      }
      .padding(4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("桌面老师，\(pet.name)")
    .accessibilityValue(accessibilityValue)
    .accessibilityHint("单击展开或收起花花老师，可以直接看解释、打字或说话提问")
  }

  private var accessibilityValue: String {
    if tutorNotificationCenter.hasUnreadTutorPresentation {
      return "\(stateController.currentState.displayName)，有新的解释"
    }
    return stateController.currentState.displayName
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

private struct TutorUnreadBadgeView: View {
  var body: some View {
    Circle()
      .fill(.purple)
      .frame(width: 12, height: 12)
      .overlay {
        Circle().stroke(.white.opacity(0.9), lineWidth: 1.5)
      }
      .shadow(
        color: AppShadow.badge.color,
        radius: AppShadow.badge.radius,
        y: AppShadow.badge.y
      )
      .accessibilityHidden(true)
  }
}

private struct VoiceInputBadgeView: View {
  var body: some View {
    Image(systemName: "mic.fill")
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: 27, height: 27)
      .background(AppColors.listeningAttention, in: Circle())
      .overlay {
        Circle()
          .stroke(.white.opacity(0.8), lineWidth: 1.5)
      }
      .shadow(
        color: AppShadow.badge.color,
        radius: AppShadow.badge.radius,
        y: AppShadow.badge.y
      )
      .accessibilityLabel("正在使用麦克风")
  }
}

struct PetBubble: Equatable {
  let title: String
  let detail: String?

  static let welcome = PetBubble(
    title: "你好，我是你的 AI 老师。",
    detail: "点一下我，就能在这里看解释或直接提问。"
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
    BubbleChrome {
      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(bubble.title)
          .font(AppTypography.bubbleTitle)

        if let detail = bubble.detail {
          Text(detail)
            .font(AppTypography.bubbleBody)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(AppSpacing.xxs)
  }
}

struct PetTutorBubbleView: View {
  let notification: PetTutorNotification
  let onOpenTutor: () -> Void

  var body: some View {
    BubbleChrome {
      VStack(alignment: .leading, spacing: AppSpacing.xs) {
        Text(notification.title)
          .font(AppTypography.bubbleTitle)

        Text(notification.message)
          .font(AppTypography.bubbleBody)
          .foregroundStyle(.secondary)
          .lineLimit(2)

        HStack {
          Spacer()
          Button("查看解释", action: onOpenTutor)
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(AppSpacing.xxs)
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
      .shadow(
        color: AppShadow.badge.color,
        radius: AppShadow.badge.radius,
        y: AppShadow.badge.y
      )
      .accessibilityHidden(true)
  }

  private var badgeColor: Color {
    AppColors.petState(state)
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
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .foregroundStyle(AppColors.brand)
    .padding(AppSpacing.xs)
  }
}

#if DEBUG
#Preview("Pet Bubble Matrix") {
  VStack(spacing: AppSpacing.md) {
    PetBubbleView(bubble: .welcome)
      .frame(width: 300, height: 90)
    PetBubbleView(bubble: .warning)
      .frame(width: 300, height: 70)
  }
  .padding()
}

#Preview("Pet Bubble Dark") {
  PetBubbleView(bubble: .welcome)
    .frame(width: 300, height: 90)
    .padding()
    .preferredColorScheme(.dark)
}
#endif
