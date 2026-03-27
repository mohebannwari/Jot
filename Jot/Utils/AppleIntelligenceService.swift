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

// MARK: - Proofread Annotation

struct ProofreadAnnotation: Identifiable, Equatable {
    let id: UUID = UUID()
    let original: String
    let replacement: String
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
    @Guide(description: "3-7 key points extracted as short, punchy bullets")
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
    @Guide(description: "Exact erroneous phrase from source")
    var original: String
    @Guide(description: "Corrected replacement")
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
    @Guide(description: "The generated text based on the user's description")
    var generatedText: String
}
#endif

// MARK: - Service

@MainActor
final class AppleIntelligenceService {
    static let shared = AppleIntelligenceService()

    private init() {}

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

    /// Strips all custom serialization markup from `editedContent`, returning
    /// clean plain text suitable for Foundation Model input.
    static func stripMarkupForAI(_ serialized: String) -> String {
        var s = serialized

        // 1. Remove AI blocks entirely
        s = s.replacingOccurrences(
            of: #"\[\[ai-block\]\].*?\[\[/ai-block\]\]"#,
            with: "", options: .regularExpression)

        // 2. Complex embedded objects
        // Tables → placeholder
        s = s.replacingOccurrences(
            of: #"\[\[table\|[^\]]*\]\][\s\S]*?\[\[/table\]\]"#,
            with: "[Table]", options: .regularExpression)
        // Callouts → keep content
        s = s.replacingOccurrences(
            of: #"\[\[callout\|[^\]]*\]\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[[/callout]]", with: "")
        // Code blocks → keep code content
        s = s.replacingOccurrences(
            of: #"\[\[codeblock\|[^\]]*\]\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[[/codeblock]]", with: "")
        // Web clips → "TITLE (URL)"
        s = s.replacingOccurrences(
            of: #"\[\[webclip\|([^|]*)\|[^|]*\|([^\]]*)\]\]"#,
            with: "$1 ($2)", options: .regularExpression)
        // Note links → title
        s = s.replacingOccurrences(
            of: #"\[\[notelink\|[^|]*\|([^\]]*)\]\]"#,
            with: "$1", options: .regularExpression)
        // Links → URL
        s = s.replacingOccurrences(
            of: #"\[\[link\|([^\]]*)\]\]"#,
            with: "$1", options: .regularExpression)
        // Files → "[File: ORIGINAL]"
        s = s.replacingOccurrences(
            of: #"\[\[file\|[^|]*\|[^|]*\|([^\]]*)\]\]"#,
            with: "[File: $1]", options: .regularExpression)
        // File links → "[File: NAME]"
        s = s.replacingOccurrences(
            of: #"\[\[filelink\|[^|]*\|([^|]*)\|[^\]]*\]\]"#,
            with: "[File: $1]", options: .regularExpression)
        // Images → remove entirely
        s = s.replacingOccurrences(
            of: #"\[\[image\|\|\|[^\]]*\]\]"#,
            with: "", options: .regularExpression)

        // 3. Ordered lists → "N. "
        s = s.replacingOccurrences(
            of: #"\[\[ol\|(\d+)\]\]"#,
            with: "$1. ", options: .regularExpression)

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
        s = s.replacingOccurrences(
            of: #"\[\[align:(center|right|justify)\]\]"#,
            with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[[/align]]", with: "")

        // 5. Parameterized tags: color, highlight
        s = s.replacingOccurrences(
            of: #"\[\[color\|[0-9a-fA-F]{6}\]\]"#,
            with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[[/color]]", with: "")
        s = s.replacingOccurrences(
            of: #"\[\[hl\|[0-9a-fA-F]{6}\]\]"#,
            with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[[/hl]]", with: "")

        // 6. Collapse multiple blank lines
        s = s.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    #if canImport(FoundationModels)
    func summarize(text: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let session = LanguageModelSession(
            instructions: "You are a precise writing assistant. Summarize the user's note concisely and accurately."
        )
        let response = try await session.respond(
            to: "Summarize this note:\n\n\(text)",
            generating: SummaryResult.self
        )
        return response.content.text
    }

    func keyPoints(text: String) async throws -> [String] {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let session = LanguageModelSession(
            instructions: "You are a precise writing assistant. Extract the most important points from the user's note as short, actionable bullets."
        )
        let response = try await session.respond(
            to: "Extract the key points from this note:\n\n\(text)",
            generating: KeyPointsResult.self
        )
        return response.content.points
    }

    func proofread(text: String) async throws -> [ProofreadAnnotation] {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let session = LanguageModelSession(
            instructions: "You are a meticulous editor. Identify specific grammar, spelling, and clarity errors. Return exact erroneous phrases and their corrections. Return an empty array if the text is error-free."
        )
        let response = try await session.respond(
            to: "Find and list specific errors in this text with corrections:\n\n\(text)",
            generating: ProofreadAnnotationsResult.self
        )
        return response.content.annotations.map {
            ProofreadAnnotation(original: $0.original, replacement: $0.replacement)
        }
    }

    func editContent(text: String, instruction: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let session = LanguageModelSession(
            instructions: "You are a skilled writing assistant. Apply the user's editing instruction precisely while preserving the note's overall structure and voice."
        )
        let response = try await session.respond(
            to: "Apply this instruction to the note: \(instruction)\n\nNote:\n\(text)",
            generating: EditResult.self
        )
        return response.content.revisedText
    }

    func translate(text: String, to language: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let session = LanguageModelSession(
            instructions: "You are a precise translator. Translate the user's text into the requested language accurately while preserving tone, meaning, and formatting."
        )
        let response = try await session.respond(
            to: "Translate this text into \(language):\n\n\(text)",
            generating: TranslationResult.self
        )
        return response.content.translatedText
    }

    func generateText(description: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable(unavailabilityReason)
        }
        let session = LanguageModelSession(
            instructions: "You are a skilled writing assistant. Generate text based on the user's description. Write naturally and concisely. Return only the generated text with no preamble or explanation."
        )
        let response = try await session.respond(
            to: "Generate text for the following: \(description)",
            generating: TextGenerationResult.self
        )
        return response.content.generatedText
    }
    #else
    func summarize(text: String) async throws -> String {
        throw AIServiceError.unavailable(unavailabilityReason)
    }

    func keyPoints(text: String) async throws -> [String] {
        throw AIServiceError.unavailable(unavailabilityReason)
    }

    func proofread(text: String) async throws -> [ProofreadAnnotation] {
        throw AIServiceError.unavailable(unavailabilityReason)
    }

    func editContent(text: String, instruction: String) async throws -> String {
        throw AIServiceError.unavailable(unavailabilityReason)
    }

    func translate(text: String, to language: String) async throws -> String {
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
