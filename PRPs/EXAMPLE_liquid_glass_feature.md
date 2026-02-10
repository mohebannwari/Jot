# Product Requirements Prompt: Floating Action Button with Liquid Glass

## Metadata
- **Created**: January 2025
- **Target OS**: iOS 26+ / macOS 26+
- **Confidence**: 9/10
- **Estimated Complexity**: Low

---

## 1. Feature Overview

### Purpose
Add a floating action button (FAB) to the main canvas that allows users to quickly create new notes. The FAB should use Liquid Glass effects and follow Apple's design guidelines.

### User Story
As a Jot user, I want to quickly create a new note from anywhere in the app so that I can capture ideas without navigating through menus.

### Key Requirements
- Floating button visible on canvas view
- Liquid Glass styling with interactive effects
- Creates new note when tapped
- Hover animation with scale effect
- Positioned in bottom-right corner

---

## 2. Context & Background

### Existing Architecture
The FAB will integrate with the existing canvas view and NotesManager:

**Related Components:**
- `ContentView.swift` - Main app view where FAB appears
- `CanvasView.swift` - Canvas displaying note cards
- `NotesManager.swift` - Handles note creation

**State Management:**
- `NotesManager` is an @EnvironmentObject available throughout app
- FAB triggers `notesManager.addNote()` method
- No local state management needed beyond hover state

**Data Flow:**
```
User Taps FAB → notesManager.addNote() → New Note Created → Canvas Updates
```

### Dependencies
**Internal:**
- `NotesManager.swift` - for addNote() method
- `GlassEffects.swift` - for liquid glass modifiers

**External:**
- SwiftUI (iOS 26+/macOS 26+)
- `.glassEffect()` API

---

## 3. Architecture & Design Patterns

### File Structure
```
Jot/
└── Views/
    └── Components/
        └── FloatingActionButton.swift     # New component
```

### Component Structure Pattern
```swift
import SwiftUI

struct FloatingActionButton: View {
    // MARK: - Properties
    let action: () -> Void
    
    // MARK: - State
    @State private var isHovering = false
    
    // MARK: - Computed Properties
    private var buttonSize: CGFloat {
        60
    }
    
    private var buttonScale: CGFloat {
        isHovering ? 1.08 : 1.0
    }
    
    // MARK: - Body
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))
                .frame(width: buttonSize, height: buttonSize)
                .liquidGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(buttonScale)
        .onHover { hovering in
            withAnimation(.bouncy(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}
```

---

## 4. Design System Compliance

### Liquid Glass Effects
Use standard liquid glass on circular shape:

```swift
.liquidGlass(in: Circle())
```

**Rules Applied:**
- Floating UI element (button) - glass effect appropriate
- No stacking of glass effects
- Interactive hover state with scale animation
- Uses `.bouncy(duration: 0.3)` animation

### Color Usage
- `PrimaryTextColor` - For the plus icon
- Glass effect provides the surface appearance

### Typography
```swift
.font(.system(size: 24, weight: .semibold))
```

### Spacing
- Button size: 60x60 points
- Position: 24 points from bottom and right edges

### Corner Radius
- Circle shape (fully rounded)

### Animations
```swift
withAnimation(.bouncy(duration: 0.3)) {
    isHovering = hovering
}
```

Scale effect: 1.0 → 1.08 on hover

---

## 5. Implementation Steps

### Step 1: Create FloatingActionButton Component
**Objective:** Build the reusable FAB component with Liquid Glass styling

**Files to Create:**
- `Jot/Views/Components/FloatingActionButton.swift`

**Implementation Details:**
```swift
import SwiftUI

struct FloatingActionButton: View {
    // MARK: - Properties
    let action: () -> Void
    
    // MARK: - State
    @State private var isHovering = false
    
    // MARK: - Computed Properties
    private var buttonSize: CGFloat {
        60
    }
    
    private var buttonScale: CGFloat {
        isHovering ? 1.08 : 1.0
    }
    
    // MARK: - Body
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))
                .frame(width: buttonSize, height: buttonSize)
                .liquidGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(buttonScale)
        .onHover { hovering in
            withAnimation(.bouncy(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color("BackgroundColor")
            .ignoresSafeArea()
        
        FloatingActionButton {
            print("FAB tapped")
        }
    }
    .frame(width: 400, height: 300)
}
```

**Validation:**
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```

**Success Criteria:**
- [ ] File compiles without errors
- [ ] Follows component structure pattern
- [ ] Uses semantic colors
- [ ] Preview renders correctly

---

### Step 2: Integrate FAB into ContentView
**Objective:** Add the FAB to the main app view with proper positioning

**Files to Modify:**
- `Jot/App/ContentView.swift`

**Implementation Details:**
Add the FAB as an overlay on the main content:

```swift
// In ContentView body, wrap the existing content:
ZStack {
    // Existing content here
    
    // Floating Action Button
    VStack {
        Spacer()
        HStack {
            Spacer()
            FloatingActionButton {
                // Create new note
                notesManager.addNote(
                    title: "Untitled",
                    content: "",
                    tags: []
                )
            }
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
    }
}
```

**Validation:**
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```

**Success Criteria:**
- [ ] FAB appears in bottom-right corner
- [ ] Tapping FAB creates a new note
- [ ] Hover effect works
- [ ] No layout issues with existing content

---

### Step 3: Write Tests
**Objective:** Ensure FAB functionality with unit tests

**Files to Create:**
- `JotTests/FloatingActionButtonTests.swift`

**Test Pattern:**
```swift
import XCTest
@testable import Jot

final class FloatingActionButtonTests: XCTestCase {
    @MainActor
    func testFABCreatesNote() throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("notes.json")
        
        let manager = NotesManager(storageURL: url, seedIfEmpty: false)
        let initialCount = manager.notes.count
        
        // Act
        manager.addNote(title: "Untitled", content: "", tags: [])
        
        // Assert
        XCTAssertEqual(manager.notes.count, initialCount + 1)
        XCTAssertEqual(manager.notes.first?.title, "Untitled")
    }
}
```

**Validation:**
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test
```

---

## 6. Success Criteria

### Functional Requirements
- [x] FAB appears in bottom-right corner of canvas
- [x] Tapping FAB creates a new note
- [x] New note appears in the canvas immediately
- [x] Hover state provides visual feedback

### Design System Compliance
- [x] Liquid Glass effect applied correctly with Circle shape
- [x] No glass-on-glass violations
- [x] Semantic colors used (PrimaryTextColor)
- [x] Typography follows standards (24pt semibold)
- [x] Spacing uses standard value (24pt padding)
- [x] Animation uses .bouncy(duration: 0.3)
- [x] Scale effect on hover (1.0 → 1.08)

### Code Quality
- [x] Follows established component structure (props → state → computed → body)
- [x] Comments explain structure with MARK comments
- [x] Proper SwiftUI best practices
- [x] One component per file
- [x] Preview included for development

### Testing
- [x] Unit test covers note creation
- [x] Test follows established pattern
- [x] Test uses temporary storage
- [x] All tests pass

---

## 7. Validation Gates

### Build Validation
```bash
# Must succeed
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```

### Test Validation
```bash
# Must pass all tests
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test
```

---

## 8. Testing Requirements

### Unit Tests Location
`JotTests/FloatingActionButtonTests.swift`

### Test Cases Required
1. **Test note creation through FAB action**
   - Arrange: Create NotesManager with temp storage
   - Act: Call addNote() (simulating FAB tap)
   - Assert: Verify note count increased and title correct

### Test Pattern Reference
See `JotTests/NotesManagerTests.swift` for established testing patterns with temporary storage and @MainActor.

---

## 9. Gotchas & Considerations

### Common Pitfalls
- Don't hardcode the button color - use semantic colors
- Remember to use `.buttonStyle(.plain)` to prevent default button styling
- Apply glass effect to the content, not the button itself
- Positioning with padding instead of fixed coordinates allows for flexible layouts

### iOS 26+/macOS 26+ Specific
- Requires `.liquidGlass()` which wraps `.glassEffect()` API
- Falls back to `.ultraThinMaterial` on older OS versions automatically

### Performance Considerations
- Hover animation is lightweight and performs well
- No performance concerns with single FAB instance

---

## 10. Documentation & References

### Figma Design
- https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot
- Reference floating action button components

### Apple Documentation
- SwiftUI Button: https://developer.apple.com/documentation/swiftui/button
- Glass Effects (iOS 26+): Part of SwiftUI enhancements

### Example Files
Reference these examples:
- `examples/component_pattern.swift` - Component structure
- `examples/glass_effects_pattern.swift` - Liquid Glass usage
- `Jot/Views/Components/NoteCard.swift` - Similar hover effect pattern

### Related Code
- `Jot/Utils/GlassEffects.swift` - Glass effect modifiers
- `Jot/Models/NotesManager.swift` - addNote() method

---

## 11. Implementation Checklist

- [x] Read entire PRP and understand requirements
- [x] Review GlassEffects.swift for liquidGlass modifier
- [x] Review NoteCard.swift for hover pattern
- [x] Create FloatingActionButton.swift component
- [x] Add MARK comments for organization
- [x] Implement hover state with scale effect
- [x] Apply liquid glass effect
- [x] Add preview for development
- [x] Validate component builds
- [x] Integrate FAB into ContentView
- [x] Connect to NotesManager.addNote()
- [x] Position in bottom-right corner
- [x] Test manually in app
- [x] Write unit tests
- [x] Run test suite
- [x] Verify all success criteria
- [x] Run final build validation

---

## 12. Confidence Assessment

**Confidence Level:** 9/10

**What's Clear:**
- Component structure follows established patterns
- Liquid Glass implementation is straightforward
- Integration with NotesManager is simple
- Design system compliance is well-defined

**What Needs Clarification:**
- None - this is a straightforward implementation

**Additional Research Needed:**
- None - all patterns exist in codebase

---

## Notes

This is a simple, low-complexity feature that demonstrates the PRP structure. It showcases:
- Clean component architecture
- Liquid Glass design system compliance
- State management integration
- Testing approach
- Design token usage

The implementation should be straightforward and take approximately 30-45 minutes including testing.

