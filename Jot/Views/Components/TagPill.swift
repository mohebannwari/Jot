//
//  TagPill.swift
//  Jot
//
//  Reusable tag chip component with hover, press, and removal states.
//

import SwiftUI

struct TagPill: View {
    let text: String
    let isSelected: Bool
    let isHovered: Bool
    let isPressed: Bool
    let visible: Bool
    let onRemove: () -> Void
    let glassNamespace: Namespace.ID

    @ViewBuilder
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(FontManager.icon(size: 18))
                .foregroundColor(Color("TagTextColor"))
            Text(text)
                .font(FontManager.heading(size: 12, weight: .medium))
                .foregroundColor(Color("TagTextColor"))
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: {
                HapticManager.shared.tagInteraction()
                onRemove()
            }) {
                Image(systemName: "xmark")
                    .font(FontManager.icon(size: 18, weight: .bold))
                    .foregroundColor(Color("TagTextColor"))
                    .opacity(0.7)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .frame(width: 20, height: 20)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .frame(height: 28)
        .tintedLiquidGlass(in: Capsule(), tint: Color("TagBackgroundColor"))
        .background(
            Capsule()
                .fill(Color.clear)
                .frame(height: 36)
        )
        .contentShape(Capsule())
        .scaleEffect((visible ? 1 : 0.92) * (isPressed ? 0.96 : 1.0) * (isHovered ? 1.01 : 1.0))
        .opacity(visible ? 1 : 0)
        .animation(.jotBounce, value: isHovered)
        .animation(.bouncy(duration: 0.2), value: isPressed)
        .macPointingHandCursor()
    }
}
