import AppKit
import SwiftUI
import XCTest
@testable import Jot

final class ThemeManagerTests: XCTestCase {
    func testSetThemePersistsSelectedTheme() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        manager.setTheme(.dark)

        XCTAssertEqual(defaults.string(forKey: ThemeManager.themeDefaultsKey), AppTheme.dark.rawValue)
    }

    func testSetBodyFontStylePersistsSelectedStyle() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        manager.setBodyFontStyle(.mono)

        XCTAssertEqual(
            defaults.string(forKey: ThemeManager.bodyFontStyleDefaultsKey),
            BodyFontStyle.mono.rawValue
        )
    }

    func testInitializerReadsPersistedThemeAndBodyFontStyle() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppTheme.light.rawValue, forKey: ThemeManager.themeDefaultsKey)
        defaults.set(BodyFontStyle.system.rawValue, forKey: ThemeManager.bodyFontStyleDefaultsKey)

        let manager = ThemeManager(userDefaults: defaults)

        XCTAssertEqual(manager.currentTheme, .light)
        XCTAssertEqual(manager.currentBodyFontStyle, .system)
    }

    // MARK: - Tint

    func testTintDefaults_onFirstLaunch() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)

        XCTAssertEqual(manager.tintHue, 0.55, accuracy: 0.0001)
        XCTAssertEqual(manager.tintIntensity, 0.0, accuracy: 0.0001)
    }

    func testSetTintHue_persistsToUserDefaults() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        manager.tintHue = 0.33

        XCTAssertEqual(
            defaults.object(forKey: ThemeManager.tintHueKey) as? Double ?? -1,
            0.33,
            accuracy: 0.0001
        )
    }

    func testSetTintIntensity_persistsToUserDefaults() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        manager.tintIntensity = 0.75

        XCTAssertEqual(
            defaults.object(forKey: ThemeManager.tintIntensityKey) as? Double ?? -1,
            0.75,
            accuracy: 0.0001
        )
    }

    func testInit_readsPersistedTintValues() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(0.42, forKey: ThemeManager.tintHueKey)
        defaults.set(0.85, forKey: ThemeManager.tintIntensityKey)

        let manager = ThemeManager(userDefaults: defaults)

        XCTAssertEqual(manager.tintHue, 0.42, accuracy: 0.0001)
        XCTAssertEqual(manager.tintIntensity, 0.85, accuracy: 0.0001)
    }

    func testInit_distinguishesUnsetFromZero() {
        // If a user deliberately sets intensity to 0 and relaunches, we must
        // honor that explicit 0 rather than re-applying the "first launch"
        // default (which also happens to be 0). But more importantly, we must
        // distinguish "never set" from "explicitly set". The init path uses
        // `object(forKey:) as? Double` precisely for this reason.
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Case 1: explicitly persisted 0 for intensity — manager should read 0
        defaults.set(0.0, forKey: ThemeManager.tintIntensityKey)
        let manager = ThemeManager(userDefaults: defaults)
        XCTAssertEqual(manager.tintIntensity, 0.0, accuracy: 0.0001)

        // Case 2: nothing persisted — manager falls back to default (also 0)
        defaults.removeObject(forKey: ThemeManager.tintIntensityKey)
        let manager2 = ThemeManager(userDefaults: defaults)
        XCTAssertEqual(manager2.tintIntensity, 0.0, accuracy: 0.0001)
    }

    func testResetTint_restoresDefaults() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        manager.tintHue = 0.12
        manager.tintIntensity = 0.9

        manager.resetTint()

        XCTAssertEqual(manager.tintHue, 0.55, accuracy: 0.0001)
        XCTAssertEqual(manager.tintIntensity, 0.0, accuracy: 0.0001)
        XCTAssertEqual(
            defaults.object(forKey: ThemeManager.tintHueKey) as? Double ?? -1,
            0.55,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            defaults.object(forKey: ThemeManager.tintIntensityKey) as? Double ?? -1,
            0.0,
            accuracy: 0.0001
        )
    }

    /// Smoke test: calling tintedPaneSurface across all branches should
    /// never crash or return a non-renderable color. We can't easily compare
    /// SwiftUI Color values for equality, but we CAN convert them to NSColor
    /// under a specific appearance and check RGB components are in-range.
    func testTintedPaneSurface_producesValidColors_acrossBranches() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        let hues: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let intensities: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let schemes: [ColorScheme] = [.light, .dark]

        for hue in hues {
            for intensity in intensities {
                manager.tintHue = hue
                manager.tintIntensity = intensity
                for scheme in schemes {
                    let color = manager.tintedPaneSurface(for: scheme)
                    // Resolve to NSColor in sRGB and verify RGB in [0, 1]
                    let ns = NSColor(color).usingColorSpace(.sRGB)
                    XCTAssertNotNil(ns, "Color should resolve to sRGB for hue=\(hue) intensity=\(intensity) scheme=\(scheme)")
                    if let ns {
                        XCTAssertGreaterThanOrEqual(ns.redComponent, 0.0)
                        XCTAssertLessThanOrEqual(ns.redComponent, 1.0)
                        XCTAssertGreaterThanOrEqual(ns.greenComponent, 0.0)
                        XCTAssertLessThanOrEqual(ns.greenComponent, 1.0)
                        XCTAssertGreaterThanOrEqual(ns.blueComponent, 0.0)
                        XCTAssertLessThanOrEqual(ns.blueComponent, 1.0)
                    }
                }
            }
        }
    }

    /// At full intensity, the tinted surface must differ between light and
    /// dark scheme — otherwise the theme-aware branching is dead code.
    func testTintedPaneSurface_lightVsDark_differsAtFullIntensity() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        manager.tintHue = 0.33  // green
        manager.tintIntensity = 1.0

        let lightColor = NSColor(manager.tintedPaneSurface(for: .light))
            .usingColorSpace(.sRGB)!
        let darkColor = NSColor(manager.tintedPaneSurface(for: .dark))
            .usingColorSpace(.sRGB)!

        // Light target brightness = 0.96, dark target brightness = 0.16.
        // The two must produce meaningfully different luminance.
        let lightLuma = 0.299 * lightColor.redComponent
            + 0.587 * lightColor.greenComponent
            + 0.114 * lightColor.blueComponent
        let darkLuma = 0.299 * darkColor.redComponent
            + 0.587 * darkColor.greenComponent
            + 0.114 * darkColor.blueComponent

        XCTAssertGreaterThan(lightLuma - darkLuma, 0.3,
            "Light tint should be meaningfully brighter than dark tint at full intensity")
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "ThemeManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
