//
//  FloatingSearch.swift
//  Noty
//
//  Created by AI on 08.08.25.
//

import SwiftUI

struct FloatingSearch: View {
    @ObservedObject var engine: SearchEngine
    @Binding var isPresented: Bool
    let onNoteSelected: (Note) -> Void
    var folders: [Folder] = []

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchNamespace
    @State private var hoveredResultID: SearchHit.ID?
    @State private var selectedResultIndex: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    private let performanceMonitor = PerformanceMonitor.shared

    private let surfaceWidth: CGFloat = 400
    private let surfaceCornerRadius: CGFloat = 16
    private let resultItemCornerRadius: CGFloat = 8

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
            performanceMonitor.trackFeatureUsage("search_query")
            engine.query = newValue
            selectedResultIndex = 0
        }
        .onChange(of: engine.results) { _, _ in
            selectedResultIndex = 0
        }
        .onAppear {
            performanceMonitor.trackFeatureUsage("search_component_load")
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
                    .tracking(-0.4)
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
                    Image("IconArrowLeftX")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
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
                            HStack(spacing: 12) {
                                Image("IconNoteText")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(Color("SecondaryTextColor"))
                                    .frame(width: 18, height: 18)

                                Text(query)
                                    .font(FontManager.heading(size: 15, weight: .medium))
                                    .tracking(-0.5)
                                    .foregroundColor(Color("PrimaryTextColor"))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
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

    private func folderName(for folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        return folders.first(where: { $0.id == folderID })?.name
    }

    private func resultRow(_ result: SearchHit, index: Int) -> some View {
        let isHovered = hoveredResultID == result.id
        let isSelected = selectedResultIndex == index
        let belongsToFolder = result.note.folderID != nil

        return Button(action: {
            selectResult(result)
        }) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image("IconNoteText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)

                    Text(result.note.title)
                        .font(FontManager.heading(size: 15, weight: .medium))
                        .tracking(-0.5)
                        .foregroundColor(Color("PrimaryTextColor"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, belongsToFolder ? 2 : 8)

                if let name = folderName(for: result.note.folderID) {
                    HStack(spacing: 4) {
                        Image("IconArrowCornerDownRight")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color("SecondaryTextColor"))
                            .frame(width: 10, height: 10)

                        Image("IconFolder2")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color("SecondaryTextColor"))
                            .frame(width: 10, height: 10)

                        Text(name)
                            .font(FontManager.heading(size: 10, weight: .medium))
                            .foregroundColor(Color("SecondaryTextColor").opacity(0.7))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Group {
                    if isHovered || isSelected {
                        RoundedRectangle(cornerRadius: resultItemCornerRadius, style: .continuous)
                            .fill(Color("HoverBackgroundColor"))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
        performanceMonitor.trackFeatureUsage("search_result_selected")
        engine.recordCommittedQuery(searchText)
        onNoteSelected(result.note)
        dismissSearch()
    }

    private func selectCurrentResult(recordQuery: Bool = true) {
        guard !engine.results.isEmpty,
              selectedResultIndex < engine.results.count else { return }

        let result = engine.results[selectedResultIndex]
        if recordQuery {
            engine.recordCommittedQuery(searchText)
        }
        onNoteSelected(result.note)
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
