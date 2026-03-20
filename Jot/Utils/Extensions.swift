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
}
#else
extension View {
    func macPointingHandCursor() -> some View { self }
    func macArrowCursor() -> some View { self }
    func macResizeLeftRightCursor() -> some View { self }
}
#endif

// MARK: - Context Menu Icon Helper

/// macOS `.contextMenu` renders via NSMenu which ignores SwiftUI `.frame()`.
/// This creates an Image with explicit NSImage.size so NSMenu respects 18×18.
#if os(macOS)
extension Image {
    static func menuIcon(_ name: String, size: CGFloat = 18) -> Image {
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

/// Liquid glass tooltip pill that appears instantly above the hovered view.
private struct GlassTooltipModifier: ViewModifier {
    let label: String
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isHovered {
                    Text(label)
                        .font(FontManager.heading(size: 11, weight: .medium))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .fixedSize()
                        .liquidGlass(in: Capsule())
                        .offset(y: -28)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                        .zIndex(10000)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Adds a liquid glass tooltip pill that appears instantly on hover.
    func glassTooltip(_ label: String) -> some View {
        modifier(GlassTooltipModifier(label: label))
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
    var folderColor: Color {
        guard let hex = colorHex else { return Color("SecondaryTextColor") }
        return Color(hex: hex)
    }
}

// MARK: - Solid Folder Tint

extension Color {
    /// Returns a fully opaque tint derived from this color, suitable for folder
    /// section backgrounds. Light mode blends 78 % toward white; dark mode blends
    /// 75 % toward a warm near-black base.
    func solidFolderTint(for colorScheme: ColorScheme) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB)
            ?? NSColor(self).usingColorSpace(.deviceRGB)
            ?? NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)

        switch colorScheme {
        case .dark:
            let baseR: CGFloat = 0.08, baseG: CGFloat = 0.06, baseB: CGFloat = 0.05
            let t: CGFloat = 0.73
            return Color(
                red:   r * (1 - t) + baseR * t,
                green: g * (1 - t) + baseG * t,
                blue:  b * (1 - t) + baseB * t
            )
        default:
            let t: CGFloat = 0.75
            return Color(
                red:   r * (1 - t) + 1.0 * t,
                green: g * (1 - t) + 1.0 * t,
                blue:  b * (1 - t) + 1.0 * t
            )
        }
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
    static let formatMenuAction = Notification.Name("formatMenuAction")
    static let navigateNote = Notification.Name("navigateNote")
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
    // Posted by ProofreadPillView; userInfo: ["original": String, "replacement": String]
    static let aiProofreadApplySuggestion = Notification.Name("AIProofreadApplySuggestion")

    // Edit Content -- apply replacement through text storage (not editedContent)
    static let aiEditApplyReplacement = Notification.Name("AIEditApplyReplacement")
    // Proofread -- batch apply all remaining suggestions through text storage
    static let aiProofreadReplaceAll = Notification.Name("AIProofreadReplaceAll")
}
