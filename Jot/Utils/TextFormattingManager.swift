//
//  TextFormattingManager.swift
//  Jot
//
//  Manages text formatting operations for rich text editing
//

import Combine
import SwiftUI

import AppKit

@MainActor
class TextFormattingManager: ObservableObject {
        @Published var isBold = false
        @Published var isItalic = false
        @Published var isUnderline = false
        @Published var isStrikethrough = false
        @Published var currentAlignment: NSTextAlignment = .left
        @Published var currentHeadingLevel: HeadingLevel = .none

        enum HeadingLevel {
            case none, h1, h2, h3

            var fontSize: CGFloat {
                switch self {
                case .none: return ThemeManager.currentBodyFontSize()
                case .h1: return 32
                case .h2: return 24
                case .h3: return 20
                }
            }

            var fontWeight: NSFont.Weight {
                switch self {
                case .none: return .regular
                case .h1, .h2, .h3: return .semibold
                }
            }
        }

        // MARK: - Undo Helpers

        private func captureSnapshot(_ storage: NSTextStorage, range: NSRange)
            -> [(NSRange, [NSAttributedString.Key: Any])]
        {
            var snapshot: [(NSRange, [NSAttributedString.Key: Any])] = []
            storage.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
                snapshot.append((subRange, attrs))
            }
            return snapshot
        }

        private func registerUndo(
            textView: NSTextView,
            snapshot: [(NSRange, [NSAttributedString.Key: Any])],
            actionName: String
        ) {
            guard let undoManager = textView.undoManager else { return }
            let storage = textView.textStorage
            undoManager.registerUndo(withTarget: textView) { [weak storage] tv in
                storage?.beginEditing()
                for (range, attrs) in snapshot {
                    storage?.setAttributes(attrs, range: range)
                }
                storage?.endEditing()
                tv.needsDisplay = true
            }
            undoManager.setActionName(actionName)
        }

        // MARK: - Text Formatting Actions

        func applyFormatting(to textView: NSTextView, tool: EditTool) {
            guard textView.textStorage != nil else { return }

            let selectedRange = textView.selectedRange()

            // Some tools don't require text selection
            let toolsNotRequiringSelection: [EditTool] = [
                .textSelect, .divider, .lineBreak, .todo, .imageUpload, .voiceRecord,
            ]

            if selectedRange.length == 0 && !toolsNotRequiringSelection.contains(tool) {
                return
            }

            switch tool {
            case .imageUpload, .voiceRecord:
                return
            case .titleCase:
                applyTitleCase(to: textView, in: selectedRange)
            case .h1:
                applyHeading(.h1, to: textView, in: selectedRange)
            case .h2:
                applyHeading(.h2, to: textView, in: selectedRange)
            case .h3:
                applyHeading(.h3, to: textView, in: selectedRange)
            case .bold:
                toggleBold(in: textView, range: selectedRange)
            case .italic:
                toggleItalic(in: textView, range: selectedRange)
            case .underline:
                toggleUnderline(in: textView, range: selectedRange)
            case .strikethrough:
                toggleStrikethrough(in: textView, range: selectedRange)
            case .bulletList:
                toggleBulletList(to: textView, in: selectedRange)
            case .todo:
                insertTodo(to: textView)
            case .indentLeft:
                adjustIndentation(to: textView, increase: false)
            case .indentRight:
                adjustIndentation(to: textView, increase: true)
            case .alignLeft:
                setAlignment(.left, to: textView, in: selectedRange)
            case .alignCenter:
                setAlignment(.center, to: textView, in: selectedRange)
            case .alignRight:
                setAlignment(.right, to: textView, in: selectedRange)
            case .alignJustify:
                setAlignment(.justified, to: textView, in: selectedRange)
            case .lineBreak:
                insertLineBreak(to: textView)
            case .textSelect:
                selectAll(in: textView)
            case .divider:
                insertDivider(to: textView)
            case .link:
                insertLink(to: textView, in: selectedRange)
            case .searchOnPage:
                return
            }

            updateFormattingState(from: textView)
        }

        // MARK: - Title Case

        private func applyTitleCase(to textView: NSTextView, in range: NSRange) {
            guard let text = textView.string as NSString? else { return }
            let substring = text.substring(with: range)
            let titleCased = substring.capitalized

            if textView.shouldChangeText(in: range, replacementString: titleCased) {
                textView.replaceCharacters(in: range, with: titleCased)
                textView.didChangeText()
            }
        }

        // MARK: - Headings

        private func applyHeading(
            _ level: HeadingLevel, to textView: NSTextView, in range: NSRange
        ) {
            guard let textStorage = textView.textStorage else { return }

            let snapshot = captureSnapshot(textStorage, range: range)

            textStorage.beginEditing()

            // Remove existing heading attributes
            textStorage.removeAttribute(.font, range: range)

            let weight: FontManager.Weight = level.fontWeight == .semibold ? .semibold : .regular
            let font = FontManager.headingNS(size: level.fontSize, weight: weight)
            textStorage.addAttribute(.font, value: font, range: range)

            // Update paragraph style for spacing
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacingBefore = level == .none ? 0 : 8
            paragraphStyle.paragraphSpacing = level == .none ? 4 : 12
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

            textStorage.endEditing()
            currentHeadingLevel = level

            registerUndo(textView: textView, snapshot: snapshot, actionName: "Heading")
        }

        // MARK: - Text Styles

        private func toggleBold(in textView: NSTextView, range: NSRange) {
            guard let textStorage = textView.textStorage else { return }
            let snapshot = captureSnapshot(textStorage, range: range)
            textStorage.beginEditing()

            var hasBold = false
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                if let font = value as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    if traits.contains(.boldFontMask) { hasBold = true }
                }
            }

            if hasBold {
                textStorage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    if let font = value as? NSFont {
                        let newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                        textStorage.addAttribute(.font, value: newFont, range: subRange)
                    }
                }
                isBold = false
            } else {
                textStorage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    if let font = value as? NSFont {
                        let newFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                        textStorage.addAttribute(.font, value: newFont, range: subRange)
                    }
                }
                isBold = true
            }

            textStorage.endEditing()
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Bold")
        }

        private func toggleItalic(in textView: NSTextView, range: NSRange) {
            guard let textStorage = textView.textStorage else { return }
            let snapshot = captureSnapshot(textStorage, range: range)
            textStorage.beginEditing()

            var hasItalic = false
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                if let font = value as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    if traits.contains(.italicFontMask) { hasItalic = true }
                }
            }

            if hasItalic {
                textStorage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    if let font = value as? NSFont {
                        let newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                        textStorage.addAttribute(.font, value: newFont, range: subRange)
                    }
                }
                isItalic = false
            } else {
                textStorage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    if let font = value as? NSFont {
                        let newFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                        textStorage.addAttribute(.font, value: newFont, range: subRange)
                    }
                }
                isItalic = true
            }

            textStorage.endEditing()
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Italic")
        }

        private func toggleUnderline(in textView: NSTextView, range: NSRange) {
            guard let textStorage = textView.textStorage else { return }
            let snapshot = captureSnapshot(textStorage, range: range)
            textStorage.beginEditing()

            var hasUnderline = false
            textStorage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
                if let style = value as? Int, style != 0 { hasUnderline = true }
            }

            if hasUnderline {
                textStorage.removeAttribute(.underlineStyle, range: range)
                isUnderline = false
            } else {
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                isUnderline = true
            }

            textStorage.endEditing()
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Underline")
        }

        private func toggleStrikethrough(in textView: NSTextView, range: NSRange) {
            guard let textStorage = textView.textStorage else { return }
            let snapshot = captureSnapshot(textStorage, range: range)
            textStorage.beginEditing()

            var hasStrikethrough = false
            textStorage.enumerateAttribute(.strikethroughStyle, in: range, options: []) { value, _, _ in
                if let style = value as? Int, style != 0 { hasStrikethrough = true }
            }

            if hasStrikethrough {
                textStorage.removeAttribute(.strikethroughStyle, range: range)
                isStrikethrough = false
            } else {
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                isStrikethrough = true
            }

            textStorage.endEditing()
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Strikethrough")
        }

        // MARK: - Lists

        private func toggleBulletList(to textView: NSTextView, in range: NSRange) {
            guard let textStorage = textView.textStorage else { return }

            textStorage.beginEditing()

            // Get paragraph range
            let paragraphRange = (textView.string as NSString).paragraphRange(for: range)
            let text = (textView.string as NSString).substring(with: paragraphRange)

            // Check if it's already a bullet list
            if text.hasPrefix("• ") {
                // Remove bullet
                let newText = String(text.dropFirst(2))
                if textView.shouldChangeText(in: paragraphRange, replacementString: newText) {
                    textView.replaceCharacters(in: paragraphRange, with: newText)
                }
            } else {
                // Add bullet
                let newText = "• " + text
                if textView.shouldChangeText(in: paragraphRange, replacementString: newText) {
                    textView.replaceCharacters(in: paragraphRange, with: newText)
                }
            }

            textStorage.endEditing()
            textView.didChangeText()
        }

        // MARK: - Indentation

        private func adjustIndentation(to textView: NSTextView, increase: Bool) {
            guard let textStorage = textView.textStorage else { return }
            let selectedRange = textView.selectedRange()

            let paragraphRange = (textView.string as NSString).paragraphRange(for: selectedRange)
            let snapshot = captureSnapshot(textStorage, range: paragraphRange)

            textStorage.beginEditing()

            textStorage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) {
                value, subRange, _ in
                let paragraphStyle =
                    (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()

                let indentAmount: CGFloat = 20
                if increase {
                    paragraphStyle.firstLineHeadIndent += indentAmount
                    paragraphStyle.headIndent += indentAmount
                } else {
                    paragraphStyle.firstLineHeadIndent = max(
                        0, paragraphStyle.firstLineHeadIndent - indentAmount)
                    paragraphStyle.headIndent = max(0, paragraphStyle.headIndent - indentAmount)
                }

                textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: subRange)
            }

            textStorage.endEditing()
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Indentation")
        }

        // MARK: - Alignment

        private func setAlignment(
            _ alignment: NSTextAlignment, to textView: NSTextView, in range: NSRange
        ) {
            guard let textStorage = textView.textStorage else { return }

            let paragraphRange = (textView.string as NSString).paragraphRange(for: range)
            let snapshot = captureSnapshot(textStorage, range: paragraphRange)

            textStorage.beginEditing()

            textStorage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) {
                value, subRange, _ in
                let paragraphStyle =
                    (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()
                paragraphStyle.alignment = alignment
                textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: subRange)
            }

            textStorage.endEditing()
            currentAlignment = alignment
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Alignment")
        }

        // MARK: - Special Insertions

        private func insertLineBreak(to textView: NSTextView) {
            textView.insertNewline(nil)
        }

        private func selectAll(in textView: NSTextView) {
            textView.selectAll(nil)
        }

        private func insertDivider(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()

            // Get the available width from the text container (adaptive to editor width)
            let availableWidth = textView.textContainer?.size.width ?? 400
            let lineWidth = availableWidth - 20  // Subtract padding for margins

            // Create a stroke line image using Core Graphics
            // This creates a clean horizontal line that adapts to light/dark mode
            let lineHeight: CGFloat = 1.0
            let image = NSImage(size: NSSize(width: lineWidth, height: lineHeight), flipped: false)
            { rect in
                NSColor.labelColor.withAlphaComponent(0.3).setFill()
                NSBezierPath(rect: rect).fill()
                return true
            }

            // Create text attachment with the stroke line image
            let attachment = NSTextAttachment()
            attachment.image = image

            // Create attributed string with proper spacing
            let mutableString = NSMutableAttributedString()
            mutableString.append(NSAttributedString(string: "\n"))
            mutableString.append(NSAttributedString(attachment: attachment))
            mutableString.append(NSAttributedString(string: "\n"))

            // Insert the divider
            if textView.shouldChangeText(in: selectedRange, replacementString: mutableString.string)
            {
                textStorage.replaceCharacters(in: selectedRange, with: mutableString)
                textView.didChangeText()

                // Move cursor after the divider
                let newPosition = selectedRange.location + mutableString.length
                textView.setSelectedRange(NSRange(location: newPosition, length: 0))
            }
        }

        private func insertLink(to textView: NSTextView, in range: NSRange) {
            // For now, just wrap selected text in markdown link syntax
            guard let text = textView.string as NSString? else { return }
            let selectedText = text.substring(with: range)
            // Insert markdown link with the selected text: [selectedText](url)
            let linkText = "[\(selectedText)](url)"

            if textView.shouldChangeText(in: range, replacementString: linkText) {
                textView.replaceCharacters(in: range, with: linkText)
                textView.didChangeText()

                // Select the "url" part for easy replacement
                let newRange = NSRange(location: range.location + selectedText.count + 3, length: 3)
                textView.setSelectedRange(newRange)
            }
        }

        private func insertTodo(to textView: NSTextView) {
            let todoText = "[ ] "
            let selectedRange = textView.selectedRange()

            if textView.shouldChangeText(in: selectedRange, replacementString: todoText) {
                textView.replaceCharacters(in: selectedRange, with: todoText)
                textView.didChangeText()
            }
        }

        // MARK: - Text Color

        static let customTextColorKey = NSAttributedString.Key("JotCustomTextColor")

        func applyTextColor(hex: String, range: NSRange, to textView: NSTextView) {
            guard range.length > 0, range.location != NSNotFound else { return }
            guard let storage = textView.textStorage else { return }
            guard NSMaxRange(range) <= storage.length else { return }

            let snapshot = captureSnapshot(storage, range: range)
            let nsColor = Self.nsColorFromHex(hex)

            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: nsColor, range: range)
            storage.addAttribute(Self.customTextColorKey, value: true, range: range)
            storage.endEditing()

            // Force the layout manager to re-render glyphs in the affected range.
            // Without this, selected text in dark mode won't visually update until deselected.
            textView.layoutManager?.invalidateDisplay(forCharacterRange: range)
            textView.needsDisplay = true
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Text Color")
        }

        static func nsColorFromHex(_ hex: String) -> NSColor {
            let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: clean).scanHexInt64(&int)
            return NSColor(
                srgbRed: CGFloat((int >> 16) & 0xFF) / 255.0,
                green: CGFloat((int >> 8) & 0xFF) / 255.0,
                blue: CGFloat(int & 0xFF) / 255.0,
                alpha: 1.0)
        }

        // MARK: - State Updates

        func updateFormattingState(from textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0, let textStorage = textView.textStorage else { return }

            // Check for bold/italic via NSFontManager trait masks for broad compatibility
            textStorage.enumerateAttribute(.font, in: selectedRange, options: []) {
                value, _, stop in
                if let font = value as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    isBold = traits.contains(.boldFontMask)
                    isItalic = traits.contains(.italicFontMask)
                    stop.pointee = true
                }
            }

            // Check for underline
            textStorage.enumerateAttribute(.underlineStyle, in: selectedRange, options: []) {
                value, _, stop in
                isUnderline = (value as? Int ?? 0) != 0
                stop.pointee = true
            }

            // Check for strikethrough
            textStorage.enumerateAttribute(.strikethroughStyle, in: selectedRange, options: []) {
                value, _, stop in
                isStrikethrough = (value as? Int ?? 0) != 0
                stop.pointee = true
            }

            // Check alignment
            textStorage.enumerateAttribute(.paragraphStyle, in: selectedRange, options: []) {
                value, _, stop in
                if let paragraphStyle = value as? NSParagraphStyle {
                    currentAlignment = paragraphStyle.alignment
                    stop.pointee = true
                }
            }
    }
}
