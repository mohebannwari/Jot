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

    private func pumpMainLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
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

        pumpMainLoop()

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

        pumpMainLoop()

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

        pumpMainLoop()

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
}
