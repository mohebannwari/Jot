//
//  FontManager.swift
//  Noty
//
//  Created by Moheb Anwari on 10.10.25.
//
//  Centralized font management for consistent typography across the app.
//  This manager provides three font families as per design requirements:
//  1. Charter - for body text and content
//  2. SF Pro Compact - for headings and note names
//  3. SF Mono - for metadata like dates and timestamps

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Centralized font manager providing consistent typography across the application
struct FontManager {
    
    // MARK: - Body Text Fonts (Charter)
    
    /// Primary body text font using Charter
    /// Use for: Note content, editor text, paragraph text
    static func body(size: CGFloat = 16, weight: Weight = .regular) -> Font {
        // Charter is a system font on macOS/iOS
        return Font.custom("Charter", size: size)
            .weight(weight.toSwiftUIWeight())
    }
    
    #if os(macOS)
    /// NSFont version for AppKit components
    nonisolated static func bodyNS(size: CGFloat = 16, weight: Weight = .regular) -> NSFont {
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
    }
    #else
    /// UIFont version for UIKit components
    static func bodyUI(size: CGFloat = 16, weight: Weight = .regular) -> UIFont {
        // Try Charter first, fall back to Georgia (similar serif), then system
        if let charter = UIFont(name: "Charter-\(weight.toCharterName())", size: size) {
            return charter
        } else if let charter = UIFont(name: "Charter", size: size) {
            return charter
        } else if let georgia = UIFont(name: "Georgia", size: size) {
            return georgia
        }
        return UIFont.systemFont(ofSize: size, weight: weight.toUIWeight())
    }
    #endif
    
    // MARK: - Heading Fonts (SF Pro Compact)
    
    /// Heading and note title font using SF Pro Compact
    /// Use for: Note titles, headings, section headers, prominent text
    static func heading(size: CGFloat = 24, weight: Weight = .medium) -> Font {
        return Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .default)
            .leading(.tight)
    }
    
    #if os(macOS)
    /// NSFont version for AppKit headings
    static func headingNS(size: CGFloat = 24, weight: Weight = .medium) -> NSFont {
        // SF Pro Compact on macOS
        if let compact = NSFont(name: ".AppleSystemUIFontCompact", size: size) {
            return compact
        }
        // Fallback to standard SF Pro with weight
        return NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
    }
    #else
    /// UIFont version for UIKit headings
    static func headingUI(size: CGFloat = 24, weight: Weight = .medium) -> UIFont {
        // SF Pro Compact on iOS
        if let descriptor = UIFont.systemFont(ofSize: size, weight: weight.toUIWeight()).fontDescriptor
            .withDesign(.default)?
            .addingAttributes([
                .featureSettings: [
                    [
                        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                        UIFontDescriptor.FeatureKey.selector: kProportionalNumbersSelector
                    ]
                ]
            ]) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return UIFont.systemFont(ofSize: size, weight: weight.toUIWeight())
    }
    #endif
    
    // MARK: - Metadata Fonts (SF Mono)
    
    /// Metadata font using SF Mono for dates, timestamps, and technical info
    /// Use for: Dates, timestamps, metadata, monospaced technical text
    static func metadata(size: CGFloat = 12, weight: Weight = .medium) -> Font {
        return Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .monospaced)
    }
    
    #if os(macOS)
    /// NSFont version for AppKit metadata
    static func metadataNS(size: CGFloat = 12, weight: Weight = .medium) -> NSFont {
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight.toNSWeight())
    }
    #else
    /// UIFont version for UIKit metadata
    static func metadataUI(size: CGFloat = 12, weight: Weight = .medium) -> UIFont {
        return UIFont.monospacedSystemFont(ofSize: size, weight: weight.toUIWeight())
    }
    #endif
    
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
        
        #if os(macOS)
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
        #else
        nonisolated func toUIWeight() -> UIFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
        #endif
        
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

