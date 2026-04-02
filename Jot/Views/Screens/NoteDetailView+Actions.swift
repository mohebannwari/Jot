//
//  NoteDetailView+Actions.swift
//  Jot
//
//  Voice recording, image selection, link insertion, overlay
//  management, and Apple Intelligence handlers.
//

import SwiftUI
import UniformTypeIdentifiers

extension NoteDetailView {

    // MARK: - Apple Intelligence

    @MainActor
    func handleAITool(_ tool: AITool) async {
        let content = AppleIntelligenceService.stripMarkupForAI(editedContent)
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
                scheduleAutosave()
            case .keyPoints:
                let points = try await AppleIntelligenceService.shared.keyPoints(text: content)
                withAnimation(.jotSpring) {
                    aiKeyPointsItems = points
                    aiPanelState = .none
                }
                scheduleAutosave()
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
            case .translate:
                break  // handled by .aiTranslateSubmit notification
            case .textGenerate:
                break  // handled by .aiTextGenSubmit notification
            case .meetingNotes:
                break  // handled by .aiMeetingNotesStart notification
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
        let sourceText = capturedSelectionText.isEmpty
            ? AppleIntelligenceService.stripMarkupForAI(editedContent)
            : capturedSelectionText
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        withAnimation(.jotSpring) {
            aiPanelState = .loading(.editContent)
            showEditContentPanel = true
            aiIsProcessing = true
        }

        let hasSelection = !capturedSelectionText.isEmpty
        do {
            let revised = try await AppleIntelligenceService.shared.editContent(
                text: sourceText, instruction: instruction, isSelection: hasSelection)
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

    /// Apply the revised text from an editPreview state by routing through
    /// the coordinator's text storage (preserving formatting and undo).
    func applyEditContentReplacement() {
        guard case .editPreview(let revised, let range, let originalText, _) = aiPanelState else { return }

        let isFullDocument = range.location == NSNotFound

        var info: [String: Any] = [
            "original": isFullDocument ? "" : originalText,
            "replacement": revised,
            "editorInstanceID": editorInstanceID
        ]
        if aiCaptureIsCardOrigin { info["cardOrigin"] = true }
        NotificationCenter.default.post(
            name: .aiEditApplyReplacement,
            object: nil,
            userInfo: info
        )

        aiCaptureIsCardOrigin = false
        scheduleAutosave()
        withAnimation(.jotSpring) {
            showEditContentPanel = false
            aiPanelState = .none
        }
    }

    /// Applies all remaining proofread suggestions by routing through
    /// the coordinator's text storage (preserving formatting and undo).
    func replaceAllSuggestions() {
        guard case .proofread(let annotations) = aiPanelState, !annotations.isEmpty else { return }

        NotificationCenter.default.post(
            name: .aiProofreadReplaceAll,
            object: nil,
            userInfo: [
                "annotations": annotations,
                "editorInstanceID": editorInstanceID
            ]
        )

        scheduleAutosave()
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

    // MARK: - Translation

    @MainActor
    func handleAITranslate(language: String) async {
        let sourceText = capturedSelectionText.isEmpty
            ? AppleIntelligenceService.stripMarkupForAI(editedContent)
            : capturedSelectionText
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        withAnimation(.jotSpring) {
            aiPanelState = .loading(.translate)
            showTranslatePanel = true
            aiIsProcessing = true
        }

        let hasSelection = !capturedSelectionText.isEmpty
        do {
            let translated = try await AppleIntelligenceService.shared.translate(
                text: sourceText, to: language, isSelection: hasSelection)
            withAnimation(.jotSpring) {
                aiPanelState = .translatePreview(
                    translated: translated,
                    originalRange: capturedSelectionRange,
                    originalText: sourceText,
                    language: language
                )
            }
        } catch {
            withAnimation(.jotSpring) {
                aiPanelState = .error(error.localizedDescription)
                showTranslatePanel = false
            }
        }
        aiIsProcessing = false
    }

    func applyTranslateReplacement() {
        guard case .translatePreview(let translated, let range, let originalText, _) = aiPanelState else { return }

        let isFullDocument = range.location == NSNotFound

        var info: [String: Any] = [
            "original": isFullDocument ? "" : originalText,
            "replacement": translated,
            "editorInstanceID": editorInstanceID
        ]
        if aiCaptureIsCardOrigin { info["cardOrigin"] = true }
        NotificationCenter.default.post(
            name: .aiEditApplyReplacement,
            object: nil,
            userInfo: info
        )

        aiCaptureIsCardOrigin = false
        scheduleAutosave()
        showTranslatePanel = false
        aiPanelState = .none
    }

    func copyTranslation() {
        guard case .translatePreview(let translated, _, _, _) = aiPanelState else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translated, forType: .string)
        withAnimation(.jotSpring) {
            showTranslatePanel = false
            aiPanelState = .none
        }
    }

    func retranslate() {
        guard case .translatePreview(_, _, _, let language) = aiPanelState else { return }
        Task { await handleAITranslate(language: language) }
    }

    // MARK: - Text Generation

    @MainActor
    func handleAITextGenerate(description: String) async {
        withAnimation(.jotSpring) {
            aiPanelState = .loading(.textGenerate)
            showTextGenPanel = true
            aiIsProcessing = true
        }

        do {
            let generated = try await AppleIntelligenceService.shared.generateText(
                description: description)
            withAnimation(.jotSpring) {
                aiPanelState = .textGenPreview(
                    generated: generated,
                    insertionPoint: capturedSelectionRange.location
                )
            }
        } catch {
            withAnimation(.jotSpring) {
                aiPanelState = .error(error.localizedDescription)
            }
        }
        aiIsProcessing = false
    }

    func acceptTextGeneration() {
        if case .textGenPreview(let generated, _) = aiPanelState {
            var info: [String: Any] = ["editorInstanceID": editorInstanceID]
            if aiCaptureIsCardOrigin { info["cardOrigin"] = true }
            NotificationCenter.default.post(
                name: .aiTextGenInsert,
                object: generated,
                userInfo: info
            )
        }
        aiCaptureIsCardOrigin = false
        scheduleAutosave()
        withAnimation(.jotSpring) {
            showTextGenPanel = false
            aiPanelState = .none
        }
    }

    func dismissTextGeneration() {
        withAnimation(.jotSpring) {
            showTextGenPanel = false
            aiPanelState = .none
        }
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

    func openImageFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Images"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                self.handleImageSelection(url)
            }
        }
    }

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
        NotificationCenter.default.post(name: .insertWebLink, object: url, userInfo: ["editorInstanceID": editorInstanceID])
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
        replaceText = ""
        showReplaceField = false
        isReplaceFocused = false
        NotificationCenter.default.post(name: .clearSearchHighlights, object: nil, userInfo: ["editorInstanceID": editorInstanceID])
    }

    func performInNoteSearch(_ query: String) {
        guard !query.isEmpty else {
            searchOnPageMatches = []
            searchOnPageCurrentIndex = 0
            NotificationCenter.default.post(name: .clearSearchHighlights, object: nil, userInfo: ["editorInstanceID": editorInstanceID])
            return
        }

        NotificationCenter.default.post(
            name: .performSearchOnPage,
            object: nil,
            userInfo: [
                "query": query,
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

    // MARK: - Find & Replace

    func toggleReplaceField() {
        showReplaceField.toggle()
        if showReplaceField {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isReplaceFocused = true
            }
        }
    }

    func replaceCurrentMatch() {
        guard !searchOnPageMatches.isEmpty, !searchOnPageQuery.isEmpty else { return }

        NotificationCenter.default.post(
            name: .replaceCurrentSearchMatch,
            object: nil,
            userInfo: [
                "query": searchOnPageQuery,
                "replacement": replaceText,
                "matchIndex": searchOnPageCurrentIndex,
                "editorInstanceID": editorInstanceID
            ]
        )

        // After replacement, re-run search to refresh matches
        DispatchQueue.main.async {
            self.performInNoteSearch(self.searchOnPageQuery)
        }
    }

    func replaceAllMatches() {
        guard !searchOnPageMatches.isEmpty, !searchOnPageQuery.isEmpty else { return }

        NotificationCenter.default.post(
            name: .replaceAllSearchMatches,
            object: nil,
            userInfo: [
                "query": searchOnPageQuery,
                "replacement": replaceText,
                "editorInstanceID": editorInstanceID
            ]
        )

        // After replacement, re-run search (should find 0 matches)
        DispatchQueue.main.async {
            self.performInNoteSearch(self.searchOnPageQuery)
        }
    }

    // MARK: - Meeting Notes

    @MainActor
    func startMeetingRecording() {
        guard meetingRecordingState == .idle else { return }

        meetingSummaryResult = nil
        isMeetingSummaryLoading = false
        meetingManualNotes = ""
        meetingSelectedTab = .transcript

        // Configure audio recorder for meeting mode
        meetingAudioRecorder.setMeetingMode(true)
        let transcriptionService = meetingTranscriptionService
        meetingAudioRecorder.onBufferAvailable = { buffer in
            transcriptionService.feedBuffer(buffer)
        }

        Task {
            do {
                try await meetingAudioRecorder.start()
                meetingTranscriptionService.startTranscription()
                withAnimation(.jotSpring) {
                    meetingRecordingState = .recording
                    showMeetingPanel = true
                }
            } catch {
                withAnimation(.jotSpring) {
                    aiPanelState = .error("Failed to start recording: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    func pauseMeetingRecording() {
        guard meetingRecordingState == .recording else { return }
        Task {
            await meetingAudioRecorder.pause()
            withAnimation(.jotSpring) {
                meetingRecordingState = .paused
            }
        }
    }

    @MainActor
    func resumeMeetingRecording() {
        guard meetingRecordingState == .paused else { return }
        Task {
            try? await meetingAudioRecorder.resume()
            withAnimation(.jotSpring) {
                meetingRecordingState = .recording
            }
        }
    }

    @MainActor
    func stopMeetingRecording() {
        guard meetingRecordingState == .recording || meetingRecordingState == .paused else { return }

        Task {
            // Stop audio and transcription
            let audioURL = await meetingAudioRecorder.stop()
            await meetingTranscriptionService.stopTranscription()

            withAnimation(.jotSpring) {
                meetingRecordingState = .processing
                meetingSelectedTab = .summary
                isMeetingSummaryLoading = true
            }

            // Generate summary
            do {
                let (result, _) = try await meetingSummaryGenerator.generateSummary(
                    from: meetingTranscriptionService.segments,
                    manualNotes: meetingManualNotes
                )

                withAnimation(.jotSpring) {
                    meetingSummaryResult = result
                    isMeetingSummaryLoading = false
                    meetingRecordingState = .complete
                }
            } catch {
                withAnimation(.jotSpring) {
                    isMeetingSummaryLoading = false
                    meetingRecordingState = .complete
                    meetingSummaryResult = MeetingSummaryDisplayResult(
                        title: "Meeting Notes",
                        summary: "Summary generation failed: \(error.localizedDescription)",
                        keyPoints: [],
                        actionItems: [],
                        decisions: []
                    )
                }
            }

            // Cleanup audio file
            if let url = audioURL {
                AudioRecorder.cleanupMeetingAudio(at: url)
            }
        }
    }

    @MainActor
    func saveMeetingNote() {
        guard meetingRecordingState == .complete else { return }

        let newSession = MeetingSession(
            date: Date(),
            summary: meetingSummaryGenerator.formatAsRichText(
                meetingSummaryResult ?? MeetingSummaryDisplayResult(
                    title: "Meeting Notes", summary: "", keyPoints: [], actionItems: [], decisions: []
                )
            ),
            transcript: meetingTranscriptionService.serializedTranscript(),
            duration: meetingAudioRecorder.duration,
            language: meetingTranscriptionService.detectedLanguage,
            manualNotes: meetingManualNotes
        )

        var updatedNote = note
        updatedNote.isMeetingNote = true
        updatedNote.meetingSessions = note.meetingSessions + [newSession]

        // Set the note title from summary if it's still untitled
        if let result = meetingSummaryResult, !result.title.isEmpty {
            let currentTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentTitle.isEmpty || currentTitle == "Untitled" || currentTitle == "New Note" || currentTitle == "Note Title" {
                updatedNote.title = result.title
                editedTitle = result.title
            }
        }

        // Persist
        notesManager.updateNote(updatedNote)

        // Update local state so the detail panel appears immediately
        withAnimation(.jotSpring) {
            savedIsMeetingNote = true
            savedMeetingSessions = updatedNote.meetingSessions
        }

        dismissMeetingPanel()
    }

    @MainActor
    func dismissMeetingPanel() {
        // If still recording, stop first
        if meetingRecordingState == .recording || meetingRecordingState == .paused {
            Task {
                let audioURL = await meetingAudioRecorder.stop()
                await meetingTranscriptionService.stopTranscription()
                if let url = audioURL {
                    AudioRecorder.cleanupMeetingAudio(at: url)
                }
            }
        }

        withAnimation(.jotSpring) {
            showMeetingPanel = false
            meetingRecordingState = .idle
        }

        // Cleanup
        meetingAudioRecorder.onBufferAvailable = nil
        meetingAudioRecorder.setMeetingMode(false)
    }
}
