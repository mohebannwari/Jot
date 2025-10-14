//
//  ContentView.swift
//  Noty
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI

struct ContentView: View {
    // Search is powered by SearchEngine
    @StateObject private var searchEngine = SearchEngine()
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    @State private var selectedNote: Note?
    @State private var isNoteDetailPresented = false
    @State private var isSearchActive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 36) {
                        // PINNED NOTES Section
                        if !pinnedNotes.isEmpty {
                            PinnedNotesSection(
                                notes: pinnedNotes,
                                onNoteTap: { note in
                                    HapticManager.shared.noteInteraction()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        selectedNote = note
                                        isNoteDetailPresented = true
                                    }
                                }
                            )
                        }

                        // Today Section
                        if !todayNotes.isEmpty {
                            NotesSection(
                                title: "TODAY",
                                notes: todayNotes,
                                onNoteTap: { note in
                                    HapticManager.shared.noteInteraction()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        selectedNote = note
                                        isNoteDetailPresented = true
                                    }
                                },
                                onDeleteNote: { noteId in
                                    notesManager.deleteNote(id: noteId)
                                }
                            )
                        }

                        // This Month Section
                        if !thisMonthNotes.isEmpty {
                            NotesSection(
                                title: "THIS MONTH",
                                notes: thisMonthNotes,
                                onNoteTap: { note in
                                    HapticManager.shared.noteInteraction()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        selectedNote = note
                                        isNoteDetailPresented = true
                                    }
                                },
                                onDeleteNote: { noteId in
                                    notesManager.deleteNote(id: noteId)
                                }
                            )
                        }

                        // This Year Section
                        if !thisYearNotes.isEmpty {
                            NotesSection(
                                title: "THIS YEAR",
                                notes: thisYearNotes,
                                onNoteTap: { note in
                                    HapticManager.shared.noteInteraction()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        selectedNote = note
                                        isNoteDetailPresented = true
                                    }
                                },
                                onDeleteNote: { noteId in
                                    notesManager.deleteNote(id: noteId)
                                }
                            )
                        }

                        // Older Section
                        if !olderNotes.isEmpty {
                            NotesSection(
                                title: "OLDER",
                                notes: olderNotes,
                                onNoteTap: { note in
                                    HapticManager.shared.noteInteraction()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        selectedNote = note
                                        isNoteDetailPresented = true
                                    }
                                },
                                onDeleteNote: { noteId in
                                    notesManager.deleteNote(id: noteId)
                                }
                            )
                        }
                    }
                    .frame(width: 400)
                    .padding(.top, pinnedNotes.isEmpty ? 24 : 18)
                    .padding(.leading, 30)
                    .padding(.trailing, 30)
                    .padding(.bottom, 80)
                }
                .scrollIndicators(.never)
            }
            .opacity(isNoteDetailPresented ? 0 : 1)
            .offset(x: isNoteDetailPresented ? -20 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isNoteDetailPresented)
            .contentShape(Rectangle())
            .onTapGesture {
                // Close search when tapping outside
                if isSearchActive {
                    searchEngine.query = ""
                    isSearchActive = false
                }
            }

            // Bottom Bar Component
            BottomBar(onNewNote: createAndOpenNewNote)
                .environmentObject(themeManager)
                .opacity(isNoteDetailPresented ? 0 : 1)
                .offset(x: isNoteDetailPresented ? -20 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isNoteDetailPresented)
                .onTapGesture {
                    // Close search when tapping bottom bar
                    if isSearchActive {
                        searchEngine.query = ""
                        isSearchActive = false
                    }
                }

            // Floating Search Overlay (does not affect other buttons)
            FloatingSearch(engine: searchEngine) { note in
                HapticManager.shared.noteInteraction()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    selectedNote = note
                    isNoteDetailPresented = true
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 18)
            .padding(.bottom, 18)
            .opacity(isNoteDetailPresented ? 0 : 1)
            .offset(x: isNoteDetailPresented ? -20 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isNoteDetailPresented)
            .onChange(of: searchEngine.query) { _, newValue in
                isSearchActive = !newValue.isEmpty
            }

            // Note Detail Overlay
            if isNoteDetailPresented, let note = selectedNote {
                NoteDetailView(note: note, isPresented: $isNoteDetailPresented) { updated in
                    notesManager.updateNote(updated)
                    selectedNote = updated
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(100)
            }
        }
        .background(AppWindowBackground())
        // Search logic will be reintroduced with the redesigned manager
        .onAppear { searchEngine.setNotes(notesManager.notes) }
        .onChange(of: notesManager.notes) { notes in
            searchEngine.setNotes(notes)
        }
    }

    private var displayedNotes: [Note] {
        // For now always show all notes until the new search manager is introduced
        return notesManager.notes
    }

    private var pinnedNotes: [Note] {
        return displayedNotes.filter { $0.isPinned }
    }

    private var todayNotes: [Note] {
        let today = Calendar.current.startOfDay(for: Date())
        return displayedNotes.filter { note in
            !note.isPinned && Calendar.current.isDate(note.date, inSameDayAs: today)
        }
    }

    private var thisMonthNotes: [Note] {
        let today = Calendar.current.startOfDay(for: Date())
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())

        return displayedNotes.filter { note in
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

        return displayedNotes.filter { note in
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

        return displayedNotes.filter { note in
            let noteYear = calendar.component(.year, from: note.date)
            return !note.isPinned && noteYear < currentYear
        }
    }

    private func createAndOpenNewNote() {
        HapticManager.shared.noteInteraction()
        let note = notesManager.addNote(title: "New Note", content: "")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedNote = note
            isNoteDetailPresented = true
        }
    }
}

// Notes Section Component
struct NotesSection: View {
    let title: String
    let notes: [Note]
    let onNoteTap: (Note) -> Void
    let onDeleteNote: (UUID) -> Void
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section header - using SF Pro Compact for headings
            Text(title)
                .font(FontManager.heading(size: 9, weight: .medium))
                .foregroundColor(Color.primary.opacity(0.7))
                .kerning(0)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                )
                .frame(maxWidth: .infinity, alignment: .leading)

            // Notes list
            ForEach(notes, id: \.id) { note in
                NoteListCard(
                    note: note,
                    onTap: { onNoteTap(note) },
                    onDelete: { onDeleteNote(note.id) }
                )
            }
        }
    }
}

// Note List Card Component (Figma design)
struct NoteListCard: View {
    let note: Note
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var showExportSheet = false
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager

    var body: some View {
        Button(action: onTap) {
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
                Text(dateFormatter.string(from: note.date))
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.55))
                    .kerning(-0.25)
                    .frame(alignment: .center)
            }
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 50)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                HapticManager.shared.buttonTap()
                withAnimation(.easeInOut(duration: 0.25)) {
                    notesManager.togglePin(id: note.id)
                }
            } label: {
                Label(note.isPinned ? "Unpin Note" : "Pin Note", systemImage: note.isPinned ? "pin.slash" : "pin")
            }

            Button {
                HapticManager.shared.buttonTap()
                // Move to folder functionality
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }

            Button {
                HapticManager.shared.buttonTap()
                showExportSheet = true
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
        .sheet(isPresented: $showExportSheet) {
            ExportFormatSheet(isPresented: $showExportSheet, notes: [note]) { exportNotes, format in
                Task { @MainActor in
                    let success: Bool

                    if exportNotes.count == 1, let singleNote = exportNotes.first {
                        success = await NoteExportService.shared.exportNote(singleNote, format: format)
                    } else {
                        let filename = "Noty Export \(Date().formatted(date: .numeric, time: .omitted))"
                        success = await NoteExportService.shared.exportNotes(exportNotes, format: format, filename: filename)
                    }

                    if success {
                        HapticManager.shared.strong()
                    } else {
                        HapticManager.shared.medium()
                    }
                }
            }
        }
    }

    // Date formatter for numeric format: DD.MM.YY (e.g., 10.11.25)
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return formatter
    }
}

// List Tag View Component (Figma design)
struct ListTagView: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(FontManager.heading(size: 13, weight: .medium))
            .foregroundColor(Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255))  // blue-500
            .kerning(0)
    }
}

// Pinned Notes Section with Liquid Glass Capsule
struct PinnedNotesSection: View {
    let notes: [Note]
    let onNoteTap: (Note) -> Void
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section header - using SF Pro Compact for headings
            Text("PINNED")
                .font(FontManager.heading(size: 9, weight: .medium))
                .foregroundColor(Color.primary.opacity(0.7))
                .kerning(0)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                )
                .frame(maxWidth: .infinity, alignment: .leading)

            // Pinned notes chips
            FlowLayout(spacing: 8) {
                ForEach(notes) { note in
                    PinnedNoteChip(
                        note: note,
                        onTap: { onNoteTap(note) },
                        onUnpin: {
                            HapticManager.shared.buttonTap()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                notesManager.togglePin(id: note.id)
                            }
                        }
                    )
                }
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
    }
}

// Pinned Note Chip with Liquid Glass
struct PinnedNoteChip: View {
    let note: Note
    let onTap: () -> Void
    let onUnpin: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(note.title)
                .font(FontManager.heading(size: 14, weight: .medium))
                .foregroundColor(Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .glassEffect(.regular.interactive(true), in: Capsule())
        #else
        .background(.ultraThinMaterial, in: Capsule())
        #endif
        .contextMenu {
            Button {
                onUnpin()
            } label: {
                Label("Unpin Note", systemImage: "pin.slash")
            }
        }
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
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
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
