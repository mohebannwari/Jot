//
//  NoteDetailView+Actions.swift
//  Noty
//
//  Voice recording, image selection, link insertion, and overlay
//  management extracted from NoteDetailView.
//

import SwiftUI

extension NoteDetailView {

    // MARK: - Voice Recording

    func handleVoiceRecording(_ result: MicCaptureControl.Result) {
        if let transcript = result.transcript, !transcript.isEmpty {
            NotificationCenter.default.post(
                name: .insertVoiceTranscriptInEditor,
                object: transcript
            )
        }

        try? FileManager.default.removeItem(at: result.audioURL)
    }

    func processVoiceRecorderResult(_ result: MicCaptureControl.Result) {
        handleVoiceRecording(result)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.dismissVoiceRecorderOverlay()
        }
    }

    func dismissVoiceRecorderOverlay() {
        guard showVoiceRecorderOverlay else { return }
        withAnimation(.notySpring) {
            showVoiceRecorderOverlay = false
        }
    }

    // MARK: - Image Selection

    func handleImageSelection(_ imageURL: URL) {
        Task {
            if let filename = await ImageStorageManager.shared.saveImage(from: imageURL) {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .insertImageInEditor,
                        object: filename
                    )
                }
            }

            try? FileManager.default.removeItem(at: imageURL)
        }
    }

    // MARK: - Link Input

    func presentLinkInputOverlay() {
        linkInputText = ""
        showLinkInputOverlay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isLinkInputFocused = true
        }
    }

    func hideLinkInputOverlay() {
        showLinkInputOverlay = false
        linkInputText = ""
        isLinkInputFocused = false
    }

    func submitLink() {
        let trimmed = linkInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hideLinkInputOverlay()
            return
        }

        HapticManager.shared.toolbarAction()

        var finalURL = trimmed
        if !finalURL.hasPrefix("http://") && !finalURL.hasPrefix("https://") {
            finalURL = "https://" + finalURL
        }

        handleLinkInsert(finalURL)
        hideLinkInputOverlay()
    }

    func handleLinkInsert(_ url: String) {
        NotificationCenter.default.post(name: Notification.Name("InsertWebLink"), object: url)
    }
}
