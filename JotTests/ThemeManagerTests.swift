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

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "ThemeManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
