//
//  ContentView.swift
//  Noty
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    // Search is powered by SearchEngine
    @StateObject private var searchEngine = SearchEngine()
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    @State private var selectedNote: Note?
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?
    @State private var isSidebarVisible = true
    @State private var isSearchActive = false
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var showAllNotesFolderIDs: Set<UUID> = []
    @State private var sidebarWidth: CGFloat = 360
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var detailFocusRequestID = UUID()
    @State private var hasAppliedInitialLaunchSelection = false
    @State private var isAutoCreatingStarterNote = false

    @State private var isCreateFolderAlertPresented = false
    @State private var newFolderName = ""
    @State private var pendingFolderCreationIntent: FolderCreationIntent = .standalone
    @State private var isRenameFolderAlertPresented = false
    @State private var renameFolderName = ""
    @State private var pendingFolderToRename: Folder?

    @State private var isBatchDeleteConfirmationPresented = false
    @State private var pendingDeleteNoteIDs: Set<UUID> = []
    @State private var isBatchMoveAlertPresented = false
    @State private var pendingMoveNoteIDs: Set<UUID> = []
    @State private var batchMoveFolderName = ""
    @State private var isBatchExportSheetPresented = false
    @State private var notesPendingExport: [Note] = []

    @Environment(\.colorScheme) private var colorScheme

    // Window corner radius from NotyApp containerShape
    private let windowCornerRadius: CGFloat = 16
    private let sidebarSectionSpacing: CGFloat = 36
    private let sidebarToggleToContentSpacing: CGFloat = 12
    private let sidebarMinWidth: CGFloat = 320
    private let sidebarMaxWidth: CGFloat = 560
    private let minimumDetailWidth: CGFloat = 520
    private let sidebarResizeHandleWidth: CGFloat = 24
    private let sidebarVisibilityAnimation = Animation.easeInOut(duration: 0.2)
    private let folderToLooseNotesSpacing: CGFloat = 16
    private let detailToggleLeadingInset: CGFloat = 42
    private let detailToggleToContentExtraSpacingWhenSidebarHidden: CGFloat = 16
    private let sidebarToggleIconHeight: CGFloat = 24
    private var detailOuterCornerRadius: CGFloat {
        windowCornerRadius
    }
    #if os(macOS)
    private let macOSTitlebarContentInset: CGFloat = 32
    #else
    private let macOSTitlebarContentInset: CGFloat = 0
    #endif
    private var detailToggleTopInset: CGFloat {
        macOSTitlebarContentInset + 8
    }
    private var sidebarScrollTopPadding: CGFloat {
        (pinnedNotes.isEmpty ? 24 : 18) + macOSTitlebarContentInset
    }
    private var sidebarResizeHandleTopInset: CGFloat {
        sidebarScrollTopPadding + sidebarToggleIconHeight + sidebarToggleToContentSpacing
    }

    private enum FolderCreationIntent {
        case standalone
        case withNotes(Set<UUID>)
    }

    var body: some View {
        GeometryReader { geometry in
            let resolvedSidebarWidth = clampedSidebarWidth(sidebarWidth, totalWidth: geometry.size.width)
            HStack(spacing: 0) {
                if isSidebarVisible {
                    sidebarContent(containerWidth: geometry.size.width)
                        .frame(width: selectedNote == nil ? geometry.size.width : resolvedSidebarWidth)
                        .clipped()
                        .overlay(alignment: .trailing) {
                            if selectedNote != nil {
                                sidebarResizeHandle(totalWidth: geometry.size.width)
                                    .padding(.top, sidebarResizeHandleTopInset)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .offset(x: sidebarResizeHandleWidth / 2)
                                    .zIndex(1)
                            }
                        }
                }

                if let note = selectedNote {
                    detailPane(note: note)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(colorScheme == .dark ? Color.black : Color.white)
                        .if(isSidebarVisible) { view in
                            view.clipShape(
                                UnevenRoundedRectangle(
                                    cornerRadii: .init(
                                        topLeading: 0,
                                        bottomLeading: 0,
                                        bottomTrailing: detailOuterCornerRadius,
                                        topTrailing: detailOuterCornerRadius
                                    ),
                                    style: .continuous
                                )
                            )
                        }
                        .if(!isSidebarVisible) { view in
                            view.clipShape(
                                RoundedRectangle(cornerRadius: detailOuterCornerRadius, style: .continuous)
                            )
                        }
                        .frame(
                            width: isSidebarVisible
                                ? max(0, geometry.size.width - resolvedSidebarWidth)
                                : geometry.size.width
                        )
                }
            }
            .animation(sidebarVisibilityAnimation, value: isSidebarVisible)
        }
        .background(AppWindowBackground())
        .onAppear {
            searchEngine.setNotes(notesManager.notes)
            reconcileSelectionWithCurrentNotes()
        }
        .onChange(of: notesManager.notes) { notes in
            searchEngine.setNotes(notes)
            reconcileSelectionWithCurrentNotes(notes)
        }
        .onChange(of: notesManager.hasLoadedInitialNotes) { _, _ in
            reconcileSelectionWithCurrentNotes()
        }
        .onChange(of: notesManager.hasCompletedMigrationCheck) { _, _ in
            reconcileSelectionWithCurrentNotes()
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
        .sheet(isPresented: $isBatchExportSheetPresented) {
            ExportFormatSheet(isPresented: $isBatchExportSheetPresented, notes: notesPendingExport) {
                exportNotes,
                format in
                Task { @MainActor in
                    let success: Bool

                    if exportNotes.count == 1, let singleNote = exportNotes.first {
                        success = await NoteExportService.shared.exportNote(singleNote, format: format)
                    } else {
                        let filename = "Noty Export \(Date().formatted(date: .numeric, time: .omitted))"
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
        .alert("Create New Folder", isPresented: $isCreateFolderAlertPresented) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                resetPendingFolderCreation()
            }
            Button("Create") {
                confirmCreateFolder()
            }
        } message: {
            Text("Enter a name for your folder.")
        }
        .alert("Rename Folder", isPresented: $isRenameFolderAlertPresented) {
            TextField("Folder name", text: $renameFolderName)
            Button("Cancel", role: .cancel) {
                pendingFolderToRename = nil
            }
            Button("Save") {
                confirmRenameFolder()
            }
        } message: {
            Text("Update the folder name.")
        }
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
            TextField("Folder name", text: $batchMoveFolderName)
            Button("Cancel", role: .cancel) {
                resetPendingMoveSelection()
            }
            Button("Move") {
                confirmMoveSelectedNotesByName()
            }
        } message: {
            Text("Enter a folder name. If it does not exist, it will be created.")
        }
#if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
#endif
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
    private func sidebarContent(containerWidth: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: sidebarSectionSpacing) {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(sidebarVisibilityAnimation) {
                                    isSidebarVisible = false
                                }
                            } label: {
                                Image(systemName: "sidebar.left")
                                    .font(FontManager.heading(size: 15, weight: .semibold))
                                    .foregroundColor(Color("SecondaryTextColor"))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .macPointingHandCursor()
                            .disabled(selectedNote == nil)
                            .opacity(selectedNote == nil ? 0.5 : 1)
                        }
                        .padding(.bottom, -(sidebarSectionSpacing - sidebarToggleToContentSpacing))

                        if !pinnedNotes.isEmpty {
                            PinnedNotesSection(
                                notes: pinnedNotes,
                                selectedNoteIDs: selectedNoteIDs,
                                folders: folders,
                                onNoteTap: handleNoteTap,
                                onDeleteNotes: requestDeleteNotes,
                                onCreateFolderWithNotes: { noteIDs in
                                    promptCreateFolder(withNoteIDs: noteIDs)
                                },
                                onMoveNotesToFolder: moveNotesToFolder,
                                onTogglePinForNotes: setPinState,
                                onExportNotes: presentExport
                            )
                        }

                        if !folders.isEmpty {
                            FolderSection(
                                folders: folders,
                                notesByFolder: notesByFolderID,
                                selectedNoteIDs: selectedNoteIDs,
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
                                onCreateNoteInFolder: { folderID in
                                    createAndOpenNewNote(inFolder: folderID)
                                },
                                onRenameFolder: promptRenameFolder,
                                onDeleteFolder: deleteFolder,
                                onDropNoteIntoFolder: { noteID, folderID in
                                    moveNote(noteID: noteID, toFolderID: folderID)
                                }
                            )
                            .padding(
                                .bottom,
                                hasLooseNotesSection
                                    ? -(sidebarSectionSpacing - folderToLooseNotesSpacing)
                                    : 0
                            )
                        }

                        if !todayNotes.isEmpty {
                            NotesSection(
                                title: "TODAY",
                                notes: todayNotes,
                                selectedNoteIDs: selectedNoteIDs,
                                folders: folders,
                                onNoteTap: handleNoteTap,
                                onDeleteNotes: requestDeleteNotes,
                                onCreateFolderWithNotes: { noteIDs in
                                    promptCreateFolder(withNoteIDs: noteIDs)
                                },
                                onMoveNotesToFolder: moveNotesToFolder,
                                onTogglePinForNotes: setPinState,
                                onExportNotes: presentExport,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }

                        if !thisMonthNotes.isEmpty {
                            NotesSection(
                                title: "THIS MONTH",
                                notes: thisMonthNotes,
                                selectedNoteIDs: selectedNoteIDs,
                                folders: folders,
                                onNoteTap: handleNoteTap,
                                onDeleteNotes: requestDeleteNotes,
                                onCreateFolderWithNotes: { noteIDs in
                                    promptCreateFolder(withNoteIDs: noteIDs)
                                },
                                onMoveNotesToFolder: moveNotesToFolder,
                                onTogglePinForNotes: setPinState,
                                onExportNotes: presentExport,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }

                        if !thisYearNotes.isEmpty {
                            NotesSection(
                                title: "THIS YEAR",
                                notes: thisYearNotes,
                                selectedNoteIDs: selectedNoteIDs,
                                folders: folders,
                                onNoteTap: handleNoteTap,
                                onDeleteNotes: requestDeleteNotes,
                                onCreateFolderWithNotes: { noteIDs in
                                    promptCreateFolder(withNoteIDs: noteIDs)
                                },
                                onMoveNotesToFolder: moveNotesToFolder,
                                onTogglePinForNotes: setPinState,
                                onExportNotes: presentExport,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }

                        if !olderNotes.isEmpty {
                            NotesSection(
                                title: "OLDER",
                                notes: olderNotes,
                                selectedNoteIDs: selectedNoteIDs,
                                folders: folders,
                                onNoteTap: handleNoteTap,
                                onDeleteNotes: requestDeleteNotes,
                                onCreateFolderWithNotes: { noteIDs in
                                    promptCreateFolder(withNoteIDs: noteIDs)
                                },
                                onMoveNotesToFolder: moveNotesToFolder,
                                onTogglePinForNotes: setPinState,
                                onExportNotes: presentExport,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }

                        if !hasVisibleUnfiledSections && !displayedNotes.isEmpty {
                            NotesSection(
                                title: "UNFILED",
                                notes: [],
                                selectedNoteIDs: selectedNoteIDs,
                                folders: folders,
                                onNoteTap: handleNoteTap,
                                onDeleteNotes: requestDeleteNotes,
                                onCreateFolderWithNotes: { noteIDs in
                                    promptCreateFolder(withNoteIDs: noteIDs)
                                },
                                onMoveNotesToFolder: moveNotesToFolder,
                                onTogglePinForNotes: setPinState,
                                onExportNotes: presentExport,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }
                    }
                    #if os(iOS)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    #else
                    .frame(maxWidth: 400)
                    .padding(.horizontal, selectedNote == nil ? 30 : 12)
                    #endif
                    .padding(.top, sidebarScrollTopPadding)
                    .padding(.bottom, 80)
                }
                .scrollIndicators(.never)
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    HapticManager.shared.buttonTap()
                    promptCreateFolder()
                } label: {
                    Label("Create New Folder...", systemImage: "folder.badge.plus")
                }
            }
            .onTapGesture {
                if isSearchActive {
                    searchEngine.query = ""
                    isSearchActive = false
                }
            }

            BottomBar(onNewNote: createAndOpenNewNote)
                .environmentObject(themeManager)
                .onTapGesture {
                    if isSearchActive {
                        searchEngine.query = ""
                        isSearchActive = false
                    }
                }

            FloatingSearch(
                engine: searchEngine,
                onNoteSelected: { note in
                    openNote(note)
                },
                maxExpandedWidth: selectedNote != nil
                    ? containerWidth * 0.2 - 36
                    : 300
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 18)
            .padding(.bottom, 18)
            .onChange(of: searchEngine.query) { _, newValue in
                isSearchActive = !newValue.isEmpty
            }
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
        .id(note.id)
        .overlay(alignment: .topLeading) {
            if !isSidebarVisible {
                Button {
                    withAnimation(sidebarVisibilityAnimation) {
                        isSidebarVisible = true
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(FontManager.heading(size: 15, weight: .semibold))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .padding(.leading, detailToggleLeadingInset)
                .padding(.top, detailToggleTopInset)
            }
        }
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
        let note = notesManager.addNote(title: "New Note", content: "", folderID: folderID)

        if let folderID {
            expandedFolderIDs.insert(folderID)
        }

        if animated {
            withAnimation(.notySpring) {
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
            guard note.folderID == nil else { continue }
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
        newFolderName = "New Folder"
        if let noteIDs, !noteIDs.isEmpty {
            pendingFolderCreationIntent = .withNotes(noteIDs)
        } else {
            pendingFolderCreationIntent = .standalone
        }
        isCreateFolderAlertPresented = true
    }

    private func confirmCreateFolder() {
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        HapticManager.shared.buttonTap()

        switch pendingFolderCreationIntent {
        case .standalone:
            if let folder = notesManager.createFolder(name: trimmedName) {
                expandedFolderIDs.insert(folder.id)
            }
        case let .withNotes(noteIDs):
            guard let folder = notesManager.createFolder(name: trimmedName) else {
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
        newFolderName = ""
    }

    private func promptRenameFolder(_ folder: Folder) {
        renameFolderName = folder.name
        pendingFolderToRename = folder
        isRenameFolderAlertPresented = true
    }

    private func confirmRenameFolder() {
        let trimmedName = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let folder = pendingFolderToRename else { return }

        HapticManager.shared.buttonTap()
        notesManager.renameFolder(id: folder.id, name: trimmedName)
        pendingFolderToRename = nil
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

    private var notesByFolderID: [UUID: [Note]] {
        Dictionary(grouping: displayedNotes.filter { $0.folderID != nil }) { $0.folderID! }
            .mapValues { notes in
                notes.sorted { $0.date > $1.date }
            }
    }

    private var unfiledNotes: [Note] {
        displayedNotes.filter { $0.folderID == nil }
    }

    private var pinnedNotes: [Note] {
        unfiledNotes.filter { $0.isPinned }
    }

    private var todayNotes: [Note] {
        let today = Calendar.current.startOfDay(for: Date())
        return unfiledNotes.filter { note in
            !note.isPinned && Calendar.current.isDate(note.date, inSameDayAs: today)
        }
    }

    private var thisMonthNotes: [Note] {
        let today = Calendar.current.startOfDay(for: Date())
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())

        return unfiledNotes.filter { note in
            let noteMonth = calendar.component(.month, from: note.date)
            let noteYear = calendar.component(.year, from: note.date)
            let noteDay = calendar.startOfDay(for: note.date)

            return !note.isPinned &&
                   noteMonth == currentMonth &&
                   noteYear == currentYear &&
                   noteDay < today
        }
    }

    private var thisYearNotes: [Note] {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())

        return unfiledNotes.filter { note in
            let noteMonth = calendar.component(.month, from: note.date)
            let noteYear = calendar.component(.year, from: note.date)

            return !note.isPinned &&
                   noteYear == currentYear &&
                   noteMonth < currentMonth
        }
    }

    private var olderNotes: [Note] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        return unfiledNotes.filter { note in
            let noteYear = calendar.component(.year, from: note.date)
            return !note.isPinned && noteYear < currentYear
        }
    }

    private var hasVisibleUnfiledSections: Bool {
        !todayNotes.isEmpty || !thisMonthNotes.isEmpty || !thisYearNotes.isEmpty || !olderNotes.isEmpty
    }

    private var hasLooseNotesSection: Bool {
        hasVisibleUnfiledSections || (!hasVisibleUnfiledSections && !displayedNotes.isEmpty)
    }

    private var visibleSidebarNotesInOrder: [Note] {
        var ordered: [Note] = []

        ordered.append(contentsOf: pinnedNotes)

        for folder in folders where expandedFolderIDs.contains(folder.id) {
            ordered.append(contentsOf: visibleFolderNotes(for: folder.id))
        }

        ordered.append(contentsOf: todayNotes)
        ordered.append(contentsOf: thisMonthNotes)
        ordered.append(contentsOf: thisYearNotes)
        ordered.append(contentsOf: olderNotes)

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
    let folders: [Folder]
    let onNoteTap: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void
    var onDropNoteToUnfiled: ((UUID) -> Bool)? = nil

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Section header - using SF Pro Compact for headings
            Text(title)
                .font(FontManager.heading(size: 9, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .kerning(0)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color("SurfaceTranslucentColor"))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)

            // Notes list
            ForEach(notes, id: \.id) { note in
                NoteListCard(
                    note: note,
                    isSelected: selectedNoteIDs.contains(note.id),
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
                    onExport: { onExportNotes(contextSelection(for: note)) }
                )
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargeted ? Color("HoverBackgroundColor").opacity(0.55) : Color.clear)
        )
        .if(onDropNoteToUnfiled != nil) { view in
            view.dropDestination(for: NoteDragItem.self) { items, _ in
                guard let payload = items.first,
                      let onDropNoteToUnfiled else {
                    return false
                }
                return onDropNoteToUnfiled(payload.noteID)
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
    let onTap: (NoteSelectionInteraction) -> Void
    let onTogglePin: (Bool) -> Void
    let onDelete: () -> Void
    let folders: [Folder]
    let onCreateFolderWithNote: () -> Void
    let onMoveToFolder: (UUID?) -> Void
    let onExport: () -> Void

    var body: some View {
        Button {
            onTap(Self.selectionInteractionFromCurrentEvent())
        } label: {
            HStack(spacing: 8) {
                // Title - using SF Pro Compact for note names
                // Left-aligned title that takes available space
                Text(note.title)
                    .font(FontManager.heading(size: 16, weight: .medium))
                    .foregroundColor(Color.primary)
                    .kerning(0)
                    .lineSpacing(4)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Date - positioned on the right in numeric format (MM.DD.YY)
                // Uses SF Mono for metadata with subdued color for visual hierarchy
                Text(Self.dateFormatter.string(from: note.date))
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .kerning(-0.25)
                    .frame(alignment: .center)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color("SurfaceTranslucentColor") : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .draggable(NoteDragItem(noteID: note.id))
        .contextMenu {
            if note.folderID == nil {
                Button {
                    HapticManager.shared.buttonTap()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onTogglePin(!note.isPinned)
                    }
                } label: {
                    Label(
                        note.isPinned ? "Unpin Note" : "Pin Note",
                        systemImage: note.isPinned ? "pin.slash" : "pin"
                    )
                }
            }

            Button {
                HapticManager.shared.buttonTap()
                onCreateFolderWithNote()
            } label: {
                Label("Create New Folder With Note...", systemImage: "folder.badge.plus")
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
                            Label(
                                folder.name,
                                systemImage: note.folderID == folder.id ? "checkmark" : "folder"
                            )
                        }
                    }
                }

                if note.folderID != nil {
                    Divider()

                    Button {
                        HapticManager.shared.buttonTap()
                        onMoveToFolder(nil)
                    } label: {
                        Label("Remove from Folder", systemImage: "tray.and.arrow.down")
                    }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }

            Button {
                HapticManager.shared.buttonTap()
                onExport()
            } label: {
                Label("Export Note...", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button("Delete", role: .destructive) {
                HapticManager.shared.buttonTap()
                withAnimation(.easeInOut(duration: 0.25)) {
                    onDelete()
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yy"
        return f
    }()

    private static func selectionInteractionFromCurrentEvent() -> NoteSelectionInteraction {
        #if os(macOS)
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        if modifiers.contains(.shift) {
            return .shiftRange
        }
        if modifiers.contains(.command) {
            return .commandToggle
        }
        #endif
        return .plain
    }
}

// Pinned Notes Section with Liquid Glass Capsule
struct PinnedNotesSection: View {
    let notes: [Note]
    var selectedNoteIDs: Set<UUID> = []
    let folders: [Folder]
    let onNoteTap: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section header - using SF Pro Compact for headings
            Text("PINNED")
                .font(FontManager.heading(size: 9, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .kerning(0)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color("SurfaceTranslucentColor"))
                )
                .frame(maxWidth: .infinity, alignment: .leading)

            // Pinned notes chips
            FlowLayout(spacing: 8) {
                ForEach(notes) { note in
                    PinnedNoteChip(
                        note: note,
                        isSelected: selectedNoteIDs.contains(note.id),
                        folders: folders,
                        onTap: { interaction in onNoteTap(note, interaction) },
                        onUnpin: {
                            HapticManager.shared.buttonTap()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                onTogglePinForNotes(contextSelection(for: note), false)
                            }
                        },
                        onDelete: { onDeleteNotes(contextSelection(for: note)) },
                        onCreateFolderWithNote: {
                            onCreateFolderWithNotes(contextSelection(for: note))
                        },
                        onMoveToFolder: { folderID in
                            onMoveNotesToFolder(contextSelection(for: note), folderID)
                        },
                        onExport: { onExportNotes(contextSelection(for: note)) }
                    )
                }
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
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
        .draggable(NoteDragItem(noteID: note.id))
        #if os(macOS)
        .glassEffect(.regular.interactive(true), in: Capsule())
        #else
        .background(.ultraThinMaterial, in: Capsule())
        #endif
        .overlay(
            Capsule()
                .strokeBorder(Color("BorderSubtleColor"), lineWidth: isSelected ? 1 : 0)
        )
        .contextMenu {
            Button {
                onUnpin()
            } label: {
                Label("Unpin Note", systemImage: "pin.slash")
            }

            Button {
                HapticManager.shared.buttonTap()
                onCreateFolderWithNote()
            } label: {
                Label("Create New Folder With Note...", systemImage: "folder.badge.plus")
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
                            Label(folder.name, systemImage: "folder")
                        }
                    }
                }

                if note.folderID != nil {
                    Divider()

                    Button {
                        HapticManager.shared.buttonTap()
                        onMoveToFolder(nil)
                    } label: {
                        Label("Remove from Folder", systemImage: "tray.and.arrow.down")
                    }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }

            Button {
                HapticManager.shared.buttonTap()
                onExport()
            } label: {
                Label("Export Note...", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button("Delete", role: .destructive) {
                HapticManager.shared.buttonTap()
                withAnimation(.easeInOut(duration: 0.25)) {
                    onDelete()
                }
            }
        }
    }

    private static func selectionInteractionFromCurrentEvent() -> NoteSelectionInteraction {
        #if os(macOS)
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        if modifiers.contains(.shift) {
            return .shiftRange
        }
        if modifiers.contains(.command) {
            return .commandToggle
        }
        #endif
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
