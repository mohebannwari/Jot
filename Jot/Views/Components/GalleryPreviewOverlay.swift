//
//  GalleryPreviewOverlay.swift
//  Jot
//
//  Floating gallery preview badge that highlights the latest image attachment.
//

import SwiftUI

import AppKit

struct GalleryPreviewOverlay: View {
    let image: NSImage
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private let baseShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    private let imageShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    private let tileSize: CGFloat = 40
    private let offsetAmount: CGFloat = 8
    private let hoverSpread: CGFloat = 4

    var body: some View {
        layeredContent
            .frame(width: tileSize + offsetAmount + hoverSpread, height: tileSize + offsetAmount + hoverSpread, alignment: .topTrailing)
            .offset(y: containerYOffset)
            .animation(.smooth(duration: 0.25), value: isHovering)
            .background(hoverRegion)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var imageView: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
    }

    private var baseLayer: some View {
        baseShape
            .fill(colorScheme == .dark ? Color(red: 0.267, green: 0.251, blue: 0.235) : Color.white)
            .background(
                baseShape
                    .fill(Color.clear)
                    .liquidGlass(in: baseShape)
            )
            .frame(width: tileSize, height: tileSize)
            .clipShape(baseShape)
            .rotationEffect(baseRotation)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.06 : 0.12), radius: colorScheme == .dark ? 8 : 10, x: 0, y: colorScheme == .dark ? 4 : 5)
    }

    private var imageLayer: some View {
        imageView
            .frame(width: tileSize, height: tileSize)
            .clipShape(imageShape)
            .rotationEffect(imageRotation)
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    private var layeredContent: some View {
        ZStack(alignment: .topTrailing) {
            baseLayer
                .offset(baseOffset)
            imageLayer
                .offset(imageOffset)
        }
        .allowsHitTesting(false)
    }

    private var hoverRegion: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }
            .macPointingHandCursor()
            .onHover { hovering in
                withAnimation(.smooth(duration: 0.25)) {
                    isHovering = hovering
                }
            }
    }

    private var baseOffset: CGSize {
        if isHovering {
            return CGSize(
                width: -(offsetAmount + hoverSpread),
                height: offsetAmount + hoverSpread + 2
            )
        } else {
            return CGSize(width: -offsetAmount, height: offsetAmount)
        }
    }

    private var imageOffset: CGSize {
        if isHovering {
            return CGSize(
                width: hoverSpread / 2,
                height: -(hoverSpread / 2) - 2
            )
        } else {
            return .zero
        }
    }

    private var baseRotation: Angle {
        isHovering ? .degrees(-20) : .degrees(-15)
    }

    private var imageRotation: Angle {
        isHovering ? .degrees(5) : .degrees(0)
    }

    private var containerYOffset: CGFloat {
        isHovering ? -6 : 0
    }
}
