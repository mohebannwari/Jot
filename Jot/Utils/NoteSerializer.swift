//
//  NoteSerializer.swift
//  Jot
//
//  Extracted from TodoEditorRepresentable.swift — serializes the editor's NSTextStorage
//  (inline formatting + all attachments + ordered-list prefixes + corrupted-block placeholders)
//  to the Jot tag markup format.
//
//  This file intentionally does NOT collapse into `RichTextSerializer.serializeAttributedString(_:)`
//  — that helper is the narrow inline-only API used by card sections, which have no attachments.
//  The editor's serialize is attachment-aware and must stay distinct. Both share the tag
//  grammar documented in `.claude/rules/workflow.md` (Rich Text Serialization Format).
//
//  Callers are expected to pass the full text storage; `serialize(_:)` returns the full
//  markup string. Inverse direction lives in the deserializer (Batch 4).
//

import AppKit

/// Namespace for the editor's attachment-aware text serialization. Takes an NSTextStorage,
/// produces a tag-markup string. Pure — reads no Coordinator/TextView state.
enum NoteSerializer {

    /// Serialize the editor's attributed text (inline formatting + attachments) to the
    /// Jot tag format. Called from `Coordinator.syncText` (debounced binding write),
    /// `Coordinator.applyInitialText` (for subsequent round-trip equality), and the
    /// debounced serialize pipeline.
    static func serialize(_ storage: NSTextStorage) -> String {
        typealias C = TodoEditorRepresentable.Coordinator

        let fullRange = NSRange(location: 0, length: storage.length)
        var output = ""
        // Pre-size the output buffer to reduce reallocations on large documents.
        output.reserveCapacity(storage.length * 2)
        // Bridge cast once outside the closure — each call to (storage.string as NSString)
        // inside enumerateAttributes would re-bridge on every attribute run.
        let storageNSString = storage.string as NSString
        storage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            // Corrupted block placeholders — re-emit original raw markup for lossless round-trip
            if let rawMarkup = attributes[.corruptedBlock] as? String {
                output.append(rawMarkup)
                return
            }
            if let attachment = attributes[.attachment] as? NSTextAttachment,
                let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell
            {
                output.append(cell.isChecked ? "[x]" : "[ ]")
            } else if let linkCard = attributes[.attachment] as? NoteLinkCardAttachment {
                var title = C.cleanedWebClipComponent(linkCard.title)
                let description = C.cleanedWebClipComponent(linkCard.descriptionText)
                if title.isEmpty {
                    title = C.cleanedWebClipComponent(linkCard.domain)
                }
                let urlString = linkCard.url.trimmingCharacters(in: .whitespacesAndNewlines)
                output.append("[[linkcard|\(title)|\(description)|\(urlString)]]")
            } else if let urlString = attributes[.plainLinkURL] as? String {
                let sanitizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                if let label = attributes[.plainLinkLabel] as? String,
                   !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   label.trimmingCharacters(in: .whitespacesAndNewlines) != sanitizedURL
                {
                    let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    output.append("[[link|\(sanitizedURL)|\(trimmedLabel)]]")
                } else {
                    output.append("[[link|\(sanitizedURL)]]")
                }
            } else if let attachment = attributes[.attachment] as? NSTextAttachment,
                !(attachment.attachmentCell is TodoCheckboxAttachmentCell),
                let urlString = C.linkURLString(from: attributes)
            {
                var title = C.cleanedWebClipComponent(attributes[.webClipTitle])
                let description = C.cleanedWebClipComponent(
                    attributes[.webClipDescription])
                let domain = C.cleanedWebClipComponent(attributes[.webClipDomain])
                if title.isEmpty {
                    title = domain
                }
                let sanitizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                output.append("[[webclip|\(title)|\(description)|\(sanitizedURL)]]")
            } else if let filePath = attributes[.fileLinkPath] as? String,
                      storageNSString.substring(with: range).contains("\u{FFFC}") {
                let displayName = (attributes[.fileLinkDisplayName] as? String) ?? URL(fileURLWithPath: filePath).lastPathComponent
                let bookmark = (attributes[.fileLinkBookmark] as? String) ?? ""
                let sanitizedPath = C.sanitizedWebClipComponent(filePath)
                let sanitizedName = C.sanitizedWebClipComponent(displayName)
                if bookmark.isEmpty {
                    output.append("[[filelink|\(sanitizedPath)|\(sanitizedName)]]")
                } else {
                    output.append("[[filelink|\(sanitizedPath)|\(sanitizedName)|\(bookmark)]]")
                }
            } else if let storedFilename = attributes[.fileStoredFilename] as? String,
                      storageNSString.substring(with: range).contains("\u{FFFC}") {
                let typeIdentifierRaw = (attributes[.fileTypeIdentifier] as? String) ?? "public.data"
                let originalNameRaw = (attributes[.fileOriginalFilename] as? String) ?? storedFilename
                let typeIdentifier = C.sanitizedWebClipComponent(typeIdentifierRaw)
                let originalName = C.sanitizedWebClipComponent(originalNameRaw)
                let viewModeRaw = (attributes[.fileViewMode] as? String) ?? FileViewMode.tag.rawValue
                let viewMode = FileViewMode(rawValue: viewModeRaw) ?? .tag
                if viewMode == .tag {
                    output.append("[[file|\(typeIdentifier)|\(storedFilename)|\(originalName)]]")
                } else {
                    output.append("[[file|\(typeIdentifier)|\(storedFilename)|\(originalName)|\(viewMode.rawValue)]]")
                }
            } else if let tableAttachment = attributes[.attachment] as? NoteTableAttachment {
                output.append(tableAttachment.tableData.serialize())
            } else if let mapAttachment = attributes[.attachment] as? NoteMapAttachment {
                output.append(mapAttachment.mapData.serialize())
            } else if let serializedMapData = attributes[.mapSerializedData] as? String {
                output.append(serializedMapData)
            } else if let calloutAttachment = attributes[.attachment] as? NoteCalloutAttachment {
                let ser = calloutAttachment.calloutData.serialize()
                output.append(ser)
            } else if let codeBlockAttachment = attributes[.attachment] as? NoteCodeBlockAttachment {
                output.append(codeBlockAttachment.codeBlockData.serialize())
            } else if let tabsAttachment = attributes[.attachment] as? NoteTabsAttachment {
                output.append(tabsAttachment.tabsData.serialize())
            } else if let cardSectionAttachment = attributes[.attachment] as? NoteCardSectionAttachment {
                output.append(cardSectionAttachment.cardSectionData.serialize())
            } else if attributes[.attachment] is NoteDividerAttachment {
                output.append("[[divider]]")
            } else if let notelinkAttachment = attributes[.attachment] as? NotelinkAttachment {
                output.append("[[notelink|\(notelinkAttachment.noteID)|\(notelinkAttachment.noteTitle)]]")
            } else if let nlID = attributes[.notelinkID] as? String,
                      let nlTitle = attributes[.notelinkTitle] as? String {
                // Notelink fallback — the NotelinkAttachment subclass may have been
                // degraded to a plain NSTextAttachment by AppKit copy/undo operations,
                // but the text attributes survive. Catch them before the generic handler.
                output.append("[[notelink|\(nlID)|\(nlTitle)]]")
            } else if let linkCard = attributes[.attachment] as? NoteLinkCardAttachment {
                // Link card fallback — same recovery pattern as webclip
                var title = C.cleanedWebClipComponent(linkCard.title)
                let description = C.cleanedWebClipComponent(linkCard.descriptionText)
                let domain = C.cleanedWebClipComponent(linkCard.domain)
                if title.isEmpty { title = domain }
                let url = linkCard.url.trimmingCharacters(in: .whitespacesAndNewlines)
                output.append("[[linkcard|\(title)|\(description)|\(url)]]")
            } else if attributes[.webClipTitle] != nil {
                // Webclip fallback — .link attribute may have been stripped by AppKit,
                // but webclip metadata attributes survive. Recover the webclip.
                var title = C.cleanedWebClipComponent(attributes[.webClipTitle])
                let description = C.cleanedWebClipComponent(attributes[.webClipDescription])
                let domain = C.cleanedWebClipComponent(attributes[.webClipDomain])
                if title.isEmpty { title = domain }
                let url = C.linkURLString(from: attributes)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (attributes[.webClipFullURL] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? domain
                output.append("[[webclip|\(title)|\(description)|\(url)]]")
            } else if attributes[.attachment] is NoteArrowAttachment {
                output.append("[[arrow]]")
            } else if let attachment = attributes[.attachment] as? NSTextAttachment,
                !(attachment.attachmentCell is TodoCheckboxAttachmentCell)
            {
                if let filename = attributes[.imageFilename] as? String {
                    // Always serialize width ratio to avoid insert/deserialize default mismatch
                    let ratio = attributes[.imageWidthRatio] as? CGFloat ?? 1.0
                    output.append("[[image|||\(filename)|||\(String(format: "%.4f", ratio))]]")
                } else if let noteAttachment = attachment as? NoteImageAttachment {
                    let ratio = noteAttachment.widthRatio
                    output.append("[[image|||\(noteAttachment.storedFilename)|||\(String(format: "%.4f", ratio))]]")
                } else if let fileWrapper = attachment.fileWrapper,
                        let filename = fileWrapper.preferredFilename ?? fileWrapper.filename,
                        !filename.isEmpty,
                        filename.hasSuffix(".jpg")
                {
                    output.append("[[image|||\(filename)]]")
                } else if let image = attachment.image ?? attachment.fileWrapper?.regularFileContents.flatMap({ NSImage(data: $0) }) {
                    // Attachment has image data but no stored filename (e.g. clipboard paste
                    // that bypassed the image save pipeline). Save synchronously to prevent
                    // data loss on the next serialize/deserialize round-trip.
                    let filename = UUID().uuidString + ".jpg"
                    if let storageURL = ImageStorageManager.shared.getStorageDirectoryForSync(),
                       let tiffData = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                        let destURL = storageURL.appendingPathComponent(filename)
                        try? jpegData.write(to: destURL)
                        output.append("[[image|||\(filename)]]")
                    }
                    // If save fails, omit the attachment rather than emitting U+FFFC garbage
                } else {
                    // Unknown attachment type — skip rather than emitting raw U+FFFC
                    // which corrupts the serialized text
                }
            } else {
                // Ordered list prefix: the "N. " characters carry orderedListNumber
                // Emit [[ol|N]] tag and skip the prefix text — it's encoded in the tag
                if let olNum = attributes[.orderedListNumber] as? Int {
                    output.append("[[ol|\(olNum)]]")
                    return  // Skip the prefix text — it's reconstructed during deserialization
                }

                let rangeText = storageNSString.substring(with: range)

                // Determine inline formatting for this run
                let font = attributes[.font] as? NSFont
                let isBlockQuote = attributes[.blockQuote] as? Bool == true
                let highlightHex = attributes[.highlightColor] as? String
                let highlightVariant = attributes[.highlightVariant] as? Int
                let heading = font.flatMap { NoteParagraphStyler.headingLevel(for: $0) }

                var runBold = false
                var runItalic = false
                if heading == nil, let f = font {
                    let traits = NSFontManager.shared.traits(of: f)
                    runBold = traits.contains(.boldFontMask)
                    runItalic = traits.contains(.italicFontMask)
                }
                let hasUnderline = (attributes[.underlineStyle] as? Int ?? 0) != 0
                let hasStrikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                let alignment: NSTextAlignment
                if let ps = attributes[.paragraphStyle] as? NSParagraphStyle {
                    alignment = ps.alignment
                } else {
                    alignment = .left
                }

                // Build open/close tag wrappers (outer → inner)
                var openTags = ""
                var closeTags = ""

                // Block quote (outermost)
                if isBlockQuote { openTags += "[[quote]]"; closeTags = "[[/quote]]" + closeTags }

                // Alignment — emit only for non-left
                if alignment != .left {
                    switch alignment {
                    case .center:
                        openTags += "[[align:center]]"; closeTags = "[[/align]]" + closeTags
                    case .right:
                        openTags += "[[align:right]]"; closeTags = "[[/align]]" + closeTags
                    case .justified:
                        openTags += "[[align:justify]]"; closeTags = "[[/align]]" + closeTags
                    default:
                        break
                    }
                }

                // Heading or bold/italic
                if let h = heading {
                    switch h {
                    case .h1: openTags += "[[h1]]"; closeTags = "[[/h1]]" + closeTags
                    case .h2: openTags += "[[h2]]"; closeTags = "[[/h2]]" + closeTags
                    case .h3: openTags += "[[h3]]"; closeTags = "[[/h3]]" + closeTags
                    case .none: break
                    }
                } else {
                    if runBold   { openTags += "[[b]]"; closeTags = "[[/b]]" + closeTags }
                    if runItalic { openTags += "[[i]]"; closeTags = "[[/i]]" + closeTags }
                }

                if attributes[.inlineCode] as? Bool == true {
                    openTags += "[[ic]]"
                    closeTags = "[[/ic]]" + closeTags
                }

                // Underline / strikethrough
                if hasUnderline     { openTags += "[[u]]"; closeTags = "[[/u]]" + closeTags }
                if hasStrikethrough { openTags += "[[s]]"; closeTags = "[[/s]]" + closeTags }

                // Color + highlight (innermost)
                if attributes[TextFormattingManager.customTextColorKey] as? Bool == true,
                   let nsColor = attributes[.foregroundColor] as? NSColor
                {
                    let hex = C.nsColorToHex(nsColor)
                    openTags += "[[color|\(hex)]]"; closeTags = "[[/color]]" + closeTags
                }
                if let hlHex = highlightHex {
                    let variantSuffix = highlightVariant.map { "|\($0)" } ?? ""
                    openTags += "[[hl|\(hlHex)\(variantSuffix)]]"; closeTags = "[[/hl]]" + closeTags
                }

                output.append(openTags)
                output.append(rangeText)
                output.append(closeTags)

            }
        }
        return output
    }
}
