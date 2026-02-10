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

    override func layout() {
        super.layout()
        refreshCursorRects()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshCursorRects()
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
}

// MARK: - Subtle Hover Scale

/// Self-contained hover scale effect for elements that don't track their own hover state.
private struct SubtleHoverScale: ViewModifier {
    let scale: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.jotHover, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Adds a self-contained subtle scale-up on hover.
    func subtleHoverScale(_ scale: CGFloat = 1.02) -> some View {
        modifier(SubtleHoverScale(scale: scale))
    }
}

// MARK: - Folder Color Helper

extension Folder {
    var folderColor: Color {
        guard let hex = colorHex else { return Color("SecondaryTextColor") }
        return Color(hex: hex)
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
