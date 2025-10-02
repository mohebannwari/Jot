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
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard await ensureAuthorization() else { return nil }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false

        return await withCheckedContinuation { continuation in
            var completed = false
            var recognitionTask: SFSpeechRecognitionTask?
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                guard !completed else { return }
                completed = true
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else {
                    continuation.resume(returning: nil)
                }
                if error != nil {
                    recognitionTask?.cancel()
                }
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                guard !completed else { return }
                completed = true
                recognitionTask?.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}

private extension Transcriber {
    func ensureAuthorization() async -> Bool {
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
