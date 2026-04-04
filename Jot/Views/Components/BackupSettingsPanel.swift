import SwiftUI

struct BackupSettingsPanel: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    @ObservedObject private var backupManager = BackupManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var showRestoreConfirmation = false
    @State private var selectedRestoreURL: URL?
    @State private var availableBackups: [(manifest: BackupManager.BackupManifest, url: URL)] = []
    @State private var backupSucceeded: Bool?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 48) {
                backupsSection
                noteHistorySection
            }
        }
        .onAppear {
            availableBackups = backupManager.listAvailableBackups()
        }
    }

    // MARK: - Backups Section

    private var backupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Backups")

            settingsGroupedCard {
                // Backup folder row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backup location")
                            .font(FontManager.heading(size: 13, weight: .medium))
                            .tracking(-0.5)
                            .foregroundColor(Color("PrimaryTextColor"))

                        if backupManager.isBookmarkStale {
                            Text("Location unavailable -- please re-select")
                                .font(FontManager.heading(size: 11, weight: .regular))
                                .foregroundColor(.red)
                        } else if let name = backupManager.backupFolderName {
                            Text(name)
                                .font(FontManager.heading(size: 11, weight: .regular))
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))
                        } else {
                            Text("No folder selected")
                                .font(FontManager.heading(size: 11, weight: .regular))
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))
                        }
                    }

                    Spacer()

                    Button {
                        backupManager.pickBackupFolder()
                    } label: {
                        Text(backupManager.backupFolderName != nil ? "Change" : "Select")
                            .font(FontManager.heading(size: 12, weight: .medium))
                            .tracking(-0.2)
                            .foregroundColor(Color("PrimaryTextColor"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color("SettingsInnerPillColor"))
                            )
                    }
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                }

                // Frequency picker
                HStack {
                    Text("Auto backup")
                        .font(FontManager.heading(size: 13, weight: .medium))
                        .tracking(-0.5)
                        .foregroundColor(Color("PrimaryTextColor"))

                    Spacer()

                    Menu {
                        ForEach(BackupFrequency.allCases, id: \.self) { freq in
                            Button {
                                themeManager.backupFrequency = freq
                                BackupManager.shared.scheduleAutoBackup(notesManager: notesManager)
                            } label: {
                                if themeManager.backupFrequency == freq {
                                    Label(freq.displayName, systemImage: "checkmark")
                                } else {
                                    Text(freq.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(themeManager.backupFrequency.displayName)
                                .font(FontManager.heading(size: 12, weight: .medium))
                                .tracking(-0.2)
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }

                // Max backups stepper
                HStack {
                    Text("Keep last")
                        .font(FontManager.heading(size: 13, weight: .medium))
                        .tracking(-0.5)
                        .foregroundColor(Color("PrimaryTextColor"))

                    Spacer()

                    HStack(spacing: 0) {
                        Button {
                            if themeManager.backupMaxCount > 1 {
                                themeManager.backupMaxCount -= 1
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Text("\(themeManager.backupMaxCount)")
                            .font(FontManager.heading(size: 12, weight: .medium))
                            .tracking(-0.3)
                            .foregroundColor(Color("PrimaryTextColor"))
                            .frame(minWidth: 16, alignment: .center)

                        Button {
                            if themeManager.backupMaxCount < 50 {
                                themeManager.backupMaxCount += 1
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color("SettingsInnerPillColor"))
                    )
                }
            }

            // Action buttons side by side
            HStack(spacing: 8) {
                if !availableBackups.isEmpty {
                    Menu {
                        ForEach(availableBackups, id: \.url) { backup in
                            Button {
                                selectedRestoreURL = backup.url
                                showRestoreConfirmation = true
                            } label: {
                                VStack {
                                    Text(backup.url.lastPathComponent)
                                    Text("\(backup.manifest.noteCount) notes, \(backup.manifest.folderCount) folders")
                                }
                            }
                        }
                    } label: {
                        Text("Restore")
                            .font(FontManager.heading(size: 12, weight: .medium))
                            .tracking(-0.2)
                            .foregroundColor(Color("PrimaryTextColor"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color("ButtonSecondaryBgColor"), in: Capsule())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }

                Button {
                    backupSucceeded = nil
                    Task {
                        let success = await backupManager.performBackup(notesManager: notesManager)
                        backupSucceeded = success
                        if success {
                            availableBackups = backupManager.listAvailableBackups()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            backupSucceeded = nil
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if backupManager.isBackingUp {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(backupStatusText)
                            .font(FontManager.heading(size: 12, weight: .medium))
                            .tracking(-0.2)
                    }
                    .foregroundColor(colorScheme == .light ? Color.white : Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Capsule()
                            .fill(colorScheme == .light ? Color.black : Color.white)
                    )
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .disabled(backupManager.isBackingUp || backupManager.backupFolderName == nil)
                .opacity(backupManager.backupFolderName == nil ? 0.4 : 1)
            }

            // Last backup metadata
            if let lastDate = backupManager.lastBackupDate {
                (Text("Last backup ")
                    .font(FontManager.heading(size: 11, weight: .regular))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                + Text(lastDate, style: .relative)
                    .font(FontManager.heading(size: 11, weight: .regular))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                + Text(" ago")
                    .font(FontManager.heading(size: 11, weight: .regular))
                    .foregroundColor(Color("SettingsPlaceholderTextColor")))
            }

            // Restore confirmation alert (attached to section VStack)
            Color.clear.frame(height: 0)
                .alert("Restore from Backup", isPresented: $showRestoreConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Restore", role: .destructive) {
                        if let url = selectedRestoreURL {
                            backupManager.restoreBackup(url)
                        }
                    }
                } message: {
                    Text("This will replace all your current notes and folders with the backup. The app will quit -- reopen it to complete the restore. This cannot be undone.")
                }
        }
    }

    // MARK: - Note History Section

    private var noteHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Note history")

            settingsGroupedCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep versions for")
                            .font(FontManager.heading(size: 13, weight: .medium))
                            .tracking(-0.5)
                            .foregroundColor(Color("PrimaryTextColor"))

                        Text("Snapshots are created 30 seconds after you stop editing")
                            .font(FontManager.heading(size: 11, weight: .regular))
                            .foregroundColor(Color("SettingsPlaceholderTextColor"))
                    }

                    Spacer()

                    Menu {
                        ForEach([7, 30, 90, 0], id: \.self) { days in
                            Button {
                                themeManager.versionRetentionDays = days
                            } label: {
                                let label = days == 0 ? "Forever" : "\(days) days"
                                if themeManager.versionRetentionDays == days {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(retentionLabel)
                                .font(FontManager.heading(size: 12, weight: .medium))
                                .tracking(-0.2)
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private var backupStatusText: String {
        if backupManager.isBackingUp {
            return "Backing up..."
        }
        if let success = backupSucceeded {
            return success ? "Done" : "Failed"
        }
        return "Back Up Now"
    }

    private var retentionLabel: String {
        themeManager.versionRetentionDays == 0 ? "Forever" : "\(themeManager.versionRetentionDays) days"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(FontManager.heading(size: 11, weight: .medium))
            .tracking(0)
            .foregroundColor(Color("SettingsPlaceholderTextColor"))
    }

    private func settingsGroupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 18) {
            content()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))
        )
    }
}
