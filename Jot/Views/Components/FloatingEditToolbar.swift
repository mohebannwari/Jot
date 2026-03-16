//
//  FloatingEditToolbar.swift
//  Jot
//
//  Floating toolbar that appears near selected text for quick formatting.
//  Always expanded with 36pt height for compact presentation.
//

import SwiftUI

struct FloatingEditToolbar: View {
    // Position from parent view
    var position: CGPoint
    var placeAbove: Bool
    var width: CGFloat = 250

    // Formatting state from TextFormattingManager
    var isBoldActive: Bool = false
    var isItalicActive: Bool = false
    var isUnderlineActive: Bool = false
    var isStrikethroughActive: Bool = false
    var isHighlightActive: Bool = false

    // State management
    @State private var selectedTool: EditTool? = nil
    @State private var hoveredTool: EditTool? = nil
    @State private var showTooltip = false
    @State private var tooltipFrame: CGRect = .zero
    @Namespace private var toolbarNamespace
    
    // Animation states
    @State private var toolsVisible = false
    
    // Tool actions
    var onToolAction: ((EditTool) -> Void)?
    
    var body: some View {
        // Fixed-width toolbar with horizontal scrolling for all formatting tools
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // Highlight tool
                highlightTool
                    .opacity(toolsVisible ? 1 : 0)
                    .scaleEffect(toolsVisible ? 1 : 0.8)

                // Divider
                toolDivider

                // Heading styles
                headingTools
                    .opacity(toolsVisible ? 1 : 0)
                    .scaleEffect(toolsVisible ? 1 : 0.8)
                
                // Divider
                toolDivider
                
                // Text styles
                textStyleTools
                    .opacity(toolsVisible ? 1 : 0)
                    .scaleEffect(toolsVisible ? 1 : 0.8)
                
                // Divider
                toolDivider
                
                // List tools
                listTool
                    .opacity(toolsVisible ? 1 : 0)
                    .scaleEffect(toolsVisible ? 1 : 0.8)

                // Divider
                toolDivider

                // Code tools
                codeTools
                    .opacity(toolsVisible ? 1 : 0)
                    .scaleEffect(toolsVisible ? 1 : 0.8)

                // Divider
                toolDivider

                // Block-level tools (block quote, highlight)
                blockLevelTools
                    .opacity(toolsVisible ? 1 : 0)
                    .scaleEffect(toolsVisible ? 1 : 0.8)

                // Divider
                toolDivider

                // Indentation tools
                indentationTools
                    .opacity(toolsVisible ? 1 : 0)
                    .scaleEffect(toolsVisible ? 1 : 0.8)
                
                // Divider
                toolDivider
                
                // Alignment tools
                alignmentTools
                    .opacity(toolsVisible ? 1 : 0)
                    .scaleEffect(toolsVisible ? 1 : 0.8)
                
                // Divider
                toolDivider
                
                // Selection tools
                selectionTools
                    .opacity(toolsVisible ? 1 : 0)
                    .scaleEffect(toolsVisible ? 1 : 0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: width, height: 36)
        .liquidGlass(in: Capsule())
        .animation(.bouncy(duration: 0.4), value: toolsVisible)
        .onAppear {
            // Show tools immediately on appear since we're always expanded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.bouncy(duration: 0.3)) {
                    toolsVisible = true
                }
            }
        }
        .overlay {
            // Global tooltip overlay - renders outside all clipping containers
            if showTooltip, let tool = hoveredTool, tooltipFrame != .zero {
                GeometryReader { geometry in
                    let toolbarFrame = geometry.frame(in: .global)
                    let buttonCenterX = tooltipFrame.midX - toolbarFrame.minX
                    let yOffset = tooltipFrame.minY - toolbarFrame.minY - 16
                    
                    Text(tool.name)
                        .font(FontManager.heading(size: 11, weight: .medium))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .fixedSize()
                        .liquidGlass(in: Capsule())
                        .position(x: buttonCenterX, y: yOffset)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                        .zIndex(10000)
                }
            }
        }
    }
    
    // MARK: - Tool Groups
    
    // Helper for consistent dividers
    private var toolDivider: some View {
        Rectangle()
            .fill(Color("TertiaryTextColor").opacity(0.2))
            .frame(width: 1, height: 16)
            .opacity(toolsVisible ? 1 : 0)
            .scaleEffect(y: toolsVisible ? 1 : 0.5)
    }
    
    private var highlightTool: some View {
        FloatingToolButton(
            tool: .highlight,
            assetName: "IconHighlight",
            isSelected: selectedTool == .highlight,
            isHovered: hoveredTool == .highlight,
            action: { handleToolAction(.highlight) },
            onHoverChange: { hovering, frame in
                hoveredTool = hovering ? .highlight : nil
                tooltipFrame = frame
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if hoveredTool == .highlight { showTooltip = true }
                    }
                } else {
                    showTooltip = false
                }
            }
        )
    }

    private var headingTools: some View {
        HStack(spacing: 4) {
            FloatingToolButton(
                tool: .h1,
                assetName: "IconH1",
                isSelected: selectedTool == .h1,
                isHovered: hoveredTool == .h1,
                action: { handleToolAction(.h1) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .h1 : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .h1 { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .h2,
                assetName: "IconH2",
                isSelected: selectedTool == .h2,
                isHovered: hoveredTool == .h2,
                action: { handleToolAction(.h2) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .h2 : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .h2 { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .h3,
                assetName: "IconH3",
                isSelected: selectedTool == .h3,
                isHovered: hoveredTool == .h3,
                action: { handleToolAction(.h3) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .h3 : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .h3 { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
        }
    }
    
    private var textStyleTools: some View {
        HStack(spacing: 4) {
            FloatingToolButton(
                tool: .bold,
                assetName: "IconBold",
                isSelected: isBoldActive,
                isHovered: hoveredTool == .bold,
                action: { handleToolAction(.bold) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .bold : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .bold { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .italic,
                assetName: "IconItalic",
                isSelected: isItalicActive,
                isHovered: hoveredTool == .italic,
                action: { handleToolAction(.italic) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .italic : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .italic { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .underline,
                assetName: "IconUnderline",
                isSelected: isUnderlineActive,
                isHovered: hoveredTool == .underline,
                action: { handleToolAction(.underline) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .underline : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .underline { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .strikethrough,
                assetName: "IconStrikeThrough",
                isSelected: isStrikethroughActive,
                isHovered: hoveredTool == .strikethrough,
                action: { handleToolAction(.strikethrough) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .strikethrough : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .strikethrough { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )

            FloatingToolButton(
                tool: .highlight,
                assetName: "IconMarker",
                isSelected: isHighlightActive,
                isHovered: hoveredTool == .highlight,
                action: { handleToolAction(.highlight) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .highlight : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .highlight { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
        }
    }

    private var listTool: some View {
        HStack(spacing: 4) {
            FloatingToolButton(
                tool: .bulletList,
                assetName: "todo-list",
                isSelected: selectedTool == .bulletList,
                isHovered: hoveredTool == .bulletList,
                action: { handleToolAction(.bulletList) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .bulletList : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .bulletList { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .numberedList,
                assetName: "IconNumberedList",
                isSelected: selectedTool == .numberedList,
                isHovered: hoveredTool == .numberedList,
                action: { handleToolAction(.numberedList) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .numberedList : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .numberedList { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )

            FloatingToolButton(
                tool: .todo,
                assetName: "IconTodos",
                isSelected: selectedTool == .todo,
                isHovered: hoveredTool == .todo,
                action: { handleToolAction(.todo) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .todo : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .todo { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
        }
    }

    private var codeTools: some View {
        HStack(spacing: 4) {
            FloatingToolButton(
                tool: .codeBlock,
                assetName: "IconCode",
                isSelected: selectedTool == .codeBlock,
                isHovered: hoveredTool == .codeBlock,
                action: { handleToolAction(.codeBlock) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .codeBlock : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .codeBlock { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )

        }
    }

    private var blockLevelTools: some View {
        HStack(spacing: 4) {
            FloatingToolButton(
                tool: .blockQuote,
                assetName: "IconTextBlock",
                isSelected: selectedTool == .blockQuote,
                isHovered: hoveredTool == .blockQuote,
                action: { handleToolAction(.blockQuote) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .blockQuote : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .blockQuote { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )

        }
    }

    private var indentationTools: some View {
        HStack(spacing: 4) {
            FloatingToolButton(
                tool: .indentLeft,
                assetName: "IconTextIndentLeft",
                isSelected: selectedTool == .indentLeft,
                isHovered: hoveredTool == .indentLeft,
                action: { handleToolAction(.indentLeft) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .indentLeft : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .indentLeft { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .indentRight,
                assetName: "IconTextIndentRight",
                isSelected: selectedTool == .indentRight,
                isHovered: hoveredTool == .indentRight,
                action: { handleToolAction(.indentRight) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .indentRight : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .indentRight { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
        }
    }
    
    private var alignmentTools: some View {
        HStack(spacing: 4) {
            FloatingToolButton(
                tool: .alignLeft,
                assetName: "IconAlignmentLeft",
                isSelected: selectedTool == .alignLeft,
                isHovered: hoveredTool == .alignLeft,
                action: { handleToolAction(.alignLeft) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .alignLeft : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .alignLeft { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .alignCenter,
                assetName: "IconAlignmentCenter",
                isSelected: selectedTool == .alignCenter,
                isHovered: hoveredTool == .alignCenter,
                action: { handleToolAction(.alignCenter) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .alignCenter : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .alignCenter { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .alignRight,
                assetName: "IconAlignmentRight",
                isSelected: selectedTool == .alignRight,
                isHovered: hoveredTool == .alignRight,
                action: { handleToolAction(.alignRight) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .alignRight : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .alignRight { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .alignJustify,
                assetName: "IconAlignmentJustify",
                isSelected: selectedTool == .alignJustify,
                isHovered: hoveredTool == .alignJustify,
                action: { handleToolAction(.alignJustify) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .alignJustify : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .alignJustify { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
            
            FloatingToolButton(
                tool: .lineBreak,
                assetName: "IconLinebreak",
                isSelected: selectedTool == .lineBreak,
                isHovered: hoveredTool == .lineBreak,
                action: { handleToolAction(.lineBreak) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .lineBreak : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .lineBreak { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
        }
    }
    
    private var selectionTools: some View {
        HStack(spacing: 4) {
            FloatingToolButton(
                tool: .textSelect,
                assetName: "IconTextSelectDashed",
                isSelected: selectedTool == .textSelect,
                isHovered: hoveredTool == .textSelect,
                action: { handleToolAction(.textSelect) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .textSelect : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .textSelect { showTooltip = true }
                        }
                    } else {
                        showTooltip = false
                    }
                }
            )
        }
    }
    
    // MARK: - Actions
    
    private func handleToolAction(_ tool: EditTool) {
        HapticManager.shared.toolbarAction()
        selectedTool = tool
        onToolAction?(tool)
        
        // Auto-deselect after a moment for toggle-style tools
        if tool.isToggleable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                selectedTool = nil
            }
        }
    }
    
}

// MARK: - Floating Tool Button Component

private struct FloatingToolButton: View {
    let tool: EditTool
    var systemName: String = ""
    var assetName: String? = nil
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void
    var onHoverChange: ((Bool, CGRect) -> Void)? = nil

    @State private var buttonFrame: CGRect = .zero

    private var iconColor: Color {
        isSelected
            ? Color("AccentColor")
            : isHovered ? Color("PrimaryTextColor") : Color("IconSecondaryColor")
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let assetName {
                    Image(assetName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: systemName)
                        .font(FontManager.icon(size: 18, weight: .medium))
                }
            }
            .foregroundColor(iconColor)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.bouncy(duration: 0.2), value: isSelected)
            .animation(.bouncy(duration: 0.2), value: isHovered)
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
        .onHover { hovering in
            onHoverChange?(hovering, buttonFrame)
        }
    }
}

// MARK: - EditTool Enum

enum EditTool: String, CaseIterable {
    case titleCase
    case h1, h2, h3
    case bold, italic, underline, strikethrough
    case bulletList, numberedList, todo
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

    var isToggleable: Bool {
        switch self {
        case .bold, .italic, .underline, .strikethrough, .bulletList, .numberedList, .todo,
             .codeBlock, .blockQuote, .highlight:
            return true
        default:
            return false
        }
    }

    var name: String {
        switch self {
        case .titleCase: return "Title Case"
        case .h1: return "Heading 1"
        case .h2: return "Heading 2"
        case .h3: return "Heading 3"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .bulletList: return "Bullet List"
        case .numberedList: return "Numbered List"
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
