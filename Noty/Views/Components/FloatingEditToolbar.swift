//
//  FloatingEditToolbar.swift
//  Noty
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
            HStack(spacing: 2) {
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
                    let yOffset = tooltipFrame.minY - toolbarFrame.minY - 26
                    
                    Text(tool.name)
                        .font(FontManager.heading(size: 11, weight: .medium))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .fixedSize()
                        .background(
                            Capsule()
                                .fill(Color("CardBackgroundColor"))
                                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
                        )
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
    
    private var headingTools: some View {
        HStack(spacing: 2) {
            FloatingToolButton(
                tool: .h1,
                systemName: "1.circle",
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
                systemName: "2.circle",
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
                systemName: "3.circle",
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
        HStack(spacing: 2) {
            FloatingToolButton(
                tool: .bold,
                systemName: "bold",
                isSelected: selectedTool == .bold,
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
                systemName: "italic",
                isSelected: selectedTool == .italic,
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
                systemName: "underline",
                isSelected: selectedTool == .underline,
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
                systemName: "strikethrough",
                isSelected: selectedTool == .strikethrough,
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
        }
    }
    
    private var listTool: some View {
        HStack(spacing: 2) {
            FloatingToolButton(
                tool: .bulletList,
                systemName: "list.bullet",
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
                tool: .todo,
                systemName: "checklist",
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
    
    private var indentationTools: some View {
        HStack(spacing: 2) {
            FloatingToolButton(
                tool: .indentLeft,
                systemName: "decrease.indent",
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
                systemName: "increase.indent",
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
        HStack(spacing: 2) {
            FloatingToolButton(
                tool: .alignLeft,
                systemName: "text.alignleft",
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
                systemName: "text.aligncenter",
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
                systemName: "text.alignright",
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
                systemName: "text.justify",
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
                systemName: "return",
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
        HStack(spacing: 2) {
            FloatingToolButton(
                tool: .textSelect,
                systemName: "selection.pin.in.out",
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
            
            FloatingToolButton(
                tool: .divider,
                systemName: "minus",
                isSelected: selectedTool == .divider,
                isHovered: hoveredTool == .divider,
                action: { handleToolAction(.divider) },
                onHoverChange: { hovering, frame in
                    hoveredTool = hovering ? .divider : nil
                    tooltipFrame = frame
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if hoveredTool == .divider { showTooltip = true }
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
    let systemName: String
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void
    var onHoverChange: ((Bool, CGRect) -> Void)? = nil
    
    @State private var buttonFrame: CGRect = .zero
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(FontManager.heading(size: 14, weight: .medium))
                .foregroundColor(
                    isSelected
                        ? Color("AccentColor")
                        : isHovered ? Color("PrimaryTextColor") : Color("SecondaryTextColor")
                )
                .scaleEffect(isSelected ? 1.1 : (isHovered ? 1.05 : 1.0))
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
