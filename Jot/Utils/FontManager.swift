//
//  FontManager.swift
//  Jot
//
//  Created by Moheb Anwari on 10.10.25.
//
//  Centralized font management for consistent typography across the app.
//  This manager provides three font families as per design requirements:
//  1. Charter - for body text and content
//  2. SF Pro Compact - for headings and note names
//  3. SF Mono - for metadata like dates and timestamps

import SwiftUI

import AppKit

/// Centralized font manager providing consistent typography across the application
struct FontManager {
    nonisolated private static func currentBodyFontStyle(
        userDefaults: UserDefaults = .standard
    ) -> BodyFontStyle {
        let rawValue =
            userDefaults.string(forKey: ThemeManager.bodyFontStyleDefaultsKey) ?? BodyFontStyle.default.rawValue
        return BodyFontStyle(rawValue: rawValue) ?? .default
    }

    /// Optical size compensation so SF Pro and SF Mono visually match Charter at the same nominal size.
    /// Charter has a larger x-height than system fonts; scaling up non-Charter variants equalises them.
    static let opticalSizeCompensation: CGFloat = 16.0 / 15.0  // ≈ 1.067

    // MARK: - Body Text Fonts (Charter)

    /// Primary body text font using Charter
    /// Use for: Note content, editor text, paragraph text
    static func body(size: CGFloat = 16, weight: Weight = .regular) -> Font {
        switch currentBodyFontStyle() {
        case .default:
            // Charter is a system font on macOS/iOS
            return Font.custom("Charter", size: size)
                .weight(weight.toSwiftUIWeight())
        case .system:
            return Font.system(size: size * opticalSizeCompensation, weight: weight.toSwiftUIWeight(), design: .default)
        case .mono:
            return Font.system(size: size * opticalSizeCompensation, weight: weight.toSwiftUIWeight(), design: .monospaced)
        }
    }

    /// NSFont version for AppKit components
    nonisolated static func bodyNS(size: CGFloat = 16, weight: Weight = .regular) -> NSFont {
        switch currentBodyFontStyle() {
        case .default:
            // Try Charter first, fall back to Georgia (similar serif), then system
            if let charter = NSFont(name: "Charter-\(weight.toCharterName())", size: size) {
                return charter
            } else if let charter = NSFont(name: "Charter", size: size) {
                // Apply weight transformation if base Charter font is available
                let descriptor = charter.fontDescriptor.withSymbolicTraits(weight.toNSSymbolicTraits())
                return NSFont(descriptor: descriptor, size: size) ?? charter
            } else if let georgia = NSFont(name: "Georgia", size: size) {
                return georgia
            }
            return NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
        case .system:
            return NSFont.systemFont(ofSize: size * opticalSizeCompensation, weight: weight.toNSWeight())
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: size * opticalSizeCompensation, weight: weight.toNSWeight())
        }
    }
    
    // MARK: - Heading Fonts (SF Pro Compact)
    
    /// Heading and note title font using SF Pro Compact
    /// Use for: Note titles, headings, section headers, prominent text
    static func heading(size: CGFloat = 24, weight: Weight = .medium) -> Font {
        return Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .default)
            .leading(.tight)
    }
    
    /// NSFont version for AppKit headings.
    /// Follows the user's body font style setting so headings stay visually coherent
    /// with the surrounding text (Charter → Charter bold, Mono → monospaced, System → SF Pro).
    nonisolated static func headingNS(size: CGFloat = 24, weight: Weight = .medium) -> NSFont {
        switch currentBodyFontStyle() {
        case .default:
            // Use Charter at heading weight, matching body font family
            if let charter = NSFont(name: "Charter-Bold", size: size) {
                return charter
            } else if let charter = NSFont(name: "Charter", size: size) {
                let descriptor = charter.fontDescriptor.withSymbolicTraits(.bold)
                return NSFont(descriptor: descriptor, size: size) ?? charter
            }
            // Fallback: system font
            return NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
        case .system:
            // SF Pro Compact for system font choice
            if let compact = NSFont(name: ".AppleSystemUIFontCompact", size: size) {
                return compact
            }
            return NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
        case .mono:
            // 16/15 ≈ 1.067 — same optical size compensation as bodyNS, inlined to avoid main-actor access
            return NSFont.monospacedSystemFont(ofSize: size * (16.0 / 15.0), weight: weight.toNSWeight())
        }
    }

    // MARK: - Metadata Fonts (SF Mono)
    
    /// Metadata font using SF Mono for dates, timestamps, and technical info
    /// Use for: Dates, timestamps, metadata, monospaced technical text
    static func metadata(size: CGFloat = 12, weight: Weight = .medium) -> Font {
        return Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .monospaced)
    }

    // MARK: - Icon Fonts

    /// Standard icon font for UI/action symbols across the app.
    static func icon(size: CGFloat = 20, weight: Weight = .regular) -> Font {
        Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .default)
    }
    
    /// NSFont version for AppKit metadata
    static func metadataNS(size: CGFloat = 12, weight: Weight = .medium) -> NSFont {
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight.toNSWeight())
    }
    
    // MARK: - Weight Enum
    
    /// Font weight enumeration for consistent weight handling across platforms
    enum Weight {
        case regular
        case medium
        case semibold
        case bold
        
        nonisolated func toSwiftUIWeight() -> Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
        
        nonisolated func toNSWeight() -> NSFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }

        nonisolated func toNSSymbolicTraits() -> NSFontDescriptor.SymbolicTraits {
            switch self {
            case .bold: return .bold
            default: return []
            }
        }
        
        nonisolated func toCharterName() -> String {
            switch self {
            case .regular: return "Roman"
            case .medium: return "Roman"  // Charter doesn't have medium, use Roman
            case .semibold: return "Bold"
            case .bold: return "Bold"
            }
        }
    }
}
