//
//  NoteDetailView.swift
//  Noty
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
    @Binding var isPresented: Bool
    var onSave: (Note) -> Void

    // MARK: - Environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Core editing state
    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var editedTags: [String]

    static let imageTagPattern = #"\[\[image\|\|\|([^\]]+)\]\]"#
    static let imageTagRegex = try? NSRegularExpression(pattern: imageTagPattern, options: [])

    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var isAddingTagFocused: Bool

    // MARK: - UI animation state
    @State private var isViewMaterialized = false
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

    // MARK: - Scroll / toolbar state
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

    // MARK: - Init

    init(note: Note, isPresented: Binding<Bool>, onSave: @escaping (Note) -> Void) {
        self.note = note
        self._isPresented = isPresented
        self.onSave = onSave
        self._editedTitle = State(initialValue: note.title)
        self._editedContent = State(initialValue: note.content)
        self._editedTags = State(initialValue: note.tags)
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
                            .foregroundColor(Color.primary.opacity(0.55))
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
                            onToolbarAction: handleEditToolAction,
                            onCommandMenuSelection: handleCommandMenuSelection
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

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

            backButton
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .zIndex(20)
        }
        .overlay(alignment: .bottomLeading) {
            if let previewImage = galleryPreviewImage {
                GalleryPreviewOverlay(image: previewImage, onTap: {
                    guard !galleryItems.isEmpty else { return }
                    withAnimation(.notySpring) {
                        showGalleryGrid = true
                    }
                })
                    .padding(.leading, 22)
                    .padding(.bottom, 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(40)
            }
        }
        .overlay(alignment: .bottom) {
            bottomOverlay
                .opacity(showFloatingToolbar ? 0.5 : 1.0)
                .animation(.notySmoothFast, value: showFloatingToolbar)
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
        .opacity(isViewMaterialized ? 1 : 0)
        .offset(x: isViewMaterialized ? 0 : 40)
        .animation(.notySpring, value: isViewMaterialized)
        .onAppear {
            updateGalleryPreview(for: editedContent)
            DispatchQueue.main.async {
                withAnimation(.notySpring) {
                    self.isViewMaterialized = true
                }
                withAnimation(.notySpring.delay(0.1)) {
                    self.glassElementsVisible = true
                }
            }
        }
        .onDisappear {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    self.isViewMaterialized = false
                    self.glassElementsVisible = false
                }
            }
        }
        .onChange(of: editedContent) { newValue in
            updateGalleryPreview(for: newValue)
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

                    withAnimation(.notySmoothFast) {
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
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }

    // MARK: - Computed Properties

    private var available26: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        return false
    }

    private var noteDateString: String {
        Self.dateFormatter.string(from: note.date)
    }

    private var isNewNote: Bool {
        let hasMinimalTitle =
            editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || editedTitle == "Untitled" || editedTitle == "Note Title"
        let hasMinimalContent = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return hasMinimalTitle && hasMinimalContent
    }

    // MARK: - Header Components

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
        .macPointingHandCursor()
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

    // MARK: - Title

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
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .foregroundColor(
                        isAddingTag ? Color("AccentColor") : Color("TertiaryTextColor"))

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
                        .foregroundColor(Color("TertiaryTextColor"))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: 28)
            .frame(width: isAddingTag ? 128 : (isNewNote ? nil : 28))
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
                                withAnimation(.notyBounce) {
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
        if reduceTransparency {
            Rectangle().fill(headerTintColor)
        } else {
            Rectangle()
                .fill(.ultraThickMaterial)
                .overlay(Rectangle().fill(headerTintColor))
        }
    }

    private var headerTintColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.96)
        } else {
            return Color(red: 0.97, green: 0.97, blue: 0.99).opacity(0.94)
        }
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

    // MARK: - Bottom Overlay

    @ViewBuilder
    private var bottomOverlay: some View {
        if showVoiceRecorderOverlay || showLinkInputOverlay {
            VStack(spacing: 12) {
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
            .animation(.notySpring, value: showVoiceRecorderOverlay)
            .animation(.notySpring, value: showLinkInputOverlay)
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
            Image(systemName: "link")
                .font(FontManager.heading(size: 12, weight: .regular))
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
                    .font(FontManager.heading(size: 16, weight: .regular))
                    .foregroundColor(
                        linkInputText.isEmpty ? Color("TertiaryTextColor") : Color("AccentColor"))
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

    // MARK: - Helpers

    private func closeNote() {
        var updatedNote = note
        updatedNote.title = editedTitle
        updatedNote.content = editedContent
        updatedNote.tags = editedTags
        updatedNote.date = Date()

        onSave(updatedNote)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            glassElementsVisible = false
            isViewMaterialized = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
