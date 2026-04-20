//
//  AppleIntelligenceService.swift
//  Jot
//
//  On-device Foundation Models wrapper for Apple Intelligence writing tools.
//  Requires macOS 26+ with Apple Intelligence enabled.
//

import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI Tool Enum

enum AITool: String, Equatable {
    case summary
    case keyPoints
    case proofread
    case editContent
    case translate
    case textGenerate
    case meetingNotes
}

// MARK: - Proofread Models

struct ProofreadSuggestion: Equatable {
    let original: String
    let replacement: String
}

struct ProofreadAnnotation: Identifiable, Equatable {
    let id: UUID = UUID()
    let original: String
    let replacement: String
    let range: NSRange
}

// MARK: - AI Panel State

enum AIPanelState: Equatable {
    case none
    case loading(AITool)
    case summary(String)
    case keyPoints([String])
    case proofread([ProofreadAnnotation])
    case editPreview(
        revised: String,
        originalRange: NSRange,
        originalText: String,
        instruction: String
    )
    case translatePreview(
        translated: String,
        originalRange: NSRange,
        originalText: String,
        language: String
    )
    case textGenPreview(
        generated: String,
        insertionPoint: Int
    )
    case error(String)

    static func == (lhs: AIPanelState, rhs: AIPanelState) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.loading(let a), .loading(let b)): return a == b
        case (.summary(let a), .summary(let b)): return a == b
        case (.keyPoints(let a), .keyPoints(let b)): return a == b
        case (.proofread(let a), .proofread(let b)): return a == b
        case (
            .editPreview(let r1, let or1, let ot1, let i1),
            .editPreview(let r2, let or2, let ot2, let i2)
        ):
            return r1 == r2 && or1 == or2 && ot1 == ot2 && i1 == i2
        case (
            .translatePreview(let t1, let or1, let ot1, let l1),
            .translatePreview(let t2, let or2, let ot2, let l2)
        ):
            return t1 == t2 && or1 == or2 && ot1 == ot2 && l1 == l2
        case (
            .textGenPreview(let g1, let ip1),
            .textGenPreview(let g2, let ip2)
        ):
            return g1 == g2 && ip1 == ip2
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Structured Output Types

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct SummaryResult {
    @Guide(description: "A concise 2-4 sentence summary of the note")
    var text: String
}

@available(macOS 26.0, *)
@Generable
struct KeyPointsResult {
    @Guide(description: "3-5 high-level takeaways that capture the main themes of the note. Consolidate related sub-points into single key points rather than listing every line.")
    var points: [String]
}

@available(macOS 26.0, *)
@Generable
struct ProofreadAnnotationsResult {
    @Guide(description: "Specific corrections needed. Empty array if text is error-free.")
    var annotations: [ProofreadAnnotationItem]
}

@available(macOS 26.0, *)
@Generable
struct ProofreadAnnotationItem {
    @Guide(description: "Exact character-for-character substring from the input text that contains the error")
    var original: String
    @Guide(description: "Corrected replacement for the error")
    var replacement: String
}

@available(macOS 26.0, *)
@Generable
struct EditResult {
    @Guide(description: "Full text after applying the user's editing instruction")
    var revisedText: String
}

@available(macOS 26.0, *)
@Generable
struct TranslationResult {
    @Guide(description: "The translated text in the requested target language")
    var translatedText: String
}

@available(macOS 26.0, *)
@Generable
struct TextGenerationResult {
    @Guide(description: "An expanded, well-written paragraph that elaborates on the user's idea. Must contain substantially more detail and new content beyond the input.")
    var generatedText: String
}
#endif

// MARK: - Service

@MainActor
final class AppleIntelligenceService {
    static let shared = AppleIntelligenceService()

    private init() {}

    // NOTE: Task cancellation is managed by the calling view (NoteDetailView),
    // not by this singleton service. The view stores the Task handle and cancels
    // it on note switch. Service methods respect cooperative cancellation via
    // Task.checkCancellation() before expensive operations.

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    var unavailabilityReason: String {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return "Apple Intelligence requires macOS 26 or later."
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return ""
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Apple Intelligence requires Apple Silicon."
            case .appleIntelligenceNotEnabled:
                return "Enable Apple Intelligence in System Settings > Apple Intelligence & Siri."
            case .modelNotReady:
                return "Apple Intelligence model is downloading. Try again shortly."
            @unknown default:
                return "Apple Intelligence is not available on this device."
            }
        @unknown default:
            return "Apple Intelligence availability is unknown."
        }
        #else
        return "Apple Intelligence requires macOS 26 or later."
        #endif
    }

    // MARK: - Markup Stripping

    // Pre-compiled regex patterns for stripMarkupForAI — compiled once at class load time,
    // not on every call. Patterns that span newlines use .dotMatchesLineSeparators so that
    // `.*?` and similar quantifiers cross line boundaries (matching the original [\s\S]*? intent).
    private static let aiBlockRegex = try! NSRegularExpression(
        pattern: #"\[\[ai-block\]\].*?\[\[/ai-block\]\]"#,
        options: .dotMatchesLineSeparators)
    private static let tableRegex = try! NSRegularExpression(
        pattern: #"\[\[table\|[^\]]*\]\][\s\S]*?\[\[/table\]\]"#,
        options: .dotMatchesLineSeparators)
    private static let calloutOpenRegex = try! NSRegularExpression(
        pattern: #"\[\[callout\|[^\]]*\]\]"#)
    private static let codeblockOpenRegex = try! NSRegularExpression(
        pattern: #"\[\[codeblock\|[^\]]*\]\]"#)
    private static let webclipRegex = try! NSRegularExpression(
        pattern: #"\[\[webclip\|([^|]*)\|[^|]*\|([^\]]*)\]\]"#)
    private static let notelinkRegex = try! NSRegularExpression(
        pattern: #"\[\[notelink\|[^|]*\|([^\]]*)\]\]"#)
    private static let linkRegex = try! NSRegularExpression(
        pattern: #"\[\[link\|([^\]]*)\]\]"#)
    private static let fileRegex = try! NSRegularExpression(
        pattern: #"\[\[file\|[^|]*\|[^|]*\|([^\]]*)\]\]"#)
    private static let fileLinkRegex = try! NSRegularExpression(
        pattern: #"\[\[filelink\|[^|]*\|([^|]*)\|[^\]]*\]\]"#)
    private static let imageRegex = try! NSRegularExpression(
        pattern: #"\[\[image\|\|\|[^\]]*\]\]"#)
    private static let orderedListRegex = try! NSRegularExpression(
        pattern: #"\[\[ol\|(\d+)\]\]"#)
    private static let alignRegex = try! NSRegularExpression(
        pattern: #"\[\[align:(center|right|justify)\]\]"#)
    private static let colorRegex = try! NSRegularExpression(
        pattern: #"\[\[color\|[0-9a-fA-F]{6}\]\]"#)
    private static let highlightRegex = try! NSRegularExpression(
        pattern: #"\[\[hl\|[0-9a-fA-F]{6}\]\]"#)
    private static let multiNewlineRegex = try! NSRegularExpression(
        pattern: #"\n{3,}"#)

    /// Replaces all matches of `regex` in `string` with `template` in-place.
    private static func replaceMatches(
        of regex: NSRegularExpression, in string: inout String, with template: String
    ) {
        string = regex.stringByReplacingMatches(
            in: string, range: NSRange(string.startIndex..., in: string), withTemplate: template)
    }

    /// Strips all custom serialization markup from `editedContent`, returning
    /// clean plain text suitable for Foundation Model input.
    static func stripMarkupForAI(_ serialized: String) -> String {
        var s = serialized

        // 1. Remove AI blocks entirely
        Self.replaceMatches(of: Self.aiBlockRegex, in: &s, with: "")

        // 2. Complex embedded objects
        // Tables → placeholder
        Self.replaceMatches(of: Self.tableRegex, in: &s, with: "[Table]")
        // Callouts → keep content
        Self.replaceMatches(of: Self.calloutOpenRegex, in: &s, with: "")
        s = s.replacingOccurrences(of: "[[/callout]]", with: "")
        // Code blocks → keep code content
        Self.replaceMatches(of: Self.codeblockOpenRegex, in: &s, with: "")
        s = s.replacingOccurrences(of: "[[/codeblock]]", with: "")
        // Web clips → "TITLE (URL)"
        Self.replaceMatches(of: Self.webclipRegex, in: &s, with: "$1 ($2)")
        // Note links → title
        Self.replaceMatches(of: Self.notelinkRegex, in: &s, with: "$1")
        // Links → URL
        Self.replaceMatches(of: Self.linkRegex, in: &s, with: "$1")
        // Files → "[File: ORIGINAL]"
        Self.replaceMatches(of: Self.fileRegex, in: &s, with: "[File: $1]")
        // File links → "[File: NAME]"
        Self.replaceMatches(of: Self.fileLinkRegex, in: &s, with: "[File: $1]")
        // Images → remove entirely
        Self.replaceMatches(of: Self.imageRegex, in: &s, with: "")

        // 3. Ordered lists → "N. "
        Self.replaceMatches(of: Self.orderedListRegex, in: &s, with: "$1. ")

        // 4. Paired formatting tags — keep inner text
        let pairedTags = [
            "b", "i", "u", "s",
            "h1", "h2", "h3",
            "quote", "code",
        ]
        for tag in pairedTags {
            s = s.replacingOccurrences(of: "[[\(tag)]]", with: "")
            s = s.replacingOccurrences(of: "[[/\(tag)]]", with: "")
        }
        // Alignment tags
        Self.replaceMatches(of: Self.alignRegex, in: &s, with: "")
        s = s.replacingOccurrences(of: "[[/align]]", with: "")

        // 5. Parameterized tags: color, highlight
        Self.replaceMatches(of: Self.colorRegex, in: &s, with: "")
        s = s.replacingOccurrences(of: "[[/color]]", with: "")
        Self.replaceMatches(of: Self.highlightRegex, in: &s, with: "")
        s = s.replacingOccurrences(of: "[[/hl]]", with: "")

        // 6. Collapse multiple blank lines
        Self.replaceMatches(of: Self.multiNewlineRegex, in: &s, with: "\n\n")

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    #if canImport(FoundationModels)

    // MARK: - Input Length Limits

    /// Maximum input characters for summarize/keyPoints before truncation.
    /// ~750 tokens at ~4 chars/token, leaving room for instructions + output
    /// in the on-device model's 4K token context window.
    private static let maxInputChars: Int = 3000

    /// Truncate text to maxInputChars, appending a disclaimer if truncated.
    private static func truncateForModel(_ text: String) -> String {
        guard text.count > maxInputChars else { return text }
        let truncated = String(text.prefix(maxInputChars))
        return truncated + "\n\n[Note: The text above was truncated. The full note is longer than what could be processed.]"
    }

    func summarize(text: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let inputText = Self.truncateForModel(text)
        let session = LanguageModelSession(
            instructions: "You are a precise writing assistant. Summarize the user's note concisely and accurately. Only include information explicitly stated in the note. Do not add, infer, or embellish any details not present in the source text."
        )
        try Task.checkCancellation()
        let response = try await session.respond(
            to: "Summarize only what is explicitly written in this note:\n\n\(inputText)",
            generating: SummaryResult.self
        )
        try Task.checkCancellation()
        return response.content.text
    }

    func keyPoints(text: String) async throws -> [String] {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let inputText = Self.truncateForModel(text)
        let session = LanguageModelSession(
            instructions: "You are a precise writing assistant. Identify the 3-5 main themes or takeaways from the user's note. Consolidate related sub-points into single high-level key points. Do not list every individual line — synthesize related items together. Do not add topics not covered in the note."
        )
        try Task.checkCancellation()
        let response = try await session.respond(
            to: "Identify the main themes of this note. Consolidate related items into 3-5 high-level key points:\n\n\(inputText)",
            generating: KeyPointsResult.self
        )
        try Task.checkCancellation()
        return response.content.points
    }

    func proofread(text: String) async throws -> [ProofreadSuggestion] {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let inputText = Self.truncateForModel(text)
        let session = LanguageModelSession(
            instructions: "You are a meticulous editor. Identify only genuine grammar, spelling, and clarity errors in the provided text. Every 'original' field must be an EXACT character-for-character substring found in the input text. Do not fabricate errors that do not exist. Do not suggest stylistic rewrites. Return an empty array if the text is error-free."
        )
        try Task.checkCancellation()
        let response = try await session.respond(
            to: "Review this text and identify ONLY real errors. Each 'original' value must appear verbatim in the text below:\n\n\(inputText)",
            generating: ProofreadAnnotationsResult.self
        )
        try Task.checkCancellation()
        return response.content.annotations.map {
            ProofreadSuggestion(original: $0.original, replacement: $0.replacement)
        }
    }

    func editContent(text: String, instruction: String, isSelection: Bool = false) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let systemPrompt: String
        let userPrompt: String
        if isSelection {
            systemPrompt = """
            You are a skilled writing assistant. The user has selected a specific word or phrase \
            and wants you to apply an editing instruction to it. Return only the replacement text — \
            do not include any explanation, preamble, or surrounding context.
            """
            userPrompt = "The user selected this text: \"\(text)\"\n\nInstruction: \(instruction)\n\nReturn only the replacement text."
        } else {
            systemPrompt = "You are a skilled writing assistant. Apply the user's editing instruction precisely while preserving the note's overall structure and voice."
            userPrompt = "Apply this instruction to the note: \(instruction)\n\nNote:\n\(text)"
        }
        let session = LanguageModelSession(instructions: systemPrompt)
        try Task.checkCancellation()
        let response = try await session.respond(
            to: userPrompt,
            generating: EditResult.self
        )
        try Task.checkCancellation()
        return response.content.revisedText
    }

    func translate(text: String, to language: String, isSelection: Bool = false) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let systemPrompt: String
        let userPrompt: String
        if isSelection {
            systemPrompt = """
            You are a precise translator. The user has selected a specific word or phrase \
            and wants it translated. Return only the translated text — no explanation, \
            no preamble, no surrounding context.
            """
            userPrompt = "Translate \"\(text)\" into \(language). Return only the translation."
        } else {
            systemPrompt = "You are a precise translator. Translate the user's text into the requested language accurately while preserving tone, meaning, and formatting."
            userPrompt = "Translate this text into \(language):\n\n\(text)"
        }
        let session = LanguageModelSession(instructions: systemPrompt)
        try Task.checkCancellation()
        let response = try await session.respond(
            to: userPrompt,
            generating: TranslationResult.self
        )
        try Task.checkCancellation()
        return response.content.translatedText
    }

    func generateText(description: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        // First attempt: expansion framing (the on-device model handles
        // "expand this idea" far better than "generate text about X")
        let result = try await attemptTextGeneration(
            instruction: """
            You are a skilled writing assistant. The user will provide a short idea, topic, or \
            sentence fragment. Your task is to expand it into a well-written, detailed paragraph. \
            Add specific details, examples, and elaboration. The output must be substantially \
            longer and more detailed than the input. Do not repeat the input verbatim. \
            Return only the expanded text with no preamble or explanation.
            """,
            prompt: "Expand this idea into a detailed, well-written paragraph:\n\n\(description)"
        )

        // If the model echoed the input back, retry with a continuation framing
        if isEcho(input: description, output: result) {
            return try await attemptTextGeneration(
                instruction: """
                You are a writing assistant that continues and expands text. \
                Take the user's starting thought and write 3-5 additional sentences \
                that build on it with new information, examples, or details. \
                The response must NOT repeat the user's words. Write only new content.
                """,
                prompt: "Continue writing from this starting point. Add new sentences with new details:\n\n\(description)"
            )
        }

        return result
    }

    private func attemptTextGeneration(instruction: String, prompt: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let session = LanguageModelSession(instructions: instruction)
        try Task.checkCancellation()
        let response = try await session.respond(to: prompt, generating: TextGenerationResult.self)
        try Task.checkCancellation()
        return response.content.generatedText
    }

    /// Detect if the model echoed the input instead of generating new content.
    private func isEcho(input: String, output: String) -> Bool {
        let normIn = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normOut = output.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normOut == normIn { return true }
        // Prefix echo: output starts with input but has less than 50 chars of new content
        if normOut.hasPrefix(normIn) {
            let newContent = normOut.count - normIn.count
            if newContent < 50 { return true }
        }
        // Contained echo: input appears verbatim and output is barely longer
        if normIn.count > 20 && normOut.contains(normIn) {
            let newContent = normOut.count - normIn.count
            if newContent < 50 { return true }
        }
        return false
    }
    #else
    func summarize(text: String) async throws -> String {
        throw AIServiceError.unavailable(unavailabilityReason)
    }

    func keyPoints(text: String) async throws -> [String] {
        throw AIServiceError.unavailable(unavailabilityReason)
    }

    func proofread(text: String) async throws -> [ProofreadSuggestion] {
        throw AIServiceError.unavailable(unavailabilityReason)
    }

    func editContent(text: String, instruction: String, isSelection: Bool = false) async throws -> String {
        throw AIServiceError.unavailable(unavailabilityReason)
    }

    func translate(text: String, to language: String, isSelection: Bool = false) async throws -> String {
        throw AIServiceError.unavailable(unavailabilityReason)
    }

    func generateText(description: String) async throws -> String {
        throw AIServiceError.unavailable(unavailabilityReason)
    }
    #endif
}

// MARK: - Error

enum AIServiceError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason.isEmpty ? "Apple Intelligence is not available." : reason
        }
    }
}
