import Foundation
import os
import Speech

@MainActor
public protocol Transcribing: AnyObject {
    func transcribe(url: URL) async -> String?
}

@MainActor
public final class Transcriber: Transcribing {
    public static let shared = Transcriber()

    private let logger = Logger(subsystem: "com.jot", category: "Transcriber")

    private var authorizationStatus: SFSpeechRecognizerAuthorizationStatus?

    public init() {}

    public func transcribe(url: URL) async -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("transcribe: File does not exist at path: \(url.path)")
            return nil
        }

        // Ensure authorization before attempting transcription
        guard await ensureAuthorization() else {
            logger.error("transcribe: Speech recognition not authorized")
            return nil
        }

        // Check if speech recognizer is available
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            logger.error("transcribe: Speech recognizer unavailable")
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false

        // Use async/await with proper task cancellation
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                // Use actor to safely manage state
                actor RecognitionState {
                    var task: SFSpeechRecognitionTask?
                    var hasResumed = false

                    func setTask(_ task: SFSpeechRecognitionTask) {
                        self.task = task
                    }

                    func cancelTask() {
                        task?.cancel()
                        task = nil
                    }

                    func tryResume(with result: String?, continuation: CheckedContinuation<String?, Never>) {
                        guard !hasResumed else {
                            return
                        }
                        hasResumed = true
                        continuation.resume(returning: result)
                    }
                }

                let state = RecognitionState()

                // Start recognition task
                let recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                    Task {
                        if let error = error {
                            Logger(subsystem: "com.jot", category: "Transcriber").error("transcribe: Recognition error: \(error.localizedDescription)")
                            await state.tryResume(with: nil, continuation: continuation)
                            return
                        }

                        if let result = result, result.isFinal {
                            await state.tryResume(with: result.bestTranscription.formattedString, continuation: continuation)
                        }
                    }
                }

                // Store the task for cancellation
                Task {
                    await state.setTask(recognitionTask)
                }

                // Timeout handler
                Task {
                    try? await Task.sleep(for: .seconds(30))
                    Logger(subsystem: "com.jot", category: "Transcriber").error("transcribe: Timeout after 30 seconds")
                    await state.cancelTask()
                    await state.tryResume(with: nil, continuation: continuation)
                }
            }
        } onCancel: {
        }
    }
}

private extension Transcriber {
    func ensureAuthorization() async -> Bool {
        guard let usageDescription =
            Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String,
            usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            logger.error("ensureAuthorization: Missing NSSpeechRecognitionUsageDescription in Info.plist")
            authorizationStatus = .denied
            return false
        }
        if let authorizationStatus {
            return authorizationStatus == .authorized
        }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
        return status == .authorized
    }
}
