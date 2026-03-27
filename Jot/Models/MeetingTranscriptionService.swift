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

#if canImport(SpeechAnalyzer)
import SpeechAnalyzer
#endif

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

        if #available(macOS 26.0, *) {
            #if canImport(SpeechAnalyzer)
            startSpeechAnalyzerTranscription()
            #else
            startSFSpeechRecognizerTranscription()
            #endif
        } else {
            startSFSpeechRecognizerTranscription()
        }
    }

    /// Feed an audio buffer from AudioRecorder's tap.
    /// Called from the audio processing thread.
    func feedBuffer(_ buffer: AVAudioPCMBuffer) {
        if let continuation = bufferContinuation {
            continuation.yield(buffer)
        }
        recognitionRequest?.append(buffer)
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

    /// Serialized transcript for persistence.
    func serializedTranscript() -> String {
        segments.filter(\.isFinal).serialized()
    }

    /// Plain text for AI summarization.
    func plainTextTranscript() -> String {
        segments.plainText()
    }
}

// MARK: - SpeechAnalyzer (macOS 26+)

#if canImport(SpeechAnalyzer)
@available(macOS 26.0, *)
extension MeetingTranscriptionService {
    private func startSpeechAnalyzerTranscription() {
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        self.bufferContinuation = continuation

        transcriptionTask = Task { [weak self] in
            guard let self else { return }

            let transcriber = SpeechTranscriber(
                locale: Locale.current,
                preset: .progressiveLiveTranscription
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            do {
                let analysisSequence = try await analyzer.analyzeSequence(stream)

                for try await analysis in analysisSequence {
                    guard !Task.isCancelled else { break }

                    if let transcription = analysis.first(where: { $0 is SpeechTranscriber.Result }) as? SpeechTranscriber.Result {
                        await MainActor.run {
                            self.processSpeechAnalyzerResult(transcription)
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.isTranscribing = false
                    }
                }
            }
        }
    }

    private func processSpeechAnalyzerResult(_ result: SpeechTranscriber.Result) {
        let timestamp = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
        let text = result.transcription.formattedString

        guard !text.isEmpty else { return }

        // If the last segment is not final, update it in place
        if let lastIndex = segments.indices.last, !segments[lastIndex].isFinal {
            segments[lastIndex].text = text
            segments[lastIndex].isFinal = result.transcription.isFinal
        } else {
            // New segment
            let segment = TranscriptSegment(
                text: text,
                timestamp: timestamp,
                isFinal: result.transcription.isFinal
            )
            segments.append(segment)
        }
    }
}
#endif

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
