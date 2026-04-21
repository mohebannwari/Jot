//
//  TodoEditorRepresentable+Deserializer.swift
//  Jot
//
//  Extracted from TodoEditorRepresentable.swift — the tag-markup → NSAttributedString
//  deserializer, ~950 lines. Lives here as a Coordinator extension (rather than a
//  standalone `NoteDeserializer` namespace) because the function depends on 14
//  `make*Attachment` factory methods on the Coordinator plus 17 internal static
//  helpers and `currentColorScheme` instance state. A pure-function extraction would
//  require a 14-closure injection struct; that indirection cost isn't worth the weak
//  testability win (the function's behavior is inherently attachment-coupled and
//  needs real NSTextAttachment subclasses to exercise).
//
//  Moving it to a sibling file still achieves the primary extraction goal — the main
//  `TodoEditorRepresentable.swift` shrinks by ~950 lines. Access for `deserialize`
//  changed from `private` to `internal` (default) so the main-file call sites in
//  `applyInitialText` can still reach it across the file boundary.
//
//  Invariants guarded (all regression-tested elsewhere):
//    - C1: legacy `\u{2192} ` line-start arrow advances index by 2 (consumes trailing space).
//    - H3: `[[color|HEX]]` state-toggle composes with `[[ic]]` inline-code.
//    - Blockquote `headIndent = 20`, `tailIndent = -4`, `lineBreakMode = .byWordWrapping`.
//    - `[[/code]]` orphan close-tag skipped cleanly.
//    - Webclip, linkcard, image, file paragraph-style boundaries.
//

import AppKit

extension TodoEditorRepresentable.Coordinator {

        func deserialize(_ text: String) -> NSAttributedString {
            // Handle empty text case
            if text.isEmpty {
                return NSAttributedString(
                    string: "", attributes: Self.baseTypingAttributes(for: currentColorScheme))
            }

            // Strip AI metadata block if present — it lives outside the editor's domain.
            // NoteDetailView handles AI persistence separately; the editor only renders content.
            var text = text
            if let aiStart = text.range(of: "\n[[ai-block]]") ?? text.range(of: "[[ai-block]]") {
                text = String(text[text.startIndex..<aiStart.lowerBound])
            }
            guard !text.isEmpty else {
                return NSAttributedString(
                    string: "", attributes: Self.baseTypingAttributes(for: currentColorScheme))
            }

            let result = NSMutableAttributedString()
            var index = text.startIndex
            var lastWasWebClip = false

            // Inline formatting state
            var fmtBold = false
            var fmtItalic = false
            var fmtUnderline = false
            var fmtStrikethrough = false
            var fmtHeading: TextFormattingManager.HeadingLevel = .none
            var fmtAlignment: NSTextAlignment = .left
            var fmtBlockQuote = false
            var fmtHighlightHex: String? = nil
            var fmtHighlightVariant: Int? = nil
            /// True while inside `[[ic]]...[[/ic]]` — maps to monospace + `.inlineCode` for pill rendering.
            var fmtInlineCode = false

            // Buffer for accumulating plain text characters with the same attributes.
            // Flushed as a single NSAttributedString when formatting changes or a tag is hit.
            var textBuffer = ""
            let colorSchemeForBuffer = currentColorScheme
            func flushBuffer() {
                guard !textBuffer.isEmpty else { return }
                var attrs = Self.formattingAttributes(
                    base: colorSchemeForBuffer,
                    heading: fmtHeading,
                    bold: fmtBold,
                    italic: fmtItalic,
                    underline: fmtUnderline, strikethrough: fmtStrikethrough,
                    alignment: fmtAlignment)
                if fmtBlockQuote {
                    attrs[.blockQuote] = true
                    attrs[.paragraphStyle] = Self.blockQuoteParagraphStyle()
                    attrs[.foregroundColor] = blockQuoteTextColor
                }
                if let hlHex = fmtHighlightHex {
                    attrs[.highlightColor] = hlHex
                    attrs[.highlightVariant] = fmtHighlightVariant ?? Int.random(in: 0..<8)
                }
                if fmtInlineCode {
                    attrs[.font] = RichTextSerializer.inlineCodeFont(bold: fmtBold, italic: fmtItalic)
                    attrs[.inlineCode] = true
                }
                result.append(NSAttributedString(string: textBuffer, attributes: attrs))
                textBuffer = ""
            }

            /// Same attribute stack as ``flushBuffer()`` for inline specials (arrow, etc.) that are not plain text runs.
            func attributesMatchingBufferedPlainText() -> [NSAttributedString.Key: Any] {
                var attrs = Self.formattingAttributes(
                    base: colorSchemeForBuffer,
                    heading: fmtHeading,
                    bold: fmtBold,
                    italic: fmtItalic,
                    underline: fmtUnderline, strikethrough: fmtStrikethrough,
                    alignment: fmtAlignment)
                if fmtBlockQuote {
                    attrs[.blockQuote] = true
                    attrs[.paragraphStyle] = Self.blockQuoteParagraphStyle()
                    attrs[.foregroundColor] = blockQuoteTextColor
                }
                if let hlHex = fmtHighlightHex {
                    attrs[.highlightColor] = hlHex
                    attrs[.highlightVariant] = fmtHighlightVariant ?? Int.random(in: 0..<8)
                }
                if fmtInlineCode {
                    attrs[.font] = RichTextSerializer.inlineCodeFont(bold: fmtBold, italic: fmtItalic)
                    attrs[.inlineCode] = true
                }
                return attrs
            }

            /// True if `index` sits at the start of a paragraph (document start or right after `\n`).
            /// Used to upgrade legacy line-start Unicode arrows (`\u{2192}`) to the Figma attachment
            /// so notes written before `-> ` was auto-converted render consistently.
            func isAtParagraphStart() -> Bool {
                if index == text.startIndex { return true }
                let prev = text.index(before: index)
                return text[prev] == "\n"
            }

            while index < text.endIndex {
                // Legacy line-start Unicode arrow → Figma arrow attachment. Keeps `\u{21D2}` (`=>`) as
                // Unicode text by design. Runs BEFORE buffering so the plain-text run isn't polluted.
                if isAtParagraphStart(),
                   text[index...].hasPrefix("\u{2192} ") {
                    flushBuffer()
                    result.append(makeArrowAttachment(merging: attributesMatchingBufferedPlainText()))
                    // Consume both the arrow glyph AND the trailing space that matched the pattern,
                    // otherwise the space gets buffered on the next iteration and every reload of
                    // a legacy note silently grows by one space per arrow.
                    index = text.index(index, offsetBy: 2)
                    lastWasWebClip = false
                    continue
                }
                if text[index...].hasPrefix("[x]") || text[index...].hasPrefix("[ ]") {
                    flushBuffer()
                    let isChecked = text[index...].hasPrefix("[x]")
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = TodoCheckboxAttachmentCell(isChecked: isChecked)
                    attachment.bounds = CGRect(
                        x: 0, y: Self.checkboxAttachmentYOffset, width: Self.checkboxAttachmentWidth,
                        height: Self.checkboxIconSize)
                    let attString = NSMutableAttributedString(attachment: attachment)
                    attString.addAttribute(
                        .baselineOffset, value: Self.checkboxBaselineOffset,
                        range: NSRange(location: 0, length: attString.length))
                    result.append(attString)
                    index = text.index(index, offsetBy: 3)
                    lastWasWebClip = false
                    continue
                } else if text[index...].hasPrefix(Self.webClipMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let webclipText = String(text[index..<endIndex])
                        if let regex = Self.webClipRegex,
                            let match = regex.firstMatch(
                                in: webclipText,
                                options: [],
                                range: NSRange(location: 0, length: webclipText.utf16.count)
                            )
                        {
                            let rawTitle = Self.string(from: match, at: 1, in: webclipText)
                            let rawDescription = Self.string(
                                from: match, at: 2, in: webclipText)
                            let rawURL = Self.string(from: match, at: 3, in: webclipText)

                            let cleanedTitle = Self.sanitizedWebClipComponent(rawTitle)
                            let cleanedDescription = Self.sanitizedWebClipComponent(
                                rawDescription)
                            let normalizedURL = Self.normalizedURL(from: rawURL)
                            let linkForAttachment =
                                normalizedURL.isEmpty ? rawURL : normalizedURL
                            let domain = Self.sanitizedWebClipComponent(
                                Self.resolvedDomain(from: linkForAttachment)
                            )

                            let attachment = makeWebClipAttachment(
                                url: linkForAttachment,
                                title: cleanedTitle.isEmpty ? nil : cleanedTitle,
                                description: cleanedDescription.isEmpty
                                    ? nil : cleanedDescription,
                                domain: domain.isEmpty ? nil : domain
                            )
                            result.append(attachment)

                            // Add space after webclip for horizontal spacing
                            let space = NSAttributedString(
                                string: " ",
                                attributes: Self.baseTypingAttributes(for: currentColorScheme))
                            result.append(space)

                            index = endIndex
                            lastWasWebClip = true
                            continue
                        } else {
                            // Regex failed — preserve raw markup as corruptedBlock for lossless round-trip
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            var attrs = baseAttributes
                            attrs[.corruptedBlock] = webclipText
                            attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                            result.append(NSAttributedString(string: "[Corrupted webclip block]", attributes: attrs))
                            index = endIndex
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix(Self.linkCardMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let cardText = String(text[index..<endIndex])
                        if let regex = Self.linkCardRegex,
                           let match = regex.firstMatch(
                               in: cardText, options: [],
                               range: NSRange(location: 0, length: cardText.utf16.count))
                        {
                            let rawTitle = Self.string(from: match, at: 1, in: cardText)
                            let rawDescription = Self.string(from: match, at: 2, in: cardText)
                            let rawURL = Self.string(from: match, at: 3, in: cardText)

                            let cleanedTitle = Self.sanitizedWebClipComponent(rawTitle)
                            let cleanedDescription = Self.sanitizedWebClipComponent(rawDescription)
                            let normalizedURL = Self.normalizedURL(from: rawURL)
                            let linkForAttachment = normalizedURL.isEmpty ? rawURL : normalizedURL
                            let domain = Self.sanitizedWebClipComponent(
                                Self.resolvedDomain(from: linkForAttachment))

                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            // Ensure link card is on its own paragraph (same as code blocks/images)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                            let cardAttr = makeLinkCardAttachment(
                                url: linkForAttachment,
                                title: cleanedTitle.isEmpty ? domain : cleanedTitle,
                                description: cleanedDescription,
                                domain: domain)
                            result.append(cardAttr)
                            // Trailing newline so subsequent content gets its own paragraph
                            if endIndex < text.endIndex {
                                if !text[endIndex].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            index = endIndex
                            lastWasWebClip = false
                            continue
                        } else {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            var attrs = baseAttributes
                            attrs[.corruptedBlock] = cardText
                            attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                            result.append(NSAttributedString(string: "[Corrupted linkcard block]", attributes: attrs))
                            index = endIndex
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix(Self.plainLinkMarkupPrefix) {
                    flushBuffer()
                    if let closeRange = text[index...].range(of: "]]") {
                        let endIndex = closeRange.upperBound
                        let linkText = String(text[index..<endIndex])
                        let prefixLen = Self.plainLinkMarkupPrefix.count
                        guard linkText.count >= prefixLen + 2 else {
                            index = endIndex
                            continue
                        }
                        let innerStart = linkText.index(linkText.startIndex, offsetBy: prefixLen)
                        let innerEnd = linkText.index(linkText.endIndex, offsetBy: -2)
                        guard innerStart < innerEnd else {
                            index = endIndex
                            continue
                        }
                        let inner = String(linkText[innerStart..<innerEnd])
                        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                        let rawURL = String(parts[0])
                        let labelPart: String? = parts.count > 1 ? String(parts[1]) : nil
                        let attachment = makePlainLinkAttachment(url: rawURL, label: labelPart)
                        result.append(attachment)

                        let space = NSAttributedString(
                            string: " ",
                            attributes: Self.baseTypingAttributes(for: currentColorScheme))
                        result.append(space)

                        index = endIndex
                        lastWasWebClip = true
                        continue
                    }
                } else if text[index...].hasPrefix(AttachmentMarkup.fileLinkMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let fileLinkText = String(text[index..<endIndex])
                        if let regex = AttachmentMarkup.fileLinkRegex,
                           let match = regex.firstMatch(
                               in: fileLinkText,
                               options: [],
                               range: NSRange(location: 0, length: fileLinkText.utf16.count)
                           )
                        {
                            let filePath = Self.string(from: match, at: 1, in: fileLinkText)
                            let displayName = Self.string(from: match, at: 2, in: fileLinkText)
                            let bookmarkBase64 = Self.string(from: match, at: 3, in: fileLinkText)

                            let baseAttributes = Self.baseTypingAttributes(
                                for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.whitespacesAndNewlines.contains(lastScalar)
                            {
                                let leadingSpace = NSAttributedString(
                                    string: " ", attributes: baseAttributes)
                                result.append(leadingSpace)
                            }

                            let attachment = makeFileLinkAttachment(filePath: filePath, displayName: displayName, bookmarkBase64: bookmarkBase64)
                            result.append(attachment)

                            let shouldAddTrailingSpace: Bool
                            if endIndex < text.endIndex {
                                let nextCharacter = text[endIndex]
                                shouldAddTrailingSpace = !nextCharacter.isWhitespace
                            } else {
                                shouldAddTrailingSpace = true
                            }

                            if shouldAddTrailingSpace {
                                let trailingSpace = NSAttributedString(
                                    string: " ", attributes: baseAttributes)
                                result.append(trailingSpace)
                            }

                            index = endIndex
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix(AttachmentMarkup.fileMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let fileText = String(text[index..<endIndex])
                        if let regex = AttachmentMarkup.fileRegex,
                           let match = regex.firstMatch(
                               in: fileText,
                               options: [],
                               range: NSRange(location: 0, length: fileText.utf16.count)
                           )
                        {
                            let rawType = Self.string(from: match, at: 1, in: fileText)
                            let storedFilename = Self.string(from: match, at: 2, in: fileText)
                            let rawOriginal = Self.string(from: match, at: 3, in: fileText)
                            let rawViewMode = Self.string(from: match, at: 4, in: fileText)

                            let typeIdentifier = rawType.isEmpty ? "public.data" : rawType
                            let originalName = rawOriginal.isEmpty ? storedFilename : rawOriginal
                            let viewMode = FileViewMode(rawValue: rawViewMode) ?? .tag

                            let storedFile = FileAttachmentStorageManager.StoredFile(
                                storedFilename: storedFilename,
                                originalFilename: originalName,
                                typeIdentifier: typeIdentifier
                            )

                            let metadata = FileAttachmentMetadata(
                                storedFilename: storedFile.storedFilename,
                                originalFilename: storedFile.originalFilename,
                                typeIdentifier: storedFile.typeIdentifier,
                                displayLabel: originalName,
                                viewMode: viewMode
                            )

                            let baseAttributes = Self.baseTypingAttributes(
                                for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.whitespacesAndNewlines.contains(lastScalar)
                            {
                                let leadingSpace = NSAttributedString(
                                    string: " ", attributes: baseAttributes)
                                result.append(leadingSpace)
                            }

                            let attachment = makeFileAttachment(metadata: metadata)
                            result.append(attachment)

                            let shouldAddTrailingSpace: Bool
                            if endIndex < text.endIndex {
                                let nextCharacter = text[endIndex]
                                shouldAddTrailingSpace = !nextCharacter.isWhitespace
                            } else {
                                shouldAddTrailingSpace = true
                            }

                            if shouldAddTrailingSpace {
                                let trailingSpace = NSAttributedString(
                                    string: " ", attributes: baseAttributes)
                                result.append(trailingSpace)
                            }

                            index = endIndex
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix(AttachmentMarkup.imageMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let imageText = String(text[index..<endIndex])
                        if let regex = AttachmentMarkup.imageRegex,
                            let match = regex.firstMatch(
                                in: imageText,
                                options: [],
                                range: NSRange(location: 0, length: imageText.utf16.count)
                            )
                        {
                            let filename = Self.string(from: match, at: 1, in: imageText)
                            // Guard against empty filename (e.g. [[image|||]]) -- treat as corrupted
                            guard !filename.isEmpty else {
                                let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                                var attrs = baseAttributes
                                attrs[.corruptedBlock] = imageText
                                attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                                result.append(NSAttributedString(string: "[Corrupted image block]", attributes: attrs))
                                index = endIndex
                                lastWasWebClip = false
                                continue
                            }
                            let ratioString = Self.string(from: match, at: 2, in: imageText)
                            let widthRatio = Double(ratioString).map { CGFloat($0) } ?? 1.0

                            // Block-level: ensure newline before image
                            let baseAttributes = Self.baseTypingAttributes(
                                for: currentColorScheme)
                            if result.length > 0,
                                let lastScalar = result.string.unicodeScalars.last,
                                !CharacterSet.newlines.contains(lastScalar)
                            {
                                result.append(NSAttributedString(
                                    string: "\n", attributes: baseAttributes))
                            }

                            let attachment = makeImageAttachment(
                                filename: filename,
                                widthRatio: widthRatio
                            )
                            result.append(attachment)

                            // Ensure newline after so text doesn't flow inline
                            if endIndex < text.endIndex {
                                let nextChar = text[endIndex]
                                if !nextChar.isNewline {
                                    result.append(NSAttributedString(
                                        string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(
                                    string: "\n", attributes: baseAttributes))
                            }

                            index = endIndex
                            lastWasWebClip = false
                            continue
                        } else {
                            // Regex failed — preserve raw markup as corruptedBlock for lossless round-trip
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            var attrs = baseAttributes
                            attrs[.corruptedBlock] = imageText
                            attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                            result.append(NSAttributedString(string: "[Corrupted image block]", attributes: attrs))
                            index = endIndex
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[table|") {
                    flushBuffer()
                    let remaining = text[index...]
                    if let closingRange = remaining.range(of: "[[/table]]") {
                        let tableBlock = String(remaining[remaining.startIndex..<closingRange.upperBound])
                        if let tableData = NoteTableData.deserialize(from: tableBlock) {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            let attachment = makeTableAttachment(tableData: tableData)
                            result.append(attachment)

                            let afterClosing = closingRange.upperBound
                            if afterClosing < text.endIndex {
                                if !text[afterClosing].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        } else {
                            // Deserialization failed — preserve raw markup as a .corruptedBlock
                            // attribute so it re-serializes without data loss
                            let rawMarkup = String(remaining[remaining.startIndex..<closingRange.upperBound])
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            var attrs = baseAttributes
                            attrs[.corruptedBlock] = rawMarkup
                            attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                            result.append(NSAttributedString(string: "[Corrupted table block]", attributes: attrs))
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[codeblock|") {
                    flushBuffer()
                    let remaining = text[index...]
                    if let closingRange = remaining.range(of: "[[/codeblock]]") {
                        let codeBlockText = String(remaining[remaining.startIndex..<closingRange.upperBound])
                        if let codeBlockData = CodeBlockData.deserialize(from: codeBlockText) {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                            let attachment = makeCodeBlockAttachment(codeBlockData: codeBlockData)
                            result.append(attachment)
                            let afterClosing = closingRange.upperBound
                            if afterClosing < text.endIndex {
                                if !text[afterClosing].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        } else {
                            let rawMarkup = String(remaining[remaining.startIndex..<closingRange.upperBound])
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            var attrs = baseAttributes
                            attrs[.corruptedBlock] = rawMarkup
                            attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                            result.append(NSAttributedString(string: "[Corrupted code block]", attributes: attrs))
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[tabs|") {
                    flushBuffer()
                    let remaining = text[index...]
                    if let closingRange = remaining.range(of: "[[/tabs]]") {
                        let tabsText = String(remaining[remaining.startIndex..<closingRange.upperBound])
                        if let tabsData = TabsContainerData.deserialize(from: tabsText) {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                            let attachment = makeTabsAttachment(tabsData: tabsData)
                            result.append(attachment)
                            let afterClosing = closingRange.upperBound
                            if afterClosing < text.endIndex {
                                if !text[afterClosing].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        } else {
                            let rawMarkup = String(remaining[remaining.startIndex..<closingRange.upperBound])
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            var attrs = baseAttributes
                            attrs[.corruptedBlock] = rawMarkup
                            attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                            result.append(NSAttributedString(string: "[Corrupted tabs block]", attributes: attrs))
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[cards|") {
                    flushBuffer()
                    let remaining = text[index...]
                    if let closingRange = remaining.range(of: "[[/cards]]") {
                        let cardsText = String(remaining[remaining.startIndex..<closingRange.upperBound])
                        if let cardSectionData = CardSectionData.deserialize(from: cardsText) {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                            let attachment = makeCardSectionAttachment(cardSectionData: cardSectionData)
                            result.append(attachment)
                            let afterClosing = closingRange.upperBound
                            if afterClosing < text.endIndex {
                                if !text[afterClosing].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        } else {
                            let rawMarkup = String(remaining[remaining.startIndex..<closingRange.upperBound])
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            var attrs = baseAttributes
                            attrs[.corruptedBlock] = rawMarkup
                            attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                            result.append(NSAttributedString(string: "[Corrupted cards block]", attributes: attrs))
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[toggle|") {
                    flushBuffer()
                    let remaining = text[index...]
                    if let closingRange = remaining.range(of: "[[/toggle]]") {
                        let toggleBlock = String(remaining[remaining.startIndex..<closingRange.upperBound])
                        if let toggleData = ToggleData.deserialize(from: toggleBlock) {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            let attachment = makeToggleAttachment(toggleData: toggleData)
                            result.append(attachment)

                            let afterClosing = closingRange.upperBound
                            if afterClosing < text.endIndex {
                                if !text[afterClosing].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        } else {
                            let rawMarkup = String(remaining[remaining.startIndex..<closingRange.upperBound])
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            var attrs = baseAttributes
                            attrs[.corruptedBlock] = rawMarkup
                            attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                            result.append(NSAttributedString(string: "[Corrupted toggle block]", attributes: attrs))
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[callout|") {
                    flushBuffer()
                    let remaining = text[index...]
                    if let closingRange = remaining.range(of: "[[/callout]]") {
                        let calloutBlock = String(remaining[remaining.startIndex..<closingRange.upperBound])
                        if let calloutData = CalloutData.deserialize(from: calloutBlock) {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            let attachment = makeCalloutAttachment(calloutData: calloutData)
                            result.append(attachment)

                            let afterClosing = closingRange.upperBound
                            if afterClosing < text.endIndex {
                                if !text[afterClosing].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        } else {
                            let rawMarkup = String(remaining[remaining.startIndex..<closingRange.upperBound])
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            var attrs = baseAttributes
                            attrs[.corruptedBlock] = rawMarkup
                            attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
                            result.append(NSAttributedString(string: "[Corrupted callout block]", attributes: attrs))
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[divider]]") {
                    flushBuffer()
                    let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                    // Ensure preceding newline
                    if result.length > 0,
                       let lastScalar = result.string.unicodeScalars.last,
                       !CharacterSet.newlines.contains(lastScalar) {
                        result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                    }
                    let attachment = makeDividerAttachment()
                    result.append(attachment)
                    // Match other block attachments: do not add a second newline when markup
                    // already has one after [[divider]] (avoids phantom empty paragraph per load).
                    let afterDivider = text.index(index, offsetBy: "[[divider]]".count)
                    if afterDivider < text.endIndex {
                        if !text[afterDivider].isNewline {
                            result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                        }
                    } else {
                        result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                    }
                    index = afterDivider
                    lastWasWebClip = false
                    continue
                } else if text[index...].hasPrefix("[[notelink|") {
                    flushBuffer()
                    let prefixLen = "[[notelink|".count
                    let afterPrefix = text.index(index, offsetBy: prefixLen)
                    if let closeBracket = text[afterPrefix...].range(of: "]]") {
                        let body = String(text[afterPrefix..<closeBracket.lowerBound])
                        let parts = body.split(separator: "|", maxSplits: 1)
                        if parts.count == 2 {
                            let noteIDStr = String(parts[0])
                            let noteTitle = String(parts[1])

                            let notelinkStr = makeNotelinkAttachment(noteID: noteIDStr, noteTitle: noteTitle)
                            result.append(notelinkStr)

                            index = closeBracket.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[ic]]") {
                    flushBuffer()
                    fmtInlineCode = true
                    index = text.index(index, offsetBy: "[[ic]]".count)
                    continue
                } else if text[index...].hasPrefix("[[/ic]]") {
                    flushBuffer()
                    fmtInlineCode = false
                    index = text.index(index, offsetBy: "[[/ic]]".count)
                    continue
                } else if text[index...].hasPrefix("[[b]]") {
                    flushBuffer()
                    fmtBold = true
                    index = text.index(index, offsetBy: 5)
                    continue
                } else if text[index...].hasPrefix("[[/b]]") {
                    flushBuffer()
                    fmtBold = false
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[i]]") {
                    flushBuffer()
                    fmtItalic = true
                    index = text.index(index, offsetBy: 5)
                    continue
                } else if text[index...].hasPrefix("[[/i]]") {
                    flushBuffer()
                    fmtItalic = false
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[u]]") {
                    flushBuffer()
                    fmtUnderline = true
                    index = text.index(index, offsetBy: 5)
                    continue
                } else if text[index...].hasPrefix("[[/u]]") {
                    flushBuffer()
                    fmtUnderline = false
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[s]]") {
                    flushBuffer()
                    fmtStrikethrough = true
                    index = text.index(index, offsetBy: 5)
                    continue
                } else if text[index...].hasPrefix("[[/s]]") {
                    flushBuffer()
                    fmtStrikethrough = false
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[code]]") {
                    // Legacy inline code block — migrate to a plaintext code block attachment
                    flushBuffer()
                    let remaining = text[index...]
                    let prefixLen = "[[code]]".count
                    let contentStart = text.index(index, offsetBy: prefixLen)
                    if let closingRange = remaining.range(of: "[[/code]]") {
                        let rawCode = String(remaining[remaining.index(remaining.startIndex, offsetBy: prefixLen)..<closingRange.lowerBound])
                        let legacyData = CodeBlockData(language: "plaintext", code: rawCode)
                        let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                        if result.length > 0,
                           let lastScalar = result.string.unicodeScalars.last,
                           !CharacterSet.newlines.contains(lastScalar) {
                            result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                        }
                        let attachment = makeCodeBlockAttachment(codeBlockData: legacyData)
                        result.append(attachment)
                        let afterClosing = closingRange.upperBound
                        if afterClosing < text.endIndex {
                            if !text[afterClosing].isNewline {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                        } else {
                            result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                        }
                        index = closingRange.upperBound
                        lastWasWebClip = false
                        continue
                    }
                    // Malformed — skip the tag
                    index = contentStart
                    continue
                } else if text[index...].hasPrefix("[[/code]]") {
                    // Orphaned close tag from legacy format — skip
                    index = text.index(index, offsetBy: 9)
                    continue
                } else if text[index...].hasPrefix("[[arrow]]") {
                    flushBuffer()
                    result.append(makeArrowAttachment(merging: attributesMatchingBufferedPlainText()))
                    index = text.index(index, offsetBy: "[[arrow]]".count)
                    lastWasWebClip = false
                    continue
                } else if text[index...].hasPrefix("[[ol|") {
                    flushBuffer()
                    // Parse [[ol|N]] — extract the number
                    let prefixLen = "[[ol|".count
                    let afterPrefix = text.index(index, offsetBy: prefixLen)
                    if let closeBracket = text[afterPrefix...].range(of: "]]") {
                        let numStr = String(text[afterPrefix..<closeBracket.lowerBound])
                        let num = Int(numStr) ?? 1
                        let prefix = "\(num). "
                        // Pin list prefix to body + hang-indent (do not inherit bold/heading from fmt* state).
                        var attrs = Self.baseTypingAttributes(for: currentColorScheme)
                        attrs[.orderedListNumber] = num
                        attrs[.paragraphStyle] = Self.orderedListParagraphStyle()
                        attrs[.font] = FontManager.bodyNS()
                        attrs[.foregroundColor] = NSColor.labelColor
                        result.append(NSAttributedString(string: prefix, attributes: attrs))
                        index = closeBracket.upperBound
                        lastWasWebClip = false
                        continue
                    }
                } else if text[index...].hasPrefix("[[quote]]") {
                    flushBuffer()
                    fmtBlockQuote = true
                    index = text.index(index, offsetBy: 9)
                    continue
                } else if text[index...].hasPrefix("[[/quote]]") {
                    flushBuffer()
                    fmtBlockQuote = false
                    index = text.index(index, offsetBy: 10)
                    continue
                } else if text[index...].hasPrefix("[[hl|") {
                    flushBuffer()
                    let prefixLen = "[[hl|".count
                    let afterPrefix = text.index(index, offsetBy: prefixLen)
                    if let closeBracket = text[afterPrefix...].range(of: "]]") {
                        let tagContent = String(text[afterPrefix..<closeBracket.lowerBound])
                        if let pipeIdx = tagContent.firstIndex(of: "|") {
                            fmtHighlightHex = String(tagContent[tagContent.startIndex..<pipeIdx])
                            let afterPipe = tagContent.index(after: pipeIdx)
                            fmtHighlightVariant = Int(tagContent[afterPipe...])
                        } else {
                            fmtHighlightHex = tagContent
                            fmtHighlightVariant = nil
                        }
                        index = closeBracket.upperBound
                        continue
                    }
                } else if text[index...].hasPrefix("[[/hl]]") {
                    flushBuffer()
                    fmtHighlightHex = nil; fmtHighlightVariant = nil
                    index = text.index(index, offsetBy: 7)
                    continue
                } else if text[index...].hasPrefix("[[h1]]") {
                    flushBuffer()
                    fmtHeading = .h1
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[/h1]]") {
                    flushBuffer()
                    fmtHeading = .none
                    index = text.index(index, offsetBy: 7)
                    continue
                } else if text[index...].hasPrefix("[[h2]]") {
                    flushBuffer()
                    fmtHeading = .h2
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[/h2]]") {
                    flushBuffer()
                    fmtHeading = .none
                    index = text.index(index, offsetBy: 7)
                    continue
                } else if text[index...].hasPrefix("[[h3]]") {
                    flushBuffer()
                    fmtHeading = .h3
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[/h3]]") {
                    flushBuffer()
                    fmtHeading = .none
                    index = text.index(index, offsetBy: 7)
                    continue
                } else if text[index...].hasPrefix("[[align:center]]") {
                    flushBuffer()
                    fmtAlignment = .center
                    index = text.index(index, offsetBy: 16)
                    continue
                } else if text[index...].hasPrefix("[[align:right]]") {
                    flushBuffer()
                    fmtAlignment = .right
                    index = text.index(index, offsetBy: 15)
                    continue
                } else if text[index...].hasPrefix("[[align:justify]]") {
                    flushBuffer()
                    fmtAlignment = .justified
                    index = text.index(index, offsetBy: 17)
                    continue
                } else if text[index...].hasPrefix("[[/align]]") {
                    flushBuffer()
                    fmtAlignment = .left
                    index = text.index(index, offsetBy: 10)
                    continue
                } else if text[index...].hasPrefix("[[color|") {
                    flushBuffer()
                    let prefixLen = "[[color|".count
                    let afterPrefix = text.index(index, offsetBy: prefixLen)
                    // Accept both 6-char (RGB) and 8-char (RGBA) hex values
                    let remaining = text.distance(from: afterPrefix, to: text.endIndex)
                    var parsedHex: String?
                    var hexEnd: String.Index?
                    if remaining >= 10, // 8 hex + ]]
                       text[text.index(afterPrefix, offsetBy: 8)...].hasPrefix("]]") {
                        hexEnd = text.index(afterPrefix, offsetBy: 8)
                        parsedHex = String(text[afterPrefix..<hexEnd!])
                    } else if remaining >= 8, // 6 hex + ]]
                              text[text.index(afterPrefix, offsetBy: 6)...].hasPrefix("]]") {
                        hexEnd = text.index(afterPrefix, offsetBy: 6)
                        parsedHex = String(text[afterPrefix..<hexEnd!])
                    }
                    if let hex = parsedHex, let hEnd = hexEnd {
                        let contentStart = text.index(hEnd, offsetBy: 2)
                        if let closingRange = text[contentStart...].range(of: "[[/color]]") {
                            let coloredText = String(text[contentStart..<closingRange.lowerBound])
                            var attrs = Self.formattingAttributes(
                                base: currentColorScheme,
                                heading: fmtHeading,
                                bold: fmtBold, italic: fmtItalic,
                                underline: fmtUnderline, strikethrough: fmtStrikethrough,
                                alignment: fmtAlignment)
                            attrs[.foregroundColor] = TextFormattingManager.nsColorFromHex(hex)
                            attrs[TextFormattingManager.customTextColorKey] = true
                            result.append(NSAttributedString(string: coloredText, attributes: attrs))
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                    // Malformed -- fall through to single-char handler
                }

                // Accumulate plain text into buffer instead of one-char-at-a-time appends.
                let char = text[index]

                // Convert newline to space if between webclips
                if char == "\n" && lastWasWebClip {
                    // Check if next non-whitespace char is a webclip
                    var nextIndex = text.index(after: index)
                    while nextIndex < text.endIndex && text[nextIndex].isWhitespace && text[nextIndex] != "\n" {
                        nextIndex = text.index(after: nextIndex)
                    }
                    if nextIndex < text.endIndex && text[nextIndex...].hasPrefix(Self.webClipMarkupPrefix) {
                        textBuffer.append(" ")  // Convert newline to space between webclips
                    } else {
                        textBuffer.append(char)
                    }
                } else {
                    textBuffer.append(char)
                }

                index = text.index(after: index)
                lastWasWebClip = false
            }

            flushBuffer()
            return result
        }

        // MARK: - Helpers

}
