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
                        headerMeta
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
                        .frame(height: 150)
                        .background(.ultraThickMaterial, ignoresSafeAreaEdges: .top)
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black.opacity(0.9), location: 0.25),
                                    .init(color: .black.opacity(0.85), location: 0.35),
                                    .init(color: .black.opacity(0.7), location: 0.5),
                                    .init(color: .black.opacity(0.5), location: 0.65),
                                    .init(color: .black.opacity(0.2), location: 0.8),
                                    .init(color: .black.opacity(0.03), location: 0.9),
                                    .init(color: .clear, location: 1.0),
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blur(radius: 0.01)

                    // Title text on top
                    HStack {
                        Spacer()
                        Text(editedTitle.isEmpty ? "Untitled" : editedTitle)
                            .font(.system(size: 12, weight: .medium))
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
        }
        .opacity(isViewMaterialized ? 1 : 0)
        .scaleEffect(isViewMaterialized ? 1 : 0.98)
        .animation(.bouncy(duration: 0.6), value: isViewMaterialized)
        .onAppear {
            withAnimation(.bouncy(duration: 0.6).delay(0.05)) { isViewMaterialized = true }
            withAnimation(.bouncy(duration: 0.6).delay(0.2)) { glassElementsVisible = true }
            withAnimation(.bouncy(duration: 0.6).delay(0.35)) { bottomControlsExpanded = true }
        }
        .onDisappear {
            withAnimation(.bouncy(duration: 0.4)) {
                isViewMaterialized = false
                glassElementsVisible = false
                bottomControlsExpanded = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowCommandMenu")))
        { notification in
            if let info = notification.object as? [String: Any],
                let needsSpace = info["needsSpace"] as? Bool
            {
                withAnimation(.easeOut(duration: 0.2)) {
                    commandMenuNeedsSpace = needsSpace
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HideCommandMenu")))
        { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                commandMenuNeedsSpace = false
            }
        }
        .transition(.opacity)
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerMeta
            titleField
        }
    }

    // Floating back button
    @ViewBuilder
    private var backButton: some View {
        Button(action: closeNote) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .if(available26) { view in
            view.glassEffect(.regular.interactive(true), in: Circle())
                .glassID("back-button", in: glassNamespace)
        }
        .if(!available26) { view in
            view.liquidGlass(in: Circle())
        }
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
                    .font(.system(size: 12, weight: .medium))
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

    // MARK: - Meta (Date + Last Edited)
    private var headerMeta: some View {
        HStack(spacing: 4) {
            Text(dateFormatter.string(from: note.date))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color("TertiaryTextColor"))

            Text("·")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color("TertiaryTextColor"))

            Text(editedDisplayString)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color("TertiaryTextColor"))

            Spacer()
        }
    }

    // MARK: - Title
    private var titleField: some View {
        TextField("Note Title", text: $editedTitle, axis: .vertical)
            .font(.system(size: 32, weight: .medium))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(
                        isAddingTag ? Color("AccentColor") : Color("TertiaryTextColor"))

                // Text or input field
                if isAddingTag {
                    // Expanded state: show input field
                    TextField("New tag", text: $newTagText)
                        .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 12, weight: .semibold))
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
            .contentShape(Capsule())
            .onTapGesture {
                if !isAddingTag {
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
        if #available(iOS 26.0, macOS 26.0, *) {
            HStack(alignment: .bottom, spacing: 8) {
                // Edit toolbar - positioned at bottom-left
                LiquidGlassContainer(spacing: 12) {
                    EditToolbar(
                        isExpanded: $isEditToolbarExpanded,
                        onToolAction: handleEditToolAction,
                        onLinkInsert: handleLinkInsert
                    )
                    .glassID("edit-toolbar", in: glassNamespace)
                    .scaleEffect(bottomControlsExpanded ? 1 : 0.7)
                    .opacity(bottomControlsExpanded ? 1 : 0)
                }

                Spacer(minLength: 8)

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
            .animation(.bouncy(duration: 0.6), value: bottomControlsExpanded)
        } else {
            // Fallback for older OS versions
            legacyBottomControls
        }
    }

    private var legacyBottomControls: some View {
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
        .animation(.bouncy(duration: 0.6), value: bottomControlsExpanded)
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
        withAnimation(.bouncy(duration: 0.4)) { bottomControlsExpanded = false }
        withAnimation(.bouncy(duration: 0.4).delay(0.05)) { glassElementsVisible = false }
        withAnimation(.bouncy(duration: 0.5).delay(0.1)) { isViewMaterialized = false }

        // Close the view after animation completes with safety check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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

    private var editedDisplayString: String {
        let cal = Calendar.current
        let time = timeFormatter.string(from: note.date)
        if cal.isDateInToday(note.date) {
            return "Edited Today at \(time)"
        } else if cal.isDateInYesterday(note.date) {
            return "Edited Yesterday at \(time)"
        } else {
            let date = dateFormatter.string(from: note.date)
            return "Edited \(date) at \(time)"
        }
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
                name: .applyEditTool, object: nil, userInfo: ["tool": tool.rawValue])
        }
    }

    private func handleLinkInsert(_ url: String) {
        // Ask the editor to insert a web link at the current cursor location
        NotificationCenter.default.post(name: Notification.Name("InsertWebLink"), object: url)
    }

    private func handleVoiceRecording(_ result: MicCaptureControl.Result) {
        // Insert transcript at cursor position in the editor
        if let transcript = result.transcript, !transcript.isEmpty {
            // Send to editor to insert at cursor position
            NotificationCenter.default.post(
                name: Notification.Name("InsertVoiceTranscript"), object: transcript)
        }

        // TODO: Save audio file if needed
        // The audio file is available at result.audioURL
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
        HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .font(.system(size: 10))
                .foregroundColor(Color("TagTextColor"))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color("TagTextColor"))
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color("TagTextColor"))
                    .opacity(0.7)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color("TagBackgroundColor"), in: Capsule())
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
