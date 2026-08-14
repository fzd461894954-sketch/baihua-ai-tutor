import Foundation

enum PetState: String, CaseIterable, Codable, Equatable, Sendable {
  case idle
  case watching
  case thinking
  case speaking
  case needsInput
  case warning
  case success
  case error

  var displayName: String {
    switch self {
    case .idle:
      return "待机"
    case .watching:
      return "正在观察"
    case .thinking:
      return "正在理解"
    case .speaking:
      return "正在解释"
    case .needsInput:
      return "等待你的操作"
    case .warning:
      return "需要注意"
    case .success:
      return "已完成"
    case .error:
      return "出现问题"
    }
  }

  var badgeSystemImageName: String? {
    switch self {
    case .idle:
      return nil
    case .watching:
      return "eye.fill"
    case .thinking:
      return "ellipsis"
    case .speaking:
      return "waveform"
    case .needsInput:
      return "questionmark.circle.fill"
    case .warning:
      return "exclamationmark.triangle.fill"
    case .success:
      return "checkmark.circle.fill"
    case .error:
      return "xmark.circle.fill"
    }
  }

  var isTransient: Bool {
    self == .success
  }
}
