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

        // Use a simpler approach with explicit cancellation
        return await withCheckedContinuation { continuation in
            var task: SFSpeechRecognitionTask?
            var didResume = false
            let lock = NSLock()

            task = recognizer.recognitionTask(with: request) { result, error in
                lock.lock()
                defer { lock.unlock() }

                guard !didResume else { return }

                if let error = error {
                    NSLog("Transcriber.transcribe: Recognition error: %@", error.localizedDescription)
                    didResume = true
                    task?.cancel()
                    continuation.resume(returning: nil)
                    return
                }

                if let result = result, result.isFinal {
                    NSLog("Transcriber.transcribe: Transcription complete: %@", result.bestTranscription.formattedString)
                    didResume = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if result == nil {
                    NSLog("Transcriber.transcribe: No result returned")
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }

            // Timeout handler
            Task {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                lock.lock()
                defer { lock.unlock() }

                guard !didResume else { return }
                didResume = true
                NSLog("Transcriber.transcribe: Timeout after 30 seconds")
                task?.cancel()
                continuation.resume(returning: nil)
            }
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
