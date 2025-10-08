//
//  glass_effects_pattern.swift
//  Noty Examples
//
//  Simplified pattern extracted from: Noty/Utils/GlassEffects.swift
//
//  This demonstrates how to apply Apple's Liquid Glass effects
//  with appropriate fallbacks for older OS versions.
//

import SwiftUI

// MARK: - Liquid Glass Effect Modifiers

extension View {
    /// Standard liquid glass effect for floating UI elements
    ///
    /// Applies Apple's Liquid Glass design system:
    /// - iOS 26+/macOS 26+: Native .glassEffect() with interactive state
    /// - Older OS: Falls back to .ultraThinMaterial with light stroke
    ///
    /// Use for: Buttons, toolbars, floating panels, overlays
    ///
    /// Example:
    /// ```swift
    /// Button("Action") { }
    ///     .liquidGlass(in: RoundedRectangle(cornerRadius: 20))
    /// ```
    @ViewBuilder
    func liquidGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // Use native glass effect with interactive state
            self.glassEffect(.regular.interactive(true), in: shape)
        } else {
            // Fallback for older OS versions
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
    }
    
    /// Tinted liquid glass effect with custom color
    ///
    /// Applies glass effect with a color tint underneath.
    /// The tint should be a semantic color from Assets.xcassets that
    /// already encodes light/dark variants and alpha.
    ///
    /// Parameters:
    /// - shape: The bounding shape for the glass effect
    /// - tint: Semantic color from Assets.xcassets
    /// - strokeOpacity: Border stroke opacity (default: 0.06)
    /// - tintOpacity: Additional opacity multiplier (default: 1.0)
    ///
    /// Example:
    /// ```swift
    /// HStack {
    ///     Image(systemName: "star")
    ///     Text("Featured")
    /// }
    /// .padding()
    /// .tintedLiquidGlass(
    ///     in: Capsule(),
    ///     tint: Color("SurfaceTranslucentColor")
    /// )
    /// ```
    @ViewBuilder
    func tintedLiquidGlass(
        in shape: some Shape,
        tint: Color,
        strokeOpacity: Double = 0.06,
        tintOpacity: Double = 1.0
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .glassEffect(in: shape)
                .background(shape.fill(tint.opacity(tintOpacity)))
                .overlay(shape.stroke(Color.primary.opacity(strokeOpacity), lineWidth: 0.5))
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(tint.opacity(tintOpacity)))
                .overlay(shape.stroke(Color.primary.opacity(strokeOpacity), lineWidth: 0.5))
        }
    }
    
    /// Thin liquid glass for subtle UI elements
    ///
    /// Lighter glass effect for less prominent elements.
    ///
    /// Example:
    /// ```swift
    /// Text("Hint")
    ///     .padding(8)
    ///     .thinLiquidGlass(in: RoundedRectangle(cornerRadius: 12))
    /// ```
    @ViewBuilder
    func thinLiquidGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 16)) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

// MARK: - Glass Background Effects

extension View {
    /// Translucent glass background for full-window backgrounds
    ///
    /// Provides strong blur to prevent content clashing with desktop.
    /// Use for app-level background, not for scrollable content.
    ///
    /// Example:
    /// ```swift
    /// ContentView()
    ///     .translucent()
    /// ```
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
    
    /// Intense glass background for entire app window
    ///
    /// Maximum blur to prevent clashing with desktop elements.
    /// Apply to root view only.
    ///
    /// Example:
    /// ```swift
    /// ZStack {
    ///     // Content
    /// }
    /// .appGlassBackground()
    /// ```
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

// MARK: - Glass Effect Container (iOS 26+)

/// Container for morphing multiple glass shapes with coordinated animations
///
/// Only available on iOS 26+ and macOS 26+. Use for complex glass animations
/// where multiple glass surfaces morph together.
///
/// Example:
/// ```swift
/// if #available(iOS 26.0, macOS 26.0, *) {
///     LiquidGlassContainer(spacing: 20) {
///         GlassButton1()
///         GlassButton2()
///         GlassButton3()
///     }
/// }
/// ```
@available(iOS 26.0, macOS 26.0, *)
struct LiquidGlassContainer<Content: View>: View {
    let content: Content
    let spacing: CGFloat
    
    init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    
    var body: some View {
        // Native SwiftUI glass container for morphing animations
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

// MARK: - Glass Animation Helpers (iOS 26+)

@available(iOS 26.0, macOS 26.0, *)
extension View {
    /// Assign unique ID for glass effect animations
    ///
    /// Use within a LiquidGlassContainer to coordinate animations
    /// across multiple glass surfaces.
    ///
    /// Example:
    /// ```swift
    /// @Namespace var glassNamespace
    ///
    /// Button("One") { }
    ///     .liquidGlass(in: Capsule())
    ///     .glassID("button1", in: glassNamespace)
    /// ```
    func glassID<T: Hashable>(_ id: T, in namespace: Namespace.ID) -> some View {
        self.glassEffectID(id, in: namespace)
    }
}

// MARK: - Usage Examples

struct GlassEffectsExamples: View {
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Standard glass button
            Button("Standard Glass") {
                print("Tapped")
            }
            .padding()
            .liquidGlass(in: RoundedRectangle(cornerRadius: 20))
            
            // Tinted glass badge
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                Text("Featured")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .tintedLiquidGlass(
                in: Capsule(),
                tint: Color("SurfaceTranslucentColor")
            )
            
            // Thin glass for subtle elements
            Text("Subtle hint")
                .font(.caption)
                .padding(8)
                .thinLiquidGlass(in: Capsule())
            
            // Interactive glass with animation
            Button {
                withAnimation(.bouncy(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    Text(isExpanded ? "Collapse" : "Expand")
                }
                .padding()
            }
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16))
        }
        .padding()
    }
}

// MARK: - Key Takeaways

/*
 Liquid Glass Guidelines:
 
 1. WHEN TO USE GLASS
    ✓ Floating UI elements (buttons, toolbars, overlays)
    ✓ Interactive controls
    ✓ Temporary UI (popovers, sheets)
    ✓ Card surfaces
    
    ✗ Scrollable content backgrounds
    ✗ Stacked on other glass surfaces
    ✗ Solid, opaque UI elements
 
 2. GLASS EFFECT TYPES
    - liquidGlass(): Standard interactive glass
    - tintedLiquidGlass(): Glass with color tint
    - thinLiquidGlass(): Subtle glass for small elements
    - translucent(): Window-level background blur
    - appGlassBackground(): Full app background
 
 3. OS VERSION HANDLING
    - Always use @available checks
    - Provide graceful fallbacks
    - Test on older OS versions
    - .ultraThinMaterial is safe fallback
 
 4. ANIMATION RULES
    - Use .bouncy(duration: 0.3) for glass state changes
    - Apply to state that affects glass appearance
    - Coordinate animations in LiquidGlassContainer
    - Use glassID() for morphing animations
 
 5. SHAPE GUIDELINES
    - Standard shapes: RoundedRectangle, Capsule, Circle
    - Corner radii: 4, 20, 24, or fully rounded (Capsule)
    - Match shape to content and context
    - Consistent shapes for similar elements
 
 6. COLOR TINTING
    - Use semantic colors from Assets.xcassets
    - Tint adds subtle color behind glass
    - Maintain light/dark mode compatibility
    - Don't over-tint (reduces glass effect)
 
 7. COMMON MISTAKES
    ✗ Glass on glass (never stack)
    ✗ Hardcoded colors (use Assets.xcassets)
    ✗ Missing OS version checks
    ✗ Wrong animation type (use .bouncy for glass)
    ✗ Glass in scrollable content
 
 8. PERFORMANCE
    - Glass effects are GPU-intensive
    - Minimize glass surfaces in complex views
    - iOS 26+ has 40% better GPU performance
    - Use .ultraThinMaterial fallback for older OS
 
 9. ACCESSIBILITY
    - Respect "Reduce Transparency" setting
    - Fallbacks should be clear and readable
    - Maintain sufficient contrast
    - Test with accessibility settings enabled
 
 10. TESTING
     - Test on both light and dark mode
     - Verify fallbacks on older OS
     - Check performance on lower-end devices
     - Validate with Reduce Transparency enabled
 */

