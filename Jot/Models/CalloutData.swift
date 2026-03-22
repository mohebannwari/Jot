//
//  CalloutData.swift
//  Jot
//
//  Data model for callout/admonition blocks.
//  Serialization format: [[callout|type]]content[[/callout]]
//

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

        /// Accent color hex (/500 shade) — used for the floating pill background.
        var accentColorHex: String {
            switch self {
            case .info:      return "#3B82F6"  // blue-500
            case .warning:   return "#EAB308"  // yellow-500
            case .tip:       return "#22C55E"  // green-500
            case .note:      return "#78716C"  // stone-500
            case .important: return "#EF4444"  // red-500
            }
        }

        /// Light mode block background (/50 shade).
        var backgroundColorHex: String {
            switch self {
            case .info:      return "#EFF6FF"   // blue-50
            case .warning:   return "#FEFCE8"   // yellow-50
            case .tip:       return "#F0FDF4"   // green-50
            case .note:      return "#FAFAF9"   // stone-50
            case .important: return "#FEF2F2"   // red-50
            }
        }

        /// Dark mode block background (/950 shade).
        var backgroundColorDarkHex: String {
            switch self {
            case .info:      return "#172554"   // blue-950
            case .warning:   return "#422006"   // yellow-950
            case .tip:       return "#052E16"   // green-950
            case .note:      return "#0C0A09"   // stone-950
            case .important: return "#450A0A"   // red-950
            }
        }
    }

    var type: CalloutType
    var content: String

    static func empty(type: CalloutType = .info) -> CalloutData {
        CalloutData(type: type, content: "")
    }

    // MARK: - Serialization

    func serialize() -> String {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "[[callout|\(type.rawValue)]]\(escaped)[[/callout]]"
    }

    static func deserialize(from text: String) -> CalloutData? {
        // Expected: [[callout|type]]content[[/callout]]
        guard text.hasPrefix("[[callout|") else { return nil }

        let afterPrefix = text.dropFirst("[[callout|".count)
        guard let closeBracket = afterPrefix.firstIndex(of: "]"),
              closeBracket < afterPrefix.endIndex else { return nil }

        let typeString = String(afterPrefix[afterPrefix.startIndex..<closeBracket])
        guard let calloutType = CalloutType(rawValue: typeString) else { return nil }

        // Skip "]]" after type
        let contentStart = afterPrefix.index(closeBracket, offsetBy: 2)
        guard contentStart < afterPrefix.endIndex else { return nil }

        // Find [[/callout]]
        let remaining = afterPrefix[contentStart...]
        guard let closingRange = remaining.range(of: "[[/callout]]") else { return nil }

        let rawContent = String(remaining[remaining.startIndex..<closingRange.lowerBound])
        let content = rawContent
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")

        return CalloutData(type: calloutType, content: content)
    }
}
