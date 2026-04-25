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

    /// `.default` persists as `"default"` (Charter) for existing users; new installs omit the key and get `.system` (SF Pro).
    var displayName: String {
        switch self {
        case .default: return "Charter"
        case .system: return "SF Pro"
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
    /// Global shortcut to open command palette in meeting “pick a note” mode.
    static let startMeetingSessionHotKeyKey = "StartMeetingSessionHotKey"
    static let quickNotesFolderIDKey = "QuickNotesFolderID"

    // Appearance tint keys
    static let tintHueKey = "AppTintHue"
    static let tintIntensityKey = "AppTintIntensity"
    /// Note detail pane chrome: 0 = opaque paper fill, 1 = strongest Liquid Glass tint (see ContentView).
    static let detailPaneTranslucencyKey = "DetailPaneTranslucency"

    /// Duplicated string literals for `nonisolated` UserDefaults reads (must stay equal to keys above).
    private nonisolated static let tintHueUserDefaultsKey = "AppTintHue"
    private nonisolated static let tintIntensityUserDefaultsKey = "AppTintIntensity"

    static let editorSettingsChangedNotification = Notification.Name("EditorSettingsChanged")

    /// Posted whenever tintHue or tintIntensity changes. NSView overlays
    /// (tabs container, code block chip) that paint neutral-300/neutral-800
    /// surfaces subscribe to this so they can recompute their layer
    /// background colors without depending on the SwiftUI environment.
    static let tintDidChangeNotification = Notification.Name("JotTintDidChange")

    /// Posted when ``detailPaneTranslucency`` changes so AppKit overlays can
    /// refresh gated “paper” shadows without polling UserDefaults.
    static let detailPaneTranslucencyDidChangeNotification = Notification.Name("JotDetailPaneTranslucencyDidChange")

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

    /// Global shortcut: open main window command palette in meeting pick-note state.
    @Published var startMeetingSessionHotKey: QuickNoteHotKey? {
        didSet {
            guard hasFinishedInitialization else { return }
            if let hk = startMeetingSessionHotKey,
               let data = try? JSONEncoder().encode(hk) {
                userDefaults.set(data, forKey: Self.startMeetingSessionHotKeyKey)
            } else {
                userDefaults.removeObject(forKey: Self.startMeetingSessionHotKeyKey)
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
            NotificationCenter.default.post(name: Self.tintDidChangeNotification, object: nil)
        }
    }

    /// Strength of the app-wide tint, 0...1. Zero = no tint (base DetailPaneSurfaceColor),
    /// one = full blend toward the hue-derived target. Defaults to 0 so existing
    /// users see zero visual change on upgrade.
    @Published var tintIntensity: Double {
        didSet {
            guard hasFinishedInitialization else { return }
            userDefaults.set(tintIntensity, forKey: Self.tintIntensityKey)
            NotificationCenter.default.post(name: Self.tintDidChangeNotification, object: nil)
        }
    }

    /// Strength of Liquid Glass / blur translucency on the note detail pane chrome, 0...1.
    /// Zero keeps the historical opaque `tintedPaneSurface` fill (default on upgrade).
    @Published var detailPaneTranslucency: Double {
        didSet {
            guard hasFinishedInitialization else { return }
            userDefaults.set(min(1, max(0, detailPaneTranslucency)), forKey: Self.detailPaneTranslucencyKey)
            NotificationCenter.default.post(
                name: Self.detailPaneTranslucencyDidChangeNotification,
                object: nil
            )
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let savedTheme =
            userDefaults.string(forKey: Self.themeDefaultsKey) ?? AppTheme.system.rawValue
        self.currentTheme = AppTheme(rawValue: savedTheme) ?? .system

        // First launch: no key → SF Pro (`.system`). Persisted `"default"` remains Charter for upgrades.
        let savedBodyFontStyle =
            userDefaults.string(forKey: Self.bodyFontStyleDefaultsKey) ?? BodyFontStyle.system.rawValue
        self.currentBodyFontStyle = BodyFontStyle(rawValue: savedBodyFontStyle) ?? .system

        // Editor text-input niceties default ON to match every other macOS text editor.
        // Must register BEFORE the .bool(forKey:) reads below — .bool returns the registered
        // default when the key is absent, but `false` when no default was registered.
        userDefaults.register(defaults: [
            Self.spellCheckKey: true,
            Self.autocorrectKey: true,
            Self.smartQuotesKey: true,
            Self.smartDashesKey: true,
        ])
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

        let savedDetailPaneTranslucency =
            userDefaults.object(forKey: Self.detailPaneTranslucencyKey) as? Double ?? 0.0
        self.detailPaneTranslucency = min(1, max(0, savedDetailPaneTranslucency))

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

        if let data = userDefaults.data(forKey: Self.startMeetingSessionHotKeyKey),
           let decoded = try? JSONDecoder().decode(QuickNoteHotKey.self, from: data) {
            self.startMeetingSessionHotKey = decoded
        } else {
            self.startMeetingSessionHotKey = .defaultStartMeetingSession
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

    /// Shared hue wash used for pane surfaces and hover tooltips so tint reads
    /// as one family across the app.
    private func tintHueWashTarget(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color(hue: tintHue, saturation: 0.10, brightness: 0.96)
        case .dark:
            return Color(hue: tintHue, saturation: 0.38, brightness: 0.16)
        @unknown default:
            return Color(hue: tintHue, saturation: 0.10, brightness: 0.96)
        }
    }

    /// Blends any semantic base toward the app tint wash. When `tintIntensity == 0`
    /// the base is returned untouched.
    ///
    /// **Availability:** Same rules as `tintedPaneSurface` — perceptual mix on
    /// macOS 15+ / iOS 18+, sRGB blend fallback for older compile targets.
    private func blendTowardAppTintWash(base: Color, colorScheme: ColorScheme) -> Color {
        guard tintIntensity > 0 else { return base }
        let target = tintHueWashTarget(for: colorScheme)
        if #available(macOS 15.0, iOS 18.0, *) {
            return base.mix(with: target, by: tintIntensity, in: .perceptual)
        } else {
            let baseNS = NSColor(base).usingColorSpace(.sRGB) ?? NSColor(base)
            let targetNS = NSColor(target).usingColorSpace(.sRGB) ?? NSColor(target)
            let blended = baseNS.blended(withFraction: CGFloat(tintIntensity), of: targetNS) ?? baseNS
            return Color(nsColor: blended)
        }
    }

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
        blendTowardAppTintWash(base: Color("DetailPaneSurfaceColor"), colorScheme: colorScheme)
    }

    /// Hover tooltip capsule fill: `TooltipBackgroundColor` blended with the
    /// same tint wash as pane surfaces so toolbar and split-view tooltips match
    /// the rest of the chrome.
    func tintedTooltipBackground(for colorScheme: ColorScheme) -> Color {
        blendTowardAppTintWash(base: Color("TooltipBackgroundColor"), colorScheme: colorScheme)
    }

    /// Restore hue + intensity to factory defaults.
    func resetTint() {
        tintHue = 0.55
        tintIntensity = 0.0
    }

    /// SwiftUI helper for the "secondary" surface that sits one layer above
    /// `tintedPaneSurface` in the visual hierarchy — editor block containers
    /// (tabs outer wrapper, code block chip pill, file attachment tags,
    /// callout/code block chrome). Uses a deliberately different target from
    /// `tintedPaneSurface` so that at full intensity the two surfaces remain
    /// visually distinct: slightly more saturated and offset in brightness.
    func tintedBlockContainer(for colorScheme: ColorScheme) -> Color {
        let base = Color("BlockContainerColor")
        guard tintIntensity > 0 else { return base }

        let target: Color
        switch colorScheme {
        case .light:
            target = Color(hue: tintHue, saturation: 0.14, brightness: 0.88)
        case .dark:
            target = Color(hue: tintHue, saturation: 0.45, brightness: 0.22)
        @unknown default:
            target = Color(hue: tintHue, saturation: 0.14, brightness: 0.88)
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

    // MARK: - Tint (AppKit / NSView bridge)

    /// Read the current persisted tint hue directly from UserDefaults.
    /// Safe to call from any thread and from NSView overlays that don't
    /// have access to an @EnvironmentObject ThemeManager reference.
    nonisolated static func currentTintHue() -> Double {
        UserDefaults.standard.object(forKey: tintHueUserDefaultsKey) as? Double ?? 0.55
    }

    /// Read the current persisted tint intensity directly from UserDefaults.
    /// See `currentTintHue()` for rationale.
    nonisolated static func currentTintIntensity() -> Double {
        UserDefaults.standard.object(forKey: tintIntensityUserDefaultsKey) as? Double ?? 0.0
    }

    /// NSColor variant of `tintedBlockContainer(for:)` for AppKit overlays
    /// (TabsContainerOverlayView, CodeBlockOverlayView). Reads the current
    /// tint state from UserDefaults and blends the neutral-300 / neutral-800
    /// base toward the hue-derived target in sRGB.
    ///
    /// The target values mirror the SwiftUI helper so light/dark surfaces
    /// land in the same place visually whether they come from SwiftUI or
    /// AppKit. Base colors (#D4D4D4 / #262626) match the Figma
    /// BlockContainerColor token exactly.
    nonisolated static func tintedBlockContainerNS(isDark: Bool) -> NSColor {
        let base: NSColor = isDark
            ? NSColor(srgbRed: 38/255, green: 38/255, blue: 38/255, alpha: 1)     // #262626 neutral-800
            : NSColor(srgbRed: 212/255, green: 212/255, blue: 212/255, alpha: 1)  // #D4D4D4 neutral-300

        let intensity = currentTintIntensity()
        guard intensity > 0 else { return base }

        let hue = CGFloat(currentTintHue())
        let target: NSColor = isDark
            ? NSColor(hue: hue, saturation: 0.45, brightness: 0.22, alpha: 1)
            : NSColor(hue: hue, saturation: 0.14, brightness: 0.88, alpha: 1)

        let baseSRGB = base.usingColorSpace(.sRGB) ?? base
        let targetSRGB = target.usingColorSpace(.sRGB) ?? target
        return baseSRGB.blended(withFraction: CGFloat(intensity), of: targetSRGB) ?? baseSRGB
    }

    /// NSColor for inline code pill backgrounds in the editor. Same tint **targets** and
    /// intensity contract as `tintedBlockContainerNS`, but the dark base is **neutral-700**
    /// (`#404040`) so small monospace pills read slightly lighter than full block chrome
    /// (neutral-800 `#262626`).
    nonisolated static func tintedInlineCodePillNS(isDark: Bool) -> NSColor {
        let base: NSColor = isDark
            ? NSColor(srgbRed: 64 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1)   // #404040 neutral-700
            : NSColor(srgbRed: 212 / 255, green: 212 / 255, blue: 212 / 255, alpha: 1) // #D4D4D4 neutral-300

        let intensity = currentTintIntensity()
        guard intensity > 0 else { return base }

        let hue = CGFloat(currentTintHue())
        let target: NSColor = isDark
            ? NSColor(hue: hue, saturation: 0.45, brightness: 0.22, alpha: 1)
            : NSColor(hue: hue, saturation: 0.14, brightness: 0.88, alpha: 1)

        let baseSRGB = base.usingColorSpace(.sRGB) ?? base
        let targetSRGB = target.usingColorSpace(.sRGB) ?? target
        return baseSRGB.blended(withFraction: CGFloat(intensity), of: targetSRGB) ?? baseSRGB
    }

    /// NSColor variant of `tintedPaneSurface(for:)` for AppKit overlays (e.g. inline
    /// table horizontal scroll fade) that must match the note detail pane wash.
    /// Reads tint from `UserDefaults.standard` like `tintedBlockContainerNS`.
    ///
    /// Base colors match `DetailPaneSurfaceColor` in the asset catalog (#E5E5E5 light,
    /// #0A0A0A neutral-950 dark + hairline neutral-900 border at consumer). Wash targets mirror `tintHueWashTarget` used by
    /// `blendTowardAppTintWash`. Blending is sRGB like other static bridges; SwiftUI
    /// uses perceptual `Color.mix` on newer OS versions, so colors may diverge slightly
    /// at very high intensity.
    nonisolated static func tintedPaneSurfaceNS(isDark: Bool) -> NSColor {
        let base: NSColor = isDark
            ? NSColor(srgbRed: 10 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1)   // #0A0A0A neutral-950 + hairline neutral-900 border at consumer
            : NSColor(srgbRed: 229 / 255, green: 229 / 255, blue: 229 / 255, alpha: 1) // #E5E5E5 neutral-200

        let intensity = currentTintIntensity()
        guard intensity > 0 else { return base }

        let hue = CGFloat(currentTintHue())
        // Same saturation / brightness as `tintHueWashTarget(for:)`.
        let target: NSColor = isDark
            ? NSColor(hue: hue, saturation: 0.38, brightness: 0.16, alpha: 1)
            : NSColor(hue: hue, saturation: 0.10, brightness: 0.96, alpha: 1)

        let baseSRGB = base.usingColorSpace(.sRGB) ?? base
        let targetSRGB = target.usingColorSpace(.sRGB) ?? target
        return baseSRGB.blended(withFraction: CGFloat(intensity), of: targetSRGB) ?? baseSRGB
    }

    // MARK: - Secondary Button Background Tint

    /// Computes the tinted secondary button background color.
    /// Base: ButtonSecondaryBgColor (#D4D4D4 light / #171717 dark - neutral-900)
    /// Target: Slightly more saturated than block container to maintain visual hierarchy
    func tintedSecondaryButtonBackground(for colorScheme: ColorScheme) -> Color {
        let base = Color("ButtonSecondaryBgColor")
        guard tintIntensity > 0 else { return base }

        let target: Color
        switch colorScheme {
        case .light:
            target = Color(hue: tintHue, saturation: 0.16, brightness: 0.86)
        case .dark:
            target = Color(hue: tintHue, saturation: 0.48, brightness: 0.24)
        @unknown default:
            target = Color(hue: tintHue, saturation: 0.16, brightness: 0.86)
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

    /// NSColor variant of `tintedSecondaryButtonBackground(for:)` for AppKit overlays.
    nonisolated static func tintedSecondaryButtonBackgroundNS(isDark: Bool) -> NSColor {
        let base: NSColor = isDark
            ? NSColor(srgbRed: 23/255, green: 23/255, blue: 23/255, alpha: 1)     // #171717 neutral-900
            : NSColor(srgbRed: 212/255, green: 212/255, blue: 212/255, alpha: 1)  // #D4D4D4 neutral-300

        let intensity = currentTintIntensity()
        guard intensity > 0 else { return base }

        let hue = CGFloat(currentTintHue())
        let target: NSColor = isDark
            ? NSColor(hue: hue, saturation: 0.48, brightness: 0.24, alpha: 1)
            : NSColor(hue: hue, saturation: 0.16, brightness: 0.86, alpha: 1)

        let baseSRGB = base.usingColorSpace(.sRGB) ?? base
        let targetSRGB = target.usingColorSpace(.sRGB) ?? target
        return baseSRGB.blended(withFraction: CGFloat(intensity), of: targetSRGB) ?? baseSRGB
    }

    // MARK: - Settings Inner Pill Tint

    /// Computes the tinted settings inner pill color.
    /// Base: SettingsInnerPillColor (#E5E5E5 light / #000000 pure black dark + hairline neutral-900 border at consumer)
    func tintedSettingsInnerPill(for colorScheme: ColorScheme) -> Color {
        let base = Color("SettingsInnerPillColor")
        guard tintIntensity > 0 else { return base }

        let target: Color
        switch colorScheme {
        case .light:
            target = Color(hue: tintHue, saturation: 0.12, brightness: 0.90)
        case .dark:
            target = Color(hue: tintHue, saturation: 0.42, brightness: 0.20)
        @unknown default:
            target = Color(hue: tintHue, saturation: 0.12, brightness: 0.90)
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

    // MARK: - Detail Pane Color Tint

    /// Computes the tinted detail pane color.
    /// Base: DetailPaneColor (#E5E5E5 light / #0A0A0A neutral-950 dark + hairline neutral-900 border at consumer)
    func tintedDetailPane(for colorScheme: ColorScheme) -> Color {
        let base = Color("DetailPaneColor")
        guard tintIntensity > 0 else { return base }

        let target: Color
        switch colorScheme {
        case .light:
            target = Color(hue: tintHue, saturation: 0.10, brightness: 0.92)
        case .dark:
            target = Color(hue: tintHue, saturation: 0.35, brightness: 0.14)
        @unknown default:
            target = Color(hue: tintHue, saturation: 0.10, brightness: 0.92)
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
