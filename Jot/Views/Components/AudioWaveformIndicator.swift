//
//  AudioWaveformIndicator.swift
//  Jot
//
//  Compact 18x18 audio visualizer for the meeting recording panel.
//  Recording state: 4 vertical bars reactive to AudioRecorder.levels.
//  Paused state: 4 static horizontal dots.
//

import SwiftUI

struct AudioWaveformIndicator: View {
    let levels: [Float]
    let isPaused: Bool

    private let barCount = 4
    private let sampleIndices = [5, 10, 17, 23]
    private let size: CGFloat = 18

    // Bar geometry
    private let barWidth: CGFloat = 2.5
    private let barGap: CGFloat = 1.5
    private let barMinHeight: CGFloat = 3
    private let barMaxHeight: CGFloat = 14

    // Dot geometry
    private let dotDiameter: CGFloat = 3

    // Figma primitives: red/500 for recording, orange/500 for paused
    private let waveformColor = Color("MeetingRecordingColor")
    private let pausedDotColor = Color("MeetingPausedColor")

    var body: some View {
        Canvas { context, canvasSize in
            if isPaused {
                drawDots(in: context, size: canvasSize)
            } else {
                drawBars(in: context, size: canvasSize)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Canvas Drawing

    private func drawBars(in context: GraphicsContext, size: CGSize) {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = (size.width - totalWidth) / 2

        for i in 0..<barCount {
            let level = sampledLevel(at: i)
            let height = barHeight(for: level)
            let x = startX + CGFloat(i) * (barWidth + barGap)
            let y = (size.height - height) / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
            context.fill(path, with: .color(waveformColor))
        }
    }

    private func drawDots(in context: GraphicsContext, size: CGSize) {
        let totalWidth = CGFloat(barCount) * dotDiameter + CGFloat(barCount - 1) * 2
        let startX = (size.width - totalWidth) / 2
        let centerY = size.height / 2

        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (dotDiameter + 2)
            let rect = CGRect(
                x: x,
                y: centerY - dotDiameter / 2,
                width: dotDiameter,
                height: dotDiameter
            )
            let path = Path(ellipseIn: rect)
            context.fill(path, with: .color(pausedDotColor))
        }
    }

    // MARK: - Helpers

    private func sampledLevel(at index: Int) -> Float {
        guard index < sampleIndices.count, !levels.isEmpty else { return 0 }
        let sampleIndex = sampleIndices[index]
        guard sampleIndex < levels.count else { return 0 }
        return levels[sampleIndex]
    }

    private func barHeight(for level: Float) -> CGFloat {
        let clamped = min(max(CGFloat(level), 0), 1)
        return barMinHeight + clamped * (barMaxHeight - barMinHeight)
    }
}
