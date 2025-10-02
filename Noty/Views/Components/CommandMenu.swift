//
//  CommandMenu.swift
//  Noty
//
//  Command palette menu that appears when typing "/" in the text editor.
//  Matches EditToolbar styling with proper Liquid Glass implementation.
//

import SwiftUI

/// Command menu displaying editing tools in a vertical list
/// Appears when user types "/" and supports arrow key navigation
/// Uses the same Liquid Glass effect as EditToolbar for consistency
struct CommandMenu: View {
    // Available tools to display
    let tools: [EditTool]

    // Currently selected index for keyboard navigation
    @Binding var selectedIndex: Int

    // Callback when a tool is selected
    var onSelect: ((EditTool) -> Void)?

    // Maximum height for the menu
    var maxHeight: CGFloat = 280

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.element.rawValue) { index, tool in
                        CommandMenuItem(
                            tool: tool,
                            isSelected: index == selectedIndex
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect?(tool)
                        }
                        .id(index)
                    }
                }
            }
            .frame(maxHeight: maxHeight)
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.smooth(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(width: 240)
        .padding(12)  // Proper padding for concentricity
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))  // Corner radius adapts to padding (12 + 4 = 16)
        .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

/// Individual menu item matching native macOS menu appearance
struct CommandMenuItem: View {
    let tool: EditTool
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            // Tool icon - smaller size for proper scale
            Image(systemName: tool.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 16, height: 16)
                .symbolRenderingMode(.monochrome)

            // Tool name
            Text(tool.name)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? .white : .primary)

            Spacer(minLength: 0)

            // Keyboard shortcut hint
            if let shortcut = tool.keyboardShortcut {
                Text("⌘\(shortcut.character.uppercased())")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor)
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
    }
}

// MARK: - EditTool Icon Extension

extension EditTool {
    /// SF Symbol name for each tool
    var iconName: String {
        switch self {
        case .titleCase: return "pencil.tip.crop.circle"
        case .h1: return "1.square"
        case .h2: return "2.square"
        case .h3: return "3.square"
        case .bold: return "bold"
        case .italic: return "italic"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        case .bulletList: return "list.bullet"
        case .todo: return "checklist"
        case .indentLeft: return "decrease.indent"
        case .indentRight: return "increase.indent"
        case .alignLeft: return "text.alignleft"
        case .alignCenter: return "text.aligncenter"
        case .alignRight: return "text.alignright"
        case .alignJustify: return "text.justify"
        case .lineBreak: return "arrow.turn.down.left"
        case .textSelect: return "selection.pin.in.out"
        case .divider: return "minus"
        case .link: return "link"
        }
    }
}

// MARK: - Preview

struct CommandMenu_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Mock colorful background to show glass effect
            LinearGradient(
                colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            CommandMenu(
                tools: [
                    .h1, .h2, .h3,
                    .bold, .italic, .underline, .strikethrough,
                    .bulletList, .todo,
                    .divider, .link,
                ],
                selectedIndex: .constant(0),
                onSelect: { tool in
                    print("Selected: \(tool.name)")
                },
                maxHeight: 280
            )
            .padding(40)
        }
        .preferredColorScheme(.dark)
    }
}
