//
//  ExportFormatSheet.swift
//  Jot
//
//  Export format selection sheet with Liquid Glass UI
//

import SwiftUI

struct ExportFormatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    let notes: [Note]
    var onExport: (([Note], NoteExportFormat) -> Void)?

    @State private var selectedFormat: NoteExportFormat = .pdf

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Export Note\(notes.count > 1 ? "s" : "")")
                    .font(FontManager.heading(size: 20, weight: .semibold))
                    .foregroundColor(Color("PrimaryTextColor"))

                if notes.count > 1 {
                    Text("\(notes.count) notes selected")
                        .font(FontManager.body(size: 14, weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Format Selection
            VStack(spacing: 12) {
                ForEach(NoteExportFormat.allCases) { format in
                    FormatButton(
                        format: format,
                        isSelected: selectedFormat == format,
                        action: {
                            HapticManager.shared.buttonTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedFormat = format
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Export Button
            Button {
                handleExport()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(FontManager.icon(weight: .semibold))

                    Text("Export")
                        .font(FontManager.heading(size: 16, weight: .semibold))
                }
                .foregroundColor(Color("PrimaryTextColor"))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .tintedLiquidGlass(
                    in: RoundedRectangle(cornerRadius: 16),
                    tint: Color("SurfaceTranslucentColor")
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Cancel Button
            Button {
                HapticManager.shared.buttonTap()
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(FontManager.heading(size: 16, weight: .semibold))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .tintedLiquidGlass(
                        in: RoundedRectangle(cornerRadius: 16),
                        tint: Color("SurfaceTranslucentColor").opacity(0.5),
                        strokeOpacity: 0.04
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 400)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(
            color: Color.black.opacity(0.12),
            radius: 24,
            x: 0,
            y: 12
        )
    }

    private func handleExport() {
        HapticManager.shared.buttonTap()

        isPresented = false

        let format = selectedFormat
        let exportNotes = notes

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onExport?(exportNotes, format)
        }
    }
}

// MARK: - Format Button Component

struct FormatButton: View {
    let format: NoteExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: format.systemImage)
                    .font(FontManager.icon())
                    .foregroundColor(isSelected ? Color("PrimaryTextColor") : Color("SecondaryTextColor"))
                    .frame(width: 20, height: 20)

                // Format Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(format.rawValue)
                        .font(FontManager.heading(size: 16, weight: .semibold))
                        .foregroundColor(Color("PrimaryTextColor"))

                    Text(formatDescription(for: format))
                        .font(FontManager.body(size: 13, weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                }

                Spacer()

                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? Color.accentColor : Color("TertiaryTextColor").opacity(0.3),
                            lineWidth: 2
                        )
                        .frame(width: 20, height: 20)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .tintedLiquidGlass(
                in: RoundedRectangle(cornerRadius: 16),
                tint: isSelected ? Color.accentColor.opacity(0.08) : Color("SurfaceTranslucentColor"),
                strokeOpacity: isSelected ? 0.2 : 0.06
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDescription(for format: NoteExportFormat) -> String {
        switch format {
        case .pdf:
            return "Portable Document Format with images"
        case .markdown:
            return "Plain text with markdown formatting"
        case .html:
            return "Web page with embedded images"
        }
    }
}

// MARK: - Preview

#Preview {
    ExportFormatSheet(
        isPresented: .constant(true),
        notes: [
            Note(title: "Sample Note", content: "This is a sample note with some content.")
        ]
    )
}
