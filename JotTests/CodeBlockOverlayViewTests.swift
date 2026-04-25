import AppKit
import SwiftUI
import XCTest

@testable import Jot

@MainActor
final class CodeBlockOverlayViewTests: XCTestCase {

    private func scrollEvent(deltaX: Int32, deltaY: Int32 = 0) -> NSEvent {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ).flatMap(NSEvent.init(cgEvent:))
        return event!
    }

    func testBlockBodyUsesDarkDetailPaneWhenHostTextViewIsDarkAqua() {
        let textView = InlineNSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        textView.appearance = NSAppearance(named: .darkAqua)!
        let overlay = CodeBlockOverlayView(codeBlockData: CodeBlockData.empty())
        overlay.parentTextView = textView
        textView.addSubview(overlay)
        overlay.frame = NSRect(x: 20, y: 20, width: 420, height: 180)
        overlay.layoutSubtreeIfNeeded()

        guard let cg = overlay.testability_blockBodyLayerBackgroundColor,
              let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else {
            XCTFail("Expected block body layer background")
            return
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Light DetailPane (~#E7E5E4) was incorrectly baked while syntax stayed dark — this guards that regression.
        XCTAssertLessThan(r, 0.35, "Red channel should match dark pane, not light DetailPane (~0.91)")
        XCTAssertLessThan(g, 0.35)
        XCTAssertLessThan(b, 0.35)
    }

    func testBlockBodySurfaceTokenIsBrightUnderExplicitAquaAppearance() {
        // Headless tests may leave ``NSTextView.effectiveAppearance`` dark; assert the resolver directly with an explicit aqua.
        guard let aqua = NSAppearance(named: .aqua) else {
            XCTFail("Expected .aqua appearance")
            return
        }
        let cg = CodeBlockOverlayView.testability_blockBodySurfaceCGColor(isDark: false, appearance: aqua)
        guard let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else {
            XCTFail("Expected sRGB color")
            return
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)

        XCTAssertGreaterThan(r + g + b, 2.4, "Light scheme body should read as a bright surface")
    }

    func testCodeBodyScrollersStayOverlayAndAutohidingWhenSystemRequestsLegacyScrollbars() {
        let overlay = CodeBlockOverlayView(codeBlockData: CodeBlockData(
            language: "swift",
            code: String(repeating: "let oversizedLine = \"scroll horizontally\" ", count: 12),
            preferredContentWidth: nil
        ))

        XCTAssertTrue(overlay.testability_codeBodyScrollViewAutohidesScrollers)

        overlay.testability_forceCodeBodyScrollerStyle(.legacy)

        XCTAssertEqual(overlay.testability_codeBodyScrollerStyle, .overlay)
        XCTAssertTrue(overlay.testability_codeBodyScrollViewAutohidesScrollers)
    }

    func testHorizontalWheelOverCodeTextScrollsCodeBody() {
        let overlay = CodeBlockOverlayView(codeBlockData: CodeBlockData(
            language: "bash",
            code: String(repeating: "cd project && xcodebuild ", count: 16),
            preferredContentWidth: nil
        ))
        overlay.frame = NSRect(x: 0, y: 0, width: 420, height: CodeBlockOverlayView.heightForData(overlay.codeBlockData, width: 420))
        overlay.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(overlay.testability_codeBodyDocumentWidth, overlay.testability_codeBodyClipWidth)
        XCTAssertEqual(overlay.testability_codeBodyScrollOriginX, 0)

        overlay.testability_scrollCodeBodyTextViewHorizontally(deltaX: -120)

        XCTAssertGreaterThan(overlay.testability_codeBodyScrollOriginX, 0)
    }

    func testDiagonalWheelAtHorizontalEdgeFallsThroughForVerticalScroll() {
        let overlay = CodeBlockOverlayView(codeBlockData: CodeBlockData(
            language: "bash",
            code: String(repeating: "cd project && xcodebuild ", count: 16),
            preferredContentWidth: nil
        ))
        overlay.frame = NSRect(x: 0, y: 0, width: 420, height: CodeBlockOverlayView.heightForData(overlay.codeBlockData, width: 420))
        overlay.layoutSubtreeIfNeeded()

        for _ in 0..<20 {
            _ = overlay.scrollCodeBodyHorizontally(with: scrollEvent(deltaX: -240))
        }
        let edgeOriginX = overlay.testability_codeBodyScrollOriginX
        XCTAssertGreaterThan(edgeOriginX, 0)

        let handled = overlay.scrollCodeBodyHorizontally(with: scrollEvent(deltaX: -120, deltaY: -40))

        XCTAssertFalse(handled, "Vertical wheel delta should fall through when horizontal scrolling is already pinned at the edge")
        XCTAssertEqual(overlay.testability_codeBodyScrollOriginX, edgeOriginX)
    }

    func testOuterEditorWheelInsideCodeBlockRedirectsToCodeBody() {
        let editor = InlineNSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 240))
        let coordinator = TodoEditorRepresentable.Coordinator(
            text: .constant(""),
            colorScheme: .dark,
            focusRequestID: nil
        )
        editor.actionDelegate = coordinator

        let overlay = CodeBlockOverlayView(codeBlockData: CodeBlockData(
            language: "bash",
            code: String(repeating: "cd project && xcodebuild ", count: 16),
            preferredContentWidth: nil
        ))
        overlay.frame = NSRect(
            x: 40,
            y: 30,
            width: 420,
            height: CodeBlockOverlayView.heightForData(overlay.codeBlockData, width: 420)
        )
        editor.addSubview(overlay)
        overlay.layoutSubtreeIfNeeded()
        coordinator.codeBlockOverlays[ObjectIdentifier(overlay)] = overlay

        XCTAssertEqual(overlay.testability_codeBodyScrollOriginX, 0)

        let pointInsideOverlay = CGPoint(x: overlay.frame.midX, y: overlay.frame.maxY - 18)
        let handled = coordinator.scrollCodeBlockOverlay(
            at: pointInsideOverlay,
            in: editor,
            event: scrollEvent(deltaX: -120)
        )

        XCTAssertTrue(handled)
        XCTAssertGreaterThan(overlay.testability_codeBodyScrollOriginX, 0)
    }
}
