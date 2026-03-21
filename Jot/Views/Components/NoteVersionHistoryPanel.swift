import SwiftUI

struct NoteVersionHistoryPanel: View {
    let noteID: UUID
    @Binding var isPresented: Bool
    let onRestore: (NoteVersion) -> Void

    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var versions: [NoteVersion] = []
    @State private var selectedVersion: NoteVersion?
    @State private var showRestoreConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .opacity(0.3)
            content
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(colorScheme == .light ? Color.white : Color(white: 0.12))
        .onAppear {
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
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.93))
                    )
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                LazyVStack(spacing: 1) {
                    ForEach(versions) { version in
                        versionRow(version)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func versionRow(_ version: NoteVersion) -> some View {
        let isSelected = selectedVersion?.id == version.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedVersion = isSelected ? nil : version
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Version info row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.createdAt, style: .relative)
                            .font(FontManager.heading(size: 13, weight: .medium))
                            .tracking(-0.2)
                            .foregroundColor(Color("PrimaryTextColor"))
                        + Text(" ago")
                            .font(FontManager.heading(size: 13, weight: .medium))
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
                        .rotationEffect(.degrees(isSelected ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Preview + restore (expanded)
                if isSelected {
                    VStack(alignment: .leading, spacing: 8) {
                        // Title preview
                        if !version.title.isEmpty {
                            Text(version.title)
                                .font(FontManager.heading(size: 13, weight: .semibold))
                                .tracking(-0.2)
                                .foregroundColor(Color("PrimaryTextColor"))
                                .lineLimit(1)
                        }

                        // Content preview
                        Text(plainTextPreview(version.content))
                            .font(FontManager.heading(size: 12, weight: .regular))
                            .foregroundColor(Color("SettingsPlaceholderTextColor"))
                            .lineLimit(6)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Restore button
                        Button {
                            selectedVersion = version
                            showRestoreConfirmation = true
                        } label: {
                            Text("Restore This Version")
                                .font(FontManager.heading(size: 12, weight: .medium))
                                .tracking(-0.2)
                                .foregroundColor(colorScheme == .light ? Color.white : Color.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .light ? Color.black : Color.white)
                                )
                        }
                        .buttonStyle(.plain)
                        .macPointingHandCursor()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                        ? (colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
                        : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .alert("Restore Version", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                if let version = selectedVersion {
                    onRestore(version)
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

    private func plainTextPreview(_ content: String) -> String {
        // Strip markup tags for preview
        var text = content
        let patterns = [
            #"\[\[/?[a-z0-9:]+(?:\|[^\]]*?)?\]\]"#,  // [[tag]] and [[tag|value]]
            #"\[[ x]\]"#,                              // [x] [ ] checkboxes
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
