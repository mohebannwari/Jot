//
//  AudioPreviewRenderer.swift
//  Jot
//
//  Renders an inline audio player with playback controls and a seek slider.
//

import SwiftUI
import AVFoundation

struct AudioPreviewRenderer: View {
    let storedFilename: String
    let containerWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var loadFailed = false
    @State private var progressTimer: Timer?

    private let contentHeight: CGFloat = 80

    var body: some View {
        Group {
            if loadFailed {
                placeholder("Unable to load audio")
            } else if player == nil {
                placeholder("Loading audio...")
            } else {
                audioControls
            }
        }
        .task {
            await loadAudio()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Subviews

    private var audioControls: some View {
        HStack(spacing: 12) {
            playPauseButton
            VStack(alignment: .leading, spacing: 6) {
                seekSlider
                timeLabels
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: containerWidth, height: contentHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? Color("DetailPaneColor") : Color.white)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
    }

    private var playPauseButton: some View {
        Button {
            togglePlayback()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(FontManager.uiHeadingH4(weight: .medium).font)
                .foregroundStyle(Color("PrimaryTextColor"))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    private var seekSlider: some View {
        Slider(
            value: Binding(
                get: { currentTime },
                set: { newValue in
                    currentTime = newValue
                    player?.currentTime = newValue
                }
            ),
            in: 0...max(duration, 0.01)
        )
        .tint(Color("AccentColor"))
    }

    private var timeLabels: some View {
        HStack {
            Text(formatTime(currentTime))
                .jotUI(FontManager.uiLabel5(weight: .regular))
                .foregroundStyle(Color("SecondaryTextColor"))
                .monospacedDigit()
            Spacer()
            Text(formatTime(duration))
                .jotUI(FontManager.uiLabel5(weight: .regular))
                .foregroundStyle(Color("SecondaryTextColor"))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(colorScheme == .dark ? Color("DetailPaneColor") : Color.white)
            .frame(height: contentHeight)
            .overlay {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(FontManager.uiLabel2(weight: .medium).font)
                        .foregroundStyle(Color("IconSecondaryColor"))
                    Text(message)
                        .jotUI(FontManager.uiLabel5(weight: .regular))
                        .foregroundStyle(Color("SecondaryTextColor"))
                }
            }
    }

    // MARK: - Playback

    private func togglePlayback() {
        guard let player else { return }

        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            // Reset to start if playback finished
            if player.currentTime >= player.duration - 0.1 {
                player.currentTime = 0
                currentTime = 0
            }
            player.play()
            startTimer()
        }
        isPlaying = player.isPlaying
    }

    private func stopPlayback() {
        stopTimer()
        player?.stop()
        player = nil
    }

    private func startTimer() {
        stopTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let player, player.isPlaying else {
                isPlaying = false
                stopTimer()
                return
            }
            currentTime = player.currentTime
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Loading

    private func loadAudio() async {
        guard let url = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            loadFailed = true
            return
        }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            player = audioPlayer
            duration = audioPlayer.duration
        } catch {
            loadFailed = true
        }
    }

    // MARK: - Formatting

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
