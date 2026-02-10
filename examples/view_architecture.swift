//
//  view_architecture.swift
//  Jot Examples
//
//  Simplified pattern extracted from: Jot/App/ContentView.swift
//
//  This demonstrates the view composition and architecture patterns
//  for building screen-level views in the Jot app.
//

import SwiftUI

// MARK: - Screen-Level View Architecture

/// Example screen view following Jot's composition pattern:
/// - State objects for local managers
/// - Environment objects for shared state
/// - Computed properties for derived data
/// - Composed subviews for organization
/// - Sheet/fullScreenCover for navigation
struct ExampleScreenView: View {
    // MARK: - State Objects
    // Create state objects for screen-specific managers
    @StateObject private var searchEngine = SearchEngine()
    
    // MARK: - Environment Objects
    // Access shared app-level state
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var notesManager: NotesManager
    
    // MARK: - State
    // Local screen state
    @State private var selectedItem: ExampleItem?
    @State private var isDetailPresented = false
    @State private var isSearchActive = false
    
    // MARK: - Environment Values
    // System environment values
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    // MARK: - Computed Properties
    // Derived data from managers
    private var filteredItems: [ExampleItem] {
        if isSearchActive {
            return searchEngine.results
        }
        return notesManager.items
    }
    
    private var recentItems: [ExampleItem] {
        filteredItems.filter { item in
            Calendar.current.isDateInToday(item.createdDate)
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Main content layer
            VStack(spacing: 0) {
                // Scrollable content
                ScrollView {
                    VStack(spacing: 36) {
                        // Compose sections
                        if !recentItems.isEmpty {
                            ItemsSection(
                                title: "RECENT",
                                items: recentItems,
                                onItemTap: handleItemTap
                            )
                        }
                        
                        ItemsSection(
                            title: "ALL ITEMS",
                            items: filteredItems,
                            onItemTap: handleItemTap
                        )
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 100)
                }
                
                // Bottom toolbar
                BottomToolbar(
                    onSearchTap: {
                        withAnimation(.bouncy(duration: 0.3)) {
                            isSearchActive.toggle()
                        }
                    },
                    onAddTap: handleAddItem
                )
            }
            
            // Floating overlay layer
            if isSearchActive {
                FloatingSearchBar(
                    searchText: $searchEngine.query,
                    onDismiss: {
                        withAnimation(.bouncy(duration: 0.3)) {
                            isSearchActive = false
                        }
                    }
                )
            }
        }
        // Navigation
        .sheet(isPresented: $isDetailPresented) {
            if let item = selectedItem {
                DetailView(item: item)
            }
        }
        // Accessibility
        .preferredColorScheme(themeManager.colorScheme)
    }
    
    // MARK: - Helper Methods
    
    /// Handle item selection with animation
    private func handleItemTap(_ item: ExampleItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedItem = item
            isDetailPresented = true
        }
    }
    
    /// Handle add button action
    private func handleAddItem() {
        let newItem = notesManager.addItem(
            title: "Untitled",
            content: ""
        )
        handleItemTap(newItem)
    }
}

// MARK: - Composed Subviews

/// Section component for grouping items
struct ItemsSection: View {
    let title: String
    let items: [ExampleItem]
    let onItemTap: (ExampleItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section header
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.horizontal, 24)
            
            // Items grid
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 222), spacing: 18)
                ],
                spacing: 18
            ) {
                ForEach(items) { item in
                    ExampleItemCard(
                        item: item,
                        onTap: { onItemTap(item) }
                    )
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

/// Item card component
struct ExampleItemCard: View {
    let item: ExampleItem
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color("PrimaryTextColor"))
                
                Text(item.content)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .lineLimit(3)
            }
            .padding(12)
            .frame(width: 222, height: 182)
            .background(Color("CardBackgroundColor"))
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.bouncy(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}

/// Bottom toolbar with glass effect
struct BottomToolbar: View {
    let onSearchTap: () -> Void
    let onAddTap: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: onSearchTap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            Button(action: onAddTap) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .frame(width: 60, height: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 24))
    }
}

/// Floating search bar overlay
struct FloatingSearchBar: View {
    @Binding var searchText: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color("SecondaryTextColor"))
                
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color("SecondaryTextColor"))
                }
            }
            .padding(16)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)
            .padding(.top, 60)
            
            Spacer()
        }
        .background(Color.black.opacity(0.3))
        .transition(.opacity)
    }
}

// MARK: - Key Takeaways

/*
 View Architecture Patterns:
 
 1. SCREEN-LEVEL VIEW STRUCTURE
    - @StateObject for screen-specific managers
    - @EnvironmentObject for shared app state
    - @State for local UI state
    - @Environment for system values
    - Computed properties for derived data
    - Helper methods for actions
 
 2. COMPOSITION STRATEGY
    - Break down into logical subviews
    - Each subview has single responsibility
    - Pass data down via props
    - Pass actions up via callbacks
    - Use @ViewBuilder for flexible composition
 
 3. STATE MANAGEMENT HIERARCHY
    App Level (JotApp.swift):
    - ThemeManager
    - NotesManager
    
    Screen Level (ContentView.swift):
    - SearchEngine (local to screen)
    - Selected items
    - Presentation state
    
    Component Level:
    - Hover states
    - Animation states
    - Local UI state
 
 4. NAVIGATION PATTERNS
    Sheet for modal presentation:
    .sheet(isPresented: $isPresented) {
        DetailView()
    }
    
    Full screen cover for immersive:
    .fullScreenCover(isPresented: $isPresented) {
        FullScreenView()
    }
    
    Navigation stack for hierarchical:
    NavigationStack {
        List { }
    }
 
 5. LAYOUT COMPOSITION
    ZStack: Layer overlays (floating search, toolbars)
    VStack: Vertical stacking (sections, lists)
    HStack: Horizontal arrangement (toolbars, buttons)
    LazyVGrid: Efficient grid layout
    ScrollView: Scrollable content
 
 6. DATA FLOW
    Parent → Child (Props):
    ItemsSection(
        title: "RECENT",
        items: recentItems,
        onItemTap: handleItemTap
    )
    
    Child → Parent (Callbacks):
    let onItemTap: (ExampleItem) -> Void
    
    Environment (Shared):
    @EnvironmentObject var notesManager: NotesManager
 
 7. ANIMATION GUIDELINES
    State changes:
    withAnimation(.bouncy(duration: 0.3)) {
        isActive.toggle()
    }
    
    Spring animations:
    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
        selectedItem = item
    }
    
    Smooth transitions:
    withAnimation(.smooth) {
        value = newValue
    }
 
 8. ACCESSIBILITY
    - Check reduceTransparency environment value
    - Provide alternative layouts if needed
    - Respect color scheme preference
    - Add accessibility labels
 
 9. PERFORMANCE OPTIMIZATION
    - Use LazyVGrid for large lists (loads on-demand)
    - Extract subviews to prevent re-renders
    - Keep computed properties efficient
    - Minimize @State changes
    - Use proper view identity with ForEach
 
 10. COMMON PATTERNS
     Conditional sections:
     if !items.isEmpty {
         ItemsSection(...)
     }
     
     Computed filtering:
     private var filteredItems: [Item] {
         items.filter { $0.matches(criteria) }
     }
     
     Overlay presentation:
     ZStack {
         MainContent()
         if showOverlay {
             OverlayView()
         }
     }
     
     Bottom padding for toolbars:
     .padding(.bottom, 100)
 
 11. FILE ORGANIZATION
     - One main view per file
     - Related subviews in same file
     - Extract large subviews to separate files
     - Keep screen views focused
 
 12. TESTING CONSIDERATIONS
     - Inject managers for testing
     - Use @StateObject only in root
     - Pass environment objects in previews
     - Test with different data states
 */

