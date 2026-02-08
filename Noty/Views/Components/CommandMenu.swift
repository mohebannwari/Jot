//
//  CommandMenu.swift
//  Noty
//
//  Command palette menu that appears when typing "/" in the text editor.
//  Matches EditToolbar styling with proper Liquid Glass implementation.
//

import SwiftUI

enum CommandMenuLayout {
    static let itemHeight: CGFloat = 36  // Updated to match padding(.vertical, 10) + content height
    static let itemSpacing: CGFloat = 0  // Spacing between items
    static let defaultMaxHeight: CGFloat = 280
    static let width: CGFloat = 150
    static let outerPadding: CGFloat = 12

    // Calculate the ideal height to fit content without extra space
    // The outer padding is handled by the .padding(CommandMenuLayout.outerPadding) modifier on the menu itself
    static func idealHeight(for itemCount: Int, maxHeight: CGFloat = defaultMaxHeight) -> CGFloat {
        guard itemCount > 0 else {
            return 0  // Return 0 when no items, let the padding handle minimum size
        }
        // Calculate exact height needed for items
        // Each item is itemHeight tall, with itemSpacing between them
        let contentHeight = CGFloat(itemCount) * itemHeight + CGFloat(max(0, itemCount - 1)) * itemSpacing
        return min(maxHeight, contentHeight)
    }
}

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
    var maxHeight: CGFloat = CommandMenuLayout.defaultMaxHeight

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
            .frame(height: CommandMenuLayout.idealHeight(for: tools.count, maxHeight: maxHeight))
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.smooth(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(width: CommandMenuLayout.width)
        .padding(CommandMenuLayout.outerPadding)  // Proper padding for concentricity
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))  // Corner radius adapts to padding (12 + 4 = 16)
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

/// Individual menu item matching native macOS menu appearance
struct CommandMenuItem: View {
    let tool: EditTool
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var selectedForegroundColor: Color {
        colorScheme == .dark ? .white : Color("PrimaryTextColor")
    }

    private var selectedShortcutColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.84)
            : Color("PrimaryTextColor").opacity(0.72)
    }

    private var selectedBackgroundColor: Color {
        Color("HoverBackgroundColor").opacity(colorScheme == .dark ? 0.95 : 1.0)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Tool icon - smaller size for proper scale
            Group {
                if let assetName = tool.iconAssetName {
                    Image(assetName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: tool.iconName)
                        .font(FontManager.icon(weight: .medium))
                        .symbolRenderingMode(.monochrome)
                }
            }
            .foregroundStyle(isSelected ? selectedForegroundColor : .primary)
            .frame(width: 18, height: 18)

            // Tool name
            Text(tool.name)
                .font(FontManager.heading(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? selectedForegroundColor : .primary)

            Spacer(minLength: 0)

            // Keyboard shortcut hint - using SF Mono for metadata
            if let shortcut = tool.keyboardShortcut {
                Text("⌘\(shortcut.character.uppercased())")
                    .font(FontManager.metadata(size: 11, weight: .regular))
                    .foregroundStyle(isSelected ? selectedShortcutColor : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(selectedBackgroundColor)
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
    /// Custom asset icon name, nil means fall back to SF Symbol
    var iconAssetName: String? {
        switch self {
        case .titleCase: return nil
        case .h1: return "IconH1"
        case .h2: return "IconH2"
        case .h3: return "IconH3"
        case .bold: return "IconBold"
        case .italic: return "IconItalic"
        case .underline: return "IconUnderline"
        case .strikethrough: return "IconStrikeThrough"
        case .bulletList: return "todo-list"
        case .todo: return "IconTodos"
        case .indentLeft: return "IconTextIndentLeft"
        case .indentRight: return "IconTextIndentRight"
        case .alignLeft: return "IconAlignmentLeft"
        case .alignCenter: return "IconAlignmentCenter"
        case .alignRight: return "IconAlignmentRight"
        case .alignJustify: return "IconAlignmentJustify"
        case .lineBreak: return "IconLinebreak"
        case .textSelect: return "IconTextSelectDashed"
        case .divider: return "IconDivider"
        case .link: return "insert link"
        case .imageUpload: return "gallery"
        case .voiceRecord: return "mic-recording"
        }
    }

    /// SF Symbol name for each tool (fallback)
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
        case .imageUpload: return "photo.on.rectangle.angled"
        case .voiceRecord: return "mic"
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
                tools: [.imageUpload, .voiceRecord, .link],
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
