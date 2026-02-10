//
//  NoteDetailView+Actions.swift
//  Jot
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
        withAnimation(.jotSpring) {
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

    // MARK: - Search on Page

    func presentSearchOnPage() {
        searchOnPageQuery = ""
        searchOnPageMatches = []
        searchOnPageCurrentIndex = 0
        showSearchOnPageOverlay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchOnPageFocused = true
        }
    }

    func dismissSearchOnPage() {
        showSearchOnPageOverlay = false
        searchOnPageQuery = ""
        searchOnPageMatches = []
        searchOnPageCurrentIndex = 0
        isSearchOnPageFocused = false
        NotificationCenter.default.post(name: .clearSearchHighlights, object: nil)
    }

    func performInNoteSearch(_ query: String) {
        guard !query.isEmpty else {
            searchOnPageMatches = []
            searchOnPageCurrentIndex = 0
            NotificationCenter.default.post(name: .clearSearchHighlights, object: nil)
            return
        }

        let nsContent = editedContent as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsContent.length)

        while searchRange.location < nsContent.length {
            let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            let foundRange = nsContent.range(
                of: query,
                options: options,
                range: searchRange
            )
            guard foundRange.location != NSNotFound else { break }
            ranges.append(foundRange)
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = nsContent.length - searchRange.location
        }

        searchOnPageMatches = ranges
        searchOnPageCurrentIndex = ranges.isEmpty ? 0 : 0

        NotificationCenter.default.post(
            name: .highlightSearchMatches,
            object: nil,
            userInfo: [
                "ranges": ranges,
                "activeIndex": searchOnPageCurrentIndex
            ]
        )
    }

    func navigateToNextMatch() {
        guard !searchOnPageMatches.isEmpty else { return }
        searchOnPageCurrentIndex = (searchOnPageCurrentIndex + 1) % searchOnPageMatches.count
        postSearchNavigationUpdate()
    }

    func navigateToPreviousMatch() {
        guard !searchOnPageMatches.isEmpty else { return }
        searchOnPageCurrentIndex = (searchOnPageCurrentIndex - 1 + searchOnPageMatches.count) % searchOnPageMatches.count
        postSearchNavigationUpdate()
    }

    private func postSearchNavigationUpdate() {
        NotificationCenter.default.post(
            name: .highlightSearchMatches,
            object: nil,
            userInfo: [
                "ranges": searchOnPageMatches,
                "activeIndex": searchOnPageCurrentIndex
            ]
        )
    }
}
