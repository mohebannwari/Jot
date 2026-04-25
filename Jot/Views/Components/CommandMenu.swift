//
//  CommandMenu.swift
//  Jot
//
//  Command palette menu that appears when typing "/" in the text editor.
//  Matches EditToolbar styling with proper Liquid Glass implementation.
//

import SwiftUI

enum CommandMenuLayout {
    static let itemHeight: CGFloat = 36
    static let itemSpacing: CGFloat = 0
    static let maxVisibleItems: Int = 7
    static let width: CGFloat = 150
    static let outerPadding: CGFloat = 12
    static let scrollIndicatorSize: CGFloat = 24
    /// Top and bottom spacer inside the ScrollView (each side). Kept as a
    /// named constant so the positioning math in `clampedCommandMenuPosition`
    /// can reason about the menu's true rendered height.
    static let scrollContentPadding: CGFloat = 4

    /// Breathing room between the "/" line and the command menu (above or below).
    /// Shared by `showCommandMenuAtCursor` (AppKit) and `clampedCommandMenuPosition`
    /// (SwiftUI) so anchor math cannot drift.
    static let verticalAnchorGap: CGFloat = 10

    /// Height that fits up to `maxVisibleItems` rows — anything beyond scrolls.
    static func idealHeight(for itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let visibleCount = min(itemCount, maxVisibleItems)
        return CGFloat(visibleCount) * itemHeight
    }

    /// Total rendered height of the menu card, including the ScrollView's
    /// internal top/bottom spacers and the card's outer padding. This is
    /// what positioning logic must use to compute above/below placement —
    /// `idealHeight(for:)` alone under-counts by `scrollContentPadding * 2`
    /// plus `outerPadding * 2`, which causes the menu to overlap the
    /// anchor character when flipped above.
    static func totalHeight(for itemCount: Int) -> CGFloat {
        idealHeight(for: itemCount) + scrollContentPadding * 2 + outerPadding * 2
    }

    /// Top Y of the command menu in text-view coordinates. When `showsAbove` is true,
    /// recomputing with the live `itemCount` keeps the menu bottom anchored near the
    /// slash as the filtered list shrinks; when false, placement does not depend on height.
    static func menuTopY(
        showsAbove: Bool,
        anchorCursorY: CGFloat,
        cursorHeight: CGFloat,
        itemCount: Int
    ) -> CGFloat {
        if showsAbove {
            anchorCursorY - totalHeight(for: itemCount) - verticalAnchorGap
        } else {
            anchorCursorY + cursorHeight + verticalAnchorGap
        }
    }
}

/// Command menu displaying editing tools in a vertical list
/// Appears when user types "/" and supports arrow key navigation
/// Uses Liquid Glass with native .materialize transition
struct CommandMenu: View {
    let tools: [EditTool]
    @Binding var selectedIndex: Int
    @Binding var isRevealed: Bool
    var onSelect: ((EditTool) -> Void)?

    private let glassShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    @State private var isAtBottom = false
    @State private var chevronBounce = false
    @Environment(\.colorScheme) private var colorScheme

    private var visibleContentHeight: CGFloat {
        CommandMenuLayout.idealHeight(for: tools.count)
    }

    private var needsScrolling: Bool {
        tools.count > CommandMenuLayout.maxVisibleItems
    }

    private var showScrollIndicator: Bool {
        isRevealed && needsScrolling && !isAtBottom
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: CommandMenuLayout.scrollContentPadding)
                        ForEach(Array(tools.enumerated()), id: \.element.rawValue) { index, tool in
                            Button {
                                onSelect?(tool)
                            } label: {
                                CommandMenuItem(
                                    tool: tool,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .opacity(isRevealed ? 1 : 0)
                                .offset(y: isRevealed ? 0 : 8)
                                .scaleEffect(isRevealed ? 1 : 0.92, anchor: .top)
                                .animation(
                                    .bouncy(duration: 0.4).delay(Double(index) * 0.04),
                                    value: isRevealed
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer().frame(height: CommandMenuLayout.scrollContentPadding)
                    }
                }
                .frame(height: visibleContentHeight + CommandMenuLayout.scrollContentPadding * 2)
                .modifier(ScrollBottomDetector(isAtBottom: $isAtBottom))
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            // Scroll-more indicator — liquid glass circle with chevron
            if showScrollIndicator {
                scrollDownIndicator
                    .offset(y: chevronBounce ? 6 : -3)
                    .transition(.blurReplace.combined(with: .opacity))
                    .allowsHitTesting(false)
                    .padding(.bottom, 2)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                            chevronBounce = true
                        }
                        withAnimation(.easeInOut(duration: 0.5).delay(0.7)) {
                            chevronBounce = false
                        }
                    }
                    .onDisappear { chevronBounce = false }
            }
        }
        .frame(width: CommandMenuLayout.width)
        .padding(CommandMenuLayout.outerPadding)
        .materializingGlass(in: glassShape)
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        // Scale + opacity in local coordinate space -- .top IS the cursor position
        .scaleEffect(isRevealed ? 1.0 : 0.35, anchor: .top)
        .opacity(isRevealed ? 1 : 0)
    }

    @ViewBuilder
    private var scrollDownIndicator: some View {
        let strokeOpacity: Double = colorScheme == .dark ? 0.22 : 0.08
        let chevron = Image(systemName: "chevron.down")
            .font(FontManager.uiTiny(weight: .bold).font)
            .foregroundStyle(Color("IconSecondaryColor"))
            .frame(width: CommandMenuLayout.scrollIndicatorSize, height: CommandMenuLayout.scrollIndicatorSize)

        if #available(macOS 26.0, iOS 26.0, *) {
            chevron
                .glassEffect(.regular, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(strokeOpacity), lineWidth: 0.5))
        } else {
            chevron
                .padding(2)
                .background(Color("SecondaryBackgroundColor"), in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(strokeOpacity), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        }
    }
}

// MARK: - Glass with Materialize Transition

private extension View {
    /// Applies liquid glass with native materialize transition on macOS 26+, fallback on older
    @ViewBuilder
    func materializingGlass(in shape: some Shape) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(true), in: shape)
                .glassEffectTransition(.materialize)
        } else {
            self
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Color("SecondaryBackgroundColor"), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
    }
}

/// Individual menu item matching native macOS menu appearance
struct CommandMenuItem: View {
    let tool: EditTool
    let isSelected: Bool

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isHighlighted: Bool { isSelected || isHovered }

    /// Idle row: one catalog token for **both** template icons and titles (`EditorCommandMenuItemForegroundColor` — chroma matches `IconSecondaryColor`; name signals shared slash-menu use).
    private var idleRowForeground: Color {
        Color("EditorCommandMenuItemForegroundColor")
    }

    /// Hover / keyboard selection: primary label color for icon + title together.
    private var highlightRowForeground: Color {
        Color("PrimaryTextColor")
    }

    private var highlightedBackgroundColor: Color {
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
                        .font(FontManager.icon(size: 15, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                }
            }
            .foregroundStyle(isHighlighted ? highlightRowForeground : idleRowForeground)
            .frame(width: 15, height: 15)

            // Tool name — same foreground token as the icon in each state.
            Text(tool.name)
                .font(FontManager.heading(size: 13, weight: .regular))
                .foregroundStyle(isHighlighted ? highlightRowForeground : idleRowForeground)

            Spacer(minLength: 0)

            // Keyboard shortcut hint - using SF Mono for metadata
            if let shortcut = tool.keyboardShortcut {
                Text("⌘\(shortcut.character)")
                    .jotMetadataLabelTypography()
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(highlightedBackgroundColor)
                .opacity(isHighlighted ? 1 : 0)
        )
        .animation(.snappy(duration: 0.15), value: isHighlighted)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - EditTool Icon Extension

extension EditTool {
    /// Custom asset icon name, nil means fall back to SF Symbol
    var iconAssetName: String? {
        switch self {
        case .body: return "IconTitleCase"
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
        case .searchOnPage: return "IconPageTextSearch"
        case .map: return "IconMap"
        case .table: return "IconTable"
        case .numberedList: return "IconNumberedList"
        case .codeBlock: return "IconCode"
        case .blockQuote: return "IconTextBlock"
        case .highlight: return nil
        case .callout: return "IconLightBulbSimple"
        case .fileLink: return "IconFileLink"
        case .sticker: return "IconSticker"
        case .tabs: return "IconDossier"
        case .cards: return "IconCarussel"
        case .dashedList: return "IconDashList"
        case .convertToWebClip: return "insert link"
        case .quickLook: return "IconQuickSearch"
        }
    }

    /// SF Symbol name for each tool (fallback)
    var iconName: String {
        switch self {
        case .body: return "textformat"
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
        case .searchOnPage: return "magnifyingglass"
        case .map: return "map"
        case .table: return "tablecells"
        case .numberedList: return "list.number"
        case .codeBlock: return "chevron.left.forwardslash.chevron.right"
        case .blockQuote: return "text.quote"
        case .highlight: return "highlighter"
        case .callout: return "info.circle.fill"
        case .fileLink: return "paperclip"
        case .sticker: return "note.text"
        case .tabs: return "rectangle.split.3x1"
        case .cards: return "rectangle.3.group"
        case .dashedList: return "list.dash"
        case .convertToWebClip: return "link"
        case .quickLook: return "eye"
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
                isRevealed: .constant(true),
                onSelect: { _ in }
            )
            .padding(40)
        }
        .preferredColorScheme(.dark)
    }
}
