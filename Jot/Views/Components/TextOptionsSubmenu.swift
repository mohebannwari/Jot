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

    @State private var isRevealed = false

    private var rows: [(icon: String, label: String, tool: EditTool, isActive: Bool)] {
        [
            ("IconNumber1Circle", "Heading 1", .h1, false),
            ("IconNumber2Circle", "Heading 2", .h2, false),
            ("IconNumber3Circle", "Heading 3", .h3, false),
            ("IconTitleCase", "Body", .body, false),
            ("IconBold", "Bold", .bold, isBoldActive),
            ("IconItalic", "Italic", .italic, isItalicActive),
            ("IconUnderline", "Underline", .underline, isUnderlineActive),
            ("IconStrikeThrough", "Strikethrough", .strikethrough, isStrikethroughActive),
            ("IconBulletList", "Bulleted List", .bulletList, false),
            ("IconNumberedList", "Numbered List", .numberedList, false),
            ("IconDashList", "Dashed List", .dashedList, false),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.tool.rawValue) { index, row in
                if index == 4 || index == 8 {
                    submenuDivider
                }
                submenuRow(icon: row.icon, label: row.label, tool: row.tool, isActive: row.isActive)
                    .opacity(isRevealed ? 1 : 0)
                    .offset(y: isRevealed ? 0 : 8)
                    .scaleEffect(isRevealed ? 1 : 0.92, anchor: .top)
                    .animation(
                        .bouncy(duration: 0.4).delay(Double(index) * 0.03),
                        value: isRevealed
                    )
            }
        }
        .padding(4)
        .frame(width: 170)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isRevealed = true
            }
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
            .fill(Color.primary.opacity(0.15))
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
                        .frame(width: 15, height: 15)
                        .foregroundColor(isActive ? Color("AccentColor") : Color("IconSecondaryColor"))
                }
                Text(label)
                    .jotUI(FontManager.uiLabel3(weight: .medium))
                    .foregroundColor(isActive ? Color("AccentColor") : Color("PrimaryTextColor"))
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(FontManager.uiTiny(weight: .bold).font)
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
        .onDisappear {
            if isHovered { NSCursor.pop() }
        }
    }
}
