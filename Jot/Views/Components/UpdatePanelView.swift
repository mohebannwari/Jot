import SwiftUI

// MARK: - Variant

enum UpdatePanelVariant: Equatable {
    case relaunch(version: String)
    case success
}

// MARK: - UpdatePanelView

struct UpdatePanelView: View {
    let variant: UpdatePanelVariant
    var imageYOffset: CGFloat = -80
    var onRelaunch: () -> Void = {}
    var onRemindLater: () -> Void = {}
    var onViewChangelog: () -> Void = {}
    var onDismiss: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    private let cardHeight: CGFloat = 112
    private let outerRadius: CGFloat = 22
    private let innerRadius: CGFloat = 20 // concentric: 22 - 2

    var body: some View {
        VStack(spacing: 0) {
            cardContent

            if case .relaunch = variant {
                buttonSection
            }
        }
        .padding(2)
        .thinLiquidGlass(in: RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
    }

    // MARK: - Card

    private var cardContent: some View {
        ZStack(alignment: .topLeading) {
            backgroundLayer

            VStack(alignment: .leading, spacing: 12) {
                iconView
                headerSection
            }
            .padding(16)

            if case .success = variant {
                closeButton
            }
        }
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        GeometryReader { geo in
            Image("SettingsThemeAuto")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(1.5)
                .offset(x: 20, y: imageYOffset)
                .clipped()
        }
        .overlay(alignment: .bottom) { gradientOverlay }
    }

    private var gradientOverlay: some View {
        // On macOS 26+ the glass material shows through, so fade to clear.
        // On older systems, fade to a solid surface color.
        let surfaceColor: Color = {
            if #available(macOS 26.0, iOS 26.0, *) {
                return colorScheme == .dark
                    ? Color.black.opacity(0.85)
                    : Color.white.opacity(0.85)
            } else {
                return colorScheme == .dark
                    ? Color(red: 0.07, green: 0.06, blue: 0.05)
                    : Color(red: 0.906, green: 0.898, blue: 0.894)
            }
        }()

        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.15),
                .init(color: surfaceColor.opacity(0.5), location: 0.40),
                .init(color: surfaceColor.opacity(0.85), location: 0.55),
                .init(color: surfaceColor, location: 0.68),
                .init(color: surfaceColor, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconView: some View {
        let iconImage: String = {
            switch variant {
            case .relaunch: return "IconUpdateDownload"
            case .success: return "IconUpdateSuccess"
            }
        }()

        Image(iconImage)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 33)
            .foregroundStyle(Color("PrimaryTextColor"))
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch variant {
            case .relaunch(let version):
                Text("Update to version \(version)")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color("PrimaryTextColor"))

                Text("Relaunch to apply")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(Color("SecondaryTextColor"))

            case .success:
                Text("Update successful!")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color("PrimaryTextColor"))

                changelogLink
            }
        }
    }

    // MARK: - Changelog Link (looping shimmer)

    private var changelogLink: some View {
        Button(action: onViewChangelog) {
            HStack(spacing: 4) {
                ShimmerText(
                    text: "View changelog",
                    font: .system(size: 12, weight: .medium),
                    tracking: -0.3,
                    baseColor: Color("SecondaryTextColor"),
                    isLooping: true
                )

                Image("arrow-up-right")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Close Button (glass circle)

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image("IconCrossMedium")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                        .foregroundStyle(Color("PrimaryTextColor").opacity(0.7))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }
        }
        .padding(10)
    }

    // MARK: - Border Gradient

    private var borderGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.639, green: 0.573, blue: 0.259), location: 0),      // #A39242
                .init(color: Color(red: 0.353, green: 0.353, blue: 0.173), location: 0.14),    // #5A5A2C
                .init(color: Color(red: 0.208, green: 0.192, blue: 0.110), location: 0.56),    // #35311C
                .init(color: Color("BorderSubtleColor"), location: 1.0),
            ],
            startPoint: UnitPoint(x: 0.45, y: 0),
            endPoint: UnitPoint(x: 0.55, y: 1)
        )
    }

    // MARK: - Button Section

    private var buttonSection: some View {
        VStack(spacing: 8) {
            ShimmerButton(
                label: "Relaunch",
                action: onRelaunch
            )

            Button(action: onRemindLater) {
                Text("Remind me later")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color("SecondaryTextColor"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
    }
}

// MARK: - Shimmer Colors (shared)

private let shimmerStops: [Gradient.Stop] = [
    .init(color: .clear, location: 0),
    .init(color: .clear, location: 0.25),
    .init(color: Color(red: 0.776, green: 0.475, blue: 0.769).opacity(0.9), location: 0.35),  // #C679C4
    .init(color: Color(red: 0.980, green: 0.239, blue: 0.114), location: 0.42),               // #FA3D1D
    .init(color: Color(red: 1.000, green: 0.690, blue: 0.020), location: 0.50),               // #FFB005
    .init(color: Color(red: 0.882, green: 0.882, blue: 0.996), location: 0.58),               // #E1E1FE
    .init(color: Color(red: 0.012, green: 0.345, blue: 0.969).opacity(0.9), location: 0.65),  // #0358F7
    .init(color: .clear, location: 0.75),
    .init(color: .clear, location: 1.0),
]

private func shimmerOffset(phase: CGFloat, width: CGFloat) -> CGFloat {
    let totalWidth = width * 3
    return -totalWidth + (totalWidth * phase)
}

private func startShimmerLoop(
    phase: Binding<CGFloat>,
    task: Binding<Task<Void, Never>?>,
    initialDelay: Double = 0.5,
    sweepDuration: Double = 1.5,
    pauseDuration: Double = 3.0
) {
    task.wrappedValue?.cancel()
    task.wrappedValue = Task { @MainActor in
        do {
            try await Task.sleep(for: .seconds(initialDelay))

            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: sweepDuration)) {
                    phase.wrappedValue = 1
                }

                try await Task.sleep(for: .seconds(sweepDuration))

                var t = Transaction(animation: nil)
                t.disablesAnimations = true
                withTransaction(t) {
                    phase.wrappedValue = 0
                }

                try await Task.sleep(for: .seconds(pauseDuration))
            }
        } catch {
            // CancellationError -- task exits cleanly
        }
    }
}

// MARK: - Shimmer Button (looping shimmer on entire button surface)

private struct ShimmerButton: View {
    let label: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerPhase: CGFloat = 0
    @State private var shimmerTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(Color("ButtonPrimaryTextColor"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color("ButtonPrimaryBgColor"))
                .overlay { shimmerOverlay }
                .clipShape(Capsule())
                .shadow(color: .white.opacity(0.8), radius: 4, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .onAppear {
            startShimmerLoop(phase: $shimmerPhase, task: $shimmerTask)
        }
        .onDisappear { shimmerTask?.cancel() }
    }

    private var shimmerOverlay: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: shimmerStops,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 3)
            .offset(x: shimmerOffset(phase: shimmerPhase, width: geo.size.width))
            .blendMode(colorScheme == .dark ? .screen : .multiply)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shimmer Text (gradient sweep on text, supports looping)

private struct ShimmerText: View {
    let text: String
    let font: Font
    let tracking: CGFloat
    let baseColor: Color
    var isLooping: Bool = false

    @State private var shimmerPhase: CGFloat = 0
    @State private var shimmerTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Text(text)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(baseColor)

            Text(text)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(.clear)
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(
                            stops: shimmerStops,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 3)
                        .offset(x: shimmerOffset(phase: shimmerPhase, width: geo.size.width))
                    }
                    .clipped()
                    .allowsHitTesting(false)
                }
                .mask {
                    Text(text)
                        .font(font)
                        .tracking(tracking)
                }
        }
        .onAppear {
            startShimmerLoop(
                phase: $shimmerPhase,
                task: $shimmerTask,
                initialDelay: 0.3,
                sweepDuration: 0.85,
                pauseDuration: isLooping ? 3.0 : .infinity
            )
        }
        .onDisappear { shimmerTask?.cancel() }
    }
}
