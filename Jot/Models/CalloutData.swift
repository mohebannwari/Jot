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

        /// Accent color hex used for the left border and icon tint.
        var accentColorHex: String {
            switch self {
            case .info:      return "#3B82F6"  // blue
            case .warning:   return "#F59E0B"  // amber
            case .tip:       return "#10B981"  // green
            case .note:      return "#6B7280"  // gray
            case .important: return "#EF4444"  // red
            }
        }

        /// Lighter background fill hex.
        var backgroundColorHex: String {
            switch self {
            case .info:      return "#EFF6FF"
            case .warning:   return "#FFFBEB"
            case .tip:       return "#ECFDF5"
            case .note:      return "#F3F4F6"
            case .important: return "#FEF2F2"
            }
        }

        /// Dark mode background fill hex.
        var backgroundColorDarkHex: String {
            switch self {
            case .info:      return "#1E293B"
            case .warning:   return "#292524"
            case .tip:       return "#1A2E2A"
            case .note:      return "#1F2937"
            case .important: return "#2D1B1B"
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
