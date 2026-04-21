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
}
