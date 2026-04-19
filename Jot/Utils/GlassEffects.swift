//
//  GlassEffects.swift
//  Jot
//
//  Shared helpers to apply Apple's Liquid Glass effects with
//  sensible fallbacks on older OS versions.
//

import SwiftUI

// MARK: - Tooltip modifiers (app tint via ThemeManager)

/// Solid hover tooltip capsule; background follows Settings tint (not Liquid Glass).
private struct TooltipGlassModifier: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = Capsule()
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(themeManager.tintedTooltipBackground(for: colorScheme), in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

/// Real `.glassEffect` on OS 26+ (no extra tint). Pre-26 uses the same tinted
/// solid fill as `tooltipGlass()` so link/file pills still pick up the app wash.
private struct LiquidGlassTooltipModifier<S: Shape>: ViewModifier {
    let shape: S
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(themeManager.tintedTooltipBackground(for: colorScheme), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
    }
}

extension View {
    /// Applies a standard liquid glass surface inside the given shape, bounded to that shape.
    /// - On modern OS versions uses `glassEffect(..., in:)`.
    /// - On older OS versions falls back to `.ultraThinMaterial` with a light stroke.
    @ViewBuilder
    func liquidGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(true), in: shape)
        } else {
            self
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: shape)
                .background(Color("SecondaryBackgroundColor").opacity(0.5), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
    }

    /// Applies a tinted liquid glass surface inside the given shape, bounded to that shape.
    /// The `tint` color may be an asset color that already encodes light/dark variants and alpha.
    /// You can additionally scale its opacity using `tintOpacity` if needed.
    @ViewBuilder
    func tintedLiquidGlass(
        in shape: some Shape,
        tint: Color,
        strokeOpacity: Double = 0.06,
        tintOpacity: Double = 1.0
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(tintOpacity)), in: shape)
        } else {
            self
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(shape.fill(tint.opacity(tintOpacity)))
                .background(.ultraThinMaterial, in: shape)
                .background(Color("SecondaryBackgroundColor").opacity(0.5), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(max(strokeOpacity, 0.12)), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
    }
    
    /// Applies a thin liquid glass effect for subtle UI elements.
    /// - On modern OS versions uses default `glassEffect()` with a shape.
    /// - On older OS versions falls back to `.ultraThinMaterial`.
    @ViewBuilder
    func thinLiquidGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 16)) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: shape)
                .background(Color("SecondaryBackgroundColor").opacity(0.5), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
    }
    
    /// Applies a solid tooltip capsule (no drop shadow) using the app tint from
    /// `ThemeManager`. Requires `ThemeManager` in the environment.
    func tooltipGlass() -> some View {
        modifier(TooltipGlassModifier())
    }

    /// Liquid Glass tooltip on iOS/macOS 26+ (untinted native glass). Older OS
    /// uses the same tinted solid background as `tooltipGlass()`.
    func liquidGlassTooltip<S: Shape>(shape: S = Capsule()) -> some View {
        modifier(LiquidGlassTooltipModifier(shape: shape))
    }

    /// Applies a prominent glass effect for important UI elements.
    /// - On modern OS versions uses `.buttonStyle(.glassProminent)` for buttons.
    /// - On older OS versions falls back to `.borderedProminent` style.
    @ViewBuilder
    func prominentGlassStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

/// Container for morphing multiple liquid glass shapes with coordinated animations.
/// Only available on iOS 26.0+ and macOS 26.0+
@available(iOS 26.0, macOS 26.0, *)
struct LiquidGlassContainer<Content: View>: View {
    let content: Content
    let spacing: CGFloat

    init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

/// Applies a translucent glass background suitable for full-window backgrounds.
/// Uses strong blur effects to prevent content clashing with elements behind the app.
/// - On modern OS versions uses `.clear` glass effect with enhanced blur.
/// - On older OS versions falls back to `.ultraThinMaterial` with reduced opacity.
extension View {
    @ViewBuilder
    func translucent() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .glassEffect(.clear)
                .background(.black.opacity(0.1))
                .blur(radius: 1.2, opaque: false)
        } else {
            self
                .background(Color("SecondaryBackgroundColor").opacity(0.85))
                .blur(radius: 2.0, opaque: false)
        }
    }

    /// Applies an intense translucent glass background for the entire app window.
    /// Provides maximum blur to prevent content clashing with desktop elements.
    @ViewBuilder
    func appGlassBackground() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.clear.interactive(false))
                        .background(.black.opacity(0.05))
                        .ignoresSafeArea(.all)
                }
        } else {
            self
                .background {
                    ZStack {
                        BackdropBlurView(material: .hudWindow, blendingMode: .behindWindow)
                        Color(.black).opacity(0.10)
                    }
                    .ignoresSafeArea(.all)
                }
        }
    }
}

// MARK: - AI Panel Glass / Glow Modifiers

/// Applies Liquid Glass on macOS 26+ and the Apple Intelligence glow on older OS versions.
/// Use on AI panels (Translate, Edit Content, Text Gen, Summary, Key Points, Meeting Detail)
/// whose solid background is already conditionally removed on macOS 26+.
/// On macOS 26+, uses ``GlassEffectStyle/regular`` so panels read as real Liquid Glass on the note canvas
/// (clear glass was too subtle on bright paper).
struct AIGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    var glowMode: GlowMode = .oneShot

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(true),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .appleIntelligenceGlow(cornerRadius: cornerRadius, mode: glowMode)
        }
    }
}

/// Applies the Apple Intelligence glow ONLY on pre-macOS 26.
/// On macOS 26+ it's a no-op because the panel already has Liquid Glass via AIGlassModifier.
/// Use at call sites in NoteDetailView where glow was applied externally.
struct AIGlowFallbackModifier: ViewModifier {
    let cornerRadius: CGFloat
    var mode: GlowMode = .oneShot

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
        } else {
            content
                .appleIntelligenceGlow(cornerRadius: cornerRadius, mode: mode)
        }
    }
}

/// Wrapper for animated glass morphing effects with unique IDs
@available(iOS 26.0, macOS 26.0, *)
extension View {
    /// Assigns a unique ID for glass effect animations within a GlassEffectContainer
    func glassID<T: Hashable>(_ id: T, in namespace: Namespace.ID) -> some View {
        self.glassEffectID(id, in: namespace)
    }
}
