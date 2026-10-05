import Foundation

struct SpeechVoiceOption: Equatable, Identifiable, Sendable {
  let identifier: String
  let name: String
  let language: String

  var id: String { identifier }
}

struct SpeechConfiguration: Equatable, Sendable {
  static let rateRange: ClosedRange<Float> = 0.38...0.56
  static let pitchRange: ClosedRange<Float> = 0.75...1.25
  static let volumeRange: ClosedRange<Float> = 0.2...1

  static let `default` = SpeechConfiguration(
    voiceIdentifier: nil,
    rate: 0.46,
    pitch: 1,
    volume: 1
  )

  var voiceIdentifier: String?
  var rate: Float
  var pitch: Float
  var volume: Float

  func clamped() -> SpeechConfiguration {
    SpeechConfiguration(
      voiceIdentifier: voiceIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
      rate: rate.clamped(to: Self.rateRange),
      pitch: pitch.clamped(to: Self.pitchRange),
      volume: volume.clamped(to: Self.volumeRange)
    )
  }

  static func resolvedVoiceIdentifier(
    preferredIdentifier: String?,
    availableVoices: [SpeechVoiceOption]
  ) -> String? {
    if let preferredIdentifier,
       availableVoices.contains(where: { $0.identifier == preferredIdentifier }) {
      return preferredIdentifier
    }

    return availableVoices.first(where: { $0.language == "zh-CN" })?.identifier
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
