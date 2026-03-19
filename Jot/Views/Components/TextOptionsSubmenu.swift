//
//  TextOptionsSubmenu.swift
//  Jot
//
//  Vertical dropdown for the "Text" pill in the floating toolbar.
//  Contains headings, text styles, and list options.
//

import SwiftUI

struct TextOptionsSubmenu: View {
    var isBoldActive: Bool = false
    var isItalicActive: Bool = false
    var isUnderlineActive: Bool = false
    var isStrikethroughActive: Bool = false
    var onToolAction: ((EditTool) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var visible = false

    var body: some View {
        VStack(spacing: 0) {
            // Headings + Body
            submenuRow(icon: "IconNumber1Circle", label: "Heading 1", tool: .h1)
            submenuRow(icon: "IconNumber2Circle", label: "Heading 2", tool: .h2)
            submenuRow(icon: "IconNumber3Circle", label: "Heading 3", tool: .h3)
            submenuRow(icon: "IconTitleCase", label: "Body", tool: .titleCase)

            submenuDivider

            // Text styles
            submenuRow(icon: "IconBold", label: "Bold", tool: .bold, isActive: isBoldActive)
            submenuRow(icon: "IconItalic", label: "Italic", tool: .italic, isActive: isItalicActive)
            submenuRow(icon: "IconUnderline", label: "Underline", tool: .underline, isActive: isUnderlineActive)
            submenuRow(icon: "IconStrikeThrough", label: "Strikethrough", tool: .strikethrough, isActive: isStrikethroughActive)

            submenuDivider

            // Lists
            submenuRow(icon: "IconBulletList", label: "Bulleted List", tool: .bulletList)
            submenuRow(icon: "IconNumberedList", label: "Numbered List", tool: .numberedList)
            submenuRow(icon: "IconDashList", label: "Dashed List", tool: .dashedList)
        }
        .padding(4)
        .frame(width: 170)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16))
        .scaleEffect(visible ? 1 : 0.9, anchor: .top)
        .opacity(visible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(duration: 0.2)) { visible = true }
        }
    }

    private func submenuRow(icon: String, label: String, tool: EditTool, isActive: Bool = false) -> some View {
        SubmenuRowButton(icon: icon, label: label, isActive: isActive) {
            HapticManager.shared.toolbarAction()
            // Apply formatting outside any animation context so text doesn't animate
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onToolAction?(tool)
            }
            onDismiss?()
        }
    }

    private var submenuDivider: some View {
        Rectangle()
            .fill(Color(hex: "#44403c").opacity(0.15))
            .frame(height: 0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

// MARK: - Shared Submenu Row Button

struct SubmenuRowButton: View {
    let icon: String?
    let label: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundColor(isActive ? Color("AccentColor") : Color("IconSecondaryColor"))
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(isActive ? Color("AccentColor") : Color("PrimaryTextColor"))
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color("AccentColor"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isHovered ? Color("PrimaryTextColor").opacity(0.08) : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
