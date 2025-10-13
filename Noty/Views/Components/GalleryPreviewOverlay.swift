//
//  GalleryPreviewOverlay.swift
//  Noty
//
//  Floating gallery preview badge that highlights the latest image attachment.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct GalleryPreviewOverlay: View {
    let image: PlatformImage

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private let baseShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    private let imageShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    private let tileSize: CGFloat = 52
    private let offsetAmount: CGFloat = 12
    private let baseBorderWidth: CGFloat = 2.0
    private let imageBorderWidth: CGFloat = 2.0
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
        #if os(macOS)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
        #else
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
        #endif
    }

    private var baseLayer: some View {
        baseShape
            .fill(Color.clear)
            .background(
                baseShape
                    .fill(Color.clear)
                    .liquidGlass(in: baseShape)
            )
            .frame(width: tileSize, height: tileSize)
            .clipShape(baseShape)
            .overlay {
                baseShape
                    .inset(by: -baseBorderWidth / 2)
                    .stroke(baseStrokeColor, lineWidth: baseBorderWidth)
            }
            .rotationEffect(baseRotation)
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 10)
    }

    private var imageLayer: some View {
        imageView
            .frame(width: tileSize, height: tileSize)
            .clipShape(imageShape)
            .overlay {
                imageShape
                    .inset(by: -imageBorderWidth / 2)
                    .stroke(imageStrokeColor, lineWidth: imageBorderWidth)
            }
            .rotationEffect(imageRotation)
            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 6)
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

    private var baseStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.08)
    }

    private var imageStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.12)
    }

    private var containerYOffset: CGFloat {
        isHovering ? -6 : 0
    }
}
