import Foundation

struct DoubaoS2SConfiguration: Equatable, Sendable {
  static let forbiddenSceneIdentifier = "Doubao_scene_SLM_Doubao_realtime_voice_model"

  let provider: String
  let outputMode: Int
  let model: String
  let testPersona: String

  init(
    provider: String = "volcano",
    outputMode: Int = 0,
    model: String,
    testPersona: String = "你是一个简洁友好的中文语音助手。"
  ) throws {
    let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedModel.isEmpty,
          normalizedModel != Self.forbiddenSceneIdentifier else {
      throw RealtimeVoiceFailure.aiTaskStartFailed(
        message: "The account-confirmed S2S-O model value is required."
      )
    }
    self.provider = provider
    self.outputMode = outputMode
    self.model = normalizedModel
    self.testPersona = testPersona
  }
}
