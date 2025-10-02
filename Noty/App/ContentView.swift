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
    @EnvironmentObject private var notesManager: NotesManager
    @State private var selectedNote: Note?
    @State private var isNoteDetailPresented = false
    @State private var isSearchActive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 48) {
                        // TODAY Section
                        if !todayNotes.isEmpty {
                            NotesSection(
                                title: "TODAY",
                                notes: todayNotes,
                                onNoteTap: { note in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        selectedNote = note
                                        isNoteDetailPresented = true
                                    }
                                },
                                onDeleteNote: { noteId in
                                    notesManager.deleteNote(id: noteId)
                                }
                            )
                        }

                        // LAST WEEK Section
                        if !lastWeekNotes.isEmpty {
                            NotesSection(
                                title: "LAST WEEK",
                                notes: lastWeekNotes,
                                onNoteTap: { note in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        selectedNote = note
                                        isNoteDetailPresented = true
                                    }
                                },
                                onDeleteNote: { noteId in
                                    notesManager.deleteNote(id: noteId)
                                }
                            )
                        }

                        // OLDER Section
                        if !olderNotes.isEmpty {
                            NotesSection(
                                title: "OLDER",
                                notes: olderNotes,
                                onNoteTap: { note in
                                    withAnimation(.easeInOut(duration: 0.3)) {
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
                    .padding(.top, 60)
                    .padding(.leading, 30)
                    .padding(.trailing, 30)
                }
                .scrollIndicators(.never)
            }
            .opacity(isNoteDetailPresented ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: isNoteDetailPresented)
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
                .animation(.easeInOut(duration: 0.3), value: isNoteDetailPresented)
                .onTapGesture {
                    // Close search when tapping bottom bar
                    if isSearchActive {
                        searchEngine.query = ""
                        isSearchActive = false
                    }
                }

            // Floating Search Overlay (does not affect other buttons)
            FloatingSearch(engine: searchEngine) { note in
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedNote = note
                    isNoteDetailPresented = true
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 18)
            .padding(.bottom, 18)
            .opacity(isNoteDetailPresented ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: isNoteDetailPresented)
            .onChange(of: searchEngine.query) { _, newValue in
                isSearchActive = !newValue.isEmpty
            }

            // Note Detail Overlay
            if isNoteDetailPresented, let note = selectedNote {
                NoteDetailView(note: note, isPresented: $isNoteDetailPresented) { updated in
                    notesManager.updateNote(updated)
                    selectedNote = updated
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(100)
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .containerBackground(.thickMaterial, for: .window)
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

    private var todayNotes: [Note] {
        let today = Calendar.current.startOfDay(for: Date())
        return displayedNotes.filter { note in
            Calendar.current.isDate(note.date, inSameDayAs: today)
        }
    }

    private var lastWeekNotes: [Note] {
        let today = Calendar.current.startOfDay(for: Date())
        let lastWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: today)!
        return displayedNotes.filter { note in
            let noteDay = Calendar.current.startOfDay(for: note.date)
            return noteDay < today && noteDay >= lastWeekStart
        }
    }

    private var olderNotes: [Note] {
        let today = Calendar.current.startOfDay(for: Date())
        let lastWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: today)!
        return displayedNotes.filter { note in
            let noteDay = Calendar.current.startOfDay(for: note.date)
            return noteDay < lastWeekStart
        }
    }

    private func createAndOpenNewNote() {
        let note = notesManager.addNote(title: "New Note", content: "")
        withAnimation(.easeInOut(duration: 0.3)) {
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
    @EnvironmentObject private var notesManager: NotesManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section header
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.primary.opacity(0.7))
                .kerning(0)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Notes list
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                VStack(spacing: 18) {
                    NoteListCard(
                        note: note,
                        onTap: { onNoteTap(note) },
                        onDelete: { onDeleteNote(note.id) }
                    )

                    // Divider between cards (except after last card)
                    if index < notes.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.2))
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }
}

// Note List Card Component (Figma design)
struct NoteListCard: View {
    let note: Note
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Content
                VStack(alignment: .leading, spacing: 8) {
                    // Date
                    Text(dateFormatter.string(from: note.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.primary.opacity(0.7))
                        .kerning(0)

                    // Title
                    Text(note.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.primary)
                        .kerning(0)
                        .lineSpacing(4)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Three-dot menu button
                Menu {
                    Button {
                        // Pin functionality
                    } label: {
                        Label("Pin Note", systemImage: "pin")
                    }

                    Button {
                        // Move to folder functionality
                    } label: {
                        Label("Move to Folder", systemImage: "folder")
                    }

                    Divider()

                    Button("Delete", role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            onDelete()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundColor(Color.primary)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(4)
                .background(
                    Circle()
                        .fill(Color.clear)
                )
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                // Pin functionality
            } label: {
                Label("Pin Note", systemImage: "pin")
            }

            Button {
                // Move to folder functionality
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }

            Divider()

            Button("Delete", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    onDelete()
                }
            }
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }
}

// List Tag View Component (Figma design)
struct ListTagView: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255))  // blue-500
            .kerning(0)
    }
}

#Preview {
    ContentView()
        .environmentObject(NotesManager())
        .environmentObject(ThemeManager())
}
