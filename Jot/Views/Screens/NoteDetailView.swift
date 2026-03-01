//
//  NoteDetailView.swift
//  Jot
//
//  Created by AI on 15.08.25.
//
//  Figma-aligned note detail view.
//  Gallery logic lives in NoteDetailView+Gallery.swift
//  Voice/image/link handlers live in NoteDetailView+Actions.swift

import SwiftUI

import AppKit

struct NoteDetailView: View {
    let note: Note
    let editorInstanceID: UUID
    let focusRequestID: UUID
    let contentTopInsetAdjustment: CGFloat
    var onSave: (Note) -> Void

    // MARK: - Environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var themeManager: ThemeManager

    // MARK: - Core editing state
    @State private var editedTitle: String
    @State var editedContent: String
    @State private var editedTags: [String]
    @State private var autosaveWorkItem: DispatchWorkItem?
    @State private var lastSavedSnapshot: DraftSnapshot
    /// The note whose content editedTitle/editedContent/editedTags currently describe.
    /// Distinct from `note` (the prop), which SwiftUI updates to the NEW note BEFORE
    /// `onChange(of: note.id)` fires — so `persistIfNeeded()` must use this, not `note`.
    @State private var noteForPersist: Note

    static let imageTagPattern = #"\[\[image\|\|\|([^\]]+)\]\]"#
    static let imageTagRegex = try? NSRegularExpression(pattern: imageTagPattern, options: [])

    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var isAddingTagFocused: Bool

    // MARK: - UI animation state
    @State private var glassElementsVisible = false
    @State private var hoveredTag: String?
    @State private var pressedTag: String?
    @State private var selectedTags: Set<String> = []
    @Namespace private var glassNamespace

    // MARK: - Gallery state (accessed by +Gallery extension)
    @State var galleryPreviewImage: NSImage?
    @State var lastGalleryFilename: String?
    @State var galleryItems: [GalleryGridOverlay.Item] = []
    @State var showGalleryGrid = false

    // MARK: - Overlay state (accessed by +Actions extension)
    @State var showVoiceRecorderOverlay = false
    @State private var showImagePicker = false
    @State var showLinkInputOverlay = false
    @State var linkInputText = ""
    @FocusState var isLinkInputFocused: Bool

    // MARK: - Search on page state (accessed by +Actions extension)
    @State var showSearchOnPageOverlay = false
    @State var searchOnPageQuery = ""
    @State var searchOnPageMatches: [NSRange] = []
    @State var searchOnPageCurrentIndex: Int = 0
    @FocusState var isSearchOnPageFocused: Bool

    // MARK: - Apple Intelligence state
    @State var aiPanelState: AIPanelState = .none   // loading / proofread / editPreview / error
    @State var aiSummaryText: String? = nil          // independent — not cleared by other tools
    @State var aiKeyPointsItems: [String]? = nil     // independent — not cleared by other tools
    @State var aiIsProcessing: Bool = false
    @State private var aiStateCache: [UUID: AIPanelState] = [:]
    @State var currentProofreadIndex: Int = 0

    // Selection capture for Edit Content
    @State var capturedSelectionRange: NSRange = NSRange(location: NSNotFound, length: 0)
    @State var capturedSelectionText: String = ""
    @State var capturedSelectionWindowRect: CGRect = .zero

    // Edit Content floating panel
    @State var showEditContentPanel: Bool = false
    @State var editContentPanelPosition: CGPoint = .zero

    // MARK: - Scroll / toolbar state
    @FocusState private var titleFocused: Bool
    @State private var localEditorFocusID: UUID?

    @State private var showStickyHeader = false
    @State private var headerRevealProgress: CGFloat = 0
    @State private var titleOffset: CGFloat = 0
    @State private var commandMenuNeedsSpace = false
    @State private var showFloatingToolbar = false
    @State private var floatingToolbarOffset = CGPoint.zero
    @State private var floatingToolbarPlaceAbove = false

    // MARK: - Constants

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yy"
        return f
    }()

    private var editorIdentity: String {
        "\(note.id.uuidString)-\(themeManager.currentBodyFontStyle.rawValue)"
    }

    private struct DraftSnapshot: Equatable {
        let title: String
        let content: String
        let tags: [String]
    }

    // MARK: - Init

    init(
        note: Note,
        editorInstanceID: UUID = UUID(),
        focusRequestID: UUID,
        contentTopInsetAdjustment: CGFloat = 0,
        onSave: @escaping (Note) -> Void
    ) {
        self.note = note
        self.editorInstanceID = editorInstanceID
        self.focusRequestID = focusRequestID
        self.contentTopInsetAdjustment = contentTopInsetAdjustment
        self.onSave = onSave
        self._editedTitle = State(initialValue: note.title)
        self._editedContent = State(initialValue: note.content)
        self._editedTags = State(initialValue: note.tags)
        self._lastSavedSnapshot = State(
            initialValue: DraftSnapshot(title: note.title, content: note.content, tags: note.tags)
        )
        self._noteForPersist = State(initialValue: note)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            noteContent
                .blur(radius: showGalleryGrid ? 0.6 : 0)
                .scaleEffect(showGalleryGrid ? 0.996 : 1.0)
                .animation(.smooth(duration: 0.28), value: showGalleryGrid)
                .allowsHitTesting(!showGalleryGrid)

            if showGalleryGrid, !galleryItems.isEmpty {
                GalleryGridOverlay(
                    items: galleryItems,
                    onDismiss: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showGalleryGrid = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)
            }
        }
    }

    // MARK: - Note Content

    private var noteContent: some View {
        noteContentEvents
    }

    private var noteContentLayout: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(noteDateString)
                                .font(FontManager.metadata(size: 11, weight: .medium))
                                .foregroundColor(Color("SecondaryTextColor"))
                                .kerning(-0.25)

                            if note.isArchived {
                                Circle()
                                    .fill(Color("SecondaryTextColor"))
                                    .frame(width: 2, height: 2)

                                Text("Archived")
                                    .font(FontManager.metadata(size: 11, weight: .medium))
                                    .foregroundColor(Color("SecondaryTextColor"))
                                    .kerning(-0.25)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 0)

                        titleField
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .named("scroll")).minY) {
                                            oldValue, newValue in
                                            titleOffset = newValue
                                            let shouldShow = newValue < 0
                                            if shouldShow != showStickyHeader {
                                                withAnimation(.smooth(duration: 0.3)) {
                                                    showStickyHeader = shouldShow
                                                }
                                            }
                                        }
                                }
                            )
                        if FeatureFlags.tagsEnabled {
                            tagsRow
                        }
                        if let summaryText = aiSummaryText {
                            AIResultPanel(
                                state: .summary(summaryText),
                                onDismiss: { withAnimation(.jotSpring) { aiSummaryText = nil } }
                            )
                            .transition(.opacity.combined(with: .offset(y: -8)))
                        }
                        if let keyPointsItems = aiKeyPointsItems {
                            AIResultPanel(
                                state: .keyPoints(keyPointsItems),
                                onDismiss: { withAnimation(.jotSpring) { aiKeyPointsItems = nil } }
                            )
                            .transition(.opacity.combined(with: .offset(y: -8)))
                        }
                        if shouldShowTopPanel {
                            AIResultPanel(
                                state: aiPanelState,
                                onDismiss: {
                                    withAnimation(.jotSpring) { aiPanelState = .none }
                                }
                            )
                            .transition(.opacity.combined(with: .offset(y: -8)))
                        }
                        TodoRichTextEditor(
                            text: $editedContent,
                            focusRequestID: localEditorFocusID ?? focusRequestID,
                            editorInstanceID: editorInstanceID,
                            onToolbarAction: handleEditToolAction,
                            onCommandMenuSelection: handleCommandMenuSelection
                        )
                        .id(editorIdentity)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if commandMenuNeedsSpace {
                            Color.clear
                                .frame(height: 320)
                                .id("menuSpacer")
                        }
                    }
                    .padding(.top, 48 + contentTopInsetAdjustment)
                    .padding(.horizontal, 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollClipDisabled()
                .coordinateSpace(name: "scroll")
                .contentMargins(.bottom, 100, for: .scrollContent)
                .onChange(of: commandMenuNeedsSpace) { _, needsSpace in
                    if needsSpace {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("menuSpacer", anchor: .top)
                            }
                        }
                    }
                }
            }

            // Bottom content fade
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 120)
                    .background(
                        headerMaterialBase
                            .mask(footerMaskGradient)
                    )
                    .blur(radius: 0.1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .zIndex(14)

            // Sticky header
            if showStickyHeader {
                ZStack(alignment: .top) {
                    // Gradient fade — extends into the safe area (title bar zone)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 120)
                        .background(
                            headerMaterialBase
                                .mask(headerMaskGradient)
                                .ignoresSafeArea(edges: .top)
                        )
                        .ignoresSafeArea(edges: .top)
                        .blur(radius: 0.1)

                    // Title — lives in normal content space (same as overlay icons)
                    HStack {
                        Spacer()
                        Text(editedTitle.isEmpty ? "Untitled" : editedTitle)
                            .font(FontManager.heading(size: 12, weight: .medium))
                            .foregroundColor(Color("PrimaryTextColor"))
                            .opacity(0.5)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 80)
                        Spacer()
                    }
                    .frame(height: 18)
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(15)
            }

        }
        .overlay(alignment: .bottomLeading) {
            if let previewImage = galleryPreviewImage {
                GalleryPreviewOverlay(image: previewImage, onTap: {
                    guard !galleryItems.isEmpty else { return }
                    withAnimation(.jotSpring) {
                        showGalleryGrid = true
                    }
                })
                    .padding(.leading, 22)
                    .padding(.bottom, 56)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(40)
            }
        }
        .overlay(alignment: .bottom) {
            bottomOverlay
                .opacity(showFloatingToolbar ? 0.5 : 1.0)
                .animation(.jotSmoothFast, value: showFloatingToolbar)
        }
        .overlay {
            floatingToolbarOverlay
                .allowsHitTesting(showFloatingToolbar && !showEditContentPanel)
        }
        .overlay {
            editContentPanelOverlay
                .allowsHitTesting(showEditContentPanel)
        }
        .preference(
            key: BottomOverlayActivePreferenceKey.self,
            value: showSearchOnPageOverlay || showLinkInputOverlay || showVoiceRecorderOverlay
        )
    }

    // Event handling chain — split from layout to reduce type-checker pressure
    private var noteContentEvents: some View {
        noteContentLayout
        .onAppear {
            updateGalleryPreview(for: editedContent)
            glassElementsVisible = true
            if isNewNote {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    titleFocused = true
                }
            }
        }
        .onDisappear {
            autosaveWorkItem?.cancel()
            persistIfNeeded()
            glassElementsVisible = false
        }
        .onChange(of: editedTitle) { _, newTitle in
            if newTitle.contains("\n") {
                editedTitle = newTitle.replacingOccurrences(of: "\n", with: "")
                titleFocused = false
                localEditorFocusID = UUID()
                return
            }
            scheduleAutosave()
        }
        .onChange(of: editedContent) { newValue in
            updateGalleryPreview(for: newValue)
            scheduleAutosave()
        }
        .onChange(of: editedTags) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: note.id) { oldNoteID, newNoteID in
            autosaveWorkItem?.cancel()
            persistIfNeeded()
            // Advance noteForPersist to the new note AFTER the save above.
            // persistIfNeeded() must see the OLD note (via noteForPersist) to save correctly.
            noteForPersist = note

            // Cache current state (don't cache editPreview — it's contextual to a selection)
            if case .editPreview = aiPanelState {
                aiStateCache[oldNoteID] = nil
            } else {
                aiStateCache[oldNoteID] = aiPanelState == .none ? nil : aiPanelState
            }

            // Tear down transient overlays
            aiIsProcessing = false
            showEditContentPanel = false
            aiSummaryText = nil
            aiKeyPointsItems = nil
            currentProofreadIndex = 0
            NotificationCenter.default.post(name: .aiProofreadClearOverlays, object: nil, userInfo: ["editorInstanceID": editorInstanceID])

            // Restore standard note fields
            editedTitle = note.title
            editedContent = note.content
            editedTags = note.tags
            lastSavedSnapshot = DraftSnapshot(title: note.title, content: note.content, tags: note.tags)
            if isNewNote {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    titleFocused = true
                }
            }
            galleryPreviewImage = nil; lastGalleryFilename = nil
            galleryItems = []; showGalleryGrid = false
            showVoiceRecorderOverlay = false; showLinkInputOverlay = false; showImagePicker = false
            capturedSelectionRange = NSRange(location: NSNotFound, length: 0)
            capturedSelectionText = ""; capturedSelectionWindowRect = .zero

            // Restore cached AI state for new note
            let newState = aiStateCache[newNoteID] ?? .none
            aiPanelState = newState

            // Re-apply proofread overlays if that was the cached state
            if case .proofread(let annotations) = newState, !annotations.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(
                        name: .aiProofreadShowAnnotations,
                        object: annotations,
                        userInfo: ["activeIndex": 0, "editorInstanceID": self.editorInstanceID]
                    )
                }
            }

            updateGalleryPreview(for: note.content)
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteToolsBarAction))
        { notification in
            handleNoteToolsBarNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiToolAction)) { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            guard let tool = notification.object as? AITool else { return }
            Task { await handleAITool(tool) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiEditSubmit)) { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            guard let instruction = notification.object as? String else { return }
            Task { await handleAIEdit(instruction: instruction) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiEditCaptureSelection)) { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            guard let userInfo = notification.userInfo else { return }
            capturedSelectionRange = (userInfo["nsRange"] as? NSRange) ?? NSRange(location: NSNotFound, length: 0)
            capturedSelectionText = (userInfo["selectedText"] as? String) ?? ""
            capturedSelectionWindowRect = (userInfo["windowRect"] as? CGRect) ?? .zero
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiProofreadApplySuggestion)) { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            guard let userInfo = notification.userInfo,
                  let original = userInfo["original"] as? String else { return }
            if case .proofread(var annotations) = aiPanelState {
                annotations.removeAll { $0.original == original }
                currentProofreadIndex = annotations.isEmpty ? 0 : min(currentProofreadIndex, annotations.count - 1)
                withAnimation(.jotSpring) { aiPanelState = .proofread(annotations) }
                if !annotations.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(
                            name: .aiProofreadShowAnnotations,
                            object: annotations,
                            userInfo: ["activeIndex": self.currentProofreadIndex, "editorInstanceID": self.editorInstanceID]
                        )
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showInNoteSearch)) { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            presentSearchOnPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowCommandMenu")))
        { notification in
            DispatchQueue.main.async {
                if let info = notification.object as? [String: Any],
                    let needsSpace = info["needsSpace"] as? Bool
                {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.commandMenuNeedsSpace = needsSpace
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HideCommandMenu")))
        { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.commandMenuNeedsSpace = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .textSelectionChanged))
        { notification in
            handleTextSelectionChanged(notification)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(
                onImagesSelected: { urls in
                    showImagePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        urls.forEach { url in
                            handleImageSelection(url)
                        }
                    }
                },
                onDismiss: {
                    showImagePicker = false
                }
            )
            .frame(minWidth: 800, minHeight: 600)
        }
    }

    // MARK: - Extracted Overlays (reduce type-checker pressure on noteContent)

    @ViewBuilder
    private var editContentPanelOverlay: some View {
        GeometryReader { geometry in
            if showEditContentPanel {
                let parentFrame = geometry.frame(in: .global)
                let localX = floatingToolbarOffset.x - parentFrame.minX
                let localY = floatingToolbarOffset.y - parentFrame.minY
                let estimatedWidth: CGFloat = 280
                let centerX = min(
                    max(localX + estimatedWidth / 2, estimatedWidth / 2),
                    geometry.size.width - estimatedWidth / 2
                )
                let centerY = localY - 20

                EditContentFloatingPanel(
                    state: aiPanelState,
                    onReplace: { applyEditContentReplacement() },
                    onDismiss: {
                        withAnimation(.jotSpring) {
                            showEditContentPanel = false
                            aiPanelState = .none
                        }
                    },
                    onRedo: { redoEditContent() }
                )
                .position(x: centerX, y: centerY)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                .zIndex(150)
            }
        }
        .allowsHitTesting(showEditContentPanel)
    }


    @ViewBuilder
    private var floatingToolbarOverlay: some View {
        GeometryReader { geometry in
            if showFloatingToolbar && !showEditContentPanel {
                let parentFrame = geometry.frame(in: .global)
                let localX = floatingToolbarOffset.x - parentFrame.minX
                let localY = floatingToolbarOffset.y - parentFrame.minY
                let toolbarWidth: CGFloat = 250
                let toolbarHeight: CGFloat = 36
                let paneWidth: CGFloat = geometry.size.width
                let edgeInset: CGFloat = 12
                let centerX: CGFloat = localX + toolbarWidth / 2
                let clampedCenterX: CGFloat = min(max(centerX, toolbarWidth / 2 + edgeInset), paneWidth - toolbarWidth / 2 - edgeInset)
                let centerY: CGFloat = localY + toolbarHeight / 2

                FloatingEditToolbar(
                    position: floatingToolbarOffset,
                    placeAbove: floatingToolbarPlaceAbove,
                    width: 250,
                    onToolAction: handleEditToolAction
                )
                .position(x: clampedCenterX, y: centerY)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .zIndex(100)

                // Color picker — positioned ABOVE the toolbar, centered, with 4px gap
                let colorPillWidth: CGFloat = 186
                let colorPillHeight: CGFloat = 36
                let colorPickerGap: CGFloat = 4
                let colorPickerY: CGFloat = centerY - toolbarHeight / 2 - colorPickerGap - colorPillHeight / 2
                let clampedColorX: CGFloat = min(
                    max(colorPillWidth / 2 + edgeInset, clampedCenterX),
                    paneWidth - colorPillWidth / 2 - edgeInset
                )

                FloatingColorPicker(onColorSelected: { [editorInstanceID] hex in
                    NotificationCenter.default.post(
                        name: Notification.Name("applyTextColor"),
                        object: nil,
                        userInfo: ["hex": hex, "editorInstanceID": editorInstanceID]
                    )
                })
                .position(x: clampedColorX, y: colorPickerY)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .zIndex(100)
            }
        }
    }

    // MARK: - Notification Handlers (extracted to reduce type-checker pressure)

    private func handleTextSelectionChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo,
                  let hasSelection = userInfo["hasSelection"] as? Bool else { return }

            // If this notification is from a different pane, dismiss our toolbar
            if let notifID = userInfo["editorInstanceID"] as? UUID,
               notifID != self.editorInstanceID {
                if hasSelection {
                    withAnimation(.smooth(duration: 0.15)) { self.showFloatingToolbar = false }
                }
                return
            }

            if hasSelection,
               let selectionWidth = userInfo["selectionWidth"] as? CGFloat,
               let selectionHeight = userInfo["selectionHeight"] as? CGFloat,
               let selectionWindowY = userInfo["selectionWindowY"] as? CGFloat,
               let selectionWindowX = userInfo["selectionWindowX"] as? CGFloat,
               let visibleWidth = userInfo["visibleWidth"] as? CGFloat,
               let visibleHeight = userInfo["visibleHeight"] as? CGFloat {

                let result = FloatingToolbarPositioner.calculatePosition(
                    selectionWindowX: selectionWindowX,
                    selectionWindowY: selectionWindowY,
                    selectionWidth: selectionWidth,
                    selectionHeight: selectionHeight,
                    visibleWidth: visibleWidth,
                    visibleHeight: visibleHeight
                )

                withAnimation(.jotSmoothFast) {
                    self.floatingToolbarOffset = result.origin
                    self.floatingToolbarPlaceAbove = result.placeAbove
                    self.showFloatingToolbar = true
                }
            } else {
                withAnimation(.smooth(duration: 0.15)) {
                    self.showFloatingToolbar = false
                }
            }
        }
    }

    private func handleNoteToolsBarNotification(_ notification: Notification) {
        if let notifID = notification.userInfo?["editorInstanceID"] as? UUID,
           notifID != self.editorInstanceID { return }
        if let rawValue = notification.object as? String,
           let tool = EditTool(rawValue: rawValue)
        {
            handleEditToolAction(tool)
        }
    }

    // MARK: - Computed Properties

    private var noteDateString: String {
        Self.dateFormatter.string(from: note.date)
    }

    var shouldShowTopPanel: Bool {
        switch aiPanelState {
        case .error: return true
        case .loading(let tool):
            return tool == .summary || tool == .keyPoints
        default: return false
        }
    }

    private var isNewNote: Bool {
        let hasMinimalTitle =
            editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || editedTitle == "Untitled" || editedTitle == "Note Title"
            || editedTitle == "New Note"
        let hasMinimalContent = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return hasMinimalTitle && hasMinimalContent
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("Note Title", text: $editedTitle, axis: .vertical)
            .font(FontManager.heading(size: 32, weight: .medium))
            .foregroundColor(Color("PrimaryTextColor"))
            .textFieldStyle(.plain)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .focused($titleFocused)
            .onKeyPress(.return) {
                titleFocused = false
                localEditorFocusID = UUID()
                return .handled
            }
            .padding(.top, 4)
    }

    // MARK: - Tags

    private var tagsRow: some View {
        HStack(alignment: .top, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(FontManager.icon(size: 18, weight: .semibold))
                    .foregroundColor(
                        isAddingTag ? Color("AccentColor") : Color("SecondaryTextColor"))

                if isAddingTag {
                    TextField("New tag", text: $newTagText)
                        .font(FontManager.heading(size: 12, weight: .semibold))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                        .focused($isAddingTagFocused)
                        .onSubmit(addTag)
                        .onExitCommand { cancelTagInput() }
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                isAddingTagFocused = true
                            }
                        }
                } else if isNewNote {
                    Text("New tag")
                        .font(FontManager.heading(size: 12, weight: .semibold))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: 28)
            .frame(width: isAddingTag ? 128 : (isNewNote ? nil : 28))
            .overlay(
                Capsule()
                    .strokeBorder(Color("BorderSubtleColor"), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .background(
                Capsule()
                    .fill(Color.clear)
                    .frame(height: 44)
            )
            .contentShape(Capsule())
            .onTapGesture {
                if !isAddingTag {
                    HapticManager.shared.tagInteraction()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isAddingTag = true
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isAddingTag)
            .macPointingHandCursor()

            if !editedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(editedTags, id: \.self) { tag in
                            TagPill(
                                text: tag,
                                isSelected: selectedTags.contains(tag),
                                isHovered: hoveredTag == tag,
                                isPressed: pressedTag == tag,
                                visible: glassElementsVisible,
                                onRemove: { removeTag(tag) },
                                glassNamespace: glassNamespace
                            )
                            .onHover { hovering in
                                withAnimation(.bouncy(duration: 0.2)) {
                                    hoveredTag =
                                        hovering ? tag : (hoveredTag == tag ? nil : hoveredTag)
                                }
                            }
                            .onTapGesture {
                                HapticManager.shared.tagInteraction()
                                withAnimation(.jotBounce) {
                                    if selectedTags.contains(tag) {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                }
                            }
                            .onLongPressGesture(
                                minimumDuration: 0,
                                pressing: { pressing in
                                    withAnimation(.bouncy(duration: 0.15)) {
                                        pressedTag =
                                            pressing ? tag : (pressedTag == tag ? nil : pressedTag)
                                    }
                                }, perform: {})
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollClipDisabled(true)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onExitCommand {
            if isAddingTag { cancelTagInput() }
        }
    }

    // MARK: - Header Styling Helpers

    @ViewBuilder
    private var headerMaterialBase: some View {
        if reduceTransparency || colorScheme == .dark {
            Rectangle().fill(detailPaneDarkBackground)
        } else {
            Rectangle()
                .fill(.ultraThickMaterial)
                .overlay(Rectangle().fill(Color("BackgroundColor").opacity(0.70)))
        }
    }

    private var detailPaneDarkBackground: Color {
        Color(red: 0.047, green: 0.039, blue: 0.035)
    }

    private var headerMaskGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white, location: 0.0),
                .init(color: Color.white, location: 0.28),
                .init(color: Color.white.opacity(0.85), location: 0.45),
                .init(color: Color.white.opacity(0.45), location: 0.65),
                .init(color: Color.white.opacity(0.18), location: 0.82),
                .init(color: Color.clear, location: 1.0),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var footerMaskGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.clear, location: 0.0),
                .init(color: Color.white.opacity(0.18), location: 0.18),
                .init(color: Color.white.opacity(0.45), location: 0.32),
                .init(color: Color.white.opacity(0.8), location: 0.55),
                .init(color: Color.white.opacity(0.96), location: 0.8),
                .init(color: Color.white, location: 1.0),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Bottom Overlay

    @ViewBuilder
    private var bottomOverlay: some View {
        let proofreadAnnotations: [ProofreadAnnotation]? = {
            if case .proofread(let a) = aiPanelState { return a }
            return nil
        }()
        let showProofreadLoading: Bool = {
            if case .loading(.proofread) = aiPanelState { return true }
            return false
        }()
        let showProofreadSuggestions = !(proofreadAnnotations?.isEmpty ?? true)
        let showProofreadSuccess = proofreadAnnotations?.isEmpty == true
        let showAnyOverlay = showVoiceRecorderOverlay || showLinkInputOverlay
            || showSearchOnPageOverlay || showProofreadLoading
            || showProofreadSuggestions || showProofreadSuccess

        if showAnyOverlay {
            VStack(spacing: 12) {
                if showSearchOnPageOverlay {
                    HStack {
                        Spacer()
                        searchOnPagePrompt
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        Spacer()
                    }
                }

                if showLinkInputOverlay {
                    HStack {
                        Spacer()
                        linkInputPrompt
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        Spacer()
                    }
                }

                if showVoiceRecorderOverlay {
                    HStack {
                        Spacer()
                        voiceRecorderControl
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        Spacer()
                    }
                }

                if showProofreadLoading {
                    HStack {
                        Spacer()
                        proofreadLoadingPill
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        Spacer()
                    }
                }

                if showProofreadSuggestions, let annotations = proofreadAnnotations {
                    HStack {
                        Spacer()
                        proofreadSuggestionsBar(annotations: annotations)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        Spacer()
                    }
                }

                if showProofreadSuccess {
                    HStack {
                        Spacer()
                        looksGoodPill
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .animation(.jotSpring, value: showVoiceRecorderOverlay)
            .animation(.jotSpring, value: showLinkInputOverlay)
            .animation(.jotSpring, value: showSearchOnPageOverlay)
            .animation(.jotSpring, value: showProofreadLoading)
            .animation(.jotSpring, value: showProofreadSuggestions)
            .animation(.jotSpring, value: showProofreadSuccess)
        }
    }

    private var proofreadLoadingPill: some View {
        HStack(spacing: 8) {
            Image("IconBroomSparkle")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(width: 18, height: 18)
            Text("Proofreading...")
                .font(FontManager.heading(size: 12, weight: .medium))
                .foregroundColor(Color("PrimaryTextColor"))
                .shimmering(active: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func proofreadSuggestionsBar(annotations: [ProofreadAnnotation]) -> some View {
        let count = annotations.count
        let clampedIndex = count > 0 ? min(currentProofreadIndex, count - 1) : 0
        let current = count > 0 ? annotations[clampedIndex] : nil

        return VStack(alignment: .leading, spacing: 8) {
            if let current {
                HStack(spacing: 8) {
                    Text(current.original)
                        .strikethrough()
                        .font(FontManager.body(size: 16, weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color("SecondaryBackgroundColor"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text(current.replacement)
                        .font(FontManager.body(size: 16, weight: .regular))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color("SecondaryBackgroundColor"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if count > 1 {
                    Text("\(clampedIndex + 1)/\(count)")
                        .font(FontManager.heading(size: 12, weight: .medium).monospacedDigit())
                        .foregroundColor(Color("SecondaryTextColor"))
                        .padding(.leading, 8)

                    Button { navigateToPrevProofreadSuggestion() } label: {
                        Image("IconChevronTopSmall")
                            .renderingMode(.template)
                            .resizable().scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    .foregroundColor(Color("SecondaryTextColor"))
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                    .subtleHoverScale(1.04)

                    Button { navigateToNextProofreadSuggestion() } label: {
                        Image("IconChevronDownSmall")
                            .renderingMode(.template)
                            .resizable().scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    .foregroundColor(Color("SecondaryTextColor"))
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                    .subtleHoverScale(1.04)
                }

                Spacer()

                Button("Done") {
                    NotificationCenter.default.post(name: .aiProofreadClearOverlays, object: nil, userInfo: ["editorInstanceID": editorInstanceID])
                    withAnimation(.jotSpring) { aiPanelState = .none }
                }
                .font(FontManager.heading(size: 12, weight: .regular))
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .liquidGlass(in: Capsule())
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.04)

                Button("Replace All") {
                    replaceAllSuggestions()
                }
                .font(FontManager.heading(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.accentColor, in: Capsule())
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.04)
            }
        }
        .padding(8)
        .frame(maxWidth: 360)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var looksGoodPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
            Text("Looks good")
                .font(FontManager.heading(size: 12, weight: .medium))
                .foregroundColor(Color("PrimaryTextColor"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(in: Capsule())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.jotSpring) { aiPanelState = .none }
            }
        }
    }

    private var voiceRecorderControl: some View {
        MicCaptureControl(
            onSend: { result in
                processVoiceRecorderResult(result)
            },
            onCancel: {
                dismissVoiceRecorderOverlay()
            },
            autoStart: true
        )
    }

    private var linkInputPrompt: some View {
        HStack(spacing: 8) {
            Image("insert link")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundColor(Color("SecondaryTextColor"))

            TextField("Enter URL", text: $linkInputText)
                .textFieldStyle(.plain)
                .font(FontManager.heading(size: 12, weight: .medium))
                .foregroundColor(Color("PrimaryTextColor"))
                .focused($isLinkInputFocused)
                .submitLabel(.done)
                .onSubmit(submitLink)

            Button(action: submitLink) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(FontManager.heading(size: 20, weight: .regular))
                    .foregroundColor(
                        linkInputText.isEmpty ? Color("SecondaryTextColor") : Color("AccentColor"))
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .disabled(linkInputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(in: Capsule())
        .frame(maxWidth: 200)
        .onExitCommand {
            hideLinkInputOverlay()
        }
    }

    // MARK: - Search on Page Overlay

    private var searchCountLabel: String {
        guard !searchOnPageMatches.isEmpty else {
            return "0/0"
        }
        return "\(searchOnPageCurrentIndex + 1)/\(searchOnPageMatches.count)"
    }

    private var searchOnPagePrompt: some View {
        HStack(spacing: 8) {
            Text(searchCountLabel)
                .font(FontManager.heading(size: 12, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .trailing)

            TextField("Search", text: $searchOnPageQuery)
                .textFieldStyle(.plain)
                .font(FontManager.heading(size: 12, weight: .medium))
                .foregroundColor(Color("PrimaryTextColor"))
                .focused($isSearchOnPageFocused)
                .onChange(of: searchOnPageQuery) { _, newValue in
                    performInNoteSearch(newValue)
                }
                .onSubmit { navigateToNextMatch() }

            HStack(spacing: 4) {
                Button(action: navigateToPreviousMatch) {
                    Image("IconChevronTopSmall")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .buttonStyle(.plain)
                .disabled(searchOnPageMatches.isEmpty)

                Button(action: navigateToNextMatch) {
                    Image("IconChevronDownSmall")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .buttonStyle(.plain)
                .disabled(searchOnPageMatches.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlass(in: Capsule())
        .frame(maxWidth: 240)
        .onExitCommand {
            dismissSearchOnPage()
        }
    }

    // MARK: - Helpers

    private func persistIfNeeded() {
        let snapshot = DraftSnapshot(
            title: editedTitle,
            content: editedContent,
            tags: editedTags
        )
        guard snapshot != lastSavedSnapshot else { return }

        // Use noteForPersist, NOT note. SwiftUI updates `note` to the NEW note before
        // onChange(of: note.id) fires, so `note` here already has the wrong ID.
        var updatedNote = noteForPersist
        updatedNote.title = editedTitle
        updatedNote.content = editedContent
        updatedNote.tags = editedTags
        updatedNote.date = Date()

        onSave(updatedNote)
        lastSavedSnapshot = snapshot
    }

    func scheduleAutosave() {
        autosaveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            persistIfNeeded()
        }
        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !editedTags.contains(trimmed) else {
            cancelTagInput()
            return
        }
        editedTags.append(trimmed)
        cancelTagInput()
    }

    private func removeTag(_ tag: String) {
        editedTags.removeAll { $0 == tag }
    }

    private func cancelTagInput() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isAddingTag = false
        }
        newTagText = ""
        isAddingTagFocused = false
    }

    private func handleEditToolAction(_ tool: EditTool) {
        if performAuxiliaryToolAction(tool) {
            return
        }
        let eidInfo: [String: Any] = ["editorInstanceID": editorInstanceID]
        switch tool {
        case .todo:
            NotificationCenter.default.post(
                name: Notification.Name("TodoToolbarAction"), object: nil, userInfo: eidInfo)
        default:
            var info = eidInfo
            info["tool"] = tool.rawValue
            NotificationCenter.default.post(
                name: Notification.Name("applyEditTool"), object: nil, userInfo: info)
        }
    }

    private func handleCommandMenuSelection(_ tool: EditTool) {
        _ = performAuxiliaryToolAction(tool)
    }

    @discardableResult
    private func performAuxiliaryToolAction(_ tool: EditTool) -> Bool {
        switch tool {
        case .imageUpload:
            hideLinkInputOverlay()
            showImagePicker = true
            return true
        case .voiceRecord:
            hideLinkInputOverlay()
            showVoiceRecorderOverlay = true
            return true
        case .link:
            presentLinkInputOverlay()
            return true
        case .searchOnPage:
            presentSearchOnPage()
            return true
        default:
            return false
        }
    }
}

// MARK: - Preference Keys

struct TitleOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BottomOverlayActivePreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
