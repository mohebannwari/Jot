//
//  FloatingToolbarPositioner.swift
//  Jot
//
//  Pure geometry helper for positioning the floating edit toolbar
//  relative to a text selection, with platform-aware window resolution.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

enum FloatingToolbarPositioner {

    struct Result {
        let origin: CGPoint
        let placeAbove: Bool
    }

    /// Calculate the toolbar origin (top-left) given a text selection rect
    /// expressed in window coordinates and the available container size.
    ///
    /// - Parameters:
    ///   - selectionWindowX: Selection rect origin X in window coordinates.
    ///   - selectionWindowY: Selection rect origin Y in window coordinates (AppKit: bottom-left).
    ///   - selectionWidth: Width of the selection rect.
    ///   - selectionHeight: Height of the selection rect.
    ///   - visibleWidth: Fallback container width (used on iOS or when window unavailable).
    ///   - visibleHeight: Fallback container height.
    ///   - toolbarWidth: The fixed width of the toolbar.
    ///   - toolbarHeight: The fixed height of the toolbar.
    ///   - gap: Minimum gap between toolbar and selection.
    static func calculatePosition(
        selectionWindowX: CGFloat,
        selectionWindowY: CGFloat,
        selectionWidth: CGFloat,
        selectionHeight: CGFloat,
        visibleWidth: CGFloat,
        visibleHeight: CGFloat,
        toolbarWidth: CGFloat,
        toolbarHeight: CGFloat = 46,
        gap: CGFloat = 8
    ) -> Result {

        // Resolve actual window dimensions
        #if os(macOS)
        let windowReference = NSApp.keyWindow ?? NSApp.mainWindow
        let windowHeight = windowReference?.contentView?.bounds.height
            ?? windowReference?.frame.height
            ?? visibleHeight
        let windowWidth = windowReference?.contentView?.bounds.width
            ?? windowReference?.frame.width
            ?? visibleWidth
        #else
        let windowHeight = visibleHeight
        let windowWidth = visibleWidth
        #endif

        // Convert AppKit window coordinates (origin bottom-left) to top-left space
        let selectionTopFromTop = max(0, windowHeight - (selectionWindowY + selectionHeight))
        let selectionBottomFromTop = min(windowHeight, selectionTopFromTop + selectionHeight)

        let availableAbove = selectionTopFromTop
        let availableBelow = max(0, windowHeight - selectionBottomFromTop)

        let fitsAbove = availableAbove >= (toolbarHeight + gap)
        let fitsBelow = availableBelow >= (toolbarHeight + gap)

        let minTop = gap
        let maxTop = max(gap, windowHeight - toolbarHeight - gap)

        let targetAboveTop = selectionTopFromTop - gap - toolbarHeight
        let clampedAboveTop = min(max(targetAboveTop, minTop), maxTop)
        let aboveMaintainsGap = (clampedAboveTop + toolbarHeight) <= (selectionTopFromTop - gap + 0.5)

        let targetBelowTop = selectionBottomFromTop + gap
        let clampedBelowTop = min(max(targetBelowTop, minTop), maxTop)
        let belowMaintainsGap = clampedBelowTop >= (selectionBottomFromTop + gap - 0.5)

        // Decide vertical placement — prefer BELOW selection
        var placeAbove = false
        var chosenToolbarTop: CGFloat

        if belowMaintainsGap {
            placeAbove = false
            chosenToolbarTop = clampedBelowTop
        } else if aboveMaintainsGap {
            placeAbove = true
            chosenToolbarTop = clampedAboveTop
        } else if fitsBelow && !fitsAbove {
            placeAbove = false
            chosenToolbarTop = clampedBelowTop
        } else if fitsAbove && !fitsBelow {
            placeAbove = true
            chosenToolbarTop = clampedAboveTop
        } else if availableBelow >= availableAbove {
            placeAbove = false
            chosenToolbarTop = clampedBelowTop
        } else {
            placeAbove = true
            chosenToolbarTop = clampedAboveTop
        }

        // Horizontal centering with edge clamping
        let edgePadding: CGFloat = 20
        let halfToolbarWidth = toolbarWidth / 2
        var toolbarX = selectionWindowX + (selectionWidth / 2) - halfToolbarWidth

        if toolbarX < edgePadding {
            toolbarX = edgePadding
        }

        let maxX = windowWidth - toolbarWidth - edgePadding
        if maxX > edgePadding {
            toolbarX = min(max(toolbarX, edgePadding), maxX)
        } else {
            let fallbackMax = max(0, windowWidth - toolbarWidth)
            toolbarX = min(max(toolbarX, 0), fallbackMax)
        }

        return Result(origin: CGPoint(x: toolbarX, y: chosenToolbarTop), placeAbove: placeAbove)
    }
}
