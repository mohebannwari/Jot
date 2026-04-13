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

    @Environment(\.colorScheme) private var colorScheme

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

            buttonSection
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
        // y-offset is pre-computed from the 240 pt Figma design:
        //   relaunch: original y = 179 * -1.4537 = -260 pt → -260/240 = -1.084 × w
        let w = size.width
        let h = size.height
        let imgW = w * 2.7458
        let x = w * -0.2342
        let designedY = w * -1.084

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
            .frame(width: 24, height: 24)
            .foregroundStyle(Color("PrimaryTextColor"))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Update App — \(variantVersion)")
                .font(FontManager.heading(size: 15, weight: .medium))
                .tracking(-0.5)
                .lineLimit(1)
                .foregroundStyle(Color("PrimaryTextColor"))

            switch variant {
            case .downloading:
                HStack(spacing: 6) {
                    BrailleLoader(pattern: .orbit, size: 11)
                    Text("Downloading update…")
                        .font(FontManager.heading(size: 12, weight: .medium))
                        .tracking(-0.3)
                        .foregroundStyle(Color("SecondaryTextColor"))
                }
            case .relaunch:
                Text("Relaunch to finish installing")
                    .font(FontManager.heading(size: 12, weight: .medium))
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
                    label: "Relaunch to update",
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
