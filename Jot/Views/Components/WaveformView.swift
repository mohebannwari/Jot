import SwiftUI

public struct WaveformView: View {
    private let levels: [Float]
    private let barCount: Int
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(levels: [Float],
                barCount: Int = 28,
                barWidth: CGFloat = 3,
                spacing: CGFloat = 2,
                color: Color = .accentColor) {
        self.levels = levels
        self.barCount = barCount
        self.barWidth = barWidth
        self.spacing = spacing
        self.color = color
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: spacing) {
                Spacer(minLength: 0)
                ForEach(0..<min(levels.count, barCount), id: \.self) { index in
                    let level = max(0.05, min(1, levels[index]))
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.85))
                        .frame(width: barWidth,
                               height: max(proxy.size.height * CGFloat(level), proxy.size.height * 0.08))
                        .animation(reduceMotion ? nil : .linear(duration: 0.05), value: levels[index])
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                .blendMode(.screen)
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
struct WaveformView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WaveformView(levels: Array(repeating: 0.3, count: 28))
                .frame(width: 160, height: 40)
                .previewDisplayName("Static")
            WaveformView(levels: stride(from: 0.1 as Float, to: 1.0, by: 0.03).map { min(1, $0) })
                .frame(width: 160, height: 40)
                .preferredColorScheme(.dark)
                .previewDisplayName("Gradient")
        }
    }
}
#endif
