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

    // Stop coordination: await the final isFinal=true result before cleanup
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var stopTimeoutTask: Task<Void, Never>?

    // Buffer queuing during restart gap (prevents audio loss)
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var isRestarting: Bool = false

    // Tracks the last known text for the current non-final segment.
    // Used to detect when SFSpeechRecognizer clears its internal transcript
    // after a speech pause (known Apple bug on macOS 15+ / iOS 18+).
    private var lastPartialText: String = ""

    /// Start transcription, returning a callback to feed audio buffers.
    func startTranscription() {
        guard !isTranscribing else { return }
        segments = []
        lastPartialText = ""
        detectedLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        recordingStartDate = Date()
        pendingBuffers = []
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
    /// Uses Task { @MainActor } for Swift 6 strict concurrency compatibility.
    nonisolated func feedBuffer(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.bufferContinuation?.yield(buffer)
            if self.isRestarting {
                self.pendingBuffers.append(buffer)
            } else {
                self.recognitionRequest?.append(buffer)
            }
        }
    }

    /// Stop transcription and finalize all segments.
    /// Async because we wait for SFSpeechRecognizer to deliver the final
    /// isFinal=true result after endAudio(), rather than aborting with cancel().
    func stopTranscription() async {
        isTranscribing = false
        bufferContinuation?.finish()
        bufferContinuation = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Signal end of audio -- the recognizer will process remaining buffers
        // and deliver a final result with isFinal=true. Do NOT call cancel()
        // here because that aborts processing and discards the final transcript.
        recognitionRequest?.endAudio()

        if recognitionTask != nil {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.stopContinuation = continuation

                // Timeout: if the final result doesn't arrive within 3s, resume anyway
                self.stopTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    self?.resumeStopContinuationIfNeeded()
                }
            }
        }

        // Cleanup after final result (or timeout)
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil

        // Mark any remaining non-final segments as final
        for i in segments.indices {
            segments[i].isFinal = true
        }
    }

    private func resumeStopContinuationIfNeeded() {
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        if let continuation = stopContinuation {
            stopContinuation = nil
            continuation.resume()
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
                            // Detect SFSpeechRecognizer transcript-clearing bug:
                            // On macOS 15+ / iOS 18+, the recognizer clears its internal
                            // transcript after a speech pause, causing formattedString to
                            // regress to only the latest fragment. When this happens,
                            // preserve the previous text as a finalized segment.
                            let previousText = self.lastPartialText
                            let isRegression = previousText.count >= 20
                                && text.count < previousText.count / 2
                                && !text.lowercased().hasPrefix(previousText.lowercased().prefix(min(20, previousText.count)))

                            if isRegression {
                                // Recognizer cleared its buffer — finalize previous segment
                                self.segments[lastIndex].isFinal = true
                                self.lastPartialText = text
                                self.segments.append(TranscriptSegment(
                                    text: text,
                                    timestamp: timestamp,
                                    isFinal: result.isFinal
                                ))
                            } else {
                                self.segments[lastIndex].text = text
                                self.segments[lastIndex].isFinal = result.isFinal
                                self.lastPartialText = text
                            }
                        } else {
                            self.lastPartialText = text
                            self.segments.append(TranscriptSegment(
                                text: text,
                                timestamp: timestamp,
                                isFinal: result.isFinal
                            ))
                        }

                        if result.isFinal {
                            self.lastPartialText = ""
                            if self.isTranscribing {
                                // SFSpeechRecognizer has a ~1 minute limit; restart for continuity
                                self.restartRecognitionForContinuity()
                            } else {
                                // Stop was requested -- final result arrived, signal completion
                                self.resumeStopContinuationIfNeeded()
                            }
                        }
                    }
                }

                if error != nil {
                    if self.isTranscribing {
                        // Still actively transcribing -- mark segment final and restart
                        if let lastIndex = self.segments.indices.last, !self.segments[lastIndex].isFinal {
                            self.segments[lastIndex].isFinal = true
                        }
                        self.lastPartialText = ""
                        self.restartRecognitionForContinuity()
                    } else {
                        // Stop was requested -- error during finalization, resume anyway
                        self.resumeStopContinuationIfNeeded()
                    }
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

        // Queue buffers during the restart gap to prevent audio loss
        isRestarting = true
        pendingBuffers = []

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        // Small delay then restart
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, self.isTranscribing else {
                self?.isRestarting = false
                return
            }
            self.startSFSpeechRecognizerTranscription()

            // Drain any buffers that arrived during the restart gap
            let buffered = self.pendingBuffers
            self.pendingBuffers = []
            self.isRestarting = false
            for buffer in buffered {
                self.recognitionRequest?.append(buffer)
            }
        }
    }
}
