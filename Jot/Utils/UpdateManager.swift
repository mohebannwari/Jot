import Combine
import Foundation
import Sparkle
import SwiftUI

/// Production update manager powered by Sparkle 2.
/// Checks for updates in the background, downloads silently, and surfaces the
/// UpdatePanelView when a new version is ready. The user decides when to relaunch.
@MainActor
final class UpdateManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var isUpdateAvailable: Bool = false
    @Published private(set) var isDownloading: Bool = false
    @Published private(set) var updateVersion: String = ""
    /// Shown in the command palette after the user taps "Remind me later" on the relaunch panel.
    @Published private(set) var deferredInstallReminderVersion: String?
    @Published var showUpToDateAlert: Bool = false
    @Published var showUpdateErrorAlert: Bool = false

    // MARK: - Private State

    private let updater: SPUUpdater
    private let driverBridge: UserDriverBridge
    fileprivate var replyHandler: ((SPUUserUpdateChoice) -> Void)?
    private var checkForUpdatesObserver: AnyCancellable?

    private static let remindLaterKey = "SparkleRemindLaterTimestamp"
    private static let deferredInstallVersionKey = "SparkleDeferredInstallVersion"
    private static let suppressInterval: TimeInterval = 4 * 60 * 60 // 4 hours

    // MARK: - Init

    override init() {
        let bridge = UserDriverBridge()

        self.driverBridge = bridge
        self.updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: bridge,
            delegate: nil
        )

        super.init()
        bridge.owner = self

        deferredInstallReminderVersion = UserDefaults.standard.string(forKey: Self.deferredInstallVersionKey)

        do {
            try updater.start()
        } catch {
            // Non-fatal: app works without updates
        }

        // Listen for menu bar "Check for Updates" trigger
        checkForUpdatesObserver = NotificationCenter.default
            .publisher(for: AppCommand.Kind.checkForUpdates.name)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkForUpdates()
            }
    }

    // MARK: - Public API

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    func relaunch() {
        clearDeferredInstallReminder()

        // 1. Force autosave so no user data is lost
        NotificationCenter.default.post(.forceSaveNote)

        // 2. Brief delay for SwiftData WAL flush, then tell Sparkle to install
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            self.replyHandler?(.install)
            self.replyHandler = nil
        }
    }

    func remindLater() {
        UserDefaults.standard.set(Date(), forKey: Self.remindLaterKey)
        if !updateVersion.isEmpty {
            UserDefaults.standard.set(updateVersion, forKey: Self.deferredInstallVersionKey)
            deferredInstallReminderVersion = updateVersion
        }
        replyHandler?(.dismiss)
        replyHandler = nil

        withAnimation(.jotSpring) {
            isUpdateAvailable = false
        }
    }

    /// User chose "install" from the global search palette after deferring the sidebar panel.
    func resumeDeferredUpdateFromCommandPalette() {
        guard deferredInstallReminderVersion != nil else { return }
        checkForUpdates()
    }

    private func clearDeferredInstallReminder() {
        UserDefaults.standard.removeObject(forKey: Self.deferredInstallVersionKey)
        deferredInstallReminderVersion = nil
    }

    // MARK: - Internal (called by UserDriverBridge)

    fileprivate func handleUpdateFound(version: String, userInitiated: Bool, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Only suppress background checks -- user-initiated checks always show the panel
        if !userInitiated,
           let stored = UserDefaults.standard.object(forKey: Self.remindLaterKey) as? Date,
           Date().timeIntervalSince(stored) < Self.suppressInterval {
            reply(.dismiss)
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.remindLaterKey)
        clearDeferredInstallReminder()

        replyHandler = reply
        withAnimation(.jotSpring) {
            updateVersion = version
            isDownloading = true
        }
    }

    fileprivate func handleUpdateReady(reply: @escaping (SPUUserUpdateChoice) -> Void) {
        replyHandler = reply
        withAnimation(.jotSpring) {
            isDownloading = false
            isUpdateAvailable = true
        }
    }

    fileprivate func handleUpdateDismissed() {
        // Do not clear `deferredInstallReminderVersion` here — "Remind me later" dismisses
        // the flow but the palette should keep offering the deferred install row.
        withAnimation(.jotSpring) {
            isUpdateAvailable = false
            isDownloading = false
        }
        replyHandler = nil
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }
}

// MARK: - UserDriverBridge

/// Lightweight SPUUserDriver implementation that forwards Sparkle lifecycle events
/// to UpdateManager. Needed because SPUUpdater requires a userDriver at init time,
/// before UpdateManager.self is fully constructed.
@MainActor
private final class UserDriverBridge: NSObject, SPUUserDriver {
    weak var owner: UpdateManager?

    // MARK: - Permission Request

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Auto-approve update permission checks
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    // MARK: - User-Initiated Check

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        // No spinner UI -- silent
    }

    // MARK: - Update Found

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = appcastItem.displayVersionString
        owner?.handleUpdateFound(version: version, userInitiated: state.userInitiated, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // No release notes UI
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    // MARK: - No Update / Errors

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        owner?.showUpToDateAlert = true
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        owner?.showUpdateErrorAlert = true
    }

    // MARK: - Download Progress (silent)

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        // Downloading state already set via handleUpdateFound
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    // MARK: - Extraction (silent)

    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}

    // MARK: - Ready to Install

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        owner?.handleUpdateReady(reply: reply)
    }

    // MARK: - Installing

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        // Autosave already fired in relaunch(). Let Sparkle proceed.
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    // MARK: - Dismiss

    func dismissUpdateInstallation() {
        owner?.handleUpdateDismissed()
    }
}
