//
//  MeetingModels.swift
//  Jot
//
//  Data types for AI Meeting Notes — transcript segments, chunked summary
//  intermediates, and the final structured meeting summary.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Transcript Segment

/// A single segment of transcribed speech from a meeting recording.
struct TranscriptSegment: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var timestamp: TimeInterval      // seconds from recording start
    var isFinal: Bool                // false while speech recognizer is refining

    init(id: UUID = UUID(), text: String, timestamp: TimeInterval, isFinal: Bool = false) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
    }
}

// MARK: - Meeting Recording State

enum MeetingRecordingState: Equatable {
    case idle
    case recording
    case paused
    case processing       // recording stopped, AI summarizing
    case complete         // summary ready
}

// MARK: - Meeting Tab

enum MeetingTab: String, CaseIterable, Identifiable {
    case summary
    case transcript
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .summary: return "Summary"
        case .transcript: return "Transcript"
        case .notes: return "Notes"
        }
    }
}

// MARK: - Meeting Session

/// A single meeting recording session attached to a note.
/// Multiple sessions accumulate when the user records additional meetings on the same note.
struct MeetingSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var summary: String = ""
    var transcript: String = ""
    var duration: TimeInterval = 0
    var language: String = ""
    var manualNotes: String = ""
}

// MARK: - Generable Types for FoundationModels

#if canImport(FoundationModels)

@available(macOS 26.0, *)
@Generable
struct MeetingChunkSummary {
    @Guide(description: "Key points ONLY from words explicitly spoken in this excerpt. Each point must use vocabulary from the transcript. Empty array if no key points are explicitly stated.")
    var keyPoints: [String]
    @Guide(description: "Action items explicitly mentioned as tasks in the transcript, each with assignee if stated. Do not promote discussion topics into action items. Empty if none mentioned.")
    var actionItems: [MeetingActionItem]
    @Guide(description: "Decisions explicitly stated in this excerpt. Empty array if none mentioned.")
    var decisions: [String]
}

@available(macOS 26.0, *)
@Generable
struct MeetingActionItem {
    @Guide(description: "What needs to be done — use the speaker's own words where possible")
    var taskDescription: String
    @Guide(description: "ONLY use a name explicitly spoken in the transcript as the assignee for this specific task. Use 'Unassigned' if no specific person was named for this task.")
    var assignee: String
}

@available(macOS 26.0, *)
@Generable
struct MeetingSummaryResult {
    @Guide(description: "A short title (under 10 words) using only words and topics that appear in the transcript. Do not add descriptive words not spoken.")
    var title: String
    @Guide(description: "2-4 sentence summary using only information from the input. Every claim must be traceable to specific input text. If input is sparse, write 1 sentence rather than padding.")
    var summary: String
    @Guide(description: "Key points from the meeting, each directly supported by the transcript. Each must use vocabulary from the source. Do not infer or add points not spoken.")
    var keyPoints: [String]
    @Guide(description: "Action items explicitly stated in the meeting as tasks to be done. Do not fabricate tasks or promote discussion topics into action items.")
    var actionItems: [MeetingActionItem]
    @Guide(description: "Decisions explicitly made during the meeting. Empty if none stated.")
    var decisions: [String]
}

#endif

// MARK: - Serialization Helpers

extension Array where Element == TranscriptSegment {
    /// Serialize transcript segments to a storable string format.
    /// Format: each line is `timestamp|text` where timestamp is seconds with 1 decimal.
    func serialized() -> String {
        map { segment in
            let ts = String(format: "%.1f", segment.timestamp)
            let escapedText = segment.text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\(ts)|\(escapedText)"
        }.joined(separator: "\n")
    }

    /// Deserialize transcript segments from stored string.
    static func deserialized(from string: String) -> [TranscriptSegment] {
        guard !string.isEmpty else { return [] }
        return string.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2,
                  let timestamp = TimeInterval(parts[0])
            else { return nil }
            let unescapedText = String(parts[1])
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\\", with: "\\")
            return TranscriptSegment(
                text: unescapedText,
                timestamp: timestamp,
                isFinal: true
            )
        }
    }

    /// Plain text transcript for AI processing (no timestamps, all segments).
    func plainText() -> String {
        map(\.text)
            .joined(separator: " ")
    }
}
