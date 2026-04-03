#if DEBUG
import Combine
import Foundation
import AppKit
import SwiftUI

/// Watches the running app's executable for changes (recompilation) and surfaces
/// an update panel so the user can relaunch at will. DEBUG-only.
@MainActor
final class BuildWatcherManager: ObservableObject {

    // MARK: - Constants

    private static let remindLaterKey = "DevBuildWatcherRemindLaterTimestamp"
    private static let suppressInterval: TimeInterval = 2 * 60 * 60 // 2 hours

    // MARK: - Published State

    @Published private(set) var isUpdateAvailable: Bool = false
    @Published private(set) var buildVersion: String = ""

    // MARK: - Private State

    private var watchSource: DispatchSourceFileSystemObject?
    private var suppressTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Modern Debug app bundles often load code from a sibling `*.debug.dylib`
    /// while `Bundle.main.executableURL` points at a small launcher stub.
    /// Watching the dylib catches incremental rebuilds that do not replace the stub.
    static func watchedBinaryURL(for executableURL: URL) -> URL {
        let debugDylibURL = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent(executableURL.deletingPathExtension().lastPathComponent + ".debug.dylib")

        if FileManager.default.fileExists(atPath: debugDylibURL.path) {
            return debugDylibURL
        }

        return executableURL
    }

    func startWatching() {
        guard watchSource == nil else { return }
        guard let execURL = Bundle.main.executableURL,
              FileManager.default.fileExists(atPath: execURL.path) else { return }

        let watchedURL = Self.watchedBinaryURL(for: execURL)

        let fd = open(watchedURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .link],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleBinaryChanged()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watchSource = source
    }

    func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
    }

    // MARK: - Event Handler

    private func handleBinaryChanged() {
        // The inode may have been replaced (atomic swap). Re-arm on the new file.
        stopWatching()
        defer { startWatching() }

        // Already showing? No-op (prevents rapid-fire duplicate events during a build).
        guard !isUpdateAvailable else { return }

        // Check suppress window from "Remind me later"
        if let stored = UserDefaults.standard.object(forKey: Self.remindLaterKey) as? Date {
            if Date().timeIntervalSince(stored) < Self.suppressInterval {
                return
            }
            UserDefaults.standard.removeObject(forKey: Self.remindLaterKey)
        }

        let version = readVersionFromNewBinary()
        withAnimation(.jotSpring) {
            buildVersion = version
            isUpdateAvailable = true
        }
    }

    // MARK: - Actions

    func remindLater() {
        UserDefaults.standard.set(Date(), forKey: Self.remindLaterKey)
        suppressTask?.cancel()

        withAnimation(.jotSpring) {
            isUpdateAvailable = false
        }

        // Re-surface after the suppress interval expires (even without a new build event)
        suppressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.suppressInterval))
            guard let self, !Task.isCancelled else { return }
            UserDefaults.standard.removeObject(forKey: Self.remindLaterKey)
            withAnimation(.jotSpring) {
                self.isUpdateAvailable = true
            }
        }
    }

    func relaunch() {
        // Force autosave so no user data is lost
        NotificationCenter.default.post(name: .forceSaveNote, object: nil)

        let appPath = Bundle.main.bundleURL.path

        // Spawn a shell that waits for us to die, then opens the fresh binary.
        // /usr/bin/open while we're still running just reactivates us (no-op),
        // so we must exit first. The shell child gets reparented to launchd and
        // survives our termination.
        // Brief delay for SwiftData WAL flush before exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "sleep 0.5 && open \"\(appPath)\""]
            try? task.run()

            exit(0)
        }
    }

    // MARK: - Helpers

    /// Reads the version string from the on-disk Info.plist (which may differ from
    /// the in-memory Bundle.main if the binary was replaced after launch).
    private func readVersionFromNewBinary() -> String {
        guard let execURL = Bundle.main.executableURL else { return "new build" }

        // execURL = .../Jot.app/Contents/MacOS/Jot
        let contentsDir = execURL
            .deletingLastPathComponent()  // -> .../Jot.app/Contents/MacOS/
            .deletingLastPathComponent()  // -> .../Jot.app/Contents/
        let plistURL = contentsDir.appendingPathComponent("Info.plist")

        guard let plist = NSDictionary(contentsOf: plistURL),
              let version = plist["CFBundleShortVersionString"] as? String else {
            return "new build"
        }
        return version
    }

    deinit {
        // Capture by value to avoid actor-isolation violation (deinit is nonisolated)
        let source = watchSource
        let task = suppressTask
        source?.cancel()
        task?.cancel()
    }
}
#endif
