//
//  CodeBlockData.swift
//  Jot
//
//  Data model for code block attachments.
//  Serialization format: [[codeblock|language]]escaped_code[[/codeblock]]
//

import Foundation

struct CodeBlockData: Equatable {

    /// Language identifier (lowercase). e.g. "javascript", "swift", "plaintext"
    var language: String

    /// Raw code string (unescaped).
    var code: String

    static func empty(language: String = "plaintext") -> CodeBlockData {
        CodeBlockData(language: language, code: "")
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

    func serialize() -> String {
        let escaped = Self.escapeCode(code)
        return "[[codeblock|\(language)]]\(escaped)[[/codeblock]]"
    }

    static func deserialize(from text: String) -> CodeBlockData? {
        guard text.hasPrefix("[[codeblock|") else { return nil }
        let afterPrefix = text.dropFirst("[[codeblock|".count)
        guard let closeBracket = afterPrefix.range(of: "]]") else { return nil }

        let language = String(afterPrefix[afterPrefix.startIndex..<closeBracket.lowerBound])
        let contentStart = closeBracket.upperBound

        let remaining = afterPrefix[contentStart...]
        guard let closingRange = remaining.range(of: "[[/codeblock]]") else { return nil }

        let rawCode = String(remaining[remaining.startIndex..<closingRange.lowerBound])
        let code = unescapeCode(rawCode)

        return CodeBlockData(language: language.isEmpty ? "plaintext" : language, code: code)
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
