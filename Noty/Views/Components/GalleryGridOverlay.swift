//
//  GalleryGridOverlay.swift
//  Noty
//
//  Presents the full gallery of images for the current note in a blurred overlay grid.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct GalleryGridOverlay: View {
    struct Item: Identifiable {
        let id: String
        let image: PlatformImage
    }

    let items: [Item]
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var isExpanded = false
    @State private var isVisible = false
    @State private var isClosing = false
    @State private var selectedItem: Item?
    @Namespace private var lightboxNamespace
    @Namespace private var controlNamespace

    var body: some View {
        ZStack(alignment: .top) {
            backgroundLayer
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridColumns(for: geometry.size.width), spacing: 24) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, element in
                            let animation = transformAnimation(for: index, totalCount: items.count)
                            let isSelected = selectedItem?.id == element.id
                            GalleryGridTile(image: element.image)
                                .matchedGeometryEffect(
                                    id: element.id,
                                    in: lightboxNamespace,
                                    properties: .frame,
                                    anchor: .center
                                )
                                .rotationEffect(.degrees(isExpanded ? 0 : 6), anchor: .bottomLeading)
                                .scaleEffect(isExpanded ? 1 : 0.68, anchor: .bottomLeading)
                                .offset(isExpanded ? .zero : collapsedOffset(for: geometry.size, index: index))
                                .opacity(isVisible ? (isSelected ? 0 : 1) : 0)
                                .animation(animation, value: isExpanded)
                                .animation(.easeInOut(duration: 0.14), value: isVisible)
                                .animation(.easeInOut(duration: 0.2), value: selectedItem?.id)
                                .onTapGesture {
                                    guard selectedItem == nil else { return }
                                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                        selectedItem = element
                                    }
                                }
                        }
                    }
                    .padding(.top, 96)
                    .padding(.bottom, 80)
                    .padding(.horizontal, horizontalPadding(for: geometry.size.width))
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(selectedItem == nil)
                .animation(.easeInOut(duration: 0.2), value: selectedItem?.id)
            }
            .opacity(selectedItem == nil ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: selectedItem?.id)

            if let selectedItem {
                lightbox(for: selectedItem)
            }
        }
        .overlay(alignment: .bottom) {
            closeButton
                .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
        .onAppear {
            isClosing = false
            isExpanded = false
            isVisible = false
            selectedItem = nil

            withAnimation(.easeOut(duration: 0.22)) {
                isVisible = true
            }

            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                isExpanded = true
            }
        }
        .transition(.identity)
    }

    private var backgroundLayer: some View {
        ZStack {
#if os(macOS)
            BackdropBlurView(material: .hudWindow, blendingMode: .withinWindow)
#else
            BackdropBlurView(style: .systemUltraThinMaterialDark)
#endif
            Color.black.opacity(colorScheme == .dark ? 0.08 : 0.06)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedItem != nil {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                    selectedItem = nil
                }
            } else {
                dismiss()
            }
        }
    }

    private var closeButton: some View {
        let isLightbox = selectedItem != nil
        let surfaceShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        return Button(action: isLightbox ? backToGrid : dismiss) {
            HStack(spacing: isLightbox ? 10 : 0) {
                Image(systemName: isLightbox ? "chevron.left" : "xmark")
                    .font(.system(size: isLightbox ? 18 : 20, weight: .semibold))
                    .foregroundStyle(closeSymbolColor)

                if isLightbox {
                    Text("Back")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(closeSymbolColor)
                        .lineLimit(1)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, isLightbox ? 24 : 0)
            .frame(width: isLightbox ? nil : 52)
            .frame(minWidth: 52)
            .contentShape(surfaceShape)
            .background(surfaceShape.fill(Color.clear))
            .if(available26) { view in
                if #available(iOS 26.0, macOS 26.0, *) {
                    AnyView(
                        view
                            .glassEffect(.regular.interactive(true), in: surfaceShape)
                            .glassID("gallery-control-surface", in: controlNamespace)
                    )
                } else {
                    AnyView(view)
                }
            }
            .if(!available26) { view in
                view.background(.ultraThinMaterial, in: surfaceShape)
            }
            .overlay(
                surfaceShape
                    .stroke(controlStrokeColor, lineWidth: 0.6)
            )
            .matchedGeometryEffect(id: "gallery-control-surface", in: controlNamespace)
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 32)
#if os(macOS)
        .keyboardShortcut(.cancelAction)
#endif
    }

    private var closeSymbolColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85)
    }

    private var controlStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    private var lightboxStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color.black.opacity(0.16)
    }

    @ViewBuilder
    private func lightbox(for item: Item) -> some View {
        GeometryReader { geometry in
            let targetSize = fittedSize(for: item.image, in: geometry.size)

            lightboxImage(for: item.image)
                .matchedGeometryEffect(id: item.id, in: lightboxNamespace, properties: .frame, anchor: .center)
                .frame(width: targetSize.width, height: targetSize.height)
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: selectedItem?.id)
    }

    private func lightboxImage(for image: PlatformImage) -> some View {
#if os(macOS)
        return Image(nsImage: image)
            .resizable()
            .aspectRatio(imageAspectRatio(for: image), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(lightboxStrokeColor, lineWidth: 1)
            )
#else
        return Image(uiImage: image)
            .resizable()
            .aspectRatio(imageAspectRatio(for: image), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(lightboxStrokeColor, lineWidth: 1)
            )
#endif
    }

    private func fittedSize(for image: PlatformImage, in available: CGSize) -> CGSize {
        let aspect = imageAspectRatio(for: image)
        let maxWidth = available.width * 0.82
        let maxHeight = available.height * 0.82

        guard aspect > 0 else {
            return CGSize(width: maxWidth, height: maxHeight)
        }

        var width = maxWidth
        var height = width / aspect

        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }

        return CGSize(width: width, height: height)
    }

    private func imageAspectRatio(for image: PlatformImage) -> CGFloat {
#if os(macOS)
        let size = image.size
        guard size.height > 0 else { return 1 }
        return max(CGFloat(size.width / size.height), 0.1)
#else
        let size = image.size
        guard size.height > 0 else { return 1 }
        return max(size.width / size.height, 0.1)
#endif
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let padding = horizontalPadding(for: width) * 2
        let effectiveWidth = max(0, width - padding)
        let minimum: CGFloat

        if effectiveWidth < 380 {
            minimum = max(140, effectiveWidth * 0.85)
        } else if effectiveWidth < 680 {
            minimum = 164
        } else if effectiveWidth < 980 {
            minimum = 200
        } else {
            minimum = 224
        }

        let maximum = min(max(minimum + 84, minimum * 1.25), 320)
        return [
            GridItem(
                .adaptive(minimum: minimum, maximum: maximum),
                spacing: 24,
                alignment: .center
            )
        ]
    }

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        switch width {
        case ..<640:
            return 28
        case ..<960:
            return 48
        default:
            return 72
        }
    }

    private func dismiss() {
        guard !isClosing else { return }
        guard selectedItem == nil else {
            backToGrid()
            return
        }

        isClosing = true

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isExpanded = false
        }

        let maxDelay = Double(max(items.count - 1, 0)) * 0.015
        let fadeDelay = maxDelay + 0.06

        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) {
            withAnimation(.easeInOut(duration: 0.18)) {
                isVisible = false
            }
        }

        let totalDelay = fadeDelay + 0.12
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            isExpanded = false
            isClosing = false
            onDismiss()
            isVisible = false
            selectedItem = nil
        }
    }

    private func backToGrid() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            selectedItem = nil
        }
    }

    private var available26: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        return false
    }
}

private struct GalleryGridTile: View {
    let image: PlatformImage
    @Environment(\.colorScheme) private var colorScheme

    private let tileShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        GeometryReader { geometry in
            platformImage
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(tileShape)
                .overlay(
                    tileShape
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 12)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.12)
    }

    private var platformImage: Image {
#if os(macOS)
        Image(nsImage: image)
#else
        Image(uiImage: image)
#endif
    }
}

extension GalleryGridOverlay {
    private func transformAnimation(for index: Int, totalCount: Int) -> Animation {
        let delay = Double(totalCount - 1 - index) * 0.015
        return .spring(response: 0.26, dampingFraction: 0.8).delay(delay)
    }

    private func collapsedOffset(for containerSize: CGSize, index: Int) -> CGSize {
        let baseX = -(containerSize.width * 0.48) + 96
        let baseY = containerSize.height * 0.42
        let depth = CGFloat(index)
        let spread = CGFloat(index % 3) * 10
        return CGSize(
            width: baseX - depth * 16 - spread,
            height: baseY + depth * 18 + spread * 0.4
        )
    }
}
