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

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredFolderID: UUID?
    @State private var dropTargetFolderID: UUID?
    @State private var renamingFolderID: UUID?
    @State private var renamingName: String = ""
    @FocusState private var isRenaming: Bool
    private let rowHoverHorizontalInset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(folders, id: \.id) { folder in
                let isExpanded = expandedFolderIDs.contains(folder.id)
                VStack(alignment: .leading, spacing: 4) {
                    folderRow(folder)

                    if isExpanded {
                        folderNotesList(folder)
                    }
                }
            }
        }
    }

    private func folderRow(_ folder: Folder) -> some View {
        let isExpanded = expandedFolderIDs.contains(folder.id)
        let isHovered = hoveredFolderID == folder.id
        let isDropTarget = dropTargetFolderID == folder.id
        let shouldShowActions = isHovered
        let isRenamingThisFolder = renamingFolderID == folder.id
        let noteCount = (notesByFolder[folder.id] ?? []).count
        let leadingAsset = noteCount == 0 ? "IconFolder1" : (isExpanded ? "IconFolderOpen" : "IconFolder1")

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
                    .tracking(-0.4)
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rowBackgroundColor(isDropTarget: isDropTarget, isHovered: isHovered))
                .padding(.horizontal, rowHoverHorizontalInset)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
