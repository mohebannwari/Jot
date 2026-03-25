import SwiftUI

// MARK: - Glow Mode

enum GlowMode {
    /// Rotates continuously while visible
    case continuous
    /// Completes exactly one full rotation, then stops
    case oneShot
}

// MARK: - Apple Intelligence Glow Modifier

/// Animated rotating gradient glow inspired by the iOS 26 Siri / Apple Intelligence effect.
/// Renders behind the view as a soft halo that peeks out from behind the panel edges.
struct AppleIntelligenceGlow: ViewModifier {
    let cornerRadius: CGFloat
    let mode: GlowMode

    @State private var rotation: Angle = .zero
    @State private var isComplete: Bool = false
    @State private var oneShotTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // Apple Intelligence palette
    private static let colors: [Color] = [
        Color(red: 188/255, green: 130/255, blue: 243/255), // #BC82F3 purple
        Color(red: 245/255, green: 185/255, blue: 234/255), // #F5B9EA pink
        Color(red: 141/255, green: 159/255, blue: 255/255), // #8D9FFF blue
        Color(red: 255/255, green: 103/255, blue: 120/255), // #FF6778 red
        Color(red: 255/255, green: 186/255, blue: 113/255), // #FFBA71 orange
        Color(red: 198/255, green: 134/255, blue: 255/255), // #C686FF violet
    ]

    private var gradient: AngularGradient {
        AngularGradient(
            colors: Self.colors + [Self.colors[0]],
            center: .center,
            angle: rotation
        )
    }

    func body(content: Content) -> some View {
        content
            .background { glowLayers }
            .onAppear { startAnimation() }
            .onDisappear { oneShotTask?.cancel() }
    }

    // MARK: - Glow Layers

    @ViewBuilder
    private var glowLayers: some View {
        if !isComplete && !reduceMotion {
            // Rendered behind the panel, padded outward so the glow
            // peeks from behind the edges without bleeding into the content.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(gradient)
                .padding(-4)
                .blur(radius: 12)
                .allowsHitTesting(false)
                .opacity(colorScheme == .dark ? 0.8 : 0.55)
        }
    }

    // MARK: - Animation

    private func startAnimation() {
        guard !reduceMotion else {
            isComplete = true
            return
        }

        switch mode {
        case .continuous:
            // Start from a random angle so reopening the panel doesn't
            // always snap to the same color position.
            let startAngle = Double.random(in: 0..<360)
            rotation = .degrees(startAngle)
            withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                rotation = .degrees(startAngle + 360)
            }

        case .oneShot:
            withAnimation(.easeInOut(duration: 4.0)) {
                rotation = .degrees(360)
            }
            oneShotTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4.0))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.5)) {
                    isComplete = true
                }
            }
        }
    }
}

// MARK: - Convenience Extension

extension View {
    func appleIntelligenceGlow(cornerRadius: CGFloat = 22, mode: GlowMode = .continuous) -> some View {
        modifier(AppleIntelligenceGlow(cornerRadius: cornerRadius, mode: mode))
    }
}
