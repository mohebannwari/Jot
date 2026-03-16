//
//  SidebarListComponents.swift
//  Jot
//
//  Extracted from ContentView.swift — sidebar list components (NotesSection,
//  NoteListCard, PinnedNotesSection, LockedNotesSection, FlowLayout).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Notes Section Component
struct NotesSection: View {
    let title: String
    let notes: [Note]
    var selectedNoteIDs: Set<UUID> = []
    var activeNoteID: UUID? = nil
    var splitNoteIDs: Set<UUID> = []
    var onSplitIconTap: ((Note) -> Void)? = nil
    let folders: [Folder]
    let onNoteTap: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void
    var onArchiveNotes: ((Set<UUID>) -> Void)? = nil
    var onToggleLockNote: ((UUID) -> Void)? = nil
    var onLockIconTap: ((Note) -> Void)? = nil
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
        }
        .background(
            Capsule()
                .fill(isDropTargeted ? Color("SurfaceTranslucentColor") : Color.clear)
        )
        .if(onDropNoteToUnfiled != nil) { view in
            view.onDrop(of: [.jotNoteDragPayload], delegate: NoteMoveDropDelegate(
                isTargeted: $isDropTargeted,
                onPerformDrop: { payload in
                    guard let first = payload.items.first,
                          let onDropNoteToUnfiled else {
                        return false
                    }
                    return onDropNoteToUnfiled(first.noteID)
                }
            ))
        }
    }

    private func contextSelection(for note: Note) -> Set<UUID> {
        if selectedNoteIDs.count > 1, selectedNoteIDs.contains(note.id) {
            return selectedNoteIDs
        }
        return [note.id]
    }
}

// Split Picker Overlay -- Figma 2122:7878
// Self-contained card with its own search state; lifecycle resets on mount.
struct SplitPickerOverlayCard: View {
    let notes: [Note]
    let onSelect: (Note) -> Void

    @State private var searchQuery = ""

    private var filteredNotes: [Note] {
        let base = searchQuery.isEmpty
            ? notes
            : notes.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
        return Array(base.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title -- Label/Label-5/Medium
            Text("Switch note")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .tracking(-0.2)
                .padding(8)

            // Search field -- Label/Label-4/Medium
            HStack(spacing: 8) {
                Image("IconMagnifyingGlass")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 18, height: 18)
                TextField("Search", text: $searchQuery)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .textFieldStyle(.plain)
            }
            .padding(8)

            // Results -- Label/Label-2/Medium
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filteredNotes) { note in
                    SplitPickerOverlayRow(note: note, onSelect: onSelect)
                }
            }
        }
        .padding(12)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SplitPickerOverlayRow: View {
    let note: Note
    let onSelect: (Note) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(note)
        } label: {
            HStack(spacing: 8) {
                Image("IconNoteText")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 18, height: 18)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .tracking(-0.2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule()
                    .fill(Color("HoverBackgroundColor"))
                    .opacity(isHovered ? 1 : 0)
            )
            .contentShape(Capsule())
            .animation(.jotHover, value: isHovered)
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .onHover { isHovered = $0 }
    }
}

// Note List Card Component (Figma design)
struct NoteListCard: View {
    let note: Note
    var isSelected: Bool = false
    var isActiveNote: Bool = false
    var leadingIconAssetName: String? = nil
    var hoverLeadingIconAssetName: String? = nil
    var showLeadingIconOnHoverOnly: Bool = false
    var persistentLeadingIconBg: Bool = false
    var leadingIconBgColor: Color = .accentColor
    var leadingIconFgColor: Color = .white
    var hoverLeadingIconBgColor: Color? = nil
    var hoverLeadingIconFgColor: Color? = nil
    var onLeadingIconTap: (() -> Void)? = nil
    let onTap: (NoteSelectionInteraction) -> Void
    let onTogglePin: (Bool) -> Void
    let onDelete: () -> Void
    let folders: [Folder]
    let onCreateFolderWithNote: () -> Void
    let onMoveToFolder: (UUID?) -> Void
    let onExport: () -> Void
    var onArchive: (() -> Void)? = nil
    var onToggleLock: (() -> Void)? = nil
    var onRename: ((String) -> Void)? = nil
    var getDragItems: (() -> [NoteDragItem])? = nil
    var cornerRadius: CGFloat = 12
    @State private var isHovered = false
    @State private var isLeadingIconHovered = false
    @State private var isEllipsisHovered = false
    @State private var isRenaming = false
    @State private var renamingTitle = ""
    @FocusState private var isFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var leadingIconTint: Color {
        isActiveNote
            ? Color("ButtonPrimaryTextColor")
            : Color("SecondaryTextColor")
    }

    private var titleColor: Color {
        isActiveNote ? Color("ButtonPrimaryTextColor") : Color("PrimaryTextColor")
    }

    private var dateColor: Color {
        isActiveNote ? Color("ButtonPrimaryTextColor").opacity(0.7) : Color("SecondaryTextColor")
    }

    private var ellipsisColor: Color {
        isActiveNote
            ? Color("ButtonPrimaryTextColor").opacity(isEllipsisHovered ? 1.0 : 0.5)
            : Color("SecondaryTextColor").opacity(isEllipsisHovered ? 1.0 : 0.7)
    }

    @ViewBuilder
    private var noteContextMenuContent: some View {
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
                    Image.menuIcon(note.isPinned ? "IconUnpin" : "IconThumbtack")
                }
            }
        }

        Button {
            HapticManager.shared.buttonTap()
            onCreateFolderWithNote()
        } label: {
            Label {
                Text("Create New Folder With Note...")
            } icon: {
                Image.menuIcon("IconFolderAddRight")
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
                                    .frame(width: 18, height: 18)
                            }
                        } else {
                            Label {
                                Text(folder.name)
                            } icon: {
                                Image.menuIcon("IconFolder1")
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
                        Text("Remove from Folder")
                    } icon: {
                        Image.menuIcon("IconFolderOpen")
                    }
                }
            }
        } label: {
            Label {
                Text("Move to Folder")
            } icon: {
                Image.menuIcon("IconMoveFolder")
            }
        }

        Button {
            HapticManager.shared.buttonTap()
            onExport()
        } label: {
            Label {
                Text("Export Note...")
            } icon: {
                Image.menuIcon("IconFileDownload")
            }
        }

        if let onToggleLock {
            Button {
                HapticManager.shared.buttonTap()
                onToggleLock()
            } label: {
                Label {
                    Text(note.isLocked ? "Remove Lock" : "Lock Note")
                } icon: {
                    Image.menuIcon(note.isLocked ? "IconUnlocked" : "IconLock")
                }
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
                    Image.menuIcon("IconArchive1")
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
                Image.menuIcon("delete")
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = leadingIconAssetName {
                let isLeadingIconVisible = !showLeadingIconOnHoverOnly || isHovered
                let isShowingHoverVariant = isLeadingIconHovered && hoverLeadingIconAssetName != nil
                let showBg = persistentLeadingIconBg || (isLeadingIconHovered && onLeadingIconTap != nil)
                let currentFg = showBg
                    ? (isShowingHoverVariant ? (hoverLeadingIconFgColor ?? leadingIconFgColor) : leadingIconFgColor)
                    : leadingIconTint
                let currentBg = showBg
                    ? (isShowingHoverVariant ? (hoverLeadingIconBgColor ?? leadingIconBgColor) : leadingIconBgColor)
                    : Color.clear

                ZStack {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(currentFg)
                        .frame(width: 14, height: 14)
                        .opacity(isLeadingIconVisible && !isShowingHoverVariant ? 1 : 0)

                    if let hoverIcon = hoverLeadingIconAssetName {
                        Image(hoverIcon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(currentFg)
                            .frame(width: 14, height: 14)
                            .opacity(isLeadingIconVisible && isShowingHoverVariant ? 1 : 0)
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(currentBg)
                )
                .compositingGroup()
                .drawingGroup()
                .animation(.jotHover, value: isLeadingIconHovered)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { isLeadingIconHovered = $0 }
                .onTapGesture {
                    onLeadingIconTap?()
                }
                .macPointingHandCursor()
                .allowsHitTesting(isLeadingIconVisible && onLeadingIconTap != nil)
                .animation(.easeInOut(duration: 0.12), value: isLeadingIconVisible)
                .padding(.leading, -2)

                Circle()
                    .fill(leadingIconTint)
                    .frame(width: 2, height: 2)
                    .opacity(isLeadingIconVisible ? 1 : 0)
                    .padding(.horizontal, -2)
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
                    .foregroundColor(titleColor)
                    .tracking(-0.1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) {
                        startRename()
                    }
            }

            HStack(spacing: 6) {
                Text(Self.compactDateString(from: note.date))
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(dateColor)

                Menu {
                    noteContextMenuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .font(FontManager.icon(size: 14, weight: .medium))
                        .foregroundColor(ellipsisColor)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isEllipsisHovered = $0 }
            }
            .fixedSize()
        }
        .animation(.jotHover, value: isHovered)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 34)
        .background {
            if isActiveNote {
                Capsule()
                    .fill(Color("ButtonPrimaryBgColor"))
            } else if isSelected {
                Capsule()
                    .fill(Color("SurfaceTranslucentColor"))
            } else if isHovered {
                Capsule()
                    .fill(Color("HoverBackgroundColor"))
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            if !isRenaming {
                onTap(Self.selectionInteractionFromCurrentEvent())
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .draggable(
            TransferablePayload(items: getDragItems?() ?? [NoteDragItem(noteID: note.id)])
        ) {
            HStack {
                Text(note.title)
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .tracking(-0.1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(Self.compactDateString(from: note.date))
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("ButtonPrimaryTextColor").opacity(0.7))
                    .fixedSize()
            }
            .padding(8)
            .frame(width: 220, height: 34)
            .background(Capsule().fill(Color("ButtonPrimaryBgColor")))
            .contentShape(.dragPreview, Capsule())
        }
        .contextMenu {
            noteContextMenuContent
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

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM"
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    /// Day.Month for notes less than 1 year old, just the year for older notes.
    private static func compactDateString(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        if let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now),
           date < oneYearAgo {
            return yearFormatter.string(from: date)
        }
        return dayMonthFormatter.string(from: date)
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

// Pinned Notes Section with Liquid Glass Capsule
struct PinnedNotesSection: View {
    let notes: [Note]
    var selectedNoteIDs: Set<UUID> = []
    var activeNoteID: UUID? = nil
    var splitNoteIDs: Set<UUID> = []
    var onSplitIconTap: ((Note) -> Void)? = nil
    let folders: [Folder]
    let onNoteTap: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void
    var onArchiveNotes: ((Set<UUID>) -> Void)? = nil
    var onToggleLockNote: ((UUID) -> Void)? = nil
    var onLockIconTap: ((Note) -> Void)? = nil
    var onRenameNote: ((Note, String) -> Void)? = nil
    @Binding var isExpanded: Bool

    private var activeNote: Note? {
        guard let activeID = activeNoteID else { return nil }
        return notes.first { $0.id == activeID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Pinned notes")
                    .font(FontManager.heading(size: 13, weight: .medium))
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

            // Notes
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(notes, id: \.id) { note in
                        NoteListCard(
                            note: note,
                            isSelected: selectedNoteIDs.contains(note.id),
                            isActiveNote: note.id == activeNoteID,
                            leadingIconAssetName: "IconThumbtack",
                            hoverLeadingIconAssetName: "IconUnpin",
                            persistentLeadingIconBg: true,
                            leadingIconBgColor: Color.yellow,
                            leadingIconFgColor: .black,
                            onLeadingIconTap: {
                                onTogglePinForNotes([note.id], false)
                            },
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
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if let peekNote = activeNote {
                HStack(alignment: .center, spacing: 6) {
                    Image("IconRedirectArrow")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)

                    NoteListCard(
                        note: peekNote,
                        isSelected: selectedNoteIDs.contains(peekNote.id),
                        isActiveNote: peekNote.id == activeNoteID,
                        leadingIconAssetName: "IconThumbtack",
                        hoverLeadingIconAssetName: "IconUnpin",
                        persistentLeadingIconBg: true,
                        leadingIconBgColor: Color.yellow,
                        leadingIconFgColor: .black,
                        onLeadingIconTap: {
                            onTogglePinForNotes([peekNote.id], false)
                        },
                        onTap: { interaction in onNoteTap(peekNote, interaction) },
                        onTogglePin: { shouldPin in
                            onTogglePinForNotes(contextSelection(for: peekNote), shouldPin)
                        },
                        onDelete: { onDeleteNotes(contextSelection(for: peekNote)) },
                        folders: folders,
                        onCreateFolderWithNote: { onCreateFolderWithNotes(contextSelection(for: peekNote)) },
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
                }
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
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

struct LockedNotesSection: View {
    let notes: [Note]
    var selectedNoteIDs: Set<UUID> = []
    var activeNoteID: UUID? = nil
    var splitNoteIDs: Set<UUID> = []
    var onSplitIconTap: ((Note) -> Void)? = nil
    let folders: [Folder]
    let onNoteTap: (Note, NoteSelectionInteraction) -> Void
    let onDeleteNotes: (Set<UUID>) -> Void
    let onCreateFolderWithNotes: (Set<UUID>) -> Void
    let onMoveNotesToFolder: (Set<UUID>, UUID?) -> Void
    let onTogglePinForNotes: (Set<UUID>, Bool) -> Void
    let onExportNotes: (Set<UUID>) -> Void
    var onArchiveNotes: ((Set<UUID>) -> Void)? = nil
    var onToggleLockNote: ((UUID) -> Void)? = nil
    var onLockIconTap: ((Note) -> Void)? = nil
    var onRenameNote: ((Note, String) -> Void)? = nil
    @Binding var isExpanded: Bool

    private var activeNote: Note? {
        guard let activeID = activeNoteID else { return nil }
        return notes.first { $0.id == activeID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Locked notes")
                    .font(FontManager.heading(size: 13, weight: .medium))
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

            // Notes
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(notes, id: \.id) { note in
                        NoteListCard(
                            note: note,
                            isSelected: selectedNoteIDs.contains(note.id),
                            isActiveNote: note.id == activeNoteID,
                            leadingIconAssetName: "IconLock",
                            hoverLeadingIconAssetName: "IconUnlocked",
                            persistentLeadingIconBg: true,
                            leadingIconBgColor: Color.red,
                            leadingIconFgColor: .white,
                            hoverLeadingIconBgColor: Color.green,
                            hoverLeadingIconFgColor: .white,
                            onLeadingIconTap: { onLockIconTap?(note) },
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
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if let peekNote = activeNote {
                HStack(alignment: .center, spacing: 6) {
                    Image("IconRedirectArrow")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)

                    NoteListCard(
                        note: peekNote,
                        isSelected: selectedNoteIDs.contains(peekNote.id),
                        isActiveNote: peekNote.id == activeNoteID,
                        leadingIconAssetName: "IconLock",
                        hoverLeadingIconAssetName: "IconUnlocked",
                        persistentLeadingIconBg: true,
                        leadingIconBgColor: Color.red,
                        leadingIconFgColor: .white,
                        hoverLeadingIconBgColor: Color.green,
                        hoverLeadingIconFgColor: .white,
                        onLeadingIconTap: { onLockIconTap?(peekNote) },
                        onTap: { interaction in onNoteTap(peekNote, interaction) },
                        onTogglePin: { shouldPin in
                            onTogglePinForNotes(contextSelection(for: peekNote), shouldPin)
                        },
                        onDelete: { onDeleteNotes(contextSelection(for: peekNote)) },
                        folders: folders,
                        onCreateFolderWithNote: { onCreateFolderWithNotes(contextSelection(for: peekNote)) },
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
                }
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
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

// MARK: - Split Pane Shadow

extension View {
    /// Dims an inactive split pane with a color overlay instead of `.opacity()`,
    /// so the underlying NSTextView's insertion point renders at full alpha.
    func splitPaneDimming(isInactive: Bool, cornerRadius: CGFloat, colorScheme: ColorScheme) -> some View {
        self
    }

    /// Applies a layered shadow via a background shape instead of directly on the content.
    /// This prevents SwiftUI from rasterizing the content (which kills NSTextView's cursor blink timer).
    func splitPaneShadow(isActive: Bool, cornerRadius: CGFloat, backgroundColor: Color, colorScheme: ColorScheme, showStroke: Bool = false) -> some View {
        let base: Color = colorScheme == .dark ? .white : .black
        let strokeColor: Color = colorScheme == .dark
            ? .white.opacity(isActive && showStroke ? 0.50 : 0)
            : .black.opacity(isActive && showStroke ? 0.50 : 0)
        return self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
                    .shadow(color: base.opacity(isActive ? 0.20 : 0), radius: 1, x: 0, y: 0)
                    .shadow(color: base.opacity(isActive ? 0.15 : 0), radius: 6, x: 0, y: 2)
                    .shadow(color: base.opacity(isActive ? 0.10 : 0), radius: 20, x: 0, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 2)
                    .padding(1)
            }
    }
}
