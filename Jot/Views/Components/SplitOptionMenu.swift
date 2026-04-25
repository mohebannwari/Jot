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
            JotPopoverTextIconMenuRow(
                iconAsset: "IconLayoutRight", title: "Split-right"
            ) {
                onSplitRight()
                dismiss()
            }
            JotPopoverTextIconMenuRow(
                iconAsset: "IconLayoutLeft", title: "Split-left"
            ) {
                onSplitLeft()
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
