import Foundation

enum EditorPasteClassifier {
    static func isLikelyURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else {
            return false
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }
        let fullRange = NSRange(location: 0, length: (trimmed as NSString).length)
        let matches = detector.matches(in: trimmed, options: [], range: fullRange)
        return matches.count == 1 && matches[0].range.location == 0 && matches[0].range.length == fullRange.length
    }

    static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let fullRange = NSRange(location: 0, length: (trimmed as NSString).length)
        return detector.firstMatch(in: trimmed, options: [], range: fullRange)?.url
    }

    static func classifyCode(_ text: String) -> (isCode: Bool, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "plaintext") }

        let lines = trimmed.components(separatedBy: .newlines)
        let isMultiline = lines.count > 1

        let strongPatterns: [String] = [
            #"^import\s+"#, #"^from\s+\S+\s+import"#,
            #"^func\s+"#, #"^def\s+"#, #"^class\s+"#, #"^struct\s+"#,
            #"^enum\s+"#, #"^#include\s+"#, #"^package\s+"#,
            #"^use\s+"#, #"^module\s+"#,
            #"=>\s*\{"#, #"->\s*\{"#,
        ]
        let lineEndPatterns: [String] = [
            #"\{\s*$"#, #"\};\s*$"#,
        ]

        var strongCount = 0
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            for pattern in strongPatterns where trimmedLine.range(of: pattern, options: .regularExpression) != nil {
                strongCount += 1
                break
            }
            for pattern in lineEndPatterns where trimmedLine.range(of: pattern, options: .regularExpression) != nil {
                strongCount += 1
                break
            }
        }

        var mediumCount = 0
        if trimmed.contains("{") && trimmed.contains("}") { mediumCount += 1 }
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix(";") }) { mediumCount += 1 }
        if trimmed.contains("->") { mediumCount += 1 }
        if lines.contains(where: {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line.hasPrefix("//") || (line.hasPrefix("#") && !line.hasPrefix("# ") && !line.hasPrefix("## "))
        }) { mediumCount += 1 }
        if trimmed.range(of: #"(let|var|const|val)\s+\w+\s*="#, options: .regularExpression) != nil {
            mediumCount += 1
        }

        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if nonEmptyLines.count > 1 {
            let indentedCount = nonEmptyLines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
            if Double(indentedCount) / Double(nonEmptyLines.count) >= 0.5 { mediumCount += 1 }
        }
        if trimmed.range(of: #"\w+\([^)]*\)"#, options: .regularExpression) != nil { mediumCount += 1 }

        var negativeCount = 0
        for line in lines {
            let words = line.split(separator: " ")
            let hasOperators = line.contains("{") || line.contains("}") || line.contains(";")
                || line.contains("=") || line.contains("(") || line.contains("->")
            if words.count >= 5 && !hasOperators {
                negativeCount += 1
            }
        }
        if lines.contains(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }) { negativeCount += 1 }
        if trimmed.count < 8 && strongCount == 0 { return (false, "plaintext") }

        let isCode: Bool
        if isMultiline {
            isCode = strongCount > 0 || (mediumCount >= 2 && negativeCount < nonEmptyLines.count / 2)
        } else {
            isCode = strongCount > 0
        }

        if !isCode { return (false, "plaintext") }
        return (true, detectCodeLanguage(trimmed))
    }

    static func detectCodeLanguage(_ text: String) -> String {
        struct LangScore {
            let language: String
            let exclusiveKeywords: [String]
            let keywords: [String]
        }

        let languages: [LangScore] = [
            LangScore(language: "swift", exclusiveKeywords: ["guard ", "@State", "@Published", "import SwiftUI", "import UIKit"], keywords: ["func ", "let ", "var "]),
            LangScore(language: "go", exclusiveKeywords: [":=", "fmt.", "go func", "package main"], keywords: ["func ", "package "]),
            LangScore(language: "python", exclusiveKeywords: ["elif ", "__init__", "self."], keywords: ["def ", "import "]),
            LangScore(language: "javascript", exclusiveKeywords: ["===", "console.log", "require("], keywords: ["function ", "const ", "=> "]),
            LangScore(language: "typescript", exclusiveKeywords: [": string", ": number", ": boolean", "interface "], keywords: ["function ", "const ", "=> "]),
            LangScore(language: "rust", exclusiveKeywords: ["fn ", "mut ", "impl ", "pub fn"], keywords: ["::"]),
            LangScore(language: "java", exclusiveKeywords: ["public static void", "System.out", "@Override"], keywords: ["class ", "import "]),
            LangScore(language: "cpp", exclusiveKeywords: ["#include", "std::", "nullptr", "int main"], keywords: ["::", "cout"]),
            LangScore(language: "sql", exclusiveKeywords: ["SELECT ", "INSERT INTO", "CREATE TABLE"], keywords: ["FROM ", "WHERE ", "JOIN "]),
            LangScore(language: "html", exclusiveKeywords: ["<div", "<span", "<html", "className="], keywords: ["</"]),
            LangScore(language: "css", exclusiveKeywords: ["font-size:", "margin:", "padding:", "display:"], keywords: ["{", "}"]),
            LangScore(language: "bash", exclusiveKeywords: ["#!/bin/bash", "#!/bin/sh"], keywords: ["echo ", "export "]),
            LangScore(language: "ruby", exclusiveKeywords: ["puts ", "require '", "attr_accessor"], keywords: ["def ", "end"]),
        ]

        var bestLang = "plaintext"
        var bestScore = 0

        for lang in languages {
            var score = 0
            for keyword in lang.exclusiveKeywords where text.contains(keyword) {
                score += 3
            }
            for keyword in lang.keywords where text.contains(keyword) {
                score += 1
            }
            if score > bestScore {
                bestScore = score
                bestLang = lang.language
            }
        }

        return bestScore > 0 ? bestLang : "plaintext"
    }
}
