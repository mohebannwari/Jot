//
//  ThemeManager.swift
//  Noty
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI
import Combine

#if os(macOS)
import AppKit
#else
import UIKit
#endif

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

class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "AppTheme")
        }
    }
    
    init() {
        let savedTheme = UserDefaults.standard.string(forKey: "AppTheme") ?? AppTheme.system.rawValue
        self.currentTheme = AppTheme(rawValue: savedTheme) ?? .system
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
        #if os(macOS)
        let appearance = NSApp?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
        let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua ? .dark : .light
        #else
        let style = UIScreen.main.traitCollection.userInterfaceStyle
        switch style {
        case .dark:
            return .dark
        case .light:
            return .light
        default:
            return .light
        }
        #endif
    }
}
