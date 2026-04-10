//
//  HueGradientSlider.swift
//  Jot
//
//  Custom slider with a rainbow gradient track and a color-matched thumb.
//  Used in Settings > Appearance > Colors to pick the app-wide tint hue.
//
//  Why a custom view instead of stock SwiftUI `Slider`: stock Slider draws
//  a flat accent-colored track and a white thumb. The hue picker needs the
//  full spectrum visible in the track itself (so the user sees what they're
//  picking) and a thumb that actually shows the currently-selected hue.
//

import SwiftUI

struct HueGradientSlider: View {
    @Binding var value: Double

    private let trackHeight: CGFloat = 6
    private let thumbDiameter: CGFloat = 16

    private static let rainbowStops: [Gradient.Stop] = (0...12).map { i in
        let h = Double(i) / 12.0
        return .init(color: Color(hue: h, saturation: 1, brightness: 1), location: h)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let clamped = min(max(value, 0), 1)
            let thumbX = clamped * width

            ZStack(alignment: .leading) {
                // Rainbow track
                Capsule()
                    .fill(LinearGradient(
                        stops: Self.rainbowStops,
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(height: trackHeight)

                // Color-matched thumb
                Circle()
                    .fill(Color(hue: clamped, saturation: 1, brightness: 1))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .offset(x: thumbX - thumbDiameter / 2)
            }
            .frame(height: thumbDiameter)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let newValue = min(max(drag.location.x / width, 0), 1)
                        value = newValue
                    }
            )
        }
        .frame(height: thumbDiameter)
        .accessibilityElement()
        .accessibilityLabel(Text("Hue"))
        .accessibilityValue(Text("\(Int(value * 360)) degrees"))
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / 12.0
            switch direction {
            case .increment:
                value = min(value + step, 1)
            case .decrement:
                value = max(value - step, 0)
            @unknown default:
                break
            }
        }
    }
}
