//
//  NoteCard.swift
//  Noty
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI

struct NoteCard: View {
    let note: Note
    let onTap: () -> Void
    @State private var isHovering = false
    @State private var showExportSheet = false
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Bar with Date and Menu
                HStack {
                    // Date Badge - using SF Mono for metadata
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(FontManager.metadata(size: 10, weight: .regular))
                            .foregroundColor(Color("TertiaryTextColor"))
                        
                        Text(dateFormatter.string(from: note.date))
                            .font(FontManager.metadata(size: 10, weight: .medium))
                            .foregroundColor(Color("TertiaryTextColor"))
                    }
                    .padding(.horizontal, 6) 
                    .padding(.vertical, 4)
                    .tintedLiquidGlass(in: Capsule(), tint: Color("SurfaceTranslucentColor"))
                    
                    Spacer()
                    
                    // Menu Button
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

                        Button {
                            showExportSheet = true
                        } label: {
                            Label("Export Note...", systemImage: "square.and.arrow.down")
                        }

                        Divider()

                        Button("Delete", role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                notesManager.deleteNote(id: note.id)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(FontManager.heading(size: 12, weight: .regular))
                            .foregroundColor(Color("TertiaryTextColor"))
                            .frame(width: 24, height: 24)
                            .tintedLiquidGlass(in: Circle(), tint: Color("SurfaceTranslucentColor"))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Content Section
                VStack(alignment: .leading, spacing: 8) {
                    // Title - using SF Pro Compact for note names
                    Text(note.title)
                        .font(FontManager.heading(size: 17, weight: .semibold))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    // Content with original gradient fade (stronger at bottom) - using Charter for body text
                    ZStack(alignment: .topLeading) {
                        // Base text
                        Text(note.content)
                            .font(FontManager.body(size: 14, weight: .regular))
                            .foregroundColor(Color("SecondaryTextColor"))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        
                        // Blurred overlay masked to intensify bottom fade
                        Text(note.content)
                            .font(FontManager.body(size: 14, weight: .regular))
                            .foregroundColor(Color("SecondaryTextColor"))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .blur(radius: 2.0)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .clear, location: 0.6),
                                        .init(color: .black.opacity(0.3), location: 0.8),
                                        .init(color: .black.opacity(0.7), location: 1.0)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.black)
                            // Fade starts at the very bottom of the card, not above tags
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.black, location: 0.0),
                                    .init(color: Color.black, location: 0.88),
                                    .init(color: Color.black.opacity(0.5), location: 0.94),
                                    .init(color: Color.clear, location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 18)
                        }
                    )
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            
            // Floating tags overlay
            if FeatureFlags.tagsEnabled && !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(note.tags.prefix(3)), id: \.self) { tag in
                        TagView(tag: tag)
                    }
                    Spacer()
                }
                .padding(.bottom, 6)
            }
        }
            .padding(12)
            .frame(width: 222, height: 182)
            .background(Color("CardBackgroundColor"))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(
                color: Color.black.opacity(0.02),
                radius: 19,
                x: 0,
                y: 9
            )
            .shadow(
                color: Color.black.opacity(0.02),
                radius: 35,
                x: 0,
                y: 35
            )
            .shadow(
                color: Color.black.opacity(0.01),
                radius: 78,
                x: 0,
                y: 78
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.bouncy(duration: 0.3)) {
                isHovering = hovering
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
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM"
        return formatter
    }
}

// Tag Component for NoteCard thumbnails
struct TagView: View {
    let tag: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(FontManager.heading(size: 10, weight: .regular))
                .foregroundColor(Color("TagTextColor"))

            Text(tag)
                .font(FontManager.heading(size: 12, weight: .medium))
                .foregroundColor(Color("TagTextColor"))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Color("TagBackgroundColor"), in: Capsule())
    }
}
