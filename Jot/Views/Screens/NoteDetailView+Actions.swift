//
//  NoteDetailView+Actions.swift
//  Jot
//
//  Voice recording, image selection, link insertion, overlay
//  management, and Apple Intelligence handlers.
//

import SwiftUI

extension NoteDetailView {

    // MARK: - Apple Intelligence

    @MainActor
    func handleAITool(_ tool: AITool) async {
        let content = editedContent
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.jotSpring) {
            aiPanelState = .loading(tool)
            aiIsProcessing = true
        }
        do {
            switch tool {
            case .summary:
                let result = try await AppleIntelligenceService.shared.summarize(text: content)
                withAnimation(.jotSpring) {
                    aiSummaryText = result
                    aiPanelState = .none
                }
            case .keyPoints:
                let points = try await AppleIntelligenceService.shared.keyPoints(text: content)
                withAnimation(.jotSpring) {
                    aiKeyPointsItems = points
                    aiPanelState = .none
                }
            case .proofread:
                let textToProofread = capturedSelectionText.isEmpty ? content : capturedSelectionText
                let rawAnnotations = try await AppleIntelligenceService.shared.proofread(text: textToProofread)
                let nsContent = content as NSString  // filter against full document for overlay positioning
                let annotations = rawAnnotations.filter {
                    nsContent.range(of: $0.original, options: .literal).location != NSNotFound
                }
                currentProofreadIndex = 0
                withAnimation(.jotSpring) { aiPanelState = .proofread(annotations) }
                NotificationCenter.default.post(name: .aiProofreadClearOverlays, object: nil, userInfo: ["editorInstanceID": editorInstanceID])
                if !annotations.isEmpty {
                    NotificationCenter.default.post(
                        name: .aiProofreadShowAnnotations,
                        object: annotations,
                        userInfo: ["activeIndex": 0, "editorInstanceID": editorInstanceID]
                    )
                }
            case .editContent:
                break  // handled by .aiEditSubmit notification
            }
        } catch {
            withAnimation(.jotSpring) {
                aiPanelState = .error(error.localizedDescription)
            }
        }
        aiIsProcessing = false
    }

    @MainActor
    func handleAIEdit(instruction: String) async {
        let sourceText = capturedSelectionText.isEmpty ? editedContent : capturedSelectionText
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Resolve panel position before showing the panel so it never appears at (0,0)
        if capturedSelectionWindowRect != .zero {
            // FloatingToolbarPositioner reads the real window bounds from NSApp.keyWindow on macOS;
            // the visibleWidth/Height params are only fallbacks for non-macOS paths.
            let result = FloatingToolbarPositioner.calculatePosition(
                selectionWindowX: capturedSelectionWindowRect.minX,
                selectionWindowY: capturedSelectionWindowRect.minY,
                selectionWidth: capturedSelectionWindowRect.width,
                selectionHeight: capturedSelectionWindowRect.height,
                visibleWidth: 0,
                visibleHeight: 0,
                toolbarWidth: 320,
                toolbarHeight: 160
            )
            editContentPanelPosition = result.origin
        }

        withAnimation(.jotSpring) {
            aiPanelState = .loading(.editContent)
            showEditContentPanel = true
            aiIsProcessing = true
        }

        do {
            let revised = try await AppleIntelligenceService.shared.editContent(
                text: sourceText, instruction: instruction)
            withAnimation(.jotSpring) {
                aiPanelState = .editPreview(
                    revised: revised,
                    originalRange: capturedSelectionRange,
                    originalText: sourceText,
                    instruction: instruction
                )
            }
        } catch {
            withAnimation(.jotSpring) {
                aiPanelState = .error(error.localizedDescription)
                showEditContentPanel = false
            }
        }
        aiIsProcessing = false
    }

    /// Apply the revised text from an editPreview state, replacing the captured range or full content.
    func applyEditContentReplacement() {
        guard case .editPreview(let revised, let range, _, _) = aiPanelState else { return }

        if range.location != NSNotFound,
           let swiftRange = Range(range, in: editedContent)
        {
            editedContent.replaceSubrange(swiftRange, with: revised)
        } else {
            editedContent = revised
        }

        scheduleAutosave()
        withAnimation(.jotSpring) {
            showEditContentPanel = false
            aiPanelState = .none
        }
    }

    /// Applies all remaining proofread suggestions to the note text, then clears overlays.
    func replaceAllSuggestions() {
        guard case .proofread(let annotations) = aiPanelState, !annotations.isEmpty else { return }

        var text = editedContent

        // Sort by first-occurrence position descending so replacements don't shift earlier indices
        let sorted: [(annotation: ProofreadAnnotation, location: Int)] = annotations.compactMap { ann in
            let range = (text as NSString).range(of: ann.original, options: .literal)
            guard range.location != NSNotFound else { return nil }
            return (ann, range.location)
        }.sorted { $0.location > $1.location }

        for entry in sorted {
            let ns = text as NSString
            let range = ns.range(of: entry.annotation.original, options: .literal)
            if range.location != NSNotFound {
                text = ns.replacingCharacters(in: range, with: entry.annotation.replacement)
            }
        }

        editedContent = text
        scheduleAutosave()
        NotificationCenter.default.post(name: .aiProofreadClearOverlays, object: nil, userInfo: ["editorInstanceID": editorInstanceID])
        withAnimation(.jotSpring) { aiPanelState = .proofread([]) }
    }

    func navigateToNextProofreadSuggestion() {
        guard case .proofread(let annotations) = aiPanelState, !annotations.isEmpty else { return }
        currentProofreadIndex = (currentProofreadIndex + 1) % annotations.count
        NotificationCenter.default.post(
            name: .aiProofreadShowAnnotations,
            object: annotations,
            userInfo: ["activeIndex": currentProofreadIndex, "editorInstanceID": editorInstanceID]
        )
    }

    func navigateToPrevProofreadSuggestion() {
        guard case .proofread(let annotations) = aiPanelState, !annotations.isEmpty else { return }
        currentProofreadIndex = (currentProofreadIndex - 1 + annotations.count) % annotations.count
        NotificationCenter.default.post(
            name: .aiProofreadShowAnnotations,
            object: annotations,
            userInfo: ["activeIndex": currentProofreadIndex, "editorInstanceID": editorInstanceID]
        )
    }

    /// Re-runs the same instruction from an editPreview state.
    func redoEditContent() {
        guard case .editPreview(_, _, _, let instruction) = aiPanelState else { return }
        Task { await handleAIEdit(instruction: instruction) }
    }

    // MARK: - Voice Recording

    func handleVoiceRecording(_ result: MicCaptureControl.Result) {
        if let transcript = result.transcript, !transcript.isEmpty {
            NotificationCenter.default.post(
                name: .insertVoiceTranscriptInEditor,
                object: transcript,
                userInfo: ["editorInstanceID": editorInstanceID]
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
                        object: filename,
                        userInfo: ["editorInstanceID": self.editorInstanceID]
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
        NotificationCenter.default.post(name: Notification.Name("InsertWebLink"), object: url, userInfo: ["editorInstanceID": editorInstanceID])
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
        NotificationCenter.default.post(name: .clearSearchHighlights, object: nil, userInfo: ["editorInstanceID": editorInstanceID])
    }

    func performInNoteSearch(_ query: String) {
        guard !query.isEmpty else {
            searchOnPageMatches = []
            searchOnPageCurrentIndex = 0
            NotificationCenter.default.post(name: .clearSearchHighlights, object: nil, userInfo: ["editorInstanceID": editorInstanceID])
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
                "activeIndex": searchOnPageCurrentIndex,
                "editorInstanceID": editorInstanceID
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
                "activeIndex": searchOnPageCurrentIndex,
                "editorInstanceID": editorInstanceID
            ]
        )
    }
}
