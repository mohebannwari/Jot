import SwiftUI

struct NoteVersionHistoryPanel: View {
    let noteID: UUID
    @Binding var isPresented: Bool
    @Binding var previewingVersion: NoteVersion?
    let onRestore: (NoteVersion) -> Void

    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var versions: [NoteVersion] = []
    @State private var showRestoreConfirmation = false

    private let panelWidth: CGFloat = 280
    private let panelCornerRadius: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            content

            if previewingVersion != nil {
                bottomActions
            }
        }
        .padding(.horizontal, 8)
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .padding(.vertical, 8)
        .liquidGlass(in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 9.5, x: 0, y: 9)
        .shadow(color: .black.opacity(0.02), radius: 17.5, x: 0, y: 35)
        .shadow(color: .black.opacity(0.01), radius: 23.5, x: 0, y: 78)
        .onAppear {
            loadVersions()
        }
        .onChange(of: noteID) { _, _ in
            previewingVersion = nil
            loadVersions()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Version History")
                .font(FontManager.heading(size: 14, weight: .semibold))
                .tracking(-0.3)
                .foregroundColor(Color("PrimaryTextColor"))

            Spacer()

            Button {
                previewingVersion = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                    .frame(width: 22, height: 22)
                    .thinLiquidGlass(in: Circle())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if versions.isEmpty {
            VStack(spacing: 8) {
                Text("No versions yet")
                    .font(FontManager.heading(size: 14, weight: .medium))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))

                Text("Versions are saved 30 seconds after you stop editing.")
                    .font(FontManager.heading(size: 12, weight: .regular))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(versions) { version in
                        versionRow(version)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func versionRow(_ version: NoteVersion) -> some View {
        let isActive = previewingVersion?.id == version.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                previewingVersion = isActive ? nil : version
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(version.createdAt, style: .relative)
                        .font(FontManager.heading(size: 13, weight: isActive ? .semibold : .medium))
                        .tracking(-0.2)
                        .foregroundColor(Color("PrimaryTextColor"))
                    + Text(" ago")
                        .font(FontManager.heading(size: 13, weight: isActive ? .semibold : .medium))
                        .tracking(-0.2)
                        .foregroundColor(Color("PrimaryTextColor"))

                    Text(version.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(FontManager.heading(size: 11, weight: .regular))
                        .foregroundColor(Color("SettingsPlaceholderTextColor"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive
                        ? (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                        : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        VStack(spacing: 8) {
            Button {
                showRestoreConfirmation = true
            } label: {
                Text("Restore This Version")
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.2)
                    .foregroundColor(colorScheme == .light ? Color.white : Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        Capsule()
                            .fill(colorScheme == .light ? Color.black : Color.white)
                    )
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    previewingVersion = nil
                }
            } label: {
                Text("Back to Current")
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.2)
                    .foregroundColor(Color("PrimaryTextColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        Capsule()
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .alert("Restore Version", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                if let version = previewingVersion {
                    onRestore(version)
                    previewingVersion = nil
                    loadVersions()
                }
            }
        } message: {
            Text("This will replace the current note content with this version. A snapshot of the current content will be saved before restoring.")
        }
    }

    // MARK: - Helpers

    private func loadVersions() {
        versions = NoteVersionManager.shared.versions(for: noteID, in: notesManager.modelContext)
    }
}
