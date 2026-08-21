import Foundation
import Observation

enum CurrentExplainableContentError: Error, Equatable, Sendable {
  case noStableContent
}

/// Keeps only the latest stable SemanticChunk owned by the active AX live
/// session. It has no history, snapshot body, revision archive, or persistence.
@MainActor
@Observable
final class CurrentExplainableContentProvider: TutorCurrentContentProviding {
  private(set) var activeSessionID: UUID?
  private(set) var hasStableContent = false

  @ObservationIgnored private var currentChunk: SemanticChunk?
  @ObservationIgnored private let maximumCharacterCount: Int

  init(
    maximumCharacterCount: Int = TutorRequest.defaultMaximumSourceCharacterCount
  ) {
    self.maximumCharacterCount = maximumCharacterCount
  }

  func beginSession(_ sessionID: UUID) {
    activeSessionID = sessionID
    currentChunk = nil
    hasStableContent = false
  }

  func receive(_ chunk: SemanticChunk, sessionID: UUID) {
    guard
      activeSessionID == sessionID,
      Self.hasVisibleText(chunk.text),
      chunk.text.count <= maximumCharacterCount,
      Self.isValid(chunk.confidence)
    else {
      return
    }
    currentChunk = chunk
    hasStableContent = true
  }

  func invalidateSession(_ sessionID: UUID? = nil) {
    if let sessionID, activeSessionID != sessionID {
      return
    }
    activeSessionID = nil
    currentChunk = nil
    hasStableContent = false
  }

  func currentSemanticChunk() throws -> SemanticChunk {
    guard
      activeSessionID != nil,
      let currentChunk,
      Self.hasVisibleText(currentChunk.text),
      currentChunk.text.count <= maximumCharacterCount,
      Self.isValid(currentChunk.confidence)
    else {
      throw CurrentExplainableContentError.noStableContent
    }
    return currentChunk
  }

  private static func hasVisibleText(_ text: String) -> Bool {
    text.contains(where: { !$0.isWhitespace })
  }

  private static func isValid(_ confidence: DiffConfidence) -> Bool {
    switch confidence {
    case .low, .medium, .high:
      return true
    }
  }
}
