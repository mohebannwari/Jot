import Foundation
import Speech

@MainActor
public protocol Transcribing: AnyObject {
    func transcribe(url: URL) async -> String?
}

@MainActor
public final class Transcriber: Transcribing {
    public static let shared = Transcriber()

    private var authorizationStatus: SFSpeechRecognizerAuthorizationStatus?

    public init() {}

    public func transcribe(url: URL) async -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("Transcriber.transcribe: File does not exist at path: %@", url.path)
            return nil
        }

        // Ensure authorization before attempting transcription
        guard await ensureAuthorization() else {
            NSLog("Transcriber.transcribe: Speech recognition not authorized")
            return nil
        }

        // Check if speech recognizer is available
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            NSLog("Transcriber.transcribe: Speech recognizer unavailable")
            return nil
        }

        NSLog("Transcriber.transcribe: Starting transcription for file: %@", url.path)

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
                            NSLog("Transcriber: Ignoring duplicate resume attempt")
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
                            NSLog("Transcriber.transcribe: Recognition error: %@", error.localizedDescription)
                            await state.tryResume(with: nil, continuation: continuation)
                            return
                        }

                        if let result = result, result.isFinal {
                            NSLog("Transcriber.transcribe: Transcription complete: %@", result.bestTranscription.formattedString)
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
                    NSLog("Transcriber.transcribe: Timeout after 30 seconds")
                    await state.cancelTask()
                    await state.tryResume(with: nil, continuation: continuation)
                }
            }
        } onCancel: {
            NSLog("Transcriber.transcribe: Task was cancelled")
        }
    }
}

private extension Transcriber {
    func ensureAuthorization() async -> Bool {
        guard let usageDescription =
            Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String,
            usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            NSLog(
                "Transcriber.ensureAuthorization: Missing NSSpeechRecognitionUsageDescription in Info.plist"
            )
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
