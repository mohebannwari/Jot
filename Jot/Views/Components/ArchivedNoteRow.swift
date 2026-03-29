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
    /// When true, renders as a folder-item row: date on right, no unarchive button,
    /// delete-only context menu — matching the layout of NoteListCard inside FolderSection.
    var inFolderContext: Bool = false

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Text(note.title)
                .font(FontManager.heading(size: 15, weight: .medium))
                .foregroundColor(Color("PrimaryTextColor"))
                .tracking(-0.1)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if inFolderContext {
                Text(Self.dateFormatter.string(from: note.date))
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
            } else {
                Spacer(minLength: 8)

                HStack(spacing: 2) {
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
                            .frame(width: 16, height: 16)
                            .foregroundColor(Color("SecondaryTextColor"))
                            .padding(4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .subtleHoverScale(1.06)
                    .hoverContainer(cornerRadius: 999)
                    .help("Unarchive Note")

                    Button {
                        HapticManager.shared.buttonTap()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            onDelete()
                        }
                    } label: {
                        Image("delete")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundColor(.red)
                            .padding(4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .subtleHoverScale(1.06)
                    .hoverContainer(cornerRadius: 999)
                    .help("Delete Note")
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 34)
        .background(
            Capsule()
                .fill(backgroundFill)
        )
        .shadow(color: isActive ? .black.opacity(0.06) : .clear, radius: 3, x: 0, y: 1)
        .shadow(color: isActive ? .black.opacity(0.03) : .clear, radius: 1, x: 0, y: 0)
        .animation(.jotHover, value: isHovered)
        .contentShape(Capsule())
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
                        Image.menuIcon("delete")
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
                        Image.menuIcon("IconStepBack")
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
        }
    }

    private var backgroundFill: Color {
        if isActive {
            return colorScheme == .light ? .white : Color("DetailPaneColor")
        } else if isSelected {
            return Color("SurfaceTranslucentColor")
        } else if isHovered {
            return Color("HoverBackgroundColor")
        }
        return Color.clear
    }
}
