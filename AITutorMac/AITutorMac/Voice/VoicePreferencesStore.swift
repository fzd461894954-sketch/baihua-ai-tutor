import Foundation

struct VoicePreferencesStore {
  private enum Key {
    static let voiceIdentifier = "voice.preferences.voiceIdentifier"
    static let rate = "voice.preferences.rate"
    static let pitch = "voice.preferences.pitch"
    static let volume = "voice.preferences.volume"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> SpeechConfiguration {
    let fallback = SpeechConfiguration.default
    return SpeechConfiguration(
      voiceIdentifier: defaults.string(forKey: Key.voiceIdentifier),
      rate: storedFloat(forKey: Key.rate) ?? fallback.rate,
      pitch: storedFloat(forKey: Key.pitch) ?? fallback.pitch,
      volume: storedFloat(forKey: Key.volume) ?? fallback.volume
    ).clamped()
  }

  func save(_ configuration: SpeechConfiguration) {
    let configuration = configuration.clamped()
    if let voiceIdentifier = configuration.voiceIdentifier {
      defaults.set(voiceIdentifier, forKey: Key.voiceIdentifier)
    } else {
      defaults.removeObject(forKey: Key.voiceIdentifier)
    }
    defaults.set(configuration.rate, forKey: Key.rate)
    defaults.set(configuration.pitch, forKey: Key.pitch)
    defaults.set(configuration.volume, forKey: Key.volume)
  }

  private func storedFloat(forKey key: String) -> Float? {
    guard defaults.object(forKey: key) != nil else {
      return nil
    }
    return defaults.float(forKey: key)
  }
}
