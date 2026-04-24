//
//  FileHoverTooltips.swift
//  Jot
//
//  Side-by-side glass pill tooltips shown above file attachments on hover.
//  Composes the existing Quick Look pill with a new Extract pill.
//

import SwiftUI

struct FileHoverTooltips: View {
    var onQuickLook: () -> Void
    var onExtract: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            LinkQuickLookTooltip()
                .onTapGesture { onQuickLook() }

            ExtractTooltipPill()
                .onTapGesture { onExtract() }
        }
    }
}

struct ExtractTooltipPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("IconExtract")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)

            Text("Extract")
                .jotUI(FontManager.uiLabel5(weight: .regular))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Color("PrimaryTextColor"))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassTooltip(shape: RoundedRectangle(cornerRadius: 999, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            @unknown default:
                break
            }
        }
    }
}
