//
//  CodeBlockData.swift
//  Jot
//
//  Data model for code block attachments.
//  Serialization: `[[codeblock|language]]escaped_code[[/codeblock]]` or, when width is customized,
//  `[[codeblock|language:WW.WW]]escaped_code[[/codeblock]]` (POSIX decimal point; same idea as callouts).
//

import CoreGraphics
import Foundation

struct CodeBlockData: Equatable {

    /// Language identifier (lowercase). e.g. "javascript", "swift", "plaintext"
    var language: String

    /// Raw code string (unescaped).
    var code: String

    /// When non-nil, editor uses this width clamped to the text container; `nil` means full container width.
    var preferredContentWidth: CGFloat?

    init(language: String, code: String, preferredContentWidth: CGFloat? = nil) {
        self.language = language
        self.code = code
        self.preferredContentWidth = preferredContentWidth
    }

    static func empty(language: String = "plaintext") -> CodeBlockData {
        CodeBlockData(language: language, code: "", preferredContentWidth: nil)
    }

    // MARK: - Supported Languages

    /// All supported language identifiers in display order.
    static let supportedLanguages: [String] = [
        "plaintext", "swift", "javascript", "typescript", "python",
        "json", "html", "css", "sql", "go", "rust",
        "kotlin", "java", "c", "cpp", "bash",
        "ruby", "php", "yaml", "xml", "markdown"
    ]

    /// Human-readable display name for a language identifier.
    static func displayName(for language: String) -> String {
        switch language.lowercased() {
        case "plaintext":   return "Plaintext"
        case "swift":       return "Swift"
        case "javascript":  return "JavaScript"
        case "typescript":  return "TypeScript"
        case "python":      return "Python"
        case "json":        return "JSON"
        case "html":        return "HTML"
        case "css":         return "CSS"
        case "sql":         return "SQL"
        case "go":          return "Go"
        case "rust":        return "Rust"
        case "kotlin":      return "Kotlin"
        case "java":        return "Java"
        case "c":           return "C"
        case "cpp":         return "C++"
        case "bash":        return "Bash"
        case "ruby":        return "Ruby"
        case "php":         return "PHP"
        case "yaml":        return "YAML"
        case "xml":         return "XML"
        case "markdown":    return "Markdown"
        default:            return language.isEmpty ? "Plaintext" : language.capitalized
        }
    }

    // MARK: - Serialization

    private static let markupLocale = Locale(identifier: "en_US_POSIX")

    func serialize() -> String {
        let escaped = Self.escapeCode(code)
        let openTag: String
        if let w = preferredContentWidth {
            let widthStr = String(format: "%.2f", locale: Self.markupLocale, Double(w))
            openTag = "[[codeblock|\(language):\(widthStr)]]"
        } else {
            openTag = "[[codeblock|\(language)]]"
        }
        return "\(openTag)\(escaped)[[/codeblock]]"
    }

    static func deserialize(from text: String) -> CodeBlockData? {
        guard text.hasPrefix("[[codeblock|") else { return nil }
        let afterPrefix = text.dropFirst("[[codeblock|".count)
        guard let closeBracket = afterPrefix.range(of: "]]") else { return nil }

        let rawHeader = String(afterPrefix[afterPrefix.startIndex..<closeBracket.lowerBound])
        var language = rawHeader
        var preferredContentWidth: CGFloat?
        // Optional `language:width` suffix — width must parse as a positive double.
        if let colonIdx = rawHeader.lastIndex(of: ":"), colonIdx > rawHeader.startIndex {
            let prefix = String(rawHeader[..<colonIdx])
            let suffix = String(rawHeader[rawHeader.index(after: colonIdx)...])
            if let w = Double(suffix), w > 0, !prefix.isEmpty {
                language = prefix
                preferredContentWidth = CGFloat(w)
            }
        }
        if language.isEmpty { language = "plaintext" }

        let contentStart = closeBracket.upperBound

        let remaining = afterPrefix[contentStart...]
        guard let closingRange = remaining.range(of: "[[/codeblock]]") else { return nil }

        let rawCode = String(remaining[remaining.startIndex..<closingRange.lowerBound])
        let code = unescapeCode(rawCode)

        return CodeBlockData(language: language, code: code, preferredContentWidth: preferredContentWidth)
    }

    // MARK: - Escape Helpers
    //
    // Uses a proper character-by-character escaper so that code containing
    // literal \n, \\, etc. round-trips correctly — unlike naive replacingOccurrences
    // which has an ordering ambiguity between \\ and \n sequences.

    private static func escapeCode(_ code: String) -> String {
        var result = ""
        result.reserveCapacity(code.count + 16)
        for char in code {
            switch char {
            case "\\":  result += "\\\\"
            case "\n":  result += "\\n"
            default:    result.append(char)
            }
        }
        return result
    }

    private static func unescapeCode(_ escaped: String) -> String {
        var result = ""
        result.reserveCapacity(escaped.count)
        var i = escaped.startIndex
        while i < escaped.endIndex {
            if escaped[i] == "\\" {
                let next = escaped.index(after: i)
                if next < escaped.endIndex {
                    switch escaped[next] {
                    case "n":  result += "\n"; i = escaped.index(after: next)
                    case "\\": result += "\\"; i = escaped.index(after: next)
                    default:   result.append(escaped[i]); i = next
                    }
                } else {
                    result.append(escaped[i])
                    i = escaped.index(after: i)
                }
            } else {
                result.append(escaped[i])
                i = escaped.index(after: i)
            }
        }
        return result
    }
}
