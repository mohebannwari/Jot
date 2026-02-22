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
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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

    @Published var currentTheme: AppTheme {
        didSet {
            userDefaults.set(currentTheme.rawValue, forKey: Self.themeDefaultsKey)
        }
    }

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

    func resetToSystemTheme() {
        currentTheme = .system
    }

    private func orderedThemes() -> [AppTheme] {
        let systemTheme = resolvedSystemTheme()
        if systemTheme == .light {
            return [.system, .dark, .light]
        } else {
            return [.system, .light, .dark]
        }
    }

    private func resolvedSystemTheme() -> AppTheme {
        let appearance = NSApp?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
        let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua ? .dark : .light
    }
}
