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

import AppKit
import Foundation
import SwiftUI

// File-scope cache: `FontManager` is MainActor-isolated by default, so static storage on the
// struct cannot be touched from `nonisolated` `bodyNS` / `headingNS` (AppKit layout threads).
// `nonisolated(unsafe)` opts this pair out of actor isolation; the lock makes access safe.
// Compiler: NSLock is Sendable so `nonisolated(unsafe)` is redundant on the lock alone; without
// it, this `let` is main-actor-isolated and cannot be used from `nonisolated` `bodyNS`/`headingNS`.
private nonisolated(unsafe) let fontManagerNSFontCacheLock = NSLock()
private nonisolated(unsafe) var fontManagerNSFontCache: [String: NSFont] = [:]

/// Centralized font manager providing consistent typography across the application
struct FontManager {
    // Duplicated from ThemeManager.bodyFontStyleDefaultsKey to avoid accessing
    // a main-actor-isolated property from a nonisolated context.
    private nonisolated static let bodyFontStyleKey = "AppBodyFontStyle"

    // MARK: - Font Cache

    /// Call when body font style changes to clear stale cached fonts.
    static func invalidateFontCache() {
        fontManagerNSFontCacheLock.lock()
        defer { fontManagerNSFontCacheLock.unlock() }
        fontManagerNSFontCache.removeAll()
    }

    nonisolated private static func currentBodyFontStyle(
        userDefaults: UserDefaults = .standard
    ) -> BodyFontStyle {
        let rawValue =
            userDefaults.string(forKey: bodyFontStyleKey) ?? BodyFontStyle.default.rawValue
        return BodyFontStyle(rawValue: rawValue) ?? .default
    }

    /// Horizontal / vertical padding for ImageRenderer capsule pills inlined in the rich text editor
    /// (notelinks, file links, file-attachment tags). Fractional vertical values trim bitmap slack vs. Charter line metrics.
    enum InlineEditorPillRasterPadding {
        public static let horizontal: CGFloat = 4
        public static let vertical: CGFloat = 3.4375
    }

    // MARK: - Body Text Fonts (Charter)

    /// Primary body text font using Charter
    /// Use for: Note content, editor text, paragraph text
    static func body(size: CGFloat = 16, weight: Weight = .regular) -> Font {
        switch currentBodyFontStyle() {
        case .default:
            return Font.custom("Charter", size: size)
                .weight(weight.toSwiftUIWeight())
        case .system:
            return Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .default)
        case .mono:
            return Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .monospaced)
        }
    }

    /// NSFont version for AppKit components
    nonisolated static func bodyNS(size: CGFloat = 16, weight: Weight = .regular) -> NSFont {
        let key = "body-\(size)-\(weight)"
        fontManagerNSFontCacheLock.lock()
        defer { fontManagerNSFontCacheLock.unlock() }
        if let cached = fontManagerNSFontCache[key] { return cached }
        let font: NSFont
        switch currentBodyFontStyle() {
        case .default:
            // Try Charter first, fall back to Georgia (similar serif), then system
            if let charter = NSFont(name: "Charter-\(weight.toCharterName())", size: size) {
                font = charter
            } else if let charter = NSFont(name: "Charter", size: size) {
                let descriptor = charter.fontDescriptor.withSymbolicTraits(weight.toNSSymbolicTraits())
                font = NSFont(descriptor: descriptor, size: size) ?? charter
            } else if let georgia = NSFont(name: "Georgia", size: size) {
                font = georgia
            } else {
                font = NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
            }
        case .system:
            font = NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
        case .mono:
            font = NSFont.monospacedSystemFont(ofSize: size, weight: weight.toNSWeight())
        }
        fontManagerNSFontCache[key] = font
        return font
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
        let key = "heading-\(size)-\(weight)"
        fontManagerNSFontCacheLock.lock()
        defer { fontManagerNSFontCacheLock.unlock() }
        if let cached = fontManagerNSFontCache[key] { return cached }
        let font: NSFont
        switch currentBodyFontStyle() {
        case .default:
            if let charter = NSFont(name: "Charter-Bold", size: size) {
                font = charter
            } else if let charter = NSFont(name: "Charter", size: size) {
                let descriptor = charter.fontDescriptor.withSymbolicTraits(.bold)
                font = NSFont(descriptor: descriptor, size: size) ?? charter
            } else {
                font = NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
            }
        case .system:
            font = NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
        case .mono:
            font = NSFont.monospacedSystemFont(ofSize: size, weight: weight.toNSWeight())
        }
        fontManagerNSFontCache[key] = font
        return font
    }

    // MARK: - Metadata Fonts (SF Mono)

    /// Monospaced metadata (dates, shortcuts, technical labels).
    ///
    /// **Design system:** For static `Text` labels, default to **11pt** and apply
    /// `jotMetadataLabelTypography(size:weight:)` so copy is **all caps**.
    /// Use a non-default `size` only when a screen or Figma spec explicitly requires it.
    /// Do **not** force all caps on `TextField` / user-typed content.
    static func metadata(size: CGFloat = 11, weight: Weight = .medium) -> Font {
        return Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .monospaced)
    }

    // MARK: - Icon Fonts

    /// Standard icon font for UI/action symbols across the app.
    static func icon(size: CGFloat = 16, weight: Weight = .regular) -> Font {
        Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .default)
    }
    
    /// NSFont version for AppKit metadata (same defaults as ``metadata(size:weight:)``).
    static func metadataNS(size: CGFloat = 11, weight: Weight = .medium) -> NSFont {
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight.toNSWeight())
    }

    // MARK: - Layout metrics (AppKit text measurement)

    /// Single source for line height when matching SwiftUI spacing to AppKit layout.
    nonisolated static func defaultLineHeight(for font: NSFont) -> CGFloat {
        // `defaultLineHeight(for:)` is an instance method on AppKit's `NSLayoutManager`.
        NSLayoutManager().defaultLineHeight(for: font)
    }

    // MARK: - Note detail title (NoteDetailView)

    /// Point size for the multi-line note title field — keep scroll insets and fonts in sync.
    nonisolated static let noteDetailTitlePointSize: CGFloat = 32

    /// Sticky header, toolbars, and compact labels in ``NoteDetailView``.
    nonisolated static let noteDetailOverlayHeadingSize: CGFloat = 12

    /// Secondary section titles inside note chrome (e.g. proofread blocks).
    nonisolated static let noteDetailAuxiliaryHeadingSize: CGFloat = 20

    /// SwiftUI font for the note title ``TextField``. Omits ``.leading(.tight)`` from ``heading(...)``
    /// so wrapped lines and tall capitals are not clipped by overly tight line metrics.
    static func noteDetailTitleFont(weight: Weight = .medium) -> Font {
        Font.system(size: noteDetailTitlePointSize, weight: weight.toSwiftUIWeight(), design: .default)
    }

    /// Top padding for ``NoteDetailView`` scroll content above the metadata row.
    /// Uses AppKit line metrics (not magic constants) so changing ``noteDetailTitlePointSize`` or
    /// metadata size updates the gutter. macOS windows often report zero SwiftUI safe-area inset,
    /// so title ascender slop is folded into the formula instead of reading ``safeAreaInsets``.
    nonisolated static func noteDetailEditorScrollTopInset() -> CGFloat {
        let meta = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let titleFont = NSFont.systemFont(ofSize: noteDetailTitlePointSize, weight: .medium)
        let metadataLine = defaultLineHeight(for: meta)
        let titleLine = defaultLineHeight(for: titleFont)
        let titleAscenderSlop = max(0, titleLine - titleFont.capHeight - 4)
        return metadataLine + 36 + titleAscenderSlop
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

// MARK: - Metadata label styling (SwiftUI)

extension View {
    /// Monospaced metadata **labels**: 11pt (unless overridden) and **all caps** per design system.
    ///
    /// Use for `Text` only. Do **not** apply to `TextField` / `TextEditor` where the user types
    /// sentence-case content — use `.font(FontManager.metadata(...))` there without all caps.
    func jotMetadataLabelTypography(
        size: CGFloat = 11,
        weight: FontManager.Weight = .medium
    ) -> some View {
        font(FontManager.metadata(size: size, weight: weight))
            .textCase(.uppercase)
    }
}
