//
//  ArchivedNoteRow.swift
//  Jot
//

import SwiftUI

struct ArchivedNoteRow: View {
    let note: Note
    let isSelected: Bool
    let isActive: Bool
    let onTap: () -> Void
    let onUnarchive: () -> Void
    let onDelete: () -> Void
    var cornerRadius: CGFloat = 10
    /// When true, renders as a folder-item row: date on right, no unarchive button,
    /// delete-only context menu — matching the layout of NoteListCard inside FolderSection.
    var inFolderContext: Bool = false

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Text(note.title)
                .font(FontManager.heading(size: 15, weight: .medium))
                .foregroundColor(Color("PrimaryTextColor"))
                .tracking(-0.4)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if inFolderContext {
                Text(Self.dateFormatter.string(from: note.date))
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
            } else {
                Spacer(minLength: 8)

                Button {
                    HapticManager.shared.buttonTap()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onUnarchive()
                    }
                } label: {
                    Image("IconStepBack")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .buttonStyle(.plain)
                .subtleHoverScale(1.06)
                .help("Unarchive Note")
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundFill)
        )
        .shadow(color: isActive ? .black.opacity(0.06) : .clear, radius: 3, x: 0, y: 1)
        .shadow(color: isActive ? .black.opacity(0.03) : .clear, radius: 1, x: 0, y: 0)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.jotHover, value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if inFolderContext {
                Button(role: .destructive) {
                    HapticManager.shared.buttonTap()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onDelete()
                    }
                } label: {
                    Label {
                        Text("Delete Note")
                    } icon: {
                        Image("delete")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
            } else {
                Button {
                    HapticManager.shared.buttonTap()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onUnarchive()
                    }
                } label: {
                    Label {
                        Text("Unarchive")
                    } icon: {
                        Image("IconStepBack")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
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
                        Image("delete")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
            }
        }
    }

    private var backgroundFill: Color {
        if isActive {
            return colorScheme == .light ? Color.white : Color(red: 0.047, green: 0.039, blue: 0.035)
        } else if isSelected {
            return Color("SurfaceTranslucentColor")
        }
        return Color.clear
    }
}
