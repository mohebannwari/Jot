//
//  FontManager.swift
//  Jot
//
//  Created by Moheb Anwari on 10.10.25.
//
//  Centralized font management for consistent typography across the app.
//  Families:
//  1. SF Pro — UI chrome, headings, and default note body (see ``BodyFontStyle`` / ThemeManager)
//  2. Charter — optional serif body (`BodyFontStyle.default`)
//  3. SF Mono — metadata and technical labels

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
            userDefaults.string(forKey: bodyFontStyleKey) ?? BodyFontStyle.system.rawValue
        return BodyFontStyle(rawValue: rawValue) ?? .system
    }

    /// Horizontal / vertical padding for ImageRenderer capsule pills inlined in the rich text editor
    /// (notelinks, file links, file-attachment tags). Fractional vertical values trim bitmap slack vs. body line metrics.
    enum InlineEditorPillRasterPadding {
        public static let horizontal: CGFloat = 4
        public static let vertical: CGFloat = 3.4375
    }

    // MARK: - Body text (user preference: SF Pro, Charter, or mono)

    /// Note body / editor paragraph font. Default install uses SF Pro (``BodyFontStyle.system``).
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
    /// Headings are part of the UI type scale and should stay on the system face even when
    /// the body copy preference switches to Charter or mono.
    nonisolated static func headingNS(size: CGFloat = 24, weight: Weight = .medium) -> NSFont {
        let key = "heading-\(size)-\(weight)"
        fontManagerNSFontCacheLock.lock()
        defer { fontManagerNSFontCacheLock.unlock() }
        if let cached = fontManagerNSFontCache[key] { return cached }
        let font = NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
        fontManagerNSFontCache[key] = font
        return font
    }

    // MARK: - Metadata Fonts (SF Mono)

    /// Monospaced metadata (dates, shortcuts, technical labels).
    ///
    /// **Design system (static labels):** **11pt**, **medium**, **all caps** — use
    /// `jotMetadataLabelTypography(size:weight:)` so the trio stays linked. Use a non-default
    /// `size`/`weight` only when product explicitly documents an exception (rare).
    ///
    /// **User input / dynamic prose:** `TextField`, `TextEditor`, assignee names, and similar
    /// content use ``metadata(size:weight:)`` **without** `jotMetadataLabelTypography()` so casing
    /// stays natural (still default to **11pt medium** for the monospace face).
    static func metadata(size: CGFloat = 11, weight: Weight = .medium) -> Font {
        // Use the same face as ``metadataNS``. SwiftUI's `Font.system(..., design: .monospaced)`
        // can render lighter than the requested weight on macOS; bridging NSFont fixes that.
        Font(NSFont.monospacedSystemFont(ofSize: size, weight: weight.toNSWeight()))
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

    // MARK: - UI type ramp (SF Pro, Figma-aligned)

    /// Proportional SF UI chrome: font + SwiftUI letter spacing (`.tracking`, in **points**).
    /// Apply with ``View/jotUI(_:)`` so tracking stays tied to the size ramp.
    struct UIChromeFont: Sendable, Hashable {
        let font: Font
        let tracking: CGFloat
    }

    /// Point sizes from `.claude/rules/design-system.md` (Figma type scale). Prefer named
    /// ``uiLabel2()`` … ``uiMicro()`` for hierarchy; use ``uiPro(size:weight:)`` for one-off
    /// control sizes until they are promoted into the ramp. Future: map each rung to
    /// `Font.TextStyle` / Dynamic Type without touching every call site.
    enum UITextRamp {
        nonisolated static let headingH4: CGFloat = 20
        nonisolated static let label2: CGFloat = 15
        nonisolated static let label3: CGFloat = 13
        nonisolated static let label4: CGFloat = 12
        nonisolated static let label5: CGFloat = 11
        nonisolated static let tiny: CGFloat = 10
        nonisolated static let micro: CGFloat = 9
    }

    /// Letter spacing for fixed-size **proportional** SF chrome (SwiftUI `.tracking` points).
    ///
    /// Apple’s SF fonts ship with optical size tables; `Font.system(size:)` does not apply the
    /// same tracking as `TextStyle`-based text. Policy: **zero tracking through Label-2 (15pt)**
    /// — lets SF Pro’s built-in optical metrics handle small UI sizes instead of layering extra
    /// positive tracking. Display sizes (17pt+) use mild negative tracking so headlines do not
    /// feel loose.
    nonisolated static func proportionalUITracking(pointSize: CGFloat) -> CGFloat {
        let s = pointSize
        switch s {
        case ..<17: return 0
        case 17..<22: return -0.04
        case 22..<28: return -0.08
        default: return -0.12
        }
    }

    /// SF Pro for chrome and controls (not note body — use ``body``).
    static func uiPro(size: CGFloat, weight: Weight = .regular) -> UIChromeFont {
        UIChromeFont(
            font: Font.system(size: size, weight: weight.toSwiftUIWeight(), design: .default),
            tracking: proportionalUITracking(pointSize: size)
        )
    }

    /// Figma Heading/H4 — 20pt.
    static func uiHeadingH4(weight: Weight = .medium) -> UIChromeFont {
        uiPro(size: UITextRamp.headingH4, weight: weight)
    }

    /// Figma Label-2 — 15pt.
    static func uiLabel2(weight: Weight = .medium) -> UIChromeFont {
        uiPro(size: UITextRamp.label2, weight: weight)
    }

    /// Figma Label-3 — 13pt.
    static func uiLabel3(weight: Weight = .medium) -> UIChromeFont {
        uiPro(size: UITextRamp.label3, weight: weight)
    }

    /// Figma Label-4 — 12pt.
    static func uiLabel4(weight: Weight = .regular) -> UIChromeFont {
        uiPro(size: UITextRamp.label4, weight: weight)
    }

    /// Figma Label-5 — 11pt (proportional SF Pro; for mono static labels use ``metadata`` + ``jotMetadataLabelTypography()``).
    /// Pass `textLeading` when matching `NSTextField`/`TextField` line metrics (e.g. search field).
    static func uiLabel5(weight: Weight = .medium, textLeading: Font.Leading? = nil) -> UIChromeFont {
        var base = Font.system(size: UITextRamp.label5, weight: weight.toSwiftUIWeight(), design: .default)
        if let textLeading {
            base = base.leading(textLeading)
        }
        return UIChromeFont(
            font: base,
            tracking: proportionalUITracking(pointSize: UITextRamp.label5)
        )
    }

    /// Figma Tiny — 10pt.
    static func uiTiny(weight: Weight = .semibold) -> UIChromeFont {
        uiPro(size: UITextRamp.tiny, weight: weight)
    }

    /// Figma Micro — 9pt.
    static func uiMicro(weight: Weight = .semibold) -> UIChromeFont {
        uiPro(size: UITextRamp.micro, weight: weight)
    }

    /// NSFont SF Pro for AppKit overlays matching the UI ramp.
    nonisolated static func uiProNS(size: CGFloat, weight: Weight = .regular) -> NSFont {
        let key = "uiPro-\(size)-\(weight)"
        fontManagerNSFontCacheLock.lock()
        defer { fontManagerNSFontCacheLock.unlock() }
        if let cached = fontManagerNSFontCache[key] { return cached }
        let font = NSFont.systemFont(ofSize: size, weight: weight.toNSWeight())
        fontManagerNSFontCache[key] = font
        return font
    }

    nonisolated static func uiHeadingH4NS(weight: Weight = .medium) -> NSFont {
        uiProNS(size: UITextRamp.headingH4, weight: weight)
    }

    nonisolated static func uiLabel2NS(weight: Weight = .medium) -> NSFont {
        uiProNS(size: UITextRamp.label2, weight: weight)
    }

    nonisolated static func uiLabel3NS(weight: Weight = .medium) -> NSFont {
        uiProNS(size: UITextRamp.label3, weight: weight)
    }

    nonisolated static func uiLabel4NS(weight: Weight = .regular) -> NSFont {
        uiProNS(size: UITextRamp.label4, weight: weight)
    }

    nonisolated static func uiLabel5NS(weight: Weight = .medium) -> NSFont {
        uiProNS(size: UITextRamp.label5, weight: weight)
    }

    nonisolated static func uiTinyNS(weight: Weight = .semibold) -> NSFont {
        uiProNS(size: UITextRamp.tiny, weight: weight)
    }

    nonisolated static func uiMicroNS(weight: Weight = .semibold) -> NSFont {
        uiProNS(size: UITextRamp.micro, weight: weight)
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
    static func noteDetailTitleFont(weight: Weight = .regular) -> Font {
        Font.system(size: noteDetailTitlePointSize, weight: weight.toSwiftUIWeight(), design: .default)
    }

    /// Top padding for ``NoteDetailView`` scroll content above the metadata row.
    /// Uses AppKit line metrics (not magic constants) so changing ``noteDetailTitlePointSize`` or
    /// metadata size updates the gutter. macOS windows often report zero SwiftUI safe-area inset,
    /// so title ascender slop is folded into the formula instead of reading ``safeAreaInsets``.
    nonisolated static func noteDetailEditorScrollTopInset() -> CGFloat {
        let meta = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let titleFont = NSFont.systemFont(ofSize: noteDetailTitlePointSize, weight: .semibold)
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
    /// Applies proportional SF UI chrome from ``FontManager/UIChromeFont`` (font + tracking).
    func jotUI(_ chrome: FontManager.UIChromeFont) -> some View {
        font(chrome.font).tracking(chrome.tracking)
    }

    /// Monospaced metadata **labels** (SF Mono): **11pt**, **medium**, and **all caps** per design system.
    /// **All caps is reserved for this mono API** — SF Pro chrome uses ``jotUI(_:)`` / `uiLabel*` with
    /// sentence case; see `.claude/rules/design-system.md` (Typography, casing).
    ///
    /// Use for `Text` only. Do **not** apply to `TextField` / `TextEditor` where the user types
    /// sentence-case content — use `.font(FontManager.metadata(size: 11, weight: .medium))` there
    /// without applying `.textCase(.uppercase)`.
    func jotMetadataLabelTypography(
        size: CGFloat = 11,
        weight: FontManager.Weight = .medium
    ) -> some View {
        font(FontManager.metadata(size: size, weight: weight))
            .textCase(.uppercase)
    }
}
