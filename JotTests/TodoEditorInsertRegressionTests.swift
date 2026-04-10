import XCTest
import SwiftUI
@testable import Jot

@MainActor
final class TodoEditorInsertRegressionTests: XCTestCase {

    private struct EditorHarness {
        let coordinator: TodoEditorRepresentable.Coordinator
        let editorInstanceID: UUID
        let textView: InlineNSTextView
        let syncCount: () -> Int
        let currentText: () -> String
    }

    private func makeHarness(initialText: String) -> EditorHarness {
        let editorInstanceID = UUID()
        var textValue = initialText
        var bindingWriteCount = 0

        let binding = Binding<String>(
            get: { textValue },
            set: { newValue in
                textValue = newValue
                bindingWriteCount += 1
            }
        )

        let coordinator = TodoEditorRepresentable.Coordinator(
            text: binding,
            colorScheme: .light,
            focusRequestID: nil,
            editorInstanceID: editorInstanceID,
            readOnly: false
        )

        let textView = InlineNSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.delegate = coordinator
        textView.actionDelegate = coordinator
        textView.editorInstanceID = editorInstanceID
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = FontManager.bodyNS(size: ThemeManager.currentBodyFontSize(), weight: .regular)
        textView.textContainerInset = NSSize(width: 28, height: 16)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.typingAttributes = TodoEditorRepresentable.Coordinator.baseTypingAttributes(for: .light)
        textView.defaultParagraphStyle = TodoEditorRepresentable.Coordinator.baseParagraphStyle()

        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            container.lineFragmentPadding = 0
            container.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        }

        coordinator.updateColorScheme(.light)
        coordinator.configure(with: textView)
        coordinator.applyInitialText(initialText)

        if let container = textView.textContainer,
           let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: container)
        }

        return EditorHarness(
            coordinator: coordinator,
            editorInstanceID: editorInstanceID,
            textView: textView,
            syncCount: { bindingWriteCount },
            currentText: { textValue }
        )
    }

    /// Drains the main run loop and then flushes the Coordinator's debounced
    /// serialization so tests can assert on the binding state deterministically.
    /// `syncText` in production defers binding writes by 150 ms to coalesce
    /// keystroke noise; without an explicit flush the 50 ms pump would return
    /// before the debounced work item fires and the binding would still be stale.
    private func pumpMainLoop(_ harness: EditorHarness) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        harness.coordinator.flushPendingSerialization()
    }

    func testCommandMenuTableInsertPerformsSingleBindingSync() {
        let harness = makeHarness(initialText: "/")

        NotificationCenter.default.post(
            name: .applyCommandMenuTool,
            object: [
                "tool": EditTool.table,
                "slashLocation": 0,
                "filterLength": 0,
            ],
            userInfo: ["editorInstanceID": harness.editorInstanceID]
        )

        pumpMainLoop(harness)

        XCTAssertEqual(
            harness.syncCount(),
            1,
            "Selecting a table from the slash menu should behave like one atomic insert, not multiple intermediate binding syncs."
        )
        XCTAssertFalse(
            harness.currentText().isEmpty,
            "The slash command insert should leave serialized editor content behind."
        )
    }

    func testToolbarTableInsertCreatesOverlayOnFirstInsert() {
        let harness = makeHarness(initialText: "")

        NotificationCenter.default.post(
            name: .applyEditTool,
            object: nil,
            userInfo: [
                "editorInstanceID": harness.editorInstanceID,
                "tool": EditTool.table.rawValue,
            ]
        )

        pumpMainLoop(harness)

        let hasTableOverlay = harness.textView.subviews.contains { $0 is NoteTableOverlayView }
        XCTAssertTrue(
            hasTableOverlay,
            "A single toolbar table insert should create its overlay immediately, because the attachment cell itself intentionally draws nothing."
        )
    }

    func testCommandMenuDividerInsertPerformsSingleBindingSync() {
        let harness = makeHarness(initialText: "/")

        NotificationCenter.default.post(
            name: .applyCommandMenuTool,
            object: [
                "tool": EditTool.divider,
                "slashLocation": 0,
                "filterLength": 0,
            ],
            userInfo: ["editorInstanceID": harness.editorInstanceID]
        )

        pumpMainLoop(harness)

        XCTAssertEqual(
            harness.syncCount(),
            1,
            "Selecting a divider from the slash menu should sync the binding once after the final document state is ready."
        )
        XCTAssertFalse(
            harness.currentText().isEmpty,
            "The divider insert should leave serialized editor content behind."
        )
    }

    /// Regression: cursor on the newline after a callout used to trip `shouldChangeTextIn`'s
    /// "typing beside block" path because the replacement string for a tabs insert contains
    /// U+FFFC. That redirected the insert and fought `insertTabs`, producing the two-click /
    /// invisible-block symptom (see debug run H6).
    func testTabsInsertAfterCalloutAddsSingleSerializedBlockAndOverlay() {
        let calloutMarkup = CalloutData.empty().serialize()
        let harness = makeHarness(initialText: calloutMarkup + "\n")

        NotificationCenter.default.post(
            name: .applyEditTool,
            object: nil,
            userInfo: [
                "editorInstanceID": harness.editorInstanceID,
                "tool": EditTool.tabs.rawValue,
            ]
        )

        pumpMainLoop(harness)

        let text = harness.currentText()
        let tabsBlocks = text.components(separatedBy: "[[tabs|").count - 1
        let calloutBlocks = text.components(separatedBy: "[[callout|").count - 1
        XCTAssertEqual(calloutBlocks, 1, "Existing callout should remain a single block")
        XCTAssertEqual(tabsBlocks, 1, "One toolbar action should insert exactly one tabs block")

        let tabsOverlayViews = harness.textView.subviews.filter { $0 is TabsContainerOverlayView }
        XCTAssertEqual(
            tabsOverlayViews.count,
            1,
            "Tabs rely on an overlay view; the first insert must create it immediately."
        )
    }

    func testTableOverlayRebuildsAfterLayoutInvalidation() {
        let harness = makeHarness(initialText: "")

        NotificationCenter.default.post(
            name: .applyEditTool,
            object: nil,
            userInfo: [
                "editorInstanceID": harness.editorInstanceID,
                "tool": EditTool.table.rawValue,
            ]
        )

        pumpMainLoop(harness)

        harness.coordinator.removeAllOverlays()
        let fullRange = NSRange(location: 0, length: harness.textView.textStorage?.length ?? 0)
        harness.textView.layoutManager?.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)

        harness.coordinator.updateTableOverlays(in: harness.textView)

        let hasTableOverlay = harness.textView.subviews.contains { $0 is NoteTableOverlayView }
        XCTAssertTrue(
            hasTableOverlay,
            "Table overlays should rebuild immediately even after the text layout has been invalidated."
        )
    }

    // MARK: - First-Line Cursor Skip Regression

    /// Regression: typing the first character in a brand-new empty note must not
    /// skip the first line. The character should appear at position 0 with the
    /// cursor immediately after it, and no spurious newlines should be injected.
    func testFirstCharacterOnEmptyNoteStaysOnFirstLine() {
        let harness = makeHarness(initialText: "")
        let textView = harness.textView

        // Pre-condition: storage is truly empty
        XCTAssertEqual(textView.textStorage?.length ?? -1, 0,
            "Empty note should start with zero-length storage")

        // Simulate typing "a" at position 0
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
        pumpMainLoop(harness)

        let text = textView.textStorage?.string ?? ""

        // 1. No spurious newlines
        XCTAssertFalse(text.hasPrefix("\n"),
            "Text must not start with a newline after typing the first character")
        XCTAssertEqual(text.components(separatedBy: "\n").count, 1,
            "Single character insertion must not inject any newlines; got: \(text.debugDescription)")

        // 2. Correct cursor position
        let cursorPos = textView.selectedRange().location
        XCTAssertEqual(cursorPos, 1,
            "Cursor should be at position 1 (after the typed character)")

        // 3. The character's glyph sits on the very first line fragment
        if let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: textView.textContainer!)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: 0)
            let lineOrigin = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex, effectiveRange: nil).origin
            XCTAssertEqual(lineOrigin.y, 0, accuracy: 1.0,
                "First character glyph should be on line fragment at y~0, got y=\(lineOrigin.y)")
        }

        // 4. Serialized output matches expectations
        XCTAssertEqual(harness.currentText(), "a",
            "Serialized binding should contain exactly the typed character")
    }

    /// Simulates a Return key arriving at the editor right before the first
    /// real character — mirrors the title-to-editor focus transition where
    /// the Return keypress may leak through the responder chain.
    func testReturnKeyLeakBeforeFirstCharacterDoesNotCorruptContent() {
        let harness = makeHarness(initialText: "")
        let textView = harness.textView

        // Simulate a Return key arriving (as if leaked from title field transition)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        pumpMainLoop(harness)

        // The empty-document guard should have blocked the newline
        XCTAssertEqual(textView.textStorage?.length ?? -1, 0,
            "Return into empty document should be rejected")

        // Then simulate the user typing their first real character
        textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
        pumpMainLoop(harness)

        let finalText = textView.textStorage?.string ?? ""
        XCTAssertEqual(finalText, "a",
            "First character should appear without a leading newline; got: \(finalText.debugDescription)")
        XCTAssertEqual(textView.selectedRange().location, 1,
            "Cursor should be at position 1 after typing 'a'")
    }

    /// Typing multiple characters rapidly into an empty note should keep
    /// everything on the first line with no injected newlines.
    func testRapidTypingInEmptyNoteStaysOnFirstLine() {
        let harness = makeHarness(initialText: "")
        let textView = harness.textView

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        for char in "hello" {
            textView.insertText(String(char), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        pumpMainLoop(harness)

        let text = textView.textStorage?.string ?? ""
        XCTAssertEqual(text, "hello",
            "Rapid typing should produce 'hello' with no injected newlines; got: \(text.debugDescription)")
        XCTAssertEqual(textView.selectedRange().location, 5,
            "Cursor should be at end of typed text")
    }
}
