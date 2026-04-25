//
//  Extensions.swift
//  Jot
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI

#if os(macOS)
import AppKit

private struct MacCursorOverlay: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorOverlayView {
        let view = CursorOverlayView(cursor: cursor)
        return view
    }

    func updateNSView(_ nsView: CursorOverlayView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class CursorOverlayView: NSView {
    var cursor: NSCursor {
        didSet {
            if oldValue != cursor {
                refreshCursorRects()
            }
        }
    }

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = false
        postsBoundsChangedNotifications = false
        postsFrameChangedNotifications = false
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CursorOverlayView does not support init(coder:)")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil  // Allow underlying views to receive events
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    private func refreshCursorRects() {
        if let window {
            window.invalidateCursorRects(for: self)
        } else {
            setNeedsDisplay(bounds)
        }
    }
}

private struct MacCursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.overlay(
            MacCursorOverlay(cursor: cursor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}

/// A cursor modifier whose backing NSView accepts hits, so its cursor rect
/// takes priority over AppKit views (like NSTextView) layered beneath it.
private struct MacBlockingCursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.background(
            MacBlockingCursorOverlay(cursor: cursor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        )
    }
}

private struct MacBlockingCursorOverlay: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> BlockingCursorView {
        BlockingCursorView(cursor: cursor)
    }

    func updateNSView(_ nsView: BlockingCursorView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class BlockingCursorView: NSView {
    var cursor: NSCursor {
        didSet {
            if oldValue != cursor {
                if let window { window.invalidateCursorRects(for: self) }
            }
        }
    }

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }
}

extension View {
    /// Applies a pointing-hand cursor on macOS while keeping other platforms unchanged.
    func macPointingHandCursor() -> some View {
        modifier(MacCursorModifier(cursor: .pointingHand))
    }

    /// Restores the default arrow cursor on macOS and leaves other platforms untouched.
    func macArrowCursor() -> some View {
        modifier(MacCursorModifier(cursor: .arrow))
    }

    /// Applies a horizontal resize cursor on macOS for split-handle interactions.
    func macResizeLeftRightCursor() -> some View {
        modifier(MacCursorModifier(cursor: .resizeLeftRight))
    }

    /// Forces the arrow cursor, overriding AppKit views (like NSTextView) beneath this view.
    func macBlockingArrowCursor() -> some View {
        modifier(MacBlockingCursorModifier(cursor: .arrow))
    }
}
#else
extension View {
    func macPointingHandCursor() -> some View { self }
    func macArrowCursor() -> some View { self }
    func macResizeLeftRightCursor() -> some View { self }
    func macBlockingArrowCursor() -> some View { self }
}
#endif

// MARK: - Context Menu Icon Helper

/// macOS `.contextMenu` renders via NSMenu which ignores SwiftUI `.frame()`.
/// This creates an Image with explicit NSImage.size so NSMenu respects 15×15.
#if os(macOS)
extension Image {
    static func menuIcon(_ name: String, size: CGFloat = 15) -> Image {
        let img = NSImage(named: name) ?? NSImage()
        img.isTemplate = true
        img.size = NSSize(width: size, height: size)
        return Image(nsImage: img)
    }
}
#endif

// MARK: - Shared Animation Constants

extension Animation {
    /// Standard spring used throughout the app for transitions and materialization.
    static let jotSpring = Animation.spring(response: 0.35, dampingFraction: 0.82)

    /// Bouncy spring for interactive feedback (tags, buttons, hover).
    static let jotBounce = Animation.bouncy(duration: 0.3)

    /// Fast smooth animation for toolbar and subtle state changes.
    static let jotSmoothFast = Animation.smooth(duration: 0.2)

    /// Quick, damped spring for hover micro-interactions.
    static let jotHover = Animation.spring(response: 0.25, dampingFraction: 0.75)

    /// Snappy spring for drag-feedback states (targeting, drop preview).
    static let jotDragSnap = Animation.spring(response: 0.18, dampingFraction: 0.9)
}

// MARK: - Subtle Hover Scale

/// Self-contained hover effect with optional container background.
/// Scale is intentionally omitted — scaleEffect rasterizes vector icons
/// at their natural size, causing visible blur on Retina displays.
private struct SubtleHoverScale: ViewModifier {
    let containerCornerRadius: CGFloat?
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                if let cr = containerCornerRadius {
                    RoundedRectangle(cornerRadius: cr, style: .continuous)
                        .fill(Color("HoverBackgroundColor"))
                        .opacity(isHovered ? 1 : 0)
                }
            }
            .animation(.jotHover, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Adds a self-contained hover effect with optional container background.
    func subtleHoverScale(_ scale: CGFloat = 1.01, container cornerRadius: CGFloat? = nil) -> some View {
        modifier(SubtleHoverScale(containerCornerRadius: cornerRadius))
    }
}

// MARK: - Hover Container Background

/// Self-contained hover container background (no scale).
private struct HoverContainerBackground: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color("HoverBackgroundColor"))
                    .opacity(isHovered ? 1 : 0)
            )
            .animation(.jotSmoothFast, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Adds a self-contained hover container background.
    func hoverContainer(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverContainerBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Tooltip

/// Solid tinted tooltip pill on hover; styling from `tooltipGlass()` in GlassEffects.
private struct GlassTooltipModifier: ViewModifier {
    let label: String
    let edge: HorizontalAlignment
    let below: Bool

    @State private var isHovered = false

    private var overlayAlignment: Alignment {
        if below {
            switch edge {
            case .leading: return .bottomLeading
            case .trailing: return .bottomTrailing
            default: return .bottom
            }
        } else {
            switch edge {
            case .leading: return .topLeading
            case .trailing: return .topTrailing
            default: return .top
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: overlayAlignment) {
                if isHovered {
                    Text(label)
                        .font(FontManager.heading(size: 11, weight: .medium))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .fixedSize()
                        .tooltipGlass()
                        .offset(y: below ? 34 : -34)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.9, anchor: below ? .top : .bottom).combined(with: .opacity))
                        .zIndex(10000)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Hover tooltip pill using the app tint (not Liquid Glass).
    func glassTooltip(_ label: String, edge: HorizontalAlignment = .center, below: Bool = false) -> some View {
        modifier(GlassTooltipModifier(label: label, edge: edge, below: below))
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            .sRGB,
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }

    func toHexString() -> String {
        #if os(macOS)
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Folder Color Helper

extension Folder {
    /// Whether this folder's pill color is too bright for white text (dark mode contrast fix).
    var folderColorNeedsDarkForeground: Bool {
        guard let hex = colorHex?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#")) else {
            // Default "SecondaryTextColor" -- in dark mode this is light, needs dark text
            return true
        }
        guard hex.count == 6,
              let r = UInt8(hex.prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(4).prefix(2), radix: 16)
        else { return false }

        // W3C relative luminance
        func linearize(_ c: UInt8) -> Double {
            let s = Double(c) / 255.0
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
        return luminance > 0.4
    }

    var folderColor: Color {
        guard let hex = colorHex else { return Color("SecondaryTextColor") }
        return Color(hex: hex)
    }

    /// Returns the folder icon color -- Tailwind 600 in light mode, raw color in dark.
    func folderDisplayColor(for colorScheme: ColorScheme) -> Color {
        guard let hex = colorHex?.lowercased() else { return Color("SecondaryTextColor") }
        guard colorScheme == .light else { return Color(hex: hex) }
        if let shade = Self.tailwind600[hex] { return Color(hex: shade) }
        // Custom color: reduce brightness ~18 %
        let ns = NSColor(Color(hex: hex)).usingColorSpace(.sRGB)
            ?? NSColor(Color(hex: hex)).usingColorSpace(.deviceRGB)
            ?? NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: Double(max(b * 0.82, 0)), opacity: 1)
    }
}

// MARK: - Folder Container Fill (Tailwind 600 Shade)

extension Folder {
    /// Tailwind 600 shades keyed by stored preset hex.
    fileprivate static let tailwind600: [String: String] = [
        "#ef4444": "#dc2626",  // red-600
        "#facc15": "#a16207",  // yellow-700
        "#22c55e": "#16a34a",  // green-600
        "#d946ef": "#c026d3",  // fuchsia-600
        "#3b82f6": "#2563eb",  // blue-600
    ]

    /// Returns the solid Tailwind 600 container fill for this folder's color.
    /// Default (no color) folders use neutral-600.
    func folderContainerFill(for colorScheme: ColorScheme) -> Color {
        guard let hex = colorHex?.lowercased() else {
            return Color(hex: "#525252") // neutral-600
        }

        if let shade = Self.tailwind600[hex] {
            return Color(hex: shade)
        }

        // Custom color: reduce brightness ~18 % to approximate the 600 step.
        let ns = NSColor(Color(hex: hex)).usingColorSpace(.sRGB)
            ?? NSColor(Color(hex: hex)).usingColorSpace(.deviceRGB)
            ?? NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: Double(max(b * 0.82, 0)), opacity: 1)
    }
}

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if isActive {
            content
                .opacity(0.35)
                .overlay {
                    GeometryReader { geo in
                        content
                            .opacity(1)
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white, location: 0.4),
                                        .init(color: .white, location: 0.6),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: geo.size.width * 0.6)
                                .offset(x: -geo.size.width + (phase * 2.5 * geo.size.width))
                            }
                    }
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(
                            .linear(duration: 2.5)
                            .repeatForever(autoreverses: false)
                        ) {
                            phase = 1
                        }
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func shimmering(active: Bool = true) -> some View {
        modifier(ShimmerModifier(isActive: active))
    }
}

// MARK: - Color Markup Stripping

extension String {
    /// Strips `[[color|rrggbb]]...[[/color]]` serialization markup, leaving inner text intact.
    var strippingColorMarkup: String {
        guard contains("[[color|") else { return self }
        var result = self
        result = result.replacingOccurrences(of: "[[/color]]", with: "")
        if let regex = try? NSRegularExpression(pattern: #"\[\[color\|[0-9a-fA-F]{6}\]\]"#) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result
    }
}

// MARK: - Full Markup Stripping

fileprivate enum MarkupRegex {
    static let attachmentRegex = try! NSRegularExpression(
        pattern: #"\[\[(image\|\|\||webclip\||file\||filelink\||notelink\||link\|)[^\]]*?\]\]"#
    )
    static let tagRegex = try! NSRegularExpression(
        pattern: #"\[\[/?[a-z0-9:]+(?:\|[^\]]*?)?\]\]"#
    )
    static let newlineRegex = try! NSRegularExpression(pattern: #"\n{3,}"#)
}

extension String {
    /// Strips all rich-text serialization markup, returning plain readable text.
    /// Removes attachment tags, formatting wrappers (`[[b]]`, `[[/b]]`, etc.),
    /// checkbox markers, and collapses excessive newlines.
    var strippingAllMarkup: String {
        JotMarkupLiteral.protectingRawTokens(in: self) { protectedSource in
            var result = protectedSource

            // 1. Remove self-closing attachment tags (binary blobs — vanish entirely)
            result = MarkupRegex.attachmentRegex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")

            // 2. Strip all remaining [[tag]] and [[/tag]] wrappers
            result = MarkupRegex.tagRegex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")

            // 3. Remove checkbox markers
            result = result.replacingOccurrences(of: "[x]", with: "")
            result = result.replacingOccurrences(of: "[ ]", with: "")

            // 4. Collapse 3+ consecutive newlines to 2, trim
            result = MarkupRegex.newlineRegex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "\n\n")

            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - App Notification Names

extension Notification.Name {
    static let exportSingleNote = Notification.Name("exportSingleNote")
    static let openSettings = Notification.Name("openSettings")
    static let noteToolsBarAction = Notification.Name("NoteToolsBarAction")
    static let applyTextColor = Notification.Name("applyTextColor")
    static let applyHighlightColor = Notification.Name("applyHighlightColor")
    static let highlightTextClicked = Notification.Name("highlightTextClicked")
    static let setHighlightEditRange = Notification.Name("setHighlightEditRange")
    static let removeHighlightColor = Notification.Name("removeHighlightColor")
    static let removeTextColor = Notification.Name("removeTextColor")
    static let todoToolbarAction = Notification.Name("TodoToolbarAction")
    static let applyFontSize = Notification.Name("applyFontSize")
    static let applyFontFamily = Notification.Name("applyFontFamily")
    static let forceSaveNote = Notification.Name("forceSaveNote")
    static let createNewNote = Notification.Name("createNewNote")
    static let createNewFolder = Notification.Name("createNewFolder")
    static let trashFocusedNote = Notification.Name("trashFocusedNote")
    static let navigateNote = Notification.Name("navigateNote")
    static let openNoteFromSpotlight = Notification.Name("openNoteFromSpotlight")
    static let printCurrentNote = Notification.Name("printCurrentNote")
    static let toggleVersionHistory = Notification.Name("toggleVersionHistory")
    static let togglePropertiesPanel = Notification.Name("togglePropertiesPanel")
    static let propertiesPanelToggleTodo = Notification.Name("propertiesPanelToggleTodo")
    static let checkForUpdates = Notification.Name("checkForUpdates")
    static let requestSplitViewFromCommandPalette = Notification.Name(
        "requestSplitViewFromCommandPalette")
}

// MARK: - AI Notification Names

extension Notification.Name {
    static let aiToolAction = Notification.Name("AIToolAction")
    static let aiEditSubmit = Notification.Name("AIEditSubmit")

    // Edit Content selection capture
    // Posted by AIToolsOverlay when "Edit Content" is tapped — triggers Coordinator to read selection
    static let aiEditRequestSelection = Notification.Name("AIEditRequestSelection")
    // Posted by Coordinator; userInfo: ["nsRange": NSRange, "selectedText": String, "windowRect": CGRect]
    static let aiEditCaptureSelection = Notification.Name("AIEditCaptureSelection")

    // Proofread overlay management
    // Posted to remove all proofread pill views and underlines from the editor
    static let aiProofreadClearOverlays = Notification.Name("AIProofreadClearOverlays")
    // Posted by AIToolsOverlay/NoteDetailView+Actions with object: [ProofreadAnnotation]
    static let aiProofreadShowAnnotations = Notification.Name("AIProofreadShowAnnotations")
    // Posted by ProofreadPillView; userInfo: ["original": String, "replacement": String, "originalRange": NSValue]
    static let aiProofreadApplySuggestion = Notification.Name("AIProofreadApplySuggestion")

    // Edit Content -- apply replacement through text storage (not editedContent)
    static let aiEditApplyReplacement = Notification.Name("AIEditApplyReplacement")
    // Proofread -- batch apply all remaining suggestions through text storage
    static let aiProofreadReplaceAll = Notification.Name("AIProofreadReplaceAll")

    // Translation -- language submitted from translate field
    static let aiTranslateSubmit = Notification.Name("AITranslateSubmit")
    // Text Generation -- description submitted from prompt card
    static let aiTextGenSubmit = Notification.Name("AITextGenSubmit")
    // Text Generation -- insert generated text at cursor
    static let aiTextGenInsert = Notification.Name("AITextGenInsert")

    // Meeting Notes
    static let aiMeetingNotesStart = Notification.Name("AIMeetingNotesStart")
    static let aiMeetingNotesPause = Notification.Name("AIMeetingNotesPause")
    static let aiMeetingNotesResume = Notification.Name("AIMeetingNotesResume")
    static let aiMeetingNotesStop = Notification.Name("AIMeetingNotesStop")
    static let aiMeetingNotesComplete = Notification.Name("AIMeetingNotesComplete")
    static let aiMeetingNotesSave = Notification.Name("AIMeetingNotesSave")
    static let aiMeetingNotesDismiss = Notification.Name("AIMeetingNotesDismiss")
}

// MARK: - macOS 14 Compatibility Modifiers

/// Wraps `.contentMargins(.bottom, _, for: .scrollContent)` with a macOS 15 availability check.
/// On macOS 14, falls back to adding a transparent spacer via safeAreaInset.
struct BottomContentMargin: ViewModifier {
    let bottom: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.contentMargins(.bottom, bottom, for: .scrollContent)
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottom)
            }
        }
    }
}

// MARK: - windowBackgroundDragBehavior Compatibility (macOS 15+)

extension Scene {
    /// Applies `.windowBackgroundDragBehavior(.disabled)` on macOS 15+; no-op on macOS 14.
    func windowBackgroundDragDisabledIfAvailable() -> some Scene {
        if #available(macOS 15.0, *) {
            return self.windowBackgroundDragBehavior(.disabled)
        } else {
            return self
        }
    }
}

// MARK: - NSCursor.frameResize Compatibility (macOS 15+)

extension NSCursor {
    /// Compatibility wrapper for `NSCursor.frameResize(position:directions:)` (macOS 15+).
    /// On macOS 14, falls back to the closest classic resize cursor.
    @MainActor
    static func compatFrameResize(position: String, directions: String = "all") -> NSCursor {
        if #available(macOS 15.0, *) {
            let pos: NSCursor.FrameResizePosition
            switch position {
            case "right":       pos = .right
            case "bottom":      pos = .bottom
            case "bottomRight": pos = .bottomRight
            default:            pos = .right
            }
            return NSCursor.frameResize(position: pos, directions: .all)
        } else {
            // Fallback cursors that convey the same resize intent
            switch position {
            case "right":       return NSCursor.resizeLeftRight
            case "bottom":      return NSCursor.resizeUpDown
            case "bottomRight": return NSCursor.crosshair
            default:            return NSCursor.resizeLeftRight
            }
        }
    }
}

/// Wraps `.onScrollGeometryChange` with a macOS 15 availability check.
/// On macOS 14, `isAtBottom` stays true (indicator hidden).
struct ScrollBottomDetector: ViewModifier {
    @Binding var isAtBottom: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Bool.self, of: { geo in
                let maxOffset = geo.contentSize.height - geo.containerSize.height
                return maxOffset <= 0 || geo.contentOffset.y >= maxOffset - 2
            }, action: { _, atBottom in
                withAnimation(.easeInOut(duration: 0.25)) {
                    isAtBottom = atBottom
                }
            })
        } else {
            content.onAppear { isAtBottom = true }
        }
    }
}
