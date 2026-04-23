import SwiftUI

// MARK: - Animation Pattern
// Frame sequences sourced from agilek/cli-loaders (unicode-animations/src/braille.ts)

enum BraillePattern {
    case pulse
    case wave
    case orbit
    case breathe
    case waverows
    case scan
    case sparkle
    case checkerboard
    case cascade
    case snake
    case helix

    var frames: [String] {
        switch self {
        case .pulse:
            // genPulse(): expanding concentric ring, 5 radii, 180ms
            return [
                "⠀⠶⠀",
                "⠰⣿⠆",
                "⢾⣉⡷",
                "⣏⠀⣹",
                "⡁⠀⢈",
            ]
        case .wave:
            // Rotating single-dot positions around a 2x4 cell
            return [
                "⠁⠂⠄⡀⢀⠠⠐⠈",
                "⠂⠄⡀⢀⠠⠐⠈⠁",
                "⠄⡀⢀⠠⠐⠈⠁⠂",
                "⡀⢀⠠⠐⠈⠁⠂⠄",
                "⢀⠠⠐⠈⠁⠂⠄⡀",
                "⠠⠐⠈⠁⠂⠄⡀⢀",
                "⠐⠈⠁⠂⠄⡀⢀⠠",
                "⠈⠁⠂⠄⡀⢀⠠⠐",
            ]
        case .orbit:
            // Classic single-char spinner
            return [
                "⠋",
                "⠙",
                "⠹",
                "⠸",
                "⠼",
                "⠴",
                "⠦",
                "⠧",
                "⠇",
                "⠏",
            ]
        case .breathe:
            // genBreathe(): single char filling dot-by-dot, palindrome, 100ms
            return [
                "⠀", "⠂", "⠌", "⡑", "⢕", "⢝", "⣫", "⣟", "⣿",
                "⣟", "⣫", "⢝", "⢕", "⡑", "⠌", "⠂", "⠀",
            ]
        case .waverows:
            // genWaveRows(): 4-col sinusoidal wave scrolling left, 90ms
            return [
                "⠖⠉⠉⠑",
                "⡠⠖⠉⠉",
                "⣠⡠⠖⠉",
                "⣄⣠⡠⠖",
                "⠢⣄⣠⡠",
                "⠙⠢⣄⣠",
                "⠉⠙⠢⣄",
                "⠊⠉⠙⠢",
                "⠜⠊⠉⠙",
                "⡤⠜⠊⠉",
                "⣀⡤⠜⠊",
                "⢤⣀⡤⠜",
                "⠣⢤⣀⡤",
                "⠑⠣⢤⣀",
                "⠉⠑⠣⢤",
                "⠋⠉⠑⠣",
            ]
        case .scan:
            // genScan(): vertical bar sweeping left-to-right, 70ms
            return [
                "⠀⠀⠀⠀",
                "⡇⠀⠀⠀",
                "⣿⠀⠀⠀",
                "⢸⡇⠀⠀",
                "⠀⣿⠀⠀",
                "⠀⢸⡇⠀",
                "⠀⠀⣿⠀",
                "⠀⠀⢸⡇",
                "⠀⠀⠀⣿",
                "⠀⠀⠀⢸",
            ]
        case .sparkle:
            // genSparkle(): scattered dot patterns shifting around, 150ms
            return [
                "⡡⠊⢔⠡",
                "⠊⡰⡡⡘",
                "⢔⢅⠈⢢",
                "⡁⢂⠆⡍",
                "⢔⠨⢑⢐",
                "⠨⡑⡠⠊",
            ]
        case .checkerboard:
            // genCheckerboard(): alternating checkerboard + diagonal stripes, 250ms
            return [
                "⢕⢕⢕",
                "⡪⡪⡪",
                "⢊⠔⡡",
                "⡡⢊⠔",
            ]
        case .cascade:
            // genCascade(): diagonal band sweeping top-left to bottom-right, 60ms
            return [
                "⠀⠀⠀⠀",
                "⠀⠀⠀⠀",
                "⠁⠀⠀⠀",
                "⠋⠀⠀⠀",
                "⠞⠁⠀⠀",
                "⡴⠋⠀⠀",
                "⣠⠞⠁⠀",
                "⢀⡴⠋⠀",
                "⠀⣠⠞⠁",
                "⠀⢀⡴⠋",
                "⠀⠀⣠⠞",
                "⠀⠀⢀⡴",
                "⠀⠀⠀⣠",
                "⠀⠀⠀⢀",
            ]
        case .snake:
            // genSnake(): 4-dot trail tracing a snake path across 4x4 grid, 80ms
            return [
                "⣁⡀", "⣉⠀", "⡉⠁", "⠉⠉",
                "⠈⠙", "⠀⠛", "⠐⠚", "⠒⠒",
                "⠖⠂", "⠶⠀", "⠦⠄", "⠤⠤",
                "⠠⢤", "⠀⣤", "⢀⣠", "⣀⣀",
            ]
        case .helix:
            // genHelix(): dual sine-wave helix across 8x4 grid, 80ms
            return [
                "⢌⣉⢎⣉", "⣉⡱⣉⡱", "⣉⢎⣉⢎", "⡱⣉⡱⣉",
                "⢎⣉⢎⣉", "⣉⡱⣉⡱", "⣉⢎⣉⢎", "⡱⣉⡱⣉",
                "⢎⣉⢎⣉", "⣉⡱⣉⡱", "⣉⢎⣉⢎", "⡱⣉⡱⣉",
                "⢎⣉⢎⣉", "⣉⡱⣉⡱", "⣉⢎⣉⢎", "⡱⣉⡱⣉",
            ]
        }
    }

    /// Native interval from the source library
    var nativeInterval: TimeInterval {
        switch self {
        case .pulse:        return 0.18
        case .wave:         return 0.08
        case .orbit:        return 0.08
        case .breathe:      return 0.10
        case .waverows:     return 0.09
        case .scan:         return 0.07
        case .sparkle:      return 0.15
        case .checkerboard: return 0.25
        case .cascade:      return 0.06
        case .snake:        return 0.08
        case .helix:        return 0.08
        }
    }
}

// MARK: - Speed

enum BrailleSpeed {
    case slow
    case normal
    case fast
    /// Uses the pattern's native timing from the cli-loaders source
    case native

    func interval(for pattern: BraillePattern) -> TimeInterval {
        switch self {
        case .slow:    return 0.15
        case .normal:  return 0.08
        case .fast:    return 0.05
        case .native:  return pattern.nativeInterval
        }
    }
}

// MARK: - BrailleLoader

struct BrailleLoader: View {
    let pattern: BraillePattern
    var speed: BrailleSpeed = .native
    var size: CGFloat = 11

    @State private var frameIndex: Int = 0
    @State private var animationTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(reduceMotion ? "..." : pattern.frames[frameIndex])
            // Braille animation frames: fixed-width 11 medium; no forced caps (glyphs are not words).
            .font(FontManager.metadata(size: size, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .onAppear { startAnimation() }
            .onDisappear { animationTask?.cancel() }
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(speed.interval(for: pattern)))
                guard !Task.isCancelled else { return }
                frameIndex = (frameIndex + 1) % pattern.frames.count
            }
        }
    }
}
