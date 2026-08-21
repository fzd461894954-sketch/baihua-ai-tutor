import XCTest

@testable import AITutorMac

final class TextNormalizerTests: XCTestCase {
  private let normalizer = TextNormalizer()
  private let fingerprinter = ContextFingerprinter()

  func testCanonicalizesUnicodeNewlinesInvisibleCharactersAndWhitespace() {
    let result = normalizer.normalize(
      "  Cafe\u{301}\r\nhello\u{200B}\t world \r\n\r\n\r\n next\u{00A0}line "
    )

    XCTAssertEqual(result.displayText, "Café\nhello world\n\nnext line")
    XCTAssertEqual(result.comparisonText, "Café hello world\n\nnext line")
  }

  func testSoftLineWrappingDoesNotChangeComparisonTextOrFingerprint() {
    let wrapped = normalizer.normalize("The build is\nstill running")
    let singleLine = normalizer.normalize("The build is still running")

    XCTAssertNotEqual(wrapped.displayText, singleLine.displayText)
    XCTAssertEqual(wrapped.comparisonText, singleLine.comparisonText)
    XCTAssertEqual(
      fingerprinter.fingerprint(wrapped),
      fingerprinter.fingerprint(singleLine)
    )
  }

  func testParagraphBoundaryRemainsMeaningful() {
    let paragraphBreak = normalizer.normalize("First paragraph\n\nSecond paragraph")
    let softWrap = normalizer.normalize("First paragraph\nSecond paragraph")

    XCTAssertEqual(
      paragraphBreak.comparisonText,
      "First paragraph\n\nSecond paragraph"
    )
    XCTAssertEqual(softWrap.comparisonText, "First paragraph Second paragraph")
    XCTAssertNotEqual(
      fingerprinter.fingerprint(paragraphBreak),
      fingerprinter.fingerprint(softWrap)
    )
  }

  func testFencedCodePreservesIndentationAndLineBreaks() {
    let result = normalizer.normalize(
      "```swift\r\n  let value = 1\t \r\n\tprint(value)\r\n```"
    )

    XCTAssertEqual(
      result.displayText,
      "```swift\n  let value = 1\n\tprint(value)\n```"
    )
    XCTAssertEqual(result.comparisonText, result.displayText)

    let differentIndentation = normalizer.normalize(
      "```swift\nlet value = 1\n\tprint(value)\n```"
    )
    XCTAssertNotEqual(
      fingerprinter.fingerprint(result),
      fingerprinter.fingerprint(differentIndentation)
    )
  }

  func testFingerprintIsDeterministicSHA256() {
    let text = normalizer.normalize("你好, context")
    let first = fingerprinter.fingerprint(text)
    let second = fingerprinter.fingerprint(text)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.rawValue.count, 64)
    XCTAssertTrue(first.rawValue.allSatisfy { $0.isHexDigit })
  }
}
