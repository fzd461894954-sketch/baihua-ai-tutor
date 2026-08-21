import XCTest

@testable import AITutorMac

final class ContextDiffEngineTests: XCTestCase {
  private let normalizer = TextNormalizer()
  private let engine = ContextDiffEngine()

  func testFirstTextEstablishesBaselineWithoutAddedText() {
    let result = engine.diff(
      previous: nil,
      current: normalizer.normalize("Existing window content")
    )

    XCTAssertEqual(result.kind, .baseline)
    XCTAssertEqual(result.confidence, .high)
    XCTAssertEqual(result.addedText, "")
    XCTAssertNil(result.previousFingerprint)
    XCTAssertFalse(result.hasAddedText)
  }

  func testIdenticalNormalizedContentProducesNoChange() {
    let previous = normalizer.normalize("The build is\nstill running")
    let current = normalizer.normalize("The build is still running")

    let result = engine.diff(previous: previous, current: current)

    XCTAssertEqual(result.kind, .noChange)
    XCTAssertEqual(result.confidence, .high)
    XCTAssertEqual(result.addedText, "")
    XCTAssertEqual(result.previousFingerprint, result.currentFingerprint)
  }

  func testExactAppendReturnsOnlyAddedTextWithHighConfidence() {
    let result = diff(previous: "Build", current: "Build succeeded")

    XCTAssertEqual(result.kind, .added)
    XCTAssertEqual(result.confidence, .high)
    XCTAssertEqual(result.addedText, "succeeded")
  }

  func testStreamingGrowthInsideTokenReturnsOnlyNewCharacters() {
    let result = diff(previous: "runn", current: "running")

    XCTAssertEqual(result.kind, .added)
    XCTAssertEqual(result.confidence, .high)
    XCTAssertEqual(result.addedText, "ing")
  }

  func testExactMiddleInsertionReturnsAddedTextWithoutRemovedText() {
    let result = diff(previous: "alpha gamma", current: "alpha beta gamma")

    XCTAssertEqual(result.kind, .added)
    XCTAssertEqual(result.confidence, .high)
    XCTAssertEqual(result.addedText, "beta")
  }

  func testViewportTailOverlapReturnsOnlyNewTailWithMediumConfidence() {
    let result = diff(
      previous: "Step one completed\nStep two is running",
      current: "Step two is running\nStep three completed"
    )

    XCTAssertEqual(result.kind, .added)
    XCTAssertEqual(result.confidence, .medium)
    XCTAssertEqual(result.addedText, "Step three completed")
  }

  func testScrollingToContentAlreadyInsidePreviousTextDoesNotEmit() {
    let result = diff(
      previous: "First block\nSecond block\nThird block",
      current: "Second block"
    )

    XCTAssertEqual(result.kind, .noChange)
    XCTAssertEqual(result.confidence, .medium)
    XCTAssertEqual(result.addedText, "")
  }

  func testSmallRewriteIsAmbiguousAndDoesNotExposeReplacementAsAdded() {
    let result = diff(previous: "Build failed", current: "Build passed")

    XCTAssertEqual(result.kind, .ambiguous)
    XCTAssertEqual(result.confidence, .low)
    XCTAssertEqual(result.addedText, "")
  }

  func testUnrelatedContentIsResetAndDoesNotEmitWholeScreen() {
    let result = diff(
      previous: "Installing project dependencies",
      current: "Database migration status"
    )

    XCTAssertEqual(result.kind, .reset)
    XCTAssertEqual(result.confidence, .low)
    XCTAssertEqual(result.addedText, "")
  }

  func testContextExpansionAroundPreviousTextIsAmbiguous() {
    let result = diff(
      previous: "Existing answer",
      current: "Older header Existing answer unrelated footer"
    )

    XCTAssertEqual(result.kind, .ambiguous)
    XCTAssertEqual(result.confidence, .low)
    XCTAssertEqual(result.addedText, "")
  }

  func testEmptyPreviousTextCanProduceAddedText() {
    let result = diff(previous: "", current: "Build succeeded")

    XCTAssertEqual(result.kind, .added)
    XCTAssertEqual(result.confidence, .high)
    XCTAssertEqual(result.addedText, "Build succeeded")
  }

  func testChineseAndEmojiAppendUsesCharacterBoundaries() {
    let result = diff(
      previous: "正在构建项目",
      current: "正在构建项目，已完成 🎉"
    )

    XCTAssertEqual(result.kind, .added)
    XCTAssertEqual(result.confidence, .high)
    XCTAssertEqual(result.addedText, "，已完成 🎉")
  }

  func testEmptyCurrentTextIsConservativeReset() {
    let result = diff(previous: "Visible content", current: "")

    XCTAssertEqual(result.kind, .reset)
    XCTAssertEqual(result.confidence, .low)
    XCTAssertEqual(result.addedText, "")
  }

  private func diff(previous: String, current: String) -> ContextDiffResult {
    engine.diff(
      previous: normalizer.normalize(previous),
      current: normalizer.normalize(current)
    )
  }
}
