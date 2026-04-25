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
            JotPopoverTextIconMenuRow(
                iconAsset: "IconFolderNewRegular", title: "Folder"
            ) {
                onRegularFolder()
                dismiss()
            }
            JotPopoverTextIconMenuRow(
                iconAsset: "IconFolderNewSmart", title: "Smart folder"
            ) {
                onSmartFolder()
                dismiss()
            }
        }
        .padding(ConcentricPopoverMenuGeometry.menuContentPadding)
        .thinLiquidGlass(
            in: RoundedRectangle(
                cornerRadius: ConcentricPopoverMenuGeometry.outerMenuCornerRadius,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .fixedSize(horizontal: true, vertical: false)
    }
}
