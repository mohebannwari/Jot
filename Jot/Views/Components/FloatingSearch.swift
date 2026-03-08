//
//  FloatingSearch.swift
//  Jot
//
//  Created by AI on 08.08.25.
//

import SwiftUI

struct FloatingSearch: View {
    @ObservedObject var engine: SearchEngine
    @Binding var isPresented: Bool
    let onNoteSelected: (Note) -> Void
    var onFolderSelected: ((Folder) -> Void)? = nil
    var folders: [Folder] = []

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchNamespace
    @State private var hoveredResultID: SearchHit.ID?
    @State private var selectedResultIndex: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    private let surfaceWidth: CGFloat = 400
    private let surfaceCornerRadius: CGFloat = 16
    private let resultItemCornerRadius: CGFloat = 12

    private enum SearchAnimations {
        static let appear = Animation.bouncy(duration: 0.35)
        static let disappear = Animation.snappy(duration: 0.24)
        static let resultHover = Animation.spring(response: 0.25, dampingFraction: 0.86)
    }

    private var showResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !engine.results.isEmpty
    }

    private var displayedRecentQueries: [String] {
        Array(engine.recentQueries.prefix(3))
    }

    private var showRecentQueries: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !displayedRecentQueries.isEmpty
    }

    private var maxResultsHeight: CGFloat {
        if showResults { return 200 }
        if showRecentQueries { return 178 }
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
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
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
            HStack(spacing: 8) {
                Image("IconMagnifyingGlass")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 18, height: 18)

                TextField("Search", text: $searchText)
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.1)
                    .foregroundColor(Color("PrimaryTextColor"))
                    .focused($isSearchFocused)
                    .textFieldStyle(.plain)
                    .onKeyPress(.downArrow) {
                        navigateResults(direction: .down)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        navigateResults(direction: .up)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        commitCurrentSearch()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismissSearch()
                        return .handled
                    }

                Button(action: trailingAction) {
                    Image("IconCircleX")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .subtleHoverScale(1.06)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            if showRecentQueries {
                recentQuerySection
            }

            if showResults {
                resultsSection
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
    }

    // MARK: - Recent Queries

    @ViewBuilder
    private var recentQuerySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LAST SEARCH")
                .font(FontManager.heading(size: 9, weight: .bold))
                .textCase(.uppercase)
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(displayedRecentQueries.enumerated()), id: \.offset) { _, query in
                        Button {
                            applyRecentQuery(query)
                        } label: {
                            HStack(spacing: 8) {
                                Image("IconNoteText")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(Color("SecondaryTextColor"))
                                    .frame(width: 18, height: 18)

                                Text(query)
                                    .font(FontManager.heading(size: 15, weight: .medium))
                                    .tracking(-0.2)
                                    .foregroundColor(Color("PrimaryTextColor"))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .hoverContainer(cornerRadius: 999)
                    }
                }
            }
            .frame(maxHeight: maxResultsHeight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, result in
                    resultRow(result, index: index)
                }
            }
        }
        .frame(maxHeight: maxResultsHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func folder(for folderID: UUID?) -> Folder? {
        guard let folderID else { return nil }
        return folders.first(where: { $0.id == folderID })
    }

    private func resultRow(_ result: SearchHit, index: Int) -> some View {
        let isHovered = hoveredResultID == result.id
        let isSelected = selectedResultIndex == index
        let belongsToFolder = result.note?.folderID != nil

        return Button(action: {
            selectResult(result)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(result.isFolderResult ? "IconFolder1" : "IconNoteText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)

                    Text(result.title)
                        .font(FontManager.heading(size: 15, weight: .medium))
                        .tracking(-0.1)
                        .foregroundColor(Color("PrimaryTextColor"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, belongsToFolder ? 2 : 8)

                if let note = result.note, let folder = folder(for: note.folderID) {
                    HStack(spacing: 4) {
                        Image("IconFolder1")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)

                        Text(folder.name)
                            .font(FontManager.heading(size: 11, weight: .medium))
                            .tracking(-0.2)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(folder.folderColor, in: Capsule())
                    .padding(.leading, 36)
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if belongsToFolder {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color("HoverBackgroundColor"))
                        .opacity(isHovered || isSelected ? 1 : 0)
                } else {
                    Capsule()
                        .fill(Color("HoverBackgroundColor"))
                        .opacity(isHovered || isSelected ? 1 : 0)
                }
            }
            .contentShape(belongsToFolder
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

    // MARK: - Actions

    private func trailingAction() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            searchText = ""
            engine.query = ""
            return
        }
        dismissSearch()
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
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Navigation

    private func selectResult(_ result: SearchHit) {

        engine.recordCommittedQuery(searchText)
        if let note = result.note {
            onNoteSelected(note)
        } else if let folder = result.folder {
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
            onNoteSelected(note)
        } else if let folder = result.folder {
            onFolderSelected?(folder)
        }
        dismissSearch()
    }

    private enum NavigationDirection {
        case up, down
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
