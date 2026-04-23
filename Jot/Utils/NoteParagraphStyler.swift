//
//  NoteParagraphStyler.swift
//  Jot
//
//  Extracted from TodoEditorRepresentable.swift — pure attribute-math for paragraph-level
//  styling. The two entry points are `styleTodoParagraphs(in:editedRange:)` (called on
//  every keystroke) and `fixInconsistentFonts(in:scopeRange:expectedAttributes:)` (called
//  after Writing Tools / external rich-text paste), both of which mutate an NSTextStorage
//  in place.
//
//  The Coordinator keeps thin facade methods (`styleTodoParagraphs()`, `fixInconsistentFonts(in:)`)
//  that forward to this namespace — existing call sites in the editor continue to work
//  unchanged. The payoff of the split is testability: paragraph-style invariants (blockquote
//  `tailIndent = -4`, heading-font guard, numbered-list hang-indent, arrow paragraph detection)
//  are now exercisable without spinning up a full Coordinator + NSTextView harness.
//
//  Invariants preserved:
//    - Heading paragraphs: `paragraphSpacingBefore = 8`, `paragraphSpacing = 12`, alignment preserved.
//    - Blockquote: `headIndent = 20`, `tailIndent = -4`, `lineBreakMode = .byWordWrapping`.
//    - Numbered list: `headIndent = 22`, `firstLineHeadIndent = 0`.
//    - Heading fonts are not downgraded by `fixInconsistentFonts` (Writing Tools guard).
//    - Inline-code (`.inlineCode == true`) is not rewritten to the body font.
//    - Attachment characters (U+FFFC) are not rewritten — preserves custom keys like
//      `.notelinkID` that would otherwise be silently stripped.
//

import AppKit

/// Namespace for paragraph-level attribute styling. All methods are pure — they take a
/// mutable `NSTextStorage` + context params and apply styling without reading any
/// Coordinator or TextView instance state. Typography constants / paragraph-style
/// factories still live on `TodoEditorRepresentable.Coordinator`; this namespace reaches
/// them by full-type path.
enum NoteParagraphStyler {

    // MARK: - Heading level detection

    /// Maps a font's point size to its `TextFormattingManager.HeadingLevel`, if any.
    /// Used by `fixInconsistentFonts` (to skip heading runs) and by `styleTodoParagraphs`
    /// (to detect heading paragraphs). Also used by the Coordinator's `serialize()` path
    /// to emit heading tags.
    static func headingLevel(for font: NSFont) -> TextFormattingManager.HeadingLevel? {
        switch font.pointSize {
        case TextFormattingManager.HeadingLevel.h1.fontSize: return .h1
        case TextFormattingManager.HeadingLevel.h2.fontSize: return .h2
        case TextFormattingManager.HeadingLevel.h3.fontSize: return .h3
        default: return nil
        }
    }

    // MARK: - Font consistency (post Writing Tools / external rich text)

    /// Fixes text that has inconsistent font formatting (e.g., after Writing Tools or
    /// pasting external rich text). When `scopeRange` is provided, only the affected
    /// paragraphs are scanned. Pass `nil` for full-document passes.
    ///
    /// `expectedAttributes` is typically `Coordinator.baseTypingAttributes(for:)` — the
    /// caller supplies it so this function stays free of Coordinator state. The caller is
    /// responsible for setting `isUpdating = true` around this call to suppress
    /// `textDidChange` callbacks.
    ///
    /// Skips:
    ///   - Attachment characters (U+FFFC) — `setAttributes` would strip custom keys.
    ///   - Inline-code runs (`.inlineCode == true`) — those intentionally use monospace.
    ///   - Heading-font runs — protects heading typography from Writing Tools downgrades.
    ///   - Runs with `customFontFamilyKey` — user explicitly chose that family.
    ///   - Runs with `customTextColorKey`, `.blockQuote`, `.todoChecked` — keep their color.
    static func fixInconsistentFonts(
        in textStorage: NSTextStorage,
        scopeRange: NSRange?,
        expectedAttributes: [NSAttributedString.Key: Any]
    ) {
        guard let expectedFont = expectedAttributes[.font] as? NSFont,
              let expectedColor = expectedAttributes[.foregroundColor] as? NSColor
        else { return }

        // Determine working range: scoped to affected paragraphs or full document
        let workingRange: NSRange
        if let scope = scopeRange, scope.location != NSNotFound, scope.location < textStorage.length {
            let nsString = textStorage.string as NSString
            let start = nsString.paragraphRange(for: NSRange(location: scope.location, length: 0)).location
            let endLoc = min(NSMaxRange(scope), textStorage.length)
            let endPara = nsString.paragraphRange(for: NSRange(location: max(endLoc, start), length: 0))
            workingRange = NSRange(location: start, length: NSMaxRange(endPara) - start)
        } else {
            workingRange = NSRange(location: 0, length: textStorage.length)
        }

        // Collect ranges that need fixing, then batch-apply inside beginEditing/endEditing
        var fixups: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []

        textStorage.enumerateAttributes(
            in: workingRange
        ) { attributes, range, _ in
            // Attachment characters (U+FFFC) render through their NSTextAttachmentCell,
            // not through text attributes. Rewriting their attributes with setAttributes
            // can silently strip critical custom keys (.notelinkID, .notelinkTitle, etc.)
            // causing notelinks and other attachments to vanish after serialization.
            if attributes[.attachment] != nil { return }
            // Inline code intentionally uses monospaced SF; do not rewrite it to the body font.
            if attributes[.inlineCode] as? Bool == true { return }

            var needsFixing = false
            var fixedAttributes: [NSAttributedString.Key: Any] = attributes

            // Check font: correct only when the FAMILY is wrong or size is wrong.
            // Checking family (not name) preserves intentional bold/italic variants
            // in the correct family, while still catching Writing Tools injecting
            // a completely different typeface (e.g. Helvetica into body text).
            if let currentFont = attributes[.font] as? NSFont {
                let isHeading = headingLevel(for: currentFont) != nil
                let hasCustomFontFamily = attributes[TextFormattingManager.customFontFamilyKey] as? Bool == true
                if !isHeading && !hasCustomFontFamily {
                    let currentFamily = currentFont.familyName ?? currentFont.fontName
                    let expectedFamily = expectedFont.familyName ?? expectedFont.fontName
                    if currentFamily != expectedFamily
                        || currentFont.pointSize != expectedFont.pointSize
                    {
                        // Replace font family but preserve bold/italic traits
                        let traits = NSFontManager.shared.traits(of: currentFont)
                        var replacement = expectedFont
                        if traits.contains(.boldFontMask) {
                            replacement = NSFontManager.shared.convert(
                                replacement, toHaveTrait: .boldFontMask)
                        }
                        if traits.contains(.italicFontMask) {
                            replacement = NSFontManager.shared.convert(
                                replacement, toHaveTrait: .italicFontMask)
                        }
                        fixedAttributes[.font] = replacement
                        needsFixing = true
                    }
                }
            } else {
                fixedAttributes[.font] = expectedFont
                needsFixing = true
            }

            // Check text color — skip ranges with a user-intentional custom color, block quote, or checked todo
            let hasCustomColor = attributes[TextFormattingManager.customTextColorKey] as? Bool == true
            let isBlockQuote = attributes[.blockQuote] as? Bool == true
            let isTodoChecked = attributes[.todoChecked] as? Bool == true
            if !hasCustomColor && !isBlockQuote && !isTodoChecked {
                if let currentColor = attributes[.foregroundColor] as? NSColor {
                    if !currentColor.isEqual(expectedColor) {
                        fixedAttributes[.foregroundColor] = expectedColor
                        needsFixing = true
                    }
                } else {
                    fixedAttributes[.foregroundColor] = expectedColor
                    needsFixing = true
                }
            }

            if needsFixing {
                fixups.append((range: range, attrs: fixedAttributes))
            }
        }

        // Batch all mutations in a single editing bracket so the layout manager
        // receives one processEditing notification, not N individual ones
        if !fixups.isEmpty {
            textStorage.beginEditing()
            for fixup in fixups {
                textStorage.setAttributes(fixup.attrs, range: fixup.range)
            }
            textStorage.endEditing()
        }
    }

    // MARK: - Paragraph styling

    /// Styles paragraphs for todo checkboxes, lists, block quotes, images, tables, headings,
    /// etc. When `editedRange` is provided, only the affected paragraph(s) are re-styled
    /// (O(1) for single-character edits). Pass `nil` for full-document passes.
    static func styleTodoParagraphs(
        in textStorage: NSTextStorage,
        editedRange: NSRange?
    ) {
        typealias C = TodoEditorRepresentable.Coordinator

        let fullRange = NSRange(location: 0, length: textStorage.length)
        // Bridge cast once — reused for working-range expansion and the paragraph loop below.
        // Safe to hoist: textStorage.string is only modified via addAttribute/removeAttribute
        // inside this function, neither of which changes the string content itself.
        let nsString = textStorage.string as NSString
        // Determine the working range: either the edited paragraph(s) or the full document
        let workingRange: NSRange
        if let edited = editedRange, edited.location != NSNotFound, edited.location < textStorage.length {
            // Expand to paragraph boundaries so we always style complete paragraphs
            let start = nsString.paragraphRange(for: NSRange(location: edited.location, length: 0)).location
            let endLoc = min(NSMaxRange(edited), textStorage.length)
            let endPara = nsString.paragraphRange(for: NSRange(location: max(endLoc, start), length: 0))
            workingRange = NSRange(location: start, length: NSMaxRange(endPara) - start)
        } else {
            workingRange = fullRange
        }
        textStorage.beginEditing()
        // Do NOT blanket-remove .paragraphStyle — heading and alignment styles live there.
        textStorage.removeAttribute(.baselineOffset, range: workingRange)

        var paragraphRange = NSRange(location: workingRange.location, length: 0)
        while paragraphRange.location < NSMaxRange(workingRange) {
            let substringRange = nsString.paragraphRange(
                for: NSRange(location: paragraphRange.location, length: 0))
            if substringRange.length == 0 { break }
            defer { paragraphRange.location = NSMaxRange(substringRange) }

            // Strip highlight from paragraph-terminating newlines — prevents full-width
            // background extension and highlight bleeding when Enter is pressed
            let lastCharIndex = NSMaxRange(substringRange) - 1
            if lastCharIndex >= 0,
               lastCharIndex < textStorage.length,
               nsString.character(at: lastCharIndex) == 0x0A,
               textStorage.attribute(.highlightColor, at: lastCharIndex, effectiveRange: nil) != nil {
                let nlRange = NSRange(location: lastCharIndex, length: 1)
                textStorage.removeAttribute(.backgroundColor, range: nlRange)
                textStorage.removeAttribute(.highlightColor, range: nlRange)
                textStorage.removeAttribute(.highlightVariant, range: nlRange)
            }

            var isTodoParagraph = false
            var isWebClipParagraph = false
            var isImageParagraph = false
            var isTableParagraph = false

            textStorage.enumerateAttribute(
                .attachment,
                in: NSRange(
                    location: substringRange.location, length: min(1, substringRange.length)
                ), options: []
            ) { value, _, stop in
                if let attachment = value as? NSTextAttachment {
                    // Check if it's a todo checkbox
                    if let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell {
                        isTodoParagraph = true
                        cell.invalidateAppearance()
                        stop.pointee = true
                    }
                    // Check if it's a web clip attachment (inline pill style)
                    else if textStorage.attribute(
                        .webClipTitle, at: substringRange.location, effectiveRange: nil)
                        != nil
                    {
                        isWebClipParagraph = true
                        stop.pointee = true
                    }
                    // Table attachments need extra top spacing for grab handles
                    else if attachment is NoteTableAttachment {
                        isTableParagraph = true
                        stop.pointee = true
                    }
                    // Other block-level attachments (image, callout, code block, link card, file preview)
                    else if attachment is NoteImageAttachment
                            || attachment is NoteMapAttachment
                            || attachment is NoteCalloutAttachment
                            || attachment is NoteCodeBlockAttachment
                            || attachment is NoteTabsAttachment
                            || attachment is NoteCardSectionAttachment
                            || attachment is NoteLinkCardAttachment
                            || ((attachment as? NoteFileAttachment).map { $0.viewMode != .tag } ?? false) {
                        isImageParagraph = true
                        stop.pointee = true
                    }
                }
            }

            // Detect numbered list paragraphs
            var isNumberedListParagraph = false
            if !isTodoParagraph && !isWebClipParagraph && !isImageParagraph && !isTableParagraph {
                if substringRange.location < textStorage.length,
                   textStorage.attribute(.orderedListNumber, at: substringRange.location, effectiveRange: nil) != nil {
                    isNumberedListParagraph = true
                }
            }

            // Detect block quote paragraphs
            var isBlockQuoteParagraph = false
            if !isTodoParagraph && !isWebClipParagraph && !isImageParagraph && !isTableParagraph && !isNumberedListParagraph {
                if substringRange.location < textStorage.length,
                   textStorage.attribute(.blockQuote, at: substringRange.location, effectiveRange: nil) as? Bool == true {
                    isBlockQuoteParagraph = true
                }
            }

            // Arrow pseudo-bullets (imported `->` / `=>` or Unicode arrows) — hang-indent like ordered lists.
            var isArrowParagraph = false
            if !isTodoParagraph && !isWebClipParagraph && !isImageParagraph && !isTableParagraph
                && !isNumberedListParagraph && !isBlockQuoteParagraph,
               substringRange.location < textStorage.length, substringRange.length > 0
            {
                let peekLen = min(12, substringRange.length)
                let peek = nsString.substring(
                    with: NSRange(location: substringRange.location, length: peekLen))
                if peek.hasPrefix("\u{2192} ") || peek.hasPrefix("\u{21D2} ") {
                    isArrowParagraph = true
                } else if textStorage.attribute(
                    .attachment, at: substringRange.location, effectiveRange: nil) is NoteArrowAttachment {
                    isArrowParagraph = true
                }
            }

            // Detect heading paragraphs — apply heading paragraph spacing on the full range
            // (including the trailing newline) so AppKit does not resolve the paragraph from
            // the newline's base style and drop heading spacing after import/round-trip.
            var headingLevelForParagraph: TextFormattingManager.HeadingLevel?
            if !isTodoParagraph && !isWebClipParagraph && !isNumberedListParagraph && !isBlockQuoteParagraph
                && !isArrowParagraph
            {
                // Heading font is carried from the paragraph's first character by invariant
                // (styleTodoParagraphs itself is what preserves this). A single-point peek
                // saves N `enumerateAttribute` visits per paragraph on every keystroke.
                if let f = textStorage.attribute(.font, at: substringRange.location, effectiveRange: nil) as? NSFont,
                   let level = headingLevel(for: f) {
                    headingLevelForParagraph = level
                }
            }
            let isHeadingParagraph = headingLevelForParagraph != nil

            // Apply appropriate paragraph style based on content type
            if isTableParagraph {
                // Tables need extra top spacing so column grab handles don't overlap content above
                let tableStyle = NSMutableParagraphStyle()
                tableStyle.alignment = .left
                tableStyle.paragraphSpacing = 8
                tableStyle.paragraphSpacingBefore = 30
                textStorage.addAttribute(.paragraphStyle, value: tableStyle, range: substringRange)
            } else if isImageParagraph {
                // Preserve block image paragraph style — do not override
                let imgStyle = NSMutableParagraphStyle()
                imgStyle.alignment = .left
                imgStyle.paragraphSpacing = 8
                imgStyle.paragraphSpacingBefore = 8
                textStorage.addAttribute(.paragraphStyle, value: imgStyle, range: substringRange)
            } else if isWebClipParagraph {
                textStorage.addAttribute(.paragraphStyle, value: C.webClipParagraphStyle(), range: substringRange)
            } else if isTodoParagraph {
                textStorage.addAttribute(.paragraphStyle, value: C.todoParagraphStyle(), range: substringRange)
            } else if isNumberedListParagraph {
                textStorage.addAttribute(.paragraphStyle, value: C.orderedListParagraphStyle(), range: substringRange)
            } else if isBlockQuoteParagraph {
                // Actively enforce block quote paragraph style on every text change,
                // just like every other block type. Preserves custom alignment if set.
                guard let quoteStyle = C.blockQuoteParagraphStyle().mutableCopy() as? NSMutableParagraphStyle else { return }
                textStorage.enumerateAttribute(.paragraphStyle, in: substringRange, options: []) { val, _, stop in
                    if let ps = val as? NSParagraphStyle, ps.alignment != .left {
                        quoteStyle.alignment = ps.alignment
                        stop.pointee = true
                    }
                }
                textStorage.addAttribute(.paragraphStyle, value: quoteStyle, range: substringRange)
            } else if isArrowParagraph {
                textStorage.addAttribute(.paragraphStyle, value: C.orderedListParagraphStyle(), range: substringRange)
            } else if isHeadingParagraph {
                // Match TextFormattingManager.applyHeading spacing for all heading levels.
                let headingStyle = NSMutableParagraphStyle()
                headingStyle.paragraphSpacingBefore = 8
                headingStyle.paragraphSpacing = 12
                if headingLevelForParagraph == .h3 {
                    headingStyle.tailIndent = -24
                }
                textStorage.enumerateAttribute(.paragraphStyle, in: substringRange, options: []) { val, _, stop in
                    if let ps = val as? NSParagraphStyle {
                        if ps.alignment != .left {
                            headingStyle.alignment = ps.alignment
                        }
                        if ps.tailIndent < 0 {
                            headingStyle.tailIndent = ps.tailIndent
                        }
                        stop.pointee = true
                    }
                }
                textStorage.addAttribute(.paragraphStyle, value: headingStyle, range: substringRange)
            } else {
                // Body paragraph: apply base style but preserve any custom alignment
                guard let mutableStyle = C.baseParagraphStyle().mutableCopy() as? NSMutableParagraphStyle else { return }
                var existingAlignment: NSTextAlignment = .left
                textStorage.enumerateAttribute(.paragraphStyle, in: substringRange, options: []) { val, _, stop in
                    if let ps = val as? NSParagraphStyle, ps.alignment != .left {
                        existingAlignment = ps.alignment
                        stop.pointee = true
                    }
                }
                if existingAlignment != .left { mutableStyle.alignment = existingAlignment }
                textStorage.addAttribute(.paragraphStyle, value: mutableStyle, range: substringRange)
            }

            // Don't adjust baseline for todo, web clip, heading, image, table, numbered list, block quote, or arrow paragraphs
            if !isTodoParagraph && !isWebClipParagraph && !isHeadingParagraph && !isImageParagraph && !isTableParagraph && !isNumberedListParagraph && !isBlockQuoteParagraph && !isArrowParagraph {
                textStorage.addAttribute(
                    .baselineOffset, value: C.baseBaselineOffset, range: substringRange)
            }

            if isTodoParagraph {
                var checkedCell: TodoCheckboxAttachmentCell?
                textStorage.enumerateAttribute(.attachment, in: substringRange, options: [])
                { value, attachmentRange, _ in
                    guard let attachment = value as? NSTextAttachment,
                        let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell
                    else { return }
                    attachment.bounds = CGRect(
                        x: 0, y: C.checkboxAttachmentYOffset,
                        width: C.checkboxAttachmentWidth, height: C.checkboxIconSize)
                    textStorage.addAttribute(
                        .baselineOffset, value: C.checkboxBaselineOffset,
                        range: attachmentRange)
                    cell.invalidateAppearance()
                    checkedCell = cell
                }

                // Enforce checked todo text styling on the text portion
                // Todo structure: [attachment][space][space][text...] — skip all 3 prefix chars
                if let cell = checkedCell {
                    let textStart = substringRange.location + 3
                    let textEnd = NSMaxRange(substringRange)
                    if textStart < textEnd {
                        let textRange = NSRange(location: textStart, length: textEnd - textStart)
                        if cell.isChecked {
                            textStorage.addAttribute(.todoChecked, value: true, range: textRange)
                            textStorage.addAttribute(.foregroundColor, value: checkedTodoTextColor, range: textRange)
                        } else {
                            textStorage.removeAttribute(.todoChecked, range: textRange)
                            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: textRange)
                        }
                    }
                }
            }
        }

        // Suppress spell check red underlines on attachment characters (U+FFFC).
        // Without this, the spell checker treats words adjacent to inline attachments
        // (checkboxes, images, webclips) as misspelled due to the invisible U+FFFC boundary.
        textStorage.enumerateAttribute(.attachment, in: workingRange, options: []) { value, range, _ in
            if value != nil {
                textStorage.addAttribute(.spellingState, value: 0, range: range)
            }
        }

        textStorage.endEditing()
    }
}
