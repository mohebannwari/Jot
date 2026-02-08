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
        case .folders: return "Folders"
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
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var showAllNotesFolderIDs: Set<UUID> = []
    @State private var sidebarSectionFilter: SidebarSectionFilter = .all
    @State private var sidebarWidth: CGFloat = 295
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var detailFocusRequestID = UUID()
    @State private var hasAppliedInitialLaunchSelection = false
    @State private var isAutoCreatingStarterNote = false
    @State private var aiToolsState: AIToolsState = .collapsed

    @State private var isCreateFolderAlertPresented = false
    @State private var pendingFolderCreationIntent: FolderCreationIntent = .standalone
    @State private var pendingFolderToEdit: Folder?

    @State private var isBatchDeleteConfirmationPresented = false
    @State private var pendingDeleteNoteIDs: Set<UUID> = []
    @State private var isBatchMoveAlertPresented = false
    @State private var pendingMoveNoteIDs: Set<UUID> = []
    @State private var batchMoveFolderName = ""
    @State private var isBatchExportSheetPresented = false
    @State private var notesPendingExport: [Note] = []
    @State private var isShowingArchive = false
    @State private var hoveredSidebarMenuLabel: String?
    #if os(macOS)
    @State private var trafficLightMetrics = TrafficLightMetrics.fallback
    #endif

    @Environment(\.colorScheme) private var colorScheme

    // Window corner radius from NotyApp containerShape
    private let windowCornerRadius: CGFloat = 16
    private let windowContentPadding: CGFloat = 8
    private let sidebarDesignColumnWidth: CGFloat = 295
    private let sidebarMenuTop: CGFloat = 45
    private let sidebarNotesTop: CGFloat = 161
    private let sidebarSectionSpacing: CGFloat = 22
    private let sidebarChromeSpacing: CGFloat = 12
    private let sidebarMinWidth: CGFloat = 295
    private let sidebarMaxWidth: CGFloat = 560
    private let minimumDetailWidth: CGFloat = 520
    private let sidebarResizeHandleWidth: CGFloat = 24
    private let sidebarVisibilityAnimation = Animation.interactiveSpring(
        response: 0.28,
        dampingFraction: 0.86,
        blendDuration: 0.15
    )
    private let detailToggleToContentExtraSpacingWhenSidebarHidden: CGFloat = 16
    private let sidebarIconSize: CGFloat = 18
    private let sidebarTopIconSpacingCollapsed: CGFloat = 8
    private let sidebarTopBarButtonSize: CGFloat = 20
    private let sidebarTopBarTrafficLightGap: CGFloat = 12
    private let sidebarRowHoverInset: CGFloat = 0
    private var sidebarItemLeadingPadding: CGFloat {
        max(0, 18 - windowContentPadding)
    }
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
    #if os(macOS)
    /// Icon leading derived from the actual traffic light zoom button position.
    private var iconLeading: CGFloat { trafficLightMetrics.iconLeading }
    /// Icon top derived from the actual traffic light zoom button position.
    private var iconTop: CGFloat { trafficLightMetrics.iconTop }
    #else
    private let iconLeading: CGFloat = 78
    private let iconTop: CGFloat = 4
    #endif

    private enum FolderCreationIntent {
        case standalone
        case withNotes(Set<UUID>)
    }

    var body: some View {
        GeometryReader { geometry in
            let effectivePadding: CGFloat = isSidebarVisible ? windowContentPadding : 0
            let availableWidth = geometry.size.width - (effectivePadding * 2)
            let sidebarDetailGap: CGFloat = isSidebarVisible ? 10 : 0
            let resolvedSidebarWidth = clampedSidebarWidth(sidebarWidth, totalWidth: availableWidth)
            let expandedSidebarWidth = selectedNote == nil ? availableWidth : resolvedSidebarWidth
            let visibleSidebarWidth = isSidebarVisible ? expandedSidebarWidth : 0
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
                                    .fill(colorScheme == .dark ? Color(red: 0.16, green: 0.14, blue: 0.14) : Color(red: 0.906, green: 0.898, blue: 0.894))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: detailCornerRadius, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                AIToolsOverlay(state: $aiToolsState)
                                    .padding(.trailing, 18)
                                    .padding(.bottom, 18)
                            }
                            .padding(.leading, sidebarDetailGap)
                    }
                }

                appCenteredSearchOverlay()
                    .zIndex(3)
            }
            .padding(effectivePadding)
            .animation(sidebarVisibilityAnimation, value: isSidebarVisible)
#if os(macOS)
            .overlay(alignment: .topLeading) {
                if !isSidebarVisible {
                    collapsedTopBarRow
                }
            }
            .overlay(alignment: .topLeading) {
                globalSearchShortcutActivator
            }
#endif
        }
        .background {
            ZStack {
                #if os(macOS)
                BackdropBlurView(material: .hudWindow, blendingMode: .behindWindow)
                #else
                BackdropBlurView(style: .systemUltraThinMaterial)
                #endif
                Color("BackgroundColor")
            }
            .ignoresSafeArea()
        }
        #if os(macOS)
        .background(
            TrafficLightAligner(
                metrics: $trafficLightMetrics,
                gap: sidebarTopBarTrafficLightGap,
                iconHeight: sidebarTopBarButtonSize
            )
        )
        #endif
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
        .onChange(of: isShowingArchive) { _, showing in
            if showing {
                notesManager.loadArchivedNotes()
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
        .sheet(isPresented: $isCreateFolderAlertPresented) {
            CreateFolderSheet(
                onCreate: { name, colorHex in
                    confirmCreateFolder(name: name, colorHex: colorHex)
                    isCreateFolderAlertPresented = false
                },
                onCancel: {
                    resetPendingFolderCreation()
                    isCreateFolderAlertPresented = false
                }
            )
            .presentationDetents([.height(340)])
            .presentationBackground(.clear)
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $pendingFolderToEdit) { folder in
            CreateFolderSheet(
                onCreate: { name, colorHex in
                    confirmEditFolder(name: name, colorHex: colorHex)
                    pendingFolderToEdit = nil
                },
                onCancel: {
                    pendingFolderToEdit = nil
                },
                editingFolder: folder
            )
            .presentationDetents([.height(340)])
            .presentationBackground(.clear)
            .presentationDragIndicator(.hidden)
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
    private func sidebarContent() -> some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                #if os(macOS)
                BackdropBlurView(material: .hudWindow, blendingMode: .behindWindow)
                #else
                BackdropBlurView(style: .systemUltraThinMaterial)
                #endif
                Color("BackgroundColor")
            }

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
                    if isShowingArchive {
                        sidebarArchiveList
                    } else {
                    VStack(spacing: sidebarSectionSpacing) {
                        if shouldShowPinnedSection {
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
                                onExportNotes: presentExport,
                                onArchiveNotes: archiveNotes
                            )
                        }

                        if shouldShowFoldersSection {
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
                                onArchiveNotes: archiveNotes,
                                onCreateNoteInFolder: { folderID in
                                    createAndOpenNewNote(inFolder: folderID)
                                },
                                onRenameFolder: promptEditFolder,
                                onDeleteFolder: deleteFolder,
                                onDropNoteIntoFolder: { noteID, folderID in
                                    moveNote(noteID: noteID, toFolderID: folderID)
                                }
                            )
                        }

                        if shouldShowTodaySection {
                            NotesSection(
                                title: "Today",
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
                                onArchiveNotes: archiveNotes,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }

                        if shouldShowThisMonthSection {
                            NotesSection(
                                title: "This month",
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
                                onArchiveNotes: archiveNotes,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }

                        if shouldShowThisYearSection {
                            NotesSection(
                                title: "This year",
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
                                onArchiveNotes: archiveNotes,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }

                        if shouldShowOlderSection {
                            NotesSection(
                                title: "Older",
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
                                onArchiveNotes: archiveNotes,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }

                        if shouldShowUnfiledPlaceholderSection {
                            NotesSection(
                                title: "Unfiled",
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
                                onArchiveNotes: archiveNotes,
                                onDropNoteToUnfiled: { noteID in
                                    moveNote(noteID: noteID, toFolderID: nil)
                                }
                            )
                        }
                    }
                    .frame(width: sidebarDesignColumnWidth, alignment: .leading)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    } // end else (non-archive)
                }
                .scrollIndicators(.never)
            }
            .padding(.top, sidebarMenuTop)
            .frame(width: sidebarDesignColumnWidth, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    HapticManager.shared.buttonTap()
                    promptCreateFolder()
                } label: {
                    Label("Create New Folder...", image: "IconFolderAddRight")
                }
            }
            .onTapGesture {
                if isSearchPresented {
                    isSearchPresented = false
                }
            }

            // Settings -- pinned to bottom of sidebar
            VStack {
                Spacer()
                sidebarMenuItem(assetName: "IconSettingsGear1", label: "Settings") {
                    // No action yet - UI only
                }
            }
            .frame(width: sidebarDesignColumnWidth, alignment: .leading)
            .padding(.bottom, sidebarSettingsBottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            sidebarMenuItem(assetName: "IconArchive1", label: "Archive") {
                withAnimation(.notySpring) {
                    isShowingArchive.toggle()
                }
            }
        }
        .frame(width: sidebarDesignColumnWidth, alignment: .leading)
    }

    private func sidebarMenuItem(
        assetName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                sidebarAssetIcon(assetName: assetName, tint: Color("SecondaryTextColor"))

                Text(label)
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .tracking(-0.4)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, sidebarItemLeadingPadding)
            .padding(.trailing, sidebarItemTrailingPadding)
            .padding(.vertical, sidebarItemVPadding)
            .frame(height: sidebarMenuItemHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        hoveredSidebarMenuLabel == label
                            ? Color("HoverBackgroundColor").opacity(colorScheme == .dark ? 0.6 : 0.45)
                            : Color.clear
                    )
                    .padding(.horizontal, sidebarRowHoverInset)
            )
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
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

                Menu {
                    ForEach(SidebarSectionFilter.allCases) { filter in
                        Button {
                            sidebarSectionFilter = filter
                        } label: {
                            Label(
                                filter.label,
                                systemImage: sidebarSectionFilter == filter ? "checkmark" : "line.3.horizontal.decrease"
                            )
                        }
                    }
                } label: {
                    sidebarAssetIcon(assetName: "IconFilterCircle", tint: Color("SecondaryTextColor"))
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
            }
        }
        .padding(.leading, sidebarItemLeadingPadding)
        .padding(.trailing, sidebarItemTrailingPadding)
        .frame(width: sidebarDesignColumnWidth, alignment: .leading)
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
    }

    private var sidebarArchiveList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if notesManager.archivedNotes.isEmpty {
                Text("No archived notes")
                    .font(FontManager.metadata(size: 11, weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, sidebarItemLeadingPadding)
                    .padding(.trailing, sidebarItemTrailingPadding)
                    .padding(.top, 12)
            } else {
                ForEach(notesManager.archivedNotes, id: \.id) { note in
                    NoteListCard(
                        note: note,
                        isSelected: selectedNoteIDs.contains(note.id),
                        onTap: { interaction in handleNoteTap(note, interaction) },
                        onTogglePin: { _ in },
                        onDelete: { requestDeleteNotes([note.id]) },
                        folders: [],
                        onCreateFolderWithNote: { },
                        onMoveToFolder: { _ in },
                        onExport: { presentExport([note.id]) },
                        onArchive: { unarchiveNotes([note.id]) }
                    )
                }
            }
        }
        .frame(width: sidebarDesignColumnWidth, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .onAppear {
            notesManager.loadArchivedNotes()
        }
    }

    private func presentSearch() {
        withAnimation(sidebarVisibilityAnimation) {
            isSearchPresented = true
        }
    }

    @ViewBuilder
    private func appCenteredSearchOverlay() -> some View {
        ZStack {
            if isSearchPresented {
                Color.black.opacity(0.15)
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
                folders: folders
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 182)
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchPresented)
    }

#if os(macOS)
    private var globalSearchShortcutActivator: some View {
        Button(action: presentSearch) {
            Color.clear
                .frame(width: 1, height: 1)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: [.command])
        .accessibilityHidden(true)
        .opacity(0.001)
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

            sidebarTopBarIcon(assetName: "IconMagnifyingGlass") {
                presentSearch()
            }
        }
        .padding(.leading, iconLeading)
        .padding(.top, iconTop)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .zIndex(4)
    }
#endif

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
        isCreateFolderAlertPresented = true
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

    private func promptEditFolder(_ folder: Folder) {
        pendingFolderToEdit = folder
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
    let folders: [Folder]
    let onNoteTap: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void
    var onArchiveNotes: ((Set<UUID>) -> Void)? = nil
    var onDropNoteToUnfiled: ((UUID) -> Bool)? = nil

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FontManager.heading(size: 10, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.trailing, 8)

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
                    onExport: { onExportNotes(contextSelection(for: note)) },
                    onArchive: onArchiveNotes != nil ? { onArchiveNotes?(contextSelection(for: note)) } : nil
                )
            }
        }
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
    var leadingIconAssetName: String? = nil
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
    @State private var isHovered = false

    var body: some View {
        Button {
            onTap(Self.selectionInteractionFromCurrentEvent())
        } label: {
            HStack(spacing: 8) {
                if let icon = leadingIconAssetName {
                    let isLeadingIconVisible = !showLeadingIconOnHoverOnly || isHovered
                    Group {
                        if let onLeadingIconTap {
                            Image(icon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Color("SecondaryTextColor"))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onLeadingIconTap()
                                }
                                .macPointingHandCursor()
                            .opacity(isLeadingIconVisible ? 1 : 0)
                            .allowsHitTesting(isLeadingIconVisible)
                        } else {
                            Image(icon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Color("SecondaryTextColor"))
                                .frame(width: 18, height: 18)
                                .opacity(isLeadingIconVisible ? 1 : 0)
                        }
                    }
                    .animation(.easeInOut(duration: 0.12), value: isLeadingIconVisible)
                }

                Text(note.title)
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .tracking(-0.4)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(Self.dateFormatter.string(from: note.date))
                    .font(FontManager.heading(size: 10, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color("SurfaceTranslucentColor") : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
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
                        image: note.isPinned ? "IconUnpin" : "IconThumbtack"
                    )
                }
            }

            Button {
                HapticManager.shared.buttonTap()
                onCreateFolderWithNote()
            } label: {
                Label("Create New Folder With Note...", image: "IconFolderAddRight")
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
                                Label(folder.name, systemImage: "checkmark")
                            } else {
                                Label(folder.name, image: "IconFolder2")
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
                        Label("Remove from Folder", image: "IconFolderOpen")
                    }
                }
            } label: {
                Label("Move to Folder", image: "IconFolder2")
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
                    Label(note.isArchived ? "Unarchive" : "Archive", image: "IconArchive1")
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
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
    var onArchiveNotes: ((Set<UUID>) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(notes, id: \.id) { note in
                NoteListCard(
                    note: note,
                    isSelected: selectedNoteIDs.contains(note.id),
                    leadingIconAssetName: "IconThumbtack",
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
                    onArchive: onArchiveNotes != nil ? { onArchiveNotes?(contextSelection(for: note)) } : nil
                )
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
                Label("Unpin Note", image: "IconUnpin")
            }

            Button {
                HapticManager.shared.buttonTap()
                onCreateFolderWithNote()
            } label: {
                Label("Create New Folder With Note...", image: "IconFolderAddRight")
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
                        Label("Remove from Folder", image: "IconFolderOpen")
                    }
                }
            } label: {
                Label("Move to Folder", image: "IconFolder2")
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
