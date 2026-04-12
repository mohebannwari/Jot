//
//  AtomDismiss.swift
//  Jot
//
//  Imperative wrapper that runs the SwiftUI AtomDissolveContainer over a
//  window-server snapshot of a panel. Mirrors the carrier pattern used by
//  GenieDismiss.
//
//  Why not embed AtomDissolveContainer directly inside the panel's SwiftUI
//  tree? Because the panel contains TextField and TextEditor, both of which
//  are NSViewRepresentable-backed (NSTextField / NSTextView). Apple's
//  ImageRenderer documentation is explicit:
//
//    "ImageRenderer output only includes views that SwiftUI renders, such
//     as text, images, shapes, and composite views of these types. It does
//     not render views provided by native platform frameworks (AppKit and
//     UIKit) such as... some controls. For these views, ImageRenderer
//     displays a placeholder image."
//
//  The "placeholder image" is a yellow field with a circled cross — exactly
//  the visual we were getting when AtomDissolveContainer tried to snapshot
//  the panel's content directly.
//
//  The escape hatch matches GenieDismiss: ScreenCaptureKit captures compositor
//  pixels (with a cacheDisplay fallback), so we get real composed pixels
//  — including Liquid Glass material, NSTextView text, focus rings, and
//  everything else that lives in the compositor rather than a view backing
//  store. We feed that snapshot into AtomDissolveContainer as an `Image`
//  (which IS a pure SwiftUI primitive ImageRenderer can rasterize cleanly),
//  and the sampled particles end up representing the real panel pixels.
//

import AppKit
import SwiftUI

@MainActor
enum AtomDismiss {

    // MARK: - Public API

    /// Dismisses `panel` with a SwiftUI atom-dissolve animation whose source
    /// image is a window-server snapshot of `panel`'s current pixels. The
    /// real panel is ordered out the instant the carrier is visible, and
    /// `completion` fires when the dissolve finishes and the carrier has
    /// been torn down.
    ///
    /// Default config uses `stride: 2` — densest sampling, producing ~60k
    /// particles for a typical 600×400 panel. With the draw loop back to
    /// plain rect fills (no filters, no blend modes, no gradients), the
    /// per-frame cost is low enough to justify the density. The result is
    /// a fine mist of 2pt coloured specks rather than chunky dots.
    static func run(
        panel: NSPanel,
        config: AtomDissolveConfig = AtomDissolveConfig(
            stride: 2,
            cascade: 0.25,
            baseLife: 0.8,
            totalDuration: 1.1
        ),
        completion: @escaping @MainActor () -> Void
    ) {
        guard let contentView = panel.contentView,
              let screen = panel.screen ?? NSScreen.main else {
            panel.orderOut(nil)
            completion()
            return
        }

        Task { @MainActor in
            guard let snapshot = await PanelCompositorSnapshot.capture(
                panel: panel, contentView: contentView)
            else {
                panel.orderOut(nil)
                completion()
                return
            }

        let panelFrame = panel.frame
        let screenFrame = screen.frame
        let contentSize = contentView.bounds.size

        // Carrier window: full-screen, transparent, borderless, nonactivating.
        // Same setup as GenieDismiss — nonactivating so we don't steal focus
        // from the app the user is returning to, and alphaValue=0 initially
        // so SwiftUI can pay its first-frame cost invisibly before we swap
        // the panel out.
        let carrier = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        carrier.isOpaque = false
        carrier.backgroundColor = .clear
        carrier.hasShadow = false
        carrier.level = panel.level
        carrier.ignoresMouseEvents = true
        carrier.isMovable = false
        carrier.isReleasedWhenClosed = false
        carrier.alphaValue = 0
        carrier.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle
        ]

        // Convert the panel's position from screen-local Cocoa coordinates
        // (bottom-left origin) into carrier-local SwiftUI coordinates
        // (top-left origin). The carrier shares the screen bounds, so the
        // X translation is straightforward; the Y flip mirrors the panel
        // across the screen's vertical axis.
        let panelTopLeft = CGPoint(
            x: panelFrame.minX - screenFrame.minX,
            y: screenFrame.height - (panelFrame.minY - screenFrame.minY) - panelFrame.height
        )

        // Host the SwiftUI overlay that drives the dissolve. The overlay
        // owns the `isDissolving` state and flips it true on appear so the
        // animation kicks off as soon as the carrier is laid out.
        let overlay = AtomDismissOverlay(
            image: snapshot,
            imageSize: contentSize,
            panelTopLeft: panelTopLeft,
            config: config,
            onDone: { [weak carrier] in
                carrier?.orderOut(nil)
                completion()
            }
        )
        let hosting = NSHostingView(rootView: overlay)
        hosting.frame = NSRect(origin: .zero, size: screenFrame.size)
        hosting.autoresizingMask = [.width, .height]
        carrier.contentView = hosting

        carrier.orderFront(nil)

        // Pre-warm: give SwiftUI one runloop cycle with the carrier front
        // but at alpha 0 so Canvas/ImageRenderer can compile their Metal
        // pipelines invisibly. On the next tick, swap the panel out and
        // flip the carrier visible in the same synchronous block.
        DispatchQueue.main.async {
            panel.orderOut(nil)
            panel.alphaValue = 1.0
            carrier.alphaValue = 1.0
        }
        }
    }
}

// MARK: - SwiftUI overlay

/// Hosts the AtomDissolveContainer with an Image(nsImage:) as its content,
/// positioned at the original panel's top-left corner within the full-screen
/// carrier. Flips `dissolving` on appear so the animation runs immediately.
///
/// Drift padding: the particle formula in AtomDissolveContainer pushes
/// particles up to ~122pt upward and ~70pt rightward from their sample
/// origin. SwiftUI's Canvas clips drawings to its frame bounds (per the
/// WWDC21 "Add rich graphics" session; undocumented in the reference but
/// consistently observed), so without padding the drifting particles would
/// clip at the top and right edges of the panel image and produce a visible
/// hard cutoff. Padding the Image inside the container extends the Canvas
/// frame outward, and the compensating negative offset keeps the image
/// itself pinned to the panel's original on-screen position.
@MainActor
private struct AtomDismissOverlay: View {
    let image: NSImage
    let imageSize: CGSize
    let panelTopLeft: CGPoint
    let config: AtomDissolveConfig
    let onDone: () -> Void

    @State private var dissolving = false

    /// Padding around the image inside the AtomDissolveContainer. Values
    /// chosen to comfortably contain the worst-case drift of any particle
    /// spawned along the matching edge. Particles now drift up-and-LEFT
    /// (see vx/vy in AtomDissolveContainer.sample), so the generous
    /// margins live on the TOP and LEADING edges. Downward/rightward drift
    /// is negligible and just gets a small safety margin.
    private static let driftPadding = EdgeInsets(
        top: 160,
        leading: 140,
        bottom: 40,
        trailing: 40
    )

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            AtomDissolveContainer(
                isDissolving: $dissolving,
                config: config,
                onComplete: onDone
            ) {
                // Image IS a pure SwiftUI primitive that ImageRenderer can
                // rasterize. The AtomDissolveContainer's internal trigger()
                // will run ImageRenderer on this Image view and get back
                // a clean CGImage of the original panel snapshot — no
                // yellow placeholder. The padding around the Image expands
                // the container's measured size so the Canvas frame has
                // room for drifting particles (see type doc above).
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageSize.width, height: imageSize.height)
                    .padding(Self.driftPadding)
            }
            // Compensate the padding so the Image itself still lands at
            // the panel's original top-left corner on screen.
            .offset(
                x: panelTopLeft.x - Self.driftPadding.leading,
                y: panelTopLeft.y - Self.driftPadding.top
            )
        }
        .ignoresSafeArea()
        .onAppear {
            // Defer one runloop tick so the hosting view has finished its
            // first layout pass and the AtomDissolveContainer has measured
            // its content size before trigger() reads measuredSize.
            DispatchQueue.main.async {
                dissolving = true
            }
        }
    }
}
