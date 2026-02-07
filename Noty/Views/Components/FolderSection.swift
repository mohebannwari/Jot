//
//  FolderSection.swift
//  Noty
//

import SwiftUI

struct FolderSection: View {
    let folders: [Folder]
    let notesByFolder: [UUID: [Note]]
    var selectedNoteIDs: Set<UUID> = []
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
    let onDeleteFolder: (Folder) -> Void
    let onDropNoteIntoFolder: (UUID, UUID) -> Bool

    @State private var hoveredFolderID: UUID?
    @State private var dropTargetFolderID: UUID?
    private let rowHoverHorizontalInset: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(folders, id: \.id) { folder in
                VStack(alignment: .leading, spacing: 6) {
                    folderRow(folder)

                    if expandedFolderIDs.contains(folder.id) {
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
        let leadingAsset = isExpanded ? "IconFolderOpen" : "IconFolder2"

        return HStack(spacing: 8) {
            Image(leadingAsset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(folder.folderColor)
                .frame(width: 16, height: 16)

            Text(folder.name)
                .font(FontManager.heading(size: 13, weight: .medium))
                .foregroundColor(Color("PrimaryTextColor"))
                .tracking(-0.4)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Menu {
                    Button {
                        HapticManager.shared.buttonTap()
                        onCreateNoteInFolder(folder.id)
                    } label: {
                        Label("Create New Notes", image: "IconNoteText")
                    }

                    Button {
                        HapticManager.shared.buttonTap()
                        onRenameFolder(folder)
                    } label: {
                        Label("Rename Folder", image: "rename note")
                    }

                    Divider()

                    Button(role: .destructive) {
                        HapticManager.shared.buttonTap()
                        onDeleteFolder(folder)
                    } label: {
                        Label("Delete Folder", image: "delete")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    HapticManager.shared.buttonTap()
                    onCreateNoteInFolder(folder.id)
                } label: {
                    Image("IconNoteText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .opacity(shouldShowActions ? 1 : 0)
            .allowsHitTesting(shouldShowActions)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rowBackgroundColor(isDropTarget: isDropTarget, isHovered: isHovered))
                .padding(.horizontal, rowHoverHorizontalInset)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            HapticManager.shared.buttonTap()
            withAnimation(.notySpring) {
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
                onCreateNoteInFolder(folder.id)
            } label: {
                Label("Create New Notes", image: "IconNoteText")
            }

            Button {
                HapticManager.shared.buttonTap()
                onRenameFolder(folder)
            } label: {
                Label("Rename Folder", image: "rename note")
            }

            Divider()

            Button(role: .destructive) {
                HapticManager.shared.buttonTap()
                onDeleteFolder(folder)
            } label: {
                Label("Delete Folder", image: "delete")
            }
        }
        .dropDestination(for: NoteDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            let success = onDropNoteIntoFolder(item.noteID, folder.id)
            if success {
                withAnimation(.notySpring) {
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

        return VStack(alignment: .leading, spacing: 2) {
            if notes.isEmpty {
                Text("No notes")
                    .font(FontManager.metadata(size: 11, weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .padding(.leading, 34)
                    .padding(.vertical, 4)
            } else {
                ForEach(visibleNotes, id: \.id) { note in
                    NoteListCard(
                        note: note,
                        isSelected: selectedNoteIDs.contains(note.id),
                        leadingIconAssetName: "IconThumbtack",
                        showLeadingIconOnHoverOnly: true,
                        onLeadingIconTap: {
                            onTogglePinForNotes(contextSelection(for: note), !note.isPinned)
                        },
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
                        onArchive: onArchiveNotes != nil ? { onArchiveNotes?(contextSelection(for: note)) } : nil
                    )
                }

                if notes.count > 5 {
                    Button {
                        withAnimation(.notySpring) {
                            toggleShowAllNotes(for: folder.id)
                        }
                    } label: {
                        Text(showsAll ? "Show less" : "Show more")
                            .font(FontManager.metadata(size: 11, weight: .semibold))
                            .foregroundColor(Color("SecondaryTextColor"))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 34)
                    .padding(.top, 2)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func rowBackgroundColor(isDropTarget: Bool, isHovered: Bool) -> Color {
        if isDropTarget {
            return Color("HoverBackgroundColor").opacity(0.85)
        }
        if isHovered {
            return Color("HoverBackgroundColor").opacity(0.65)
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
}
