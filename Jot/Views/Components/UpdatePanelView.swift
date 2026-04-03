import SwiftUI

// MARK: - Variant

enum UpdatePanelVariant: Equatable {
    case downloading(version: String)
    case relaunch(version: String)
}

// MARK: - UpdatePanelView

struct UpdatePanelView: View {
    let variant: UpdatePanelVariant
    var onRelaunch: () -> Void = {}
    var onRemindLater: () -> Void = {}
    var isEmbeddedInGlass: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPreparingRelaunch = false

    private let cornerRadius: CGFloat = 22
    // SettingsThemeAuto is 2528×1684 px — keep this ratio locked so the image
    // never stretches when the panel width changes between the regular sidebar
    // (240 pt) and the floating sidebar (224 pt, due to 8 pt horizontal padding).
    private let imageAspectRatio: CGFloat = 2528.0 / 1684.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Content section (icon + header)
            VStack(alignment: .leading, spacing: 12) {
                iconView
                headerSection
            }
            .padding(8)

            // Button section or download progress
            if isPreparingRelaunch {
                downloadProgressSection
            } else {
                buttonSection
            }
        }
        .padding(8)
        .background { backgroundLayer }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Background
    // Figma (relaunch):    image w=274.58% h=245.37% left=-23.42% top=-145.37%
    // Figma (downloading): image w=265.90% h=278.34% left=-20.25% top=-178.16%
    // Gradient: absolute inset-0, transparent -> bg/secondary

    // Gradient endpoint must match the panel's outer container background exactly.
    // SettingsOptionCardColor dark (#0C0A09) provides the near-black needed for
    // the image-to-surface fade; .white is used directly in light mode to avoid
    // dynamic color resolution overhead inside the gradient (matches original).
    private var surfaceColor: Color {
        colorScheme == .dark ? Color("SettingsOptionCardColor") : .white
    }

    private func bgImageLayout(_ size: CGSize) -> (w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat) {
        // Anchor everything to panel WIDTH so the image scales uniformly and
        // never distorts when the panel is narrower in the floating sidebar.
        // y-offsets are pre-computed from the 240 pt Figma design:
        //   relaunch:    original y = 179 * -1.4537 = -260 pt → -260/240 = -1.084 × w
        //   downloading: original y = 153 * -1.7816 = -273 pt → -273/240 = -1.136 × w
        let w = size.width
        let h = size.height
        var imgW: CGFloat
        var x: CGFloat
        var designedY: CGFloat

        if isPreparingRelaunch {
            imgW = w * 2.659
            x = w * -0.2025
            designedY = w * -1.136
        } else {
            imgW = w * 2.7458
            x = w * -0.2342
            designedY = w * -1.084
        }

        let imgH = imgW / imageAspectRatio
        // Ensure image bottom edge reaches container bottom
        let y = max(designedY, h - imgH)
        return (imgW, imgH, x, y)
    }

    private var backgroundLayer: some View {
        surfaceColor
            .overlay {
                GeometryReader { geo in
                    let img = bgImageLayout(geo.size)
                    Image("SettingsThemeAuto")
                        .resizable()
                        .frame(width: img.w, height: img.h)
                        .offset(x: img.x, y: img.y)
                }
                .clipped()
            }
            .overlay {
                LinearGradient(
                    colors: [surfaceColor.opacity(0), surfaceColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    // MARK: - Icon

    private var iconView: some View {
        Image("IconUpdateDownload")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 33)
            .foregroundStyle(Color("PrimaryTextColor"))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Update to version \(variantVersion)")
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.5)
                .lineLimit(1)
                .foregroundStyle(Color("PrimaryTextColor"))

            switch variant {
            case .downloading:
                HStack(spacing: 6) {
                    BrailleLoader(pattern: .orbit, size: 11)
                    Text("Downloading update...")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(-0.3)
                        .foregroundStyle(Color("SecondaryTextColor"))
                }
            case .relaunch:
                Text("Ready to install")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
        }
    }

    private var variantVersion: String {
        switch variant {
        case .downloading(let v), .relaunch(let v): return v
        }
    }

    // MARK: - Button Section

    @ViewBuilder
    private var buttonSection: some View {
        switch variant {
        case .downloading:
            EmptyView()

        case .relaunch:
            VStack(spacing: 8) {
                ShimmerButton(
                    label: "Download & Relaunch",
                    action: {
                        withAnimation(.jotSpring) {
                            isPreparingRelaunch = true
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(12))
                            onRelaunch()
                        }
                    }
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
        }
    }

    // MARK: - Download Progress

    @ViewBuilder
    private var downloadProgressSection: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let content = VStack(spacing: 4) {
            Text("DOWNLOADING...")
                .font(FontManager.metadata(size: 11, weight: .medium))
                .foregroundStyle(Color("PrimaryTextColor"))
                .kerning(0.5)

            BrailleTrailBar(duration: 10)
        }
        .padding(8)

        if isEmbeddedInGlass {
            content
                .background(.thinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        } else {
            content
                .thinLiquidGlass(in: shape)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }
}

// MARK: - Braille Cascade Bar

private struct BrailleTrailBar: View {
    var duration: TimeInterval = 12

    private let helixFrames = BraillePattern.helix.frames
    private let barHeight: CGFloat = 16

    @State private var frameIndex: Int = 0
    @State private var fillProgress: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Cascade braille characters filling the entire bar
                HStack(spacing: 0) {
                    ForEach(0..<tileCount(for: geo.size.width), id: \.self) { i in
                        let tileFrame = (frameIndex + i * 3) % helixFrames.count
                        Text(helixFrames[tileFrame])
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .foregroundStyle(Color.accentColor)
                // Clip to the fill progress width
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: geo.size.width * fillProgress)
                }
            }
        }
        .frame(height: barHeight)
        .background(Color("BorderSubtleColor").opacity(0.15))
        .clipShape(Capsule())
        .onAppear { startAnimation() }
        .onDisappear { animationTask?.cancel() }
    }

    private func tileCount(for width: CGFloat) -> Int {
        let tileWidth: CGFloat = 28
        return max(1, Int(ceil(width / tileWidth)))
    }

    private func startAnimation() {
        animationTask?.cancel()

        // Fill progress: 0 -> 1 over the duration
        // Use linear so the bar fills uniformly and completes before relaunch
        withAnimation(.linear(duration: duration)) {
            fillProgress = 1
        }

        // Cascade frame cycling
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(BraillePattern.helix.nativeInterval))
                guard !Task.isCancelled else { return }
                frameIndex = (frameIndex + 1) % helixFrames.count
            }
        }
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
                .frame(height: 42)
                .background(Color("ButtonPrimaryBgColor"))
                .overlay { shimmerOverlay }
                .clipShape(Capsule())
                .shadow(color: Color("ButtonPrimaryBgColor").opacity(0.3), radius: 8, x: 0, y: 0)
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
