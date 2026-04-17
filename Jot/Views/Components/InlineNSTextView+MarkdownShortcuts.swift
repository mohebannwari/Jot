//
//  InlineNSTextView+MarkdownShortcuts.swift
//  Jot
//
//  Extracted from TodoEditorRepresentable.swift — markdown-style shortcut detection
//  that runs after every text insertion. Kept as an extension (not a new type) so the
//  call site in `InlineNSTextView.insertText(_:replacementRange:)` stays unchanged.
//
//  Block-level shortcuts (triggered on Space at line start):
//    - "- " / "* "       → bullet list
//    - "[ ] "            → todo checkbox
//    - "> "              → blockquote
//    - "N. "             → numbered list
//    - "-> "             → Figma arrow attachment + trailing space
//    - "=> "             → Unicode double arrow (\u{21D2})
//
//  Inline shortcuts (triggered on closing delimiter):
//    - **text**          → bold
//    - *text*            → italic
//    - ~~text~~          → strikethrough
//

import AppKit

extension InlineNSTextView {

    /// Base typing attributes for markdown shortcut results
    fileprivate var markdownBaseAttributes: [NSAttributedString.Key: Any] {
        let font = FontManager.bodyNS()
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
    }

    /// Detects and applies markdown-style shortcuts after text insertion.
    ///
    /// Access: `internal` (default). Called from
    /// `InlineNSTextView.insertText(_:replacementRange:)` in `TodoEditorRepresentable.swift`.
    /// The original declaration was `private`; extension-in-separate-file bumps it to
    /// internal so the original call site still resolves.
    func handleMarkdownShortcuts(inserted: String) {
        guard let textStorage = self.textStorage else { return }
        // Group shortcut replacement with the preceding character insertion
        // so Cmd+Z reverts both in one step
        undoManager?.groupsByEvent = false
        defer { undoManager?.groupsByEvent = true }
        let cursor = selectedRange().location

        // --- Block-level shortcuts (trigger on Space) ---
        if inserted == " " {
            let paraRange = (textStorage.string as NSString).paragraphRange(
                for: NSRange(location: max(0, cursor - 1), length: 0))
            let lineText = (textStorage.string as NSString).substring(with: paraRange)
            let trimmed = lineText.trimmingCharacters(in: .newlines)

            // Only trigger if cursor is right after the pattern (at start of line)
            let cursorInPara = cursor - paraRange.location
            struct BlockPattern {
                let prefix: String
                let action: String
            }
            let patterns: [BlockPattern] = [
                .init(prefix: "- ", action: "bullet"),
                .init(prefix: "* ", action: "bullet"),
                .init(prefix: "[ ] ", action: "todo"),
                .init(prefix: "> ", action: "quote"),
            ]

            for pattern in patterns {
                if trimmed == pattern.prefix.trimmingCharacters(in: .whitespaces)
                    || (cursorInPara == pattern.prefix.count && lineText.hasPrefix(pattern.prefix)) {
                    // Verify cursor position matches end of prefix
                    guard cursorInPara == pattern.prefix.count else { continue }

                    let deleteRange = NSRange(
                        location: paraRange.location,
                        length: pattern.prefix.count)

                    switch pattern.action {
                    case "bullet":
                        textStorage.replaceCharacters(in: deleteRange, with: "")
                        let newCursorPos = paraRange.location
                        setSelectedRange(NSRange(location: newCursorPos, length: 0))
                        if let coord = actionDelegate {
                            coord.formatter.applyFormatting(to: self, tool: .bulletList)
                        }
                        // Position cursor after "• " — toggleBulletList leaves it past the newline
                        setSelectedRange(NSRange(location: paraRange.location + 2, length: 0))
                    case "todo":
                        textStorage.replaceCharacters(in: deleteRange, with: "")
                        let newCursorPos = paraRange.location
                        setSelectedRange(NSRange(location: newCursorPos, length: 0))
                        if let coord = actionDelegate {
                            coord.insertTodo()
                        }
                    case "quote":
                        // Remove "> " prefix and apply block quote formatting atomically.
                        // beginEditing/endEditing prevents processEditing from firing
                        // between the character removal and attribute application — without
                        // this, styleTodoParagraphs() runs before .blockQuote is set
                        // and applies baseParagraphStyle (no indent).
                        textStorage.beginEditing()
                        textStorage.replaceCharacters(in: deleteRange, with: "")
                        let newCursorPos = paraRange.location
                        let newParaRange = (textStorage.string as NSString).paragraphRange(
                            for: NSRange(location: newCursorPos, length: 0))
                        let quoteStyle = TodoEditorRepresentable.Coordinator.blockQuoteParagraphStyle()
                        textStorage.addAttribute(.blockQuote, value: true, range: newParaRange)
                        textStorage.addAttribute(.paragraphStyle, value: quoteStyle, range: newParaRange)
                        textStorage.addAttribute(
                            .foregroundColor,
                            value: blockQuoteTextColor,
                            range: newParaRange)
                        textStorage.endEditing()
                        setSelectedRange(NSRange(location: newCursorPos, length: 0))
                        // Set typing attributes so first typed character gets the full style
                        var quoteTyping = TodoEditorRepresentable.Coordinator.baseTypingAttributes(
                            for: actionDelegate?.currentColorScheme)
                        quoteTyping[.blockQuote] = true
                        quoteTyping[.paragraphStyle] = quoteStyle
                        quoteTyping[.foregroundColor] = blockQuoteTextColor
                        typingAttributes = quoteTyping
                    default:
                        break
                    }
                    return
                }
            }

            // Check for numbered list pattern: "1. " at line start
            let olPattern = /^(\d+)\. $/
            if let match = trimmed.wholeMatch(of: olPattern),
               cursorInPara == trimmed.count {
                let num = Int(match.1) ?? 1
                // NSRange lengths are UTF-16 code units; use NSString length so a paragraph that
                // begins with a multi-scalar grapheme (emoji, combining marks) produces the right
                // delete range.
                let deleteRange = NSRange(
                    location: paraRange.location,
                    length: (trimmed as NSString).length)
                let prefix = "\(num). "
                textStorage.replaceCharacters(in: deleteRange, with: prefix)
                let prefixRange = NSRange(location: paraRange.location, length: prefix.count)
                textStorage.addAttribute(.orderedListNumber, value: num, range: prefixRange)
                setSelectedRange(NSRange(location: paraRange.location + prefix.count, length: 0))
                return
            }

            // Line-start `-> ` / `=> ` — Figma `IconArrowRight` attachment vs Unicode double arrow.
            if trimmed.wholeMatch(of: /^\s*-> $/) != nil,
               cursorInPara == trimmed.count,
               let coord = actionDelegate {
                let deleteRange = NSRange(location: paraRange.location, length: (trimmed as NSString).length)
                let seedAttrs = textStorage.attributes(at: paraRange.location, effectiveRange: nil)
                let chunk = NSMutableAttributedString(
                    attributedString: coord.makeArrowGlyphForMarkdownShortcut(merging: seedAttrs))
                let spaceAttrs = TodoEditorRepresentable.Coordinator.baseTypingAttributes(for: coord.currentColorScheme)
                chunk.append(NSAttributedString(string: " ", attributes: spaceAttrs))
                textStorage.replaceCharacters(in: deleteRange, with: chunk)
                setSelectedRange(NSRange(location: deleteRange.location + chunk.length, length: 0))
                return
            }
            if trimmed.wholeMatch(of: /^\s*=> $/) != nil,
               cursorInPara == trimmed.count {
                let deleteRange = NSRange(location: paraRange.location, length: (trimmed as NSString).length)
                let doubleArrow = "\u{21D2} "
                let attrs = TodoEditorRepresentable.Coordinator.baseTypingAttributes(
                    for: actionDelegate?.currentColorScheme)
                let chunk = NSAttributedString(string: doubleArrow, attributes: attrs)
                textStorage.replaceCharacters(in: deleteRange, with: chunk)
                setSelectedRange(NSRange(location: deleteRange.location + (doubleArrow as NSString).length, length: 0))
                return
            }
        }

        // --- Inline shortcuts (trigger on closing delimiter) ---
        if inserted == "*" || inserted == "`" || inserted == "~" {
            let paraRange = (textStorage.string as NSString).paragraphRange(
                for: NSRange(location: max(0, cursor - 1), length: 0))
            let lineStart = paraRange.location
            let textBeforeCursor = (textStorage.string as NSString).substring(
                with: NSRange(location: lineStart, length: cursor - lineStart))

            // Bold: **text**
            if inserted == "*" && textBeforeCursor.hasSuffix("*") {
                // Look for opening **
                let searchStr = textBeforeCursor
                if let range = searchStr.range(of: "**", options: .backwards,
                                                range: searchStr.startIndex..<searchStr.index(before: searchStr.endIndex)) {
                    let openOffset = searchStr.distance(from: searchStr.startIndex, to: range.lowerBound)
                    let contentStart = openOffset + 2
                    let contentEnd = searchStr.count - 1  // before the last *
                    if contentEnd > contentStart {
                        let content = String(searchStr[searchStr.index(searchStr.startIndex, offsetBy: contentStart)..<searchStr.index(searchStr.startIndex, offsetBy: contentEnd)])
                        if !content.isEmpty && !content.hasPrefix("*") {
                            // Replace **content** with bold content
                            let absStart = lineStart + openOffset
                            let fullLen = cursor - absStart  // includes closing *
                            let replaceRange = NSRange(location: absStart, length: fullLen)
                            var attrs = markdownBaseAttributes
                            if let font = attrs[.font] as? NSFont {
                                attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                            }
                            textStorage.replaceCharacters(in: replaceRange, with: NSAttributedString(string: content, attributes: attrs))
                            setSelectedRange(NSRange(location: absStart + content.count, length: 0))
                            return
                        }
                    }
                }
            }

            // Italic: *text* (single asterisk, not **)
            if inserted == "*" {
                let searchStr = textBeforeCursor
                // Find last single * that isn't part of ** — search before the closing *
                let searchRange = searchStr.startIndex..<searchStr.index(before: searchStr.endIndex)
                if let lastStar = searchStr[searchRange].lastIndex(of: "*") {
                    let afterStar = searchStr.index(after: lastStar)
                    // Bounds check: afterStar must be a valid index before subscripting
                    guard afterStar < searchStr.endIndex else { return }
                    // Make sure it's a single * (not **) — check before only when not at start
                    let notDoubleBefore = lastStar == searchStr.startIndex || searchStr[searchStr.index(before: lastStar)] != "*"
                    if notDoubleBefore && searchStr[afterStar] != "*" {
                        let openOffset = searchStr.distance(from: searchStr.startIndex, to: lastStar)
                        let contentStart = openOffset + 1
                        let contentEnd = searchStr.count  // before closing *
                        if contentEnd > contentStart {
                            let content = String(searchStr[searchStr.index(searchStr.startIndex, offsetBy: contentStart)...])
                            if !content.isEmpty {
                                let absStart = lineStart + openOffset
                                let fullLen = cursor - absStart
                                let replaceRange = NSRange(location: absStart, length: fullLen)
                                var attrs = markdownBaseAttributes
                                if let font = attrs[.font] as? NSFont {
                                    attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                                }
                                textStorage.replaceCharacters(in: replaceRange, with: NSAttributedString(string: content, attributes: attrs))
                                setSelectedRange(NSRange(location: absStart + content.count, length: 0))
                                return
                            }
                        }
                    }
                }
            }

            // Strikethrough: ~~text~~
            if inserted == "~" && textBeforeCursor.hasSuffix("~") {
                let searchStr = textBeforeCursor
                if let range = searchStr.range(of: "~~", options: .backwards,
                                                range: searchStr.startIndex..<searchStr.index(before: searchStr.endIndex)) {
                    let openOffset = searchStr.distance(from: searchStr.startIndex, to: range.lowerBound)
                    let contentStart = openOffset + 2
                    let contentEnd = searchStr.count - 1
                    if contentEnd > contentStart {
                        let content = String(searchStr[searchStr.index(searchStr.startIndex, offsetBy: contentStart)..<searchStr.index(searchStr.startIndex, offsetBy: contentEnd)])
                        if !content.isEmpty && !content.hasPrefix("~") {
                            let absStart = lineStart + openOffset
                            let fullLen = cursor - absStart
                            let replaceRange = NSRange(location: absStart, length: fullLen)
                            var attrs = markdownBaseAttributes
                            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                            attrs[.foregroundColor] = checkedTodoTextColor
                            textStorage.replaceCharacters(in: replaceRange, with: NSAttributedString(string: content, attributes: attrs))
                            setSelectedRange(NSRange(location: absStart + content.count, length: 0))
                            return
                        }
                    }
                }
            }
        }

        // --- Divider shortcut: --- or *** at line start, trigger on Enter ---
        // (handled separately since Enter triggers newline insertion)
    }
}
