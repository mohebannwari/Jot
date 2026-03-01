//
//  GlassEffects.swift
//  Jot
//
//  Shared helpers to apply Apple's Liquid Glass effects with
//  sensible fallbacks on older OS versions.
//

import SwiftUI

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
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
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
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(tint.opacity(tintOpacity)))
                .overlay(shape.stroke(Color.primary.opacity(strokeOpacity), lineWidth: 0.5))
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
            self.background(.ultraThinMaterial, in: shape)
        }
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
                .background(.ultraThinMaterial.opacity(0.7))
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
                        .blur(radius: 8.0, opaque: false)
                        .ignoresSafeArea(.all)
                }
        } else {
            self
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.6))
                        .blur(radius: 12.0, opaque: false)
                        .ignoresSafeArea(.all)
                }
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
