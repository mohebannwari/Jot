//
//  NoteDetailView.swift
//  Noty
//
//  Created by AI on 15.08.25.
//
//  Simpler, Figma-aligned note detail view

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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var editedTags: [String]

    private static let imageTagPattern = #"\[\[image\|\|\|([^\]]+)\]\]"#
    private static let imageTagRegex = try? NSRegularExpression(pattern: imageTagPattern, options: [])

    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var isAddingTagFocused: Bool

    // Liquid glass animation states
    @State private var isViewMaterialized = false
    @State private var glassElementsVisible = false
    @State private var hoveredTag: String?
    @State private var pressedTag: String?
    @State private var selectedTags: Set<String> = []
    @Namespace private var glassNamespace
    @State private var galleryPreviewImage: PlatformImage?
    @State private var lastGalleryFilename: String?
    @State private var galleryItems: [GalleryGridOverlay.Item] = []
    @State private var showGalleryGrid = false
    
    // Auxiliary overlays
    @State private var showVoiceRecorderOverlay = false
    // @State private var micSessionID = UUID()  // Removed to prevent view recreation crashes
    @State private var showImagePicker = false
    @State private var showLinkInputOverlay = false
    @State private var linkInputText = ""
    @FocusState private var isLinkInputFocused: Bool

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

        debugLog("DEBUG: NoteDetailView init - note.content: '\(note.content.prefix(100))...'")
        debugLog(
            "DEBUG: NoteDetailView init - editedContent will be initialized with: '\(note.content.prefix(100))...'"
        )
    }

    private var noteContent: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        titleField
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .named("scroll")).minY) {
                                            oldValue, newValue in
                                            titleOffset = newValue
                                            let shouldShow = newValue < 0

                                            debugLog(
                                                "🔵 SCROLL: titleOffset=\(newValue), shouldShow=\(shouldShow)"
                                            )

                                            if shouldShow != showStickyHeader {
                                                debugLog("🟢 TOGGLING HEADER TO: \(shouldShow)")
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
                        // Body text editor - unified with header, flows naturally
                        TodoRichTextEditor(
                            text: $editedContent,
                            onToolbarAction: handleEditToolAction,
                            onCommandMenuSelection: handleCommandMenuSelection
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
                        .background(
                            headerMaterialBase
                                .mask(headerMaskGradient)
                                .ignoresSafeArea(edges: .top)
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
        .overlay(alignment: .bottomLeading) {
            if let previewImage = galleryPreviewImage {
                GalleryPreviewOverlay(image: previewImage, onTap: {
                    guard !galleryItems.isEmpty else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
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
                .animation(.smooth(duration: 0.2), value: showFloatingToolbar)
        }
        .overlay {
            // Floating toolbar overlay - appears near selected text (like CommandMenu)
            GeometryReader { geometry in
                if showFloatingToolbar {
                    let parentFrame = geometry.frame(in: .global)

                    // Convert window coordinates to parent view coordinates
                    let localX = floatingToolbarOffset.x - parentFrame.minX
                    let localY = floatingToolbarOffset.y - parentFrame.minY

                    // Calculate center position for .position() modifier
                    // Toolbar dimensions: 250x36
                    let toolbarWidth: CGFloat = 250
                    let toolbarHeight: CGFloat = 36
                    let centerX = localX + toolbarWidth / 2
                    let centerY = localY + toolbarHeight / 2

                    let _ = debugLog("📍 [Overlay] Position calculation:")
                    let _ = debugLog("  - parentFrame: \(parentFrame)")
                    let _ = debugLog("  - Window toolbar origin: (\(floatingToolbarOffset.x), \(floatingToolbarOffset.y))")
                    let _ = debugLog("  - Local toolbar origin: (\(localX), \(localY))")
                    let _ = debugLog("  - Toolbar center position: (\(centerX), \(centerY))")

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
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isViewMaterialized)
        .onAppear {
            updateGalleryPreview(for: editedContent)
            // Safety check to prevent crashes on appear
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    self.isViewMaterialized = true
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82).delay(0.1)) {
                    self.glassElementsVisible = true
                }
            }
        }
        .onDisappear {
            // Safety check to prevent crashes on disappear
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
                   let selectionX = userInfo["selectionX"] as? CGFloat,
                   let selectionY = userInfo["selectionY"] as? CGFloat,
                   let selectionWidth = userInfo["selectionWidth"] as? CGFloat,
                   let selectionHeight = userInfo["selectionHeight"] as? CGFloat,
                   let selectionWindowY = userInfo["selectionWindowY"] as? CGFloat,
                   let selectionWindowX = userInfo["selectionWindowX"] as? CGFloat,
                   let visibleWidth = userInfo["visibleWidth"] as? CGFloat,
                   let visibleHeight = userInfo["visibleHeight"] as? CGFloat {

                    let _ = debugLog("📍 [NoteDetailView] Received coordinates:")
                    let _ = debugLog("  - selectionX: \(selectionX), selectionY: \(selectionY)")
                    let _ = debugLog("  - selectionWindowX: \(selectionWindowX), selectionWindowY: \(selectionWindowY)")
                    let _ = debugLog("  - selectionWidth: \(selectionWidth), selectionHeight: \(selectionHeight)")
                    let _ = debugLog("  - titleOffset: \(titleOffset)")

                    // Calculate toolbar positioning with 4px gap
                    let toolbarHeight: CGFloat = 36
                    let gap: CGFloat = 2

                    let windowReference = NSApp.keyWindow ?? NSApp.mainWindow
                    let windowHeight = windowReference?.contentView?.bounds.height
                        ?? windowReference?.frame.height
                        ?? visibleHeight
                    let windowWidth = windowReference?.contentView?.bounds.width
                        ?? windowReference?.frame.width
                        ?? visibleWidth

                    // Convert AppKit window coordinates (origin bottom-left) into SwiftUI's top-left space
                    let selectionTopFromTop = max(
                        0,
                        windowHeight - (selectionWindowY + selectionHeight)
                    )
                    let selectionBottomFromTop = min(windowHeight, selectionTopFromTop + selectionHeight)

                    let availableAbove = selectionTopFromTop
                    let availableBelow = max(0, windowHeight - selectionBottomFromTop)

                    let fitsAbove = availableAbove >= (toolbarHeight + gap)
                    let fitsBelow = availableBelow >= (toolbarHeight + gap)

                    let minTop = gap
                    let maxTop = max(gap, windowHeight - toolbarHeight - gap)

                    let targetAboveTop = selectionTopFromTop - gap - toolbarHeight
                    let clampedAboveTop = min(max(targetAboveTop, minTop), maxTop)
                    let aboveMaintainsGap = (clampedAboveTop + toolbarHeight)
                        <= (selectionTopFromTop - gap + 0.5)

                    let targetBelowTop = selectionBottomFromTop + gap
                    let clampedBelowTop = min(max(targetBelowTop, minTop), maxTop)
                    let belowMaintainsGap = clampedBelowTop
                        >= (selectionBottomFromTop + gap - 0.5)

                    var placeAbove = false
                    var chosenToolbarTop: CGFloat

                    if aboveMaintainsGap {
                        placeAbove = true
                        chosenToolbarTop = clampedAboveTop
                    } else if belowMaintainsGap {
                        placeAbove = false
                        chosenToolbarTop = clampedBelowTop
                    } else if fitsAbove && !fitsBelow {
                        placeAbove = true
                        chosenToolbarTop = clampedAboveTop
                    } else if fitsBelow && !fitsAbove {
                        placeAbove = false
                        chosenToolbarTop = clampedBelowTop
                    } else if availableAbove >= availableBelow {
                        placeAbove = true
                        chosenToolbarTop = clampedAboveTop
                    } else {
                        placeAbove = false
                        chosenToolbarTop = clampedBelowTop
                    }

                    let estimatedToolbarWidth: CGFloat = 250  // Fixed toolbar width
                    let edgePadding: CGFloat = 20  // Minimum distance from edges
                    let halfToolbarWidth = estimatedToolbarWidth / 2

                    // Center on selection using window coordinates
                    var toolbarX = selectionWindowX + (selectionWidth / 2) - halfToolbarWidth

                    // Ensure toolbar doesn't go off the left edge
                    if toolbarX < edgePadding {
                        toolbarX = edgePadding
                    }

                    // Clamp within window bounds when available
                    let maxX = windowWidth - estimatedToolbarWidth - edgePadding
                    if maxX > edgePadding {
                        toolbarX = min(max(toolbarX, edgePadding), maxX)
                    } else {
                        // Fallback when the window is narrower than our ideal padding allows.
                        let fallbackMax = max(0, windowWidth - estimatedToolbarWidth)
                        toolbarX = min(max(toolbarX, 0), fallbackMax)
                    }

                    let _ = debugLog("  - availableAbove: \(availableAbove), availableBelow: \(availableBelow)")
                    let _ = debugLog("  - fitsAbove: \(fitsAbove), fitsBelow: \(fitsBelow)")
                    let _ = debugLog("  - aboveMaintainsGap: \(aboveMaintainsGap), belowMaintainsGap: \(belowMaintainsGap)")
                    let _ = debugLog("  - Final toolbar position (top): (\(toolbarX), \(chosenToolbarTop)), placeAbove: \(placeAbove)")
                    
                    withAnimation(.smooth(duration: 0.2)) {
                        self.floatingToolbarOffset = CGPoint(x: toolbarX, y: chosenToolbarTop)
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
            .macPointingHandCursor()

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
            .animation(
                .spring(response: 0.35, dampingFraction: 0.82),
                value: showVoiceRecorderOverlay
            )
            .animation(
                .spring(response: 0.35, dampingFraction: 0.82),
                value: showLinkInputOverlay
            )
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
        // .id(micSessionID)  // Removed to prevent view recreation during async operations
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
        .onExitCommand {
            hideLinkInputOverlay()
        }
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
        debugLog("🔧 DEBUG: handleEditToolAction called with tool: \(tool)")
        debugLog("🔧 DEBUG: Tool rawValue: \(tool.rawValue)")
        if performAuxiliaryToolAction(tool) {
            return
        }
        switch tool {
        case .todo:
            debugLog("🔧 DEBUG: Posting TodoToolbarAction")
            NotificationCenter.default.post(
                name: Notification.Name("TodoToolbarAction"), object: nil)
        default:
            debugLog("🔧 DEBUG: Posting applyEditTool with userInfo: [\"tool\": \"\(tool.rawValue)\"]")
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
            // micSessionID = UUID()  // Removed to prevent view recreation
            showVoiceRecorderOverlay = true
            return true
        case .link:
            presentLinkInputOverlay()
            return true
        default:
            return false
        }
    }

    private func processVoiceRecorderResult(_ result: MicCaptureControl.Result) {
        handleVoiceRecording(result)

        // Give more time for text insertion to complete
        // This ensures the transcription is fully inserted before dismissing the overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.dismissVoiceRecorderOverlay()
        }
    }

    private func dismissVoiceRecorderOverlay() {
        guard showVoiceRecorderOverlay else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showVoiceRecorderOverlay = false
        }
        // micSessionID = UUID()  // Removed to prevent view recreation crashes
    }

    private func presentLinkInputOverlay() {
        linkInputText = ""
        showLinkInputOverlay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isLinkInputFocused = true
        }
    }

    private func hideLinkInputOverlay() {
        showLinkInputOverlay = false
        linkInputText = ""
        isLinkInputFocused = false
    }

    private func submitLink() {
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

    private func handleLinkInsert(_ url: String) {
        // Ask the editor to insert a web link at the current cursor location
        NotificationCenter.default.post(name: Notification.Name("InsertWebLink"), object: url)
    }

    // MARK: - Gallery Preview

    private func updateGalleryPreview(for text: String) {
        let filenames = extractGalleryFilenames(from: text)
        let currentIDs = galleryItems.map(\.id)
        let needsReload = filenames != currentIDs

        let items: [GalleryGridOverlay.Item]
        if needsReload {
            items = filenames.compactMap { filename -> GalleryGridOverlay.Item? in
                guard let loadedImage = loadGalleryImage(named: filename) else { return nil }
                return GalleryGridOverlay.Item(id: filename, image: loadedImage)
            }
            galleryItems = items
        } else {
            items = galleryItems
        }

        guard let latestItem = items.last else {
            lastGalleryFilename = nil
            if galleryPreviewImage != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    galleryPreviewImage = nil
                }
            }
            if showGalleryGrid {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showGalleryGrid = false
                }
            }
            return
        }

        let shouldUpdatePreview = latestItem.id != lastGalleryFilename || galleryPreviewImage == nil
        lastGalleryFilename = latestItem.id

        guard shouldUpdatePreview else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            galleryPreviewImage = latestItem.image
        }
    }

    private func extractGalleryFilenames(from text: String) -> [String] {
        guard let regex = Self.imageTagRegex else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[range])
        }
    }

    private func loadGalleryImage(named filename: String) -> PlatformImage? {
        guard let imageURL = ImageStorageManager.shared.getImageURL(for: filename) else {
            return nil
        }

        #if os(macOS)
        return NSImage(contentsOf: imageURL)
        #else
        return UIImage(contentsOfFile: imageURL.path)
        #endif
    }

    private func handleVoiceRecording(_ result: MicCaptureControl.Result) {
        NSLog("🎤 NoteDetailView.handleVoiceRecording: START - audioURL: %@, transcript: %@", result.audioURL.path, result.transcript ?? "nil")

        // Insert transcript at cursor position in the editor
        if let transcript = result.transcript, !transcript.isEmpty {
            NSLog("🎤 NoteDetailView.handleVoiceRecording: Posting notification with transcript: %@", transcript)

            // Already on @MainActor, post directly without redundant dispatch
            NotificationCenter.default.post(
                name: .insertVoiceTranscriptInEditor,
                object: transcript
            )
            NSLog("🎤 NoteDetailView.handleVoiceRecording: Notification posted successfully")
        } else {
            NSLog("🎤 NoteDetailView.handleVoiceRecording: No transcript to insert")
        }

        // Clean up temporary audio file (transcript already extracted, audio not stored)
        do {
            try FileManager.default.removeItem(at: result.audioURL)
            NSLog("🎤 NoteDetailView.handleVoiceRecording: Cleaned up temp audio file at %@", result.audioURL.path)
        } catch {
            NSLog("🎤 NoteDetailView.handleVoiceRecording: Failed to cleanup temp audio: %@", error.localizedDescription)
        }

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

            // Clean up temporary image file (already saved/processed to permanent storage)
            do {
                try FileManager.default.removeItem(at: imageURL)
                NSLog("🖼️ NoteDetailView.handleImageSelection: Cleaned up temp image at %@", imageURL.path)
            } catch {
                NSLog("🖼️ NoteDetailView.handleImageSelection: Failed to cleanup temp image: %@", error.localizedDescription)
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
        .macPointingHandCursor()
    }

    private var available26: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        return false
    }
}

#if DEBUG
private func debugLog(_ message: @autoclosure () -> String) {
    print(message())
}
#else
private func debugLog(_ message: @autoclosure () -> String) {}
#endif
