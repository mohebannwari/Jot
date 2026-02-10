//
//  component_pattern.swift
//  Jot Examples
//
//  Simplified pattern extracted from: Jot/Views/Components/NoteCard.swift
//
//  This demonstrates the standard component structure for SwiftUI views
//  in the Jot app, including state management, liquid glass effects,
//  and interactive animations.
//

import SwiftUI

// MARK: - Component Structure Pattern

/// Example component following Jot's established structure:
/// 1. Properties (props from parent + environment objects)
/// 2. State (local component state)
/// 3. Computed properties (complex logic extracted from body)
/// 4. Body (view hierarchy)
/// 5. Helper methods (private supporting functions)
struct ExampleCard: View {
    // MARK: - Properties
    // Props passed from parent component
    let title: String
    let content: String
    let onTap: () -> Void
    
    // Environment objects for shared state
    // These are injected at app level in JotApp.swift
    @EnvironmentObject private var notesManager: NotesManager
    @EnvironmentObject private var themeManager: ThemeManager
    
    // MARK: - State
    // Local component state for hover interaction
    @State private var isHovering = false
    
    // MARK: - Computed Properties
    // Extract complex logic from body for readability
    private var cardScale: CGFloat {
        isHovering ? 1.02 : 1.0
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM"
        return formatter.string(from: Date())
    }
    
    // MARK: - Body
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with date badge
                HStack {
                    // Date badge with liquid glass effect
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .foregroundColor(Color("TertiaryTextColor"))
                        
                        Text(formattedDate)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color("TertiaryTextColor"))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    // Apply tinted liquid glass effect
                    .tintedLiquidGlass(
                        in: Capsule(),
                        tint: Color("SurfaceTranslucentColor")
                    )
                    
                    Spacer()
                }
                
                // Content section
                VStack(alignment: .leading, spacing: 8) {
                    // Title with semantic color
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color("PrimaryTextColor"))
                        .lineLimit(1)
                    
                    // Content with semantic color
                    Text(content)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .lineLimit(3)
                }
            }
            .padding(12)
            .frame(width: 222, height: 182)
            // Use semantic background color
            .background(Color("CardBackgroundColor"))
            // Standard corner radius
            .clipShape(RoundedRectangle(cornerRadius: 24))
            // Shadow layers for depth
            .shadow(color: Color.black.opacity(0.02), radius: 19, x: 0, y: 9)
            .shadow(color: Color.black.opacity(0.02), radius: 35, x: 0, y: 35)
        }
        .buttonStyle(.plain)
        // Scale effect on hover with bouncy animation
        .scaleEffect(cardScale)
        .onHover { hovering in
            // Use .bouncy animation with 0.3 duration (standard for glass effects)
            withAnimation(.bouncy(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
    
    // MARK: - Helper Methods
    // Private methods for supporting functionality
    private func handleAction() {
        // Complex action logic here
    }
}

// MARK: - Preview

/// Always include previews for component development
#Preview {
    ExampleCard(
        title: "Example Title",
        content: "This is example content that demonstrates the component pattern.",
        onTap: { print("Card tapped") }
    )
    // Inject required environment objects for preview
    .environmentObject(NotesManager())
    .environmentObject(ThemeManager())
    .frame(width: 300, height: 250)
    .background(Color("BackgroundColor"))
}

// MARK: - Key Takeaways

/*
 Component Structure Pattern:
 
 1. PROPERTIES SECTION
    - Define props (data passed from parent)
    - Declare environment objects (@EnvironmentObject)
    - Use private access for environment objects
 
 2. STATE SECTION
    - Local component state with @State
    - Keep state minimal and focused
    - Use private access
 
 3. COMPUTED PROPERTIES SECTION
    - Extract complex calculations from body
    - Improve readability
    - Enable reuse of logic
 
 4. BODY SECTION
    - Main view hierarchy
    - Apply modifiers in logical order:
      * Content modifiers first
      * Layout modifiers (frame, padding)
      * Styling modifiers (background, foreground)
      * Behavior modifiers (onHover, onTapGesture)
 
 5. HELPER METHODS SECTION
    - Private supporting functions
    - Keep body lean by extracting logic
 
 Design System Rules:
 - Use semantic colors from Assets.xcassets (never hardcode)
 - Apply standard spacing values: 4, 6, 8, 12, 16, 18, 24, 60
 - Use standard corner radii: 4, 20, 24, or Capsule
 - Apply glass effects to floating elements only
 - Use .bouncy(duration: 0.3) for glass animations
 - Include MARK comments for organization
 
 Liquid Glass Guidelines:
 - Use .liquidGlass() or .tintedLiquidGlass() modifiers
 - Apply to floating UI elements (cards, buttons, overlays)
 - Never stack glass on glass
 - Interactive elements need interactive glass effects
 - Falls back to .ultraThinMaterial on older OS versions
 
 State Management:
 - Access shared state via @EnvironmentObject
 - Managers handle business logic and persistence
 - Components focus on presentation
 - Use @Published properties in managers for UI updates
 */

