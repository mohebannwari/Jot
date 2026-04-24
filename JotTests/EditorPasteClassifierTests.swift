import XCTest
@testable import Jot

final class EditorPasteClassifierTests: XCTestCase {
    func testLikelyURLRequiresWholeTrimmedStringToBeTheURL() {
        XCTAssertTrue(EditorPasteClassifier.isLikelyURL(" https://example.com/path?q=1 "))
        XCTAssertFalse(EditorPasteClassifier.isLikelyURL("see https://example.com"))
        XCTAssertFalse(EditorPasteClassifier.isLikelyURL("https://example.com and text"))
    }

    func testFirstURLFindsURLInsideArbitraryText() {
        XCTAssertEqual(
            EditorPasteClassifier.firstURL(in: "Open https://example.com/docs today")?.absoluteString,
            "https://example.com/docs"
        )
        XCTAssertNil(EditorPasteClassifier.firstURL(in: "no links here"))
    }

    func testClassifyCodeDetectsSwiftPaste() {
        let code = """
        import SwiftUI

        struct Card: View {
            var body: some View { Text("Hi") }
        }
        """

        let result = EditorPasteClassifier.classifyCode(code)

        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "swift")
    }

    func testClassifyCodeRejectsPlainMarkdownProse() {
        let text = """
        # Plan

        This is a short paragraph with ordinary words and no real code structure.
        """

        let result = EditorPasteClassifier.classifyCode(text)

        XCTAssertFalse(result.isCode)
        XCTAssertEqual(result.language, "plaintext")
    }
}
