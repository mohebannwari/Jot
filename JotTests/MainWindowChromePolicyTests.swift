import XCTest
@testable import Jot

final class MainWindowChromePolicyTests: XCTestCase {

    func testMacOS26BackdropStaysGlassWhenTranslucencyIsOff() {
        let state = MainWindowChromePolicy.state(
            detailPaneTranslucency: 0.0,
            reduceTransparency: false,
            supportsLiquidGlass: true
        )

        XCTAssertEqual(state.backdropStyle, .modernUnifiedTranslucent)
        XCTAssertEqual(state.surfaceStyle(for: .sidebar), .modernTranslucentGlass)
        XCTAssertEqual(state.surfaceStyle(for: .editor), .opaqueFill)
        XCTAssertEqual(state.surfaceStyle(for: .properties), .opaqueFill)
        XCTAssertEqual(state.surfaceStyle(for: .settings), .opaqueFill)
        XCTAssertTrue(state.usesUnifiedTranslucentBackdrop)
        XCTAssertFalse(state.usesTransparentDetailChrome)
    }

    func testModernUnifiedTranslucencyWhenLiquidGlassIsAvailable() {
        let state = MainWindowChromePolicy.state(
            detailPaneTranslucency: 0.72,
            reduceTransparency: false,
            supportsLiquidGlass: true
        )

        XCTAssertEqual(state.backdropStyle, .modernUnifiedTranslucent)
        for role in MainChromeSurfaceRole.allCases {
            XCTAssertEqual(state.surfaceStyle(for: role), .modernTranslucentGlass)
        }
        XCTAssertTrue(state.usesUnifiedTranslucentBackdrop)
        XCTAssertTrue(state.usesModernTranslucentGlass)
        XCTAssertTrue(state.usesTransparentDetailChrome)
    }

    func testLegacyUnifiedBlurFallbackWhenLiquidGlassIsUnavailable() {
        let state = MainWindowChromePolicy.state(
            detailPaneTranslucency: 0.72,
            reduceTransparency: false,
            supportsLiquidGlass: false
        )

        XCTAssertEqual(state.backdropStyle, .legacyUnifiedBlurTint)
        for role in MainChromeSurfaceRole.allCases {
            XCTAssertEqual(state.surfaceStyle(for: role), .legacyTranslucentBlur)
        }
        XCTAssertTrue(state.usesUnifiedTranslucentBackdrop)
        XCTAssertFalse(state.usesModernTranslucentGlass)
    }

    func testLegacyBackdropPersistsWhenTranslucencyIsOff() {
        let state = MainWindowChromePolicy.state(
            detailPaneTranslucency: 0.0,
            reduceTransparency: false,
            supportsLiquidGlass: false
        )

        XCTAssertEqual(state.backdropStyle, .legacyUnifiedBlurTint)
        XCTAssertEqual(state.surfaceStyle(for: .sidebar), .legacyTranslucentBlur)
        XCTAssertEqual(state.surfaceStyle(for: .editor), .opaqueFill)
        XCTAssertEqual(state.surfaceStyle(for: .properties), .opaqueFill)
        XCTAssertEqual(state.surfaceStyle(for: .settings), .opaqueFill)
        XCTAssertTrue(state.usesUnifiedTranslucentBackdrop)
        XCTAssertFalse(state.usesTransparentDetailChrome)
    }

    func testReduceTransparencyForcesOpaqueMode() {
        let state = MainWindowChromePolicy.state(
            detailPaneTranslucency: 1.0,
            reduceTransparency: true,
            supportsLiquidGlass: true
        )

        XCTAssertEqual(state.backdropStyle, .opaqueTintedWindow)
        for role in MainChromeSurfaceRole.allCases {
            XCTAssertEqual(state.surfaceStyle(for: role), .opaqueFill)
        }
    }
}
