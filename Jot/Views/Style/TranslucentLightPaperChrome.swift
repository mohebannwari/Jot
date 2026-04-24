//
//  TranslucentLightPaperChrome.swift
//  Jot
//
//  Shared “paper card” elevation for light mode when note-pane translucency is on.
//  Shadow **stacks match AI panels** (see ``MeetingPanelBackgroundModifier`` in
//  ``MeetingNotesFloatingPanel``): diffuse liquid-glass depth, not harsh contact shadows.
//

import AppKit
import SwiftUI

// MARK: - SwiftUI (same stack order as AI meeting panel on macOS 26+)

extension View {
    /// Drop shadow for opaque light “paper” surfaces sitting on translucent chrome.
    /// Uses the same two-pass shadow as AI result / meeting panels so Settings and note
    /// blocks feel like siblings on the canvas.
    /// Caller gates with light mode + translucency + Reduce Transparency (SwiftUI environment).
    @ViewBuilder
    func liquidGlassPaperElevatedShadow(enabled: Bool) -> some View {
        if enabled {
            self
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        } else {
            self
        }
    }

    /// Hairline stroke matching ``NoteTableOverlayView``’s light-mode outer border: black 8% @ 0.5pt.
    /// Use only when ``enabled`` is the same gate as ``liquidGlassPaperElevatedShadow`` (light + translucency + not reducing transparency).
    @ViewBuilder
    func translucentLightPaperTableStroke<S: Shape>(shape: S, enabled: Bool) -> some View {
        if enabled {
            self.overlay {
                shape.stroke(TranslucentLightPaperTableStroke.lightStrokeSwiftUIColor, lineWidth: TranslucentLightPaperTableStroke.lineWidth)
            }
        } else {
            self
        }
    }
}

// MARK: - Table-matched stroke (shared with NoteTableOverlayView outer border)

/// Constants for the inline table’s outer perimeter in light mode — reused by Settings paper cards and code blocks.
enum TranslucentLightPaperTableStroke {
    /// Same alpha as ``NoteTableOverlayView`` `borderColor` in light (not ``BorderSubtleColor``).
    static let lightStrokeBlackAlpha: CGFloat = 0.08
    /// Matches table perimeter line width (half-point hairline).
    static let lineWidth: CGFloat = 0.5

    static var lightStrokeSwiftUIColor: Color {
        Color.black.opacity(lightStrokeBlackAlpha)
    }

    static func lightOuterStrokeNSColor() -> NSColor {
        NSColor.black.withAlphaComponent(lightStrokeBlackAlpha)
    }
}

// MARK: - AppKit (inline editor overlays)

/// Gate and apply CALayer shadows for white block chrome over the translucent note pane.
enum LiquidPaperShadowChrome {
    /// Translucency on, not reducing transparency, resolved light appearance.
    static func shouldShowPaperShadow(effectiveAppearance: NSAppearance) -> Bool {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { return false }
        let raw = UserDefaults.standard.object(forKey: ThemeManager.detailPaneTranslucencyKey) as? Double ?? 0
        let t = min(1, max(0, raw))
        guard t > 0.001 else { return false }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return !dark
    }

    /// Single CALayer shadow approximating the AI panel SwiftUI stack (diffuse-first).
    /// ``CALayer`` only supports one shadow; we bias toward the large soft pass (24pt blur,
    /// 8pt drop) with modest opacity so code/tabs/table match Summary / Key Points panels.
    static func applyPaperShadow(to layer: CALayer?, path: CGPath, enabled: Bool) {
        guard let layer else { return }
        if enabled {
            layer.shadowPath = path
            layer.masksToBounds = false
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.14
            layer.shadowRadius = 22
            layer.shadowOffset = NSSize(width: 0, height: 7)
        } else {
            layer.shadowPath = nil
            layer.shadowColor = nil
            layer.shadowOpacity = 0
            layer.shadowRadius = 0
            layer.shadowOffset = .zero
        }
    }

    /// Table-matched hairline on a dedicated ``CAShapeLayer`` (stroke only, no fill). Path should be the rounded rect
    /// used for the code block shell, inset by half ``TranslucentLightPaperTableStroke/lineWidth`` like ``NoteTableOverlayView``.
    static func applyLightTableOuterStroke(to layer: CAShapeLayer?, path: CGPath?, enabled: Bool) {
        guard let layer else { return }
        if enabled, let path {
            layer.isHidden = false
            layer.fillColor = nil
            layer.strokeColor = TranslucentLightPaperTableStroke.lightOuterStrokeNSColor().cgColor
            layer.lineWidth = TranslucentLightPaperTableStroke.lineWidth
            layer.path = path
            layer.lineJoin = .round
        } else {
            layer.isHidden = true
            layer.path = nil
            layer.strokeColor = nil
        }
    }
}
