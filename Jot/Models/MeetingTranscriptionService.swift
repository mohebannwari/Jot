//
//  MeetingTranscriptionService.swift
//  Jot
//
//  Real-time speech-to-text for meeting note recording.
//  Uses SpeechAnalyzer (macOS 26+) for on-device progressive transcription.
//  Falls back to SFSpeechRecognizer for pre-26 targets.
//

import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class MeetingTranscriptionService: ObservableObject {
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var isTranscribing: Bool = false
    @Published private(set) var detectedLanguage: String = ""

    private var recordingStartDate: Date?
    private var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var transcriptionTask: Task<Void, Never>?

    // SFSpeechRecognizer fallback
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Start transcription, returning a callback to feed audio buffers.
    func startTranscription() {
        guard !isTranscribing else { return }
        segments = []
        detectedLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        recordingStartDate = Date()
        isTranscribing = true

        // v1: Use SFSpeechRecognizer for reliable transcription on all macOS versions.
        // SpeechAnalyzer (macOS 26) requires AssetInventory model download which may
        // not be complete. SFSpeechRecognizer with on-device recognition is the safe path.
        // TODO: v2 -- add SpeechAnalyzer with proper asset lifecycle management.
        startSFSpeechRecognizerTranscription()
    }

    /// Feed an audio buffer from AudioRecorder's tap.
    /// Called from the audio processing thread -- dispatches to MainActor
    /// since bufferContinuation and recognitionRequest are actor-isolated.
    nonisolated func feedBuffer(_ buffer: AVAudioPCMBuffer) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bufferContinuation?.yield(buffer)
            self.recognitionRequest?.append(buffer)
        }
    }

    /// Stop transcription and finalize all segments.
    func stopTranscription() {
        isTranscribing = false
        bufferContinuation?.finish()
        bufferContinuation = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // SFSpeechRecognizer cleanup
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil

        // Mark all segments as final
        for i in segments.indices {
            segments[i].isFinal = true
        }
    }

    /// Serialized transcript for persistence (includes ALL segments).
    func serializedTranscript() -> String {
        segments.serialized()
    }

    /// Plain text for AI summarization (all segments, not just final).
    func plainTextTranscript() -> String {
        segments.map(\.text).joined(separator: " ")
    }
}

// MARK: - SpeechAnalyzer (macOS 26+)
//
// SpeechAnalyzer is part of the Speech framework (not a separate module).
// It uses AnalyzerInput wrappers around AVAudioPCMBuffer, results come
// from the transcriber's .results AsyncSequence, and the analyzer runs
// analysis in parallel via analyzeSequence().

@available(macOS 26.0, *)
extension MeetingTranscriptionService {
    fileprivate func startSpeechAnalyzerTranscription() {
        let currentLocale = Locale.current
        detectedLanguage = currentLocale.language.languageCode?.identifier ?? "en"

        let transcriber = SpeechTranscriber(
            locale: currentLocale,
            preset: .progressiveTranscription
        )

        // Must verify assets are installed before using SpeechAnalyzer.
        // Without this check, SpeechRecognizerWorker.preRunRecognition() hits
        // a precondition failure (SIGTRAP) when the model isn't downloaded.
        transcriptionTask = Task { [weak self] in
            guard let self else { return }

            // Check and install assets if needed
            do {
                if let installRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    // Assets not ready -- try to install, fall back if it takes too long
                    try await installRequest.downloadAndInstall()
                }
            } catch {
                // Assets unavailable -- fall back to SFSpeechRecognizer
                await MainActor.run { [weak self] in
                    self?.startSFSpeechRecognizerTranscription()
                }
                return
            }

            await MainActor.run { [weak self] in
                self?.startSpeechAnalyzerAfterAssetCheck(transcriber: transcriber)
            }
        }
    }

    fileprivate func startSpeechAnalyzerAfterAssetCheck(transcriber: SpeechTranscriber) {
        // Create the AnalyzerInput stream (wraps AVAudioPCMBuffer)
        let (inputStream, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

        // Store a buffer continuation that wraps buffers into AnalyzerInput
        let (bufferStream, bufContinuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        self.bufferContinuation = bufContinuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Task 1: Forward AVAudioPCMBuffers -> AnalyzerInput stream
        let forwardTask = Task {
            for await buffer in bufferStream {
                guard !Task.isCancelled else { break }
                inputContinuation.yield(AnalyzerInput(buffer: buffer))
            }
            inputContinuation.finish()
        }

        // Task 2: Consume transcription results
        let resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { break }
                    let text = String(result.text.characters)
                    guard !text.isEmpty else { continue }

                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        let timestamp = self.recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0

                        // Update last non-final segment in place, or append new
                        if let lastIndex = self.segments.indices.last, !self.segments[lastIndex].isFinal {
                            self.segments[lastIndex].text = text
                        } else {
                            self.segments.append(TranscriptSegment(
                                text: text,
                                timestamp: timestamp,
                                isFinal: false
                            ))
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        self?.isTranscribing = false
                    }
                }
            }
        }

        // Task 3: Run the analyzer (blocks until input finishes)
        // Store as transcriptionTask so stopTranscription() can cancel it
        transcriptionTask = Task {
            do {
                let _ = try await analyzer.analyzeSequence(inputStream)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        self?.isTranscribing = false
                    }
                }
            }
            forwardTask.cancel()
            resultsTask.cancel()
        }
    }
}

// MARK: - SFSpeechRecognizer Fallback

extension MeetingTranscriptionService {
    fileprivate func startSFSpeechRecognizerTranscription() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
        guard let recognizer, recognizer.isAvailable else {
            isTranscribing = false
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let timestamp = self.recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
                    let text = result.bestTranscription.formattedString

                    if !text.isEmpty {
                        if let lastIndex = self.segments.indices.last, !self.segments[lastIndex].isFinal {
                            self.segments[lastIndex].text = text
                            self.segments[lastIndex].isFinal = result.isFinal
                        } else {
                            self.segments.append(TranscriptSegment(
                                text: text,
                                timestamp: timestamp,
                                isFinal: result.isFinal
                            ))
                        }

                        // SFSpeechRecognizer has a ~1 minute limit; when a segment
                        // finalizes, start a new recognition request for continuity
                        if result.isFinal {
                            self.restartRecognitionForContinuity()
                        }
                    }
                }

                if error != nil && !Task.isCancelled {
                    // Mark the current segment as final before restarting --
                    // otherwise the new recognition's text overwrites the old segment
                    if let lastIndex = self.segments.indices.last, !self.segments[lastIndex].isFinal {
                        self.segments[lastIndex].isFinal = true
                    }
                    // Auto-restart on error for continuous transcription
                    self.restartRecognitionForContinuity()
                }
            }
        }
    }

    /// SFSpeechRecognizer has a ~1 minute audio limit. When it finalizes,
    /// we tear down and restart a new request to continue transcribing.
    private func restartRecognitionForContinuity() {
        guard isTranscribing else { return }

        // Finalize the last segment so the new recognition doesn't overwrite it
        if let lastIndex = segments.indices.last, !segments[lastIndex].isFinal {
            segments[lastIndex].isFinal = true
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        // Small delay then restart
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, self.isTranscribing else { return }
            self.startSFSpeechRecognizerTranscription()
        }
    }
}
