//
//  ThemeManager.swift
//  Jot
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI
import Combine

import AppKit

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum BodyFontStyle: String, CaseIterable {
    case `default` = "default"
    case system = "system"
    case mono = "mono"

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .system: return "System"
        case .mono: return "Mono"
        }
    }
}

final class ThemeManager: ObservableObject {
    static let themeDefaultsKey = "AppTheme"
    static let bodyFontStyleDefaultsKey = "AppBodyFontStyle"

    private let userDefaults: UserDefaults
    private var appearanceObserver: NSKeyValueObservation?

    @Published var currentTheme: AppTheme {
        didSet {
            userDefaults.set(currentTheme.rawValue, forKey: Self.themeDefaultsKey)
            applyAppKitAppearance(currentTheme)
            updateResolvedColorScheme()
        }
    }

    /// Always non-nil — resolves "system" to the actual system scheme.
    /// Use this for `preferredColorScheme` instead of passing nil.
    @Published private(set) var resolvedColorScheme: ColorScheme = .light

    @Published var currentBodyFontStyle: BodyFontStyle {
        didSet {
            userDefaults.set(currentBodyFontStyle.rawValue, forKey: Self.bodyFontStyleDefaultsKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let savedTheme =
            userDefaults.string(forKey: Self.themeDefaultsKey) ?? AppTheme.system.rawValue
        self.currentTheme = AppTheme(rawValue: savedTheme) ?? .system

        let savedBodyFontStyle =
            userDefaults.string(forKey: Self.bodyFontStyleDefaultsKey) ?? BodyFontStyle.default.rawValue
        self.currentBodyFontStyle = BodyFontStyle(rawValue: savedBodyFontStyle) ?? .default

        // didSet doesn't fire during init — apply manually
        applyAppKitAppearance(self.currentTheme)
        resolvedColorScheme = Self.resolveColorScheme(for: self.currentTheme)

        // Track system appearance changes so "System" mode stays in sync
        appearanceObserver = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateResolvedColorScheme()
            }
        }
    }

    func toggleTheme() {
        let sequence = orderedThemes()
        guard let currentIndex = sequence.firstIndex(of: currentTheme) else { return }
        let nextIndex = (currentIndex + 1) % sequence.count
        currentTheme = sequence[nextIndex]
    }

    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }

    func setBodyFontStyle(_ bodyFontStyle: BodyFontStyle) {
        currentBodyFontStyle = bodyFontStyle
    }

    // MARK: - Private

    private func applyAppKitAppearance(_ theme: AppTheme) {
        switch theme {
        case .system:
            NSApp?.appearance = nil
        case .light:
            NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func updateResolvedColorScheme() {
        let resolved = Self.resolveColorScheme(for: currentTheme)
        if resolvedColorScheme != resolved {
            resolvedColorScheme = resolved
        }
    }

    private static func resolveColorScheme(for theme: AppTheme) -> ColorScheme {
        switch theme {
        case .system:
            let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func orderedThemes() -> [AppTheme] {
        let systemScheme = Self.resolveColorScheme(for: .system)
        if systemScheme == .light {
            return [.system, .dark, .light]
        } else {
            return [.system, .light, .dark]
        }
    }
}
