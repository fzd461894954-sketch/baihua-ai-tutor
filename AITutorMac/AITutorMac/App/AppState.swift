import Observation

@MainActor
@Observable
final class AppState {
  enum ShellStatus: Equatable {
    case ready
    case hotKeyUnavailable

    var displayText: String {
      switch self {
      case .ready:
        return "准备就绪"
      case .hotKeyUnavailable:
        return "快捷键不可用"
      }
    }
  }

  var isPanelVisible = false
  var isPetVisible = false
  var shellStatus: ShellStatus = .ready
}
