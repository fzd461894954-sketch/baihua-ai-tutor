import Foundation
import OSLog

enum AppLogger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.baihuaai.AITutorMac"

  static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
  static let panel = Logger(subsystem: subsystem, category: "panel")
  static let pet = Logger(subsystem: subsystem, category: "pet")
  static let customPet = Logger(subsystem: subsystem, category: "custom-pet")
  static let voice = Logger(subsystem: subsystem, category: "voice")
  static let voiceInput = Logger(subsystem: subsystem, category: "voice-input")
  static let hotKey = Logger(subsystem: subsystem, category: "hotkey")
  static let context = Logger(subsystem: subsystem, category: "context")
  static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
  static let tutorRuntime = Logger(subsystem: subsystem, category: "tutor-runtime")
}
