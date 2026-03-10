//
//  SyntaxHighlighter.swift
//  Jot
//
//  Regex-based native syntax highlighter for 21 languages.
//  Produces NSAttributedString with adaptive light/dark token colors.
//
//  Architecture:
//  1. State-machine tokenizer marks comment & string ranges (protected regions)
//  2. Keyword/number/type regex applied only outside protected regions
//  3. String & comment colors applied last (highest visual priority)
//

import AppKit
import Foundation

// MARK: - Language Grammar

struct LanguageGrammar {
    let keywords: Set<String>
    let lineCommentPrefix: String?
    let blockCommentStart: String?
    let blockCommentEnd: String?
    /// Single-character string delimiters (e.g. `"`, `'`, `` ` ``)
    let stringDelimiters: [Character]
    /// Multi-character string delimiters (e.g. `"""` for Swift/Python)
    let multilineStringDelimiter: String?
    /// Optional regex for type/class names (applied outside protected regions)
    let typePattern: String?
    /// Whether keyword matching is case-insensitive (e.g. SQL)
    let caseInsensitiveKeywords: Bool

    init(
        keywords: Set<String>,
        lineCommentPrefix: String? = nil,
        blockCommentStart: String? = nil,
        blockCommentEnd: String? = nil,
        stringDelimiters: [Character] = [],
        multilineStringDelimiter: String? = nil,
        typePattern: String? = nil,
        caseInsensitiveKeywords: Bool = false
    ) {
        self.keywords = keywords
        self.lineCommentPrefix = lineCommentPrefix
        self.blockCommentStart = blockCommentStart
        self.blockCommentEnd = blockCommentEnd
        self.stringDelimiters = stringDelimiters
        self.multilineStringDelimiter = multilineStringDelimiter
        self.typePattern = typePattern
        self.caseInsensitiveKeywords = caseInsensitiveKeywords
    }
}

// MARK: - SyntaxHighlighter

enum SyntaxHighlighter {

    // MARK: - Public API

    static func highlight(code: String, language: String, isDark: Bool) -> NSAttributedString {
        let grammar = grammars[language.lowercased()] ?? grammars["plaintext"]!
        return applyHighlighting(code: code, grammar: grammar, isDark: isDark)
    }

    // MARK: - Core Engine

    private static func applyHighlighting(
        code: String,
        grammar: LanguageGrammar,
        isDark: Bool
    ) -> NSAttributedString {
        let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let result = NSMutableAttributedString(string: code, attributes: [
            .font: monoFont,
            .foregroundColor: NSColor.labelColor
        ])

        guard !code.isEmpty else { return result }

        let (commentRanges, stringRanges) = tokenize(code, grammar: grammar)
        let protectedRanges = commentRanges + stringRanges

        // Apply keyword colors (outside protected regions)
        if !grammar.keywords.isEmpty {
            let escaped = grammar.keywords
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "|")
            let pattern = "\\b(?:\(escaped))\\b"
            var options: NSRegularExpression.Options = []
            if grammar.caseInsensitiveKeywords { options.insert(.caseInsensitive) }
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                let fullRange = NSRange(code.startIndex..., in: code)
                regex.enumerateMatches(in: code, range: fullRange) { match, _, _ in
                    guard let range = match?.range,
                          !isInProtectedRange(range, protectedRanges: protectedRanges) else { return }
                    result.addAttribute(.foregroundColor, value: keywordColor(isDark: isDark), range: range)
                }
            }
        }

        // Apply number colors (outside protected regions)
        let numberPattern = #"\b(?:0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+|\d+\.?\d*(?:[eE][+-]?\d+)?)\b"#
        if let regex = try? NSRegularExpression(pattern: numberPattern) {
            let fullRange = NSRange(code.startIndex..., in: code)
            regex.enumerateMatches(in: code, range: fullRange) { match, _, _ in
                guard let range = match?.range,
                      !isInProtectedRange(range, protectedRanges: protectedRanges) else { return }
                result.addAttribute(.foregroundColor, value: numberColor(isDark: isDark), range: range)
            }
        }

        // Apply type/class name colors (outside protected regions)
        if let typePattern = grammar.typePattern,
           let regex = try? NSRegularExpression(pattern: typePattern) {
            let fullRange = NSRange(code.startIndex..., in: code)
            regex.enumerateMatches(in: code, range: fullRange) { match, _, _ in
                guard let range = match?.range,
                      !isInProtectedRange(range, protectedRanges: protectedRanges) else { return }
                result.addAttribute(.foregroundColor, value: typeColor(isDark: isDark), range: range)
            }
        }

        // Apply string colors (overrides keywords/numbers inside strings)
        for range in stringRanges {
            result.addAttribute(.foregroundColor, value: stringColor(isDark: isDark), range: range)
        }

        // Apply comment colors (highest priority — overrides everything)
        let commentColor = Self.commentColor(isDark: isDark)
        for range in commentRanges {
            result.addAttribute(.foregroundColor, value: commentColor, range: range)
        }

        return result
    }

    // MARK: - State-Machine Tokenizer

    private static func tokenize(
        _ code: String,
        grammar: LanguageGrammar
    ) -> (commentRanges: [NSRange], stringRanges: [NSRange]) {
        var commentRanges: [NSRange] = []
        var stringRanges: [NSRange] = []
        var i = code.startIndex

        while i < code.endIndex {
            let slice = code[i...]

            // Block comment (e.g. /* ... */)
            if let bcs = grammar.blockCommentStart,
               let bce = grammar.blockCommentEnd,
               slice.hasPrefix(bcs) {
                let startIdx = i
                i = code.index(i, offsetBy: bcs.count, limitedBy: code.endIndex) ?? code.endIndex
                while i < code.endIndex {
                    if code[i...].hasPrefix(bce) {
                        i = code.index(i, offsetBy: bce.count, limitedBy: code.endIndex) ?? code.endIndex
                        break
                    }
                    i = code.index(after: i)
                }
                commentRanges.append(NSRange(startIdx..<i, in: code))
                continue
            }

            // Line comment (e.g. //, #, --)
            if let lcp = grammar.lineCommentPrefix, slice.hasPrefix(lcp) {
                let startIdx = i
                i = code.index(i, offsetBy: lcp.count, limitedBy: code.endIndex) ?? code.endIndex
                while i < code.endIndex && code[i] != "\n" {
                    i = code.index(after: i)
                }
                commentRanges.append(NSRange(startIdx..<i, in: code))
                continue
            }

            // Multiline string (e.g. """ ... """)
            if let msd = grammar.multilineStringDelimiter, slice.hasPrefix(msd) {
                let startIdx = i
                i = code.index(i, offsetBy: msd.count, limitedBy: code.endIndex) ?? code.endIndex
                while i < code.endIndex {
                    if code[i...].hasPrefix(msd) {
                        i = code.index(i, offsetBy: msd.count, limitedBy: code.endIndex) ?? code.endIndex
                        break
                    }
                    // Skip escaped character
                    if code[i] == "\\" {
                        i = code.index(after: i)
                        if i < code.endIndex { i = code.index(after: i) }
                    } else {
                        i = code.index(after: i)
                    }
                }
                stringRanges.append(NSRange(startIdx..<i, in: code))
                continue
            }

            // Single-character string delimiter (e.g. ", ', `)
            if grammar.stringDelimiters.contains(code[i]) {
                let delim = code[i]
                let startIdx = i
                i = code.index(after: i)
                while i < code.endIndex && code[i] != "\n" {
                    if code[i] == "\\" {
                        // Skip the escaped character
                        i = code.index(after: i)
                        if i < code.endIndex { i = code.index(after: i) }
                        continue
                    }
                    if code[i] == delim {
                        i = code.index(after: i)
                        break
                    }
                    i = code.index(after: i)
                }
                stringRanges.append(NSRange(startIdx..<i, in: code))
                continue
            }

            i = code.index(after: i)
        }

        return (commentRanges, stringRanges)
    }

    // MARK: - Range Utility

    private static func isInProtectedRange(_ range: NSRange, protectedRanges: [NSRange]) -> Bool {
        for protected in protectedRanges {
            if NSIntersectionRange(range, protected).length > 0 { return true }
        }
        return false
    }

    // MARK: - Token Colors

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }

    private static func keywordColor(isDark: Bool) -> NSColor {
        isDark ? rgb(0.749, 0.353, 0.949) : rgb(0.345, 0.337, 0.839)
    }

    private static func stringColor(isDark: Bool) -> NSColor {
        isDark ? rgb(0.188, 0.855, 0.357) : rgb(0.098, 0.569, 0.431)
    }

    static func commentColor(isDark: Bool) -> NSColor {
        isDark ? rgb(0.388, 0.388, 0.400) : rgb(0.557, 0.557, 0.576)
    }

    private static func numberColor(isDark: Bool) -> NSColor {
        isDark ? rgb(0.392, 0.824, 1.000) : rgb(0.000, 0.478, 1.000)
    }

    private static func typeColor(isDark: Bool) -> NSColor {
        isDark ? rgb(0.353, 0.784, 0.980) : rgb(0.000, 0.439, 0.792)
    }

    // MARK: - Language Grammars

    static let grammars: [String: LanguageGrammar] = [

        "plaintext": LanguageGrammar(keywords: []),

        "swift": LanguageGrammar(
            keywords: [
                "as", "associatedtype", "break", "case", "catch", "class", "continue",
                "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough",
                "false", "fileprivate", "final", "for", "func", "get", "guard", "if", "import",
                "in", "init", "inout", "internal", "is", "lazy", "let", "mutating", "nil",
                "nonmutating", "open", "operator", "override", "postfix", "prefix", "private",
                "protocol", "public", "repeat", "required", "rethrows", "return", "self", "Self",
                "set", "some", "static", "struct", "subscript", "super", "switch", "throw",
                "throws", "true", "try", "typealias", "unowned", "var", "weak", "where", "while",
                "any", "actor", "async", "await", "consume", "copy", "distributed", "each",
                "macro", "nonisolated", "package", "then", "isolated"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\""],
            multilineStringDelimiter: "\"\"\"",
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "javascript": LanguageGrammar(
            keywords: [
                "async", "await", "break", "case", "catch", "class", "const", "continue",
                "debugger", "default", "delete", "do", "else", "export", "extends", "false",
                "finally", "for", "from", "function", "get", "if", "import", "in", "instanceof",
                "let", "new", "null", "of", "return", "set", "static", "super", "switch",
                "this", "throw", "true", "try", "typeof", "undefined", "var", "void",
                "while", "with", "yield", "arguments", "prototype"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'", "`"]
        ),

        "typescript": LanguageGrammar(
            keywords: [
                "abstract", "any", "as", "async", "await", "boolean", "break", "case",
                "catch", "class", "const", "continue", "declare", "default", "delete",
                "do", "else", "enum", "export", "extends", "false", "finally", "for",
                "from", "function", "get", "if", "implements", "import", "in", "infer",
                "instanceof", "interface", "is", "keyof", "let", "namespace", "never",
                "new", "null", "number", "object", "of", "override", "private", "protected",
                "public", "readonly", "return", "satisfies", "set", "static", "string",
                "super", "switch", "symbol", "this", "throw", "true", "try", "type",
                "typeof", "undefined", "unique", "unknown", "var", "void", "while", "with",
                "yield"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'", "`"],
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "python": LanguageGrammar(
            keywords: [
                "False", "None", "True", "and", "as", "assert", "async", "await",
                "break", "class", "continue", "def", "del", "elif", "else", "except",
                "finally", "for", "from", "global", "if", "import", "in", "is",
                "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try",
                "while", "with", "yield", "self", "cls", "print", "range", "len",
                "type", "isinstance", "hasattr", "getattr", "setattr", "super"
            ],
            lineCommentPrefix: "#",
            stringDelimiters: ["\"", "'"],
            multilineStringDelimiter: "\"\"\"",
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "json": LanguageGrammar(
            keywords: ["true", "false", "null"],
            stringDelimiters: ["\""]
        ),

        "html": LanguageGrammar(
            keywords: [],
            blockCommentStart: "<!--",
            blockCommentEnd: "-->",
            stringDelimiters: ["\"", "'"]
        ),

        "css": LanguageGrammar(
            keywords: [
                "important", "inherit", "initial", "unset", "revert", "auto", "none",
                "normal", "bold", "italic", "underline", "relative", "absolute", "fixed",
                "sticky", "static", "block", "flex", "grid", "inline", "inline-block",
                "inline-flex", "inline-grid", "hidden", "visible", "collapse", "solid",
                "dashed", "dotted", "double", "center", "left", "right", "top", "bottom",
                "transparent", "currentColor"
            ],
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"],
            caseInsensitiveKeywords: true
        ),

        "sql": LanguageGrammar(
            keywords: [
                "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
                "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "ADD", "COLUMN", "INDEX",
                "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "FULL", "CROSS", "ON",
                "AND", "OR", "NOT", "NULL", "IS", "IN", "LIKE", "BETWEEN", "EXISTS",
                "DISTINCT", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "AS",
                "WITH", "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END",
                "DECLARE", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "IF", "WHILE",
                "RETURN", "VARCHAR", "INT", "INTEGER", "BIGINT", "SMALLINT", "FLOAT",
                "DOUBLE", "DECIMAL", "BOOLEAN", "TEXT", "DATE", "TIMESTAMP", "PRIMARY",
                "KEY", "FOREIGN", "REFERENCES", "UNIQUE", "DEFAULT", "CONSTRAINT",
                "TRIGGER", "VIEW", "PROCEDURE", "FUNCTION", "DATABASE", "SCHEMA",
                "GRANT", "REVOKE", "SHOW", "USE", "DESCRIBE", "EXPLAIN", "TRUNCATE"
            ],
            lineCommentPrefix: "--",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"],
            caseInsensitiveKeywords: true
        ),

        "go": LanguageGrammar(
            keywords: [
                "break", "case", "chan", "const", "continue", "default", "defer",
                "else", "fallthrough", "for", "func", "go", "goto", "if", "import",
                "interface", "map", "package", "range", "return", "select", "struct",
                "switch", "type", "var", "nil", "true", "false", "iota",
                "append", "cap", "close", "copy", "delete", "imag", "len", "make",
                "new", "panic", "print", "println", "real", "recover",
                "int", "int8", "int16", "int32", "int64",
                "uint", "uint8", "uint16", "uint32", "uint64", "uintptr",
                "float32", "float64", "complex64", "complex128",
                "byte", "rune", "string", "bool", "error", "any", "comparable"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "`"],
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "rust": LanguageGrammar(
            keywords: [
                "as", "async", "await", "break", "const", "continue", "crate", "dyn",
                "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in",
                "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
                "self", "Self", "static", "struct", "super", "trait", "true", "type",
                "unsafe", "use", "where", "while", "abstract", "become", "box", "do",
                "final", "macro", "override", "priv", "try", "typeof", "unsized",
                "virtual", "yield",
                "i8", "i16", "i32", "i64", "i128", "isize",
                "u8", "u16", "u32", "u64", "u128", "usize",
                "f32", "f64", "bool", "char", "str"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\""],
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "kotlin": LanguageGrammar(
            keywords: [
                "abstract", "actual", "as", "break", "by", "catch", "class", "companion",
                "const", "constructor", "continue", "crossinline", "data", "do", "dynamic",
                "else", "enum", "expect", "external", "false", "final", "finally", "for",
                "fun", "get", "if", "import", "in", "infix", "init", "inline", "inner",
                "interface", "internal", "is", "it", "lateinit", "noinline", "null",
                "object", "open", "operator", "out", "override", "package", "private",
                "protected", "public", "reified", "return", "sealed", "set", "super",
                "suspend", "tailrec", "this", "throw", "true", "try", "typealias",
                "val", "var", "vararg", "when", "where", "while"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\""],
            multilineStringDelimiter: "\"\"\"",
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "java": LanguageGrammar(
            keywords: [
                "abstract", "assert", "boolean", "break", "byte", "case", "catch",
                "char", "class", "const", "continue", "default", "do", "double",
                "else", "enum", "extends", "final", "finally", "float", "for", "goto",
                "if", "implements", "import", "instanceof", "int", "interface", "long",
                "native", "new", "null", "package", "private", "protected", "public",
                "return", "short", "static", "strictfp", "super", "switch",
                "synchronized", "this", "throw", "throws", "transient", "true", "try",
                "var", "void", "volatile", "while", "sealed", "record", "permits"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\""],
            multilineStringDelimiter: "\"\"\"",
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "c": LanguageGrammar(
            keywords: [
                "auto", "break", "case", "char", "const", "continue", "default", "do",
                "double", "else", "enum", "extern", "float", "for", "goto", "if",
                "inline", "int", "long", "register", "restrict", "return", "short",
                "signed", "sizeof", "static", "struct", "switch", "typedef", "union",
                "unsigned", "void", "volatile", "while", "NULL", "true", "false",
                "_Bool", "_Complex", "_Imaginary"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"]
        ),

        "cpp": LanguageGrammar(
            keywords: [
                "alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand",
                "bitor", "bool", "break", "case", "catch", "char", "char8_t",
                "char16_t", "char32_t", "class", "compl", "concept", "const",
                "consteval", "constexpr", "constinit", "const_cast", "continue",
                "co_await", "co_return", "co_yield", "decltype", "default", "delete",
                "do", "double", "dynamic_cast", "else", "enum", "explicit", "export",
                "extern", "false", "float", "for", "friend", "goto", "if", "inline",
                "int", "long", "mutable", "namespace", "new", "noexcept", "not",
                "not_eq", "nullptr", "operator", "or", "or_eq", "override", "private",
                "protected", "public", "register", "reinterpret_cast", "requires",
                "return", "short", "signed", "sizeof", "static", "static_assert",
                "static_cast", "struct", "switch", "template", "this", "thread_local",
                "throw", "true", "try", "typedef", "typeid", "typename", "union",
                "unsigned", "using", "virtual", "void", "volatile", "wchar_t",
                "while", "xor", "xor_eq", "NULL"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"],
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "bash": LanguageGrammar(
            keywords: [
                "if", "then", "else", "elif", "fi", "for", "do", "done", "while",
                "until", "case", "esac", "function", "in", "select", "time",
                "local", "return", "exit", "echo", "printf", "read", "break",
                "continue", "shift", "source", "export", "unset", "set", "declare",
                "readonly", "true", "false", "let", "test", "alias", "unalias",
                "cd", "pwd", "ls", "mkdir", "rm", "cp", "mv", "cat", "grep",
                "awk", "sed", "sort", "uniq", "wc", "curl", "wget", "chmod", "chown"
            ],
            lineCommentPrefix: "#",
            stringDelimiters: ["\"", "'"]
        ),

        "ruby": LanguageGrammar(
            keywords: [
                "BEGIN", "END", "__ENCODING__", "__END__", "__FILE__", "__LINE__",
                "alias", "and", "begin", "break", "case", "class", "def", "defined?",
                "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in",
                "module", "next", "nil", "not", "or", "redo", "rescue", "retry",
                "return", "self", "super", "then", "true", "undef", "unless",
                "until", "when", "while", "yield", "raise", "require", "include",
                "extend", "attr_accessor", "attr_reader", "attr_writer", "puts", "print"
            ],
            lineCommentPrefix: "#",
            stringDelimiters: ["\"", "'"],
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "php": LanguageGrammar(
            keywords: [
                "__CLASS__", "__DIR__", "__FILE__", "__FUNCTION__", "__LINE__",
                "__METHOD__", "__NAMESPACE__", "__TRAIT__", "abstract", "and", "array",
                "as", "break", "callable", "case", "catch", "class", "clone", "const",
                "continue", "declare", "default", "die", "do", "echo", "else", "elseif",
                "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch",
                "endwhile", "eval", "exit", "extends", "final", "finally", "fn", "for",
                "foreach", "function", "global", "goto", "if", "implements", "include",
                "include_once", "instanceof", "insteadof", "interface", "isset", "list",
                "match", "namespace", "new", "or", "print", "private", "protected",
                "public", "readonly", "require", "require_once", "return", "static",
                "switch", "throw", "trait", "try", "unset", "use", "var", "while",
                "xor", "yield", "null", "true", "false", "NULL", "TRUE", "FALSE"
            ],
            lineCommentPrefix: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"],
            typePattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
        ),

        "yaml": LanguageGrammar(
            keywords: ["true", "false", "null", "yes", "no", "on", "off", "~"],
            lineCommentPrefix: "#",
            stringDelimiters: ["\"", "'"]
        ),

        "xml": LanguageGrammar(
            keywords: [],
            blockCommentStart: "<!--",
            blockCommentEnd: "-->",
            stringDelimiters: ["\"", "'"]
        ),

        "markdown": LanguageGrammar(
            keywords: []
        ),
    ]
}
