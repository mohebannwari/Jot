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

/// One selectable row in meeting pick mode (current note + recents).
private struct MeetingPickChoice: Identifiable {
    let id: UUID
    let note: Note
    let isCurrentNoteOption: Bool
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
    /// Matches command-palette Zen (sidebar hidden): meeting header becomes “Exit zen mode”.
    var isZenMode: Bool = false

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchNamespace
    @State private var hoveredResultID: SearchHit.ID?
    @State private var selectedResultIndex: Int = 0
    @State private var paletteMode: CommandPaletteMode = .root
    @Environment(\.colorScheme) private var colorScheme

    /// Figma command palette width (node 2780:4006): 562pt minimum.
    private let surfaceWidth: CGFloat = 562
    private let surfaceCornerRadius: CGFloat = 22
    private let resultItemCornerRadius: CGFloat = 12
    /// Fixed quick actions in root mode (excluding optional deferred-update lead row).
    private let rootStandardQuickActionCount = 9
    /// Shared vertical slot so the magnifier, placeholder/caret, and clear control align (plain TextField has extra cell insets).
    private let searchFieldLineHeight: CGFloat = 18

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

    /// macOS: legacy thick scrollbar for the **results** list only (see `FloatingSearchScrollViewLegacyScrollers`).
    /// Not used on the quick-actions list: `NSScrollView` legacy style reserves a right gutter while SwiftUI
    /// still sizes the document full-width, which clips trailing shortcut labels (e.g. ⌘N).
    @ViewBuilder
    private var resultsScrollViewLegacyScrollerProbe: some View {
        #if os(macOS)
        FloatingSearchScrollViewLegacyScrollers()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        #else
        EmptyView()
        #endif
    }

    private enum SearchAnimations {
        static let appear = Animation.bouncy(duration: 0.35)
        static let disappear = Animation.snappy(duration: 0.24)
        static let resultHover = Animation.spring(response: 0.25, dampingFraction: 0.86)
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmptyQuery: Bool {
        trimmedSearch.isEmpty
    }

    private var showResults: Bool {
        !trimmedSearch.isEmpty && !engine.results.isEmpty
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

    /// Sidebar selection with fresh `isArchived` / `isPinned` from `notes` when available.
    private var commandPaletteSelectedNote: Note? {
        guard let sel = selectedNote else { return nil }
        return notes.first(where: { $0.id == sel.id }) ?? sel
    }

    private var archiveOrRestoreQuickActionTitle: String {
        commandPaletteSelectedNote?.isArchived == true ? "Restore" : "Archive note"
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

    private var maxResultsHeight: CGFloat {
        if showResults { return 280 }
        return 0
    }

    var body: some View {
        Group {
            if isPresented {
                searchInput
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(SearchAnimations.appear, value: isPresented)
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
        .onChange(of: showResults) { _, isShowing in
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
        .onReceive(NotificationCenter.default.publisher(for: .floatingSearchSwitchToMeetingPickNote)) { _ in
            guard isPresented else { return }
            withAnimation(SearchAnimations.appear) {
                paletteMode = .meetingPickNote
                selectedResultIndex = 0
                searchText = ""
                engine.query = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
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
            }

            if showResults {
                Rectangle()
                    .fill(Color("BorderSubtleColor"))
                    .frame(height: 0.5)
                resultsSection
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

            // Standard line leading (not FontManager.heading’s .tight) so AppKit’s single-line cell centers like the 15×15 icon.
            TextField("Search anything…", text: $searchText)
                .font(Font.system(size: 11, weight: .medium, design: .default).leading(.standard))
                .tracking(-0.2)
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
        .padding(16)
    }

    // MARK: - Quick actions + LAST SEARCH (empty query only)

    @ViewBuilder
    private var quickActionsAndRecentsBlock: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color("BorderSubtleColor"))
                .frame(height: 0.5)

            if paletteMode == .meetingPickNote {
                meetingPickNoteBlock
            } else {
                rootQuickActionsAndLastSearchBlock
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
                        meetingPickNoteHeaderLabel(title: "Exit zen mode")
                    }
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                } else {
                    meetingPickNoteHeaderLabel(title: "Start recording in:")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color("BorderSubtleColor"))
                .frame(height: 0.5)

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

    /// Shared meeting-picker header: same leading icon for “Start recording in:” and “Exit zen mode”.
    private func meetingPickNoteHeaderLabel(title: String) -> some View {
        HStack(spacing: 8) {
            Image("IconMeetingNotes")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(width: 15, height: 15)

            Text(title)
                .font(FontManager.heading(size: 13, weight: .medium))
                .tracking(-0.4)
                .foregroundColor(Color("SecondaryTextColor"))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private func meetingPickNoteRow(note: Note, index: Int, isCurrentNoteOption: Bool) -> some View {
        let isSelected = isEmptyQuery && !showResults && selectedResultIndex == index
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
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(Color("PrimaryTextColor"))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Current-note row: label on the trailing edge (metadata, all caps).
                if isCurrentNoteOption {
                    Text("CURRENT NOTE")
                        .font(FontManager.metadata(size: 11, weight: .medium))
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
            if hovering, isEmptyQuery, !showResults {
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
                    .fill(Color("BorderSubtleColor"))
                    .frame(height: 0.5)
                lastSearchSectionContent
            }
        }
    }

    private func deferredUpdateQuickRow(index: Int) -> some View {
        quickActionRow(
            index: index,
            iconName: "IconUpdateDownload",
            title: "Update App",
            isEnabled: true,
            trailing: { EmptyView() })
    }

    @ViewBuilder
    private var rootStandardQuickActionRows: some View {
        quickActionRow(
            index: 0,
            iconName: "IconEditSmall2",
            title: "New Note",
            isEnabled: true,
            trailing: { sidebarStyleShortcutLabel("\u{2318}N") })
        quickActionRow(
            index: 1,
            iconName: "IconFloatingNote",
            title: "Floating note",
            isEnabled: true,
            trailing: { sidebarStyleShortcutLabel(quickNoteShortcutDisplay) })
        quickActionRow(
            index: 2,
            iconName: "IconMicrophoneSparkle",
            title: "Start meeting session in a Note",
            isEnabled: true,
            trailing: { sidebarStyleShortcutLabel(startMeetingSessionShortcutDisplay) })
        quickActionRow(
            index: 3,
            iconName: "IconFolderAddRight",
            title: "New Folder",
            isEnabled: true,
            trailing: { EmptyView() })
        quickActionRow(
            index: 4,
            iconName: "IconSplit",
            title: "New Splitview",
            isEnabled: true,
            trailing: { EmptyView() })
        quickActionRow(
            index: 5,
            iconName: selectedNote?.isPinned == true ? "IconUnpin" : "IconThumbtack",
            title: selectedNote?.isPinned == true ? "Unpin note" : "Pin note",
            isEnabled: selectedNote != nil,
            trailing: { EmptyView() })
        quickActionRow(
            index: 6,
            iconName: "IconZenMode",
            title: "Zen mode",
            isEnabled: true,
            trailing: { sidebarStyleShortcutLabel("\u{2318}.") })
        quickActionRow(
            index: 7,
            iconName: archiveOrRestoreQuickActionIcon,
            title: archiveOrRestoreQuickActionTitle,
            isEnabled: isArchiveOrRestoreQuickActionEnabled,
            trailing: { EmptyView() })
        quickActionRow(
            index: 8,
            iconName: "IconSettingsGear1",
            title: "Settings",
            isEnabled: true,
            trailing: { sidebarStyleShortcutLabel("\u{2318},") })
    }

    private func quickActionRow<Trailing: View>(
        index: Int,
        iconName: String,
        title: String,
        isEnabled: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let isSelected = isEmptyQuery && !showResults && selectedResultIndex == index
        return Button {
            activateQuickAction(at: index)
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 15, height: 15)

                    Text(title)
                        .font(FontManager.heading(size: 13, weight: .medium))
                        .tracking(-0.4)
                        .foregroundColor(Color("PrimaryTextColor"))
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
            if hovering, isEmptyQuery, !showResults, isEnabled {
                selectedResultIndex = index
            }
        }
    }

    /// Same shortcut styling as `sidebarMenuItem` in ContentView (metadata text, no Figma keycap assets).
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
            .font(FontManager.metadata(size: 11, weight: .medium))
            .foregroundColor(Color("SecondaryTextColor"))
            .lineLimit(1)
    }

    // MARK: - LAST SEARCH (string queries + opened targets)

    @ViewBuilder
    private var lastSearchSectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LAST SEARCH")
                .font(FontManager.heading(size: 9, weight: .bold))
                .textCase(.uppercase)
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func stringRecentRow(query: String, index: Int) -> some View {
        let isSelected = isEmptyQuery && !showResults && selectedResultIndex == index
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
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(Color("PrimaryTextColor"))
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
            if hovering, isEmptyQuery, !showResults {
                selectedResultIndex = index
            }
        }
    }

    private func openedTargetRow(target: RecentOpenedSearchTarget, index: Int) -> some View {
        let isSelected = isEmptyQuery && !showResults && selectedResultIndex == index
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
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(Color("PrimaryTextColor"))
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
            if hovering, isEmptyQuery, !showResults {
                selectedResultIndex = index
            }
        }
    }

    // MARK: - Footer

    private var commandPaletteFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color("BorderSubtleColor"))
                .frame(height: 0.5)

            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            footerChevronKeycap(imageName: "IconChevronTopSmall")
                            footerChevronKeycap(imageName: "IconChevronDownSmall")
                        }
                        Text("Navigate")
                            .font(FontManager.metadata(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundColor(Color("SecondaryTextColor"))
                    }

                    Rectangle()
                        .fill(Color("IconSecondaryColor"))
                        .frame(width: 1, height: 8)
                        .clipShape(Capsule())

                    HStack(spacing: 4) {
                        footerSelectKeycap

                        Text("Select")
                            .font(FontManager.metadata(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundColor(Color("SecondaryTextColor"))
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color("SurfaceElevatedColor"))
                        Text("esc")
                            .font(FontManager.metadata(size: 9, weight: .semibold))
                            .foregroundColor(Color("SecondaryTextColor"))
                    }
                    .frame(width: 24, height: 15)
                    .compositingGroup()
                    .floatingSearchKeycapShadows()

                    Text(paletteMode == .meetingPickNote ? "Back" : "Close")
                        .font(FontManager.metadata(size: 11, weight: .semibold))
                        .textCase(.uppercase)
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
                .fill(Color("SurfaceElevatedColor"))
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
                .fill(Color("SurfaceElevatedColor"))
            Image(systemName: "return.left")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Color("SecondaryTextColor"))
        }
        .frame(width: 15, height: 15)
        .compositingGroup()
        .floatingSearchKeycapShadows()
    }

    // MARK: - Results (unchanged behavior)

    @ViewBuilder
    private var resultsSection: some View {
        ScrollView {
            VStack(spacing: 0) {
                resultsScrollViewLegacyScrollerProbe
                ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, result in
                    resultRow(result, index: index)
                }
            }
        }
        .scrollIndicators(.visible)
        .frame(maxHeight: maxResultsHeight)
        .padding(8)
    }

    private func folder(for folderID: UUID?) -> Folder? {
        guard let folderID else { return nil }
        return folders.first(where: { $0.id == folderID })
    }

    private func resultRow(_ result: SearchHit, index: Int) -> some View {
        let isHovered = hoveredResultID == result.id
        let isSelected = selectedResultIndex == index
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
                        .font(FontManager.heading(size: 13, weight: .medium))
                        .tracking(-0.4)
                        .foregroundColor(Color("PrimaryTextColor"))
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
                                .font(FontManager.heading(size: 13, weight: .medium))
                                .tracking(-0.2)
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
                        .font(FontManager.heading(size: 11, weight: .regular))
                        .tracking(-0.1)
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
                    selectedResultIndex = index
                }
            }
        }
    }

    // MARK: - Preview Highlighting

    private func highlightedPreview(for result: SearchHit) -> AttributedString {
        let previewText = result.preview
        var attributed = AttributedString(previewText)
        attributed.font = FontManager.heading(size: 11, weight: .regular)
        attributed.foregroundColor = Color("SecondaryTextColor")

        let query = result.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return attributed }

        if let range = attributed.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            attributed[range].font = FontManager.heading(size: 11, weight: .semibold)
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
            paletteMode = .root
        } else {
            dismissSearch()
        }
    }

    private func prepareForPresentation() {
        selectedResultIndex = 0
        if openIntent == .startMeetingSessionPickNote {
            // Must clear query before showing meeting pick: `quickActionsAndRecentsBlock` only renders
            // when `isEmptyQuery`; restoring `engine.query` would leave the field non-empty and hide
            // “Start recording in:” behind an empty results strip or footer-only UI.
            searchText = ""
            engine.query = ""
            paletteMode = .meetingPickNote
            openIntent = .commandPaletteRoot
        } else {
            searchText = engine.query
            paletteMode = .root
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
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
        onNoteSelectedStartMeeting(note)
        dismissSearch()
    }

    private func activateQuickAction(at index: Int) {
        if hasDeferredUpdateRow, index == deferredUpdateRowSelectableIndex {
            if deferredUpdateUsesSparkleHandler {
                onResumeSparkleDeferredUpdate()
            } else {
                onResumeDevDeferredRelaunch()
            }
            dismissSearch()
            return
        }

        guard index >= 0, index < rootStandardQuickActionCount else { return }

        switch index {
        case 0:
            NotificationCenter.default.post(name: .createNewNote, object: nil)
            dismissSearch()
        case 1:
            #if os(macOS)
            QuickNoteWindowController.shared.showPanel()
            #endif
            dismissSearch()
        case 2:
            paletteMode = .meetingPickNote
            selectedResultIndex = 0
        case 3:
            NotificationCenter.default.post(name: .createNewFolder, object: nil)
            dismissSearch()
        case 4:
            NotificationCenter.default.post(name: .requestSplitViewFromCommandPalette, object: nil)
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
            NotificationCenter.default.post(name: .openSettings, object: nil)
            dismissSearch()
        default:
            break
        }
    }

    private func activatePaletteRow(at index: Int) {
        guard isEmptyQuery, !showResults else { return }
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
            activateQuickAction(at: index)
        }
    }

    private func handleReturnKey() {
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

        let result = engine.results[selectedResultIndex]
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
/// SwiftUI’s `ScrollView` uses an `NSScrollView` with overlay scrubbers by default. Walking up from a
/// zero-size view in the document view applies `scrollerStyle = .legacy` (thick thumb) and disables autohide.
/// Use only where trailing edge content does not need the full width (legacy scrollers reserve gutter space).
private struct FloatingSearchScrollViewLegacyScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var current: NSView? = nsView.superview
            while let c = current {
                if let scroll = c as? NSScrollView {
                    scroll.scrollerStyle = .legacy
                    scroll.autohidesScrollers = false
                    return
                }
                current = c.superview
            }
        }
    }
}
#endif
