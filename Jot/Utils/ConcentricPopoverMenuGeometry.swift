//
//  ConcentricPopoverMenuGeometry.swift
//  Jot
//
//  Concentric menu chrome: item hover background radius = outer popover corner radius
//  minus the content padding inset from the popover’s rounded-rect (matches concentric
//  radii in the design system: inner = outer − padding).
//

import SwiftUI

// MARK: - Layout constants

/// Geometry for small floating popover menus (split direction, new folder, etc.) that
/// use ``thinLiquidGlass`` / a rounded-rect of ``outerMenuCornerRadius`` and wrap rows in
/// ``menuContentPadding`` (must match the host view’s `VStack { ... }.padding(_)` value).
enum ConcentricPopoverMenuGeometry {
    static let outerMenuCornerRadius: CGFloat = 12
    static let menuContentPadding: CGFloat = 4

    /// Rounded-rect corner radius for row hovers, concentric with the popover’s outer
    /// shape after accounting for the inset between the popover border and the row.
    static var itemHoverCornerRadius: CGFloat {
        outerMenuCornerRadius - menuContentPadding
    }
}

// MARK: - Hover background

/// Per-row highlight: a full continuous rounded rect (all four corners) at
/// `itemHoverCornerRadius` so it stays concentric with the popover (`outer − padding`)
/// and reads as a single pill per row, not a strip with square inner edges.
struct PopoverMenuItemHoverBackground: View {
    let isHighlighted: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var fill: Color {
        Color("HoverBackgroundColor").opacity(colorScheme == .dark ? 0.95 : 1.0)
    }

    var body: some View {
        RoundedRectangle(
            cornerRadius: ConcentricPopoverMenuGeometry.itemHoverCornerRadius,
            style: .continuous
        )
        .fill(fill)
        .opacity(isHighlighted ? 1 : 0)
        .animation(.snappy(duration: 0.15), value: isHighlighted)
    }
}

// MARK: - Tappable item row (icon + title, CommandMenu-adjacent idle/hover colors)

/// One row in a concentric-corners popover menu. Keeps `isHovered` in a real `View` type
/// (not a `menuRow` helper) so hover state is stable.
struct JotPopoverTextIconMenuRow: View {
    let iconAsset: String
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool { isHovered }

    // Idle: same catalog pair as `CommandMenuItem` rows; highlight: full primary.
    private var idleForeground: Color { Color("EditorCommandMenuItemForegroundColor") }
    private var highlightForeground: Color { Color("PrimaryTextColor") }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Image(iconAsset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(isHighlighted ? highlightForeground : idleForeground)
                    .frame(width: 15, height: 15)
                Text(title)
                    .jotUI(FontManager.uiLabel3(weight: .regular))
                    .foregroundStyle(isHighlighted ? highlightForeground : idleForeground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                PopoverMenuItemHoverBackground(
                    isHighlighted: isHighlighted
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .macPointingHandCursor()
    }
}
