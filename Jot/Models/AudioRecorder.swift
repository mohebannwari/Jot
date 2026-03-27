import AVFoundation
import Accelerate
import Combine
import Foundation

public enum MicCaptureState: Equatable {
    case idle
    case recording
    case paused
}

public protocol AudioRecorderService: ObservableObject
where ObjectWillChangePublisher == ObservableObjectPublisher {
    var state: MicCaptureState { get }
    var levels: [Float] { get }
    var duration: TimeInterval { get }
    var fileURL: URL? { get }
    var error: AudioRecorder.RecorderError? { get }
    @MainActor func start() async throws
    @MainActor func pause() async
    @MainActor func resume() async throws
    @MainActor @discardableResult func stop() async -> URL?
    @MainActor func cancel()
}

public final class AudioRecorder: NSObject, ObservableObject, AudioRecorderService,
    @unchecked Sendable
{
    public enum RecorderError: Error, Equatable, LocalizedError {
        case permissionDenied
        case engineUnavailable
        case fileCreationFailed
        case configurationFailed

        public var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission is required to record audio."
            case .engineUnavailable:
                return "Audio engine could not be started."
            case .fileCreationFailed:
                return "Unable to create a recording file."
            case .configurationFailed:
                return "Audio engine configuration failed."
            }
        }
    }

    @Published public private(set) var state: MicCaptureState = .idle
    @Published public private(set) var levels: [Float]
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var error: RecorderError?

    public private(set) var fileURL: URL?

    /// Called on the audio processing thread with each new buffer.
    /// Used by MeetingTranscriptionService to feed SpeechAnalyzer.
    var onBufferAvailable: ((AVAudioPCMBuffer) -> Void)?

    /// When true, recording files go to MeetingCapture/ instead of MicCapture/.
    private(set) var isMeetingMode: Bool = false

    private let barCount: Int
    private let defaultSampleRate: Double = 44_100
    private let preferredChannelCount: AVAudioChannelCount = 1
    private let engine = AVAudioEngine()
    private let bridgeMixer = AVAudioMixerNode()
    private var audioFile: AVAudioFile?
    private let audioFileQueue = DispatchQueue(label: "com.jot.audiofile")
    private var isConfigured = false
    private var tapInstalled = false
    private var accumulatedDuration: TimeInterval = 0
    private var startDate: Date?
    private var durationTimer: DispatchSourceTimer?
    private var decayTimer: DispatchSourceTimer?
    private var lastLevelTimestamp: CFTimeInterval = 0
    private var targetSampleRate: Double
    private var outputFormat: AVAudioFormat?

    public init(barCount: Int = 28) {
        self.barCount = barCount
        self.targetSampleRate = defaultSampleRate
        self.levels = Array(repeating: 0, count: barCount)
        super.init()
    }

    deinit {
        cleanup()
    }

    @MainActor
    public func start() async throws {
        error = nil
        guard state != .recording else { return }

        do {
            try await ensurePermissions()
        } catch {
            self.error = .permissionDenied
            throw RecorderError.permissionDenied
        }

        if !isConfigured {
            do {
                try configureEngine()
            } catch {
                self.error = .configurationFailed
                throw RecorderError.configurationFailed
            }
        }

        if state == .idle {
            do {
                try prepareRecordingFile()
            } catch {
                self.error = .fileCreationFailed
                throw RecorderError.fileCreationFailed
            }
        }

        installTapIfNeeded()

        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            removeTap()
            self.error = .engineUnavailable
            throw RecorderError.engineUnavailable
        }

        startDate = Date()
        startDurationUpdates()
        decayTimer?.cancel()
        decayTimer = nil
        state = .recording
    }

    @MainActor
    public func pause() async {
        guard state == .recording else { return }
        engine.pause()
        if let startDate {
            accumulatedDuration += Date().timeIntervalSince(startDate)
        }
        startDate = nil
        stopDurationUpdates()
        startDecay()
        state = .paused
    }

    @MainActor
    public func resume() async throws {
        guard state == .paused else { return }
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            self.error = .engineUnavailable
            throw RecorderError.engineUnavailable
        }
        startDate = Date()
        startDurationUpdates()
        decayTimer?.cancel()
        state = .recording
    }

    @MainActor
    @discardableResult
    public func stop() async -> URL? {
        guard state != .idle else { return nil }

        // Stop engine and remove tap first to ensure no more data is written
        engine.stop()
        removeTap()
        stopDurationUpdates()
        decayTimer?.cancel()
        decayTimer = nil

        if let startDate {
            accumulatedDuration += Date().timeIntervalSince(startDate)
        }
        startDate = nil
        duration = accumulatedDuration

        let url = fileURL
        audioFileQueue.async { [weak self] in self?.audioFile = nil }
        fileURL = nil
        accumulatedDuration = 0
        state = .idle
        resetLevels()

        // Verify the file exists and has content
        if let url = url {
            if FileManager.default.fileExists(atPath: url.path) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes?[.size] as? Int64 ?? 0
                NSLog("AudioRecorder.stop: Recording saved - size: %lld bytes", fileSize)
            } else {
                NSLog("AudioRecorder.stop: Warning - file does not exist at path: %@", url.path)
            }
        }

        return url
    }

    @MainActor
    public func cancel() {
        engine.stop()
        removeTap()
        stopDurationUpdates()
        decayTimer?.cancel()
        decayTimer = nil
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioFileQueue.async { [weak self] in self?.audioFile = nil }
        fileURL = nil
        accumulatedDuration = 0
        startDate = nil
        duration = 0
        state = .idle
        resetLevels()
    }

    @MainActor
    public func resetForTesting() {
        cleanup()
        levels = Array(repeating: 0, count: barCount)
        duration = 0
        state = .idle
        fileURL = nil
        audioFileQueue.sync { audioFile = nil }
        accumulatedDuration = 0
        startDate = nil
        targetSampleRate = defaultSampleRate
        outputFormat = nil
        isConfigured = false
    }
}

// MARK: - Engine Configuration
extension AudioRecorder {
    fileprivate func ensurePermissions() async throws {
        #if os(macOS)
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                return
            case .denied, .restricted:
                throw RecorderError.permissionDenied
            case .notDetermined:
                let granted = await withCheckedContinuation { continuation in
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        continuation.resume(returning: granted)
                    }
                }
                guard granted else {
                    throw RecorderError.permissionDenied
                }
            @unknown default:
                throw RecorderError.permissionDenied
            }
        #else
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .measurement, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
            switch session.recordPermission {
            case .granted:
                return
            case .denied:
                throw RecorderError.permissionDenied
            case .undetermined:
                let granted = await withCheckedContinuation { continuation in
                    session.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
                guard granted else {
                    throw RecorderError.permissionDenied
                }
            @unknown default:
                throw RecorderError.permissionDenied
            }
        #endif
    }

    fileprivate func prepareRecordingFile() throws {
        if let existing = fileURL {
            try? FileManager.default.removeItem(at: existing)
        }
        let url = try isMeetingMode ? Self.makeMeetingRecordingURL() : Self.makeRecordingURL()
        let sampleRate = outputFormat?.sampleRate ?? targetSampleRate
        let channelCount = Int(outputFormat?.channelCount ?? preferredChannelCount)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 96_000,
        ]
        audioFile = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false)
        fileURL = url
        accumulatedDuration = 0
        duration = 0
        startDate = nil
        resetLevels()
    }

    fileprivate func configureEngine() throws {
        if !engine.attachedNodes.contains(bridgeMixer) {
            engine.attach(bridgeMixer)
        }
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        engine.connect(input, to: bridgeMixer, format: inputFormat)

        let channelCount = max(AVAudioChannelCount(1), min(inputFormat.channelCount, preferredChannelCount))
        guard
            let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: channelCount,
                interleaved: false)
        else {
            throw RecorderError.configurationFailed
        }

        engine.connect(bridgeMixer, to: engine.mainMixerNode, format: recordingFormat)

        targetSampleRate = recordingFormat.sampleRate
        outputFormat = recordingFormat

        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        isConfigured = true
    }

    fileprivate func installTapIfNeeded() {
        guard !tapInstalled else { return }
        guard let outputFormat else { return }
        bridgeMixer.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: outputFormat
        ) { [weak self] buffer, _ in
            guard let self else { return }
            let computedLevels = self.computeLevels(from: buffer)
            self.audioFileQueue.sync {
                if let audioFile = self.audioFile {
                    do {
                        try audioFile.write(from: buffer)
                    } catch {
                        self.dispatchToMain {
                            self.error = .engineUnavailable
                        }
                    }
                }
            }
            // Forward buffer to transcription service if in meeting mode
            self.onBufferAvailable?(buffer)
            self.dispatchToMain {
                self.updateLevels(computedLevels)
            }
        }
        tapInstalled = true
    }

    fileprivate func removeTap() {
        guard tapInstalled else { return }
        bridgeMixer.removeTap(onBus: 0)
        tapInstalled = false
    }
}

// MARK: - Levels & Duration
extension AudioRecorder {
    fileprivate func computeLevels(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return Array(repeating: 0, count: barCount)
        }

        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 {
            return Array(repeating: 0, count: barCount)
        }

        let channelCount = Int(buffer.format.channelCount)
        var monoSamples = [Float](repeating: 0, count: frameLength)

        monoSamples.withUnsafeMutableBufferPointer { dest in
            guard let destPtr = dest.baseAddress else { return }
            if channelCount > 0 {
                memcpy(destPtr, channelData[0], frameLength * MemoryLayout<Float>.size)
                if channelCount > 1 {
                    for channel in 1..<channelCount {
                        vDSP_vadd(
                            destPtr,
                            1,
                            channelData[channel],
                            1,
                            destPtr,
                            1,
                            vDSP_Length(frameLength))
                    }
                    var divisor = Float(channelCount)
                    vDSP_vsdiv(
                        destPtr,
                        1,
                        &divisor,
                        destPtr,
                        1,
                        vDSP_Length(frameLength))
                }
            }
        }

        let chunk = max(frameLength / barCount, 1)
        var result = [Float](repeating: 0, count: barCount)

        monoSamples.withUnsafeBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            for index in 0..<barCount {
                let start = index * chunk
                if start >= frameLength { break }
                let count = min(chunk, frameLength - start)
                var rms: Float = 0
                vDSP_rmsqv(
                    baseAddress + start,
                    1,
                    &rms,
                    vDSP_Length(count))
                let normalized = normalize(rms: rms)
                result[index] = normalized
            }
        }

        return result
    }

    fileprivate func normalize(rms: Float) -> Float {
        let level = max(rms, 1e-5)
        let db = 20 * log10(level)
        let clamped = max(-60, min(0, db))
        return (clamped + 60) / 60
    }

    @MainActor
    fileprivate func updateLevels(_ newLevels: [Float]) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLevelTimestamp >= (1.0 / 60.0) else { return }
        lastLevelTimestamp = now

        let current = levels
        let count = min(current.count, newLevels.count)
        var smoothed = current
        for index in 0..<count {
            let incoming = newLevels[index]
            let existing = current[index]
            let mix: Float = incoming > existing ? 0.6 : 0.3
            smoothed[index] = existing + (incoming - existing) * mix
        }
        levels = smoothed
    }

    @MainActor
    fileprivate func startDurationUpdates() {
        durationTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.state == .recording else { return }
            let running = self.startDate.map { Date().timeIntervalSince($0) } ?? 0
            self.duration = self.accumulatedDuration + running
        }
        timer.activate()
        durationTimer = timer
    }

    @MainActor
    fileprivate func stopDurationUpdates() {
        durationTimer?.cancel()
        durationTimer = nil
    }

    @MainActor
    fileprivate func startDecay() {
        decayTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(
            deadline: .now() + .milliseconds(60), repeating: .milliseconds(60),
            leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var nextLevels = self.levels
            var retainsEnergy = false
            for index in nextLevels.indices {
                let value = max(0, nextLevels[index] * 0.72 - 0.01)
                nextLevels[index] = value
                retainsEnergy = retainsEnergy || value > 0.02
            }
            self.levels = nextLevels
            if !retainsEnergy {
                self.decayTimer?.cancel()
                self.decayTimer = nil
            }
        }
        timer.activate()
        decayTimer = timer
    }

    @MainActor
    fileprivate func resetLevels() {
        levels = Array(repeating: 0, count: barCount)
        lastLevelTimestamp = 0
    }
}

// MARK: - Helpers
extension AudioRecorder {
    fileprivate func dispatchToMain(_ action: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async {
                action()
            }
        }
    }

    fileprivate func cleanup() {
        durationTimer?.cancel()
        decayTimer?.cancel()
        durationTimer = nil
        decayTimer = nil
        removeTap()
        engine.stop()
    }
}

// MARK: - File Management
extension AudioRecorder {
    @discardableResult
    internal static func makeRecordingURL() throws -> URL {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("MicCapture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let url =
            directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw RecorderError.fileCreationFailed
        }
        return url
    }

    @discardableResult
    internal static func makeMeetingRecordingURL() throws -> URL {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("MeetingCapture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let url =
            directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw RecorderError.fileCreationFailed
        }
        return url
    }

    /// Enable meeting mode before calling start(). Directs audio to MeetingCapture/ directory.
    @MainActor
    func setMeetingMode(_ enabled: Bool) {
        isMeetingMode = enabled
    }

    /// Clean up a meeting recording file after it's been processed.
    static func cleanupMeetingAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Clean up all files in the MeetingCapture directory.
    static func cleanupAllMeetingAudio() {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("MeetingCapture", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }
}
