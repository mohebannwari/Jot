//
//  CalloutData.swift
//  Jot
//
//  Data model for callout/admonition blocks.
//  Serialization: `[[callout|type]]content[[/callout]]` or, when width is customized,
//  `[[callout|type:WW.WW]]content[[/callout]]` (POSIX decimal point).
//

import CoreGraphics
import Foundation

struct CalloutData: Equatable {

    enum CalloutType: String, CaseIterable, Equatable {
        case info
        case warning
        case tip
        case note
        case important

        var icon: String {
            switch self {
            case .info:      return "IconCircleInfo"
            case .warning:   return "IconExclamationTriangle"
            case .tip:       return "IconLightBulbSimple"
            case .note:      return "IconNote2"
            case .important: return "IconExclamationCircleBold"
            }
        }
    }

    var type: CalloutType
    var content: String
    /// When non-nil, editor uses this width clamped to the text container; `nil` means full container width.
    var preferredContentWidth: CGFloat?

    static func empty(type: CalloutType = .info) -> CalloutData {
        CalloutData(type: type, content: "", preferredContentWidth: nil)
    }

    // MARK: - Serialization

    private static let markupLocale = Locale(identifier: "en_US_POSIX")

    func serialize() -> String {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
        let openTag: String
        if let w = preferredContentWidth {
            let widthStr = String(format: "%.2f", locale: Self.markupLocale, Double(w))
            openTag = "[[callout|\(type.rawValue):\(widthStr)]]"
        } else {
            openTag = "[[callout|\(type.rawValue)]]"
        }
        return "\(openTag)\(escaped)[[/callout]]"
    }

    static func deserialize(from text: String) -> CalloutData? {
        guard text.hasPrefix("[[callout|") else { return nil }

        let afterPrefix = text.dropFirst("[[callout|".count)
        guard let closeBracket = afterPrefix.firstIndex(of: "]"),
              closeBracket < afterPrefix.endIndex else { return nil }

        let header = String(afterPrefix[afterPrefix.startIndex..<closeBracket])
        var preferredContentWidth: CGFloat?
        var typeString = header
        // Optional `type:width` suffix — `:` is never part of a CalloutType raw value.
        if let colonIdx = header.lastIndex(of: ":"), colonIdx > header.startIndex {
            let prefix = String(header[..<colonIdx])
            let suffix = String(header[header.index(after: colonIdx)...])
            if let w = Double(suffix), CalloutType(rawValue: prefix) != nil {
                typeString = prefix
                preferredContentWidth = CGFloat(w)
            }
        }
        guard let calloutType = CalloutType(rawValue: typeString) else { return nil }

        let contentStart = afterPrefix.index(closeBracket, offsetBy: 2)
        guard contentStart < afterPrefix.endIndex else { return nil }

        let remaining = afterPrefix[contentStart...]
        guard let closingRange = remaining.range(of: "[[/callout]]") else { return nil }

        let rawContent = String(remaining[remaining.startIndex..<closingRange.lowerBound])
        let content = rawContent
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")

        return CalloutData(
            type: calloutType, content: content, preferredContentWidth: preferredContentWidth)
    }
}
