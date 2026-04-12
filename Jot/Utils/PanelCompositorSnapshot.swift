//
//  PanelCompositorSnapshot.swift
//  Jot
//
//  Window-server-quality snapshots for dismiss animations (Liquid Glass,
//  NSTextView, etc.). Uses ScreenCaptureKit instead of the deprecated
//  CGWindowListCreateImage API, with a view backing-store fallback.

import AppKit
import ScreenCaptureKit

@MainActor
enum PanelCompositorSnapshot {

    /// Best-effort compositor capture; falls back to `viewCacheSnapshot` if SCK fails.
    static func capture(panel: NSPanel, contentView: NSView) async -> NSImage? {
        let windowID = CGWindowID(panel.windowNumber)
        guard windowID != 0 else {
            return viewCacheSnapshot(of: contentView)
        }
        do {
            let shareable = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let scWindow = shareable.windows.first(where: { $0.windowID == windowID }) else {
                return viewCacheSnapshot(of: contentView)
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            let scale = max(1.0, (panel.screen ?? NSScreen.main)?.backingScaleFactor ?? 2.0)
            let bounds = contentView.bounds
            config.width = max(1, Int(ceil(bounds.width * scale)))
            config.height = max(1, Int(ceil(bounds.height * scale)))
            config.showsCursor = false
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            let size = NSSize(width: bounds.width, height: bounds.height)
            return NSImage(cgImage: cgImage, size: size)
        } catch {
            return viewCacheSnapshot(of: contentView)
        }
    }

    /// Fallback: `cacheDisplay` path (may miss Liquid Glass — matches legacy GenieDismiss behavior).
    static func viewCacheSnapshot(of view: NSView) -> NSImage? {
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
}
