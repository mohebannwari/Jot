//
//  FloatingSearch.swift
//  Jot
//
//  Created by AI on 08.08.25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// How the main-window command palette opens when `isPresented` becomes true.
enum FloatingSearchOpenIntent: Equatable {
    case commandPaletteRoot
    case startMeetingSessionPickNote
}

// MARK: - Window-level presentation (shared with ContentView)

/// Curves for `isSearchPresented` / `$isPresented` so the scrim, palette, and in-palette `withAnimation` dismiss use one timing — avoids competing transactions that read as a shimmy on open.
enum FloatingSearchOverlayAnimation {
    static let appear = Animation.bouncy(duration: 0.35)
    static let disappear = Animation.snappy(duration: 0.24)
}

/// Extra SwiftUI `.tracking` (points) for **all-caps** monospaced labels in this palette (section
/// headers, footer hints). Mono caps in a compact glass panel read tight without a slight open
/// track; this stays local to global search so sidebar metadata invariants are unchanged.
private let floatingSearchMetadataCapsTracking: CGFloat = 0.55

/// One selectable row in meeting pick mode (current note + recents).
private struct MeetingPickChoice: Identifiable {
    let id: UUID
    let note: Note
    let isCurrentNoteOption: Bool
}

/// One root quick action row used to filter commands while the palette query is non-empty (`activationIndex` matches `activateQuickAction(at:)`).
struct RootQuickActionFilterSpec: Identifiable {
    var id: Int { activationIndex }
    let activationIndex: Int
    let iconName: String
    let title: String
    let isEnabled: Bool
}

/// Catalog of keyword aliases for each root quick action index — title plus common synonyms
/// like "floating panel" for index 1 or "preferences" for index 8. Pure value type so it can
/// be unit-tested without materializing a SwiftUI view.
///
/// Indices 5 (pin), 6 (zen), and 7 (archive) depend on live app state (pin status, zen toggle,
/// whether the note is archived), so those are passed as struct fields rather than read from a
/// view-level `@State`.
struct RootQuickActionKeywordCatalog {
    /// Whether the currently selected note is pinned — flips index 5's primary label between
    /// "Pin Note" and "Unpin Note". Alias terms "Pin" and "Unpin" are always included so either
    /// verb matches regardless of current state.
    let selectedNoteIsPinned: Bool
    /// Whether the app is in zen mode — flips index 6's primary label between "Zen Mode" and
    /// "Exit Zen Mode". Aliases "Zen" and "Focus" are always included.
    let isZenMode: Bool
    /// Current dynamic title for the archive/restore action (depends on selected-note archive
    /// state). Aliases "Archive" and "Restore" are always included so either verb matches.
    let archiveOrRestoreTitle: String
    /// Meeting-session entry points are fully removed when Apple Intelligence is unavailable.
    let meetingNotesEnabled: Bool

    /// Keyword list for the given activation index — title plus common synonyms. Out-of-range
    /// indices return an empty array.
    func keywords(for index: Int) -> [String] {
        switch index {
        case 0:
            return ["New Note"]
        case 1:
            return ["Floating Note", "Quick Note", "Quick Capture", "Floating Panel"]
        case 2:
            guard meetingNotesEnabled else { return [] }
            return ["Start Meeting Session in a Note", "Meeting", "Recording", "Session"]
        case 3:
            return ["New Folder", "Folder"]
        case 4:
            return ["New Split View", "Split View", "Split"]
        case 5:
            return [
                selectedNoteIsPinned ? "Unpin Note" : "Pin Note",
                "Pin",
                "Unpin",
            ]
        case 6:
            return [
                isZenMode ? "Exit Zen Mode" : "Zen Mode",
                "Zen",
                "Focus",
            ]
        case 7:
            return [
                archiveOrRestoreTitle,
                "Archive",
                "Restore",
            ]
        case 8:
            return ["Settings", "Preferences"]
        default:
            return []
        }
    }

    /// True if any alias for this action contains `query` (diacritic- and case-insensitive).
    func matches(index: Int, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        return keywords(for: index).contains { $0.localizedStandardContains(q) }
    }
}

/// Root command palette vs. meeting “pick a note to record” sub-state (Figma 2795:4389).
private enum CommandPaletteMode: Equatable {
    case root
    case meetingPickNote
}

struct FloatingSearch: View {
    @ObservedObject var engine: SearchEngine
    @Binding var isPresented: Bool
    @Binding var openIntent: FloatingSearchOpenIntent
    let onNoteSelected: (Note) -> Void
    /// Opens the note and starts a meeting recording session (command palette meeting flow).
    var onNoteSelectedStartMeeting: (Note) -> Void = { _ in }
    var onFolderSelected: ((Folder) -> Void)? = nil
    var folders: [Folder] = []
    var notes: [Note] = []
    /// Sidebar / list selection — drives Pin vs Unpin row.
    var selectedNote: Note? = nil
    var deferredSparkleUpdateVersion: String? = nil
    var deferredDevRelaunchVersion: String? = nil
    var onToggleSidebar: () -> Void = {}
    var onTogglePin: () -> Void = {}
    /// Archives the selected note when active, or restores it when `isArchived` (same row as command palette).
    var onArchiveOrRestoreSelectedNote: () -> Void = {}
    var onResumeSparkleDeferredUpdate: () -> Void = {}
    var onResumeDevDeferredRelaunch: () -> Void = {}
    /// Matches command-palette Zen (sidebar hidden): meeting header becomes “Exit Zen Mode”.
    var isZenMode: Bool = false

    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var appleIntelligenceService = AppleIntelligenceService.shared
    @State private var searchText = ""
    /// Bumped whenever the palette should (re)capture the native search field’s first responder; drives `FloatingSearchNativeTextField` without spamming retries on every keystroke.
    @State private var commandPaletteNativeFocusGeneration: UInt64 = 0
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchNamespace
    @State private var hoveredResultID: SearchHit.ID?
    @State private var selectedResultIndex: Int = 0
    @State private var paletteMode: CommandPaletteMode = .root
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// Global command palette width (668pt).
    private let surfaceWidth: CGFloat = 668
    private let surfaceCornerRadius: CGFloat = 22
    private let resultItemCornerRadius: CGFloat = 12
    /// Visible root quick actions in palette order (excluding optional deferred-update row).
    private var rootStandardQuickActionCount: Int { visibleRootQuickActionActivationIndices.count }
    /// Shared vertical slot so the magnifier, placeholder/caret, and clear control align (plain TextField has extra cell insets).
    /// On macOS the focused field is edited by AppKit’s field editor, so leave headroom and apply the 1.5pt optical shift inside the native editor rect.
    private let searchFieldLineHeight: CGFloat = 22
    /// Pre–macOS 26 command palette shell fill — same tokens as the tabs block text body
    /// (`TabsContainerOverlayView.blocksColor` / `FloatingEditToolbar.pillBg` / Figma `bg/blocks`).
    private var searchPanelPreGlassFill: Color {
        switch colorScheme {
        case .light:
            Color("SurfaceDefaultColor")
        case .dark:
            Color("DetailPaneColor")
        @unknown default:
            Color("SurfaceDefaultColor")
        }
    }

    /// Tint for internal seams in the command palette — under the search field, between the
    /// quick actions block and LAST SEARCH, above the footer, and between commands/results in
    /// typed-query mode. The app-wide `BorderSubtleColor` at 9% white is swallowed by this
    /// panel's glass backdrop in dark mode, so we bump to ~15% locally. Light mode keeps the
    /// existing token since 9% black already reads well against the surface. Outer panel stroke
    /// and footer keycap separator use their own tokens.
    private var panelDividerColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.15)
        default:
            Color("BorderSubtleColor")
        }
    }

    /// Fill for footer shortcut legend keycaps (chevrons, Return, esc). Light mode stays on
    /// `SurfaceElevatedColor`; dark uses **stone-700** via `InlineCodeBgColor` so the small shells
    /// read slightly above the palette chrome (stone-800), matching the design-system pair in
    /// AGENTS.md / Figma.
    private var floatingSearchFooterKeycapFill: Color {
        switch colorScheme {
        case .dark:
            Color("InlineCodeBgColor")
        case .light:
            Color("SurfaceElevatedColor")
        @unknown default:
            Color("SurfaceElevatedColor")
        }
    }

    private enum SearchAnimations {
        static let appear = FloatingSearchOverlayAnimation.appear
        static let disappear = FloatingSearchOverlayAnimation.disappear
        static let resultHover = Animation.spring(response: 0.25, dampingFraction: 0.86)
        /// Quick actions ↔ meeting note picker: spring paired with symmetric scale+opacity (same in/out; `.slide` is asymmetric and reverses by insert vs remove).
        static let paletteSwap = Animation.spring(duration: 0.38, bounce: 0.28)
    }

    /// Center-scaled crossfade — identical forward/back; avoids `.slide`’s leading/trailing flip when two branches swap.
    private var paletteSwapTransition: AnyTransition {
        if accessibilityReduceMotion {
            .opacity
        } else {
            .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
        }
    }

    private func withPaletteSwapAnimation(_ updates: () -> Void) {
        if accessibilityReduceMotion {
            updates()
        } else {
            withAnimation(SearchAnimations.paletteSwap, updates)
        }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmptyQuery: Bool {
        trimmedSearch.isEmpty
    }

    /// True when typed query has at least one note/folder hit (independent of command filtering).
    private var showResults: Bool {
        !trimmedSearch.isEmpty && !engine.results.isEmpty
    }

    /// Any scrollable hit list below the search field — unified root-mode list OR meeting-pick-note
    /// search. Replaces the legacy `showMixedQueryResults || showNoteSearchResultsOnly` pair.
    private var showResultsPanel: Bool {
        if typedQueryUnifiedListActive { return true }
        return paletteMode == .meetingPickNote && showResults
    }

    /// Full root quick-action list in palette order (for typed-query filtering).
    /// Keep `activationIndex` / titles aligned with `rootStandardQuickActionRows` and `activateQuickAction(at:)`.
    private var allRootQuickActionFilterSpecs: [RootQuickActionFilterSpec] {
        var rows: [RootQuickActionFilterSpec] = [
            RootQuickActionFilterSpec(
                activationIndex: 0, iconName: "IconEditSmall2", title: "New Note", isEnabled: true),
            RootQuickActionFilterSpec(
                activationIndex: 1, iconName: "IconFloatingNote", title: "Floating Note", isEnabled: true),
            RootQuickActionFilterSpec(
                activationIndex: 3, iconName: "IconFolderAddRight", title: "New Folder", isEnabled: true),
            RootQuickActionFilterSpec(
                activationIndex: 4, iconName: "IconSplit", title: "New Split View", isEnabled: true),
            RootQuickActionFilterSpec(
                activationIndex: 5,
                iconName: selectedNote?.isPinned == true ? "IconUnpin" : "IconThumbtack",
                title: selectedNote?.isPinned == true ? "Unpin Note" : "Pin Note",
                isEnabled: selectedNote != nil),
            RootQuickActionFilterSpec(
                activationIndex: 6,
                iconName: "IconZenMode",
                title: isZenMode ? "Exit Zen Mode" : "Zen Mode",
                isEnabled: true),
            RootQuickActionFilterSpec(
                activationIndex: 7,
                iconName: archiveOrRestoreQuickActionIcon,
                title: archiveOrRestoreQuickActionTitle,
                isEnabled: isArchiveOrRestoreQuickActionEnabled),
            RootQuickActionFilterSpec(
                activationIndex: 8, iconName: "IconSettingsGear1", title: "Settings", isEnabled: true),
        ]
        if meetingNotesCapability.showsEntryPoints {
            rows.insert(
                RootQuickActionFilterSpec(
                    activationIndex: 2,
                    iconName: "IconMicrophoneSparkle",
                    title: "Start Meeting Session in a Note",
                    isEnabled: true
                ),
                at: 2
            )
        }
        if hasDeferredUpdateRow {
            rows.append(
                RootQuickActionFilterSpec(
                    activationIndex: deferredUpdateActionActivationIndex,
                    iconName: "IconUpdateDownload",
                    title: "Update App",
                    isEnabled: true))
        }
        return rows
    }

    /// Keyword catalog constructed from live view state — used by the spec filter below so
    /// queries like "Capture" alias onto "Floating Note" the same way the legacy index-filter
    /// did before PR #22's refactor.
    private var rootQuickActionKeywordCatalog: RootQuickActionKeywordCatalog {
        RootQuickActionKeywordCatalog(
            selectedNoteIsPinned: selectedNote?.isPinned == true,
            isZenMode: isZenMode,
            archiveOrRestoreTitle: archiveOrRestoreQuickActionTitle,
            meetingNotesEnabled: meetingNotesCapability.showsEntryPoints
        )
    }

    /// Quick actions whose title or keyword aliases match the trimmed query (enabled rows only).
    private var filteredRootQuickActionSpecs: [RootQuickActionFilterSpec] {
        let q = trimmedSearch
        guard !q.isEmpty else { return [] }
        let catalog = rootQuickActionKeywordCatalog
        return allRootQuickActionFilterSpecs.filter { spec in
            spec.isEnabled && catalog.matches(index: spec.activationIndex, query: q)
        }
    }

    private var typedQueryCommandMatchCount: Int { filteredRootQuickActionSpecs.count }

    private var typedQueryUnifiedRowCount: Int { typedQueryCommandMatchCount + engine.results.count }

    /// Non-empty query in root mode with at least one command match and/or note-folder hit.
    private var typedQueryUnifiedListActive: Bool {
        !isEmptyQuery && paletteMode == .root && typedQueryUnifiedRowCount > 0
    }

    private var typedQueryScrollMaxHeight: CGFloat {
        guard typedQueryUnifiedListActive else { return 0 }
        let hasCommands = typedQueryCommandMatchCount > 0
        let hasNotes = !engine.results.isEmpty
        if hasCommands && hasNotes { return 320 }
        return 280
    }

    /// Sparkle takes precedence over DEBUG build-watcher when both are set.
    private var deferredUpdateRowVersion: String? {
        deferredSparkleUpdateVersion ?? deferredDevRelaunchVersion
    }

    private var deferredUpdateUsesSparkleHandler: Bool {
        deferredSparkleUpdateVersion != nil
    }

    private var hasDeferredUpdateRow: Bool {
        deferredUpdateRowVersion != nil
    }

    private var meetingNotesCapability: MeetingNotesCapability {
        appleIntelligenceService.meetingNotesCapability
    }

    private var visibleRootQuickActionActivationIndices: [Int] {
        (0..<9).filter { activationIndex in
            meetingNotesCapability.showsEntryPoints || activationIndex != 2
        }
    }

    /// LAST SEARCH rows only when that section is visible (root + empty query + history).
    private var paletteHistoryRowCount: Int {
        guard paletteMode == .root, isEmptyQuery, !engine.paletteHistory.isEmpty else { return 0 }
        return engine.paletteHistory.count
    }

    private var deferredUpdateSlotCount: Int {
        hasDeferredUpdateRow ? 1 : 0
    }

    /// Root palette: nine quick actions + optional deferred “Update App” (under Settings) + LAST SEARCH.
    private var rootPaletteSelectableRowCount: Int {
        rootStandardQuickActionCount + deferredUpdateSlotCount + paletteHistoryRowCount
    }

    /// Deferred update row sits immediately after the nine standard quick actions (Figma 2795:4600).
    private var deferredUpdateRowSelectableIndex: Int {
        rootStandardQuickActionCount
    }

    /// Stable activation index for the synthetic deferred-update command row.
    private let deferredUpdateActionActivationIndex = 9

    /// Sidebar selection with fresh `isArchived` / `isPinned` from `notes` when available.
    private var commandPaletteSelectedNote: Note? {
        guard let sel = selectedNote else { return nil }
        return notes.first(where: { $0.id == sel.id }) ?? sel
    }

    private var archiveOrRestoreQuickActionTitle: String {
        commandPaletteSelectedNote?.isArchived == true ? "Restore Note" : "Archive Note"
    }

    private var archiveOrRestoreQuickActionIcon: String {
        commandPaletteSelectedNote?.isArchived == true ? "IconStepBack" : "IconArchive1"
    }

    private var isArchiveOrRestoreQuickActionEnabled: Bool {
        guard let n = commandPaletteSelectedNote else { return false }
        return !n.isDeleted
    }

    /// First selectable index for LAST SEARCH rows (after quick actions + optional update row).
    private var paletteHistorySectionStartIndex: Int {
        rootStandardQuickActionCount + deferredUpdateSlotCount
    }

    /// Meeting pick: optional **current note** row (when one is selected) plus up to five other recents.
    private var meetingPickChoices: [MeetingPickChoice] {
        var rows: [MeetingPickChoice] = []
        if let sel = selectedNote {
            let fresh = notes.first(where: { $0.id == sel.id }) ?? sel
            if !fresh.isDeleted && !fresh.isArchived {
                rows.append(
                    MeetingPickChoice(id: fresh.id, note: fresh, isCurrentNoteOption: true))
            }
        }
        let excluded = Set(rows.map(\.id))
        let active = notes.filter {
            !$0.isDeleted && !$0.isArchived && !excluded.contains($0.id)
        }
        let byRecency = active.sorted { $0.date > $1.date }
        for note in byRecency.prefix(5) {
            rows.append(MeetingPickChoice(id: note.id, note: note, isCurrentNoteOption: false))
        }
        return rows
    }

    private var totalPaletteRows: Int {
        if typedQueryUnifiedListActive {
            return typedQueryUnifiedRowCount
        }
        if showResults { return engine.results.count }
        guard isEmptyQuery else { return 0 }
        if paletteMode == .meetingPickNote {
            return meetingPickChoices.count
        }
        return rootPaletteSelectableRowCount
    }

    private var showLastSearchSection: Bool {
        paletteMode == .root && isEmptyQuery && !engine.paletteHistory.isEmpty
    }

    var body: some View {
        Group {
            if isPresented {
                searchInput
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        // Do not add `.animation(..., value: isPresented)` here: `ContentView` drives one
        // `withAnimation(FloatingSearchOverlayAnimation.*)` for `isSearchPresented` so the scrim and
        // palette share a single transaction.
        .onChange(of: isPresented) { _, newValue in
            handlePresentationChange(newValue)
        }
        .onChange(of: searchText) { _, newValue in
            engine.query = newValue
            selectedResultIndex = 0
        }
        .onChange(of: engine.results) { _, _ in
            selectedResultIndex = 0
        }
        .onChange(of: appleIntelligenceService.meetingNotesCapability.showsEntryPoints) { _, isEnabled in
            guard !isEnabled, paletteMode == .meetingPickNote else { return }
            withPaletteSwapAnimation {
                paletteMode = .root
                selectedResultIndex = 0
                searchText = ""
                engine.query = ""
            }
        }
        .onChange(of: showResultsPanel) { _, isShowing in
            if isShowing {
                hoveredResultID = nil
                selectedResultIndex = 0
            } else {
                hoveredResultID = nil
                selectedResultIndex = min(selectedResultIndex, max(0, totalPaletteRows - 1))
            }
        }
        .onChange(of: paletteMode) { _, _ in
            selectedResultIndex = 0
        }
        .onAppear {
            if isPresented {
                prepareForPresentation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.Kind.floatingSearchSwitchToMeetingPickNote.name)) { _ in
            guard isPresented else { return }
            guard appleIntelligenceService.refreshMeetingNotesCapability().showsEntryPoints else {
                withPaletteSwapAnimation {
                    paletteMode = .root
                    selectedResultIndex = 0
                }
                return
            }
            withPaletteSwapAnimation {
                paletteMode = .meetingPickNote
                selectedResultIndex = 0
                searchText = ""
                engine.query = ""
            }
            kickCommandPaletteNativeSearchFocus()
        }
    }

    // MARK: - Search Surface

    @ViewBuilder
    private var searchInput: some View {
        if #available(macOS 26.0, *) {
            LiquidGlassContainer(spacing: 0) {
                searchSurfaceContent
                    .glassEffect(
                        .regular.interactive(true),
                        in: RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                    )
                    .glassID("floating-search.surface", in: searchNamespace)
                    .frame(width: surfaceWidth)
                    .contentShape(RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
                    #if os(macOS)
                    .onExitCommand {
                        handlePaletteEscapeKey()
                    }
                    #endif
            }
        } else {
            searchSurfaceContent
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                        .fill(searchPanelPreGlassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                        .stroke(Color("BorderSubtleColor"), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .frame(width: surfaceWidth)
                .contentShape(RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
                #if os(macOS)
                .onExitCommand {
                    handlePaletteEscapeKey()
                }
                #endif
        }
    }

    @ViewBuilder
    private var searchSurfaceContent: some View {
        VStack(spacing: 0) {
            searchFieldRow

            if isEmptyQuery {
                quickActionsAndRecentsBlock
            } else if typedQueryUnifiedListActive {
                Rectangle()
                    .fill(panelDividerColor)
                    .frame(height: 0.5)
                typedQueryUnifiedList
                    .frame(maxHeight: typedQueryScrollMaxHeight)
            }

            commandPaletteFooter
        }
        .clipShape(RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
    }

    // MARK: - Input row (Figma inputfield p-16; clear only when typed — IconArrowLeftX)

    private var searchFieldRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image("IconMagnifyingGlass")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(width: 15, height: 15)
                .frame(height: searchFieldLineHeight, alignment: .center)

            searchFieldInput

            if !trimmedSearch.isEmpty {
                Button(action: clearSearchText) {
                    Image("IconArrowLeftX")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("IconSecondaryColor"))
                        .frame(width: 15, height: 15)
                }
                .buttonStyle(.plain)
                .subtleHoverScale(1.06)
                .frame(height: searchFieldLineHeight, alignment: .center)
            }
        }
        // +1 / −1 vs symmetric 16: shifts the whole row down slightly; the native macOS field applies its own 1.5pt editor-rect offset inside the 22pt slot.
        .padding(.horizontal, 16)
        .padding(.top, 17)
        .padding(.bottom, 15)
    }

    @ViewBuilder
    private var searchFieldInput: some View {
        #if os(macOS)
        FloatingSearchNativeTextField(
            text: $searchText,
            isFocused: Binding(
                get: { isSearchFocused },
                set: { isSearchFocused = $0 }
            ),
            focusGeneration: commandPaletteNativeFocusGeneration,
            placeholder: "Search anything…",
            verticalOffset: 1.5,
            onMoveDown: { navigateKeyboard(direction: .down) },
            onMoveUp: { navigateKeyboard(direction: .up) },
            onSubmit: { handleReturnKey() },
            onCancel: { handlePaletteEscapeKey() }
        )
        .frame(height: searchFieldLineHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        // iOS: same 11pt system regular as the macOS `NSTextField` below.
        TextField("Search anything…", text: $searchText)
            .jotUI(FontManager.uiLabel5(weight: .regular, textLeading: .standard))
            .foregroundColor(Color("PrimaryTextColor"))
            .focused($isSearchFocused)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .frame(height: searchFieldLineHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onKeyPress(.downArrow) {
                navigateKeyboard(direction: .down)
                return .handled
            }
            .onKeyPress(.upArrow) {
                navigateKeyboard(direction: .up)
                return .handled
            }
            .onKeyPress(.return) {
                handleReturnKey()
                return .handled
            }
            .onKeyPress(.escape) {
                handlePaletteEscapeKey()
                return .handled
            }
        #endif
    }

    // MARK: - Quick actions + LAST SEARCH (empty query only)

    @ViewBuilder
    private var quickActionsAndRecentsBlock: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(panelDividerColor)
                .frame(height: 0.5)

            Group {
                if paletteMode == .meetingPickNote {
                    meetingPickNoteBlock
                        .transition(paletteSwapTransition)
                } else {
                    rootQuickActionsAndLastSearchBlock
                        .transition(paletteSwapTransition)
                }
            }
        }
    }

    @ViewBuilder
    private var meetingPickNoteBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if isZenMode {
                    Button {
                        onToggleSidebar()
                    } label: {
                        meetingPickNoteHeaderLabel(title: "Exit Zen Mode")
                    }
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                } else {
                    meetingPickNoteHeaderLabel(title: "Start recording in:")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            VStack(spacing: 0) {
                ForEach(Array(meetingPickChoices.enumerated()), id: \.element.id) {
                    offset, choice in
                    meetingPickNoteRow(
                        note: choice.note, index: offset, isCurrentNoteOption: choice.isCurrentNoteOption)
                }
            }
            .padding(8)
        }
    }

    /// Shared meeting-picker header: same leading icon; copy is **mono 11 medium + all caps** (see `jotMetadataLabelTypography()`).
    private func meetingPickNoteHeaderLabel(title: String) -> some View {
        HStack(spacing: 8) {
            Image("IconMeetingNotes")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(width: 15, height: 15)

            Text(title)
                .jotMetadataLabelTypography()
                .tracking(floatingSearchMetadataCapsTracking)
                .foregroundColor(Color("SecondaryTextColor"))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private func meetingPickNoteRow(note: Note, index: Int, isCurrentNoteOption: Bool) -> some View {
        let isSelected = isEmptyQuery && !showResultsPanel && selectedResultIndex == index
        let title =
            note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled" : note.title
        return Button {
            openNoteStartingMeeting(note)
        } label: {
            HStack(spacing: 8) {
                Image("IconNoteText")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 15, height: 15)

                Text(title)
                    .jotUI(FontManager.uiLabel3(weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isCurrentNoteOption {
                    Text("Current Note")
                        .jotMetadataLabelTypography()
                        .tracking(floatingSearchMetadataCapsTracking)
                        .foregroundColor(Color("SecondaryTextColor"))
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule()
                    .fill(Color("HoverBackgroundColor"))
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering, isEmptyQuery, !showResultsPanel {
                selectedResultIndex = index
            }
        }
    }

    @ViewBuilder
    private var rootQuickActionsAndLastSearchBlock: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Figma: quick actions through Settings, then Update App (2795:4600), then LAST SEARCH.
                rootStandardQuickActionRows
                if hasDeferredUpdateRow {
                    deferredUpdateQuickRow(index: deferredUpdateRowSelectableIndex)
                }
            }
            .padding(8)

            if showLastSearchSection {
                Rectangle()
                    .fill(panelDividerColor)
                    .frame(height: 0.5)
                lastSearchSectionContent
            }
        }
    }

    private func deferredUpdateQuickRow(index: Int) -> some View {
        quickActionRow(
            selectionIndex: index,
            activationIndex: deferredUpdateActionActivationIndex,
            iconName: "IconUpdateDownload",
            title: "Update App",
            isEnabled: true,
            trailing: { EmptyView() })
    }

    /// Single root quick action by activation index. Deferred “Update App” uses `deferredUpdateQuickRow` separately.
    @ViewBuilder
    private func rootPaletteQuickActionRow(activationIndex: Int, selectionIndex: Int) -> some View {
        switch activationIndex {
        case 0:
            quickActionRow(
                selectionIndex: selectionIndex,
                activationIndex: activationIndex,
                iconName: "IconEditSmall2",
                title: "New Note",
                isEnabled: true,
                trailing: { sidebarStyleShortcutLabel("\u{2318}N") })
        case 1:
            quickActionRow(
                selectionIndex: selectionIndex,
                activationIndex: activationIndex,
                iconName: "IconFloatingNote",
                title: "Floating Note",
                isEnabled: true,
                trailing: { sidebarStyleShortcutLabel(quickNoteShortcutDisplay) })
        case 2:
            quickActionRow(
                selectionIndex: selectionIndex,
                activationIndex: activationIndex,
                iconName: "IconMicrophoneSparkle",
                title: "Start Meeting Session in a Note",
                isEnabled: true,
                trailing: { sidebarStyleShortcutLabel(startMeetingSessionShortcutDisplay) })
        case 3:
            quickActionRow(
                selectionIndex: selectionIndex,
                activationIndex: activationIndex,
                iconName: "IconFolderAddRight",
                title: "New Folder",
                isEnabled: true,
                trailing: { EmptyView() })
        case 4:
            quickActionRow(
                selectionIndex: selectionIndex,
                activationIndex: activationIndex,
                iconName: "IconSplit",
                title: "New Split View",
                isEnabled: true,
                trailing: { EmptyView() })
        case 5:
            quickActionRow(
                selectionIndex: selectionIndex,
                activationIndex: activationIndex,
                iconName: selectedNote?.isPinned == true ? "IconUnpin" : "IconThumbtack",
                title: selectedNote?.isPinned == true ? "Unpin Note" : "Pin Note",
                isEnabled: selectedNote != nil,
                trailing: { EmptyView() })
        case 6:
            quickActionRow(
                selectionIndex: selectionIndex,
                activationIndex: activationIndex,
                iconName: "IconZenMode",
                // Same wording as meeting-picker header when the sidebar is hidden (⌘. toggles either way).
                title: isZenMode ? "Exit Zen Mode" : "Zen Mode",
                isEnabled: true,
                trailing: { sidebarStyleShortcutLabel("\u{2318}.") })
        case 7:
            quickActionRow(
                selectionIndex: selectionIndex,
                activationIndex: activationIndex,
                iconName: archiveOrRestoreQuickActionIcon,
                title: archiveOrRestoreQuickActionTitle,
                isEnabled: isArchiveOrRestoreQuickActionEnabled,
                trailing: { EmptyView() })
        case 8:
            quickActionRow(
                selectionIndex: selectionIndex,
                activationIndex: activationIndex,
                iconName: "IconSettingsGear1",
                title: "Settings",
                isEnabled: true,
                trailing: { sidebarStyleShortcutLabel("\u{2318},") })
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var rootStandardQuickActionRows: some View {
        ForEach(Array(visibleRootQuickActionActivationIndices.enumerated()), id: \.element) { pair in
            rootPaletteQuickActionRow(
                activationIndex: pair.element,
                selectionIndex: pair.offset
            )
        }
    }

    private func quickActionRow<Trailing: View>(
        selectionIndex: Int,
        activationIndex: Int,
        iconName: String,
        title: String,
        isEnabled: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let isSelected = isEmptyQuery && !showResultsPanel && selectedResultIndex == selectionIndex
        return Button {
            activateQuickAction(at: activationIndex)
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 15, height: 15)

                    // Same token as the template icon (`SecondaryTextColor`) — matches sidebar quick actions.
                    Text(title)
                        .jotUI(FontManager.uiLabel3(weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    trailing()
                }
                .frame(minHeight: 15)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule()
                    .fill(Color("HoverBackgroundColor"))
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering in
            guard hovering, isEnabled else { return }
            if isEmptyQuery, !showResultsPanel {
                selectedResultIndex = selectionIndex
            }
        }
    }

    /// Trailing shortcut glyphs — system regular (proportional), aligned with the rest of the palette.
    private var quickNoteShortcutDisplay: String {
        (themeManager.quickNoteHotKey ?? QuickNoteHotKey.default).displayString
    }

    private var startMeetingSessionShortcutDisplay: String {
        (themeManager.startMeetingSessionHotKey ?? QuickNoteHotKey.defaultStartMeetingSession)
            .displayString
    }

    @ViewBuilder
    private func sidebarStyleShortcutLabel(_ shortcut: String) -> some View {
        Text(shortcut)
            .jotMetadataLabelTypography()
            .foregroundColor(Color("SecondaryTextColor"))
            .lineLimit(1)
    }

    // MARK: - LAST SEARCH (string queries + opened targets)

    @ViewBuilder
    private var lastSearchSectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("LAST SEARCH")
                    .jotMetadataLabelTypography()
                    .tracking(floatingSearchMetadataCapsTracking)
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                clearLastSearchButton
            }
            .padding(8)

            VStack(spacing: 0) {
                ForEach(Array(engine.paletteHistory.enumerated()), id: \.element.id) { offset, entry in
                    let rowIndex = paletteHistorySectionStartIndex + offset
                    if entry.isQuery, let q = entry.queryText {
                        stringRecentRow(query: q, index: rowIndex)
                    } else if let target = entry.openedTarget {
                        openedTargetRow(target: target, index: rowIndex)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .padding(8)
    }

    private var clearLastSearchButton: some View {
        Button {
            engine.clearPaletteHistory()
            selectedResultIndex = 0
        } label: {
            Text("Clear All")
                .jotMetadataLabelTypography()
                .tracking(floatingSearchMetadataCapsTracking)
                .foregroundColor(Color("SecondaryTextColor"))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Clear recent searches")
        .accessibilityLabel("Clear recent searches")
    }

    private func stringRecentRow(query: String, index: Int) -> some View {
        let isSelected = isEmptyQuery && !showResultsPanel && selectedResultIndex == index
        return Button {
            applyRecentQuery(query)
        } label: {
            HStack(spacing: 8) {
                Image("IconNoteText")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 15, height: 15)

                Text(query)
                    .jotUI(FontManager.uiLabel3(weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule()
                    .fill(Color("HoverBackgroundColor"))
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering, isEmptyQuery, !showResultsPanel {
                selectedResultIndex = index
            }
        }
    }

    private func openedTargetRow(target: RecentOpenedSearchTarget, index: Int) -> some View {
        let isSelected = isEmptyQuery && !showResultsPanel && selectedResultIndex == index
        let iconName = target.kind == .folder ? "IconFolder2" : "IconNoteText"
        // Match sidebar: tinted folder icon when the folder has a custom color (LAST SEARCH).
        let leadingIconColor: Color = {
            guard target.kind == .folder,
                let folder = folders.first(where: { $0.id == target.entityID })
            else { return Color("SecondaryTextColor") }
            return folder.folderDisplayColor(for: colorScheme)
        }()
        return Button {
            openRecentTarget(target)
        } label: {
            HStack(spacing: 8) {
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(leadingIconColor)
                    .frame(width: 15, height: 15)

                Text(target.title)
                    .jotUI(FontManager.uiLabel3(weight: .regular))
                    .foregroundColor(leadingIconColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule()
                    .fill(Color("HoverBackgroundColor"))
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering, isEmptyQuery, !showResultsPanel {
                selectedResultIndex = index
            }
        }
    }

    // MARK: - Footer

    private var commandPaletteFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(panelDividerColor)
                .frame(height: 0.5)

            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            footerChevronKeycap(imageName: "IconChevronTopSmall")
                            footerChevronKeycap(imageName: "IconChevronDownSmall")
                        }
                        Text("Navigate")
                            .jotMetadataLabelTypography()
                            .tracking(floatingSearchMetadataCapsTracking)
                            .foregroundColor(Color("SecondaryTextColor"))
                    }

                    Rectangle()
                        .fill(Color("IconSecondaryColor"))
                        .frame(width: 1, height: 8)
                        .clipShape(Capsule())

                    HStack(spacing: 4) {
                        footerSelectKeycap

                        Text("Select")
                            .jotMetadataLabelTypography()
                            .tracking(floatingSearchMetadataCapsTracking)
                            .foregroundColor(Color("SecondaryTextColor"))
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(floatingSearchFooterKeycapFill)
                        Text("esc")
                            .jotMetadataLabelTypography()
                            .tracking(floatingSearchMetadataCapsTracking)
                            .foregroundColor(Color("SecondaryTextColor"))
                    }
                    .frame(width: 28, height: 17)
                    .compositingGroup()
                    .floatingSearchKeycapShadows()

                    Text(paletteMode == .meetingPickNote ? "Back" : "Close")
                        .jotMetadataLabelTypography()
                        .tracking(floatingSearchMetadataCapsTracking)
                        .foregroundColor(Color("SecondaryTextColor"))
                }
            }
            // Match Figma footer bar p-16; explicit edges so drop shadows don’t throw off perceived inset.
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
    }

    /// Figma: each Navigate chevron in a 15×15 elevated shell; 2pt gap between shells.
    @ViewBuilder
    private func footerChevronKeycap(imageName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(floatingSearchFooterKeycapFill)
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(width: 11, height: 11)
        }
        .frame(width: 15, height: 15)
        .compositingGroup()
        .floatingSearchKeycapShadows()
    }

    /// Select key: small SF Symbol return glyph so it matches system keycap proportions.
    private var footerSelectKeycap: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(floatingSearchFooterKeycapFill)
            Image(systemName: "return.left")
                .font(FontManager.uiPro(size: 7, weight: .regular).font)
                .foregroundStyle(Color("SecondaryTextColor"))
        }
        .frame(width: 15, height: 15)
        .compositingGroup()
        .floatingSearchKeycapShadows()
    }

    // MARK: - Typed query: filtered commands + note/folder hits (single list)

    /// One scrollable column: matching quick actions (if any), divider, then `SearchEngine` hits (if any).
    ///
    /// Divider + spacing intentionally mirrors `rootQuickActionsAndLastSearchBlock` (empty-query
    /// state): each section wraps with symmetric `.padding(8)` and the divider runs edge-to-edge
    /// between them. This keeps the seam between sections visually identical regardless of
    /// whether the user is browsing quick actions or typing a query.
    @ViewBuilder
    private var typedQueryUnifiedList: some View {
        let hasCommands = !filteredRootQuickActionSpecs.isEmpty
        let hasResults = !engine.results.isEmpty
        ScrollView {
            VStack(spacing: 0) {
                if hasCommands {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredRootQuickActionSpecs.enumerated()), id: \.element.activationIndex) {
                            pair in
                            typedFilterQuickActionRow(spec: pair.element, unifiedIndex: pair.offset)
                        }
                    }
                    .padding(8)
                }
                if hasCommands, hasResults {
                    Rectangle()
                        .fill(panelDividerColor)
                        .frame(height: 0.5)
                }
                if hasResults {
                    VStack(spacing: 0) {
                        ForEach(Array(engine.results.enumerated()), id: \.element.id) { pair in
                            resultRow(
                                pair.element,
                                unifiedIndex: typedQueryCommandMatchCount + pair.offset)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    @ViewBuilder
    private func typedFilterQuickActionTrailing(activationIndex: Int) -> some View {
        switch activationIndex {
        case 0:
            sidebarStyleShortcutLabel("\u{2318}N")
        case 1:
            sidebarStyleShortcutLabel(quickNoteShortcutDisplay)
        case 2:
            sidebarStyleShortcutLabel(startMeetingSessionShortcutDisplay)
        case 6:
            sidebarStyleShortcutLabel("\u{2318}.")
        case 8:
            sidebarStyleShortcutLabel("\u{2318},")
        default:
            EmptyView()
        }
    }

    private func typedFilterQuickActionRow(spec: RootQuickActionFilterSpec, unifiedIndex: Int) -> some View {
        let isSelected = typedQueryUnifiedListActive && selectedResultIndex == unifiedIndex
        return Button {
            activateQuickAction(at: spec.activationIndex)
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(spec.iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 15, height: 15)

                    Text(spec.title)
                        .jotUI(FontManager.uiLabel3(weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    typedFilterQuickActionTrailing(activationIndex: spec.activationIndex)
                }
                .frame(minHeight: 15)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule()
                    .fill(Color("HoverBackgroundColor"))
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!spec.isEnabled)
        .opacity(spec.isEnabled ? 1 : 0.45)
        .onHover { hovering in
            if hovering, typedQueryUnifiedListActive, spec.isEnabled {
                selectedResultIndex = unifiedIndex
            }
        }
    }

    private func folder(for folderID: UUID?) -> Folder? {
        guard let folderID else { return nil }
        return folders.first(where: { $0.id == folderID })
    }

    private func resultRow(_ result: SearchHit, unifiedIndex: Int) -> some View {
        let isHovered = hoveredResultID == result.id
        let isSelected = selectedResultIndex == unifiedIndex
        let hasPreview = result.type == .content
        // Folder name lives on the title row (Figma 2785:4587); only content preview adds a second line.
        let isMultiLine = hasPreview
        // Folder hits: same tint as sidebar (prefer live `folders` for current colorHex).
        let leadingResultIconColor: Color = {
            guard result.isFolderResult, let hitFolder = result.folder else {
                return Color("SecondaryTextColor")
            }
            let folder = folders.first(where: { $0.id == hitFolder.id }) ?? hitFolder
            return folder.folderDisplayColor(for: colorScheme)
        }()
        let inlineFolder: Folder? = {
            guard !result.isFolderResult, let note = result.note else { return nil }
            return folder(for: note.folderID)
        }()
        let folderTint = inlineFolder.map { $0.folderDisplayColor(for: colorScheme) }

        return Button(action: {
            selectResult(result)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(result.isFolderResult ? "IconFolder1" : "IconNoteText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(leadingResultIconColor)
                        .frame(width: 15, height: 15)

                    Text(result.title)
                        .jotUI(FontManager.uiLabel3(weight: .regular))
                        .foregroundColor(leadingResultIconColor)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(-1)

                    if let folder = inlineFolder, let tint = folderTint {
                        HStack(spacing: 4) {
                            Image("IconFolder1")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(tint)
                                .frame(width: 14, height: 14)

                            Text(folder.name)
                                .jotUI(FontManager.uiLabel3(weight: .regular))
                                .foregroundColor(tint)
                                .lineLimit(1)
                        }
                        .layoutPriority(0)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, isMultiLine ? 2 : 8)

                if hasPreview {
                    Text(highlightedPreview(for: result))
                        .tracking(FontManager.proportionalUITracking(pointSize: FontManager.UITextRamp.label5))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 31)
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isMultiLine {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color("HoverBackgroundColor"))
                        .opacity(isHovered || isSelected ? 1 : 0)
                } else {
                    Capsule()
                        .fill(Color("HoverBackgroundColor"))
                        .opacity(isHovered || isSelected ? 1 : 0)
                }
            }
            .contentShape(isMultiLine
                ? AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                : AnyShape(Capsule()))
            .animation(.jotHover, value: isHovered)
            .animation(.jotHover, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(SearchAnimations.resultHover) {
                hoveredResultID = hovering ? result.id : (hoveredResultID == result.id ? nil : hoveredResultID)
                if hovering {
                    selectedResultIndex = unifiedIndex
                }
            }
        }
    }

    // MARK: - Preview Highlighting

    private func highlightedPreview(for result: SearchHit) -> AttributedString {
        let previewText = result.preview
        var attributed = AttributedString(previewText)
        attributed.font = FontManager.uiLabel5(weight: .regular).font
        attributed.foregroundColor = Color("SecondaryTextColor")

        let query = result.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return attributed }

        if let range = attributed.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            attributed[range].font = FontManager.uiLabel5(weight: .semibold).font
            attributed[range].foregroundColor = Color("PrimaryTextColor")
        }

        return attributed
    }

    // MARK: - Actions

    /// Clears the query from the palette clear control (shown only when text is non-empty).
    private func clearSearchText() {
        searchText = ""
        engine.query = ""
    }

    private func handlePresentationChange(_ presented: Bool) {
        if presented {
            prepareForPresentation()
        } else {
            withAnimation(SearchAnimations.disappear) {
                hoveredResultID = nil
                selectedResultIndex = 0
                searchText = ""
                engine.query = ""
                isSearchFocused = false
                paletteMode = .root
            }
        }
    }

    /// Escape / macOS exit command: leave meeting sub-palette first, then dismiss.
    private func handlePaletteEscapeKey() {
        if paletteMode == .meetingPickNote {
            withPaletteSwapAnimation {
                paletteMode = .root
            }
        } else {
            dismissSearch()
        }
    }

    private func prepareForPresentation() {
        selectedResultIndex = 0
        if openIntent == .startMeetingSessionPickNote,
           appleIntelligenceService.refreshMeetingNotesCapability().showsEntryPoints {
            // Must clear query before showing meeting pick: `quickActionsAndRecentsBlock` only renders
            // when `isEmptyQuery`; restoring `engine.query` would leave the field non-empty and hide
            // “Start recording in:” behind an empty results strip or footer-only UI.
            searchText = ""
            engine.query = ""
            withPaletteSwapAnimation {
                paletteMode = .meetingPickNote
            }
            openIntent = .commandPaletteRoot
        } else {
            searchText = engine.query
            if paletteMode != .root {
                withPaletteSwapAnimation {
                    paletteMode = .root
                }
            }
        }
        kickCommandPaletteNativeSearchFocus()
    }

    /// Ensures the macOS AppKit-backed palette field becomes first responder after the open animation
    /// and layout settle, so `makeKey` / `makeFirstResponder` are not interleaved with the bouncy scale
    /// entry (reduces “shaking”). The `FloatingSearchNativeTextField` coordinator still runs its retry ladder.
    private func kickCommandPaletteNativeSearchFocus() {
        Task { @MainActor in
            // Aligns with `FloatingSearchOverlayAnimation.appear` so focus work is not on the same frames
            // as the scale+opacity transition.
            try? await Task.sleep(nanoseconds: 230_000_000)
            guard isPresented else { return }
            isSearchFocused = true
            commandPaletteNativeFocusGeneration &+= 1
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard isPresented else { return }
            isSearchFocused = true
            commandPaletteNativeFocusGeneration &+= 1
        }
    }

    private func dismissSearch() {
        guard isPresented else { return }
        withAnimation(SearchAnimations.disappear) {
            isPresented = false
        }
    }

    private func commitCurrentSearch() {
        let trimmed = trimmedSearch
        guard !trimmed.isEmpty else { return }

        engine.recordCommittedQuery(trimmed)
        // Command activation in root mode is handled by `handleReturnKey` via the unified list
        // path before this function is called — so by the time we're here, either we're in
        // meetingPickNote mode with note results, or the user pressed Enter on a typed query
        // with zero selectable rows (just recording the committed query above).
        if !engine.results.isEmpty {
            selectCurrentResult(recordQuery: false)
        }
    }

    private func applyRecentQuery(_ query: String) {
        engine.recordCommittedQuery(query)
        searchText = query
        engine.query = query
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
        }
    }

    private func openRecentTarget(_ target: RecentOpenedSearchTarget) {
        switch target.kind {
        case .note:
            if let note = notes.first(where: { $0.id == target.entityID }) {
                onNoteSelected(note)
                dismissSearch()
            } else {
                engine.removeRecentOpenedTarget(entityID: target.entityID)
            }
        case .folder:
            if let folder = folders.first(where: { $0.id == target.entityID }) {
                onFolderSelected?(folder)
                dismissSearch()
            } else {
                engine.removeRecentOpenedTarget(entityID: target.entityID)
            }
        }
    }

    private func openNoteStartingMeeting(_ note: Note) {
        guard appleIntelligenceService.refreshMeetingNotesCapability().canStartNewSession else {
            withPaletteSwapAnimation {
                paletteMode = .root
                selectedResultIndex = 0
            }
            return
        }
        onNoteSelectedStartMeeting(note)
        dismissSearch()
    }

    private func activateQuickAction(at index: Int) {
        if hasDeferredUpdateRow, index == deferredUpdateActionActivationIndex {
            if deferredUpdateUsesSparkleHandler {
                onResumeSparkleDeferredUpdate()
            } else {
                onResumeDevDeferredRelaunch()
            }
            dismissSearch()
            return
        }

        guard index >= 0, index <= 8 else { return }

        switch index {
        case 0:
            NotificationCenter.default.post(.createNewNote)
            dismissSearch()
        case 1:
            #if os(macOS)
            QuickNoteWindowController.shared.showPanel()
            #endif
            dismissSearch()
        case 2:
            guard meetingNotesCapability.showsEntryPoints else { return }
            // Meeting pick UI only mounts when the query is empty; clear typed filter text before swapping.
            searchText = ""
            engine.query = ""
            withPaletteSwapAnimation {
                paletteMode = .meetingPickNote
                selectedResultIndex = 0
            }
        case 3:
            NotificationCenter.default.post(.createNewFolder)
            dismissSearch()
        case 4:
            NotificationCenter.default.post(.requestSplitViewFromCommandPalette)
            dismissSearch()
        case 5:
            guard selectedNote != nil else { return }
            onTogglePin()
            dismissSearch()
        case 6:
            onToggleSidebar()
            dismissSearch()
        case 7:
            guard isArchiveOrRestoreQuickActionEnabled else { return }
            onArchiveOrRestoreSelectedNote()
            dismissSearch()
        case 8:
            NotificationCenter.default.post(.openSettings)
            dismissSearch()
        default:
            break
        }
    }

    private func activatePaletteRow(at index: Int) {
        guard isEmptyQuery, !showResultsPanel else { return }
        if paletteMode == .meetingPickNote {
            guard index >= 0, index < meetingPickChoices.count else { return }
            openNoteStartingMeeting(meetingPickChoices[index].note)
            return
        }

        if hasDeferredUpdateRow, index == deferredUpdateRowSelectableIndex {
            if deferredUpdateUsesSparkleHandler {
                onResumeSparkleDeferredUpdate()
            } else {
                onResumeDevDeferredRelaunch()
            }
            dismissSearch()
            return
        }

        let historyCount = paletteHistoryRowCount
        let historyStart = paletteHistorySectionStartIndex
        if index >= historyStart, index < historyStart + historyCount {
            let historyIndex = index - historyStart
            guard historyIndex < engine.paletteHistory.count else { return }
            let entry = engine.paletteHistory[historyIndex]
            if entry.isQuery, let q = entry.queryText {
                applyRecentQuery(q)
                return
            }
            if let target = entry.openedTarget {
                openRecentTarget(target)
            }
            return
        }

        if index < rootStandardQuickActionCount {
            let activationIndex = visibleRootQuickActionActivationIndices[index]
            activateQuickAction(at: activationIndex)
        }
    }

    private func handleReturnKey() {
        if typedQueryUnifiedListActive {
            if selectedResultIndex < typedQueryCommandMatchCount {
                let specs = filteredRootQuickActionSpecs
                guard selectedResultIndex < specs.count else { return }
                activateQuickAction(at: specs[selectedResultIndex].activationIndex)
            } else {
                let noteIdx = selectedResultIndex - typedQueryCommandMatchCount
                guard noteIdx < engine.results.count else { return }
                selectResult(engine.results[noteIdx])
            }
            return
        }
        if showResults {
            commitCurrentSearch()
        } else if isEmptyQuery, totalPaletteRows > 0 {
            activatePaletteRow(at: selectedResultIndex)
        } else if !trimmedSearch.isEmpty {
            // Typed query with no selectable row (including zero search hits): still record committed query.
            commitCurrentSearch()
        }
    }

    private enum NavigationDirection {
        case up, down
    }

    private func navigateKeyboard(direction: NavigationDirection) {
        if typedQueryUnifiedListActive {
            guard typedQueryUnifiedRowCount > 0 else { return }
            let maxIndex = typedQueryUnifiedRowCount - 1
            switch direction {
            case .down:
                selectedResultIndex = min(selectedResultIndex + 1, maxIndex)
            case .up:
                selectedResultIndex = max(selectedResultIndex - 1, 0)
            }
            if selectedResultIndex >= typedQueryCommandMatchCount {
                let noteIdx = selectedResultIndex - typedQueryCommandMatchCount
                if noteIdx < engine.results.count {
                    hoveredResultID = engine.results[noteIdx].id
                }
            } else {
                hoveredResultID = nil
            }
            return
        }
        if showResults {
            navigateResults(direction: direction)
        } else if isEmptyQuery, totalPaletteRows > 0 {
            switch direction {
            case .down:
                selectedResultIndex = min(selectedResultIndex + 1, totalPaletteRows - 1)
            case .up:
                selectedResultIndex = max(selectedResultIndex - 1, 0)
            }
        }
    }

    private func selectResult(_ result: SearchHit) {
        engine.recordCommittedQuery(searchText)
        if paletteMode == .meetingPickNote, let note = result.note {
            engine.recordOpenedFromSearch(note: note)
            onNoteSelectedStartMeeting(note)
            dismissSearch()
            return
        }
        if let note = result.note {
            engine.recordOpenedFromSearch(note: note)
            onNoteSelected(note)
        } else if let folder = result.folder {
            engine.recordOpenedFromSearch(folder: folder)
            onFolderSelected?(folder)
        }
        dismissSearch()
    }

    private func selectCurrentResult(recordQuery: Bool = true) {
        guard !engine.results.isEmpty,
              selectedResultIndex < engine.results.count else { return }
        selectSearchHit(at: selectedResultIndex, recordQuery: recordQuery)
    }

    private func selectSearchHit(at resultIndex: Int, recordQuery: Bool) {
        guard resultIndex >= 0, resultIndex < engine.results.count else { return }
        let result = engine.results[resultIndex]
        if recordQuery {
            engine.recordCommittedQuery(searchText)
        }
        if paletteMode == .meetingPickNote, let note = result.note {
            engine.recordOpenedFromSearch(note: note)
            onNoteSelectedStartMeeting(note)
            dismissSearch()
            return
        }
        if let note = result.note {
            engine.recordOpenedFromSearch(note: note)
            onNoteSelected(note)
        } else if let folder = result.folder {
            engine.recordOpenedFromSearch(folder: folder)
            onFolderSelected?(folder)
        }
        dismissSearch()
    }

    private func navigateResults(direction: NavigationDirection) {
        guard !engine.results.isEmpty else { return }

        switch direction {
        case .down:
            selectedResultIndex = min(selectedResultIndex + 1, engine.results.count - 1)
        case .up:
            selectedResultIndex = max(selectedResultIndex - 1, 0)
        }

        selectedResultIndex = max(0, min(selectedResultIndex, engine.results.count - 1))
        if selectedResultIndex < engine.results.count {
            hoveredResultID = engine.results[selectedResultIndex].id
        }
    }
}

// MARK: - Figma shadow-surface-default (footer keycaps)

private extension View {
    /// Footer keycap elevation: tight shadows so they stay inside the 16pt inset and remain visible on elevated fills.
    func floatingSearchKeycapShadows() -> some View {
        self
            .shadow(color: Color.black.opacity(0.14), radius: 0.75, x: 0, y: 0.5)
            .shadow(color: Color.black.opacity(0.09), radius: 1.5, x: 0, y: 1)
    }
}

#if os(macOS)
/// Palette input uses a native AppKit text field so the placeholder and the active field editor share the same vertical rect.
private struct FloatingSearchNativeTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusGeneration: UInt64
    let placeholder: String
    let verticalOffset: CGFloat
    let onMoveDown: () -> Void
    let onMoveUp: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> FloatingSearchAppKitTextField {
        let field = FloatingSearchAppKitTextField()
        field.cell = FloatingSearchTextFieldCell(textCell: "")
        field.delegate = context.coordinator
        configure(field)
        context.coordinator.field = field
        let coordinator = context.coordinator
        field.onWindowChange = { [weak coordinator, weak field] in
            guard let coordinator, let field else { return }
            coordinator.handleWindowChanged(field: field)
        }
        return field
    }

    func updateNSView(_ nsView: FloatingSearchAppKitTextField, context: Context) {
        context.coordinator.parent = self
        configure(nsView)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.handleUpdate(field: nsView, focusGeneration: focusGeneration)
        if let editor = nsView.currentEditor() {
            context.coordinator.configure(editor: editor)
        }
    }

    private func configure(_ field: FloatingSearchAppKitTextField) {
        let font = NSFont.systemFont(ofSize: 11, weight: .regular)
        let primaryText = NSColor(named: "PrimaryTextColor") ?? .labelColor
        field.verticalTextOffset = verticalOffset
        field.font = font
        field.textColor = primaryText
        field.placeholderString = placeholder
        field.alignment = .left
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        field.isAutomaticTextCompletionEnabled = false
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FloatingSearchNativeTextField
        weak var field: FloatingSearchAppKitTextField?
        /// Work items for the multi-shot first responder capture; cancelled whenever a new capture session starts.
        private var pendingFirstResponderWork: [DispatchWorkItem] = []
        /// Last `focusGeneration` we scheduled a capture for — avoids restarting capture on every keystroke (`text` updates).
        private var lastScheduledFocusGeneration: UInt64?

        init(parent: FloatingSearchNativeTextField) {
            self.parent = parent
        }

        /// True when this `NSTextField` (or its shared field editor) is actually first responder.
        private static func fieldHasInsertionFocus(_ field: NSTextField) -> Bool {
            guard let window = field.window else { return false }
            if window.firstResponder === field {
                return true
            }
            if let editor = field.currentEditor() {
                return window.firstResponder === editor
            }
            return false
        }

        /// `makeFirstResponder` is unreliable if the palette’s window is not key yet (overlay + transitions).
        private static func activateHostWindow(for field: NSTextField) {
            guard let window = field.window else { return }
            if !window.isKeyWindow {
                window.makeKey()
            }
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        func handleUpdate(field: FloatingSearchAppKitTextField, focusGeneration: UInt64) {
            self.field = field

            // We intentionally do NOT gate on `parent.isFocused` here. The native field only exists while the palette
            // is presented (it's inside an `if isPresented` branch in `searchInput`), so field existence already means
            // "should be focused." The freshly-created Binding can read stale `false` during the first render
            // transaction after `isPresented` flips, and canceling pending work on that stale read erased the
            // retry cascade we just scheduled — which produced a ~1s delay before focus landed via the next kick pass.

            if Self.fieldHasInsertionFocus(field) {
                cancelPendingFirstResponderWork()
                return
            }

            // Only start a new multi-shot session when the palette explicitly bumped the generation, otherwise
            // typing would cancel/restart capture constantly via `updateNSView`.
            if lastScheduledFocusGeneration != focusGeneration {
                lastScheduledFocusGeneration = focusGeneration
                scheduleFirstResponderCapture(field: field)
            } else if pendingFirstResponderWork.isEmpty {
                // Generation unchanged (e.g. layout finished) but we still never got focus — try one more wave.
                scheduleFirstResponderCapture(field: field)
            }
        }

        /// Called when the representable is finally attached to a window (SwiftUI often sets `window` after first layout).
        ///
        /// The native field only exists while the palette is presented (it lives inside an `if isPresented` branch
        /// in `searchInput`), so "attached to a window" already implies "palette is shown, should be focused." We
        /// intentionally omit a `parent.isFocused` guard here: during the first render transaction after
        /// `isPresented` flips to `true`, the freshly-created `Binding(get: { isSearchFocused })` can read stale
        /// `false` before SwiftUI commits the `isSearchFocused = true` update, which would otherwise cause the
        /// palette to open without keyboard focus and force the user to click before typing.
        func handleWindowChanged(field: FloatingSearchAppKitTextField) {
            guard field.window != nil else { return }
            if Self.fieldHasInsertionFocus(field) {
                cancelPendingFirstResponderWork()
                return
            }
            scheduleFirstResponderCapture(field: field)
        }

        private func scheduleFirstResponderCapture(field: FloatingSearchAppKitTextField) {
            cancelPendingFirstResponderWork()
            let delays: [TimeInterval] = [0, 0.02, 0.05, 0.09, 0.16, 0.26, 0.42]
            for delay in delays {
                let work = DispatchWorkItem { [weak field] in
                    // Field existence is a stronger signal than `parent.isFocused`: the NSView is only ever in the
                    // tree while the palette is presented, and `parent.isFocused` can race with view remount during
                    // the initial presentation transaction (see `handleWindowChanged` comment).
                    guard let field else { return }
                    if Coordinator.fieldHasInsertionFocus(field) { return }
                    guard field.window != nil else { return }
                    Coordinator.activateHostWindow(for: field)
                    _ = field.window?.makeFirstResponder(field)
                }
                pendingFirstResponderWork.append(work)
                if delay == 0 {
                    DispatchQueue.main.async(execute: work)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                }
            }
        }

        private func cancelPendingFirstResponderWork() {
            for item in pendingFirstResponderWork {
                item.cancel()
            }
            pendingFirstResponderWork.removeAll()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
            if let editor = (notification.object as? NSTextField)?.currentEditor() {
                configure(editor: editor)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
            if let editor = field.currentEditor() {
                configure(editor: editor)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        func configure(editor: NSText) {
            guard let editor = editor as? NSTextView else { return }
            var typingAttributes = editor.typingAttributes
            typingAttributes[.font] = NSFont.systemFont(ofSize: 11, weight: .regular)
            typingAttributes[.kern] = -0.2
            typingAttributes[.foregroundColor] = NSColor(named: "PrimaryTextColor") ?? .labelColor
            editor.typingAttributes = typingAttributes
            editor.textColor = NSColor(named: "PrimaryTextColor") ?? .labelColor
        }
    }
}

/// NSTextField still uses a shared field editor; shifting the cell rects keeps placeholder and I-beam in the same native coordinate space.
private final class FloatingSearchAppKitTextField: NSTextField {
    /// Fired whenever the view is reparented so we can retry `makeFirstResponder` after SwiftUI attaches a `window`.
    var onWindowChange: (() -> Void)?

    var verticalTextOffset: CGFloat = 0 {
        didSet {
            (cell as? FloatingSearchTextFieldCell)?.verticalOffset = verticalTextOffset
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }
}

private final class FloatingSearchTextFieldCell: NSTextFieldCell {
    var verticalOffset: CGFloat = 0

    private func adjustedRect(_ rect: NSRect) -> NSRect {
        var adjusted = rect
        adjusted.origin.y += verticalOffset
        adjusted.size.height = max(0, adjusted.size.height - verticalOffset)
        return adjusted
    }

    /// Canonical vertically-centered `NSTextFieldCell` pattern: `drawingRect` is the single source of truth for the
    /// content frame, and `edit` / `select` route through it so the field editor lands at the same offset as the
    /// placeholder. An earlier implementation gated this on an `isEditingOrSelecting` flag, which caused the base
    /// (unshifted) rect to leak through during `super.edit(_:)` — the insertion bar and typed text appeared ~1.5pt
    /// higher than the placeholder the moment focus landed.
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        adjustedRect(super.drawingRect(forBounds: rect))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

#endif
