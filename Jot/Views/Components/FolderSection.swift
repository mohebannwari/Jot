//
//  FolderSection.swift
//  Jot
//

import SwiftUI

struct FolderSection: View {
    let folders: [Folder]
    let notesByFolder: [UUID: [Note]]
    var selectedNoteIDs: Set<UUID> = []
    var activeNoteID: UUID? = nil
    @Binding var expandedFolderIDs: Set<UUID>
    @Binding var showAllNotesFolderIDs: Set<UUID>
    let allFolders: [Folder]
    let onOpenNote: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void
    var onArchiveNotes: ((Set<UUID>) -> Void)? = nil
    let onCreateNoteInFolder: (UUID) -> Void
    let onRenameFolder: (Folder) -> Void
    var onCommitRenameFolder: ((Folder, String) -> Void)? = nil
    var onRenameNote: ((Note, String) -> Void)? = nil
    var onArchiveFolder: ((Folder) -> Void)? = nil
    let onDeleteFolder: (Folder) -> Void
    let onDropNotesIntoFolder: (Set<UUID>, UUID) -> Bool
    var splitNoteIDs: Set<UUID> = []
    var onSplitIconTap: ((Note) -> Void)? = nil
    var onToggleLockNote: ((UUID) -> Void)? = nil
    var onLockIconTap: ((Note) -> Void)? = nil
    var highlightedFolderID: UUID? = nil
    @Binding var isExpanded: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredFolderID: UUID?
    @State private var dropTargetFolderID: UUID?
    @State private var peekRevealedFolderID: UUID?
    @State private var renamingFolderID: UUID?
    @State private var renamingName: String = ""
    @FocusState private var isRenaming: Bool
    private let rowHoverHorizontalInset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accordion header
            HStack(spacing: 8) {
                Text("Folders")
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))

                Circle()
                    .fill(Color("SecondaryTextColor"))
                    .frame(width: 2, height: 2)

                Text("\(folders.count)")
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))

                Spacer(minLength: 0)

                Image(isExpanded ? "IconChevronTopSmall" : "IconChevronDownSmall")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 18, height: 18)
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                HapticManager.shared.buttonTap()
                withAnimation(.jotSmoothFast) {
                    isExpanded.toggle()
                }
            }

            // Folder rows
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(folders, id: \.id) { folder in
                        let isFolderExpanded = expandedFolderIDs.contains(folder.id)
                        VStack(alignment: .leading, spacing: 4) {
                            folderRow(folder)

                            if isFolderExpanded {
                                folderNotesList(folder)
                            } else if let peekNote = activeNoteInFolder(folder) {
                                NoteListCard(
                                    note: peekNote,
                                    isSelected: selectedNoteIDs.contains(peekNote.id),
                                    isActiveNote: peekNote.id == activeNoteID,
                                    activeIconTint: folder.folderColor,
                                    isInsideFolder: true,
                                    onTap: { interaction in onOpenNote(peekNote, interaction) },
                                    onTogglePin: { shouldPin in
                                        onTogglePinForNotes(contextSelection(for: peekNote), shouldPin)
                                    },
                                    onDelete: { onDeleteNotes(contextSelection(for: peekNote)) },
                                    folders: allFolders,
                                    onCreateFolderWithNote: {
                                        onCreateFolderWithNotes(contextSelection(for: peekNote))
                                    },
                                    onMoveToFolder: { folderID in
                                        onMoveNotesToFolder(contextSelection(for: peekNote), folderID)
                                    },
                                    onExport: { onExportNotes(contextSelection(for: peekNote)) },
                                    onArchive: onArchiveNotes != nil ? { onArchiveNotes?(contextSelection(for: peekNote)) } : nil,
                                    onToggleLock: onToggleLockNote != nil ? { onToggleLockNote?(peekNote.id) } : nil,
                                    onRename: { newTitle in
                                        onRenameNote?(peekNote, newTitle)
                                    },
                                    getDragItems: {
                                        if selectedNoteIDs.contains(peekNote.id) {
                                            return selectedNoteIDs.map { NoteDragItem(noteID: $0) }
                                        } else {
                                            return [NoteDragItem(noteID: peekNote.id)]
                                        }
                                    }
                                )
                                .padding(.leading, 26)
                                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                            }
                        }
                        .id(folder.id)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if let (peekFolder, peekNote) = activeFolderAndNote {
                VStack(alignment: .leading, spacing: 4) {
                    // Folder header — tap to expand accordion + folder
                    HStack(spacing: 8) {
                        Image("IconRedirectArrow")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color("SecondaryTextColor"))
                            .frame(width: 18, height: 18)

                        Image("IconFolder1")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(peekFolder.folderColor)
                            .frame(width: 18, height: 18)

                        Text(peekFolder.name)
                            .font(FontManager.heading(size: 15, weight: .medium))
                            .foregroundColor(Color("PrimaryTextColor"))
                            .tracking(-0.1)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Circle()
                            .fill(Color("SecondaryTextColor"))
                            .frame(width: 2, height: 2)

                        Text("\((notesByFolder[peekFolder.id] ?? []).count)")
                            .font(FontManager.metadata(size: 11, weight: .medium))
                            .foregroundColor(Color("SecondaryTextColor"))

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.shared.buttonTap()
                        withAnimation(.jotSmoothFast) {
                            peekRevealedFolderID = peekRevealedFolderID == peekFolder.id ? nil : peekFolder.id
                        }
                    }

                    if peekRevealedFolderID == peekFolder.id {
                        // All notes in this folder
                        folderNotesList(peekFolder)
                            .padding(.leading, 26)
                    } else {
                        // Active note only
                        NoteListCard(
                            note: peekNote,
                            isSelected: selectedNoteIDs.contains(peekNote.id),
                            isActiveNote: peekNote.id == activeNoteID,
                            activeIconTint: peekFolder.folderColor,
                            isInsideFolder: true,
                            onTap: { interaction in onOpenNote(peekNote, interaction) },
                            onTogglePin: { shouldPin in
                                onTogglePinForNotes(contextSelection(for: peekNote), shouldPin)
                            },
                            onDelete: { onDeleteNotes(contextSelection(for: peekNote)) },
                            folders: allFolders,
                            onCreateFolderWithNote: {
                                onCreateFolderWithNotes(contextSelection(for: peekNote))
                            },
                            onMoveToFolder: { folderID in
                                onMoveNotesToFolder(contextSelection(for: peekNote), folderID)
                            },
                            onExport: { onExportNotes(contextSelection(for: peekNote)) },
                            onArchive: onArchiveNotes != nil ? { onArchiveNotes?(contextSelection(for: peekNote)) } : nil,
                            onToggleLock: onToggleLockNote != nil ? { onToggleLockNote?(peekNote.id) } : nil,
                            onRename: { newTitle in
                                onRenameNote?(peekNote, newTitle)
                            },
                            getDragItems: {
                                if selectedNoteIDs.contains(peekNote.id) {
                                    return selectedNoteIDs.map { NoteDragItem(noteID: $0) }
                                } else {
                                    return [NoteDragItem(noteID: peekNote.id)]
                                }
                            }
                        )
                        .padding(.leading, 52)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                .onChange(of: activeNoteID) {
                    peekRevealedFolderID = nil
                }
            }
        }
    }

    private func folderRow(_ folder: Folder) -> some View {
        let isFolderOpen = expandedFolderIDs.contains(folder.id)
        let isHovered = hoveredFolderID == folder.id
        let isDropTarget = dropTargetFolderID == folder.id
        let shouldShowActions = isHovered
        let isRenamingThisFolder = renamingFolderID == folder.id
        let noteCount = (notesByFolder[folder.id] ?? []).count
        let leadingAsset = noteCount == 0 ? "IconFolder1" : (isFolderOpen ? "IconFolderOpen" : "IconFolder1")

        return HStack(spacing: 8) {
            Image(leadingAsset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(folder.folderColor)
                .frame(width: 18, height: 18)

            if isRenamingThisFolder {
                TextField("Folder Name", text: $renamingName)
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .textFieldStyle(.plain)
                    .focused($isRenaming)
                    .onSubmit {
                        commitRename(folder)
                    }
                    .onExitCommand {
                        cancelRename()
                    }
            } else {
                Text(folder.name)
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .tracking(-0.1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) {
                        startRename(folder)
                    }
            }

            if noteCount > 0 {
                Circle()
                    .fill(Color("SecondaryTextColor"))
                    .frame(width: 2, height: 2)
                Text("\(noteCount)")
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                Menu {
                    Button {
                        HapticManager.shared.buttonTap()
                        onRenameFolder(folder)
                    } label: {
                        Label {
                            Text("Edit Folder")
                        } icon: {
                            Image.menuIcon("rename note")
                        }
                    }

                    if let onArchiveFolder {
                        Button {
                            HapticManager.shared.buttonTap()
                            onArchiveFolder(folder)
                        } label: {
                            Label {
                                Text("Archive Folder")
                            } icon: {
                                Image.menuIcon("IconArchive1")
                            }
                        }
                    }

                    Button(role: .destructive) {
                        HapticManager.shared.buttonTap()
                        onDeleteFolder(folder)
                    } label: {
                        Label {
                            Text("Delete Folder")
                        } icon: {
                            Image.menuIcon("delete")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(FontManager.icon(size: 18, weight: .medium))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .subtleHoverScale(1.06)

                Button {
                    HapticManager.shared.buttonTap()
                    onCreateNoteInFolder(folder.id)
                } label: {
                    Image("IconNoteText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .subtleHoverScale(1.06)
            }
            .opacity(shouldShowActions ? 1 : 0)
            .allowsHitTesting(shouldShowActions)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            Capsule()
                .fill(rowBackgroundColor(isDropTarget: isDropTarget, isHovered: isHovered))
                .padding(.horizontal, rowHoverHorizontalInset)
        )
        .overlay {
            if highlightedFolderID == folder.id {
                FolderHighlightPulse(color: folder.folderColor)
                    .padding(.horizontal, rowHoverHorizontalInset)
            }
        }
        .contentShape(Capsule())
        .animation(.jotHover, value: isHovered)
        .onTapGesture {
            HapticManager.shared.buttonTap()
            withAnimation(.jotSmoothFast) {
                toggleFolderExpansion(folder.id)
            }
        }
        .onHover { hovering in
            if hovering {
                hoveredFolderID = folder.id
            } else if hoveredFolderID == folder.id {
                hoveredFolderID = nil
            }
        }
        .contextMenu {
            Button {
                HapticManager.shared.buttonTap()
                onRenameFolder(folder)
            } label: {
                Label {
                    Text("Edit Folder")
                } icon: {
                    Image.menuIcon("rename note")
                }
            }

            if let onArchiveFolder {
                Button {
                    HapticManager.shared.buttonTap()
                    onArchiveFolder(folder)
                } label: {
                    Label {
                        Text("Archive Folder")
                    } icon: {
                        Image.menuIcon("IconArchive1")
                    }
                }
            }

            Button(role: .destructive) {
                HapticManager.shared.buttonTap()
                onDeleteFolder(folder)
            } label: {
                Label {
                    Text("Delete Folder")
                } icon: {
                    Image.menuIcon("delete")
                }
            }
        }
        .dropDestination(for: TransferablePayload.self) { payloads, _ in
            let items = payloads.flatMap { $0.items }
            guard !items.isEmpty else { return false }
            let noteIDs = Set(items.map { $0.noteID })
            let success = onDropNotesIntoFolder(noteIDs, folder.id)
            if success {
                withAnimation(.jotSmoothFast) {
                    expandedFolderIDs.insert(folder.id)
                }
            }
            return success
        } isTargeted: { targeted in
            if targeted {
                dropTargetFolderID = folder.id
            } else if dropTargetFolderID == folder.id {
                dropTargetFolderID = nil
            }
        }
    }

    private func folderNotesList(_ folder: Folder) -> some View {
        let notes = notesByFolder[folder.id] ?? []
        let showsAll = showAllNotesFolderIDs.contains(folder.id)
        let shouldLimit = notes.count > 5 && !showsAll
        let visibleNotes = shouldLimit ? Array(notes.prefix(5)) : notes

        return Group {
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleNotes, id: \.id) { note in
                        NoteListCard(
                            note: note,
                            isSelected: selectedNoteIDs.contains(note.id),
                            isActiveNote: note.id == activeNoteID,
                            activeIconTint: folder.folderColor,
                            isInsideFolder: true,
                            leadingIconAssetName: note.isLocked
                                ? "IconLock"
                                : (splitNoteIDs.contains(note.id) ? "IconArrowSplitUp" : nil),
                            hoverLeadingIconAssetName: note.isLocked ? "IconUnlocked" : nil,
                            persistentLeadingIconBg: note.isLocked || splitNoteIDs.contains(note.id),
                            leadingIconBgColor: note.isLocked ? Color.red : .blue,
                            leadingIconFgColor: .white,
                            hoverLeadingIconBgColor: note.isLocked ? Color.green : nil,
                            hoverLeadingIconFgColor: nil,
                            onLeadingIconTap: note.isLocked
                                ? { onLockIconTap?(note) }
                                : (splitNoteIDs.contains(note.id) ? { onSplitIconTap?(note) } : nil),
                            onTap: { interaction in onOpenNote(note, interaction) },
                            onTogglePin: { shouldPin in
                                onTogglePinForNotes(contextSelection(for: note), shouldPin)
                            },
                            onDelete: { onDeleteNotes(contextSelection(for: note)) },
                            folders: allFolders,
                            onCreateFolderWithNote: {
                                onCreateFolderWithNotes(contextSelection(for: note))
                            },
                            onMoveToFolder: { folderID in
                                onMoveNotesToFolder(contextSelection(for: note), folderID)
                            },
                            onExport: { onExportNotes(contextSelection(for: note)) },
                            onArchive: onArchiveNotes != nil ? { onArchiveNotes?(contextSelection(for: note)) } : nil,
                            onToggleLock: onToggleLockNote != nil ? { onToggleLockNote?(note.id) } : nil,
                            onRename: { newTitle in
                                onRenameNote?(note, newTitle)
                            },
                            getDragItems: {
                                if selectedNoteIDs.contains(note.id) {
                                    return selectedNoteIDs.map { NoteDragItem(noteID: $0) }
                                } else {
                                    return [NoteDragItem(noteID: note.id)]
                                }
                            },
                        )
                    }

                    if notes.count > 5 {
                        Button {
                            withAnimation(.jotSpring) {
                                toggleShowAllNotes(for: folder.id)
                            }
                        } label: {
                            Text(showsAll ? "Show less" : "Show more")
                                .font(FontManager.metadata(size: 11, weight: .semibold))
                                .foregroundColor(Color("SecondaryTextColor"))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        .padding(.top, 2)
                        .subtleHoverScale(1.02)
                    }
                }
                .padding(.leading, 26)
            }
        }
    }

    private func activeNoteInFolder(_ folder: Folder) -> Note? {
        guard let activeID = activeNoteID else { return nil }
        return (notesByFolder[folder.id] ?? []).first { $0.id == activeID }
    }

    private var activeFolderAndNote: (Folder, Note)? {
        guard let activeID = activeNoteID else { return nil }
        for folder in folders {
            if let notes = notesByFolder[folder.id],
               let note = notes.first(where: { $0.id == activeID }) {
                return (folder, note)
            }
        }
        return nil
    }

    private func rowBackgroundColor(isDropTarget: Bool, isHovered: Bool) -> Color {
        if isDropTarget {
            return Color("SurfaceTranslucentColor")
        }
        if isHovered {
            return Color("HoverBackgroundColor")
        }
        return Color.clear
    }

    private func toggleFolderExpansion(_ folderID: UUID) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }

    private func toggleShowAllNotes(for folderID: UUID) {
        if showAllNotesFolderIDs.contains(folderID) {
            showAllNotesFolderIDs.remove(folderID)
        } else {
            showAllNotesFolderIDs.insert(folderID)
        }
    }

    private func contextSelection(for note: Note) -> Set<UUID> {
        if selectedNoteIDs.count > 1, selectedNoteIDs.contains(note.id) {
            return selectedNoteIDs
        }
        return [note.id]
    }

    private func startRename(_ folder: Folder) {
        renamingName = folder.name
        renamingFolderID = folder.id
        isRenaming = true
    }

    private func commitRename(_ folder: Folder) {
        let trimmed = renamingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onCommitRenameFolder?(folder, trimmed)
        }
        renamingFolderID = nil
        isRenaming = false
    }

    private func cancelRename() {
        renamingFolderID = nil
        isRenaming = false
    }
}

private struct FolderHighlightPulse: View {
    let color: Color
    @State private var trigger = false

    var body: some View {
        Capsule()
            .fill(color)
            .phaseAnimator(
                [0.0, 0.22, 0.0, 0.22, 0.0],
                trigger: trigger
            ) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.45)
            }
            .onAppear { trigger.toggle() }
    }
}
