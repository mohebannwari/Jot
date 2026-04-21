//
//  RichTextSerializer.swift
//  Jot
//
//  Shared inline rich text serialization/deserialization.
//  Used by both the main editor and card section text views.
//

#if os(macOS)
import AppKit

/// Serializes and deserializes NSAttributedString to/from the Jot tag format
/// for inline formatting only (no attachments).
enum RichTextSerializer {

    // MARK: - Font helpers

    private static var _cachedTextFont: NSFont?
    static var textFont: NSFont {
        if let cached = _cachedTextFont { return cached }
        let font = FontManager.bodyNS(size: ThemeManager.currentBodyFontSize(), weight: .regular)
        _cachedTextFont = font
        return font
    }

    static var baseLineHeight: CGFloat {
        ThemeManager.currentBodyFontSize() * 1.5
    }

    // MARK: - Paragraph styles

    private static var _cachedBaseParagraphStyle: NSParagraphStyle?
    static func baseParagraphStyle() -> NSParagraphStyle {
        if let cached = _cachedBaseParagraphStyle { return cached }
        let spacing = ThemeManager.currentLineSpacing()
        let scaledHeight = baseLineHeight * spacing.multiplier / 1.2
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = spacing.multiplier
        style.minimumLineHeight = scaledHeight
        style.maximumLineHeight = scaledHeight + 4
        style.paragraphSpacing = 8
        _cachedBaseParagraphStyle = style
        return style
    }

    /// Invalidate caches when font size, line spacing, or body font style changes.
    /// Call from any settings-change handler that affects typography.
    static func invalidateCaches() {
        _cachedTextFont = nil
        _cachedBaseParagraphStyle = nil
        _cachedBlockQuoteParagraphStyle = nil
    }

    private static var _cachedBlockQuoteParagraphStyle: NSParagraphStyle?
    static func blockQuoteParagraphStyle() -> NSParagraphStyle {
        if let cached = _cachedBlockQuoteParagraphStyle { return cached }
        let spacing = ThemeManager.currentLineSpacing()
        let scaledHeight = baseLineHeight * spacing.multiplier / 1.2
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = spacing.multiplier
        style.minimumLineHeight = scaledHeight
        style.maximumLineHeight = scaledHeight + 4
        style.paragraphSpacing = 8
        style.firstLineHeadIndent = 20
        style.headIndent = 20
        // Must mirror TextFormattingManager.toggleBlockQuote so reload geometry matches live toggle.
        style.tailIndent = -4
        style.lineBreakMode = .byWordWrapping
        _cachedBlockQuoteParagraphStyle = style
        return style
    }

    /// Shared monospace font for `[[ic]]…[[/ic]]` inline-code runs.
    /// Used from both the serializer's `flushBuffer` and the editor's deserialize paths so the
    /// three call sites stay in lockstep on font size, weight, and bold/italic trait handling.
    static func inlineCodeFont(bold: Bool, italic: Bool) -> NSFont {
        let baseSize = ThemeManager.currentBodyFontSize() * 0.92
        var codeFont = NSFont.monospacedSystemFont(ofSize: baseSize, weight: .regular)
        if bold { codeFont = NSFontManager.shared.convert(codeFont, toHaveTrait: .boldFontMask) }
        if italic { codeFont = NSFontManager.shared.convert(codeFont, toHaveTrait: .italicFontMask) }
        return codeFont
    }

    static func orderedListParagraphStyle() -> NSParagraphStyle {
        let spacing = ThemeManager.currentLineSpacing()
        let scaledHeight = baseLineHeight * spacing.multiplier / 1.2
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = spacing.multiplier
        style.minimumLineHeight = scaledHeight
        style.maximumLineHeight = scaledHeight + 4
        style.paragraphSpacing = 4
        style.firstLineHeadIndent = 0
        style.headIndent = 22
        return style
    }

    // MARK: - Typing attributes

    static func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: textFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: baseParagraphStyle(),
            .underlineStyle: 0,
        ]
    }

    // MARK: - Heading detection

    static func headingLevel(for font: NSFont) -> TextFormattingManager.HeadingLevel? {
        switch font.pointSize {
        case TextFormattingManager.HeadingLevel.h1.fontSize: return .h1
        case TextFormattingManager.HeadingLevel.h2.fontSize: return .h2
        case TextFormattingManager.HeadingLevel.h3.fontSize: return .h3
        default: return nil
        }
    }

    // MARK: - Color conversion

    static func nsColorToHex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? color
        return String(format: "%02x%02x%02x",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }

    // MARK: - Formatting attribute builder

    static func formattingAttributes(
        heading: TextFormattingManager.HeadingLevel,
        bold: Bool, italic: Bool,
        underline: Bool, strikethrough: Bool,
        alignment: NSTextAlignment
    ) -> [NSAttributedString.Key: Any] {
        var attrs = baseTypingAttributes()

        if heading != .none {
            let weight: FontManager.Weight = heading.fontWeight == .semibold ? .semibold : .regular
            attrs[.font] = FontManager.headingNS(size: heading.fontSize, weight: weight)
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.paragraphSpacingBefore = 8
            paraStyle.paragraphSpacing = 12
            if alignment != .left { paraStyle.alignment = alignment }
            attrs[.paragraphStyle] = paraStyle
        } else {
            var font = attrs[.font] as? NSFont ?? textFont
            if bold   { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            attrs[.font] = font

            if alignment != .left {
                let paraStyle = (attrs[.paragraphStyle] as? NSParagraphStyle)?
                    .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                paraStyle.alignment = alignment
                attrs[.paragraphStyle] = paraStyle
            }
        }

        attrs[.underlineStyle] = underline ? NSUnderlineStyle.single.rawValue : 0
        if strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            // SecondaryTextColor is the canonical 70%-label dimmer token; matches blockquote foreground.
            attrs[.foregroundColor] = NSColor(named: "SecondaryTextColor") ?? NSColor.secondaryLabelColor
        } else {
            attrs[.strikethroughStyle] = 0
        }

        return attrs
    }

    // MARK: - Serialize

    /// Serialize an NSAttributedString to the Jot tag format (inline formatting only).
    /// Skips attachment characters (U+FFFC).
    static func serializeAttributedString(_ attrString: NSAttributedString) -> String {
        let fullRange = NSRange(location: 0, length: attrString.length)
        guard fullRange.length > 0 else { return "" }
        var output = ""

        attrString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            // Skip attachment characters
            if attributes[.attachment] != nil { return }

            // Ordered list prefix
            if let olNum = attributes[.orderedListNumber] as? Int {
                output.append("[[ol|\(olNum)]]")
                return
            }

            let rangeText = (attrString.string as NSString).substring(with: range)

            // Skip empty strings
            guard !rangeText.isEmpty else { return }

            let font = attributes[.font] as? NSFont
            let isBlockQuote = attributes[.blockQuote] as? Bool == true
            let highlightHex = attributes[.highlightColor] as? String
            let highlightVariant = attributes[.highlightVariant] as? Int
            let heading = font.flatMap { headingLevel(for: $0) }

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

            var openTags = ""
            var closeTags = ""

            if isBlockQuote { openTags += "[[quote]]"; closeTags = "[[/quote]]" + closeTags }

            if alignment != .left {
                switch alignment {
                case .center:   openTags += "[[align:center]]"; closeTags = "[[/align]]" + closeTags
                case .right:    openTags += "[[align:right]]"; closeTags = "[[/align]]" + closeTags
                case .justified: openTags += "[[align:justify]]"; closeTags = "[[/align]]" + closeTags
                default: break
                }
            }

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

            if hasUnderline     { openTags += "[[u]]"; closeTags = "[[/u]]" + closeTags }
            if hasStrikethrough { openTags += "[[s]]"; closeTags = "[[/s]]" + closeTags }

            if attributes[TextFormattingManager.customTextColorKey] as? Bool == true,
               let nsColor = attributes[.foregroundColor] as? NSColor {
                let hex = nsColorToHex(nsColor)
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
        return output
    }

    // MARK: - Deserialize

    /// Deserialize a Jot tag-format string to an NSAttributedString (inline formatting only).
    /// Ignores attachment tags. Plain text with no tags produces base-styled text.
    static func deserializeToAttributedString(_ text: String) -> NSAttributedString {
        if text.isEmpty {
            return NSAttributedString(string: "", attributes: baseTypingAttributes())
        }

        let result = NSMutableAttributedString()
        var index = text.startIndex

        var fmtBold = false
        var fmtItalic = false
        var fmtUnderline = false
        var fmtStrikethrough = false
        var fmtHeading: TextFormattingManager.HeadingLevel = .none
        var fmtAlignment: NSTextAlignment = .left
        var fmtBlockQuote = false
        var fmtHighlightHex: String? = nil
        var fmtHighlightVariant: Int? = nil
        var fmtInlineCode = false
        var fmtColorHex: String? = nil

        // SecondaryTextColor is the canonical 70%-label dimmer token; matches strikethrough foreground.
        let blockQuoteColor = NSColor(named: "SecondaryTextColor") ?? NSColor.secondaryLabelColor

        var textBuffer = ""
        func flushBuffer() {
            guard !textBuffer.isEmpty else { return }
            var attrs = formattingAttributes(
                heading: fmtHeading,
                bold: fmtBold, italic: fmtItalic,
                underline: fmtUnderline, strikethrough: fmtStrikethrough,
                alignment: fmtAlignment)
            if fmtBlockQuote {
                attrs[.blockQuote] = true
                attrs[.paragraphStyle] = blockQuoteParagraphStyle()
                attrs[.foregroundColor] = blockQuoteColor
            }
            if let hlHex = fmtHighlightHex {
                attrs[.highlightColor] = hlHex
                // Assign variant — random if not persisted (backward compat with old notes)
                attrs[.highlightVariant] = fmtHighlightVariant ?? Int.random(in: 0..<8)
            }
            if fmtInlineCode {
                attrs[.font] = inlineCodeFont(bold: fmtBold, italic: fmtItalic)
                attrs[.inlineCode] = true
            }
            // Custom color must apply last so it overrides blockquote dimmer and composes with inline-code.
            if let hex = fmtColorHex {
                attrs[.foregroundColor] = TextFormattingManager.nsColorFromHex(hex)
                attrs[TextFormattingManager.customTextColorKey] = true
            }
            result.append(NSAttributedString(string: textBuffer, attributes: attrs))
            textBuffer = ""
        }

        while index < text.endIndex {
            let remaining = text[index...]

            // Skip known attachment tags that cards don't support
            if remaining.hasPrefix("[[image") || remaining.hasPrefix("[[webclip|") ||
               remaining.hasPrefix("[[linkcard|") || remaining.hasPrefix("[[link|") || remaining.hasPrefix("[[filelink|") ||
               remaining.hasPrefix("[[file|") || remaining.hasPrefix("[[table|") ||
               remaining.hasPrefix("[[callout|") || remaining.hasPrefix("[[code]]") ||
               remaining.hasPrefix("[[tabs|") || remaining.hasPrefix("[[cards|") ||
               remaining.hasPrefix("[[toggle|") ||
               remaining.hasPrefix("[[divider]]") || remaining.hasPrefix("[[notelink|") {
                flushBuffer()
                // Skip to the end of this tag
                if remaining.hasPrefix("[[divider]]") {
                    index = text.index(index, offsetBy: "[[divider]]".count)
                } else if let closeRange = remaining.range(of: "]]") {
                    index = closeRange.upperBound
                    // For paired tags like [[table|...]]...[[/table]], skip to the closing tag
                    if remaining.hasPrefix("[[table|") {
                        if let endRange = text[index...].range(of: "[[/table]]") {
                            index = endRange.upperBound
                        }
                    } else if remaining.hasPrefix("[[callout|") {
                        if let endRange = text[index...].range(of: "[[/callout]]") {
                            index = endRange.upperBound
                        }
                    } else if remaining.hasPrefix("[[code]]") {
                        if let endRange = text[index...].range(of: "[[/code]]") {
                            // Preserve code content as plain text instead of silently dropping it
                            let codeContent = String(text[index..<endRange.lowerBound])
                            textBuffer += codeContent
                            index = endRange.upperBound
                        }
                    } else if remaining.hasPrefix("[[tabs|") {
                        if let endRange = text[index...].range(of: "[[/tabs]]") {
                            index = endRange.upperBound
                        }
                    } else if remaining.hasPrefix("[[cards|") {
                        if let endRange = text[index...].range(of: "[[/cards]]") {
                            index = endRange.upperBound
                        }
                    } else if remaining.hasPrefix("[[toggle|") {
                        if let endRange = text[index...].range(of: "[[/toggle]]") {
                            index = endRange.upperBound
                        }
                    }
                } else {
                    index = text.index(after: index)
                }
                continue
            }

            // Inline formatting tags
            if remaining.hasPrefix("[[ic]]") {
                flushBuffer(); fmtInlineCode = true
                index = text.index(index, offsetBy: "[[ic]]".count); continue
            } else if remaining.hasPrefix("[[/ic]]") {
                flushBuffer(); fmtInlineCode = false
                index = text.index(index, offsetBy: "[[/ic]]".count); continue
            } else if remaining.hasPrefix("[[b]]") {
                flushBuffer(); fmtBold = true
                index = text.index(index, offsetBy: 5); continue
            } else if remaining.hasPrefix("[[/b]]") {
                flushBuffer(); fmtBold = false
                index = text.index(index, offsetBy: 6); continue
            } else if remaining.hasPrefix("[[i]]") {
                flushBuffer(); fmtItalic = true
                index = text.index(index, offsetBy: 5); continue
            } else if remaining.hasPrefix("[[/i]]") {
                flushBuffer(); fmtItalic = false
                index = text.index(index, offsetBy: 6); continue
            } else if remaining.hasPrefix("[[u]]") {
                flushBuffer(); fmtUnderline = true
                index = text.index(index, offsetBy: 5); continue
            } else if remaining.hasPrefix("[[/u]]") {
                flushBuffer(); fmtUnderline = false
                index = text.index(index, offsetBy: 6); continue
            } else if remaining.hasPrefix("[[s]]") {
                flushBuffer(); fmtStrikethrough = true
                index = text.index(index, offsetBy: 5); continue
            } else if remaining.hasPrefix("[[/s]]") {
                flushBuffer(); fmtStrikethrough = false
                index = text.index(index, offsetBy: 6); continue
            } else if remaining.hasPrefix("[[h1]]") {
                flushBuffer(); fmtHeading = .h1
                index = text.index(index, offsetBy: 6); continue
            } else if remaining.hasPrefix("[[/h1]]") {
                flushBuffer(); fmtHeading = .none
                index = text.index(index, offsetBy: 7); continue
            } else if remaining.hasPrefix("[[h2]]") {
                flushBuffer(); fmtHeading = .h2
                index = text.index(index, offsetBy: 6); continue
            } else if remaining.hasPrefix("[[/h2]]") {
                flushBuffer(); fmtHeading = .none
                index = text.index(index, offsetBy: 7); continue
            } else if remaining.hasPrefix("[[h3]]") {
                flushBuffer(); fmtHeading = .h3
                index = text.index(index, offsetBy: 6); continue
            } else if remaining.hasPrefix("[[/h3]]") {
                flushBuffer(); fmtHeading = .none
                index = text.index(index, offsetBy: 7); continue
            } else if remaining.hasPrefix("[[quote]]") {
                flushBuffer(); fmtBlockQuote = true
                index = text.index(index, offsetBy: 9); continue
            } else if remaining.hasPrefix("[[/quote]]") {
                flushBuffer(); fmtBlockQuote = false
                index = text.index(index, offsetBy: 10); continue
            } else if remaining.hasPrefix("[[align:center]]") {
                flushBuffer(); fmtAlignment = .center
                index = text.index(index, offsetBy: 16); continue
            } else if remaining.hasPrefix("[[align:right]]") {
                flushBuffer(); fmtAlignment = .right
                index = text.index(index, offsetBy: 15); continue
            } else if remaining.hasPrefix("[[align:justify]]") {
                flushBuffer(); fmtAlignment = .justified
                index = text.index(index, offsetBy: 17); continue
            } else if remaining.hasPrefix("[[/align]]") {
                flushBuffer(); fmtAlignment = .left
                index = text.index(index, offsetBy: 10); continue
            } else if remaining.hasPrefix("[[hl|") {
                flushBuffer()
                let prefixLen = "[[hl|".count
                let afterPrefix = text.index(index, offsetBy: prefixLen)
                if let closeBracket = text[afterPrefix...].range(of: "]]") {
                    let tagContent = String(text[afterPrefix..<closeBracket.lowerBound])
                    if let pipeIdx = tagContent.firstIndex(of: "|") {
                        // New format: [[hl|HEX|VARIANT]]
                        fmtHighlightHex = String(tagContent[tagContent.startIndex..<pipeIdx])
                        let afterPipe = tagContent.index(after: pipeIdx)
                        fmtHighlightVariant = Int(tagContent[afterPipe...])
                    } else {
                        // Legacy format: [[hl|HEX]] — variant assigned randomly in flushBuffer
                        fmtHighlightHex = tagContent
                        fmtHighlightVariant = nil
                    }
                    index = closeBracket.upperBound; continue
                }
            } else if remaining.hasPrefix("[[/hl]]") {
                flushBuffer(); fmtHighlightHex = nil; fmtHighlightVariant = nil
                index = text.index(index, offsetBy: 7); continue
            } else if remaining.hasPrefix("[[arrow]]") {
                flushBuffer()
                result.append(NSAttributedString(string: "\u{2192}", attributes: baseTypingAttributes()))
                index = text.index(index, offsetBy: "[[arrow]]".count)
                continue
            } else if remaining.hasPrefix("[[ol|") {
                flushBuffer()
                let prefixLen = "[[ol|".count
                let afterPrefix = text.index(index, offsetBy: prefixLen)
                if let closeBracket = text[afterPrefix...].range(of: "]]") {
                    let numStr = String(text[afterPrefix..<closeBracket.lowerBound])
                    let num = Int(numStr) ?? 1
                    let prefix = "\(num). "
                    var attrs = formattingAttributes(
                        heading: fmtHeading, bold: fmtBold, italic: fmtItalic,
                        underline: fmtUnderline, strikethrough: fmtStrikethrough,
                        alignment: fmtAlignment)
                    attrs[.orderedListNumber] = num
                    attrs[.font] = textFont
                    attrs[.foregroundColor] = NSColor.labelColor
                    // Hang-indent under the "N. " prefix so wrapped lines align past the number.
                    attrs[.paragraphStyle] = orderedListParagraphStyle()
                    result.append(NSAttributedString(string: prefix, attributes: attrs))
                    index = closeBracket.upperBound; continue
                }
            } else if remaining.hasPrefix("[[color|") {
                flushBuffer()
                let prefixLen = "[[color|".count
                let afterPrefix = text.index(index, offsetBy: prefixLen)
                // State-toggle (matches `[[hl|…]]` and every other inline tag) so nested `[[ic]]`,
                // `[[b]]`, etc. interleave correctly. Malformed hex degrades to an uncolored run
                // instead of leaking the raw tag characters.
                if let openClose = text[afterPrefix...].range(of: "]]") {
                    let hex = String(text[afterPrefix..<openClose.lowerBound])
                    let hexOK = (hex.count == 6 || hex.count == 8)
                        && hex.allSatisfy { $0.isHexDigit }
                    fmtColorHex = hexOK ? hex : nil
                    index = openClose.upperBound; continue
                }
                // No `]]` for the opener — drop the prefix tokens and resume plain text.
                index = afterPrefix; continue
            } else if remaining.hasPrefix("[[/color]]") {
                flushBuffer(); fmtColorHex = nil
                index = text.index(index, offsetBy: 10); continue
            } else if remaining.hasPrefix("[[/code]]") {
                // Orphaned close tag -- skip
                index = text.index(index, offsetBy: 9); continue
            }

            // Plain text character
            textBuffer.append(text[index])
            index = text.index(after: index)
        }

        flushBuffer()
        return result
    }
}
#endif
