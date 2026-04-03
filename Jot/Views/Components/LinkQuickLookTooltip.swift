//
//  LinkQuickLookTooltip.swift
//  Jot
//
//  Glass pill tooltip shown above links on hover.
//

import SwiftUI

struct LinkQuickLookTooltip: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("IconQuickSearch")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)

            Text("Quick Look")
                .font(FontManager.heading(size: 11, weight: .medium))
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
