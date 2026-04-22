//
//  SmartFolderSection.swift
//  Jot
//
//  Sidebar accordion for saved filter definitions. No drag targets and no “new note in folder” —
//  smart folders are read-only views over matching notes.
//

import SwiftUI

struct SmartFolderSection: View {
    let smartFolders: [SmartFolder]
    let notesBySmartFolder: [UUID: [Note]]
    var selectedNoteIDs: Set<UUID> = []
    var activeNoteID: UUID? = nil
    @Binding var expandedSmartFolderIDs: Set<UUID>
    @Binding var showAllNotesSmartFolderIDs: Set<UUID>
    let allFolders: [Folder]
    let onOpenNote: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void
    var onArchiveNotes: ((Set<UUID>) -> Void)? = nil
    let onRenameNote: ((Note, String) -> Void)?
    var onToggleLockNote: ((UUID) -> Void)? = nil
    var onLockIconTap: ((Note) -> Void)? = nil
    var splitNoteIDs: Set<UUID> = []
    var onSplitIconTap: ((Note) -> Void)? = nil
    let onEditSmartFolder: (SmartFolder) -> Void
    let onDeleteSmartFolder: (SmartFolder) -> Void
    @Binding var isExpanded: Bool

    @State private var hoveredSmartFolderID: UUID?

    private var rowTint: Color { Color("SecondaryTextColor") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Smart Folders")
                    .font(FontManager.heading(size: 11, weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))

                Circle()
                    .fill(Color("SecondaryTextColor"))
                    .frame(width: 2, height: 2)

                Text("\(smartFolders.count)")
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))

                Spacer(minLength: 0)

                Image(isExpanded ? "IconChevronTopSmall" : "IconChevronDownSmall")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 15, height: 15)
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

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(smartFolders, id: \.id) { smartFolder in
                        let isOpen = expandedSmartFolderIDs.contains(smartFolder.id)
                        VStack(alignment: .leading, spacing: 4) {
                            smartFolderRow(smartFolder)

                            if isOpen {
                                smartFolderNotesList(smartFolder)
                            }
                        }
                        .id(smartFolder.id)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }

    private func smartFolderRow(_ smartFolder: SmartFolder) -> some View {
        let isHovered = hoveredSmartFolderID == smartFolder.id
        let noteCount = (notesBySmartFolder[smartFolder.id] ?? []).count
        let shouldShowActions = isHovered

        return HStack(spacing: 8) {
            Image("IconFolderNewSmart")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(rowTint)
                .frame(width: 15, height: 15)

            Text(smartFolder.name)
                .font(FontManager.heading(size: 13, weight: .regular))
                .foregroundColor(rowTint)
                .tracking(-0.1)
                .lineLimit(1)
                .truncationMode(.tail)

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
                        onEditSmartFolder(smartFolder)
                    } label: {
                        Label {
                            Text("Edit Smart Folder")
                        } icon: {
                            Image.menuIcon("rename note")
                        }
                    }

                    Button(role: .destructive) {
                        HapticManager.shared.buttonTap()
                        onDeleteSmartFolder(smartFolder)
                    } label: {
                        Label {
                            Text("Delete")
                        } icon: {
                            Image.menuIcon("delete")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(FontManager.icon(size: 12, weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .subtleHoverScale(1.06)
            }
            .frame(width: shouldShowActions ? nil : 0)
            .opacity(shouldShowActions ? 1 : 0)
            .allowsHitTesting(shouldShowActions)
            .clipped()
            .animation(.jotHover, value: shouldShowActions)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            Capsule()
                .fill(isHovered ? Color("HoverBackgroundColor") : Color.clear)
                .padding(.horizontal, 0)
        )
        // Match `FolderSection` folderRow: hit-testing is the full capsule so hover, click,
        // and secondary-click apply to the whole row (not just the title text).
        .contentShape(Capsule())
        .animation(.jotHover, value: isHovered)
        .onTapGesture {
            HapticManager.shared.buttonTap()
            withAnimation(.jotSmoothFast) {
                toggleExpansion(smartFolder.id)
            }
        }
        .onHover { hovering in
            if hovering {
                hoveredSmartFolderID = smartFolder.id
            } else if hoveredSmartFolderID == smartFolder.id {
                hoveredSmartFolderID = nil
            }
        }
        .contextMenu {
            Button {
                HapticManager.shared.buttonTap()
                onEditSmartFolder(smartFolder)
            } label: {
                Label {
                    Text("Edit Smart Folder")
                } icon: {
                    Image.menuIcon("rename note")
                }
            }

            Button(role: .destructive) {
                HapticManager.shared.buttonTap()
                onDeleteSmartFolder(smartFolder)
            } label: {
                Label {
                    Text("Delete")
                } icon: {
                    Image.menuIcon("delete")
                }
            }
        }
    }

    private func smartFolderNotesList(_ smartFolder: SmartFolder) -> some View {
        let notes = notesBySmartFolder[smartFolder.id] ?? []
        let showsAll = showAllNotesSmartFolderIDs.contains(smartFolder.id)
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
                            activeIconTint: rowTint,
                            isInsideFolder: true,
                            leadingIconAssetName: note.isLocked
                                ? "IconLock"
                                : (splitNoteIDs.contains(note.id) ? "IconArrowSplitUp" : nil),
                            leadingIconSize: splitNoteIDs.contains(note.id) ? 14 : 15,
                            hoverLeadingIconAssetName: note.isLocked ? "IconUnlocked" : nil,
                            persistentLeadingIconBg: false,
                            leadingIconBgColor: .clear,
                            leadingIconFgColor: Color("SecondaryTextColor"),
                            hoverLeadingIconBgColor: .clear,
                            hoverLeadingIconFgColor: Color("SecondaryTextColor"),
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
                            }
                        )
                    }

                    if notes.count > 5 {
                        Button {
                            withAnimation(.jotSpring) {
                                toggleShowAll(for: smartFolder.id)
                            }
                        } label: {
                            Text(showsAll ? "Show less" : "Show more")
                                .font(FontManager.metadata(size: 11, weight: .medium))
                                .foregroundColor(Color("SecondaryTextColor"))
                                .textCase(.uppercase)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                        .subtleHoverScale(1.02)
                    }
                }
                .padding(.leading, 26)
            }
        }
    }

    private func toggleExpansion(_ id: UUID) {
        if expandedSmartFolderIDs.contains(id) {
            expandedSmartFolderIDs.remove(id)
        } else {
            expandedSmartFolderIDs.insert(id)
        }
    }

    private func toggleShowAll(for id: UUID) {
        if showAllNotesSmartFolderIDs.contains(id) {
            showAllNotesSmartFolderIDs.remove(id)
        } else {
            showAllNotesSmartFolderIDs.insert(id)
        }
    }

    private func contextSelection(for note: Note) -> Set<UUID> {
        if selectedNoteIDs.count > 1, selectedNoteIDs.contains(note.id) {
            return selectedNoteIDs
        }
        return [note.id]
    }
}
