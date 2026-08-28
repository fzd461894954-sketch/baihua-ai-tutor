import Foundation

enum TutorConversationMode: String, Equatable, Sendable {
  case normalContext
  case currentTurnOnly
}

enum TutorPromptMessageRole: String, Equatable, Sendable {
  case user
  case assistant
}

struct TutorPromptMessage: Equatable, Sendable {
  let role: TutorPromptMessageRole
  let content: String
}

/// Provider-neutral prompt input. It contains no transport, credentials, or
/// model-specific settings.
struct PromptPackage: Equatable, Sendable {
  let systemInstruction: String
  let userContent: String
  let outputSchema: String
  let constraints: [String]
  let history: [TutorPromptMessage]
  let conversationMode: TutorConversationMode
  let tutorRequestID: UUID?

  init(
    systemInstruction: String,
    userContent: String,
    outputSchema: String,
    constraints: [String],
    history: [TutorPromptMessage] = [],
    conversationMode: TutorConversationMode = .normalContext,
    tutorRequestID: UUID? = nil
  ) {
    self.systemInstruction = systemInstruction
    self.userContent = userContent
    self.outputSchema = outputSchema
    self.constraints = constraints
    self.history = conversationMode == .currentTurnOnly ? [] : history
    self.conversationMode = conversationMode
    self.tutorRequestID = tutorRequestID
  }
}
