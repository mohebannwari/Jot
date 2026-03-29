//
//  SplitOptionMenu.swift
//  Jot
//
//  Split direction chooser: split-left / split-right.
//

import SwiftUI

struct SplitOptionMenu: View {
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            menuRow(icon: "IconLayoutRight", label: "Split-right", action: onSplitRight)
            menuRow(icon: "IconLayoutLeft",  label: "Split-left",  action: onSplitLeft)
        }
        .padding(4)
        .thinLiquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: 120)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private func menuRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 16, height: 16)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .tracking(-0.1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
    }
}
