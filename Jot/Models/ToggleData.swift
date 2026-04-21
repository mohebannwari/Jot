//
//  ToggleData.swift
//  Jot
//
//  Data model for Notion-style toggle (collapsible section) blocks embedded
//  in the rich-text editor. Mirrors the CalloutData / TabsContainerData
//  pattern — the block is a single NSTextAttachment whose overlay NSView
//  renders a title row with a chevron on the right and a nested rich-text
//  body that hides when the user collapses the block.
//

import CoreGraphics
import Foundation

struct ToggleData: Equatable {
    var title: String
    /// Serialized rich-text body in the same grammar the note body uses
    /// (`[[b]]`, `[[h1]]`, `[[todo]]`, `[[image|...]]`, etc.). Kept as a
    /// single escaped string so one attachment owns one chunk of body text,
    /// same idea as TabsContainerData's per-pane content.
    var content: String
    /// Persisted, unlike heading-fold session state. Users expect a toggle
    /// to stay closed across app launches.
    var isExpanded: Bool
    /// nil = full container width; otherwise clamped to container on layout.
    var preferredContentWidth: CGFloat?

    static func empty() -> ToggleData {
        ToggleData(title: "", content: "", isExpanded: true, preferredContentWidth: nil)
    }

    // MARK: - Serialization

    // Format: [[toggle|isExpanded|preferredWidthOrEmpty]]<escapedTitle>\t\t<escapedContent>[[/toggle]]
    //   isExpanded           : "1" | "0"
    //   preferredWidthOrEmpty: %.2f POSIX decimal, or empty string for nil
    //   title / content      : escaped via Self.escape (\, \n, \t, [, ])

    private static let markupLocale = Locale(identifier: "en_US_POSIX")

    func serialize() -> String {
        let flag = isExpanded ? "1" : "0"
        let widthStr: String
        if let w = preferredContentWidth {
            widthStr = String(format: "%.2f", locale: Self.markupLocale, Double(w))
        } else {
            widthStr = ""
        }
        let t = Self.escape(title)
        let c = Self.escape(content)
        return "[[toggle|\(flag)|\(widthStr)]]\(t)\t\t\(c)[[/toggle]]"
    }

    static func deserialize(from text: String) -> ToggleData? {
        guard text.hasPrefix("[[toggle|") else { return nil }
        let afterPrefix = text.dropFirst("[[toggle|".count)
        guard let closeBracket = afterPrefix.range(of: "]]") else { return nil }

        let header = String(afterPrefix[afterPrefix.startIndex..<closeBracket.lowerBound])
        let parts = header.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let isExpanded: Bool
        switch parts[0] {
        case "1": isExpanded = true
        case "0": isExpanded = false
        default: return nil
        }

        let widthField = String(parts[1])
        let preferredContentWidth: CGFloat?
        if widthField.isEmpty {
            preferredContentWidth = nil
        } else if let w = Double(widthField) {
            preferredContentWidth = CGFloat(w)
        } else {
            // Malformed width degrades gracefully to nil — never reject the
            // whole block because the width field is garbage. Matches Tabs.
            preferredContentWidth = nil
        }

        let contentStart = closeBracket.upperBound
        let remaining = afterPrefix[contentStart...]
        guard let closingRange = remaining.range(of: "[[/toggle]]") else { return nil }
        let raw = String(remaining[remaining.startIndex..<closingRange.lowerBound])

        // Split into escaped title and escaped content on the first `\t\t`.
        // Literal double-tabs inside content are escaped to `\\t\\t` at
        // serialize time, so the first real double-tab can only be the
        // title/content separator.
        let title: String
        let content: String
        if let sep = raw.range(of: "\t\t") {
            title = Self.unescape(String(raw[raw.startIndex..<sep.lowerBound]))
            content = Self.unescape(String(raw[sep.upperBound...]))
        } else {
            title = Self.unescape(raw)
            content = ""
        }

        return ToggleData(
            title: title,
            content: content,
            isExpanded: isExpanded,
            preferredContentWidth: preferredContentWidth
        )
    }

    // MARK: - Escape helpers

    private static func escape(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "[": result += "\\["
            case "]": result += "\\]"
            default: result.append(ch)
            }
        }
        return result
    }

    private static func unescape(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\\" {
                let next = s.index(after: i)
                if next < s.endIndex {
                    switch s[next] {
                    case "\\": result.append("\\")
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "[": result.append("[")
                    case "]": result.append("]")
                    default:
                        result.append(s[i])
                        result.append(s[next])
                    }
                    i = s.index(after: next)
                } else {
                    result.append(s[i])
                    i = next
                }
            } else {
                result.append(s[i])
                i = s.index(after: i)
            }
        }
        return result
    }
}
