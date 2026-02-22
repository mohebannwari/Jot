//
//  AppleIntelligenceService.swift
//  Jot
//
//  On-device Foundation Models wrapper for Apple Intelligence writing tools.
//  Requires macOS 26+ with Apple Intelligence enabled.
//

import SwiftUI
import FoundationModels

// MARK: - AI Tool Enum

enum AITool: String, Equatable {
    case summary
    case keyPoints
    case proofread
    case editContent
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
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Structured Output Types

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

// MARK: - Service

@MainActor
final class AppleIntelligenceService {
    static let shared = AppleIntelligenceService()

    private init() {}

    var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var unavailabilityReason: String {
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
    }

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
