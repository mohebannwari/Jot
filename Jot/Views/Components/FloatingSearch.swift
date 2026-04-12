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

struct FloatingSearch: View {
    @ObservedObject var engine: SearchEngine
    @Binding var isPresented: Bool
    let onNoteSelected: (Note) -> Void
    var onFolderSelected: ((Folder) -> Void)? = nil
    var folders: [Folder] = []
    var notes: [Note] = []

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchNamespace
    @State private var hoveredResultID: SearchHit.ID?
    @State private var selectedResultIndex: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    /// Figma command palette width (node 2780:4006): 562pt minimum.
    private let surfaceWidth: CGFloat = 562
    private let surfaceCornerRadius: CGFloat = 22
    private let resultItemCornerRadius: CGFloat = 12
    private let quickActionRowCount = 5
    /// Shared vertical slot so the magnifier, placeholder/caret, and clear control align (plain TextField has extra cell insets).
    private let searchFieldLineHeight: CGFloat = 18

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

    private var paletteHistoryCount: Int {
        engine.paletteHistory.count
    }

    private var totalPaletteRows: Int {
        quickActionRowCount + paletteHistoryCount
    }

    private var showLastSearchSection: Bool {
        isEmptyQuery && !engine.paletteHistory.isEmpty
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
        .onAppear {
            if isPresented {
                prepareForPresentation()
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
                        dismissSearch()
                    }
                    #endif
            }
        } else {
            searchSurfaceContent
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                )
                .background(
                    Color("SecondaryBackgroundColor").opacity(0.5),
                    in: RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .frame(width: surfaceWidth)
                .contentShape(RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
                #if os(macOS)
                .onExitCommand {
                    dismissSearch()
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
                    dismissSearch()
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

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    quickActionRow(
                        index: 0,
                        iconName: "IconNoteText",
                        title: "New Note",
                        trailing: { sidebarStyleShortcutLabel("\u{2318}N") })

                    quickActionRow(
                        index: 1,
                        iconName: "IconEditSmall2",
                        title: "Quick Note",
                        trailing: { sidebarStyleShortcutLabel(quickNoteShortcutDisplay) })

                    quickActionRow(
                        index: 2,
                        iconName: "IconFolderAddRight",
                        title: "New Folder",
                        trailing: { EmptyView() })

                    quickActionRow(
                        index: 3,
                        iconName: "IconSplit",
                        title: "New Splitview",
                        trailing: { EmptyView() })

                    quickActionRow(
                        index: 4,
                        iconName: "IconSettingsGear1",
                        title: "Settings",
                        trailing: { sidebarStyleShortcutLabel("\u{2318},") })
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
    }

    private func quickActionRow<Trailing: View>(
        index: Int,
        iconName: String,
        title: String,
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
        .onHover { hovering in
            if hovering, isEmptyQuery, !showResults {
                selectedResultIndex = index
            }
        }
    }

    /// Same shortcut styling as `sidebarMenuItem` in ContentView (metadata text, no Figma keycap assets).
    private var quickNoteShortcutDisplay: String {
        (themeManager.quickNoteHotKey ?? QuickNoteHotKey.default).displayString
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
                    let rowIndex = quickActionRowCount + offset
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
                            .foregroundColor(Color("PrimaryTextColor"))
                    }
                    .frame(width: 24, height: 15)
                    .compositingGroup()
                    .floatingSearchKeycapShadows()

                    Text("Close")
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
                .foregroundStyle(Color("PrimaryTextColor"))
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
            }
        }
    }

    private func prepareForPresentation() {
        searchText = engine.query
        selectedResultIndex = 0
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

    private func activateQuickAction(at index: Int) {
        switch index {
        case 0:
            NotificationCenter.default.post(name: .createNewNote, object: nil)
        case 1:
            #if os(macOS)
            QuickNoteWindowController.shared.showPanel()
            #endif
        case 2:
            NotificationCenter.default.post(name: .createNewFolder, object: nil)
        case 3:
            NotificationCenter.default.post(name: .requestSplitViewFromCommandPalette, object: nil)
        case 4:
            NotificationCenter.default.post(name: .openSettings, object: nil)
        default:
            break
        }
        dismissSearch()
    }

    private func activatePaletteRow(at index: Int) {
        guard isEmptyQuery, !showResults else { return }
        if index < quickActionRowCount {
            activateQuickAction(at: index)
            return
        }
        let historyIndex = index - quickActionRowCount
        guard historyIndex >= 0, historyIndex < engine.paletteHistory.count else { return }
        let entry = engine.paletteHistory[historyIndex]
        if entry.isQuery, let q = entry.queryText {
            applyRecentQuery(q)
            return
        }
        if let target = entry.openedTarget {
            openRecentTarget(target)
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
