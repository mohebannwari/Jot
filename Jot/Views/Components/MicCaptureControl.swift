import SwiftUI
import Combine
import os
#if os(macOS)
import AppKit
#endif

private let micLogger = Logger(subsystem: "com.jot", category: "MicCaptureControl")

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

// MARK: - Geometry (concentric radius math)
//
// icon frame:     18 x 18
// button inset:   4pt each side  →  26 x 26 circle
// capsule inset:  4pt each side  →  34pt tall capsule
// capsule radius: 34 / 2 = 17
// inner circle:   26 / 2 = 13    →  17 - 4 = 13 ✓ concentric
//
private enum MicGeometry {
    static let iconSize: CGFloat = 16
    static let buttonInset: CGFloat = 4
    static let buttonDiameter: CGFloat = iconSize + buttonInset * 2   // 26
    static let capsuleInset: CGFloat = 4
    static let innerRadius: CGFloat = buttonDiameter / 2              // 13
}

// MARK: - Subviews
private extension MicCaptureControl {
    var idleView: some View {
        Button {
            HapticManager.shared.buttonTap()
            Task { @MainActor in
                await viewModel.startRecording()
            }
        } label: {
            Image(systemName: "mic")
                .font(FontManager.icon(size: MicGeometry.iconSize, weight: .medium))
                .foregroundStyle(Color("SecondaryTextColor"))
                .frame(width: MicGeometry.iconSize, height: MicGeometry.iconSize)
                .padding(MicGeometry.buttonInset)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .hoverContainer(cornerRadius: MicGeometry.innerRadius)
        .padding(MicGeometry.capsuleInset)
        .thinLiquidGlass(in: Capsule())
        .accessibilityLabel(Text("Start recording"))
    }

    var recordingView: some View {
        HStack(spacing: 4) {
            Button {
                HapticManager.shared.buttonTap()
                Task { @MainActor in
                    await viewModel.pauseRecording()
                }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white, Color.red)
                    .frame(width: MicGeometry.iconSize, height: MicGeometry.iconSize)
                    .padding(MicGeometry.buttonInset)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .accessibilityLabel(Text("Stop recording"))

            WaveformView(
                levels: viewModel.levels,
                barCount: 4,
                barWidth: 3,
                spacing: 3,
                color: Color("SecondaryTextColor")
            )
            .frame(width: 16, height: 16)
            .frame(width: MicGeometry.buttonDiameter, height: MicGeometry.buttonDiameter)
            .padding(.trailing, 4)
        }
        .padding(MicGeometry.capsuleInset)
        .thinLiquidGlass(in: Capsule())
        .overlay(cancelShortcut)
    }

    var pausedView: some View {
        HStack(spacing: 2) {
            Button {
                HapticManager.shared.buttonTap()
                Task { @MainActor in
                    await viewModel.cancelCapture()
                }
            } label: {
                Image("IconCircleX")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.red)
                    .frame(width: MicGeometry.iconSize, height: MicGeometry.iconSize)
                    .padding(MicGeometry.buttonInset)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .hoverContainer(cornerRadius: MicGeometry.innerRadius)
            .accessibilityLabel(Text("Cancel recording"))

            Button {
                HapticManager.shared.buttonTap()
                Task { @MainActor in
                    await viewModel.resumeRecording()
                }
            } label: {
                Image("IconResume")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: MicGeometry.iconSize, height: MicGeometry.iconSize)
                    .padding(MicGeometry.buttonInset)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .hoverContainer(cornerRadius: MicGeometry.innerRadius)
            .accessibilityLabel(Text("Resume recording"))

            Button {
                HapticManager.shared.buttonTap()
                Task { @MainActor in
                    await viewModel.sendRecording()
                }
            } label: {
                if viewModel.isProcessingSend {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                        .frame(width: 16, height: 16)
                        .frame(width: MicGeometry.buttonDiameter, height: MicGeometry.buttonDiameter)
                } else {
                    Image("IconArrowUpCircle")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("AccentColor"))
                        .frame(width: MicGeometry.iconSize, height: MicGeometry.iconSize)
                        .padding(MicGeometry.buttonInset)
                        .contentShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .hoverContainer(cornerRadius: MicGeometry.innerRadius)
            .disabled(viewModel.isProcessingSend)
            .accessibilityLabel(Text(viewModel.isProcessingSend ? "Sending voice note" : "Send voice note"))
        }
        .padding(MicGeometry.capsuleInset)
        .thinLiquidGlass(in: Capsule())
        .overlay(cancelShortcut)
    }



    private var resumeIconColor: Color {
        Color("PrimaryTextColor")
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
                .font(FontManager.icon(size: 16, weight: .semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(FontManager.heading(size: 14, weight: .medium))
                .foregroundStyle(Color.primary)

            Spacer(minLength: 8)

            Button("Open Settings") {
                viewModel.openSettings()
            }
            .font(FontManager.heading(size: 13, weight: .medium))
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule())
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

    private static let shortElapsedFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.zeroFormattingBehavior = .pad
        return f
    }()

    private static let longElapsedFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.zeroFormattingBehavior = .pad
        return f
    }()

    var elapsedTime: String? {
        guard recorder.duration > 0 else { return nil }
        let formatter = recorder.duration >= 3600 ? Self.longElapsedFormatter : Self.shortElapsedFormatter
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
            micLogger.error("MicCaptureViewModel.startRecording failed with recorder error: \(String(describing: error))")
            permissionMessage = error.errorDescription
        } catch {
            micLogger.error("MicCaptureViewModel.startRecording failed with unexpected error: \(String(describing: error))")
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
        guard !isProcessingSend else {
            return
        }

        withAnimation(.bouncy(duration: 0.35)) {
            isProcessingSend = true
        }

        guard let url = await recorder.stop() else {
            withAnimation(.bouncy(duration: 0.35)) {
                isProcessingSend = false
                state = recorder.state
                levels = recorder.levels
            }
            return
        }

        // Verify file exists before attempting transcription
        guard FileManager.default.fileExists(atPath: url.path) else {
            withAnimation(.bouncy(duration: 0.35)) {
                isProcessingSend = false
                state = recorder.state
                levels = recorder.levels
            }
            return
        }

        // Transcribe the audio file
        var transcript: String? = nil
        transcript = await transcriber.transcribe(url: url)

        if transcript?.isEmpty == true {
            transcript = nil
        }

        withAnimation(.bouncy(duration: 0.35)) {
            isProcessingSend = false
            state = recorder.state
            levels = recorder.levels
        }

        // Ensure callback is on main thread
        await MainActor.run {
            onSend(.init(audioURL: url, transcript: transcript))
        }
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
