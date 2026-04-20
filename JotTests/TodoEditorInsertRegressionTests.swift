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

    func testAIEditReplacementUsesCapturedSelectionRange() {
        let harness = makeHarness(initialText: "alpha beta alpha")

        NotificationCenter.default.post(
            name: .aiEditApplyReplacement,
            object: nil,
            userInfo: [
                "editorInstanceID": harness.editorInstanceID,
                "original": "alpha",
                "replacement": "omega",
                "originalRange": NSValue(range: NSRange(location: 11, length: 5)),
            ]
        )

        pumpMainLoop(harness)

        XCTAssertEqual(harness.currentText(), "alpha beta omega")
    }

    func testAIEditReplacementDoesNotFallbackToFirstMatchWhenRangeIsStale() {
        let harness = makeHarness(initialText: "alpha beta alpha")

        NotificationCenter.default.post(
            name: .aiEditApplyReplacement,
            object: nil,
            userInfo: [
                "editorInstanceID": harness.editorInstanceID,
                "original": "alpha",
                "replacement": "omega",
                "originalRange": NSValue(range: NSRange(location: 6, length: 4)),
            ]
        )

        pumpMainLoop(harness)

        XCTAssertEqual(harness.currentText(), "alpha beta alpha")
    }

    func testResolveProofreadAnnotationsRestrictsMatchesToSelectedRange() {
        let text = "typo before\npicked typo typo\ntypo after"
        let nsText = text as NSString
        let selectedRange = nsText.range(of: "picked typo typo")
        let suggestions = [
            ProofreadSuggestion(original: "typo", replacement: "fixed"),
            ProofreadSuggestion(original: "typo", replacement: "fixed"),
            ProofreadSuggestion(original: "before", replacement: "ignored"),
        ]

        let annotations = TodoEditorRepresentable.Coordinator.resolveProofreadAnnotations(
            in: nsText,
            suggestions: suggestions,
            scope: selectedRange
        )

        XCTAssertEqual(annotations.map(\.original), ["typo", "typo"])
        XCTAssertEqual(annotations.count, 2, "Only matches inside the selected range should resolve.")
        XCTAssertTrue(
            annotations.allSatisfy { NSLocationInRange($0.range.location, selectedRange) },
            "Resolved proofread annotations must stay inside the selected range."
        )
        XCTAssertEqual(
            annotations.map(\.range),
            [
                NSRange(location: selectedRange.location + 7, length: 4),
                NSRange(location: selectedRange.location + 12, length: 4),
            ]
        )
    }

    func testResolveProofreadAnnotationsUsesFullDocumentScopeWhenRequested() {
        let text = "alpha beta alpha"
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let suggestions = [
            ProofreadSuggestion(original: "alpha", replacement: "omega"),
            ProofreadSuggestion(original: "alpha", replacement: "omega"),
        ]

        let annotations = TodoEditorRepresentable.Coordinator.resolveProofreadAnnotations(
            in: nsText,
            suggestions: suggestions,
            scope: fullRange
        )

        XCTAssertEqual(
            annotations.map(\.range),
            [
                NSRange(location: 0, length: 5),
                NSRange(location: 11, length: 5),
            ]
        )
    }

    func testProofreadReplacementValidationSkipsStaleRanges() {
        let text = "alpha beta alpha"
        let nsText = text as NSString
        let annotations = [
            ProofreadAnnotation(
                original: "alpha",
                replacement: "omega",
                range: NSRange(location: 11, length: 5)
            ),
            ProofreadAnnotation(
                original: "alpha",
                replacement: "omega",
                range: NSRange(location: 6, length: 4)
            ),
        ]

        let validAnnotations = TodoEditorRepresentable.Coordinator.validProofreadAnnotationsForReplacement(
            in: nsText,
            annotations: annotations
        )

        XCTAssertEqual(validAnnotations.map(\.range), [NSRange(location: 11, length: 5)])
    }

    func testProofreadReplaceAllUsesResolvedAnnotationRangesOnly() {
        let text = "typo before\npicked typo typo\ntypo after"
        let nsText = text as NSString
        let selectedRange = nsText.range(of: "picked typo typo")
        let harness = makeHarness(initialText: text)

        let annotations = TodoEditorRepresentable.Coordinator.resolveProofreadAnnotations(
            in: nsText,
            suggestions: [
                ProofreadSuggestion(original: "typo", replacement: "fixed"),
                ProofreadSuggestion(original: "typo", replacement: "fixed"),
            ],
            scope: selectedRange
        )

        NotificationCenter.default.post(
            name: .aiProofreadReplaceAll,
            object: nil,
            userInfo: [
                "editorInstanceID": harness.editorInstanceID,
                "annotations": annotations,
            ]
        )

        pumpMainLoop(harness)

        XCTAssertEqual(harness.currentText(), "typo before\npicked fixed fixed\ntypo after")
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

    // MARK: - Markdown / divider import cleanup

    /// Divider deserialize must not append an extra `\n` when markup already has one after
    /// `[[divider]]`; serialize round-trip must not grow the document on each open.
    func testDividerSerializeRoundTripIsIdempotent() {
        let markup = "A\n[[divider]]\nB"
        let harness = makeHarness(initialText: markup)
        pumpMainLoop(harness)
        harness.coordinator.flushPendingSerialization()
        let first = harness.currentText()
        harness.coordinator.applyInitialText(first)
        pumpMainLoop(harness)
        harness.coordinator.flushPendingSerialization()
        let second = harness.currentText()
        XCTAssertEqual(
            first,
            second,
            "Opening a note with a divider must not accumulate extra newlines each load; first=\(first.debugDescription) second=\(second.debugDescription)"
        )
        XCTAssertFalse(
            first.contains("\n\n\n"),
            "Divider markup must not create triple newlines"
        )
    }

    /// After container width changes, divider attachment bounds must match (no stale 400pt cell).
    func testDividerAttachmentResizesWithContainerWidth() {
        let harness = makeHarness(initialText: "Line\n[[divider]]\nLine")
        pumpMainLoop(harness)
        guard let storage = harness.textView.textStorage else {
            XCTFail("Missing text storage")
            return
        }

        var dividerAttachment: NoteDividerAttachment?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { value, _, _ in
            if let d = value as? NoteDividerAttachment {
                dividerAttachment = d
            }
        }
        guard let attachment = dividerAttachment else {
            XCTFail("Expected a NoteDividerAttachment in storage")
            return
        }

        let newWidth: CGFloat = 512
        harness.textView.textContainer?.containerSize = NSSize(width: newWidth, height: CGFloat.greatestFiniteMagnitude)
        harness.coordinator.updateDividerAttachments(in: harness.textView)

        XCTAssertEqual(
            attachment.bounds.width,
            newWidth,
            accuracy: 1.0,
            "Divider attachment width should track text container after updateDividerAttachments"
        )
        if let cell = attachment.attachmentCell as? DividerSizeAttachmentCell {
            XCTAssertEqual(cell.displaySize.width, newWidth, accuracy: 1.0, "Divider cell display width should match container")
        }
    }

    /// Heading paragraph spacing must apply to the full paragraph (including trailing newline)
    /// so reload/import does not drop heading vertical rhythm.
    func testHeadingParagraphSpacingAppliedOnFullParagraphRange() {
        let harness = makeHarness(initialText: "[[h1]]Title[[/h1]]\nBody")
        pumpMainLoop(harness)
        guard let storage = harness.textView.textStorage else {
            XCTFail("Missing text storage")
            return
        }
        let paraRange = (storage.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        XCTAssertGreaterThan(paraRange.length, 0, "First paragraph should be non-empty")
        let lastInPara = NSMaxRange(paraRange) - 1
        guard lastInPara >= 0,
              let ps = storage.attribute(.paragraphStyle, at: lastInPara, effectiveRange: nil) as? NSParagraphStyle
        else {
            XCTFail("Expected paragraph style on heading paragraph")
            return
        }
        XCTAssertEqual(ps.paragraphSpacing, 12, accuracy: 0.01)
        XCTAssertEqual(ps.paragraphSpacingBefore, 8, accuracy: 0.01)
    }

    /// Labeled plain-link markup must deserialize to a single attachment with `.plainLinkLabel`.
    func testLabeledLinkDeserializeRendersLabel() {
        let harness = makeHarness(initialText: "[[link|https://x.com|Click]]")
        pumpMainLoop(harness)
        guard let storage = harness.textView.textStorage else {
            XCTFail("Missing text storage")
            return
        }
        var linkCount = 0
        var label: String?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            guard value != nil else { return }
            if storage.attribute(.plainLinkURL, at: range.location, effectiveRange: nil) != nil {
                linkCount += 1
                label = storage.attribute(.plainLinkLabel, at: range.location, effectiveRange: nil) as? String
            }
        }
        XCTAssertEqual(linkCount, 1, "Expected exactly one plain-link attachment")
        XCTAssertEqual(label, "Click")
    }

    // MARK: - Inline-code pill bounds (B1)

    /// Regression: inline-code pill previously used `boundingRect(forGlyphRange:in:)`
    /// directly, which returns line-fragment-sized rects (≈1.5× font size). The pill
    /// fill then extended well above cap-height and below the descender, giving
    /// visible vertical bloat. The helper must compute a tight rect from font metrics.
    func testInlineCodePillRect_HugsFontMetrics_NotLineFragmentHeight() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        // Simulated layout: a 20pt-tall line fragment with the baseline 10pt down.
        let lineRect = CGRect(x: 0, y: 0, width: 500, height: 20)
        let segmentRect = CGRect(x: 100, y: 2, width: 40, height: 16)
        let baselineLocation = CGPoint(x: 0, y: 10)

        let pill = TypingAnimationLayoutManager.inlineCodePillRect(
            lineRect: lineRect,
            segmentRect: segmentRect,
            baselineLocation: baselineLocation,
            font: font
        )

        let expectedHeight = font.capHeight + abs(font.descender) + 3  // 2 × 1.5pt padding
        XCTAssertEqual(pill.height, expectedHeight, accuracy: 0.01,
            "Pill height must hug font metrics (capHeight + |descender| + padding), not line-fragment height")
        XCTAssertLessThan(pill.height, lineRect.height - 2,
            "Pill must be meaningfully shorter than the line-fragment rect (this is the whole B1 fix)")

        let expectedTop = 10 - font.capHeight - 1.5
        XCTAssertEqual(pill.origin.y, expectedTop, accuracy: 0.01,
            "Pill top should sit at baseline − capHeight − padding")

        XCTAssertEqual(pill.width, 40 + 4, accuracy: 0.01,
            "Pill width should equal segment width + 2 × horizontal bleed")
        XCTAssertEqual(pill.origin.x, 100 - 2, accuracy: 0.01,
            "Pill x should sit at segment.x − horizontal bleed")
    }

    // MARK: - Legacy Unicode-arrow deserialize (C1)

    /// Regression: a legacy `\u{2192} ` (arrow + space) at line start must produce a single
    /// arrow attachment with no leftover space before the following text. The deserializer
    /// matched the two-char pattern but only advanced the index by one, so the trailing
    /// space was buffered as plain text on the next iteration — every reload of a pre-existing
    /// note silently grew by one space per arrow.
    func testLegacyUnicodeArrowDeserialize_ConsumesTrailingSpace() {
        let harness = makeHarness(initialText: "\u{2192} hello")
        pumpMainLoop(harness)
        guard let storage = harness.textView.textStorage else {
            XCTFail("Missing text storage")
            return
        }
        let attachment0 = storage.attribute(.attachment, at: 0, effectiveRange: nil)
        XCTAssertTrue(
            attachment0 is NoteArrowAttachment,
            "Position 0 must be a NoteArrowAttachment; got: \(String(describing: attachment0))"
        )
        XCTAssertEqual(
            storage.string,
            "\u{FFFC}hello",
            "Legacy arrow must consume the matched trailing space; got: \(storage.string.debugDescription)"
        )
    }

    /// Imported `[[ol|N]]` must not let bold/heading format state bleed into the visible "N. " prefix run.
    func testOrderedListPrefixIgnoresBoldFormattingState() {
        let harness = makeHarness(initialText: "[[ol|1]][[b]]Bold rest[[/b]]")
        pumpMainLoop(harness)
        guard let storage = harness.textView.textStorage else {
            XCTFail("Missing text storage")
            return
        }
        XCTAssertEqual(storage.string.prefix(3), "1. ", "Got prefix: \(storage.string.prefix(8))")
        let ol = storage.attribute(.orderedListNumber, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(ol, 1)
        let font0 = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font0)
        XCTAssertFalse(
            NSFontManager.shared.traits(of: font0!).contains(.boldFontMask),
            "List number prefix should be regular weight"
        )
        let fontBold = storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        XCTAssertTrue(
            NSFontManager.shared.traits(of: fontBold!).contains(.boldFontMask),
            "Text after prefix should stay bold"
        )
        guard let ps = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle else {
            XCTFail("Expected paragraph style on ordered-list line")
            return
        }
        XCTAssertGreaterThan(ps.headIndent, 0)
    }
}
