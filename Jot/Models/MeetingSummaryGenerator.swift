//
//  MeetingSummaryGenerator.swift
//  Jot
//
//  Chunked summarization pipeline for meeting transcripts.
//  Splits transcript into segments that fit within FoundationModels' 4K token
//  context window, summarizes each chunk, then merges into a final structured
//  meeting summary with rich text formatting.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class MeetingSummaryGenerator {

    /// Approximate characters per token for the on-device model.
    private static let charsPerToken: Int = 4

    /// Target chunk size in characters (~750 tokens, leaving room for
    /// instructions + output in the 4K window).
    private static let chunkSizeChars: Int = 3000

    // MARK: - Public API

    /// Generate a structured meeting summary from transcript segments and optional manual notes.
    /// Returns the formatted rich text string for display and persistence.
    func generateSummary(
        from segments: [TranscriptSegment],
        manualNotes: String = ""
    ) async throws -> (result: MeetingSummaryDisplayResult, richText: String) {
        let transcript = segments.plainText()

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let empty = MeetingSummaryDisplayResult(
                title: "Meeting Notes",
                summary: "No speech was detected during this recording.",
                keyPoints: [],
                actionItems: [],
                decisions: []
            )
            return (empty, formatAsRichText(empty))
        }

        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            throw AIServiceError.unavailable("Apple Intelligence requires macOS 26 or later.")
        }
        guard AppleIntelligenceService.shared.isAvailable else {
            throw AIServiceError.unavailable(AppleIntelligenceService.shared.unavailabilityReason)
        }

        let chunks = chunkTranscript(transcript)

        // Step 1: Summarize each chunk
        var chunkSummaries: [ChunkSummaryText] = []
        for (index, chunk) in chunks.enumerated() {
            let summary = try await summarizeChunk(chunk, index: index + 1, total: chunks.count)
            chunkSummaries.append(summary)
        }

        // Step 2: Merge chunk summaries into final result
        let merged = mergeChunkSummaries(chunkSummaries)

        // Step 3: Final summarization pass with merged content + manual notes
        let finalResult = try await generateFinalSummary(mergedContent: merged, manualNotes: manualNotes)

        return (finalResult, formatAsRichText(finalResult))
        #else
        throw AIServiceError.unavailable("Apple Intelligence requires macOS 26 or later.")
        #endif
    }
}

// MARK: - Display Result (non-Generable, for UI consumption)

struct MeetingSummaryDisplayResult {
    var title: String
    var summary: String
    var keyPoints: [String]
    var actionItems: [(description: String, assignee: String)]
    var decisions: [String]
}

// MARK: - Chunking

extension MeetingSummaryGenerator {
    /// Split transcript into chunks at sentence boundaries, each roughly within the target size.
    private func chunkTranscript(_ text: String) -> [String] {
        let maxSize = Self.chunkSizeChars

        // If short enough, single chunk
        if text.count <= maxSize {
            return [text]
        }

        var chunks: [String] = []
        var currentChunk = ""

        // Split on sentence boundaries (period + space, or newline)
        let sentences = text.components(separatedBy: ". ")

        for sentence in sentences {
            let candidate = currentChunk.isEmpty ? sentence : currentChunk + ". " + sentence

            if candidate.count > maxSize && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = sentence
            } else {
                currentChunk = candidate
            }
        }

        if !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }
}

// MARK: - Per-Chunk Summarization

#if canImport(FoundationModels)
private struct ChunkSummaryText {
    var keyPoints: [String]
    var actionItems: [(description: String, assignee: String)]
    var decisions: [String]
}

@available(macOS 26.0, *)
extension MeetingSummaryGenerator {
    private func summarizeChunk(_ chunk: String, index: Int, total: Int) async throws -> ChunkSummaryText {
        let session = LanguageModelSession(
            instructions: """
            You are analyzing a meeting transcript excerpt (\(index) of \(total)). \
            Extract ONLY information explicitly stated in the transcript. \
            Do not infer topics not discussed. Do not fabricate action items, decisions, or attendee names. \
            If nothing relevant is found in a category, leave that array empty. \
            Every point must be directly supported by words in the transcript.
            """
        )

        let response = try await session.respond(
            to: "Extract only what is explicitly said in this transcript excerpt. Do not add anything not present:\n\n\(chunk)",
            generating: MeetingChunkSummary.self
        )

        return ChunkSummaryText(
            keyPoints: response.content.keyPoints,
            actionItems: response.content.actionItems.map { ($0.taskDescription, $0.assignee) },
            decisions: response.content.decisions
        )
    }

    private func mergeChunkSummaries(_ summaries: [ChunkSummaryText]) -> String {
        var merged = "KEY POINTS:\n"
        for summary in summaries {
            for point in summary.keyPoints {
                merged += "- \(point)\n"
            }
        }
        merged += "\nACTION ITEMS:\n"
        for summary in summaries {
            for item in summary.actionItems {
                merged += "- \(item.description) (Assignee: \(item.assignee))\n"
            }
        }
        merged += "\nDECISIONS:\n"
        for summary in summaries {
            for decision in summary.decisions {
                merged += "- \(decision)\n"
            }
        }
        return merged
    }

    private func generateFinalSummary(mergedContent: String, manualNotes: String) async throws -> MeetingSummaryDisplayResult {
        var prompt = "Create a final meeting summary from these intermediate notes:\n\n\(mergedContent)"
        if !manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\nAdditional context from manual notes taken during the meeting:\n\(manualNotes)"
        }

        let session = LanguageModelSession(
            instructions: """
            You are creating the final summary of a meeting. Synthesize ONLY the provided notes — \
            do not add information not present in the input. Remove duplicates and consolidate \
            related points. The title must reflect a topic actually discussed. \
            Do not invent attendee names, dates, or details not in the source material. \
            If the input is sparse, produce a short summary rather than fabricating content.
            """
        )

        let response = try await session.respond(
            to: prompt,
            generating: MeetingSummaryResult.self
        )

        let result = response.content
        return MeetingSummaryDisplayResult(
            title: result.title,
            summary: result.summary,
            keyPoints: result.keyPoints,
            actionItems: result.actionItems.map { ($0.taskDescription, $0.assignee) },
            decisions: result.decisions
        )
    }
}
#endif

// MARK: - Rich Text Formatting

extension MeetingSummaryGenerator {
    /// Format summary into Jot's rich text serialization format.
    func formatAsRichText(_ result: MeetingSummaryDisplayResult) -> String {
        var output = ""

        // Title
        output += "[[h1]]\(result.title)[[/h1]]\n\n"

        // Summary
        if !result.summary.isEmpty {
            output += "[[h2]]Summary[[/h2]]\n"
            output += result.summary + "\n\n"
        }

        // Key Points
        if !result.keyPoints.isEmpty {
            output += "[[h2]]Key Points[[/h2]]\n"
            for point in result.keyPoints {
                output += "- \(point)\n"
            }
            output += "\n"
        }

        // Action Items (as to-do checkboxes)
        if !result.actionItems.isEmpty {
            output += "[[h2]]Action Items[[/h2]]\n"
            for item in result.actionItems {
                let assignee = item.assignee == "Unassigned" ? "" : " (\(item.assignee))"
                output += "[ ] \(item.description)\(assignee)\n"
            }
            output += "\n"
        }

        // Decisions
        if !result.decisions.isEmpty {
            output += "[[h2]]Decisions[[/h2]]\n"
            for decision in result.decisions {
                output += "- \(decision)\n"
            }
        }

        return output.trimmingCharacters(in: .newlines)
    }
}
