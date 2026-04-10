//
//  GenieDismiss.swift
//  Jot
//
//  Public-API genie animation for the Quick Notes save dismiss. Uses
//  SpriteKit's SKWarpGeometryGrid to mesh-warp a snapshot of the panel along
//  a grid that curves and contracts toward a target point on screen —
//  visually matching the dock's genie minimize-to-dock effect without
//  touching the private CGSSetWindowWarp / CAMeshTransform APIs that would
//  get the app rejected from the Mac App Store (ITMS-90338).
//
//  Flow:
//    1. Snapshot the panel's contentView into an NSImage.
//    2. Build a transparent full-screen carrier NSPanel hosting an SKView.
//    3. Position an SKSpriteNode at the panel's original screen location,
//       sized to match the panel, textured with the snapshot.
//    4. Build a keyframe sequence of SKWarpGeometryGrid states that pull
//       vertices toward the target. Rows closest to the target absorb first,
//       producing the trailing-tail feel of the real genie.
//    5. Order the panel out the moment the animation starts; when the SKAction
//       sequence completes, tear down the carrier and fire the completion.
//

import AppKit
import CoreGraphics
import SpriteKit

@MainActor
enum GenieDismiss {

    // MARK: - Public API

    /// Dismisses `panel` with a SpriteKit warp-grid genie animation whose
    /// collapse point is `targetPoint`, expressed in Cocoa screen coordinates.
    ///
    /// The real panel is ordered out the instant the animation starts (the
    /// user sees the snapshot carrier, not the original), and its
    /// `alphaValue` is reset to 1 before `completion` fires so the same panel
    /// instance can be reused on the next show.
    static func run(
        panel: NSPanel,
        toward targetPoint: CGPoint,
        duration: TimeInterval = 0.55,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let contentView = panel.contentView,
              let screen = panel.screen ?? NSScreen.main,
              let snapshot = windowSnapshot(of: panel) ?? snapshotImage(of: contentView)
        else {
            panel.orderOut(nil)
            completion()
            return
        }

        let panelFrame = panel.frame
        let screenFrame = screen.frame

        // Carrier window: full-screen, transparent, borderless, nonactivating.
        // Nonactivating is critical — we don't want the animation to steal
        // focus from whichever app the user is returning to. Initial
        // alphaValue is 0 so we can install the SKView and let SpriteKit
        // pay the first-frame cost (Metal pipeline setup, shader compile,
        // texture upload) before the carrier becomes visible. Without this
        // pre-warm, the first ~16 ms of the animation would show whatever
        // SKView's CAMetalLayer happens to have in its backing store —
        // which in practice reads as a bright flash.
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
        carrier.alphaValue = 0  // invisible until the pre-warm frame lands
        carrier.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle
        ]

        // SKView hosts the SpriteKit scene. allowsTransparency + a clear
        // scene background lets the carrier's transparency show through
        // everywhere the sprite isn't drawing. isAsynchronous = false forces
        // the Metal pipeline onto the main thread so our one-shot animation
        // isn't racing a background render worker.
        //
        // Do NOT set preferredFramesPerSecond above 60 here — when the GPU
        // can't hit the higher target (full-screen SKView + CI filter on a
        // warping sprite is a fair bit of work), vsync drops the effective
        // rate hard and the animation stutters. 60fps steady is vastly
        // better than 120fps aspirational.
        let skView = SKView(frame: NSRect(origin: .zero, size: screenFrame.size))
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        skView.shouldCullNonVisibleNodes = false
        skView.isAsynchronous = false
        carrier.contentView = skView

        let scene = SKScene(size: screenFrame.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.anchorPoint = .zero  // bottom-left origin, matching AppKit.

        // Translate the panel's frame and the target point from global screen
        // coordinates into scene-local coordinates (scene origin = carrier
        // window origin = this screen's bottom-left).
        let spriteCenterInScene = CGPoint(
            x: panelFrame.midX - screenFrame.minX,
            y: panelFrame.midY - screenFrame.minY
        )
        let targetInScene = CGPoint(
            x: targetPoint.x - screenFrame.minX,
            y: targetPoint.y - screenFrame.minY
        )

        let texture = SKTexture(image: snapshot)
        texture.filteringMode = .linear
        let sprite = SKSpriteNode(texture: texture, size: contentView.bounds.size)
        sprite.position = spriteCenterInScene
        scene.addChild(sprite)

        // Note: earlier revisions wrapped the sprite in an SKEffectNode with
        // a CIBoxBlur to get a dissolve feel. That turned out to be the root
        // cause of the jank the user reported — SKEffectNode with any CI
        // filter rasterizes the sprite to an offscreen texture every frame,
        // applies the filter chain, and composites back. Because the warp
        // geometry changes every tick, the offscreen cache is invalidated on
        // every frame and the rasterize→filter→composite round-trip on a
        // full-screen SKView blows the 16 ms frame budget. Rendering the
        // sprite directly through Metal with the warp applied as a vertex
        // transform is several times cheaper and reads much smoother.
        //
        // If the no-effect version feels "too hard" at the end of the fade,
        // the right fix is to lean on `SKAction.scale(to:duration:)` running
        // concurrently with the warp so the pixels downsample naturally —
        // NOT to reintroduce the effect node.

        // Build the warp keyframe sequence. The first warp is applied
        // immediately (before the carrier becomes visible) so there's no
        // one-frame snap from identity → first keyframe.
        let (warps, times) = makeWarps(
            spriteSize: contentView.bounds.size,
            spriteCenterInScene: spriteCenterInScene,
            targetInScene: targetInScene,
            duration: duration
        )
        if let first = warps.first {
            sprite.warpGeometry = first
        }

        // Present the scene and order the carrier front while it is still
        // at alphaValue = 0. SpriteKit then has the runloop cycle we grant
        // below to pay its first-frame cost (Metal pipeline, shader compile,
        // texture upload) invisibly. Only after that do we actually swap
        // panel → carrier and start the animation.
        skView.presentScene(scene)
        carrier.orderFront(nil)

        // SKAction.animate(withWarps:times:) is marked optional in the
        // header for historical (Obj-C) reasons but never returns nil in
        // practice when warps.count == times.count. Force-unwrap after the
        // invariant check so a mismatch crashes loudly in debug builds
        // rather than silently skipping the animation.
        precondition(warps.count == times.count, "warps/times count mismatch")
        let warpAction = SKAction.animate(withWarps: warps, times: times)!

        // Fade runs CONCURRENTLY with the warp. The sprite stays fully
        // opaque through the first 40 % of the suck so you can see the
        // shape collapsing, then dissolves out over the remaining 60 %
        // with ease-out timing.
        let fadeHold = SKAction.wait(forDuration: duration * 0.4)
        let fadeOut = SKAction.fadeOut(withDuration: duration * 0.6)
        fadeOut.timingMode = .easeOut
        let fadeSequence = SKAction.sequence([fadeHold, fadeOut])

        let sequence = SKAction.group([warpAction, fadeSequence])

        // Pre-warm: give SpriteKit one runloop cycle with the carrier
        // already front-of-screen but at alphaValue = 0. During that cycle,
        // Metal compiles, the texture uploads, and the first frame of the
        // scene renders into SKView's backing store. On the next tick we
        // flip the panel out and the carrier up in the same synchronous
        // block, and fire the action — the user never sees SKView's empty
        // first frame because by the time the carrier is visible, the
        // backing store already holds the correctly-warped sprite.
        DispatchQueue.main.async {
            panel.orderOut(nil)
            panel.alphaValue = 1.0
            carrier.alphaValue = 1.0

            sprite.run(sequence) {
                // SKAction completion blocks fire on SpriteKit's update
                // queue, not the main actor — hop explicitly.
                Task { @MainActor in
                    carrier.orderOut(nil)
                    completion()
                }
            }
        }
    }

    // MARK: - Snapshot

    /// Captures what the window server is actually drawing for `panel` —
    /// including the Liquid Glass material, which lives in the window
    /// server's compositor, not in the view's backing store. A plain
    /// `cacheDisplay(in:to:)` on the contentView misses the glass pillow and
    /// produces a flat transparent snapshot with only the text visible.
    /// `CGWindowListCreateImage` goes through the window server so what you
    /// see is what you get.
    ///
    /// Returns `nil` on failure; `run` falls back to the view-cache path.
    private static func windowSnapshot(of panel: NSPanel) -> NSImage? {
        let windowID = CGWindowID(panel.windowNumber)
        guard windowID != 0 else { return nil }
        guard let cgImage = CGWindowListCreateImage(
            .null,                       // let the system use the window's own bounds
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }
        // Size the NSImage to the panel's contentView bounds so the texture
        // we hand SpriteKit has the same point-space dimensions the sprite
        // node will use — avoids Retina double-scale in the warp grid.
        let size = panel.contentView?.bounds.size
            ?? NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        return NSImage(cgImage: cgImage, size: size)
    }

    /// Fallback: renders `view` into an NSImage via the layer-backed
    /// cacheDisplay path. Used only if `windowSnapshot` fails (e.g., the
    /// window has no windowNumber yet). Will miss Liquid Glass material.
    private static func snapshotImage(of view: NSView) -> NSImage? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Warp geometry

    /// Builds the keyframe sequence of `SKWarpGeometryGrid` states that drive
    /// the genie effect. Vertices start at their identity positions and
    /// progressively converge on `targetInScene` (translated into sprite-local
    /// normalized coordinates). Rows on the edge closest to the target absorb
    /// first — this is what produces the characteristic trailing-tail of the
    /// dock genie where the near side is sucked in before the far side
    /// catches up.
    ///
    /// The grid is intentionally coarse in the horizontal direction (3 cols)
    /// and fine in the vertical direction (21 rows) because the warp's visual
    /// interest is along the vertical axis of absorption — extra horizontal
    /// subdivisions would add tessellation cost without changing the look.
    private static func makeWarps(
        spriteSize: CGSize,
        spriteCenterInScene: CGPoint,
        targetInScene: CGPoint,
        duration: TimeInterval
    ) -> (warps: [SKWarpGeometryGrid], times: [NSNumber]) {
        let columns = 2
        let rows = 20
        let keyframeCount = 16

        // Identity source positions — evenly spaced normalized vertices from
        // (0,0) at the bottom-left of the sprite to (1,1) at the top-right.
        // (columns+1) × (rows+1) vertices total.
        var sourcePositions: [SIMD2<Float>] = []
        sourcePositions.reserveCapacity((columns + 1) * (rows + 1))
        for r in 0...rows {
            for c in 0...columns {
                sourcePositions.append(SIMD2<Float>(
                    Float(c) / Float(columns),
                    Float(r) / Float(rows)
                ))
            }
        }

        // Translate the target from scene coords into sprite-local normalized
        // coords. For a target far from the sprite these will be outside
        // [0, 1] — SpriteKit renders warp vertices outside that range without
        // clipping, which is exactly what we need to carry the content all the
        // way to the target point.
        let spriteBL = CGPoint(
            x: spriteCenterInScene.x - spriteSize.width / 2,
            y: spriteCenterInScene.y - spriteSize.height / 2
        )
        let targetLocal = SIMD2<Float>(
            Float((targetInScene.x - spriteBL.x) / spriteSize.width),
            Float((targetInScene.y - spriteBL.y) / spriteSize.height)
        )

        // Decide which edge leads the absorption based on the target's
        // position relative to the sprite. If the target sits below the
        // sprite's vertical center (targetLocal.y < 0.5), the bottom row
        // absorbs first — matches the real dock genie when the dock is at
        // the bottom of the screen. For a target above, the top leads; for a
        // target to the side, we still lead with the bottom since horizontal
        // absorption looks wrong when rows stay vertical.
        let targetIsBelow = targetLocal.y < 0.5

        /// Returns a value in [0, 1] where 0 means "this row is on the leading
        /// edge (absorbs first)" and 1 means "this row is on the trailing edge
        /// (absorbs last)".
        func rowRank(_ r: Int) -> Float {
            let normalized = Float(r) / Float(rows)
            return targetIsBelow ? normalized : (1 - normalized)
        }

        var warps: [SKWarpGeometryGrid] = []
        var times: [NSNumber] = []
        warps.reserveCapacity(keyframeCount + 1)
        times.reserveCapacity(keyframeCount + 1)

        // Stagger window: the fraction of total progress spent on the
        // leading→trailing row delay. A bigger window = more pronounced tail.
        let staggerWindow: Float = 0.45

        for k in 0...keyframeCount {
            let t = Float(k) / Float(keyframeCount)   // linear 0...1
            // Quadratic ease-in — the suck accelerates toward the target,
            // matching the dock genie's acceleration curve.
            let eased = t * t

            var destPositions: [SIMD2<Float>] = []
            destPositions.reserveCapacity(sourcePositions.count)

            for r in 0...rows {
                let rank = rowRank(r)
                // Each row's own 0→1 progress inside the staggered window.
                let rowStart = rank * staggerWindow
                let rowSpan = 1 - rowStart
                let rowT = max(0, min(1, (eased - rowStart) / rowSpan))

                for c in 0...columns {
                    let source = SIMD2<Float>(
                        Float(c) / Float(columns),
                        Float(r) / Float(rows)
                    )
                    destPositions.append(mix(source, targetLocal, t: rowT))
                }
            }

            let warp = SKWarpGeometryGrid(
                columns: columns,
                rows: rows,
                sourcePositions: sourcePositions,
                destinationPositions: destPositions
            )
            warps.append(warp)
            times.append(NSNumber(value: Double(t) * duration))
        }

        return (warps, times)
    }

    private static func mix(_ a: SIMD2<Float>, _ b: SIMD2<Float>, t: Float) -> SIMD2<Float> {
        SIMD2<Float>(
            a.x * (1 - t) + b.x * t,
            a.y * (1 - t) + b.y * t
        )
    }
}
