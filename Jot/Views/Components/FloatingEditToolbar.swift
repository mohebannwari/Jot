//
//  FloatingEditToolbar.swift
//  Jot
//
//  Compact floating toolbar with pill triggers and dropdown submenus.
//  Hugs its content — no fixed width, no horizontal scrolling.
//

import SwiftUI

// MARK: - Submenu Type

enum ToolbarSubmenuType: Equatable {
    case textOptions
    case fontSize
    case fontFamily
    case color
    case translate
    case editContent
}

// MARK: - Preference Keys

struct ToolbarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 540
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ToolbarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 46
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PillOffsetKey: PreferenceKey {
    static var defaultValue: [ToolbarSubmenuType: CGFloat] = [:]
    static func reduce(value: inout [ToolbarSubmenuType: CGFloat], nextValue: () -> [ToolbarSubmenuType: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Floating Edit Toolbar

struct FloatingEditToolbar: View {
    // Formatting state
    var isBoldActive: Bool = false
    var isItalicActive: Bool = false
    var isUnderlineActive: Bool = false
    var isStrikethroughActive: Bool = false
    var isHighlightActive: Bool = false
    var currentHeadingLevel: Int = 0

    // Font state
    var currentFontSize: CGFloat = 16
    var currentFontFamily: String = "default"
    var currentTextColorHex: String? = nil

    // AI availability
    var isAIAvailable: Bool = false

    // Submenu state (binding so parent can dismiss)
    @Binding var activeSubmenu: ToolbarSubmenuType?

    // Callbacks
    var onToolAction: ((EditTool) -> Void)?
    var onFontSizeSelected: ((CGFloat) -> Void)?
    var onFontFamilySelected: ((BodyFontStyle) -> Void)?
    var onColorSelected: ((String) -> Void)?
    var onColorRemoved: (() -> Void)?

    // Animation
    @State private var toolsVisible = false

    @Environment(\.colorScheme) private var colorScheme

    private var pillBg: Color {
        colorScheme == .dark
            ? Color("SecondaryBackgroundColor")
            : .white
    }

    private var pillTextColor: Color {
        colorScheme == .dark ? .white : Color("PrimaryTextColor")
    }

    private var pillShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.5)
            : Color.black.opacity(0.12)
    }

    private var pillShadowRadius: CGFloat {
        colorScheme == .dark ? 3 : 2
    }

    var body: some View {
        HStack(spacing: 12) {
            // Section 1: Pickers
            HStack(spacing: 4) {
                textStylePill
                fontSizePill
                fontPickerPill
            }
            .opacity(toolsVisible ? 1 : 0)
            .scaleEffect(toolsVisible ? 1 : 0.85)

            dotDivider

            // Section 2: Quick actions
            HStack(spacing: 8) {
                toolIconButton("IconTodos", tool: .todo)
                toolIconButton("insert link", tool: .convertToWebClip)
                toolIconButton("IconAlignmentLeftBar", tool: .blockQuote)
                toolIconButton("IconMarker2", tool: .highlight, isActive: isHighlightActive)
            }
            .opacity(toolsVisible ? 1 : 0)
            .scaleEffect(toolsVisible ? 1 : 0.85)

            if isAIAvailable {
                dotDivider

                // Section 3: AI tools (translate, edit content)
                HStack(spacing: 8) {
                    submenuIconButton("IconAiTranslate", submenu: .translate)
                    submenuIconButton("IconArrowsAllSides2", submenu: .editContent)
                }
                .opacity(toolsVisible ? 1 : 0)
                .scaleEffect(toolsVisible ? 1 : 0.85)
            }

            dotDivider

            // Section 4: Color picker trigger
            colorTriggerPill
                .opacity(toolsVisible ? 1 : 0)
                .scaleEffect(toolsVisible ? 1 : 0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .fixedSize()
        .coordinateSpace(name: "toolbar")
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ToolbarWidthKey.self, value: geo.size.width)
                    .preference(key: ToolbarHeightKey.self, value: geo.size.height)
            }
        )
        .thinLiquidGlass(in: Capsule())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.arrow.set()
            case .ended:
                break
            @unknown default:
                break
            }
        }
        .animation(.bouncy(duration: 0.4), value: toolsVisible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.bouncy(duration: 0.3)) {
                    toolsVisible = true
                }
            }
        }
    }

    // MARK: - Dot Divider

    private var dotDivider: some View {
        Circle()
            .fill(Color.primary.opacity(0.35))
            .frame(width: 2, height: 2)
            .opacity(toolsVisible ? 1 : 0)
    }

    // MARK: - Text Style Pill

    private var textStylePill: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                activeSubmenu = activeSubmenu == .textOptions ? nil : .textOptions
            }
        } label: {
            HStack(spacing: 0) {
                Image(currentTextStyleIcon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(pillTextColor.opacity(0.6))
                Image("IconChevronDownSmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(pillTextColor.opacity(0.6))
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(pillBg)
                .shadow(color: pillShadowColor, radius: pillShadowRadius, x: 0, y: 1)
        )
        .background(GeometryReader { geo in
            Color.clear.preference(key: PillOffsetKey.self, value: [.textOptions: geo.frame(in: .named("toolbar")).midX])
        })
    }

    private var currentTextStyleIcon: String {
        if currentHeadingLevel == 1 { return "IconNumber1Circle" }
        if currentHeadingLevel == 2 { return "IconNumber2Circle" }
        if currentHeadingLevel == 3 { return "IconNumber3Circle" }
        if isStrikethroughActive { return "IconStrikeThrough" }
        if isUnderlineActive { return "IconUnderline" }
        if isItalicActive { return "IconItalic" }
        if isBoldActive { return "IconBold" }
        return "IconTitleCase"
    }

    // MARK: - Font Size Pill

    private var fontSizePill: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                activeSubmenu = activeSubmenu == .fontSize ? nil : .fontSize
            }
        } label: {
            HStack(spacing: 0) {
                Text("\(Int(currentFontSize))")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .lineLimit(1)
                    .foregroundColor(pillTextColor)
                    .monospacedDigit()
                Image("IconChevronDownSmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(pillTextColor.opacity(0.6))
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(pillBg)
                .shadow(color: pillShadowColor, radius: pillShadowRadius, x: 0, y: 1)
        )
        .background(GeometryReader { geo in
            Color.clear.preference(key: PillOffsetKey.self, value: [.fontSize: geo.frame(in: .named("toolbar")).midX])
        })
    }

    // MARK: - Font Picker Pill

    private var fontPickerPill: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                activeSubmenu = activeSubmenu == .fontFamily ? nil : .fontFamily
            }
        } label: {
            HStack(spacing: 0) {
                Image("IconFontStyle")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15.5, height: 15.5)
                    .foregroundColor(pillTextColor.opacity(0.6))
                Image("IconChevronDownSmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(pillTextColor.opacity(0.6))
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(pillBg)
                .shadow(color: pillShadowColor, radius: pillShadowRadius, x: 0, y: 1)
        )
        .background(GeometryReader { geo in
            Color.clear.preference(key: PillOffsetKey.self, value: [.fontFamily: geo.frame(in: .named("toolbar")).midX])
        })
    }

    // MARK: - Color Trigger Pill

    private var colorTriggerPill: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                activeSubmenu = activeSubmenu == .color ? nil : .color
            }
        } label: {
            HStack(spacing: 0) {
                Circle()
                    .fill(currentTextColorHex.flatMap { Color(hex: $0) } ?? pillTextColor)
                    .frame(width: 16, height: 16)
                Image("IconChevronDownSmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(pillTextColor.opacity(0.6))
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(pillBg)
                .shadow(color: pillShadowColor, radius: pillShadowRadius, x: 0, y: 1)
        )
        .background(GeometryReader { geo in
            Color.clear.preference(key: PillOffsetKey.self, value: [.color: geo.frame(in: .named("toolbar")).midX])
        })
    }

    // MARK: - Icon Button Helper

    private func submenuIconButton(_ assetName: String, submenu: ToolbarSubmenuType) -> some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                activeSubmenu = activeSubmenu == submenu ? nil : submenu
            }
        } label: {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundColor(activeSubmenu == submenu ? Color("AccentColor") : Color("IconSecondaryColor"))
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .background(GeometryReader { geo in
            Color.clear.preference(key: PillOffsetKey.self, value: [submenu: geo.frame(in: .named("toolbar")).midX])
        })
    }

    private func toolIconButton(_ assetName: String, tool: EditTool, isActive: Bool = false) -> some View {
        Button {
            HapticManager.shared.toolbarAction()
            onToolAction?(tool)
        } label: {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundColor(isActive ? Color("AccentColor") : Color("IconSecondaryColor"))
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
}

// MARK: - EditTool Enum

enum EditTool: String, CaseIterable {
    case body
    case titleCase
    case h1, h2, h3
    case bold, italic, underline, strikethrough
    case bulletList, numberedList, dashedList, todo
    case indentLeft, indentRight
    case alignLeft, alignCenter, alignRight, alignJustify
    case lineBreak
    case textSelect, divider
    case link
    case imageUpload
    case voiceRecord
    case searchOnPage
    case table
    case codeBlock
    case blockQuote
    case highlight
    case callout
    case fileLink
    case sticker
    case tabs
    case cards
    case convertToWebClip

    var isToggleable: Bool {
        switch self {
        case .bold, .italic, .underline, .strikethrough, .bulletList, .numberedList, .dashedList, .todo,
             .codeBlock, .blockQuote:
            return true
        default:
            return false
        }
    }

    var name: String {
        switch self {
        case .body: return "Body"
        case .titleCase: return "Title Case"
        case .h1: return "Heading 1"
        case .h2: return "Heading 2"
        case .h3: return "Heading 3"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .bulletList: return "Bulleted List"
        case .numberedList: return "Numbered List"
        case .dashedList: return "Dashed List"
        case .todo: return "To-Do"
        case .indentLeft: return "Decrease Indent"
        case .indentRight: return "Increase Indent"
        case .alignLeft: return "Align Left"
        case .alignCenter: return "Align Center"
        case .alignRight: return "Align Right"
        case .alignJustify: return "Justify"
        case .lineBreak: return "Line Break"
        case .textSelect: return "Select Text"
        case .divider: return "Insert Divider"
        case .link: return "Insert Link"
        case .imageUpload: return "Image Upload"
        case .voiceRecord: return "Voice Record"
        case .searchOnPage: return "Search on Page"
        case .table: return "Table"
        case .codeBlock: return "Code Block"
        case .blockQuote: return "Block Quote"
        case .highlight: return "Highlight"
        case .callout: return "Callout"
        case .fileLink: return "Attach File"
        case .sticker: return "Post-it"
        case .tabs: return "Tabs"
        case .cards: return "Cards"
        case .convertToWebClip: return "Convert to Web Clip"
        }
    }

    var keyboardShortcut: KeyEquivalent? {
        switch self {
        case .bold: return "b"
        case .italic: return "i"
        case .underline: return "u"
        default: return nil
        }
    }
}
