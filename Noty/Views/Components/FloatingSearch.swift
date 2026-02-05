//
//  FloatingSearch.swift
//  Noty
//
//  Created by AI on 08.08.25.
//
//  Clean search component based on Figma design with Apple's glass effects
//

import SwiftUI

enum SearchState {
    case collapsed      // Simple search pill
    case expanded       // Search bar only
    case withResults    // Search bar + current results
}

struct FloatingSearch: View {
    @ObservedObject var engine: SearchEngine
    let onNoteSelected: (Note) -> Void
    @State private var searchState: SearchState = .collapsed
    @State private var shouldCollapseFromOutside = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchNamespace
    @State private var hoveredResultID: SearchHit.ID?
    @State private var selectedResultIndex: Int = 0
    @State private var isHoveringCollapsedPill = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var isProgrammaticStateChange = false
    @State private var animatedCornerRadius: CGFloat = 999

    // Performance monitoring
    private let performanceMonitor = PerformanceMonitor.shared

    // Liquid Glass-aligned animation timings tuned for quick search transitions
    private enum SearchAnimations {
        static let morph = Animation.bouncy(duration: 0.35)
        static let collapse = Animation.snappy(duration: 0.24)
        static let hover = Animation.spring(response: 0.22, dampingFraction: 0.82)
        static let resultHover = Animation.spring(response: 0.25, dampingFraction: 0.86)
    }
    
    var body: some View {
        // Performance-optimized search with single surface that grows vertically
        searchInput
            .onChange(of: searchText) { _, newValue in
                // Debounced search for better performance
                performanceMonitor.trackFeatureUsage("search_query")
                engine.query = newValue
                selectedResultIndex = 0 // Reset selection when query changes
                updateSearchState()
            }
            .onChange(of: engine.results) { _, _ in
                selectedResultIndex = 0 // Reset selection when results change
                updateSearchState()
                // Animate corner radius when results change
                animateCornerRadius()
            }
            .onChange(of: searchState) { _, _ in
                // Animate corner radius when state changes
                animateCornerRadius()
            }
            .onChange(of: engine.query) { oldValue, newValue in
                // Detect if query was cleared externally (not from typing)
                let wasExternallyCleared = !oldValue.isEmpty && newValue.isEmpty && searchText == oldValue

                // Sync searchText with engine query
                if searchText != newValue {
                    searchText = newValue

                    // If query was cleared externally, force collapse
                    if wasExternallyCleared {
                        shouldCollapseFromOutside = true
                        isSearchFocused = false
                        updateSearchState()
                    }
                }
            }
            .keyboardShortcut("f", modifiers: [.command])
            .onAppear {
                performanceMonitor.trackFeatureUsage("search_component_load")
                // Initialize animated corner radius
                animatedCornerRadius = targetCornerRadius
            }
    }
    
    // MARK: - Search Input
    
    // Target corner radius based on state and results
    private var targetCornerRadius: CGFloat {
        switch searchState {
        case .collapsed:
            return 999 // Capsule for collapsed pill
        case .expanded:
            return 999 // Capsule for expanded without results
        case .withResults:
            // Immediately use base radius when entering results state
            // Then adapt smoothly as results load
            let resultCount = engine.results.count
            let baseRadius: CGFloat = 32
            let minRadius: CGFloat = 16
            let reductionPerResult: CGFloat = 2
            
            let adaptiveRadius = max(minRadius, baseRadius - (CGFloat(resultCount) * reductionPerResult))
            return adaptiveRadius
        }
    }
    
    // Use the animated value for actual rendering
    private var currentCornerRadius: CGFloat {
        return animatedCornerRadius
    }

    // Inner hover highlight radius follows concentricity of the container's liquid glass
    private var hoverCornerRadius: CGFloat {
        // Min inset from container to hover background at corners:
        // horizontal: results padding (12) + row padding (6) = 18
        // vertical (top/bottom): results padding (12)
        let inset = CGFloat(12) // use the limiting inset for concentric rounding (min of 12 and 18)
        return max(6, currentCornerRadius - inset)
    }
    
    @ViewBuilder
    private var searchInput: some View {
        if #available(macOS 26.0, *) {
            morphingGlassSearch
        } else {
            legacySearch
        }
    }

    @ViewBuilder
    private var searchSurfaceContent: some View {
        VStack(spacing: 0) {
            if searchState == .withResults && !engine.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, result in
                        resultRow(result, index: index)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            if searchState == .collapsed {
                Button(action: expandSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(FontManager.heading(size: 16, weight: .regular))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(FontManager.heading(size: 16, weight: .regular))
                        .foregroundColor(Color("PrimaryTextColor"))

                    TextField("Search", text: $searchText)
                        .font(FontManager.heading(size: 13, weight: .medium))
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
                            selectCurrentResult()
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            closeSearch()
                            return .handled
                        }

                    if searchState == .withResults {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "delete.left.fill")
                                .font(FontManager.heading(size: 18, weight: .regular))
                                .foregroundColor(Color("SecondaryTextColor"))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }
    
    // Performance-optimized morphing glass surface for macOS 26+ - Single glass layer, no stacking
    @available(macOS 26.0, *)
    private var morphingGlassSearch: some View {
        LiquidGlassContainer(spacing: 0) {
            searchSurfaceContent
                .glassEffect(
                    .regular.interactive(true),
                    in: RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                )
                .glassID("floating-search.surface", in: searchNamespace)
                .frame(maxWidth: searchState == .collapsed ? nil : 300)
                .scaleEffect(isHoveringCollapsedPill && searchState == .collapsed ? 1.02 : 1.0)
                .contentShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
                .onHover { hovering in
                    if searchState == .collapsed {
                        withAnimation(SearchAnimations.hover) {
                            isHoveringCollapsedPill = hovering
                        }
                    }
                }
                .onTapGesture {
                    if searchState == .collapsed {
                        expandSearch()
                    }
                }
                #if os(macOS)
                .onExitCommand {
                    if searchState != .collapsed {
                        closeSearch()
                    }
                }
                #endif
                .onAppear {
                    performanceMonitor.trackFeatureUsage("search_interface")
                    if searchState != .collapsed {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            isSearchFocused = true
                        }
                    }
                }
        }
    }

    // Performance-optimized legacy fallback for systems older than macOS 26
    private var legacySearch: some View {
        searchSurfaceContent
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .frame(maxWidth: searchState == .collapsed ? nil : 300)
            .scaleEffect(isHoveringCollapsedPill && searchState == .collapsed ? 1.02 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
            .onHover { hovering in
                if searchState == .collapsed {
                    withAnimation(SearchAnimations.hover) {
                        isHoveringCollapsedPill = hovering
                    }
                }
            }
            .onTapGesture {
                if searchState == .collapsed {
                    expandSearch()
                }
            }
            .onExitCommand {
                if searchState != .collapsed {
                    closeSearch()
                }
            }
            .onAppear {
                performanceMonitor.trackFeatureUsage("search_interface_legacy")
                if searchState != .collapsed {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        isSearchFocused = true
                    }
                }
            }
    }
    
    private func resultRow(_ result: SearchHit, index: Int) -> some View {
        let isHovered = hoveredResultID == result.id
        let isSelected = selectedResultIndex == index
        return Button(action: {
            selectResult(result)
        }) {
            HStack(spacing: 12) {
                // Asset-based thumbnail with dark mode support
                Image(colorScheme == .dark ? "note-card-thumbnail-DM" : "note-card-thumbnail")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(result.note.title)
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .lineLimit(1)

                Spacer()

                // Hover affordance to indicate navigation
                Image(systemName: "arrow.right.circle.fill")
                    .font(FontManager.heading(size: 13, weight: .semibold))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .opacity(isHovered || isSelected ? 1 : 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Group {
                    if isHovered || isSelected {
                        RoundedRectangle(cornerRadius: hoverCornerRadius, style: .continuous)
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
    
    private func expandSearch() {
        // Liquid Glass materialization: smooth appearance with interactive spring
        guard searchState == .collapsed else {
            isSearchFocused = true
            return
        }

        withAnimation(SearchAnimations.morph) {
            searchState = searchText.isEmpty ? .expanded : .withResults
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            isSearchFocused = true
        }
    }
    
    private func closeSearch() {
        // Liquid Glass dematerialization: snappy disappearance
        guard searchState != .collapsed || !searchText.isEmpty else { return }

        withAnimation(SearchAnimations.collapse) {
            isProgrammaticStateChange = true
            searchText = ""
            searchState = .collapsed
            isSearchFocused = false
        }
    }
    
    private func updateSearchState() {
        if isProgrammaticStateChange {
            // Skip automatic state transitions triggered by a programmatic collapse
            isProgrammaticStateChange = false
            return
        }
        // Droplet-like blending animation for state changes
        let targetState: SearchState
        if searchText.isEmpty {
            // Force collapse if cleared from outside, otherwise use focus state
            targetState = shouldCollapseFromOutside ? .collapsed : (isSearchFocused ? .expanded : .collapsed)
        } else {
            targetState = .withResults
        }

        guard targetState != searchState else { return }

        let animation = targetState == .collapsed ? SearchAnimations.collapse : SearchAnimations.morph
        withAnimation(animation) {
            searchState = targetState
            if targetState == .collapsed {
                isSearchFocused = false
                shouldCollapseFromOutside = false // Reset the flag
            }
        }
    }
    
    // Smoothly animate corner radius changes to prevent jarring transitions
    private func animateCornerRadius() {
        let newRadius = targetCornerRadius
        guard abs(newRadius - animatedCornerRadius) > 0.1 else { return }
        
        // Use different animation speeds based on the transition
        let isEnteringResults = searchState == .withResults && animatedCornerRadius > 900
        let animation: Animation = isEnteringResults 
            ? .spring(response: 0.35, dampingFraction: 0.75)  // Match the morph animation timing
            : .spring(response: 0.4, dampingFraction: 0.85)   // Smooth for result count changes
        
        withAnimation(animation) {
            animatedCornerRadius = newRadius
        }
    }

    // MARK: - Navigation Actions

    private func selectResult(_ result: SearchHit) {
        performanceMonitor.trackFeatureUsage("search_result_selected")
        onNoteSelected(result.note)
        closeSearch()
    }

    private func selectCurrentResult() {
        guard !engine.results.isEmpty,
              selectedResultIndex < engine.results.count else { return }

        let result = engine.results[selectedResultIndex]
        selectResult(result)
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

        // Ensure index is within bounds
        selectedResultIndex = max(0, min(selectedResultIndex, engine.results.count - 1))

        // Update hover state to match selection
        if selectedResultIndex < engine.results.count {
            hoveredResultID = engine.results[selectedResultIndex].id
        }
    }
}

