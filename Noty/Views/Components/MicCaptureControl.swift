import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

public struct MicCaptureControl: View {
    public struct Result {
        public let audioURL: URL
        public let transcript: String?

        public init(audioURL: URL, transcript: String?) {
            self.audioURL = audioURL
            self.transcript = transcript
        }
    }

    @StateObject private var viewModel: MicCaptureViewModel
    @Namespace private var morphNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    public init(onSend: @escaping (Result) -> Void,
                onCancel: (() -> Void)? = nil,
                recorder: AudioRecorder? = nil,
                transcriber: Transcribing? = nil,
                autoStart: Bool = false) {
        let recorderInstance = recorder ?? AudioRecorder()
        let transcriberInstance = transcriber ?? Transcriber.shared
        _viewModel = StateObject(wrappedValue: MicCaptureViewModel(recorder: recorderInstance,
                                                                   transcriber: transcriberInstance,
                                                                   onSend: onSend,
                                                                   onCancel: onCancel,
                                                                   autoStart: autoStart))
    }

    public var body: some View {
        morphingContent
            .animation(MicAnimations.morph, value: viewModel.state)
        .onAppear {
            if viewModel.autoStart {
                Task { @MainActor in
                    await viewModel.startRecording()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.permissionMessage {
                errorBanner(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .accessibilityElement(children: .contain)
    }

    // Liquid Glass-aligned animation timings like FloatingSearch
    private enum MicAnimations {
        static let morph = Animation.bouncy(duration: 0.35)
        static let collapse = Animation.snappy(duration: 0.24)
        static let stateChange = Animation.spring(response: 0.22, dampingFraction: 0.82)
    }

    @ViewBuilder
    private var morphingContent: some View {
        switch viewModel.state {
        case .idle:
            idleView
                .matchedGeometryEffect(id: "mic-control", in: morphNamespace)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 1.2).combined(with: .opacity)
                ))
        case .recording:
            recordingView
                .matchedGeometryEffect(id: "mic-control", in: morphNamespace)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 1.2).combined(with: .opacity)
                ))
        case .paused:
            pausedView
                .matchedGeometryEffect(id: "mic-control", in: morphNamespace)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 1.2).combined(with: .opacity)
                ))
        }
    }
}

// MARK: - Subviews
private extension MicCaptureControl {
    var idleView: some View {
        Button {
            Task { @MainActor in
                await viewModel.startRecording()
            }
        } label: {
            Image(systemName: "mic")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color("PrimaryTextColor"))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .background(Circle().fill(.clear))
        .liquidGlass(in: Circle())
        .accessibilityLabel(Text("Start recording"))
        .keyboardShortcut(.space, modifiers: [])
    }

    var recordingView: some View {
        HStack(spacing: 10) {
            Button {
                Task { @MainActor in
                    await viewModel.pauseRecording()
                }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white, Color.red)
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
            .accessibilityLabel(Text("Stop recording"))

            WaveformView(
                levels: viewModel.levels,
                barCount: 4,
                barWidth: 3,
                spacing: 3,
                color: Color.red
            )
            .frame(width: 24, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(height: 44)
        .background(Capsule().fill(.clear))
        .liquidGlass(in: Capsule())
        .overlay(cancelShortcut)
    }

    var pausedView: some View {
        HStack(spacing: 3) {
            Button {
                Task { @MainActor in
                    await viewModel.cancelCapture()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 20, height: 20)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .background(cancelButtonColor, in: Capsule())
            .accessibilityLabel(Text("Cancel recording"))

            Button {
                Task { @MainActor in
                    await viewModel.resumeRecording()
                }
            } label: {
                Image(systemName: "record.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(resumeIconColor)
                    .frame(width: 20, height: 20)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .background(resumeButtonColor, in: Capsule())
            .accessibilityLabel(Text("Resume recording"))

            Button {
                Task { @MainActor in
                    await viewModel.sendRecording()
                }
            } label: {
                if viewModel.isProcessingSend {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                        .frame(width: 20, height: 20)
                        .padding(8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .padding(8)
                }
            }
            .buttonStyle(.plain)
            .background(sendButtonColor, in: Capsule())
            .disabled(viewModel.isProcessingSend)
            .accessibilityLabel(Text(viewModel.isProcessingSend ? "Sending voice note" : "Send voice note"))
        }
        .padding(2)
        .frame(height: 44)
        .background(Capsule().fill(.clear))
        .liquidGlass(in: Capsule())
        .overlay(cancelShortcut)
    }

    private var cancelButtonColor: Color {
        colorScheme == .dark
            ? Color(white: 0.25)
            : Color(white: 0.85)
    }

    private var resumeButtonColor: Color {
        colorScheme == .dark
            ? Color(white: 0.25)
            : Color(white: 0.85)
    }

    private var resumeIconColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var sendButtonColor: Color {
        Color("AccentColor")
    }

    var cancelShortcut: some View {
        Button {
            Task { @MainActor in
                await viewModel.cancelCapture()
            }
        } label: {
            EmptyView()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityHidden(true)
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary)

            Spacer(minLength: 8)

            Button("Open Settings") {
                viewModel.openSettings()
            }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(.clear))
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 12)
        .padding(.horizontal, 4)
    }
}

// MARK: - View Model
@MainActor
final class MicCaptureViewModel: ObservableObject {
    @Published private(set) var state: MicCaptureState
    @Published private(set) var levels: [Float]
    @Published private(set) var isProcessingSend = false
    @Published var permissionMessage: String?

    private let recorder: any AudioRecorderService
    private let transcriber: Transcribing
    private let onSend: (MicCaptureControl.Result) -> Void
    private let onCancel: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    let autoStart: Bool

    var elapsedTime: String? {
        guard recorder.duration > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = recorder.duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: recorder.duration)
    }

    init(recorder: any AudioRecorderService,
         transcriber: Transcribing,
         onSend: @escaping (MicCaptureControl.Result) -> Void,
         onCancel: (() -> Void)?,
         autoStart: Bool) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.onSend = onSend
        self.onCancel = onCancel
        self.autoStart = autoStart
        self.state = recorder.state
        self.levels = recorder.levels

        recorder.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.state = recorder.state
                self.levels = recorder.levels
                self.permissionMessage = recorder.error?.errorDescription
            }
            .store(in: &cancellables)
    }

    func startRecording() async {
        do {
            try await recorder.start()
            permissionMessage = nil
            state = recorder.state
            levels = recorder.levels
        } catch let error as AudioRecorder.RecorderError {
            NSLog("MicCaptureViewModel.startRecording failed with recorder error: %@", String(describing: error))
            permissionMessage = error.errorDescription
        } catch {
            NSLog("MicCaptureViewModel.startRecording failed with unexpected error: %@", String(describing: error))
            permissionMessage = AudioRecorder.RecorderError.engineUnavailable.errorDescription
        }
    }

    func pauseRecording() async {
        await recorder.pause()
        withAnimation(.bouncy(duration: 0.35)) {
            state = recorder.state
            levels = recorder.levels
        }
    }

    func resumeRecording() async {
        do {
            try await recorder.resume()
            permissionMessage = nil
            state = recorder.state
            levels = recorder.levels
        } catch let error as AudioRecorder.RecorderError {
            permissionMessage = error.errorDescription
        } catch {
            permissionMessage = AudioRecorder.RecorderError.engineUnavailable.errorDescription
        }
    }

    func sendRecording() async {
        guard !isProcessingSend else { return }
        withAnimation(.bouncy(duration: 0.35)) {
            isProcessingSend = true
        }
        let url = await recorder.stop()
        var transcript: String? = nil
        if let url, FileManager.default.fileExists(atPath: url.path) {
            transcript = await transcriber.transcribe(url: url)
            if transcript?.isEmpty == true {
                transcript = nil
            }
        }
        withAnimation(.bouncy(duration: 0.35)) {
            isProcessingSend = false
            state = recorder.state
            levels = recorder.levels
        }
        guard let finalURL = url else { return }
        onSend(.init(audioURL: finalURL, transcript: transcript))
    }

    func cancelCapture() async {
        recorder.cancel()
        permissionMessage = nil
        state = recorder.state
        levels = recorder.levels
        onCancel?()
    }

    func openSettings() {
#if os(macOS)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
#endif
    }
}
