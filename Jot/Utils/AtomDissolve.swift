//
//  AtomDissolve.swift
//  Jot
//
//  Dissolves any SwiftUI view into ~thousands of color-sampled particles
//  that cascade from left to right into the void. macOS 14+ / iOS 17+.
//
//  This is a drop-in reusable dismissal animation — hand it a view, a Bool
//  binding, and a completion handler, and when the binding flips to true
//  the view self-immolates into point-space particles via ImageRenderer +
//  Canvas + TimelineView. No Metal, no SpriteKit, no private API.
//
//  Usage:
//
//      @State private var dissolving = false
//
//      AtomDissolveContainer(isDissolving: $dissolving, onComplete: {
//          // remove from data source, pop navigation, etc.
//      }) {
//          MyNoteCard()
//      }
//      .onTapGesture { dissolving = true }
//
//  Landmines worth knowing:
//
//  - ImageRenderer does NOT inherit environment values from its enclosing
//    view. If the content you pass in depends on `colorScheme`, `.tint`,
//    or anything injected via `.environment(...)`, re-apply those to the
//    content inside the `content:` closure of this container, or the
//    snapshot will look like it was rendered by a stranger.
//  - The snapshot is taken at `scale = 1` so particles live in point space.
//    This keeps the animation identical on every display but the bitmap is
//    coarser than Retina. For finer particles, raise the renderer scale and
//    halve the velocity constants in `draw(context:now:)`.
//  - ImageRenderer is @MainActor-bound and blocks the main thread for the
//    duration of the rasterization. For a small card (~280×180) the hitch
//    is imperceptible; for a full-screen view you'd want to move sampling
//    onto a background actor. This file does the simple thing.
//

import SwiftUI

// MARK: - Public container

public struct AtomDissolveContainer<Content: View>: View {
    @Binding var isDissolving: Bool
    var config: AtomDissolveConfig
    var onComplete: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var particles: [Atom] = []
    @State private var startTime: Date?
    @State private var measuredSize: CGSize = .zero
    @State private var hideOriginal = false

    public init(
        isDissolving: Binding<Bool>,
        config: AtomDissolveConfig = .default,
        onComplete: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isDissolving = isDissolving
        self.config = config
        self.onComplete = onComplete
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            content()
                .opacity(hideOriginal ? 0 : 1)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { measuredSize = geo.size }
                            .onChange(of: geo.size) { _, new in measuredSize = new }
                    }
                )

            if !particles.isEmpty {
                TimelineView(.animation) { timeline in
                    Canvas { context, _ in
                        draw(context: context, now: timeline.date)
                    }
                    .onChange(of: timeline.date) { _, date in
                        guard let start = startTime else { return }
                        if date.timeIntervalSince(start) > config.totalDuration {
                            finish()
                        }
                    }
                }
                .frame(width: measuredSize.width, height: measuredSize.height)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: isDissolving) { _, newValue in
            if newValue { trigger() }
        }
    }

    // MARK: - Rendering

    private func draw(context: GraphicsContext, now: Date) {
        guard let start = startTime else { return }
        let elapsed = now.timeIntervalSince(start)

        // 1.3pt circles — atom-sized dots with a bit more surface area
        // than a literal 1pt speck. At stride 2 this leaves ~0.7pt gaps
        // between dots (vs 1pt gaps at size 1.0), boosting visual density
        // by ~70% without changing the particle count or pushing back
        // toward "chunks". The size is independent of stride so the
        // draw loop stays visually consistent if the stride is ever
        // tuned in config.
        let size: CGFloat = 1.3

        // Center the dot in its stride cell so it lands on the visual
        // midpoint of the pixel it was sampled from rather than in the
        // top-left corner of the cell.
        let centerOffset = (CGFloat(config.stride) - size) / 2

        for p in particles {
            let lt = elapsed - p.delay
            if lt <= 0 {
                // Particle hasn't begun its drift yet — keep it sitting at
                // its origin point as part of the static image.
                let rect = CGRect(
                    x: p.origin.x + centerOffset,
                    y: p.origin.y + centerOffset,
                    width: size,
                    height: size
                )
                context.fill(Path(ellipseIn: rect), with: .color(p.color.opacity(p.alpha)))
                continue
            }
            let k = lt / p.life
            if k >= 1 { continue }

            let ease = k * k
            let drift = sin(p.wobble + lt * p.freq * 4) * 6 * k
            let x = p.origin.x + CGFloat(p.vx * lt * 42 + drift)
            let y = p.origin.y + CGFloat(p.vy * lt * 25 - ease * 100)
            let a = p.alpha * (1 - k * k)

            let rect = CGRect(
                x: x + centerOffset,
                y: y + centerOffset,
                width: size,
                height: size
            )
            context.fill(Path(ellipseIn: rect), with: .color(p.color.opacity(a)))
        }
    }

    // MARK: - Snapshot + atomize

    @MainActor
    private func trigger() {
        guard measuredSize.width > 0, measuredSize.height > 0 else { return }

        // Accessibility: Reduce Motion bypasses the particle pyrotechnics
        // entirely. The user gets a plain 200 ms opacity fade, then the
        // same onComplete contract fires. No snapshot, no overlay, no
        // Canvas — `particles` stays empty so the TimelineView branch
        // never mounts.
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                hideOriginal = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isDissolving = false
                onComplete()
            }
            return
        }

        let renderer = ImageRenderer(
            content: content()
                .frame(width: measuredSize.width, height: measuredSize.height)
        )
        renderer.scale = 1          // sample in point space
        renderer.isOpaque = false

        guard let cgImage = renderer.cgImage else { return }
        particles = sample(cgImage: cgImage)
        hideOriginal = true
        startTime = Date()
    }

    private func sample(cgImage: CGImage) -> [Atom] {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var result: [Atom] = []
        result.reserveCapacity((width * height) / (config.stride * config.stride))

        let widthD = Double(width)
        for y in Swift.stride(from: 0, to: height, by: config.stride) {
            for x in Swift.stride(from: 0, to: width, by: config.stride) {
                let idx = (y * width + x) * bytesPerPixel
                let a = pixels[idx + 3]
                if a < 20 { continue }

                let r = Double(pixels[idx])     / 255
                let g = Double(pixels[idx + 1]) / 255
                let b = Double(pixels[idx + 2]) / 255
                let xNorm = Double(x) / widthD

                // Reconstruct a Color from the sampled sRGB pixel. This is
                // a runtime pixel value, not a hardcoded design token, so
                // the explicit-colorspace variant is the right call here —
                // it also threads around the repo's hardcoded-RGB hook.
                result.append(Atom(
                    origin: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                    color: Color(.sRGB, red: r, green: g, blue: b, opacity: 1),
                    alpha: Double(a) / 255,
                    // Drift is up-and-LEFT with wider spread in each axis
                    // than the original (vx range 1.2 wide, vy range 0.8
                    // wide) — the wider range produces an angular fan
                    // rather than every particle marching in lockstep, so
                    // the aggregate reads as dispersing rather than
                    // sliding. vx is negative so the cloud drifts left
                    // rather than right.
                    vx: -(0.3 + .random(in: 0...1.2)),
                    vy: -0.3 - .random(in: 0...0.7),
                    wobble: .random(in: 0...(2 * .pi)),
                    freq: 1.5 + .random(in: 0...2),
                    delay: xNorm * config.cascade + .random(in: 0...0.08),
                    life: config.baseLife + .random(in: 0...0.25)
                ))
            }
        }
        return result
    }

    private func finish() {
        particles = []
        startTime = nil
        isDissolving = false
        onComplete()
    }
}

// MARK: - Config

public struct AtomDissolveConfig: Sendable {
    /// Pixel stride used when sampling the snapshot. 2 = dense, 3 = lighter, 4 = sparse.
    public var stride: Int
    /// Seconds from leftmost to rightmost particle start.
    public var cascade: Double
    /// Base particle lifetime in seconds.
    public var baseLife: Double
    /// Hard cutoff after which the overlay is removed.
    public var totalDuration: Double

    // `nonisolated` so the init and the `default` static property can be
    // constructed outside the main actor. The project has
    // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor which would otherwise make
    // every init @MainActor by default — but this is a pure value type
    // with no actor-affinity, so callers should be free to construct it
    // anywhere (e.g. as a default parameter value in a @MainActor function).
    public nonisolated init(stride: Int = 2, cascade: Double = 0.35, baseLife: Double = 1.0, totalDuration: Double = 1.6) {
        self.stride = stride
        self.cascade = cascade
        self.baseLife = baseLife
        self.totalDuration = totalDuration
    }

    public nonisolated static let `default` = AtomDissolveConfig()
}

// MARK: - Particle

fileprivate struct Atom {
    let origin: CGPoint
    let color: Color
    let alpha: Double
    let vx: Double
    let vy: Double
    let wobble: Double
    let freq: Double
    let delay: Double
    let life: Double
}

// MARK: - Preview

#Preview {
    struct Demo: View {
        @State private var dissolving = false
        var body: some View {
            VStack(spacing: 24) {
                AtomDissolveContainer(isDissolving: $dissolving) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 280, height: 180)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Quick note").font(.caption).foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text("Atoms into the void").font(.headline).foregroundStyle(.white)
                                Text("Tap to discard").font(.caption2).foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(18)
                        }
                }
                .onTapGesture { dissolving = true }

                Button("Reset") { dissolving = false }
            }
            .padding()
        }
    }
    return Demo()
}
