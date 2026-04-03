//
//  VideoPreviewRenderer.swift
//  Jot
//
//  Renders a video preview with thumbnail and native playback inline in the note editor.
//

import SwiftUI
import AVKit

struct VideoPreviewRenderer: View {
    let storedFilename: String
    let containerWidth: CGFloat

    @State private var thumbnail: NSImage?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var loadFailed = false

    private let contentHeight: CGFloat = 300

    var body: some View {
        Group {
            if loadFailed {
                placeholder("Unable to load video")
            } else if isPlaying, let player {
                videoPlayer(player: player)
            } else if let thumbnail {
                thumbnailOverlay(image: thumbnail)
            } else {
                placeholder("Loading video...")
            }
        }
        .task {
            await loadThumbnail()
        }
        .onDisappear {
            player?.pause()
            player = nil
            isPlaying = false
        }
    }

    // MARK: - Subviews

    private func videoPlayer(player: AVPlayer) -> some View {
        VideoPlayer(player: player)
            .frame(width: containerWidth, height: contentHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
            .overlay(alignment: .topTrailing) {
                Button {
                    stopPlayback()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .padding(12)
                .accessibilityLabel("Close video player")
            }
    }

    private func thumbnailOverlay(image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: containerWidth, height: contentHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.25))
            }
            .overlay {
                Button {
                    startPlayback()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play video")
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color("SurfaceElevatedColor"))
            .frame(width: containerWidth, height: contentHeight)
            .overlay {
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color("SecondaryTextColor"))
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(Color("SecondaryTextColor"))
                }
            }
    }

    // MARK: - Playback

    private func startPlayback() {
        guard let url = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            return
        }

        let avPlayer = AVPlayer(url: url)
        player = avPlayer
        isPlaying = true
        avPlayer.play()
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
        isPlaying = false
    }

    // MARK: - Thumbnail Generation

    private func loadThumbnail() async {
        guard let url = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            loadFailed = true
            return
        }

        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: containerWidth * 2, height: contentHeight * 2)

        do {
            let cgImage = try await generator.image(at: .zero).image
            thumbnail = NSImage(
                cgImage: cgImage,
                size: CGSize(width: cgImage.width, height: cgImage.height)
            )
        } catch {
            loadFailed = true
        }
    }
}
