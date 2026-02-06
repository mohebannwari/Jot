//
//  AppWindowBackground.swift
//  Noty
//
//  Provides a consistent window-level background that reduces banding artefacts
//  when the app floats above varying desktop backdrops.
//

import SwiftUI

struct AppWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                fallbackLayer
            } else {
                blurLayer
            }

            gradientOverlay
            vignetteOverlay
        }
        .ignoresSafeArea()
    }
}

// MARK: - Layers
private extension AppWindowBackground {
    @ViewBuilder
    var blurLayer: some View {
        ZStack {
#if os(macOS)
            BackdropBlurView(material: .hudWindow, blendingMode: .behindWindow)
#else
            BackdropBlurView(style: .systemUltraThinMaterial)
#endif
            tintLayer
        }
    }

    var fallbackLayer: some View {
        tintLayer
    }

    var tintLayer: some View {
        Rectangle()
            .fill(baseTintColor)
    }

    var gradientOverlay: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .allowsHitTesting(false)
    }

    var vignetteOverlay: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .allowsHitTesting(false)
    }
}

// MARK: - Styling helpers
private extension AppWindowBackground {
    var baseTintColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.047, green: 0.039, blue: 0.035, opacity: 0.94)
        } else {
            return Color(red: 0.961, green: 0.961, blue: 0.957, opacity: 0.94)
        }
    }

    var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.white.opacity(0.04),
                Color.black.opacity(0.16)
            ]
        } else {
            return [
                Color.white.opacity(0.18),
                Color.black.opacity(0.06)
            ]
        }
    }
}
