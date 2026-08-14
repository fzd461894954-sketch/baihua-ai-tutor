import Foundation
import OSLog

enum AppLogger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.baihuaai.AITutorMac"

  static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
  static let panel = Logger(subsystem: subsystem, category: "panel")
  static let pet = Logger(subsystem: subsystem, category: "pet")
  static let customPet = Logger(subsystem: subsystem, category: "custom-pet")
  static let voice = Logger(subsystem: subsystem, category: "voice")
  static let hotKey = Logger(subsystem: subsystem, category: "hotkey")
}
