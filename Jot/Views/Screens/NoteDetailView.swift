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

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NoteDetailView: View {
    let note: Note
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
    @State var galleryPreviewImage: PlatformImage?
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
        focusRequestID: UUID,
        contentTopInsetAdjustment: CGFloat = 0,
        onSave: @escaping (Note) -> Void
    ) {
        self.note = note
        self.focusRequestID = focusRequestID
        self.contentTopInsetAdjustment = contentTopInsetAdjustment
        self.onSave = onSave
        self._editedTitle = State(initialValue: note.title)
        self._editedContent = State(initialValue: note.content)
        self._editedTags = State(initialValue: note.tags)
        self._lastSavedSnapshot = State(
            initialValue: DraftSnapshot(title: note.title, content: note.content, tags: note.tags)
        )
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
        ZStack(alignment: .topLeading) {
            Color.clear
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(noteDateString)
                            .font(FontManager.metadata(size: 11, weight: .medium))
                            .foregroundColor(Color("SecondaryTextColor"))
                            .kerning(-0.25)
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
                        TodoRichTextEditor(
                            text: $editedContent,
                            focusRequestID: localEditorFocusID ?? focusRequestID,
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
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 120)
                        .background(
                            headerMaterialBase
                                .mask(headerMaskGradient)
                                .ignoresSafeArea(edges: .top)
                        )
                        .blur(radius: 0.1)

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
                    .padding(.top, 14)
                }
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
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
            GeometryReader { geometry in
                if showFloatingToolbar {
                    let parentFrame = geometry.frame(in: .global)
                    let localX = floatingToolbarOffset.x - parentFrame.minX
                    let localY = floatingToolbarOffset.y - parentFrame.minY
                    let toolbarWidth: CGFloat = 250
                    let toolbarHeight: CGFloat = 36
                    let centerX = localX + toolbarWidth / 2
                    let centerY = localY + toolbarHeight / 2

                    FloatingEditToolbar(
                        position: floatingToolbarOffset,
                        placeAbove: floatingToolbarPlaceAbove,
                        width: 250,
                        onToolAction: handleEditToolAction
                    )
                    .position(x: centerX, y: centerY)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(100)
                }
            }
        }
        .onAppear {
            updateGalleryPreview(for: editedContent)
            glassElementsVisible = true
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
        .onReceive(NotificationCenter.default.publisher(for: .noteToolsBarAction))
        { notification in
            if let rawValue = notification.object as? String,
               let tool = EditTool(rawValue: rawValue)
            {
                handleEditToolAction(tool)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showInNoteSearch)) { _ in
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
            DispatchQueue.main.async {
                guard let userInfo = notification.userInfo,
                      let hasSelection = userInfo["hasSelection"] as? Bool else { return }

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
            #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
            #endif
        }
    }

    // MARK: - Computed Properties

    private var noteDateString: String {
        Self.dateFormatter.string(from: note.date)
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
            .padding(.top, 4)
    }

    // MARK: - Tags

    private var tagsRow: some View {
        HStack(alignment: .top, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(FontManager.icon(weight: .semibold))
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
                        #if os(macOS)
                        .onExitCommand { cancelTagInput() }
                        #endif
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
        #if os(macOS)
        .onExitCommand {
            if isAddingTag { cancelTagInput() }
        }
        #endif
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
                .init(color: Color.white.opacity(0.96), location: 0.2),
                .init(color: Color.white.opacity(0.8), location: 0.45),
                .init(color: Color.white.opacity(0.45), location: 0.68),
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
        if showVoiceRecorderOverlay || showLinkInputOverlay || showSearchOnPageOverlay {
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
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .animation(.jotSpring, value: showVoiceRecorderOverlay)
            .animation(.jotSpring, value: showLinkInputOverlay)
            .animation(.jotSpring, value: showSearchOnPageOverlay)
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
                .frame(width: 20, height: 20)
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
        #if os(macOS)
        .onExitCommand {
            hideLinkInputOverlay()
        }
        #endif
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
                        .frame(width: 20, height: 20)
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .buttonStyle(.plain)
                .disabled(searchOnPageMatches.isEmpty)

                Button(action: navigateToNextMatch) {
                    Image("IconChevronDownSmall")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
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
        #if os(macOS)
        .onExitCommand {
            dismissSearchOnPage()
        }
        #endif
    }

    // MARK: - Helpers

    private func persistIfNeeded() {
        let snapshot = DraftSnapshot(
            title: editedTitle,
            content: editedContent,
            tags: editedTags
        )
        guard snapshot != lastSavedSnapshot else { return }

        var updatedNote = note
        updatedNote.title = editedTitle
        updatedNote.content = editedContent
        updatedNote.tags = editedTags
        updatedNote.date = Date()

        onSave(updatedNote)
        lastSavedSnapshot = snapshot
    }

    private func scheduleAutosave() {
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
        switch tool {
        case .todo:
            NotificationCenter.default.post(
                name: Notification.Name("TodoToolbarAction"), object: nil)
        default:
            NotificationCenter.default.post(
                name: Notification.Name("applyEditTool"), object: nil, userInfo: ["tool": tool.rawValue])
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
