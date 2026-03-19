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
        @Published var isHighlight = false
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
                .bulletList, .numberedList, .dashedList, .h1, .h2, .h3, .blockQuote,
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
            case .numberedList:
                toggleNumberedList(to: textView, in: selectedRange)
            case .dashedList:
                toggleDashedList(to: textView, in: selectedRange)
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
            case .blockQuote:
                toggleBlockQuote(to: textView, in: selectedRange)
            case .highlight:
                return  // Highlight requires a color parameter — handled separately via applyHighlight()
            case .searchOnPage, .table, .callout, .codeBlock, .fileLink, .sticker, .tabs:
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

            // Toggle: if all text in range is already at this heading level, revert to body
            var allMatchLevel = range.length > 0
            if range.length > 0 {
                textStorage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
                    if let font = value as? NSFont {
                        if font.pointSize != level.fontSize {
                            allMatchLevel = false
                            stop.pointee = true
                        }
                    } else {
                        allMatchLevel = false
                        stop.pointee = true
                    }
                }
            }

            let effectiveLevel = allMatchLevel ? .none : level

            let snapshot = captureSnapshot(textStorage, range: range)

            textStorage.beginEditing()

            // Remove existing heading attributes
            textStorage.removeAttribute(.font, range: range)

            let weight: FontManager.Weight = effectiveLevel.fontWeight == .semibold ? .semibold : .regular
            let font = FontManager.headingNS(size: effectiveLevel.fontSize, weight: weight)
            textStorage.addAttribute(.font, value: font, range: range)

            // Update paragraph style for spacing
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacingBefore = effectiveLevel == .none ? 0 : 8
            paragraphStyle.paragraphSpacing = effectiveLevel == .none ? 4 : 12
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

            textStorage.endEditing()
            currentHeadingLevel = effectiveLevel

            registerUndo(textView: textView, snapshot: snapshot, actionName: "Heading")
        }

        // MARK: - Text Styles

        private func toggleBold(in textView: NSTextView, range: NSRange) {
            guard let textStorage = textView.textStorage else { return }
            let snapshot = captureSnapshot(textStorage, range: range)
            textStorage.beginEditing()

            var allBold = true
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                if let font = value as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    if !traits.contains(.boldFontMask) { allBold = false }
                } else { allBold = false }
            }

            if allBold {
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

            var allItalic = true
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                if let font = value as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    if !traits.contains(.italicFontMask) { allItalic = false }
                } else { allItalic = false }
            }

            if allItalic {
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

            let paragraphRange = (textView.string as NSString).paragraphRange(for: range)
            let text = (textView.string as NSString).substring(with: paragraphRange)

            if text.hasPrefix("\u{2022} ") {
                let newText = String(text.dropFirst(2))
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: paragraphRange, with: newText)
                textStorage.endEditing()
            } else {
                let newText = "\u{2022} " + text
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: paragraphRange, with: newText)
                textStorage.endEditing()
            }
        }

        private func toggleNumberedList(to textView: NSTextView, in range: NSRange) {
            guard let textStorage = textView.textStorage else { return }

            let paragraphRange = (textStorage.string as NSString).paragraphRange(for: range)
            let text = (textStorage.string as NSString).substring(with: paragraphRange)

            let hasOL = paragraphRange.length > 0
                && textStorage.attribute(.orderedListNumber, at: paragraphRange.location, effectiveRange: nil) != nil

            textStorage.beginEditing()
            if hasOL {
                if let dotRange = text.range(of: ". ") {
                    let prefixLen = text.distance(from: text.startIndex, to: dotRange.upperBound)
                    let removeRange = NSRange(location: paragraphRange.location, length: prefixLen)
                    textStorage.replaceCharacters(in: removeRange, with: "")
                }
            } else {
                var insertText = text
                if insertText.hasPrefix("\u{2022} ") {
                    insertText = String(insertText.dropFirst(2))
                }
                let prefix = "1. "
                let newText = prefix + insertText
                textStorage.replaceCharacters(in: paragraphRange, with: newText)
                let prefixRange = NSRange(location: paragraphRange.location, length: prefix.count)
                textStorage.addAttribute(.orderedListNumber, value: 1, range: prefixRange)
            }
            textStorage.endEditing()
        }

        // MARK: - Block Quote

        func toggleBlockQuote(to textView: NSTextView, in range: NSRange) {
            guard let textStorage = textView.textStorage else { return }

            let paragraphRange = (textStorage.string as NSString).paragraphRange(for: range)

            // Check if already a block quote
            let hasQuote = paragraphRange.length > 0
                && textStorage.attribute(.blockQuote, at: paragraphRange.location, effectiveRange: nil) as? Bool == true

            let snapshot = captureSnapshot(textStorage, range: paragraphRange)
            textStorage.beginEditing()

            if hasQuote {
                // Remove block quote formatting
                textStorage.removeAttribute(.blockQuote, range: paragraphRange)
                // Reset paragraph indent
                textStorage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, subRange, _ in
                    let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                        ?? NSMutableParagraphStyle()
                    style.firstLineHeadIndent = 0
                    style.headIndent = 0
                    textStorage.addAttribute(.paragraphStyle, value: style, range: subRange)
                }
                // Restore label color
                textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: paragraphRange)
            } else {
                // Apply block quote formatting with full paragraph style (line height + indent)
                textStorage.addAttribute(.blockQuote, value: true, range: paragraphRange)
                let style = NSMutableParagraphStyle()
                let spacing = ThemeManager.currentLineSpacing()
                let baseLineHeight: CGFloat = FontManager.bodyNS().pointSize * 1.2
                let scaledHeight = baseLineHeight * spacing.multiplier / 1.2
                style.lineHeightMultiple = spacing.multiplier
                style.minimumLineHeight = scaledHeight
                style.maximumLineHeight = scaledHeight + 4
                style.paragraphSpacing = 8
                style.firstLineHeadIndent = 20
                style.headIndent = 20
                textStorage.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
                textStorage.addAttribute(
                    .foregroundColor,
                    value: NSColor.labelColor.withAlphaComponent(0.7),
                    range: paragraphRange)
            }

            textStorage.endEditing()
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Block Quote")

            // Set typing attributes so the first character typed gets the full quote style
            var typingAttrs = textView.typingAttributes
            typingAttrs[.blockQuote] = hasQuote ? nil : true
            if hasQuote {
                typingAttrs[.foregroundColor] = NSColor.labelColor
                let resetStyle = NSMutableParagraphStyle()
                typingAttrs[.paragraphStyle] = resetStyle
            } else {
                typingAttrs[.foregroundColor] = NSColor.labelColor.withAlphaComponent(0.7)
                let spacing = ThemeManager.currentLineSpacing()
                let baseLineHeight: CGFloat = FontManager.bodyNS().pointSize * 1.2
                let scaledHeight = baseLineHeight * spacing.multiplier / 1.2
                let quoteStyle = NSMutableParagraphStyle()
                quoteStyle.lineHeightMultiple = spacing.multiplier
                quoteStyle.minimumLineHeight = scaledHeight
                quoteStyle.maximumLineHeight = scaledHeight + 4
                quoteStyle.paragraphSpacing = 8
                quoteStyle.firstLineHeadIndent = 20
                quoteStyle.headIndent = 20
                typingAttrs[.paragraphStyle] = quoteStyle
            }
            textView.typingAttributes = typingAttrs
        }

        // MARK: - Text Highlight

        func applyHighlight(hex: String, range: NSRange, to textView: NSTextView) {
            guard range.length > 0, range.location != NSNotFound else { return }
            guard let storage = textView.textStorage else { return }
            guard NSMaxRange(range) <= storage.length else { return }

            let snapshot = captureSnapshot(storage, range: range)
            let bgColor = Self.nsColorFromHex(hex).withAlphaComponent(0.35)

            storage.beginEditing()
            storage.addAttribute(.backgroundColor, value: bgColor, range: range)
            storage.addAttribute(.highlightColor, value: hex, range: range)

            // Strip highlight from newline characters — prevents full-width background
            // extension and highlight bleeding into new paragraphs
            let text = storage.string as NSString
            for pos in range.location..<NSMaxRange(range) {
                if text.character(at: pos) == 0x0A {
                    let nlRange = NSRange(location: pos, length: 1)
                    storage.removeAttribute(.backgroundColor, range: nlRange)
                    storage.removeAttribute(.highlightColor, range: nlRange)
                }
            }

            storage.endEditing()

            textView.needsDisplay = true
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Highlight")
        }

        func removeHighlight(range: NSRange, from textView: NSTextView) {
            guard range.length > 0, let storage = textView.textStorage else { return }
            guard NSMaxRange(range) <= storage.length else { return }

            let snapshot = captureSnapshot(storage, range: range)

            storage.beginEditing()
            // Only strip .backgroundColor where .highlightColor is present to avoid
            // collateral damage on search highlights or other background colors
            storage.enumerateAttribute(.highlightColor, in: range, options: []) { value, subRange, _ in
                if value != nil {
                    storage.removeAttribute(.backgroundColor, range: subRange)
                    storage.removeAttribute(.highlightColor, range: subRange)
                }
            }
            storage.endEditing()

            textView.needsDisplay = true
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Remove Highlight")
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

            // Use NoteDividerAttachment so dividers survive serialize/deserialize round-trips
            var containerWidth = textView.textContainer?.size.width ?? 400
            if containerWidth < 1 { containerWidth = 400 }
            let dividerHeight: CGFloat = 20
            let attachment = NoteDividerAttachment(data: nil, ofType: nil)
            let cellSize = CGSize(width: containerWidth, height: dividerHeight)
            attachment.attachmentCell = DividerSizeAttachmentCell(size: cellSize)
            attachment.bounds = CGRect(origin: .zero, size: cellSize)

            let mutableString = NSMutableAttributedString()
            mutableString.append(NSAttributedString(string: "\n"))
            mutableString.append(NSAttributedString(attachment: attachment))
            mutableString.append(NSAttributedString(string: "\n"))

            if textView.shouldChangeText(in: selectedRange, replacementString: mutableString.string)
            {
                textStorage.replaceCharacters(in: selectedRange, with: mutableString)
                textView.didChangeText()

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
                let newRange = NSRange(location: range.location + (selectedText as NSString).length + 3, length: 3)
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

        func removeTextColor(range: NSRange, from textView: NSTextView) {
            guard range.length > 0, let storage = textView.textStorage else { return }
            guard NSMaxRange(range) <= storage.length else { return }

            let snapshot = captureSnapshot(storage, range: range)

            storage.beginEditing()
            storage.removeAttribute(Self.customTextColorKey, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            storage.endEditing()

            textView.layoutManager?.invalidateDisplay(forCharacterRange: range)
            textView.needsDisplay = true
            registerUndo(textView: textView, snapshot: snapshot, actionName: "Remove Text Color")
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

            if selectedRange.length == 0 {
                // No selection — reflect typing attributes at insertion point
                let attrs = textView.typingAttributes
                if let font = attrs[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    isBold = traits.contains(.boldFontMask)
                    isItalic = traits.contains(.italicFontMask)
                } else {
                    isBold = false
                    isItalic = false
                }
                isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
                isStrikethrough = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
                // Check storage directly — typing attributes may not carry custom keys
                if let storage = textView.textStorage, selectedRange.location < storage.length {
                    isHighlight = storage.attribute(.highlightColor, at: selectedRange.location, effectiveRange: nil) as? String != nil
                } else {
                    isHighlight = false
                }
                if let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
                    currentAlignment = paragraphStyle.alignment
                }
                return
            }

            guard let textStorage = textView.textStorage else { return }

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

            // Check for highlight — any highlighted run in selection activates the button
            var foundHighlight = false
            textStorage.enumerateAttribute(.highlightColor, in: selectedRange, options: []) {
                value, _, stop in
                if (value as? String) != nil { foundHighlight = true; stop.pointee = true }
            }
            isHighlight = foundHighlight

            // Check alignment
            textStorage.enumerateAttribute(.paragraphStyle, in: selectedRange, options: []) {
                value, _, stop in
                if let paragraphStyle = value as? NSParagraphStyle {
                    currentAlignment = paragraphStyle.alignment
                    stop.pointee = true
                }
            }
    }

    // MARK: - Dashed List

    private func toggleDashedList(to textView: NSTextView, in range: NSRange) {
        guard let textStorage = textView.textStorage else { return }

        let paragraphRange = (textView.string as NSString).paragraphRange(for: range)
        let text = (textView.string as NSString).substring(with: paragraphRange)

        textStorage.beginEditing()
        if text.hasPrefix("- ") {
            let newText = String(text.dropFirst(2))
            textStorage.replaceCharacters(in: paragraphRange, with: newText)
        } else {
            var insertText = text
            if insertText.hasPrefix("\u{2022} ") {
                insertText = String(insertText.dropFirst(2))
            }
            let newText = "- " + insertText
            textStorage.replaceCharacters(in: paragraphRange, with: newText)
        }
        textStorage.endEditing()
    }

    // MARK: - Per-Selection Font Size

    func applyFontSize(_ size: CGFloat, to textView: NSTextView, range: NSRange) {
        guard let textStorage = textView.textStorage, range.length > 0 else { return }

        let snapshot = captureSnapshot(textStorage, range: range)

        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let existingFont = value as? NSFont ?? NSFont.systemFont(ofSize: size)
            let descriptor = existingFont.fontDescriptor
            let newFont = NSFont(descriptor: descriptor, size: size) ?? existingFont
            textStorage.addAttribute(.font, value: newFont, range: subRange)
        }
        textStorage.endEditing()

        registerUndo(textView: textView, snapshot: snapshot, actionName: "Change Font Size")
        textView.needsDisplay = true
        updateFormattingState(from: textView)
    }

    // MARK: - Per-Selection Font Family

    func applyFontFamily(_ style: BodyFontStyle, to textView: NSTextView, range: NSRange) {
        guard let textStorage = textView.textStorage, range.length > 0 else { return }

        let snapshot = captureSnapshot(textStorage, range: range)

        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let existingFont = value as? NSFont ?? NSFont.systemFont(ofSize: 16)
            let size = existingFont.pointSize
            let traits = existingFont.fontDescriptor.symbolicTraits

            let weight: FontManager.Weight
            if traits.contains(.bold) {
                weight = .semibold
            } else {
                weight = .regular
            }

            var newFont: NSFont
            switch style {
            case .default:
                newFont = FontManager.headingNS(size: size, weight: weight)
            case .system:
                let nsWeight: NSFont.Weight = weight == .semibold ? .semibold : .regular
                newFont = NSFont.systemFont(ofSize: size, weight: nsWeight)
            case .mono:
                let nsWeight: NSFont.Weight = weight == .semibold ? .semibold : .regular
                newFont = NSFont.monospacedSystemFont(ofSize: size, weight: nsWeight)
            }

            // Preserve italic trait
            if traits.contains(.italic) {
                let italicDescriptor = newFont.fontDescriptor.withSymbolicTraits(
                    newFont.fontDescriptor.symbolicTraits.union(.italic)
                )
                newFont = NSFont(descriptor: italicDescriptor, size: size) ?? newFont
            }

            textStorage.addAttribute(.font, value: newFont, range: subRange)
        }
        textStorage.endEditing()

        registerUndo(textView: textView, snapshot: snapshot, actionName: "Change Font Family")
        textView.needsDisplay = true
        updateFormattingState(from: textView)
    }
}
