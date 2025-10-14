//
//  BackdropBlurView.swift
//  Noty
//
//  Provides a cross-platform backdrop blur that matches system materials.
//

import SwiftUI

struct BackdropBlurView: View {
#if os(macOS)
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
#else
    var style: UIBlurEffect.Style = .systemThinMaterialDark
#endif

    var body: some View {
#if os(macOS)
        Representable(material: material, blendingMode: blendingMode)
#else
        Representable(style: style)
#endif
    }
}

#if os(macOS)
private struct Representable: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
#else
private struct Representable: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}
#endif
