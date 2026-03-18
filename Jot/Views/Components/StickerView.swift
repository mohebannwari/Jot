//
//  StickerView.swift
//  Jot
//
//  Single sticky-note sticker with Figma-exact gradient, shadow, and typography.
//  Supports drag-to-move, corner resize (locked aspect ratio), inline text editing,
//  and right-click context menu for color / text-color / text-size / delete.
//

import SwiftUI

struct StickerView: View {
    @Binding var sticker: Sticker
    let isSelected: Bool
    @Binding var isEditing: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onChanged: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var resizeStartSize: CGFloat? = nil
    @State private var resizePreviewSize: CGFloat? = nil

    private var displaySize: CGFloat { resizePreviewSize ?? sticker.size }

    var body: some View {
        stickerBody
            .frame(width: displaySize, height: displaySize)
            .offset(dragOffset)
            .shadow(color: .black.opacity(0.10), radius: 3.5, x: -2, y: 2)
            .shadow(color: .black.opacity(0.09), radius: 6,   x: -8, y: 9)
            .shadow(color: .black.opacity(0.05), radius: 8.5,  x: -19, y: 21)
            .overlay(alignment: .bottomTrailing) {
                resizeHandle
            }
            .contentShape(Rectangle())
            .gesture(stickerDragGesture)
            .onTapGesture(count: 2) {
                enterEditMode()
            }
            .onTapGesture(count: 1) {
                onSelect()
            }
            .contextMenu { contextMenuContent }
            .onExitCommand {
                if isEditing {
                    exitEditMode()
                }
            }
            .onKeyPress(.delete) {
                if isSelected && !isEditing {
                    onDelete()
                    return .handled
                }
                return .ignored
            }
    }

    // MARK: - Sticker Body

    private var stickerBody: some View {
        ZStack(alignment: .topLeading) {
            // Base color fill
            sticker.color.baseColor

            // Fold shadow gradient at top
            LinearGradient(
                stops: [
                    .init(color: sticker.color.foldColor, location: 0),
                    .init(color: sticker.color.foldColor, location: 0.0866),
                    .init(color: sticker.color.foldColor.opacity(0), location: 0.1262)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Text content area — proportional padding keeps text below the fold at all sizes
            textContent
                .padding(.top, displaySize * 0.14)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Text Content

    @ViewBuilder
    private var textContent: some View {
        let textColor: Color = sticker.textColorDark ? .black : .white

        if isEditing {
            StickerTextEditor(
                text: $sticker.text,
                fontSize: sticker.fontSize,
                textColor: sticker.textColorDark ? .black : .white,
                stickerBaseColor: sticker.color.baseColor,
                onCommit: { exitEditMode() },
                onColorChange: { color in sticker.color = color; onChanged() },
                onTextColorChange: { dark in sticker.textColorDark = dark; onChanged() },
                onFontSizeChange: { size in sticker.fontSize = size; onChanged() },
                onDelete: onDelete,
                currentColor: sticker.color,
                currentTextColorDark: sticker.textColorDark,
                currentFontSize: sticker.fontSize
            )
            .onChange(of: sticker.text) { _, _ in onChanged() }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                Text(sticker.text.isEmpty ? "Type here..." : sticker.text)
                    .font(.system(size: sticker.fontSize, weight: .medium))
                    .tracking(-0.3)
                    .lineSpacing(max(0, (sticker.fontSize * 14/12) - sticker.fontSize))
                    .foregroundColor(sticker.text.isEmpty ? textColor.opacity(0.4) : textColor)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .scrollIndicators(.automatic)
        }
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if resizeStartSize == nil {
                            resizeStartSize = sticker.size
                        }
                        let delta = max(value.translation.width, value.translation.height)
                        let newSize = (resizeStartSize ?? sticker.size) + delta
                        resizePreviewSize = min(Sticker.maxSize, max(Sticker.minSize, newSize))
                    }
                    .onEnded { _ in
                        if let preview = resizePreviewSize {
                            sticker.size = preview
                            onChanged()
                        }
                        resizePreviewSize = nil
                        resizeStartSize = nil
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.frameResize(position: .bottomRight, directions: .all).push() }
                else { NSCursor.pop() }
            }
    }

    // MARK: - Drag Gesture (move sticker)

    private var stickerDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isEditing else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                // Always reset dragOffset to prevent visual desync
                // (e.g. if isEditing became true mid-drag via double-tap)
                let offset = dragOffset
                dragOffset = .zero
                guard !isEditing else { return }
                sticker.positionX += offset.width
                sticker.positionY += offset.height
                sticker.positionX = max(0, sticker.positionX)
                sticker.positionY = max(0, sticker.positionY)
                onChanged()
            }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        // Color picker
        Menu {
            ForEach(StickerColor.allCases, id: \.self) { color in
                Button {
                    sticker.color = color
                    onChanged()
                } label: {
                    HStack {
                        Text(color.displayName)
                        if sticker.color == color {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }

        // Text color
        Menu {
            Button {
                sticker.textColorDark = true
                onChanged()
            } label: {
                HStack {
                    Text("Dark")
                    if sticker.textColorDark { Image(systemName: "checkmark") }
                }
            }
            Button {
                sticker.textColorDark = false
                onChanged()
            } label: {
                HStack {
                    Text("Light")
                    if !sticker.textColorDark { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Label("Text Color", systemImage: "textformat")
        }

        // Text size
        Menu {
            ForEach(9...20, id: \.self) { size in
                Button {
                    sticker.fontSize = CGFloat(size)
                    onChanged()
                } label: {
                    HStack {
                        Text("\(size) pt")
                        if Int(sticker.fontSize) == size {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Text Size", systemImage: "textformat.size")
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete Post-it", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private func enterEditMode() {
        isEditing = true
        onSelect()
    }

    private func exitEditMode() {
        isEditing = false
    }
}

// MARK: - Sticker Text Editor (NSTextView-backed for proper macOS text input)

struct StickerTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let textColor: NSColor
    let stickerBaseNSColor: NSColor
    let onCommit: () -> Void

    // Context menu callbacks
    let onColorChange: (StickerColor) -> Void
    let onTextColorChange: (Bool) -> Void
    let onFontSizeChange: (CGFloat) -> Void
    let onDelete: () -> Void
    let currentColor: StickerColor
    let currentTextColorDark: Bool
    let currentFontSize: CGFloat

    init(
        text: Binding<String>,
        fontSize: CGFloat,
        textColor: Color,
        stickerBaseColor: Color,
        onCommit: @escaping () -> Void,
        onColorChange: @escaping (StickerColor) -> Void,
        onTextColorChange: @escaping (Bool) -> Void,
        onFontSizeChange: @escaping (CGFloat) -> Void,
        onDelete: @escaping () -> Void,
        currentColor: StickerColor,
        currentTextColorDark: Bool,
        currentFontSize: CGFloat
    ) {
        self._text = text
        self.fontSize = fontSize
        self.textColor = NSColor(textColor)
        self.stickerBaseNSColor = NSColor(stickerBaseColor)
        self.onCommit = onCommit
        self.onColorChange = onColorChange
        self.onTextColorChange = onTextColorChange
        self.onFontSizeChange = onFontSizeChange
        self.onDelete = onDelete
        self.currentColor = currentColor
        self.currentTextColorDark = currentTextColorDark
        self.currentFontSize = currentFontSize
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        // Narrow scrollbar
        if let scroller = scrollView.verticalScroller {
            scroller.controlSize = .mini
        }

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        // Subtle selection color — slightly darker version of sticker base color
        textView.selectedTextAttributes = [
            .backgroundColor: stickerBaseNSColor.blended(withFraction: 0.15, of: .black) ?? stickerBaseNSColor
        ]

        applyTextAttributes(to: textView)
        textView.string = text

        // Become first responder for immediate editing
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Update coordinator's parent reference for context menu
        context.coordinator.parent = self
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
        }
        // Only re-apply text attributes when they actually changed — avoids
        // resetting cursor position and breaking IME composition on every render
        let coord = context.coordinator
        if coord.lastAppliedFontSize != fontSize || coord.lastAppliedTextColor != textColor {
            applyTextAttributes(to: textView)
            coord.lastAppliedFontSize = fontSize
            coord.lastAppliedTextColor = textColor
        }
    }

    private func applyTextAttributes(to textView: NSTextView) {
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        textView.textColor = textColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = max(0, (fontSize * 14/12) - fontSize)
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .kern: -0.3
        ]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StickerTextEditor
        var lastAppliedFontSize: CGFloat = 0
        var lastAppliedTextColor: NSColor = .black

        init(_ parent: StickerTextEditor) {
            self.parent = parent
            self.lastAppliedFontSize = parent.fontSize
            self.lastAppliedTextColor = parent.textColor
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onCommit()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }

        // Override right-click menu to show sticker options instead of system Cut/Copy/Paste
        func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let menu = NSMenu()

            // Color submenu
            let colorMenu = NSMenu()
            for color in StickerColor.allCases {
                let item = NSMenuItem(title: color.displayName, action: #selector(changeColor(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = color
                if color == parent.currentColor { item.state = .on }
                colorMenu.addItem(item)
            }
            let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
            colorItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
            colorItem.submenu = colorMenu
            menu.addItem(colorItem)

            // Text Color submenu
            let textColorMenu = NSMenu()
            let darkItem = NSMenuItem(title: "Dark", action: #selector(setTextColorDark(_:)), keyEquivalent: "")
            darkItem.target = self
            darkItem.tag = 1
            if parent.currentTextColorDark { darkItem.state = .on }
            textColorMenu.addItem(darkItem)
            let lightItem = NSMenuItem(title: "Light", action: #selector(setTextColorLight(_:)), keyEquivalent: "")
            lightItem.target = self
            lightItem.tag = 0
            if !parent.currentTextColorDark { lightItem.state = .on }
            textColorMenu.addItem(lightItem)
            let textColorItem = NSMenuItem(title: "Text Color", action: nil, keyEquivalent: "")
            textColorItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
            textColorItem.submenu = textColorMenu
            menu.addItem(textColorItem)

            // Text Size submenu
            let sizeMenu = NSMenu()
            for size in 9...20 {
                let item = NSMenuItem(title: "\(size) pt", action: #selector(changeFontSize(_:)), keyEquivalent: "")
                item.target = self
                item.tag = size
                if Int(parent.currentFontSize) == size { item.state = .on }
                sizeMenu.addItem(item)
            }
            let sizeItem = NSMenuItem(title: "Text Size", action: nil, keyEquivalent: "")
            sizeItem.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: nil)
            sizeItem.submenu = sizeMenu
            menu.addItem(sizeItem)

            menu.addItem(.separator())

            // Delete
            let deleteItem = NSMenuItem(title: "Delete Post-it", action: #selector(deleteSticker(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            menu.addItem(deleteItem)

            return menu
        }

        @objc func changeColor(_ sender: NSMenuItem) {
            guard let color = sender.representedObject as? StickerColor else { return }
            parent.onColorChange(color)
        }

        @objc func setTextColorDark(_ sender: NSMenuItem) {
            parent.onTextColorChange(true)
        }

        @objc func setTextColorLight(_ sender: NSMenuItem) {
            parent.onTextColorChange(false)
        }

        @objc func changeFontSize(_ sender: NSMenuItem) {
            parent.onFontSizeChange(CGFloat(sender.tag))
        }

        @objc func deleteSticker(_ sender: NSMenuItem) {
            parent.onDelete()
        }
    }
}
