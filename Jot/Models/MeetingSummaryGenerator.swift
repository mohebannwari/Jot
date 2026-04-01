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
import NaturalLanguage
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

        // Step 3: Final summarization pass with merged content, transcript excerpt for grounding, + manual notes
        var finalResult = try await generateFinalSummary(
            mergedContent: merged,
            rawTranscript: transcript,
            manualNotes: manualNotes
        )

        // Step 4: Validate grounding — score each generated item against the raw transcript
        finalResult.grounding = validateGrounding(result: finalResult, transcript: transcript)

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
    var grounding: GroundingInfo?
}

/// Per-item grounding scores (0.0-1.0) indicating how well each generated
/// item is supported by the raw transcript. Parallel arrays to the display result.
struct GroundingInfo {
    var keyPointScores: [Double]
    var actionItemScores: [Double]
    var decisionScores: [Double]
}

// MARK: - Chunking

extension MeetingSummaryGenerator {
    /// Split transcript into chunks at sentence boundaries using NLTokenizer,
    /// each roughly within the target size. Adjacent chunks share 1-2 trailing
    /// sentences as labeled context overlap to prevent mid-thought truncation.
    private func chunkTranscript(_ text: String) -> [String] {
        let maxSize = Self.chunkSizeChars

        if text.count <= maxSize {
            return [text]
        }

        // Use NLTokenizer for robust sentence boundary detection
        // (handles ?, !, abbreviations like "Dr.", ellipses, Unicode breaks)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }

        // Build chunks from sentences
        var rawChunks: [String] = []
        var currentChunk = ""

        for sentence in sentences {
            let candidate = currentChunk + sentence
            if candidate.count > maxSize && !currentChunk.isEmpty {
                rawChunks.append(currentChunk)
                currentChunk = sentence
            } else {
                currentChunk = candidate
            }
        }
        if !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawChunks.append(currentChunk)
        }

        guard rawChunks.count > 1 else { return rawChunks }

        // Add trailing overlap from previous chunk for context continuity.
        // The per-chunk prompt instructs the model not to extract points from this context.
        var overlappedChunks = rawChunks
        for i in 1..<overlappedChunks.count {
            let prevSentences = lastSentences(from: rawChunks[i - 1], count: 2)
            if !prevSentences.isEmpty {
                overlappedChunks[i] = "[Context from previous segment: \(prevSentences)]\n\n" + overlappedChunks[i]
            }
        }

        return overlappedChunks
    }

    /// Extract the last N sentences from a chunk for overlap context.
    private func lastSentences(from text: String, count: Int) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        return sentences.suffix(count).joined().trimmingCharacters(in: .whitespacesAndNewlines)
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
            Every point must be directly supported by words in the transcript. \
            When uncertain whether something was explicitly stated, omit it. \
            An incomplete-but-accurate summary is always better than a complete-but-fabricated one. \
            Text in [Context from previous segment: ...] is provided for continuity only — \
            do not extract key points, action items, or decisions from it.
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

    private func generateFinalSummary(mergedContent: String, rawTranscript: String, manualNotes: String) async throws -> MeetingSummaryDisplayResult {
        // Build the prompt with clearly separated sections.
        // Include a raw transcript excerpt so the model can cross-check against actual spoken words.
        let instructionOverhead = 1500 // chars reserved for system instruction + schema
        let maxPromptChars = Self.chunkSizeChars * Self.charsPerToken // ~12,000 chars usable
        let notesText = manualNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerptBudget = max(0, maxPromptChars - mergedContent.count - notesText.count - instructionOverhead)

        var prompt = ""

        // Section A: Raw transcript excerpt for grounding (if budget allows)
        if excerptBudget >= 500 {
            let excerpt = buildTranscriptExcerpt(rawTranscript, budgetChars: excerptBudget)
            prompt += "ORIGINAL TRANSCRIPT EXCERPTS (for verification — these are the actual spoken words):\n\(excerpt)\n\n"
        }

        // Section B: Transcript-derived intermediate notes (primary source)
        prompt += "TRANSCRIPT-DERIVED NOTES (primary source — all summary content must come from here):\n\(mergedContent)"

        // Section C: Manual notes (supplementary only)
        if !notesText.isEmpty {
            prompt += "\n\nUSER'S PERSONAL NOTES (supplementary context only — do NOT generate action items, decisions, or key points solely from these):\n\(notesText)"
        }

        let session = LanguageModelSession(
            instructions: """
            You are creating the final summary of a meeting. Synthesize ONLY the TRANSCRIPT-DERIVED NOTES. \
            Cross-check every point against the ORIGINAL TRANSCRIPT EXCERPTS when available. \
            If a point in the intermediate notes cannot be verified against the transcript, omit it. \
            Remove duplicates and consolidate related points. \
            The title must use only words and topics from the transcript. \
            Do not invent attendee names, dates, or details not in the source material. \
            USER'S PERSONAL NOTES provide supplementary context only — they must not introduce \
            new action items, decisions, or key points not also present in the transcript-derived notes. \
            If the input is sparse, produce a short summary rather than fabricating content. \
            When uncertain whether something was explicitly stated, omit it.
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

    /// Build a transcript excerpt from the start, middle, and end of the raw transcript,
    /// fitting within the given character budget. Provides grounding material for the
    /// final synthesis stage to verify intermediate summary points.
    private func buildTranscriptExcerpt(_ transcript: String, budgetChars: Int) -> String {
        guard transcript.count > budgetChars else { return transcript }

        let thirdBudget = budgetChars / 3
        let startEnd = transcript.prefix(thirdBudget)

        let midStart = transcript.index(transcript.startIndex, offsetBy: max(0, transcript.count / 2 - thirdBudget / 2))
        let midEnd = transcript.index(midStart, offsetBy: min(thirdBudget, transcript.distance(from: midStart, to: transcript.endIndex)))
        let middle = transcript[midStart..<midEnd]

        let tailStart = transcript.index(transcript.endIndex, offsetBy: -min(thirdBudget, transcript.count))
        let end = transcript[tailStart...]

        return "\(startEnd)\n[...]\n\(middle)\n[...]\n\(end)"
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

// MARK: - Grounding Validation

extension MeetingSummaryGenerator {

    private static let stopWords: Set<String> = [
        "the", "a", "an", "is", "was", "were", "are", "to", "of", "in", "for",
        "on", "with", "at", "by", "this", "that", "it", "and", "or", "but",
        "we", "they", "he", "she", "will", "be", "have", "has", "had", "do",
        "did", "not", "so", "if", "about", "from", "as", "can", "would",
        "should", "could", "their", "our", "your", "its", "been", "being",
        "also", "just", "very", "more", "some", "all", "any", "each", "than"
    ]

    /// Score how well each generated item is grounded in the raw transcript.
    /// Returns a GroundingInfo with parallel arrays of scores (0.0-1.0).
    func validateGrounding(result: MeetingSummaryDisplayResult, transcript: String) -> GroundingInfo {
        let transcriptWords = significantWords(from: transcript)

        let keyPointScores = result.keyPoints.map { overlapScore(for: $0, against: transcriptWords) }
        let actionItemScores = result.actionItems.map { overlapScore(for: $0.description, against: transcriptWords) }
        let decisionScores = result.decisions.map { overlapScore(for: $0, against: transcriptWords) }

        return GroundingInfo(
            keyPointScores: keyPointScores,
            actionItemScores: actionItemScores,
            decisionScores: decisionScores
        )
    }

    /// Extract significant (non-stop) words from text, lowercased.
    private func significantWords(from text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        return Set(words)
    }

    /// Fraction of significant words in `item` that appear in `transcriptWords`.
    private func overlapScore(for item: String, against transcriptWords: Set<String>) -> Double {
        let itemWords = significantWords(from: item)
        guard !itemWords.isEmpty else { return 1.0 }
        let matched = itemWords.filter { transcriptWords.contains($0) }.count
        return Double(matched) / Double(itemWords.count)
    }
}
