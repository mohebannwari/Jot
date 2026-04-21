//
//  FolderCreationOptionMenu.swift
//  Jot
//
//  Chooser for regular vs smart folder — matches SplitOptionMenu glass styling.
//

import SwiftUI

struct FolderCreationOptionMenu: View {
    let onRegularFolder: () -> Void
    let onSmartFolder: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            menuRow(icon: "IconFolderNewRegular", label: "Folder", action: onRegularFolder)
            menuRow(icon: "IconFolderNewSmart", label: "Smart folder", action: onSmartFolder)
        }
        .padding(4)
        .thinLiquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: 164)
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
                    .frame(width: 15, height: 15)
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
