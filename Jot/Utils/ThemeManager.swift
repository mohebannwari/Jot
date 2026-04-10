//
//  ThemeManager.swift
//  Jot
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI
import Combine

import AppKit

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum BodyFontStyle: String, CaseIterable {
    case `default` = "default"
    case system = "system"
    case mono = "mono"

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .system: return "System"
        case .mono: return "Mono"
        }
    }
}

enum LineSpacing: String, CaseIterable {
    case compact = "compact"
    case `default` = "default"
    case relaxed = "relaxed"

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .default: return "Default"
        case .relaxed: return "Relaxed"
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .compact: return 1.0
        case .default: return 1.2
        case .relaxed: return 1.5
        }
    }
}

enum NoteSortOrder: String, CaseIterable {
    case dateEdited = "dateEdited"
    case dateCreated = "dateCreated"
    case title = "title"

    var displayName: String {
        switch self {
        case .dateEdited: return "Date Edited"
        case .dateCreated: return "Date Created"
        case .title: return "Title"
        }
    }
}

enum BackupFrequency: String, CaseIterable {
    case manual = "manual"
    case daily = "daily"
    case weekly = "weekly"

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

enum LockPasswordType: String, CaseIterable {
    case login = "login"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .login: return "Use Login Password"
        case .custom: return "Use Custom Password"
        }
    }
}

final class ThemeManager: ObservableObject {
    static let themeDefaultsKey = "AppTheme"
    static let bodyFontStyleDefaultsKey = "AppBodyFontStyle"
    static let spellCheckKey = "EditorSpellCheck"
    static let autocorrectKey = "EditorAutocorrect"
    static let smartQuotesKey = "EditorSmartQuotes"
    static let smartDashesKey = "EditorSmartDashes"
    static let lineSpacingKey = "EditorLineSpacing"
    static let fontSizeKey = "EditorFontSize"
    static let noteSortOrderKey = "NoteSortOrder"
    static let groupNotesByDateKey = "GroupNotesByDate"
    static let resumeToLastQuickNoteKey = "ResumeToLastQuickNote"
    static let autoSortCheckedItemsKey = "AutoSortCheckedItems"
    static let useTouchIDKey = "LockedNotesUseTouchID"
    static let lockPasswordTypeKey = "LockPasswordType"

    // Backup & versioning keys
    static let backupFolderBookmarkKey = "BackupFolderBookmark"
    static let backupFrequencyKey = "BackupFrequency"
    static let backupMaxCountKey = "BackupMaxCount"
    static let lastBackupDateKey = "LastBackupDate"
    static let versionRetentionDaysKey = "VersionRetentionDays"

    // Quick Notes feature keys
    static let quickNoteHotKeyKey = "QuickNoteHotKey"
    static let quickNotesFolderIDKey = "QuickNotesFolderID"

    // Appearance tint keys
    static let tintHueKey = "AppTintHue"
    static let tintIntensityKey = "AppTintIntensity"

    static let editorSettingsChangedNotification = Notification.Name("EditorSettingsChanged")

    private let userDefaults: UserDefaults
    private var appearanceObserver: NSKeyValueObservation?

    /// True once `init` has finished assigning all properties. `@Published`
    /// property wrappers route assignments through their setter, which fires
    /// `didSet` even during init — so observers that persist to UserDefaults
    /// must guard on this flag to avoid writing factory defaults on first
    /// launch (which would then pin the value across in-code default changes).
    private var hasFinishedInitialization = false

    @Published var currentTheme: AppTheme {
        didSet {
            userDefaults.set(currentTheme.rawValue, forKey: Self.themeDefaultsKey)
            applyAppKitAppearance(currentTheme)
            updateResolvedColorScheme()
        }
    }

    /// Always non-nil — resolves "system" to the actual system scheme.
    /// Use this for `preferredColorScheme` instead of passing nil.
    @Published private(set) var resolvedColorScheme: ColorScheme = .light

    @Published var currentBodyFontStyle: BodyFontStyle {
        didSet {
            userDefaults.set(currentBodyFontStyle.rawValue, forKey: Self.bodyFontStyleDefaultsKey)
            FontManager.invalidateFontCache()
            RichTextSerializer.invalidateCaches()
            notifyEditorSettingsChanged()
        }
    }

    @Published var spellCheckEnabled: Bool {
        didSet {
            userDefaults.set(spellCheckEnabled, forKey: Self.spellCheckKey)
            notifyEditorSettingsChanged()
        }
    }

    @Published var autocorrectEnabled: Bool {
        didSet {
            userDefaults.set(autocorrectEnabled, forKey: Self.autocorrectKey)
            notifyEditorSettingsChanged()
        }
    }

    @Published var smartQuotesEnabled: Bool {
        didSet {
            userDefaults.set(smartQuotesEnabled, forKey: Self.smartQuotesKey)
            notifyEditorSettingsChanged()
        }
    }

    @Published var smartDashesEnabled: Bool {
        didSet {
            userDefaults.set(smartDashesEnabled, forKey: Self.smartDashesKey)
            notifyEditorSettingsChanged()
        }
    }

    @Published var lineSpacing: LineSpacing {
        didSet {
            userDefaults.set(lineSpacing.rawValue, forKey: Self.lineSpacingKey)
            notifyEditorSettingsChanged()
        }
    }

    @Published var bodyFontSize: CGFloat {
        didSet {
            userDefaults.set(bodyFontSize, forKey: Self.fontSizeKey)
            notifyEditorSettingsChanged()
        }
    }

    @Published var noteSortOrder: NoteSortOrder {
        didSet {
            userDefaults.set(noteSortOrder.rawValue, forKey: Self.noteSortOrderKey)
        }
    }

    @Published var groupNotesByDate: Bool {
        didSet {
            userDefaults.set(groupNotesByDate, forKey: Self.groupNotesByDateKey)
        }
    }

    @Published var resumeToLastQuickNote: Bool {
        didSet {
            userDefaults.set(resumeToLastQuickNote, forKey: Self.resumeToLastQuickNoteKey)
        }
    }

    @Published var autoSortCheckedItems: Bool {
        didSet {
            userDefaults.set(autoSortCheckedItems, forKey: Self.autoSortCheckedItemsKey)
        }
    }

    @Published var useTouchID: Bool {
        didSet {
            userDefaults.set(useTouchID, forKey: Self.useTouchIDKey)
        }
    }

    @Published var lockPasswordType: LockPasswordType {
        didSet {
            userDefaults.set(lockPasswordType.rawValue, forKey: Self.lockPasswordTypeKey)
        }
    }

    // Backup & versioning settings
    @Published var backupFrequency: BackupFrequency {
        didSet {
            userDefaults.set(backupFrequency.rawValue, forKey: Self.backupFrequencyKey)
        }
    }

    @Published var backupMaxCount: Int {
        didSet {
            userDefaults.set(backupMaxCount, forKey: Self.backupMaxCountKey)
        }
    }

    @Published var versionRetentionDays: Int {
        didSet {
            userDefaults.set(versionRetentionDays, forKey: Self.versionRetentionDaysKey)
        }
    }

    // Quick Notes: user-configurable global hotkey. The companion
    // quickNotesFolderIDKey is owned by QuickNoteService directly — no
    // ThemeManager mirror because nothing in the UI binds to it and a
    // mirrored copy would just be one more thing to keep in sync.
    @Published var quickNoteHotKey: QuickNoteHotKey? {
        didSet {
            guard hasFinishedInitialization else { return }
            if let hk = quickNoteHotKey,
               let data = try? JSONEncoder().encode(hk) {
                userDefaults.set(data, forKey: Self.quickNoteHotKeyKey)
            } else {
                userDefaults.removeObject(forKey: Self.quickNoteHotKeyKey)
            }
        }
    }

    /// Hue of the app-wide tint, 0...1 (maps to 0...360 degrees).
    /// Defaults to 0.55 (blue-ish) on first launch so the rainbow picker
    /// thumb lands somewhere pleasant — but `tintIntensity = 0` means
    /// this value has no visual effect until the user slides intensity up.
    @Published var tintHue: Double {
        didSet {
            guard hasFinishedInitialization else { return }
            userDefaults.set(tintHue, forKey: Self.tintHueKey)
        }
    }

    /// Strength of the app-wide tint, 0...1. Zero = no tint (base DetailPaneSurfaceColor),
    /// one = full blend toward the hue-derived target. Defaults to 0 so existing
    /// users see zero visual change on upgrade.
    @Published var tintIntensity: Double {
        didSet {
            guard hasFinishedInitialization else { return }
            userDefaults.set(tintIntensity, forKey: Self.tintIntensityKey)
        }
    }


    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let savedTheme =
            userDefaults.string(forKey: Self.themeDefaultsKey) ?? AppTheme.system.rawValue
        self.currentTheme = AppTheme(rawValue: savedTheme) ?? .system

        let savedBodyFontStyle =
            userDefaults.string(forKey: Self.bodyFontStyleDefaultsKey) ?? BodyFontStyle.default.rawValue
        self.currentBodyFontStyle = BodyFontStyle(rawValue: savedBodyFontStyle) ?? .default

        self.spellCheckEnabled = userDefaults.bool(forKey: Self.spellCheckKey)
        self.autocorrectEnabled = userDefaults.bool(forKey: Self.autocorrectKey)
        self.smartQuotesEnabled = userDefaults.bool(forKey: Self.smartQuotesKey)
        self.smartDashesEnabled = userDefaults.bool(forKey: Self.smartDashesKey)

        let savedLineSpacing = userDefaults.string(forKey: Self.lineSpacingKey) ?? LineSpacing.default.rawValue
        self.lineSpacing = LineSpacing(rawValue: savedLineSpacing) ?? .default

        let savedFontSize = userDefaults.object(forKey: Self.fontSizeKey) as? CGFloat
        self.bodyFontSize = savedFontSize ?? 16

        // Tint: read as Optional<Double> so "never set" is distinguishable
        // from "explicitly 0", and we can apply explicit defaults only on
        // first launch.
        let savedTintHue = userDefaults.object(forKey: Self.tintHueKey) as? Double
        self.tintHue = savedTintHue ?? 0.55
        let savedTintIntensity = userDefaults.object(forKey: Self.tintIntensityKey) as? Double
        self.tintIntensity = savedTintIntensity ?? 0.0

        let savedSortOrder = userDefaults.string(forKey: Self.noteSortOrderKey) ?? NoteSortOrder.dateEdited.rawValue
        self.noteSortOrder = NoteSortOrder(rawValue: savedSortOrder) ?? .dateEdited

        // Bool defaults: true when not yet set
        userDefaults.register(defaults: [
            Self.groupNotesByDateKey: true,
            Self.resumeToLastQuickNoteKey: true,
            Self.autoSortCheckedItemsKey: true,
            Self.useTouchIDKey: false,
        ])
        self.groupNotesByDate = userDefaults.bool(forKey: Self.groupNotesByDateKey)
        self.resumeToLastQuickNote = userDefaults.bool(forKey: Self.resumeToLastQuickNoteKey)
        self.autoSortCheckedItems = userDefaults.bool(forKey: Self.autoSortCheckedItemsKey)
        self.useTouchID = userDefaults.bool(forKey: Self.useTouchIDKey)

        let savedLockType = userDefaults.string(forKey: Self.lockPasswordTypeKey) ?? LockPasswordType.login.rawValue
        self.lockPasswordType = LockPasswordType(rawValue: savedLockType) ?? .login

        let savedBackupFrequency = userDefaults.string(forKey: Self.backupFrequencyKey) ?? BackupFrequency.manual.rawValue
        self.backupFrequency = BackupFrequency(rawValue: savedBackupFrequency) ?? .manual

        userDefaults.register(defaults: [
            Self.backupMaxCountKey: 5,
            Self.versionRetentionDaysKey: 30,
        ])
        self.backupMaxCount = userDefaults.integer(forKey: Self.backupMaxCountKey)
        self.versionRetentionDays = userDefaults.integer(forKey: Self.versionRetentionDaysKey)

        // Quick Notes: hotkey defaults to the factory default on first launch.
        // The inbox folder ID is owned by QuickNoteService directly via
        // userDefaults; no ThemeManager mirror.
        if let data = userDefaults.data(forKey: Self.quickNoteHotKeyKey),
           let decoded = try? JSONDecoder().decode(QuickNoteHotKey.self, from: data) {
            self.quickNoteHotKey = decoded
        } else {
            self.quickNoteHotKey = .default
        }

        // didSet doesn't fire during init for plain stored properties — apply
        // those side effects manually. Property-wrapper-backed @Published
        // properties have the OPPOSITE behavior (didSet fires even in init),
        // which is why hasFinishedInitialization guards their persistence
        // observers above. Setting the flag here completes init.
        applyAppKitAppearance(self.currentTheme)
        resolvedColorScheme = Self.resolveColorScheme(for: self.currentTheme)
        hasFinishedInitialization = true

        // Track system appearance changes so "System" mode stays in sync
        appearanceObserver = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateResolvedColorScheme()
            }
        }
    }

    func toggleTheme() {
        currentTheme = (currentTheme == .light) ? .dark : .light
    }

    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }

    func setBodyFontStyle(_ bodyFontStyle: BodyFontStyle) {
        currentBodyFontStyle = bodyFontStyle
    }

    // MARK: - Tint

    /// Computes the app-wide pane surface color by blending the base
    /// `DetailPaneSurfaceColor` asset toward a hue-derived target in perceptual
    /// color space. The target is chosen based on the passed `colorScheme` so
    /// that light mode reads as a pastel wash and dark mode reads as a deeper
    /// saturated wash.
    ///
    /// When `tintIntensity == 0` the base color is returned untouched — this
    /// is the zero-regression fast path that keeps the app visually identical
    /// to its pre-tint appearance for users who never touch the slider.
    ///
    /// **Availability:** `Color.mix(with:by:in:)` is macOS 15+ / iOS 18+. The
    /// main Jot app targets macOS 26, but some auxiliary targets (tests,
    /// helpers) target 14.0 and compile this file too, so we gate on availability
    /// and fall back to `NSColor.blended(withFraction:of:)` on older platforms.
    /// The fallback does RGB (not perceptual) blending — acceptable because the
    /// fallback path never renders a production surface.
    func tintedPaneSurface(for colorScheme: ColorScheme) -> Color {
        let base = Color("DetailPaneSurfaceColor")
        guard tintIntensity > 0 else { return base }

        let target: Color
        switch colorScheme {
        case .light:
            target = Color(hue: tintHue, saturation: 0.10, brightness: 0.96)
        case .dark:
            target = Color(hue: tintHue, saturation: 0.38, brightness: 0.16)
        @unknown default:
            target = Color(hue: tintHue, saturation: 0.10, brightness: 0.96)
        }

        if #available(macOS 15.0, iOS 18.0, *) {
            return base.mix(with: target, by: tintIntensity, in: .perceptual)
        } else {
            let baseNS = NSColor(base).usingColorSpace(.sRGB) ?? NSColor(base)
            let targetNS = NSColor(target).usingColorSpace(.sRGB) ?? NSColor(target)
            let blended = baseNS.blended(withFraction: CGFloat(tintIntensity), of: targetNS) ?? baseNS
            return Color(nsColor: blended)
        }
    }

    /// Restore hue + intensity to factory defaults.
    func resetTint() {
        tintHue = 0.55
        tintIntensity = 0.0
    }

    // MARK: - Private

    private func applyAppKitAppearance(_ theme: AppTheme) {
        switch theme {
        case .system:
            NSApp?.appearance = nil
        case .light:
            NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func updateResolvedColorScheme() {
        let resolved = Self.resolveColorScheme(for: currentTheme)
        if resolvedColorScheme != resolved {
            resolvedColorScheme = resolved
        }
    }

    private static func resolveColorScheme(for theme: AppTheme) -> ColorScheme {
        switch theme {
        case .system:
            let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func notifyEditorSettingsChanged() {
        // Bust caches before notifying — font size and line spacing both affect serializer output.
        FontManager.invalidateFontCache()
        RichTextSerializer.invalidateCaches()
        NotificationCenter.default.post(name: Self.editorSettingsChangedNotification, object: nil)
    }

    // MARK: - Static Accessors (for non-reactive contexts like NSTextView setup)

    static func currentLineSpacing(userDefaults: UserDefaults = .standard) -> LineSpacing {
        let raw = userDefaults.string(forKey: lineSpacingKey) ?? LineSpacing.default.rawValue
        return LineSpacing(rawValue: raw) ?? .default
    }

    static func currentBodyFontSize(userDefaults: UserDefaults = .standard) -> CGFloat {
        let size = userDefaults.object(forKey: fontSizeKey) as? CGFloat
        return size ?? 16
    }

}
