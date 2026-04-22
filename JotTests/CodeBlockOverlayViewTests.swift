import AppKit
import XCTest

@testable import Jot

@MainActor
final class CodeBlockOverlayViewTests: XCTestCase {

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
}
