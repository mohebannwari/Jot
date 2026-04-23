//
//  MeetingRecorderManager.swift
//  Jot
//
//  Shared manager for AI meeting recording. Allows the recording session to persist
//  when switching between notes. The AudioRecorder and transcription service are
//  owned here so the AVAudioEngine keeps running in the background.
//  The sidebar waveform indicator uses the published levels and recordingNoteID.
//
//  This follows the project's architecture for shared state (similar to AI cache in NoteDetailView).
//  Minimal changes to existing recorder and transcription logic.
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

@MainActor
final class MeetingRecorderManager: ObservableObject {

    private var cancellables = Set<AnyCancellable>()

    @Published var recordingNoteID: UUID? = nil
    @Published var recordingState: MeetingRecordingState = .idle
    @Published var levels: [Float] = []
    @Published var duration: TimeInterval = 0
    /// Duration captured at the moment of stopping -- the recorder resets to 0 after stop
    private(set) var recordedDuration: TimeInterval = 0
    @Published var isSummaryLoading: Bool = false
    @Published var summaryResult: MeetingSummaryDisplayResult? = nil
    @Published var manualNotes: String = ""
    @Published var selectedTab: MeetingTab = .transcript

    let audioRecorder: AudioRecorder
    let transcriptionService: MeetingTranscriptionService
    let summaryGenerator: MeetingSummaryGenerator

    init() {
        self.audioRecorder = AudioRecorder(barCount: 28)
        self.transcriptionService = MeetingTranscriptionService()
        self.summaryGenerator = MeetingSummaryGenerator()

        // Throttle level meters so SwiftUI is not invalidated at audio-buffer rates (was causing
        // heavy relayout with Liquid Glass + matchedGeometry on the meeting panel and sidebar).
        self.audioRecorder.$levels
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(80), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] next in
                self?.levels = next
            }
            .store(in: &cancellables)

        // Duration timer ticks every 200ms; UI only needs ~2 Hz for mm:ss display.
        self.audioRecorder.$duration
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] next in
                self?.duration = next
            }
            .store(in: &cancellables)

        // Initial setup for meeting mode
        self.audioRecorder.setMeetingMode(true)
    }

    func startRecording(for noteID: UUID) {
        guard AppleIntelligenceService.shared.refreshMeetingNotesCapability().canStartNewSession else {
            return
        }
        guard recordingState == .idle else { return }

        recordingNoteID = noteID
        manualNotes = ""
        selectedTab = .transcript
        summaryResult = nil
        isSummaryLoading = false
        recordingState = .recording

        // Configure buffer callback to transcription
        audioRecorder.onBufferAvailable = { [weak self] buffer in
            guard let self = self else { return }
            self.transcriptionService.feedBuffer(buffer)
        }

        Task {
            do {
                try await self.audioRecorder.start()
                self.transcriptionService.startTranscription()
                // State already set above
            } catch {
                self.recordingState = .idle
                self.recordingNoteID = nil
                // Could post error notification if needed
            }
        }
    }

    func pauseRecording() {
        guard recordingState == .recording else { return }
        Task {
            await audioRecorder.pause()
            recordingState = .paused
        }
    }

    func resumeRecording() {
        guard recordingState == .paused else { return }
        Task {
            try? await audioRecorder.resume()
            recordingState = .recording
        }
    }

    func stopRecording() {
        guard recordingState == .recording || recordingState == .paused else { return }

        recordingState = .processing
        isSummaryLoading = true

        Task {
            // Capture duration before stop resets it
            recordedDuration = audioRecorder.duration

            let audioURL = await audioRecorder.stop()
            await transcriptionService.stopTranscription()

            let segments = transcriptionService.segments

            if let url = audioURL {
                AudioRecorder.cleanupMeetingAudio(at: url)
            }

            // Generate summary from transcript
            do {
                let (result, _) = try await summaryGenerator.generateSummary(
                    from: segments,
                    manualNotes: manualNotes
                )
                summaryResult = result
            } catch {
                // Fallback summary includes a snippet of the raw transcript so the user sees
                // their words rather than an empty body. The full serialized transcript is
                // saved to the MeetingSession regardless of summary success.
                let snippet = segments.prefix(8)
                    .map(\.text)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackBody = snippet.isEmpty
                    ? "Summary generation failed. The full transcript is saved on this note."
                    : "Summary generation failed. Transcript saved — first lines:\n\n\(snippet)"
                summaryResult = MeetingSummaryDisplayResult(
                    title: "Meeting Notes",
                    summary: fallbackBody,
                    keyPoints: [],
                    actionItems: [],
                    decisions: []
                )
            }

            isSummaryLoading = false
            recordingState = .complete
            selectedTab = .summary
        }
    }

    /// Re-runs summary generation from the existing transcript segments. Use when the initial
    /// `stopRecording` summary generation failed (FoundationModels unavailable, throttled, etc.)
    /// The audio file is already cleaned up at this point, but transcript segments live in the
    /// `transcriptionService` until dismissed — so retry is possible as long as the meeting
    /// panel hasn't been dismissed.
    func retrySummary() async {
        guard recordingState == .complete else { return }
        let segments = transcriptionService.segments
        guard !segments.isEmpty else { return }

        isSummaryLoading = true
        defer { isSummaryLoading = false }

        do {
            let (result, _) = try await summaryGenerator.generateSummary(
                from: segments,
                manualNotes: manualNotes
            )
            summaryResult = result
        } catch {
            // Preserve previous fallback body on retry failure — don't mask it with a generic error.
        }
    }

    func dismiss() {
        audioRecorder.onBufferAvailable = nil

        if recordingState == .recording || recordingState == .paused {
            Task {
                let audioURL = await audioRecorder.stop()
                await transcriptionService.stopTranscription()
                if let url = audioURL {
                    AudioRecorder.cleanupMeetingAudio(at: url)
                }
                audioRecorder.setMeetingMode(false)
            }
        } else {
            audioRecorder.setMeetingMode(false)
        }

        recordingState = .idle
        recordingNoteID = nil
        summaryResult = nil
        isSummaryLoading = false
        recordedDuration = 0
    }

    func isRecording(for noteID: UUID) -> Bool {
        recordingNoteID == noteID && recordingState != .idle
    }

    // For panel binding compatibility
    var bindingManualNotes: Binding<String> {
        Binding(
            get: { self.manualNotes },
            set: { self.manualNotes = $0 }
        )
    }

    var bindingSelectedTab: Binding<MeetingTab> {
        Binding(
            get: { self.selectedTab },
            set: { self.selectedTab = $0 }
        )
    }
}
