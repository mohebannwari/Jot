//
//  NoteDetailView.swift
//  Noty
//
//  Created by AI on 15.08.25.
//
//  Simpler, Figma-aligned note detail view

import SwiftUI

struct NoteDetailView: View {
    let note: Note
    @Binding var isPresented: Bool
    var onSave: (Note) -> Void
    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var editedTags: [String]

    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var isAddingTagFocused: Bool

    // Liquid glass animation states
    @State private var isViewMaterialized = false
    @State private var glassElementsVisible = false
    @State private var bottomControlsExpanded = false
    @State private var hoveredTag: String?
    @State private var pressedTag: String?
    @State private var selectedTags: Set<String> = []
    @Namespace private var glassNamespace

    // Edit toolbar state
    @State private var isEditToolbarExpanded = false
    @StateObject private var textFormattingManager = TextFormattingManager()

    // Scroll tracking state
    @State private var showStickyHeader = false
    @State private var headerRevealProgress: CGFloat = 0
    @State private var titleOffset: CGFloat = 0
    @State private var commandMenuNeedsSpace = false
    
    // Floating toolbar state (for text selection)
    @State private var showFloatingToolbar = false
    @State private var floatingToolbarOffset = CGPoint.zero
    @State private var floatingToolbarPlaceAbove = false

    init(note: Note, isPresented: Binding<Bool>, onSave: @escaping (Note) -> Void) {
        self.note = note
        self._isPresented = isPresented
        self.onSave = onSave
        self._editedTitle = State(initialValue: note.title)
        self._editedContent = State(initialValue: note.content)
        self._editedTags = State(initialValue: note.tags)

        print("DEBUG: NoteDetailView init - note.content: '\(note.content.prefix(100))...'")
        print(
            "DEBUG: NoteDetailView init - editedContent will be initialized with: '\(note.content.prefix(100))...'"
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        titleField
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .named("scroll")).minY) {
                                            oldValue, newValue in
                                            titleOffset = newValue
                                            let shouldShow = newValue < 0

                                            print(
                                                "🔵 SCROLL: titleOffset=\(newValue), shouldShow=\(shouldShow)"
                                            )

                                            if shouldShow != showStickyHeader {
                                                print("🟢 TOGGLING HEADER TO: \(shouldShow)")
                                                withAnimation(.smooth(duration: 0.3)) {
                                                    showStickyHeader = shouldShow
                                                }
                                            }
                                        }
                                }
                            )
                        tagsRow
                        // Body text editor - unified with header, flows naturally
                        TodoRichTextEditor(
                            text: $editedContent,
                            onToolbarAction: handleEditToolAction
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Dynamic spacer for CommandMenu when it appears at bottom
                        if commandMenuNeedsSpace {
                            Color.clear
                                .frame(height: 320)
                                .id("menuSpacer")
                        }
                    }
                    .padding(.top, 72)
                    .padding(.horizontal, 42)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollClipDisabled()  // Prevent clipping of CommandMenu overlay
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

            // Progressive blur header - Apple style
            if showStickyHeader {
                ZStack(alignment: .top) {
                    // Single blur layer with progressive gradient mask
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 120)
                        .background(.ultraThickMaterial, ignoresSafeAreaEdges: .top)
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black.opacity(0.95), location: 0.25),
                                    .init(color: .black.opacity(0.9), location: 0.35),
                                    .init(color: .black.opacity(0.7), location: 0.5),
                                    .init(color: .black.opacity(0.4), location: 0.65),
                                    .init(color: .black.opacity(0.15), location: 0.8),
                                    .init(color: .black.opacity(0.0), location: 0.9),
                                    .init(color: .clear, location: 1.0),
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blur(radius: 0.1)

                    // Title text on top - using SF Pro Compact for headings
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

            // Back button stays on top
            backButton
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .zIndex(20)
        }
        .overlay(alignment: .bottom) {
            bottomGlassControls
                .opacity(showFloatingToolbar ? 0.5 : 1.0)
                .animation(.smooth(duration: 0.2), value: showFloatingToolbar)
        }
        .overlay(alignment: .topLeading) {
            // Floating toolbar overlay - appears near selected text (like CommandMenu)
            if showFloatingToolbar {
                FloatingEditToolbar(
                    position: floatingToolbarOffset,
                    placeAbove: floatingToolbarPlaceAbove,
                    onToolAction: handleEditToolAction,
                    onLinkInsert: handleLinkInsert
                )
                .offset(x: floatingToolbarOffset.x, y: floatingToolbarOffset.y)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .opacity(isViewMaterialized ? 1 : 0)
        .offset(x: isViewMaterialized ? 0 : 40)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isViewMaterialized)
        .onAppear {
            // Safety check to prevent crashes on appear
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    self.isViewMaterialized = true
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82).delay(0.1)) {
                    self.glassElementsVisible = true
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82).delay(0.15)) {
                    self.bottomControlsExpanded = true
                }
            }
        }
        .onDisappear {
            // Safety check to prevent crashes on disappear
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    self.isViewMaterialized = false
                    self.glassElementsVisible = false
                    self.bottomControlsExpanded = false
                }
            }
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
                   let selectionX = userInfo["selectionX"] as? CGFloat,
                   let selectionY = userInfo["selectionY"] as? CGFloat,
                   let selectionWidth = userInfo["selectionWidth"] as? CGFloat,
                   let visibleWidth = userInfo["visibleWidth"] as? CGFloat,
                   let placeAbove = userInfo["placeAbove"] as? Bool {
                    
                    // Y position is already calculated with gap in TodoRichTextEditor
                    let toolbarY = selectionY
                    
                    // Calculate X position with horizontal constraints
                    let estimatedToolbarWidth: CGFloat = 550  // Estimated max width of toolbar
                    let edgePadding: CGFloat = 20  // Minimum distance from edges
                    let halfToolbarWidth = estimatedToolbarWidth / 2
                    
                    // Center on selection by default
                    var toolbarX = selectionX + (selectionWidth / 2) - halfToolbarWidth
                    
                    // Ensure toolbar doesn't go off the left edge
                    if toolbarX < edgePadding {
                        toolbarX = edgePadding
                    }
                    
                    // Ensure toolbar doesn't go off the right edge
                    let maxX = visibleWidth - estimatedToolbarWidth - edgePadding
                    if toolbarX > maxX {
                        toolbarX = max(edgePadding, maxX)
                    }
                    
                    withAnimation(.smooth(duration: 0.2)) {
                        self.floatingToolbarOffset = CGPoint(x: toolbarX, y: toolbarY)
                        self.floatingToolbarPlaceAbove = placeAbove
                        self.showFloatingToolbar = true
                    }
                } else {
                    // Hide floating toolbar when no selection
                    withAnimation(.smooth(duration: 0.15)) {
                        self.showFloatingToolbar = false
                    }
                }
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }

    private var available26: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        return false
    }

    // MARK: - Computed Properties

    // Determine if this is a new note based on content
    private var isNewNote: Bool {
        // Consider it a new note if title is empty/untitled and content is minimal
        let hasMinimalTitle =
            editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || editedTitle == "Untitled" || editedTitle == "Note Title"
        let hasMinimalContent = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return hasMinimalTitle && hasMinimalContent
    }

    // MARK: - Header Components


    // Floating back button
    @ViewBuilder
    private var backButton: some View {
        Button(action: {
            HapticManager.shared.navigation()
            closeNote()
        }) {
            Image(systemName: "chevron.left")
                .font(FontManager.heading(size: 16, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .if(available26) { view in
            view.glassEffect(.regular.interactive(true), in: Circle())
                .glassID("back-button", in: glassNamespace)
        }
        .if(!available26) { view in
            view.background(.ultraThinMaterial, in: Circle())
        }
        .background(
            Circle()
                .fill(Color.clear)
                .frame(width: 44, height: 44)
        )
        .contentShape(Circle().size(width: 44, height: 44))
        .scaleEffect(glassElementsVisible ? 1 : 0.9)
        .opacity(glassElementsVisible ? 1 : 0)
    }

    // Progressive blur header with centered title - Apple style
    @ViewBuilder
    private var progressiveBlurHeader: some View {
        ZStack(alignment: .top) {
            // Main blur layer with smooth progressive fade (no banding)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 140)
                .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.2),
                            .init(color: .black.opacity(0.95), location: 0.35),
                            .init(color: .black.opacity(0.85), location: 0.5),
                            .init(color: .black.opacity(0.6), location: 0.65),
                            .init(color: .black.opacity(0.3), location: 0.8),
                            .init(color: .black.opacity(0.1), location: 0.9),
                            .init(color: .clear, location: 1.0),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            HStack {
                Spacer()
                Text(editedTitle.isEmpty ? "Untitled" : editedTitle)
                    .font(FontManager.heading(size: 12, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 80)
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(15)
    }


    // MARK: - Title
    // Using SF Pro Compact for note titles as per design requirements
    private var titleField: some View {
        TextField("Note Title", text: $editedTitle, axis: .vertical)
            .font(FontManager.heading(size: 32, weight: .medium))
            .foregroundColor(Color("PrimaryTextColor"))
            .textFieldStyle(.plain)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Tags
    private var tagsRow: some View {
        HStack(alignment: .top, spacing: 6) {
            // Morphing tag input container
            HStack(spacing: 6) {
                // Plus icon - always visible at leading edge
                Image(systemName: "plus")
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .foregroundColor(
                        isAddingTag ? Color("AccentColor") : Color("TertiaryTextColor"))

                // Text or input field
                if isAddingTag {
                    // Expanded state: show input field
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
                    // Collapsed state for new notes: show "New tag" text
                    Text("New tag")
                        .font(FontManager.heading(size: 12, weight: .semibold))
                        .foregroundColor(Color("TertiaryTextColor"))
                        .transition(.opacity)
                }
                // For existing notes with collapsed state: no text shown, just icon
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: 28)
            .frame(width: isAddingTag ? 128 : (isNewNote ? nil : 28))  // Expand to 128pt when active, adaptive for "New tag", 28pt circle for existing
            .background(
                Capsule()
                    .fill(Color("SurfaceTranslucentColor"))
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

            // Existing tags in separate scrollable container
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
                                withAnimation(.bouncy(duration: 0.3)) {
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

    // MARK: - Bottom Controls
    @ViewBuilder
    private var bottomGlassControls: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Edit toolbar - positioned at bottom-left
            EditToolbar(
                isExpanded: $isEditToolbarExpanded,
                onToolAction: handleEditToolAction,
                onLinkInsert: handleLinkInsert
            )
            .scaleEffect(bottomControlsExpanded ? 1 : 0.7)
            .opacity(bottomControlsExpanded ? 1 : 0)

            Spacer(minLength: 8)

            // Image picker button - positioned before mic button
            ImagePickerControl(
                onImageSelected: { url in
                    handleImageSelection(url)
                }
            )
            .scaleEffect(bottomControlsExpanded ? 1 : 0.7)
            .opacity(bottomControlsExpanded ? 1 : 0)

            // Mic button - positioned at bottom-right
            MicCaptureControl(
                onSend: { result in
                    handleVoiceRecording(result)
                },
                onCancel: {},
                autoStart: false
            )
            .scaleEffect(bottomControlsExpanded ? 1 : 0.7)
            .opacity(bottomControlsExpanded ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: bottomControlsExpanded)
    }


    // MARK: - Helpers
    private func closeNote() {
        // Persist edits safely by creating a new note with updated values
        var updatedNote = note
        updatedNote.title = editedTitle
        updatedNote.content = editedContent
        updatedNote.tags = editedTags
        updatedNote.date = Date()

        // Save the updated note
        onSave(updatedNote)

        // Animate the exit
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            bottomControlsExpanded = false
            glassElementsVisible = false
            isViewMaterialized = false
        }

        // Close the view after animation completes with safety check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Ensure we're still on the main thread and the view is still valid
            guard Thread.isMainThread else { return }
            isPresented = false
        }
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
        // Animate the morph back to button
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isAddingTag = false
        }
        newTagText = ""
        isAddingTagFocused = false
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }


    private func handleEditToolAction(_ tool: EditTool) {
        print("🔧 DEBUG: handleEditToolAction called with tool: \(tool)")
        print("🔧 DEBUG: Tool rawValue: \(tool.rawValue)")
        switch tool {
        case .todo:
            print("🔧 DEBUG: Posting TodoToolbarAction")
            NotificationCenter.default.post(
                name: Notification.Name("TodoToolbarAction"), object: nil)
        default:
            print("🔧 DEBUG: Posting applyEditTool with userInfo: [\"tool\": \"\(tool.rawValue)\"]")
            NotificationCenter.default.post(
                name: Notification.Name("ApplyEditTool"), object: nil, userInfo: ["tool": tool.rawValue])
        }
    }

    private func handleLinkInsert(_ url: String) {
        // Ask the editor to insert a web link at the current cursor location
        NotificationCenter.default.post(name: Notification.Name("InsertWebLink"), object: url)
    }

    private func handleVoiceRecording(_ result: MicCaptureControl.Result) {
        NSLog("🎤 NoteDetailView.handleVoiceRecording: START - audioURL: %@, transcript: %@", result.audioURL.path, result.transcript ?? "nil")

        // Insert transcript at cursor position in the editor
        if let transcript = result.transcript, !transcript.isEmpty {
            NSLog("🎤 NoteDetailView.handleVoiceRecording: Posting notification with transcript: %@", transcript)

            // Ensure we're on main thread and add slight delay to ensure coordinator is ready
            DispatchQueue.main.async {
                NSLog("🎤 NoteDetailView.handleVoiceRecording: About to post notification on main thread")
                NotificationCenter.default.post(
                    name: .insertVoiceTranscriptInEditor, object: transcript)
                NSLog("🎤 NoteDetailView.handleVoiceRecording: Notification posted successfully")
            }
        } else {
            NSLog("🎤 NoteDetailView.handleVoiceRecording: No transcript to insert")
        }

        // TODO: Save audio file if needed
        // The audio file is available at result.audioURL
        NSLog("🎤 NoteDetailView.handleVoiceRecording: END")
    }
    
    private func handleImageSelection(_ imageURL: URL) {
        NSLog("🖼️ NoteDetailView.handleImageSelection: START - imageURL: %@", imageURL.path)
        
        Task {
            // Save the image to the storage directory
            if let filename = await ImageStorageManager.shared.saveImage(from: imageURL) {
                NSLog("🖼️ NoteDetailView.handleImageSelection: Image saved as %@", filename)
                
                // Post notification to insert image in editor
                await MainActor.run {
                    NSLog("🖼️ NoteDetailView.handleImageSelection: Posting notification with filename")
                    NotificationCenter.default.post(
                        name: .insertImageInEditor,
                        object: filename
                    )
                    NSLog("🖼️ NoteDetailView.handleImageSelection: Notification posted successfully")
                }
            } else {
                NSLog("🖼️ NoteDetailView.handleImageSelection: Failed to save image")
            }
        }
        
        NSLog("🖼️ NoteDetailView.handleImageSelection: END")
    }

    // MARK: - Scroll Helpers

    private func headerTopInset(for progress: CGFloat) -> CGFloat {
        max(14, 20 + (1 - progress) * 8)
    }

    private func blurMaterial(for progress: CGFloat) -> Material {
        // Use thicker materials for stronger blur
        switch progress {
        case ..<CGFloat(0.33):
            return .thickMaterial
        case ..<CGFloat(0.66):
            return .ultraThickMaterial
        default:
            return .ultraThickMaterial
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

// MARK: - View Extensions
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Subviews
private struct TagPill: View {
    let text: String
    let isSelected: Bool
    let isHovered: Bool
    let isPressed: Bool
    let visible: Bool
    let onRemove: () -> Void
    let glassNamespace: Namespace.ID

    @ViewBuilder
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(FontManager.heading(size: 10, weight: .regular))
                .foregroundColor(Color("TagTextColor"))
            Text(text)
                .font(FontManager.heading(size: 12, weight: .medium))
                .foregroundColor(Color("TagTextColor"))
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: {
                HapticManager.shared.tagInteraction()
                onRemove()
            }) {
                Image(systemName: "xmark")
                    .font(FontManager.heading(size: 8, weight: .bold))
                    .foregroundColor(Color("TagTextColor"))
                    .opacity(0.7)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .frame(width: 20, height: 20)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .frame(height: 28)
        .background(Color("TagBackgroundColor"), in: Capsule())
        .background(
            Capsule()
                .fill(Color.clear)
                .frame(height: 36)
        )
        .contentShape(Capsule())
        .scaleEffect((visible ? 1 : 0.92) * (isPressed ? 0.96 : 1.0) * (isHovered ? 1.02 : 1.0))
        .opacity(visible ? 1 : 0)
        .animation(.bouncy(duration: 0.3), value: isHovered)
        .animation(.bouncy(duration: 0.2), value: isPressed)
    }

    private var available26: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        return false
    }
}
