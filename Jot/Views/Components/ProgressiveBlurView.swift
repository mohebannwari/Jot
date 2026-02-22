//
//  ProgressiveBlurView.swift
//  Jot
//
//  True progressive backdrop blur with zero color tint.
//  Uses CAFilter variableBlur on the internal CABackdropLayer
//  of NSVisualEffectView, then strips tint sublayers.
//

import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ProgressiveBlurEdge {
    case top
    case bottom
}

struct ProgressiveBlurView: NSViewRepresentable {
    var edge: ProgressiveBlurEdge
    var maxRadius: CGFloat

    init(edge: ProgressiveBlurEdge = .bottom, maxRadius: CGFloat = 20) {
        self.edge = edge
        self.maxRadius = maxRadius
    }

    func makeNSView(context: Context) -> ProgressiveBlurNSView {
        ProgressiveBlurNSView(edge: edge, maxRadius: maxRadius)
    }

    func updateNSView(_ nsView: ProgressiveBlurNSView, context: Context) {
        nsView.update(edge: edge, maxRadius: maxRadius)
    }
}

// MARK: - NSView Implementation

final class ProgressiveBlurNSView: NSVisualEffectView {
    private var currentEdge: ProgressiveBlurEdge
    private var currentRadius: CGFloat

    init(edge: ProgressiveBlurEdge, maxRadius: CGFloat) {
        self.currentEdge = edge
        self.currentRadius = maxRadius
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func update(edge: ProgressiveBlurEdge, maxRadius: CGFloat) {
        guard edge != currentEdge || maxRadius != currentRadius else { return }
        currentEdge = edge
        currentRadius = maxRadius
        applyVariableBlur()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyVariableBlur()

        if let window {
            subviews.first?.layer?.setValue(
                window.backingScaleFactor,
                forKey: "scale"
            )
        }
    }

    override func layout() {
        super.layout()
        applyVariableBlur()
    }

    // MARK: - Core

    private func applyVariableBlur() {
        wantsLayer = true
        guard !subviews.isEmpty else { return }

        let filterClassName = String("retliFAC".reversed())
        guard let filterClass = NSClassFromString(filterClassName) as? NSObject.Type else { return }

        let selectorName = String(":epyThtiWretlif".reversed())
        let selector = NSSelectorFromString(selectorName)
        guard filterClass.responds(to: selector),
              let result = filterClass.perform(selector, with: "variableBlur"),
              let variableBlur = result.takeUnretainedValue() as? NSObject else { return }

        let maskImage = makeGradientMask(
            width: max(bounds.width, 1),
            height: max(bounds.height, 1)
        )

        variableBlur.setValue(currentRadius, forKey: "inputRadius")
        variableBlur.setValue(maskImage, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")

        // Apply to the backdrop sublayer (first subview's layer)
        subviews.first?.layer?.filters = [variableBlur]

        // Kill all tint sublayers -- zero color contribution
        for subview in subviews.dropFirst() {
            subview.alphaValue = 0
        }
    }

    // MARK: - Gradient Mask

    private func makeGradientMask(width: CGFloat, height: CGFloat) -> CGImage {
        let gradient = CIFilter.linearGradient()
        gradient.color0 = CIColor.black // full blur
        gradient.color1 = CIColor.clear // no blur

        switch currentEdge {
        case .bottom:
            // Blur at bottom (y=0 in CIImage coords), clear at top
            gradient.point0 = CGPoint(x: 0, y: 0)
            gradient.point1 = CGPoint(x: 0, y: height)
        case .top:
            // Blur at top (y=height in CIImage coords), clear at bottom
            gradient.point0 = CGPoint(x: 0, y: height)
            gradient.point1 = CGPoint(x: 0, y: 0)
        }

        let context = CIContext()
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        return context.createCGImage(gradient.outputImage!, from: rect)!
    }
}
