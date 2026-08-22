import SwiftUI

enum AppSpacing {
  static let xxs: CGFloat = 4
  static let xs: CGFloat = 8
  static let sm: CGFloat = 12
  static let md: CGFloat = 16
  static let lg: CGFloat = 24
  static let xl: CGFloat = 32
}

enum AppRadius {
  static let control: CGFloat = 8
  static let bubble: CGFloat = 12
  static let container: CGFloat = 16
}

enum AppTypography {
  static let bubbleTitle = Font.system(size: 13, weight: .medium)
  static let bubbleBody = Font.system(size: 12, weight: .regular)
}

enum AppColors {
  // The brand palette is provisional. Keep using the product accent until a
  // full-product visual review establishes a final palette.
  static let brand = Color.accentColor
  static let brandStrong = Color.accentColor

  static let stateIdle = Color(red: 0.37, green: 0.37, blue: 0.35)
  static let stateWatching = Color(red: 0.09, green: 0.37, blue: 0.65)
  static let stateActive = Color(red: 0.33, green: 0.29, blue: 0.72)
  static let stateAttention = Color(red: 0.52, green: 0.31, blue: 0.04)
  static let stateSuccess = Color(red: 0.23, green: 0.43, blue: 0.07)
  static let stateError = Color(red: 0.64, green: 0.18, blue: 0.18)
  static let listeningAttention = stateError

  static func petState(_ state: PetState) -> Color {
    switch state {
    case .idle: stateIdle
    case .watching: stateWatching
    case .thinking, .speaking: stateActive
    case .needsInput, .warning: stateAttention
    case .success: stateSuccess
    case .error: stateError
    }
  }
}

enum AppShadow {
  static let badge = (
    color: Color.black.opacity(0.16),
    radius: CGFloat(2),
    y: CGFloat(1)
  )

  static let bubble = (
    color: Color.black.opacity(0.10),
    radius: CGFloat(6),
    y: CGFloat(2)
  )
}

enum AppMotion {
  static let micro = 0.15
  static let bubble = 0.30
}
