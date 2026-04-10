//
//  WebClipView.swift
//  Jot
//
//  Proper implementation that fills space correctly
//

import CoreImage
import SwiftUI

struct WebClipView: View {
    let title: String
    let domain: String
    let url: String?

    var body: some View {
        Button {
            if let urlString = url ?? URL(string: "https://\(domain)")?.absoluteString,
                let url = URL(string: urlString)
            {
                #if os(macOS)
                    NSWorkspace.shared.open(url)
                #else
                    UIApplication.shared.open(url)
                #endif
            }
        } label: {
            HStack(spacing: 0) {
                Image("IconChainLink")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)

                Text(cleanedDomain)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .textCase(.lowercase)
                    .padding(.horizontal, 4)

                Image("IconArrowRightUpCircle")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            }
            .foregroundColor(.white) // LinkPillColor is always dark blue -- white text is forced-appearance by design
            .padding(4)
            .background(Color("LinkPillColor"), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cleanedDomain: String {
        domain
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
    }

    private var accessibilityLabel: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmedTitle.isEmpty ? cleanedDomain : trimmedTitle
        return "Open \(label)"
    }
}

/// Link card -- Figma spec: 22px radius, 12px padding, 8px gap, thumbnail + title + description + domain
struct LinkCardView: View {
    let title: String
    let description: String
    let domain: String
    let url: String
    var thumbnailImage: NSImage? = nil
    var tintColor: NSColor? = nil
    var cardWidth: CGFloat = 224

    /// No-thumbnail height: padding(12) + title(18) + gap(8) + desc(14) + gap(8) + link(10) + padding(12) = 82
    /// With-thumbnail height: padding(12) + thumbnail(108) + gap(8) + title(18) + gap(8) + desc(14) + gap(8) + link(10) + padding(12) = 198
    static let fixedHeight: CGFloat = 82
    static let thumbnailHeight: CGFloat = 108
    static let withThumbnailHeight: CGFloat = 198

    static func heightForCard(hasThumbnail: Bool) -> CGFloat {
        hasThumbnail ? withThumbnailHeight : fixedHeight
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail -- 200x108, 10pt concentric radius (22 outer - 12 padding)
            if let thumbnail = thumbnailImage {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth - 24, height: Self.thumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color("BorderSubtleColor"), lineWidth: 1)
                    )
            }

            // Title -- Label-2/Medium
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.5)
                .lineSpacing(3)
                .foregroundStyle(Color("PrimaryTextColor"))
                .lineLimit(1)

            // Description -- Label-4/Medium
            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.3)
                    .lineSpacing(2)
                    .foregroundStyle(Color("SecondaryTextColor"))
                    .lineLimit(1)
            }

            // Domain link row -- Micro/Medium
            HStack(spacing: 4) {
                Image("IconChainLink")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 10, height: 10)
                Text(cleanedDomain)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color("AccentColor"))
        }
        .padding(12)
        .frame(width: cardWidth, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(LinkCardGlassModifier(shape: cardShape, tintColor: tintColor))
    }

    private var cleanedDomain: String {
        domain
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - LinkCardView Helpers

extension LinkCardView {
    /// Downscale to 1x1 and read the average pixel color (call once, cache the result)
    static func averageColor(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            ciImage,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1.0
        )
    }
}

/// Glass modifier using pre-computed tint color
private struct LinkCardGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tintColor: NSColor?

    func body(content: Content) -> some View {
        if let tint = tintColor {
            content.tintedLiquidGlass(
                in: shape,
                tint: Color(nsColor: tint),
                tintOpacity: 0.25
            )
        } else {
            content.thinLiquidGlass(in: shape)
        }
    }
}

