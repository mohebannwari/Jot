//
//  SplitNotePickerView.swift
//  Jot
//
//  Secondary-pane content shown while the user picks a note for the split view.
//  Based on Figma 2047:3739 — "split-view-select-note".
//

import SwiftUI

struct SplitNotePickerView: View {
    let recentNotes: [Note]
    let onSelect: (Note) -> Void
    let onClose: () -> Void
    var showCloseButton: Bool = true

    @State private var searchQuery = ""

    private var filteredNotes: [Note] {
        searchQuery.isEmpty
            ? recentNotes
            : recentNotes.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        // Vertically centered content block
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text("Select a note")
                .jotUI(FontManager.uiLabel5(weight: .regular))
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            HStack(spacing: 8) {
                Image("IconMagnifyingGlass")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 15, height: 15)
                TextField("Search", text: $searchQuery)
                    .jotUI(FontManager.uiLabel5(weight: .regular))
                    .textFieldStyle(.plain)
            }
            .padding(8)

            LazyVStack(spacing: 0) {
                ForEach(filteredNotes) { note in
                    PickerNoteRow(note: note, onSelect: onSelect)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 260, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .overlay(alignment: .bottom) {
            if showCloseButton {
                Button(action: onClose) {
                    Text("Close splitview")
                        .jotUI(FontManager.uiLabel3(weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .liquidGlass(in: Capsule())
                .subtleHoverScale(1.06)
                .padding(.bottom, 28)
            }
        }
    }
}

// Separate struct so @State inside SubtleHoverScale doesn't dirty the parent body.
private struct PickerNoteRow: View {
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
                    .frame(width: 15, height: 15)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .jotUI(FontManager.uiLabel2(weight: .regular))
                    .foregroundColor(.primary)
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
