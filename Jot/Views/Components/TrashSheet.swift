//
//  TrashSheet.swift
//  Jot
//
//  Trash sheet — shows deleted notes with restore/delete actions, liquid glass container.
//

import SwiftUI

struct TrashSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager

    @Environment(\.colorScheme) private var colorScheme

    @State private var isEmptyTrashConfirmationPresented = false

    private let sheetWidth: CGFloat = 400
    private let sheetHeight: CGFloat = 400
    private let cornerRadius: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.15)
                .padding(.horizontal, 16)

            notesList

            Divider()
                .opacity(0.15)
                .padding(.horizontal, 16)
            footerButtons
        }
        .frame(width: sheetWidth, height: sheetHeight)
        .liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .alert("Delete All Notes?", isPresented: $isEmptyTrashConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                notesManager.emptyTrash()
                if notesManager.deletedNotes.isEmpty {
                    isPresented = false
                }
            }
        } message: {
            Text("This action cannot be undone. All notes in the trash will be permanently deleted.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image("delete")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(width: 18, height: 18)

            Text("Trash")
                .font(FontManager.heading(size: 15, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))
                .tracking(-0.4)

            Circle()
                .fill(Color("SecondaryTextColor"))
                .frame(width: 2, height: 2)

            Text("\(notesManager.deletedNotes.count)")
                .font(FontManager.metadata(size: 11, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Notes List

    private var notesList: some View {
        Group {
            if notesManager.deletedNotes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(notesManager.deletedNotes) { note in
                            trashNoteRow(note)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image("delete")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SecondaryTextColor").opacity(0.4))
                .frame(width: 32, height: 32)

            Text("Trash is empty")
                .font(FontManager.heading(size: 14, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .tracking(-0.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trashNoteRow(_ note: Note) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .tracking(-0.3)
                    .lineLimit(1)

                if let deletedDate = note.deletedDate {
                    Text(relativeDateString(deletedDate).uppercased())
                        .font(FontManager.metadata(size: 11, weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                // Restore button
                Button {
                    HapticManager.shared.buttonTap()
                    withAnimation(.jotBounce) {
                        notesManager.restoreFromTrash(ids: [note.id])
                        if notesManager.deletedNotes.isEmpty {
                            isPresented = false
                        }
                    }
                } label: {
                    Image("IconStepBack")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .subtleHoverScale(1.05)
                .help("Restore")

                // Permanent delete button
                Button {
                    HapticManager.shared.buttonTap()
                    withAnimation(.jotBounce) {
                        notesManager.permanentlyDeleteNotes(ids: [note.id])
                        if notesManager.deletedNotes.isEmpty {
                            isPresented = false
                        }
                    }
                } label: {
                    Image("delete")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 18, height: 18)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .subtleHoverScale(1.05)
                .help("Delete permanently")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        HStack(spacing: 8) {
            // Delete All
            Button {
                HapticManager.shared.buttonTap()
                isEmptyTrashConfirmationPresented = true
            } label: {
                Text("Delete All")
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .subtleHoverScale(1.02)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .disabled(notesManager.deletedNotes.isEmpty)
        .opacity(notesManager.deletedNotes.isEmpty ? 0.4 : 1.0)
    }

    // MARK: - Helpers

    private func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Deleted " + formatter.localizedString(for: date, relativeTo: Date())
    }
}
