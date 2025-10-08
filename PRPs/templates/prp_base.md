# Product Requirements Prompt: {Feature Name}

## Metadata
- **Created**: {Date}
- **Target OS**: iOS 26+ / macOS 26+
- **Confidence**: {X/10}
- **Estimated Complexity**: {Low/Medium/High/Very High}

---

## 1. Feature Overview

### Purpose
{Describe what this feature does and why it's needed}

### User Story
As a {user type}, I want to {goal} so that {benefit}.

### Key Requirements
- Requirement 1
- Requirement 2
- Requirement 3

---

## 2. Context & Background

### Existing Architecture
{Describe how this fits into the current Noty architecture}

**Related Components:**
- `Component1` - {description}
- `Component2` - {description}

**State Management:**
- Which managers are involved (NotesManager, ThemeManager, etc.)
- How state flows through the app
- Where this feature's state will live

**Data Flow:**
```
User Action → State Update → UI Refresh
{Describe the specific data flow for this feature}
```

### Dependencies
**Internal:**
- Files to import or extend
- Existing utilities to leverage

**External:**
- SwiftUI frameworks needed
- Apple APIs required (iOS 26+/macOS 26+)

---

## 3. Architecture & Design Patterns

### File Structure
```
Noty/
├── Models/
│   └── {ManagerName}.swift           # State management
├── Views/
│   ├── Components/
│   │   └── {ComponentName}.swift     # Reusable UI
│   └── Screens/
│       └── {ScreenName}.swift        # Full screen view
└── Utils/
    └── {UtilityName}.swift           # Helpers
```

### Component Structure Pattern
Follow this established pattern from existing components:

```swift
import SwiftUI

struct ComponentName: View {
    // MARK: - Properties
    // Props passed from parent
    let prop: Type
    
    // Environment objects for shared state
    @EnvironmentObject private var notesManager: NotesManager
    @EnvironmentObject private var themeManager: ThemeManager
    
    // MARK: - State
    // Local component state
    @State private var isHovering = false
    @State private var localValue = ""
    
    // MARK: - Computed Properties
    // Complex logic extracted from body
    private var computedValue: Type {
        // Calculation here
    }
    
    // MARK: - Body
    var body: some View {
        // View hierarchy
    }
    
    // MARK: - Helper Methods
    private func helperMethod() {
        // Logic here
    }
}
```

### State Management Pattern
```swift
@MainActor
final class FeatureManager: ObservableObject {
    // Published properties trigger UI updates
    @Published var items: [Item] = []
    
    // Private storage
    private let storageURL: URL
    
    // MARK: - Initialization
    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultURL()
        load()
    }
    
    // MARK: - CRUD Operations
    func addItem(_ item: Item) {
        items.append(item)
        save()
    }
    
    // MARK: - Persistence
    private func load() { /* Load from disk */ }
    private func save() { /* Save to disk */ }
}
```

---

## 4. Design System Compliance

### Liquid Glass Effects
{Specify which glass effects to use and where}

**Priority Order (use first available):**
1. Native `.glassEffect()` with `Glass` struct (iOS 26+, macOS 26+)
2. `.glassBackgroundEffect()` for visionOS (visionOS 2.4+)
3. `.ultraThinMaterial` (legacy fallback)

**Application:**
```swift
// Standard liquid glass
.liquidGlass(in: RoundedRectangle(cornerRadius: 24))

// Tinted liquid glass
.tintedLiquidGlass(in: Capsule(), tint: Color("SurfaceTranslucentColor"))

// Thin liquid glass for subtle elements
.thinLiquidGlass(in: Circle())
```

**Rules:**
- Apply glass to floating UI elements only (toolbars, cards, overlays)
- Never stack glass on glass
- Use `.bouncy` animations with 0.3 duration for glass state changes
- Interactive elements need `.glassEffect(.regular.interactive(true))`

### Color Usage
Use semantic colors from `Noty/Ressources/Assets.xcassets/`:

- `BackgroundColor` - Main app background
- `CardBackgroundColor` - Card surfaces
- `PrimaryTextColor` - Main text
- `SecondaryTextColor` - Secondary text
- `TertiaryTextColor` - Tertiary text
- `SurfaceTranslucentColor` - Glass tints
- `TagBackgroundColor` - Tag backgrounds
- `TagTextColor` - Tag text

**Never hardcode color values.**

### Typography
```swift
// Titles
.font(.system(size: 17, weight: .semibold))

// Body text
.font(.system(size: 14, weight: .regular))

// Small text
.font(.system(size: 12, weight: .medium))

// Tiny text
.font(.system(size: 10, weight: .medium))
```

### Spacing
Standard padding values: 4, 6, 8, 12, 16, 18, 24, 60

### Corner Radius
Standard values: 4, 20, 24, or Capsule

### Animations
```swift
// Standard glass animation
withAnimation(.bouncy(duration: 0.3)) {
    state.toggle()
}

// Smooth transitions
withAnimation(.smooth) {
    value = newValue
}
```

---

## 5. Implementation Steps

### Step 1: {Step Name}
**Objective:** {What this step accomplishes}

**Files to Create/Modify:**
- `Path/To/File.swift` - {Purpose}

**Implementation Details:**
```swift
// Code pattern to follow
```

**Validation:**
```bash
# Command to verify this step
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build
```

**Success Criteria:**
- [ ] Builds without errors
- [ ] Follows component structure pattern
- [ ] Uses design tokens

---

### Step 2: {Step Name}
{Repeat structure for each step}

---

### Step N: Write Tests
**Objective:** Ensure feature works correctly with comprehensive tests

**Files to Create:**
- `NotyTests/{FeatureName}Tests.swift`

**Test Pattern:**
```swift
import XCTest
@testable import Noty

final class FeatureTests: XCTestCase {
    @MainActor
    func testFeatureBehavior() throws {
        // Arrange
        let manager = FeatureManager(storageURL: tempURL, seedIfEmpty: false)
        
        // Act
        let result = manager.performAction()
        
        // Assert
        XCTAssertEqual(result, expectedValue)
    }
}
```

**Validation:**
```bash
xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' test
```

---

## 6. Success Criteria

### Functional Requirements
- [ ] Feature performs core functionality as specified
- [ ] Edge cases handled gracefully
- [ ] Error states display appropriate feedback
- [ ] State persists across app launches (if applicable)

### Design System Compliance
- [ ] Liquid Glass effects applied correctly
- [ ] No glass-on-glass violations
- [ ] Semantic colors used (no hardcoded values)
- [ ] Typography follows standards
- [ ] Spacing uses standard values
- [ ] Animations use .bouncy(duration: 0.3)

### Code Quality
- [ ] Follows established component structure
- [ ] State management pattern implemented correctly
- [ ] Comprehensive comments explain complex logic
- [ ] Proper error handling
- [ ] Accessibility labels added
- [ ] One primary type per file

### Testing
- [ ] Unit tests cover core functionality
- [ ] Tests follow established patterns
- [ ] All tests pass
- [ ] Edge cases tested

---

## 7. Validation Gates

### Build Validation
```bash
# Must succeed
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build
```

### Test Validation
```bash
# Must pass all tests
xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' test
```

### Clean Build (if needed)
```bash
xcodebuild -project Noty.xcodeproj -scheme Noty clean
```

---

## 8. Testing Requirements

### Unit Tests Location
`NotyTests/{FeatureName}Tests.swift`

### Test Cases Required
1. **Test basic functionality**
   - Arrange: Set up initial state
   - Act: Perform action
   - Assert: Verify expected result

2. **Test edge cases**
   - Empty state handling
   - Maximum values
   - Invalid input

3. **Test persistence (if applicable)**
   - Save and reload
   - Verify data integrity

### Test Pattern Reference
See `NotyTests/NotesManagerTests.swift` for established testing patterns.

---

## 9. Gotchas & Considerations

### Common Pitfalls
- {List potential issues}
- {Known problems to avoid}

### iOS 26+/macOS 26+ Specific
- Requires `.glassEffect()` API
- Uses new `@Entry` macro for environment values
- Leverages improved `@Observable` macro

### Performance Considerations
- {Any performance concerns}
- {Optimization strategies}

---

## 10. Documentation & References

### Figma Design
- https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Noty
- {Specific artboard or component references}

### Apple Documentation
- {Link to relevant Apple docs}
- {Link to WWDC sessions}

### Example Files
Reference these examples:
- `examples/component_pattern.swift` - Component structure
- `examples/manager_pattern.swift` - State management
- `examples/glass_effects_pattern.swift` - Liquid Glass usage

### Related Code
- `Existing/File.swift` - {What to reference}

---

## 11. Implementation Checklist

Use this checklist during implementation:

- [ ] Read entire PRP and understand requirements
- [ ] Review all referenced example files
- [ ] Create file structure as specified
- [ ] Implement Step 1
- [ ] Validate Step 1
- [ ] Implement Step 2
- [ ] Validate Step 2
- [ ] {Continue for all steps}
- [ ] Write comprehensive tests
- [ ] Run test suite
- [ ] Verify all success criteria
- [ ] Check design system compliance
- [ ] Add code comments
- [ ] Run final build validation
- [ ] Test feature manually

---

## 12. Confidence Assessment

**Confidence Level:** {X/10}

**What's Clear:**
- {Aspect 1}
- {Aspect 2}

**What Needs Clarification:**
- {Question 1}
- {Question 2}

**Additional Research Needed:**
- {Topic 1}
- {Topic 2}

---

## Notes

{Any additional context, considerations, or notes}

