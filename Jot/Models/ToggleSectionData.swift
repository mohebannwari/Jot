//
//  ToggleSectionData.swift
//  Jot
//
//  Data model for toggle sections.
//  Serialization format: [[toggle|isExpanded|title]]content[[/toggle]]
//

import Foundation

struct ToggleSectionData: Equatable {
    var isExpanded: Bool
    var title: String
    var content: String

    static func empty() -> ToggleSectionData {
        ToggleSectionData(isExpanded: true, title: "Toggle section", content: "")
    }

    // MARK: - Serialization

    func serialize() -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "|", with: "\\|")
            
        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            
        let expandedStr = isExpanded ? "1" : "0"
        return "[[toggle|\(expandedStr)|\(escapedTitle)]]\(escapedContent)[[/toggle]]"
    }

    static func deserialize(from text: String) -> ToggleSectionData? {
        guard text.hasPrefix("[[toggle|") else { return nil }
        
        let afterPrefix = text.dropFirst("[[toggle|".count)
        guard let closeBracket = afterPrefix.range(of: "]]") else { return nil }
        
        let header = String(afterPrefix[afterPrefix.startIndex..<closeBracket.lowerBound])
        let components = header.components(separatedBy: "(?<!\\\\)\\|") // Split by pipe, ignoring escaped pipes
        
        // Manual split to avoid complex regex if not supported natively easily
        var parts: [String] = []
        var currentPart = ""
        var isEscaped = false
        for char in header {
            if isEscaped {
                currentPart.append(char)
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "|" {
                parts.append(currentPart)
                currentPart = ""
            } else {
                currentPart.append(char)
            }
        }
        parts.append(currentPart)
        
        let isExpanded = (parts.first == "1")
        let title = parts.count > 1 ? parts[1].replacingOccurrences(of: "\\n", with: "\n") : "Toggle section"
        
        let contentStart = closeBracket.upperBound
        let remaining = afterPrefix[contentStart...]
        guard let closingRange = remaining.range(of: "[[/toggle]]") else { return nil }
        
        let rawContent = String(remaining[remaining.startIndex..<closingRange.lowerBound])
        let content = rawContent
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
            
        return ToggleSectionData(isExpanded: isExpanded, title: title, content: content)
    }
}
