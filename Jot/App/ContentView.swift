//
//  ContentView.swift
//  Jot
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI
import AppKit

/// Makes the hosting NSWindow transparent so liquid glass is the sole background layer.
struct WindowTransparencyView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum SidebarSectionFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case today
    case thisMonth
    case thisYear
    case older
    case folders

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .pinned: return "Pinned"
        case .today: return "Today"
        case .thisMonth: return "This Month"
        case .thisYear: return "This Year"
        case .older: return "Older"
        case .folders: return "Notebooks"
        }
    }
}

func sidebarSectionFilterAllows(_ active: SidebarSectionFilter, section: SidebarSectionFilter) -> Bool {
    active == .all || active == section
}

struct ContentView: View {
    // Search is powered by SearchEngine
    @StateObject private var searchEngine = SearchEngine()
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    @State private var selectedNote: Note?
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?
    @State private var isSidebarVisible = true
    @State private var isSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var isPinnedSectionExpanded: Bool = true
    @State private var showAllNotesFolderIDs: Set<UUID> = []
    @State private var sidebarSectionFilter: SidebarSectionFilter = .all
    @State private var sidebarWidth: CGFloat = 276
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var detailFocusRequestID = UUID()
    @State private var hasAppliedInitialLaunchSelection = false
    @State private var isAutoCreatingStarterNote = false
    @State private var aiToolsState: AIToolsState = .collapsed

    @State private var isCreateFolderAlertPresented = false
    @State private var pendingFolderCreationIntent: FolderCreationIntent = .standalone
    @State private var pendingFolderToEdit: Folder?
    @State private var createFolderButtonFrame: CGRect = .zero

    @State private var isBatchDeleteConfirmationPresented = false
    @State private var pendingDeleteNoteIDs: Set<UUID> = []
    @State private var isBatchMoveAlertPresented = false
    @State private var pendingMoveNoteIDs: Set<UUID> = []
    @State private var batchMoveFolderName = ""
    @State private var isBatchExportSheetPresented = false
    @State private var notesPendingExport: [Note] = []
    @State private var isShowingArchive = false
    @State private var hoveredSidebarMenuLabel: String?
    @State private var trafficLightMetrics = TrafficLightMetrics.fallback
    @State private var isFloatingSidebarVisible = false
    @State private var floatingSidebarDismissWorkItem: DispatchWorkItem?


    @Environment(\.colorScheme) private var colorScheme

    // Window corner radius from JotApp containerShape
    private let windowCornerRadius: CGFloat = 16
    private let windowContentPadding: CGFloat = 8
    private let sidebarDesignColumnWidth: CGFloat = 276
    private let sidebarMenuTop: CGFloat = 30
    private let sidebarNotesTop: CGFloat = 146
    private let sidebarSectionSpacing: CGFloat = 16
    private let sidebarChromeSpacing: CGFloat = 12
    private let sidebarMinWidth: CGFloat = 276
    private let sidebarMaxWidth: CGFloat = 560
    private let minimumDetailWidth: CGFloat = 520
    private let sidebarResizeHandleWidth: CGFloat = 24
    private let sidebarVisibilityAnimation = Animation.interactiveSpring(
        response: 0.28,
        dampingFraction: 0.86,
        blendDuration: 0.15
    )
    private let detailToggleToContentExtraSpacingWhenSidebarHidden: CGFloat = 16
    private let sidebarIconSize: CGFloat = 20
    private let sidebarTopIconSpacingCollapsed: CGFloat = 8
    private let sidebarTopBarButtonSize: CGFloat = 20
    private let sidebarTopBarTrafficLightGap: CGFloat = 12
    private let sidebarRowHoverInset: CGFloat = 0
    private let floatingSidebarWidth: CGFloat = 276
    private let floatingSidebarCornerRadius: CGFloat = 16
    private let floatingSidebarEdgeInset: CGFloat = 8
    private let floatingSidebarHoverTriggerWidth: CGFloat = 20
    private let floatingSidebarDismissDelay: TimeInterval = 0.3
    private let sidebarItemLeadingPadding: CGFloat = 8
    private let sidebarItemTrailingPadding: CGFloat = 8
    private let sidebarItemVPadding: CGFloat = 8
    private let sidebarMenuItemHeight: CGFloat = 32
    /// Gap between menu container bottom and "Notes" header text (Figma Notes Header py-top).
    private var sidebarMenuToNotesGap: CGFloat {
        sidebarNotesTop - sidebarMenuTop - (sidebarMenuItemHeight * 3)
    }
    private var sidebarSettingsBottomPadding: CGFloat {
        max(0, 12 - windowContentPadding)
    }
    private var sidebarResizeHandleTopInset: CGFloat {
        sidebarNotesTop + 16
    }
    /// Icon leading derived from the actual traffic light zoom button position.
    private var iconLeading: CGFloat { trafficLightMetrics.iconLeading }
    /// Icon top derived from the actual traffic light zoom button position.
    private var iconTop: CGFloat { trafficLightMetrics.iconTop }

    private enum FolderCreationIntent {
        case standalone
        case withNotes(Set<UUID>)
    }

    var body: some View {
        GeometryReader { geometry in
            let effectivePadding: CGFloat = isSidebarVisible ? windowContentPadding : 0
            let availableWidth = geometry.size.width - (effectivePadding * 2)
            let sidebarDetailGap: CGFloat = isSidebarVisible ? windowContentPadding : 0
            let resolvedSidebarWidth = clampedSidebarWidth(sidebarWidth, totalWidth: availableWidth)
            let expandedSidebarWidth = selectedNote == nil ? availableWidth : resolvedSidebarWidth
            let visibleSidebarWidth = isSidebarVisible ? expandedSidebarWidth : 0
            ZStack {
                ZStack {
                    HStack(spacing: 0) {
                        sidebarContent()
                            .frame(width: visibleSidebarWidth)
                            .opacity(isSidebarVisible ? 1 : 0)
                            .allowsHitTesting(isSidebarVisible)
                            .clipped()
                            .overlay(alignment: .trailing) {
                                if selectedNote != nil && isSidebarVisible {
                                    sidebarResizeHandle(totalWidth: availableWidth)
                                        .padding(.top, sidebarResizeHandleTopInset)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                        .offset(x: sidebarResizeHandleWidth / 2)
                                        .zIndex(1)
                                }
                            }

                        if let note = selectedNote {
                            let detailWidth: CGFloat = isSidebarVisible
                                ? max(0, availableWidth - visibleSidebarWidth - sidebarDetailGap)
                                : availableWidth
                            let detailCornerRadius: CGFloat = isSidebarVisible ? windowCornerRadius - windowContentPadding : 0

                            detailPane(note: note)
                                .frame(width: detailWidth)
                                .frame(maxHeight: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: detailCornerRadius, style: .continuous)
                                        .fill(colorScheme == .dark ? Color(red: 0.047, green: 0.039, blue: 0.035) : Color(red: 0.906, green: 0.898, blue: 0.894))
                                )
                                .clipShape(RoundedRectangle(cornerRadius: detailCornerRadius, style: .continuous))
                                .overlay(alignment: .bottomTrailing) {
                                    AIToolsOverlay(state: $aiToolsState)
                                        .padding(.trailing, 18)
                                        .padding(.bottom, 18)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    NoteToolsBar(note: note)
                                        .padding(.leading, 18)
                                        .padding(.bottom, 18)
                                }
                                .padding(.leading, sidebarDetailGap)
                                .disabled(isCreateFolderAlertPresented || pendingFolderToEdit != nil)
                        }
                    }
                }
                .padding(effectivePadding)
                .animation(sidebarVisibilityAnimation, value: isSidebarVisible)
                .overlay(alignment: .topLeading) {
                    if !isSidebarVisible {
                        floatingSidebarOverlay
                    }
                }
                .overlay(alignment: .topLeading) {
                    if !isSidebarVisible {
                        collapsedTopBarRow
                    }
                }
                .overlay(alignment: .topLeading) {
                    globalSearchShortcutActivator
                }

                appCenteredSearchOverlay()
                    .zIndex(3)

                appWindowSettingsOverlay()
                    .zIndex(4)
            }
            .coordinateSpace(name: "contentArea")
        }
        .background {
            Color.clear
                .ignoresSafeArea()
                .liquidGlass(in: Rectangle())
        }
        .background(WindowTransparencyView())
        .background(
            TrafficLightAligner(
                metrics: $trafficLightMetrics,
                gap: sidebarTopBarTrafficLightGap,
                iconHeight: sidebarTopBarButtonSize
            )
        )
        .onAppear {
            searchEngine.setNotes(notesManager.notes)
            searchEngine.setFolders(notesManager.folders)
            reconcileSelectionWithCurrentNotes()
        }
        .onChange(of: notesManager.notes) { notes in
            searchEngine.setNotes(notes)
            reconcileSelectionWithCurrentNotes(notes)
        }
        .onChange(of: notesManager.folders) { folders in
            searchEngine.setFolders(folders)
        }
        .onChange(of: notesManager.hasLoadedInitialNotes) { _, _ in
            reconcileSelectionWithCurrentNotes()
        }
        .onChange(of: notesManager.hasCompletedMigrationCheck) { _, _ in
            reconcileSelectionWithCurrentNotes()
        }
        .onChange(of: isShowingArchive) { _, showing in
            if showing {
                notesManager.loadArchivedNotes()
                notesManager.loadArchivedFolders()
            }
        }
        .onChange(of: isSidebarVisible) { _, newValue in
            if newValue {
                floatingSidebarDismissWorkItem?.cancel()
                floatingSidebarDismissWorkItem = nil
                isFloatingSidebarVisible = false
            }
        }
        .onChange(of: isSearchPresented) { _, newValue in
            if newValue && isFloatingSidebarVisible {
                floatingSidebarDismissWorkItem?.cancel()
                floatingSidebarDismissWorkItem = nil
                withAnimation(.jotSpring) {
                    isFloatingSidebarVisible = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteSelectionCommandTriggered)) { notification in
            guard
                let rawAction = notification.userInfo?["action"] as? String,
                let action = NoteSelectionCommandAction(rawValue: rawAction)
            else {
                return
            }
            handleSelectionCommand(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            presentSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSingleNote)) { notification in
            guard let noteID = notification.userInfo?["noteID"] as? UUID,
                  let note = notesManager.notes.first(where: { $0.id == noteID }) else { return }
            notesPendingExport = [note]
            withAnimation(.jotSpring) { isBatchExportSheetPresented = true }
        }
        .overlay {
            if isBatchExportSheetPresented {
                ZStack {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.jotSpring) { isBatchExportSheetPresented = false }
                        }
                    ExportFormatSheet(isPresented: $isBatchExportSheetPresented, notes: notesPendingExport) {
                        exportNotes, format in
                        Task { @MainActor in
                            // Delay to allow the sheet to dismiss before presenting the save panel
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            
                            let success: Bool
                            if exportNotes.count == 1, let singleNote = exportNotes.first {
                                success = await NoteExportService.shared.exportNote(singleNote, format: format)
                            } else {
                                let filename = "Jot Export \(Date().formatted(date: .numeric, time: .omitted))"
                                success = await NoteExportService.shared.exportNotes(
                                    exportNotes,
                                    format: format,
                                    filename: filename
                                )
                            }
                            if success {
                                HapticManager.shared.strong()
                            } else {
                                HapticManager.shared.medium()
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            if isCreateFolderAlertPresented {
                folderSheetOverlay {
                    CreateFolderSheet(
                        onCreate: { name, colorHex in
                            confirmCreateFolder(name: name, colorHex: colorHex)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                isCreateFolderAlertPresented = false
                            }
                        },
                        onCancel: {
                            resetPendingFolderCreation()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                isCreateFolderAlertPresented = false
                            }
                        }
                    )
                } onDismiss: {
                    resetPendingFolderCreation()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isCreateFolderAlertPresented = false
                    }
                }
                .transition(.opacity)
            }
            if let folder = pendingFolderToEdit {
                folderSheetOverlay {
                    CreateFolderSheet(
                        onCreate: { name, colorHex in
                            confirmEditFolder(name: name, colorHex: colorHex)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                pendingFolderToEdit = nil
                            }
                        },
                        onCancel: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                pendingFolderToEdit = nil
                            }
                        },
                        editingFolder: folder
                    )
                } onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        pendingFolderToEdit = nil
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.jotSpring, value: isBatchExportSheetPresented)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isCreateFolderAlertPresented)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: pendingFolderToEdit != nil)
        .alert("Delete Selected Notes?", isPresented: $isBatchDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {
                pendingDeleteNoteIDs.removeAll()
            }
            Button("Delete", role: .destructive) {
                deleteNotesNow(pendingDeleteNoteIDs)
                pendingDeleteNoteIDs.removeAll()
            }
        } message: {
            Text("This will permanently delete \(pendingDeleteNoteIDs.count) notes.")
        }
        .alert("Move Selected Notes", isPresented: $isBatchMoveAlertPresented) {
            TextField("Notebook name", text: $batchMoveFolderName)
            Button("Cancel", role: .cancel) {
                resetPendingMoveSelection()
            }
            Button("Move") {
                confirmMoveSelectedNotesByName()
            }
        } message: {
            Text("Enter a notebook name. If it does not exist, it will be created.")
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private func sidebarResizeHandle(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: sidebarResizeHandleWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .macResizeLeftRightCursor()
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if sidebarDragStartWidth == nil {
                            sidebarDragStartWidth = sidebarWidth
                        }
                        guard let startWidth = sidebarDragStartWidth else { return }
                        let proposedWidth = startWidth + value.translation.width
                        sidebarWidth = clampedSidebarWidth(proposedWidth, totalWidth: totalWidth)
                    }
                    .onEnded { _ in
                        sidebarDragStartWidth = nil
                        sidebarWidth = clampedSidebarWidth(sidebarWidth, totalWidth: totalWidth)
                    }
            )
    }

    @ViewBuilder
    private func sidebarContent() -> some View {
        ZStack(alignment: .topLeading) {
            // Icon row -- positioned from runtime traffic light metrics (absolute)
            sidebarTitleBarRow
                .padding(.top, iconTop - windowContentPadding)
                .zIndex(2)

            // Menu + notes -- positioned from fixed Figma coordinates (absolute)
            VStack(spacing: 0) {
                sidebarMenuContainer

                sidebarNotesHeader
                    .padding(.top, sidebarMenuToNotesGap)

                ScrollView {
                    sidebarNotesList
                }
                .scrollIndicators(.never)
                .padding(.top, 4)
                .padding(.bottom, 4)

                // Settings -- sits below scroll, content clips naturally
                sidebarMenuItem(assetName: "IconSettingsGear1", label: "Settings") {
                    presentSettings()
                }
                .padding(.bottom, sidebarSettingsBottomPadding)
            }
            .padding(.top, sidebarMenuTop)
            .frame(width: sidebarDesignColumnWidth, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    HapticManager.shared.buttonTap()
                    promptCreateFolder()
                } label: {
                    Label("Create New Notebook...", image: "IconFolderAddRight")
                }
            }
            .onTapGesture {
                if isSearchPresented {
                    isSearchPresented = false
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var sidebarNotesList: some View {
        if isShowingArchive {
            sidebarArchiveList
        } else {
            VStack(spacing: sidebarSectionSpacing) {
                if shouldShowPinnedSection {
                    PinnedNotesSection(
                        notes: pinnedNotes,
                        selectedNoteIDs: selectedNoteIDs,
                        activeNoteID: selectedNote?.id,
                        folders: folders,
                        onNoteTap: handleNoteTap,
                        onDeleteNotes: requestDeleteNotes,
                        onCreateFolderWithNotes: { noteIDs in
                            promptCreateFolder(withNoteIDs: noteIDs)
                        },
                        onMoveNotesToFolder: moveNotesToFolder,
                        onTogglePinForNotes: setPinState,
                        onExportNotes: presentExport,
                        onArchiveNotes: archiveNotes,
                        onRenameNote: { note, newTitle in
                            var updatedNote = note
                            updatedNote.title = newTitle
                            notesManager.updateNote(updatedNote)
                        },
                        isExpanded: $isPinnedSectionExpanded
                    )
                }

                if shouldShowFoldersSection {
                    FolderSection(
                        folders: folders,
                        notesByFolder: notesByFolderID,
                        selectedNoteIDs: selectedNoteIDs,
                        activeNoteID: selectedNote?.id,
                        expandedFolderIDs: $expandedFolderIDs,
                        showAllNotesFolderIDs: $showAllNotesFolderIDs,
                        allFolders: folders,
                        onOpenNote: handleNoteTap,
                        onDeleteNotes: requestDeleteNotes,
                        onCreateFolderWithNotes: { noteIDs in
                            promptCreateFolder(withNoteIDs: noteIDs)
                        },
                        onMoveNotesToFolder: moveNotesToFolder,
                        onTogglePinForNotes: setPinState,
                        onExportNotes: presentExport,
                        onArchiveNotes: archiveNotes,
                        onCreateNoteInFolder: { folderID in
                            createAndOpenNewNote(inFolder: folderID)
                        },
                        onRenameFolder: promptEditFolder,
                        onCommitRenameFolder: { folder, newName in
                            notesManager.updateFolder(id: folder.id, name: newName, colorHex: folder.colorHex)
                        },
                        onRenameNote: { note, newTitle in
                            var updatedNote = note
                            updatedNote.title = newTitle
                            notesManager.updateNote(updatedNote)
                        },
                        onArchiveFolder: { folder in
                            notesManager.archiveFolder(folder)
                        },
                        onDeleteFolder: deleteFolder,
                        onDropNotesIntoFolder: { noteIDs, folderID in
                            batchMoveNotes(noteIDs, toFolderID: folderID)
                        }
                    )
                }

                if shouldShowTodaySection {
                    NotesSection(
                        title: "Today",
                        notes: todayNotes,
                        selectedNoteIDs: selectedNoteIDs,
                        activeNoteID: selectedNote?.id,
                        folders: folders,
                        onNoteTap: handleNoteTap,
                        onDeleteNotes: requestDeleteNotes,
                        onCreateFolderWithNotes: { noteIDs in
                            promptCreateFolder(withNoteIDs: noteIDs)
                        },
                        onMoveNotesToFolder: moveNotesToFolder,
                        onTogglePinForNotes: setPinState,
                        onExportNotes: presentExport,
                        onArchiveNotes: archiveNotes,
                        onDropNoteToUnfiled: { noteID in
                            moveNote(noteID: noteID, toFolderID: nil)
                        },
                        onRenameNote: { note, newTitle in
                            var updatedNote = note
                            updatedNote.title = newTitle
                            notesManager.updateNote(updatedNote)
                        }
                    )
                }

                if shouldShowThisMonthSection {
                    NotesSection(
                        title: "This month",
                        notes: thisMonthNotes,
                        selectedNoteIDs: selectedNoteIDs,
                        activeNoteID: selectedNote?.id,
                        folders: folders,
                        onNoteTap: handleNoteTap,
                        onDeleteNotes: requestDeleteNotes,
                        onCreateFolderWithNotes: { noteIDs in
                            promptCreateFolder(withNoteIDs: noteIDs)
                        },
                        onMoveNotesToFolder: moveNotesToFolder,
                        onTogglePinForNotes: setPinState,
                        onExportNotes: presentExport,
                        onArchiveNotes: archiveNotes,
                        onDropNoteToUnfiled: { noteID in
                            moveNote(noteID: noteID, toFolderID: nil)
                        },
                        onRenameNote: { note, newTitle in
                            var updatedNote = note
                            updatedNote.title = newTitle
                            notesManager.updateNote(updatedNote)
                        }
                    )
                }

                if shouldShowThisYearSection {
                    NotesSection(
                        title: "This year",
                        notes: thisYearNotes,
                        selectedNoteIDs: selectedNoteIDs,
                        activeNoteID: selectedNote?.id,
                        folders: folders,
                        onNoteTap: handleNoteTap,
                        onDeleteNotes: requestDeleteNotes,
                        onCreateFolderWithNotes: { noteIDs in
                            promptCreateFolder(withNoteIDs: noteIDs)
                        },
                        onMoveNotesToFolder: moveNotesToFolder,
                        onTogglePinForNotes: setPinState,
                        onExportNotes: presentExport,
                        onArchiveNotes: archiveNotes,
                        onDropNoteToUnfiled: { noteID in
                            moveNote(noteID: noteID, toFolderID: nil)
                        },
                        onRenameNote: { note, newTitle in
                            var updatedNote = note
                            updatedNote.title = newTitle
                            notesManager.updateNote(updatedNote)
                        }
                    )
                }

                if shouldShowOlderSection {
                    NotesSection(
                        title: "Older",
                        notes: olderNotes,
                        selectedNoteIDs: selectedNoteIDs,
                        activeNoteID: selectedNote?.id,
                        folders: folders,
                        onNoteTap: handleNoteTap,
                        onDeleteNotes: requestDeleteNotes,
                        onCreateFolderWithNotes: { noteIDs in
                            promptCreateFolder(withNoteIDs: noteIDs)
                        },
                        onMoveNotesToFolder: moveNotesToFolder,
                        onTogglePinForNotes: setPinState,
                        onExportNotes: presentExport,
                        onArchiveNotes: archiveNotes,
                        onDropNoteToUnfiled: { noteID in
                            moveNote(noteID: noteID, toFolderID: nil)
                        },
                        onRenameNote: { note, newTitle in
                            var updatedNote = note
                            updatedNote.title = newTitle
                            notesManager.updateNote(updatedNote)
                        }
                    )
                }

                if shouldShowUnfiledPlaceholderSection {
                    NotesSection(
                        title: "Unfiled",
                        notes: [],
                        selectedNoteIDs: selectedNoteIDs,
                        activeNoteID: selectedNote?.id,
                        folders: folders,
                        onNoteTap: handleNoteTap,
                        onDeleteNotes: requestDeleteNotes,
                        onCreateFolderWithNotes: { noteIDs in
                            promptCreateFolder(withNoteIDs: noteIDs)
                        },
                        onMoveNotesToFolder: moveNotesToFolder,
                        onTogglePinForNotes: setPinState,
                        onExportNotes: presentExport,
                        onArchiveNotes: archiveNotes,
                        onDropNoteToUnfiled: { noteID in
                            moveNote(noteID: noteID, toFolderID: nil)
                        },
                        onRenameNote: { note, newTitle in
                            var updatedNote = note
                            updatedNote.title = newTitle
                            notesManager.updateNote(updatedNote)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private var shouldShowPinnedSection: Bool {
        sidebarSectionFilterAllows(sidebarSectionFilter, section: .pinned) && !pinnedNotes.isEmpty
    }

    private var shouldShowFoldersSection: Bool {
        sidebarSectionFilterAllows(sidebarSectionFilter, section: .folders) && !folders.isEmpty
    }

    private var shouldShowTodaySection: Bool {
        sidebarSectionFilterAllows(sidebarSectionFilter, section: .today) && !todayNotes.isEmpty
    }

    private var shouldShowThisMonthSection: Bool {
        sidebarSectionFilterAllows(sidebarSectionFilter, section: .thisMonth) && !thisMonthNotes.isEmpty
    }

    private var shouldShowThisYearSection: Bool {
        sidebarSectionFilterAllows(sidebarSectionFilter, section: .thisYear) && !thisYearNotes.isEmpty
    }

    private var shouldShowOlderSection: Bool {
        sidebarSectionFilterAllows(sidebarSectionFilter, section: .older) && !olderNotes.isEmpty
    }

    private var shouldShowUnfiledPlaceholderSection: Bool {
        sidebarSectionFilter == .all && !hasVisibleUnfiledSections && !displayedNotes.isEmpty
    }

    private var sidebarTitleBarRow: some View {
        HStack(spacing: sidebarTopIconSpacingCollapsed) {
            sidebarTopBarIcon(assetName: "IconLayoutAlignLeft") {
                withAnimation(sidebarVisibilityAnimation) {
                    isSidebarVisible = false
                }
            }
        }
        .padding(.leading, iconLeading - windowContentPadding)
        .frame(width: sidebarDesignColumnWidth, height: sidebarTopBarButtonSize, alignment: .leading)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
    }

    private var sidebarMenuContainer: some View {
        VStack(spacing: 0) {
            sidebarMenuItem(assetName: "IconNoteText", label: "New Note") {
                createAndOpenNewNote()
            }
            sidebarMenuItem(assetName: "IconMagnifyingGlass", label: "Search") {
                presentSearch()
            }
            sidebarMenuItem(
                assetName: isShowingArchive ? "IconChevronRightMedium" : "IconArchive1",
                label: isShowingArchive ? "Go back" : "Archive",
                flipIcon: isShowingArchive
            ) {
                withAnimation(.jotSpring) {
                    isShowingArchive.toggle()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarMenuItem(
        assetName: String,
        label: String,
        flipIcon: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                sidebarAssetIcon(assetName: assetName, tint: Color("SecondaryTextColor"))
                    .scaleEffect(x: flipIcon ? -1 : 1, y: 1)

                Text(label)
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .tracking(-0.4)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .scaleEffect(hoveredSidebarMenuLabel == label ? 1.01 : 1.0)
            .padding(.leading, sidebarItemLeadingPadding)
            .padding(.trailing, sidebarItemTrailingPadding)
            .padding(.vertical, sidebarItemVPadding)
            .frame(height: sidebarMenuItemHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
                    .padding(.horizontal, sidebarRowHoverInset)
            )
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .animation(.jotHover, value: hoveredSidebarMenuLabel)
        .onHover { isHovering in
            if isHovering {
                hoveredSidebarMenuLabel = label
            } else if hoveredSidebarMenuLabel == label {
                hoveredSidebarMenuLabel = nil
            }
        }
    }

    private var sidebarNotesHeader: some View {
        HStack(spacing: 12) {
            Text(isShowingArchive ? "Archive" : "Notes")
                .font(FontManager.heading(size: 13, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))

            Spacer(minLength: 0)

            if !isShowingArchive {
                sidebarBareIcon(assetName: "IconFolderAddRight") {
                    promptCreateFolder()
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            createFolderButtonFrame = geo.frame(in: .named("contentArea"))
                        }
                        .onChange(of: geo.frame(in: .named("contentArea"))) { _, newFrame in
                            createFolderButtonFrame = newFrame
                        }
                    }
                )

                Menu {
                    ForEach(SidebarSectionFilter.allCases) { filter in
                        Button {
                            sidebarSectionFilter = filter
                        } label: {
                            Label(
                                filter.label,
                                systemImage: sidebarSectionFilter == filter ? "checkmark" : ""
                            )
                        }
                    }
                } label: {
                    sidebarAssetIcon(assetName: "IconFilterCircle", tint: Color("SecondaryTextColor"))
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.06)
            }
        }
        .padding(.leading, sidebarItemLeadingPadding)
        .padding(.trailing, sidebarItemTrailingPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarBareIcon(
        assetName: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            sidebarAssetIcon(assetName: assetName, tint: Color("SecondaryTextColor"))
                .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .subtleHoverScale(1.06)
    }

    private var sidebarArchiveList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if notesManager.archivedFolders.isEmpty && notesManager.archivedNotes.isEmpty {
                Text("No archived items")
                    .font(FontManager.metadata(size: 11, weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, sidebarItemLeadingPadding)
                    .padding(.trailing, sidebarItemTrailingPadding)
                    .padding(.top, 12)
            } else {
                if !notesManager.archivedFolders.isEmpty {
                    Text("Folders")
                        .font(FontManager.heading(size: 13, weight: .medium))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .padding(.horizontal, sidebarItemLeadingPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    
                    ForEach(notesManager.archivedFolders, id: \.id) { folder in
                        HStack(spacing: 8) {
                            Image("IconFolder2")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(folder.folderColor)
                                .frame(width: 20, height: 20)
                            
                            Text(folder.name)
                                .font(FontManager.heading(size: 15, weight: .medium))
                                .foregroundColor(Color("PrimaryTextColor"))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Button {
                                HapticManager.shared.buttonTap()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    notesManager.unarchiveFolder(folder)
                                }
                            } label: {
                                Image("IconStepBack")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 15, height: 15)
                                    .foregroundColor(Color("SecondaryTextColor"))
                            }
                            .buttonStyle(.plain)
                            .subtleHoverScale(1.06)
                            .help("Unarchive Folder")
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.clear)
                        )
                        .padding(.horizontal, sidebarRowHoverInset)
                        .contextMenu {
                            Button {
                                notesManager.unarchiveFolder(folder)
                            } label: {
                                Label {
                                    Text("Unarchive Folder")
                                } icon: {
                                    Image("IconStepBack")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                }
                            }
                            
                            Button(role: .destructive) {
                                deleteFolder(folder)
                            } label: {
                                Label("Delete Folder", image: "delete")
                            }
                        }
                    }
                }
                
                if !notesManager.archivedNotes.isEmpty {
                    if !notesManager.archivedFolders.isEmpty {
                        Text("Notes")
                            .font(FontManager.heading(size: 13, weight: .medium))
                            .foregroundColor(Color("SecondaryTextColor"))
                            .padding(.horizontal, sidebarItemLeadingPadding)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                    }
                    
                    ForEach(notesManager.archivedNotes, id: \.id) { note in
                        ArchivedNoteRow(
                            note: note,
                            isSelected: selectedNoteIDs.contains(note.id),
                            isActive: note.id == selectedNote?.id,
                            onTap: { handleNoteTap(note, .plain) },
                            onUnarchive: { unarchiveNotes([note.id]) },
                            onDelete: { requestDeleteNotes([note.id]) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .onAppear {
            notesManager.loadArchivedNotes()
            notesManager.loadArchivedFolders()
        }
    }

    private func presentSearch() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSettingsPresented = false
            isSearchPresented = true
        }
    }

    private func presentSettings() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSearchPresented = false
            isSettingsPresented = true
        }
    }

    @ViewBuilder
    private func appCenteredSearchOverlay() -> some View {
        ZStack {
            if isSearchPresented {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        isSearchPresented = false
                    }
            }

            FloatingSearch(
                engine: searchEngine,
                isPresented: $isSearchPresented,
                onNoteSelected: { note in
                    openNote(note)
                },
                onFolderSelected: { folder in
                    openFolder(folder)
                },
                folders: folders
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 182)
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchPresented)
    }

    @ViewBuilder
    private func appWindowSettingsOverlay() -> some View {
        ZStack {
            Color.black
                .opacity(isSettingsPresented ? 0.001 : 0)
                .allowsHitTesting(isSettingsPresented)
                .onTapGesture {
                    if isSettingsPresented {
                        isSettingsPresented = false
                    }
                }

            FloatingSettings(isPresented: $isSettingsPresented)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(isSettingsPresented ? 1 : 0)
                .allowsHitTesting(isSettingsPresented)
        }
        .clipShape(RoundedRectangle(cornerRadius: windowCornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: isSettingsPresented)
    }

    private var globalSearchShortcutActivator: some View {
        Group {
            // Cmd+F -> in-note search
            Button(action: { presentInNoteSearch() }) {
                Color.clear.frame(width: 1, height: 1)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command])
            .opacity(0.001)

            // Cmd+Shift+F -> global search
            Button(action: presentSearch) {
                Color.clear.frame(width: 1, height: 1)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .opacity(0.001)

            // Cmd+K -> global search
            Button(action: presentSearch) {
                Color.clear.frame(width: 1, height: 1)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: [.command])
            .opacity(0.001)

            // Cmd+. -> toggle sidebar
            Button {
                withAnimation(sidebarVisibilityAnimation) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Color.clear.frame(width: 1, height: 1)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: [.command])
            .opacity(0.001)
        }
        .accessibilityHidden(true)
    }

    private func presentInNoteSearch() {
        guard selectedNote != nil else {
            presentSearch()
            return
        }
        NotificationCenter.default.post(name: .showInNoteSearch, object: nil)
    }

    private var collapsedTopBarRow: some View {
        HStack(spacing: sidebarTopIconSpacingCollapsed) {
            sidebarTopBarIcon(assetName: "IconLayoutAlignLeft") {
                withAnimation(sidebarVisibilityAnimation) {
                    isSidebarVisible = true
                }
            }

            sidebarTopBarIcon(assetName: "IconNoteText") {
                createAndOpenNewNote()
            }
            .opacity(isFloatingSidebarVisible ? 0 : 1)
            .allowsHitTesting(!isFloatingSidebarVisible)

            sidebarTopBarIcon(assetName: "IconMagnifyingGlass") {
                presentSearch()
            }
            .opacity(isFloatingSidebarVisible ? 0 : 1)
            .allowsHitTesting(!isFloatingSidebarVisible)
        }
        .padding(.leading, iconLeading)
        .padding(.top, iconTop)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .zIndex(4)
    }

    // MARK: - Floating Sidebar

    @ViewBuilder
    private var floatingSidebarPanel: some View {
        VStack(spacing: 0) {
            sidebarMenuContainer

            sidebarNotesHeader
                .padding(.top, sidebarMenuToNotesGap)

            ScrollView {
                sidebarNotesList
            }
            .scrollIndicators(.never)
            .padding(.top, 4)
            .padding(.bottom, 4)

            sidebarMenuItem(assetName: "IconSettingsGear1", label: "Settings") {
                presentSettings()
            }
            .padding(.bottom, sidebarSettingsBottomPadding)
        }
        .padding(.horizontal, 8)
        .frame(width: floatingSidebarWidth)
        .frame(maxHeight: .infinity)
        .padding(.vertical, 8)
        .liquidGlass(in: RoundedRectangle(cornerRadius: floatingSidebarCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 9.5, x: 0, y: 9)
        .shadow(color: .black.opacity(0.02), radius: 17.5, x: 0, y: 35)
        .shadow(color: .black.opacity(0.01), radius: 23.5, x: 0, y: 78)
    }

    @ViewBuilder
    private var floatingSidebarOverlay: some View {
        let topOffset = iconTop + sidebarTopBarButtonSize + floatingSidebarEdgeInset
        let triggerBottomExclusion: CGFloat = 100

        GeometryReader { geo in
            let availableHeight = geo.size.height - topOffset - floatingSidebarEdgeInset
            let triggerHeight = max(0, availableHeight - triggerBottomExclusion)

            ZStack(alignment: .topLeading) {
                // Invisible hover trigger strip -- explicit height, stops above NoteToolsBar
                Color.clear
                    .frame(
                        width: isFloatingSidebarVisible
                            ? (floatingSidebarWidth + floatingSidebarEdgeInset + 20)
                            : floatingSidebarHoverTriggerWidth,
                        height: triggerHeight
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleFloatingSidebarHover(hovering)
                    }

                // The floating panel -- full height, 10px from bottom
                floatingSidebarPanel
                    .frame(height: availableHeight)
                    .padding(.leading, floatingSidebarEdgeInset)
                    .opacity(isFloatingSidebarVisible ? 1 : 0)
                    .offset(x: isFloatingSidebarVisible ? 0 : -20)
                    .allowsHitTesting(isFloatingSidebarVisible)
                    .animation(.jotSpring, value: isFloatingSidebarVisible)
            }
            .padding(.top, topOffset)
        }
        .ignoresSafeArea()
    }

    private func handleFloatingSidebarHover(_ isHovering: Bool) {
        floatingSidebarDismissWorkItem?.cancel()
        floatingSidebarDismissWorkItem = nil

        if isHovering {
            if !isFloatingSidebarVisible {
                withAnimation(.jotSpring) {
                    isFloatingSidebarVisible = true
                }
            }
        } else {
            let work = DispatchWorkItem {
                withAnimation(.jotSpring) {
                    isFloatingSidebarVisible = false
                }
            }
            floatingSidebarDismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + floatingSidebarDismissDelay, execute: work)
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private func detailPane(note: Note) -> some View {
        NoteDetailView(
            note: note,
            focusRequestID: detailFocusRequestID,
            contentTopInsetAdjustment: isSidebarVisible ? 0 : detailToggleToContentExtraSpacingWhenSidebarHidden
        ) { updated in
            saveUpdatedNote(updated)
        }
    }

    private func sidebarAssetIcon(assetName: String, tint: Color) -> some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(tint)
            .frame(width: sidebarIconSize, height: sidebarIconSize)
    }

    private func sidebarTopBarIcon(
        assetName: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            sidebarAssetIcon(assetName: assetName, tint: Color("SecondaryTextColor"))
                .frame(width: sidebarTopBarButtonSize, height: sidebarTopBarButtonSize, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .subtleHoverScale(1.06)
    }

    // MARK: - Actions

    private func handleNoteTap(_ note: Note, _ interaction: NoteSelectionInteraction) {
        let visibleNoteIDs = visibleSidebarNotesInOrder.map(\.id)
        let reduction = NoteSelectionReducer.apply(
            interaction: interaction,
            noteID: note.id,
            currentSelection: selectedNoteIDs,
            currentAnchor: selectionAnchorID,
            orderedVisibleNoteIDs: visibleNoteIDs
        )

        selectedNoteIDs = reduction.selection
        selectionAnchorID = reduction.anchor

        switch interaction {
        case .plain:
            openNote(note)
        case .commandToggle, .shiftRange:
            synchronizeDetailPaneWithSelection()
        }
    }

    private var isInitialDataReady: Bool {
        notesManager.hasLoadedInitialNotes && notesManager.hasCompletedMigrationCheck
    }

    private func requestEditorFocus() {
        detailFocusRequestID = UUID()
    }

    private func clampedSidebarWidth(_ proposedWidth: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let maximumAllowed = max(sidebarMinWidth, min(sidebarMaxWidth, totalWidth - minimumDetailWidth))
        return min(max(proposedWidth, sidebarMinWidth), maximumAllowed)
    }

    private func saveUpdatedNote(_ updated: Note) {
        notesManager.updateNote(updated)
        selectedNote = updated
        if selectedNoteIDs.isEmpty {
            selectedNoteIDs = [updated.id]
        } else if !selectedNoteIDs.contains(updated.id) {
            selectedNoteIDs.insert(updated.id)
        }
        selectionAnchorID = selectionAnchorID ?? updated.id
    }

    private func openNote(_ note: Note, focusEditor: Bool = true, withHaptic: Bool = true) {
        if withHaptic {
            HapticManager.shared.noteInteraction()
        }

        selectedNote = note
        selectedNoteIDs = [note.id]
        selectionAnchorID = note.id

        hasAppliedInitialLaunchSelection = true
        if focusEditor {
            requestEditorFocus()
        }
    }

    private func openFolder(_ folder: Folder, withHaptic: Bool = true) {
        if withHaptic {
            HapticManager.shared.noteInteraction()
        }

        withAnimation(.jotSpring) {
            isShowingArchive = false
            sidebarSectionFilter = .folders
            expandedFolderIDs.insert(folder.id)
            showAllNotesFolderIDs.insert(folder.id)
            isSidebarVisible = true
        }

        if let firstNote = (notesByFolderID[folder.id] ?? []).first {
            openNote(firstNote, withHaptic: false)
        }
    }

    private func createAndOpenNewNote() {
        _ = createAndOpenNewNote(inFolder: nil)
    }

    @discardableResult
    private func createAndOpenNewNote(
        inFolder folderID: UUID?,
        focusEditor: Bool = true,
        withHaptic: Bool = true,
        animated: Bool = true
    ) -> Note {
        if withHaptic {
            HapticManager.shared.noteInteraction()
        }
        let note = notesManager.addNote(title: "", content: "", folderID: folderID)

        if let folderID {
            expandedFolderIDs.insert(folderID)
        }

        if animated {
            withAnimation(.jotSpring) {
                selectedNote = note
                selectedNoteIDs = [note.id]
                selectionAnchorID = note.id
            }
        } else {
            selectedNote = note
            selectedNoteIDs = [note.id]
            selectionAnchorID = note.id
        }

        hasAppliedInitialLaunchSelection = true
        if focusEditor {
            requestEditorFocus()
        }

        return note
    }

    @discardableResult
    private func moveNote(noteID: UUID, toFolderID folderID: UUID?) -> Bool {
        let moved = notesManager.moveNote(id: noteID, toFolderID: folderID)
        guard moved else { return false }

        if let folderID {
            expandedFolderIDs.insert(folderID)
        }

        if selectedNote?.id == noteID,
           let updated = notesManager.notes.first(where: { $0.id == noteID }) {
            selectedNote = updated
        }

        return true
    }

    private func batchMoveNotes(_ noteIDs: Set<UUID>, toFolderID: UUID?) -> Bool {
        guard !noteIDs.isEmpty else { return false }
        let count = notesManager.moveNotes(ids: noteIDs, toFolderID: toFolderID)
        return count > 0
    }

    private func moveNotesToFolder(_ noteIDs: Set<UUID>, _ folderID: UUID?) {
        guard !noteIDs.isEmpty else { return }

        HapticManager.shared.buttonTap()

        if noteIDs.count == 1, let noteID = noteIDs.first {
            _ = moveNote(noteID: noteID, toFolderID: folderID)
            return
        }

        let moved = notesManager.moveNotes(ids: noteIDs, toFolderID: folderID)
        guard moved > 0 else { return }

        if let folderID {
            expandedFolderIDs.insert(folderID)
        }

        reconcileSelectionWithCurrentNotes()
    }

    private func setPinState(for noteIDs: Set<UUID>, pinned: Bool) {
        guard !noteIDs.isEmpty else { return }

        HapticManager.shared.buttonTap()

        for noteID in noteIDs {
            guard let note = notesManager.notes.first(where: { $0.id == noteID }) else { continue }
            guard note.isPinned != pinned else { continue }
            withAnimation(.easeInOut(duration: 0.25)) {
                notesManager.togglePin(id: noteID)
            }
        }
    }

    private func requestDeleteNotes(_ noteIDs: Set<UUID>) {
        guard !noteIDs.isEmpty else { return }

        if noteIDs.count > 1 {
            pendingDeleteNoteIDs = noteIDs
            isBatchDeleteConfirmationPresented = true
            return
        }

        deleteNotesNow(noteIDs)
    }

    private func deleteNotesNow(_ noteIDs: Set<UUID>) {
        guard !noteIDs.isEmpty else { return }

        let deleted = notesManager.deleteNotes(ids: noteIDs)
        guard deleted > 0 else { return }

        selectedNoteIDs.subtract(noteIDs)
        pendingDeleteNoteIDs.subtract(noteIDs)

        if let selectionAnchorID, noteIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = selectedNoteIDs.first
        }

        reconcileSelectionWithCurrentNotes()
    }

    private func archiveNotes(_ noteIDs: Set<UUID>) {
        guard !noteIDs.isEmpty else { return }

        HapticManager.shared.buttonTap()
        let archived = notesManager.archiveNotes(ids: noteIDs)
        guard archived > 0 else { return }

        selectedNoteIDs.subtract(noteIDs)

        if let selectionAnchorID, noteIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = selectedNoteIDs.first
        }

        reconcileSelectionWithCurrentNotes()
    }

    private func unarchiveNotes(_ noteIDs: Set<UUID>) {
        guard !noteIDs.isEmpty else { return }

        HapticManager.shared.buttonTap()
        let unarchived = notesManager.unarchiveNotes(ids: noteIDs)
        guard unarchived > 0 else { return }
    }

    private func presentExport(_ noteIDs: Set<UUID>) {
        let notes = notesForExport(noteIDs)
        guard !notes.isEmpty else { return }

        notesPendingExport = notes
        isBatchExportSheetPresented = true
    }

    private func promptMoveSelectedNotesByName(_ noteIDs: Set<UUID>) {
        guard !noteIDs.isEmpty else { return }

        pendingMoveNoteIDs = noteIDs
        batchMoveFolderName = ""
        isBatchMoveAlertPresented = true
    }

    private func confirmMoveSelectedNotesByName() {
        let trimmedName = batchMoveFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { resetPendingMoveSelection() }
        guard !trimmedName.isEmpty else { return }

        let destinationFolderID: UUID?
        if let existingFolder = folders.first(where: {
            $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            destinationFolderID = existingFolder.id
        } else if let createdFolder = notesManager.createFolder(name: trimmedName) {
            destinationFolderID = createdFolder.id
            expandedFolderIDs.insert(createdFolder.id)
        } else {
            destinationFolderID = nil
        }

        guard let destinationFolderID else { return }
        moveNotesToFolder(pendingMoveNoteIDs, destinationFolderID)
    }

    private func resetPendingMoveSelection() {
        pendingMoveNoteIDs.removeAll()
        batchMoveFolderName = ""
    }

    private func promptCreateFolder(withNoteIDs noteIDs: Set<UUID>? = nil) {
        if let noteIDs, !noteIDs.isEmpty {
            pendingFolderCreationIntent = .withNotes(noteIDs)
        } else {
            pendingFolderCreationIntent = .standalone
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isCreateFolderAlertPresented = true
        }
    }

    private func confirmCreateFolder(name: String, colorHex: String? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        HapticManager.shared.buttonTap()

        switch pendingFolderCreationIntent {
        case .standalone:
            if let folder = notesManager.createFolder(name: trimmedName, colorHex: colorHex) {
                expandedFolderIDs.insert(folder.id)
            }
        case let .withNotes(noteIDs):
            guard let folder = notesManager.createFolder(name: trimmedName, colorHex: colorHex) else {
                resetPendingFolderCreation()
                return
            }

            expandedFolderIDs.insert(folder.id)
            _ = notesManager.moveNotes(ids: noteIDs, toFolderID: folder.id)

            if noteIDs.count == 1,
               let singleNoteID = noteIDs.first,
               let movedNote = notesManager.notes.first(where: { $0.id == singleNoteID }) {
                openNote(movedNote)
            } else {
                synchronizeDetailPaneWithSelection()
            }
        }

        resetPendingFolderCreation()
    }

    private func resetPendingFolderCreation() {
        pendingFolderCreationIntent = .standalone
    }

    @ViewBuilder
    private func folderSheetOverlay<Content: View>(
        @ViewBuilder content: () -> Content,
        onDismiss: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            content()
                .padding(.top, createFolderButtonFrame.maxY + 8)
                .padding(.leading, createFolderButtonFrame.minX - 4)
                .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
        }
    }

    private func promptEditFolder(_ folder: Folder) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            pendingFolderToEdit = folder
        }
    }

    private func confirmEditFolder(name: String, colorHex: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let folder = pendingFolderToEdit else { return }

        HapticManager.shared.buttonTap()
        notesManager.updateFolder(id: folder.id, name: trimmedName, colorHex: colorHex)
        pendingFolderToEdit = nil
    }

    private func deleteFolder(_ folder: Folder) {
        HapticManager.shared.buttonTap()
        notesManager.deleteFolder(id: folder.id)
        expandedFolderIDs.remove(folder.id)
        showAllNotesFolderIDs.remove(folder.id)

        if let selectedID = selectedNote?.id,
           let updated = notesManager.notes.first(where: { $0.id == selectedID }) {
            selectedNote = updated
        }

        synchronizeDetailPaneWithSelection()
    }

    private func handleSelectionCommand(_ action: NoteSelectionCommandAction) {
        switch action {
        case .selectAll:
            let visibleIDs = visibleSidebarNotesInOrder.map(\.id)
            selectedNoteIDs = NoteSelectionReducer.selectAll(orderedVisibleNoteIDs: visibleIDs)
            if let selectionAnchorID, selectedNoteIDs.contains(selectionAnchorID) {
                // Keep anchor if still selected.
            } else {
                selectionAnchorID = visibleIDs.first
            }
            synchronizeDetailPaneWithSelection()

        case .clearSelection:
            if isSettingsPresented {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSettingsPresented = false
                }
                return
            }
            selectedNoteIDs.removeAll()
            selectionAnchorID = nil
            synchronizeDetailPaneWithSelection()

        case .deleteSelection:
            requestDeleteNotes(selectedNoteIDs)

        case .exportSelection:
            presentExport(selectedNoteIDs)

        case .moveSelection:
            promptMoveSelectedNotesByName(selectedNoteIDs)
        }
    }

    private func notesForExport(_ noteIDs: Set<UUID>) -> [Note] {
        guard !noteIDs.isEmpty else { return [] }

        let visibleOrder = visibleSidebarNotesInOrder.map(\.id)
        let noteByID = Dictionary(uniqueKeysWithValues: notesManager.notes.map { ($0.id, $0) })

        var ordered: [Note] = []

        for id in visibleOrder where noteIDs.contains(id) {
            if let note = noteByID[id] {
                ordered.append(note)
            }
        }

        let alreadyIncluded = Set(ordered.map(\.id))
        let remaining = noteIDs.subtracting(alreadyIncluded)
        if !remaining.isEmpty {
            ordered.append(contentsOf: notesManager.notes.filter { remaining.contains($0.id) })
        }

        return ordered
    }

    private func reconcileSelectionWithCurrentNotes(_ notes: [Note]? = nil) {
        let source = notes ?? notesManager.notes
        let validIDs = Set(source.map(\.id))

        selectedNoteIDs.formIntersection(validIDs)
        pendingDeleteNoteIDs.formIntersection(validIDs)
        pendingMoveNoteIDs.formIntersection(validIDs)
        notesPendingExport = notesPendingExport.compactMap { exportNote in
            source.first(where: { $0.id == exportNote.id })
        }

        if notesPendingExport.isEmpty {
            isBatchExportSheetPresented = false
        }

        if let selectionAnchorID, !validIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = selectedNoteIDs.first
        }

        if let selectedID = selectedNote?.id, !validIDs.contains(selectedID) {
            selectedNote = nil
        }

        guard isInitialDataReady else {
            if let selectedID = selectedNote?.id,
               let updated = source.first(where: { $0.id == selectedID }) {
                selectedNote = updated
            }
            return
        }

        if source.isEmpty {
            autoCreateStarterNoteIfNeeded()
            return
        }

        let shouldRequestInitialFocus = !hasAppliedInitialLaunchSelection
        synchronizeDetailPaneWithSelection(
            in: source,
            requestFocusIfSelectionChanges: shouldRequestInitialFocus
        )
        hasAppliedInitialLaunchSelection = true
    }

    private func autoCreateStarterNoteIfNeeded() {
        guard isInitialDataReady else { return }
        guard notesManager.notes.isEmpty else { return }
        guard !isAutoCreatingStarterNote else { return }

        isAutoCreatingStarterNote = true
        _ = createAndOpenNewNote(
            inFolder: nil,
            focusEditor: true,
            withHaptic: false,
            animated: false
        )
        isAutoCreatingStarterNote = false
    }

    private func resolvePreferredActiveNote(in notes: [Note]) -> Note? {
        NoteSelectionPolicy.resolveActiveNote(
            notes: notes,
            currentActiveID: selectedNote?.id,
            selectedNoteIDs: selectedNoteIDs,
            selectionAnchorID: selectionAnchorID
        )
    }

    private func synchronizeDetailPaneWithSelection(
        in notes: [Note]? = nil,
        requestFocusIfSelectionChanges: Bool = false
    ) {
        let source = notes ?? notesManager.notes

        guard let resolvedNote = resolvePreferredActiveNote(in: source) else {
            selectedNote = nil
            selectedNoteIDs.removeAll()
            selectionAnchorID = nil
            return
        }

        let previousID = selectedNote?.id
        selectedNote = resolvedNote

        if selectedNoteIDs.isEmpty || !selectedNoteIDs.contains(resolvedNote.id) {
            selectedNoteIDs = [resolvedNote.id]
        }

        if let selectionAnchorID, selectedNoteIDs.contains(selectionAnchorID) {
            // Keep existing anchor when it is still valid.
        } else {
            selectionAnchorID = resolvedNote.id
        }

        if requestFocusIfSelectionChanges, previousID != resolvedNote.id {
            requestEditorFocus()
        }
    }

    // MARK: - Computed Properties

    private var displayedNotes: [Note] {
        // For now always show all notes until the new search manager is introduced
        return notesManager.notes
    }

    private var folders: [Folder] {
        notesManager.folders
    }

    // These forward to the manager's pre-computed collections — O(1), no recomputation on each render.
    private var notesByFolderID: [UUID: [Note]] { notesManager.notesByFolderID }
    private var unfiledNotes: [Note] { notesManager.unfiledNotes }
    private var pinnedNotes: [Note] { notesManager.pinnedNotes }
    private var todayNotes: [Note] { notesManager.todayNotes }
    private var thisMonthNotes: [Note] { notesManager.thisMonthNotes }
    private var thisYearNotes: [Note] { notesManager.thisYearNotes }
    private var olderNotes: [Note] { notesManager.olderNotes }

    private var hasVisibleUnfiledSections: Bool {
        !todayNotes.isEmpty || !thisMonthNotes.isEmpty || !thisYearNotes.isEmpty || !olderNotes.isEmpty
    }

    private var hasLooseNotesSection: Bool {
        hasVisibleUnfiledSections || (!hasVisibleUnfiledSections && !displayedNotes.isEmpty)
    }

    private var visibleSidebarNotesInOrder: [Note] {
        var ordered: [Note] = []

        switch sidebarSectionFilter {
        case .all:
            ordered.append(contentsOf: pinnedNotes)
            for folder in folders where expandedFolderIDs.contains(folder.id) {
                ordered.append(contentsOf: visibleFolderNotes(for: folder.id))
            }
            ordered.append(contentsOf: todayNotes)
            ordered.append(contentsOf: thisMonthNotes)
            ordered.append(contentsOf: thisYearNotes)
            ordered.append(contentsOf: olderNotes)
        case .pinned:
            ordered.append(contentsOf: pinnedNotes)
        case .folders:
            for folder in folders where expandedFolderIDs.contains(folder.id) {
                ordered.append(contentsOf: visibleFolderNotes(for: folder.id))
            }
        case .today:
            ordered.append(contentsOf: todayNotes)
        case .thisMonth:
            ordered.append(contentsOf: thisMonthNotes)
        case .thisYear:
            ordered.append(contentsOf: thisYearNotes)
        case .older:
            ordered.append(contentsOf: olderNotes)
        }

        return ordered
    }

    private func visibleFolderNotes(for folderID: UUID) -> [Note] {
        let notes = notesByFolderID[folderID] ?? []
        let showsAll = showAllNotesFolderIDs.contains(folderID)
        if notes.count > 5 && !showsAll {
            return Array(notes.prefix(5))
        }
        return notes
    }
}

// Notes Section Component
struct NotesSection: View {
    let title: String
    let notes: [Note]
    var selectedNoteIDs: Set<UUID> = []
    var activeNoteID: UUID? = nil
    let folders: [Folder]
    let onNoteTap: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void
    var onArchiveNotes: ((Set<UUID>) -> Void)? = nil
    var onDropNoteToUnfiled: ((UUID) -> Bool)? = nil
    var onRenameNote: ((Note, String) -> Void)? = nil

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(FontManager.heading(size: 13, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            // Notes list
            ForEach(notes, id: \.id) { note in
                NoteListCard(
                    note: note,
                    isSelected: selectedNoteIDs.contains(note.id),
                    isActiveNote: note.id == activeNoteID,
                    onTap: { interaction in onNoteTap(note, interaction) },
                    onTogglePin: { shouldPin in
                        onTogglePinForNotes(contextSelection(for: note), shouldPin)
                    },
                    onDelete: { onDeleteNotes(contextSelection(for: note)) },
                    folders: folders,
                    onCreateFolderWithNote: { onCreateFolderWithNotes(contextSelection(for: note)) },
                    onMoveToFolder: { folderID in
                        onMoveNotesToFolder(contextSelection(for: note), folderID)
                    },
                    onExport: { onExportNotes(contextSelection(for: note)) },
                    onArchive: onArchiveNotes != nil ? { onArchiveNotes?(contextSelection(for: note)) } : nil,
                    onRename: { newTitle in
                        onRenameNote?(note, newTitle)
                    },
                    getDragItems: {
                        if selectedNoteIDs.contains(note.id) {
                            return selectedNoteIDs.map { NoteDragItem(noteID: $0) }
                        } else {
                            return [NoteDragItem(noteID: note.id)]
                        }
                    }
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargeted ? Color("SurfaceTranslucentColor") : Color.clear)
        )
        .if(onDropNoteToUnfiled != nil) { view in
            view.dropDestination(for: TransferablePayload.self) { payloads, _ in
                let items = payloads.flatMap { $0.items }
                guard let first = items.first,
                      let onDropNoteToUnfiled else {
                    return false
                }
                return onDropNoteToUnfiled(first.noteID)
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
        }
    }

    private func contextSelection(for note: Note) -> Set<UUID> {
        if selectedNoteIDs.count > 1, selectedNoteIDs.contains(note.id) {
            return selectedNoteIDs
        }
        return [note.id]
    }
}

// Note List Card Component (Figma design)
struct NoteListCard: View {
    let note: Note
    var isSelected: Bool = false
    var isActiveNote: Bool = false
    var activeIconTint: Color = Color("SecondaryTextColor")
    var isInsideFolder: Bool = false
    var leadingIconAssetName: String? = nil
    var hoverLeadingIconAssetName: String? = nil
    var showLeadingIconOnHoverOnly: Bool = false
    var onLeadingIconTap: (() -> Void)? = nil
    let onTap: (NoteSelectionInteraction) -> Void
    let onTogglePin: (Bool) -> Void
    let onDelete: () -> Void
    let folders: [Folder]
    let onCreateFolderWithNote: () -> Void
    let onMoveToFolder: (UUID?) -> Void
    let onExport: () -> Void
    var onArchive: (() -> Void)? = nil
    var onRename: ((String) -> Void)? = nil
    var getDragItems: (() -> [NoteDragItem])? = nil
    var cornerRadius: CGFloat = 10
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renamingTitle = ""
    @FocusState private var isFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            if !isRenaming {
                onTap(Self.selectionInteractionFromCurrentEvent())
            }
        } label: {
            HStack(spacing: 8) {
                if let icon = leadingIconAssetName {
                    let isLeadingIconVisible = !showLeadingIconOnHoverOnly || isHovered
                    let isShowingHoverVariant = isHovered && hoverLeadingIconAssetName != nil
                    ZStack {
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color("SecondaryTextColor"))
                            .frame(width: 20, height: 20)
                            .opacity(isLeadingIconVisible && !isShowingHoverVariant ? 1 : 0)

                        if let hoverIcon = hoverLeadingIconAssetName {
                            Image(hoverIcon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Color("SecondaryTextColor"))
                                .frame(width: 20, height: 20)
                                .opacity(isLeadingIconVisible && isShowingHoverVariant ? 1 : 0)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onLeadingIconTap?()
                    }
                    .macPointingHandCursor()
                    .allowsHitTesting(isLeadingIconVisible && onLeadingIconTap != nil)
                    .animation(.easeInOut(duration: 0.12), value: isLeadingIconVisible)
                    .animation(.easeInOut(duration: 0.1), value: isShowingHoverVariant)
                }

                if isRenaming {
                    TextField("Note Title", text: $renamingTitle)
                        .font(FontManager.heading(size: 15, weight: .medium))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .textFieldStyle(.plain)
                        .focused($isFieldFocused)
                        .onSubmit {
                            commitRename()
                        }
                        .onExitCommand {
                            cancelRename()
                        }
                } else {
                    Text(note.title)
                        .font(FontManager.heading(size: 15, weight: .medium))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .tracking(-0.4)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) {
                            startRename()
                        }
                }

                Text(Self.dateFormatter.string(from: note.date))
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.jotHover, value: isHovered)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isActiveNote {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .light ? Color.white : Color(red: 0.047, green: 0.039, blue: 0.035))
                } else if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color("SurfaceTranslucentColor"))
                }
            }
            .shadow(color: isActiveNote ? .black.opacity(0.06) : .clear, radius: 3, x: 0, y: 1)
            .shadow(color: isActiveNote ? .black.opacity(0.03) : .clear, radius: 1, x: 0, y: 0)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .draggable(
            TransferablePayload(items: getDragItems?() ?? [NoteDragItem(noteID: note.id)])
        ) {
            HStack(spacing: 8) {
                Text(note.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(Self.dateFormatter.string(from: note.date))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .contextMenu {
            if note.folderID == nil {
                Button {
                    HapticManager.shared.buttonTap()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onTogglePin(!note.isPinned)
                    }
                } label: {
                    Label {
                        Text(note.isPinned ? "Unpin Note" : "Pin Note")
                    } icon: {
                        Image(note.isPinned ? "IconUnpin" : "IconThumbtack")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
            }

            Button {
                HapticManager.shared.buttonTap()
                onCreateFolderWithNote()
            } label: {
                Label {
                    Text("Create New Notebook With Note...")
                } icon: {
                    Image("IconFolderAddRight")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
            }

            Menu {
                if folders.isEmpty {
                    Button("No folders available") { }
                        .disabled(true)
                } else {
                    ForEach(folders, id: \.id) { folder in
                        Button {
                            HapticManager.shared.buttonTap()
                            onMoveToFolder(folder.id)
                        } label: {
                                                    if note.folderID == folder.id {
                                                        Label {
                                                            Text(folder.name)
                                                        } icon: {
                                                            Image(systemName: "checkmark")
                                                                .renderingMode(.template)
                                                                .resizable()
                                                                .scaledToFit()
                                                                .frame(width: 20, height: 20)
                                                        }
                                                    } else {                                Label {
                                    Text(folder.name)
                                } icon: {
                                    Image("IconFolder2")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                }
                            }
                        }
                    }
                }

                if note.folderID != nil {
                    Divider()

                    Button {
                        HapticManager.shared.buttonTap()
                        onMoveToFolder(nil)
                    } label: {
                        Label {
                            Text("Remove from Notebook")
                        } icon: {
                            Image("IconFolderOpen")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                    }
                }
            } label: {
                Label {
                    Text("Move to Notebook")
                } icon: {
                    Image("IconFolder2")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
            }

            Button {
                HapticManager.shared.buttonTap()
                onExport()
            } label: {
                Label {
                    Text("Export Note...")
                } icon: {
                    Image("export note")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
            }

            Divider()

            if let onArchive {
                Button {
                    HapticManager.shared.buttonTap()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onArchive()
                    }
                } label: {
                    Label {
                        Text(note.isArchived ? "Unarchive" : "Archive")
                    } icon: {
                        Image("IconArchive1")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
            }

            Button(role: .destructive) {
                HapticManager.shared.buttonTap()
                withAnimation(.easeInOut(duration: 0.25)) {
                    onDelete()
                }
            } label: {
                Label {
                    Text("Delete")
                } icon: {
                    Image("delete")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
            }
        }
    }

    private func startRename() {
        renamingTitle = note.title
        isRenaming = true
        isFieldFocused = true
    }

    private func commitRename() {
        let trimmed = renamingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRename?(trimmed)
        }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    private static func selectionInteractionFromCurrentEvent() -> NoteSelectionInteraction {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        if modifiers.contains(.shift) {
            return .shiftRange
        }
        if modifiers.contains(.command) {
            return .commandToggle
        }
        return .plain
    }
}

// Pinned Notes Section with Liquid Glass Capsule
struct PinnedNotesSection: View {
    let notes: [Note]
    var selectedNoteIDs: Set<UUID> = []
    var activeNoteID: UUID? = nil
    let folders: [Folder]
    let onNoteTap: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void
    var onArchiveNotes: ((Set<UUID>) -> Void)? = nil
    var onRenameNote: ((Note, String) -> Void)? = nil
    @Binding var isExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let containerShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    /// Saturated golden yellow -- the "folder color" equivalent for the pinned section.
    private static let pinnedBaseColor = Color(.sRGB, red: 0.98, green: 0.80, blue: 0.08, opacity: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 8) {
                Image("IconThumbtack")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 15, height: 15)
                    .foregroundColor(Color("PinnedIconColor"))

                Text("Pinned notes")
                    .font(FontManager.heading(size: 12, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))

                Circle()
                    .fill(Color("SecondaryTextColor"))
                    .frame(width: 2, height: 2)

                Text("\(notes.count)")
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))

                Spacer(minLength: 0)

                Image(isExpanded ? "IconChevronTopSmall" : "IconChevronDownSmall")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 15, height: 15)
                    .foregroundColor(Color("PinnedIconColor"))
            }
            .padding(4)
            .contentShape(Rectangle())
            .onTapGesture {
                HapticManager.shared.buttonTap()
                withAnimation(.jotSmoothFast) {
                    isExpanded.toggle()
                }
            }

            // Notes
            if isExpanded {
                ForEach(notes, id: \.id) { note in
                    NoteListCard(
                        note: note,
                        isSelected: selectedNoteIDs.contains(note.id),
                        isActiveNote: note.id == activeNoteID,
                        isInsideFolder: true,
                        onTap: { interaction in onNoteTap(note, interaction) },
                        onTogglePin: { shouldPin in
                            onTogglePinForNotes(contextSelection(for: note), shouldPin)
                        },
                        onDelete: { onDeleteNotes(contextSelection(for: note)) },
                        folders: folders,
                        onCreateFolderWithNote: { onCreateFolderWithNotes(contextSelection(for: note)) },
                        onMoveToFolder: { folderID in
                            onMoveNotesToFolder(contextSelection(for: note), folderID)
                        },
                        onExport: { onExportNotes(contextSelection(for: note)) },
                        onArchive: onArchiveNotes != nil ? { onArchiveNotes?(contextSelection(for: note)) } : nil,
                        onRename: { newTitle in
                            onRenameNote?(note, newTitle)
                        },
                        getDragItems: {
                            if selectedNoteIDs.contains(note.id) {
                                return selectedNoteIDs.map { NoteDragItem(noteID: $0) }
                            } else {
                                return [NoteDragItem(noteID: note.id)]
                            }
                        }
                    )
                }
            }
        }
        .padding(4)
        .background(
            containerShape
                .fill(Self.pinnedBaseColor.solidFolderTint(for: colorScheme))
        )
        .overlay(
            containerShape
                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(containerShape)
    }

    private func contextSelection(for note: Note) -> Set<UUID> {
        if selectedNoteIDs.count > 1, selectedNoteIDs.contains(note.id) {
            return selectedNoteIDs
        }
        return [note.id]
    }
}

// Pinned Note Chip with Liquid Glass
struct PinnedNoteChip: View {
    let note: Note
    var isSelected: Bool = false
    let folders: [Folder]
    let onTap: (NoteSelectionInteraction) -> Void
    let onUnpin: () -> Void
    let onDelete: () -> Void
    let onCreateFolderWithNote: () -> Void
    let onMoveToFolder: (UUID?) -> Void
    let onExport: () -> Void
    var onArchive: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap(Self.selectionInteractionFromCurrentEvent())
        } label: {
            Text(note.title)
                .font(FontManager.heading(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(.dragPreview, Capsule())
        .draggable(TransferablePayload(items: [NoteDragItem(noteID: note.id)])) {
            Text(note.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .contentShape(.dragPreview, Capsule())
        }
        .glassEffect(.regular.interactive(true), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color("BorderSubtleColor"), lineWidth: isSelected ? 1 : 0)
        )
        .contextMenu {
            Button {
                onUnpin()
            } label: {
                Label("Unpin Note", image: "IconUnpin")
            }

            Button {
                HapticManager.shared.buttonTap()
                onCreateFolderWithNote()
            } label: {
                Label("Create New Notebook With Note...", image: "IconFolderAddRight")
            }

            Menu {
                if folders.isEmpty {
                    Button("No folders available") { }
                        .disabled(true)
                } else {
                    ForEach(folders, id: \.id) { folder in
                        Button {
                            HapticManager.shared.buttonTap()
                            onMoveToFolder(folder.id)
                        } label: {
                            Label(folder.name, image: "IconFolder2")
                        }
                    }
                }

                if note.folderID != nil {
                    Divider()

                    Button {
                        HapticManager.shared.buttonTap()
                        onMoveToFolder(nil)
                    } label: {
                        Label("Remove from Notebook", image: "IconFolderOpen")
                    }
                }
            } label: {
                Label("Move to Notebook", image: "IconFolder2")
            }

            Button {
                HapticManager.shared.buttonTap()
                onExport()
            } label: {
                Label("Export Note...", image: "export note")
            }

            Divider()

            if let onArchive {
                Button {
                    HapticManager.shared.buttonTap()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onArchive()
                    }
                } label: {
                    Label("Archive", image: "IconArchive1")
                }
            }

            Button(role: .destructive) {
                HapticManager.shared.buttonTap()
                withAnimation(.easeInOut(duration: 0.25)) {
                    onDelete()
                }
            } label: {
                Label("Delete", image: "delete")
            }
        }
    }

    private static func selectionInteractionFromCurrentEvent() -> NoteSelectionInteraction {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        if modifiers.contains(.shift) {
            return .shiftRange
        }
        if modifiers.contains(.command) {
            return .commandToggle
        }
        return .plain
    }
}

// FlowLayout for wrapping pinned notes
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(try! SimpleSwiftDataManager())
        .environmentObject(ThemeManager())
}
