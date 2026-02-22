//
//  ExportFormatSheet.swift
//  Jot
//
//  Export format selection sheet — three horizontal pills, liquid glass container.
//

import SwiftUI

struct ExportFormatSheet: View {
    @Binding var isPresented: Bool
    let notes: [Note]
    var onExport: (([Note], NoteExportFormat) -> Void)?

    @State private var selectedFormat: NoteExportFormat = .pdf

    var body: some View {
        VStack(spacing: 16) {
            formatRow
            buttonSection
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .frame(width: 357)
    }

    // MARK: - Format Row

    private var formatRow: some View {
        HStack(spacing: 4) {
            ForEach(NoteExportFormat.allCases) { format in
                FormatPillButton(
                    format: format,
                    isSelected: selectedFormat == format
                ) {
                    HapticManager.shared.buttonTap()
                    withAnimation(.jotBounce) {
                        selectedFormat = format
                    }
                }
            }
        }
    }

    // MARK: - Buttons

    private var buttonSection: some View {
        VStack(spacing: 8) {
            Button {
                handleExport()
            } label: {
                Text("Export")
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(Color("ButtonPrimaryBgColor"))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .subtleHoverScale(1.02)

            Button {
                HapticManager.shared.buttonTap()
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(Color("PrimaryTextColor"))
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .subtleHoverScale(1.02)
        }
    }

    // MARK: - Helpers

    private func handleExport() {
        HapticManager.shared.buttonTap()
        isPresented = false
        let format = selectedFormat
        let exportNotes = notes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onExport?(exportNotes, format)
        }
    }
}

// MARK: - Format Pill Button

private struct FormatPillButton: View {
    let format: NoteExportFormat
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var pillBackground: Color {
        colorScheme == .light ? .white : Color("bg/secondary")
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(format.iconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("IconSecondaryColor"))
                    .frame(width: 20, height: 20)

                Text(format.rawValue)
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(Color("PrimaryTextColor"))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(pillBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color("SettingsSelectionOrange") : Color.clear,
                        lineWidth: 2.5
                    )
                    .animation(.jotBounce, value: isSelected)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
            .scaleEffect(isHovered ? 1.04 : (isSelected ? 1.02 : 1.0))
            .animation(.jotHover, value: isHovered)
            .animation(.jotBounce, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview {
    ExportFormatSheet(
        isPresented: .constant(true),
        notes: [
            Note(title: "Sample Note", content: "This is a sample note.")
        ]
    )
    .padding(40)
}
