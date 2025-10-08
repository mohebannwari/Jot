# Noty Code Examples

This directory contains representative code patterns extracted from the Noty codebase. These examples serve as reference implementations for AI assistants when generating new code.

## Purpose

When implementing new features, AI assistants should:
1. Review these examples to understand established patterns
2. Follow the same architectural approaches
3. Maintain consistency with existing code style
4. Apply the same design system principles

## Examples Overview

### Component Pattern (`component_pattern.swift`)
**Extracted from:** `Noty/Views/Components/NoteCard.swift`

**Demonstrates:**
- SwiftUI component structure (props → state → computed properties → body)
- Environment object usage for shared state
- Liquid Glass effect application
- Hover state management with animations
- MARK comments for code organization
- Semantic color usage from Assets.xcassets
- Typography and spacing standards

**Use this when:**
- Creating new SwiftUI view components
- Building card or container views
- Implementing interactive elements with hover states

---

### Manager Pattern (`manager_pattern.swift`)
**Extracted from:** `Noty/Models/NotesManager.swift`

**Demonstrates:**
- State management with @Published properties
- CRUD operations pattern
- JSON persistence strategy
- @MainActor usage for UI thread safety
- Error handling approach
- Seed data generation

**Use this when:**
- Creating new manager classes for features
- Implementing data persistence
- Managing application state
- Building CRUD functionality

---

### Glass Effects Pattern (`glass_effects_pattern.swift`)
**Extracted from:** `Noty/Utils/GlassEffects.swift`

**Demonstrates:**
- Liquid Glass effect modifiers
- OS version checking with @available
- Fallback strategies for older OS versions
- Standard glass, tinted glass, and thin glass variants
- GlassEffectContainer for morphing animations
- Translucent background effects

**Use this when:**
- Applying glass effects to UI elements
- Creating glass-styled buttons or surfaces
- Building floating UI components
- Implementing background effects

---

### View Architecture Pattern (`view_architecture.swift`)
**Extracted from:** `Noty/App/ContentView.swift`

**Demonstrates:**
- Root view composition
- State object creation and environment injection
- Tab view structure
- Navigation patterns
- Layout composition with ZStack/VStack/HStack
- Toolbar implementation

**Use this when:**
- Building screen-level views
- Composing multiple components
- Implementing navigation
- Setting up environment objects

---

### Testing Pattern (`testing_pattern.swift`)
**Extracted from:** `NotyTests/NotesManagerTests.swift`

**Demonstrates:**
- XCTest setup and structure
- @MainActor testing for async code
- Temporary storage pattern for isolated tests
- Arrange-Act-Assert pattern
- File system cleanup

**Use this when:**
- Writing unit tests for managers
- Testing CRUD operations
- Verifying persistence behavior
- Testing state management

---

## Design System Compliance

All examples follow Noty's design system:

### Colors
Use semantic colors from `Noty/Ressources/Assets.xcassets/`:
- `BackgroundColor`
- `CardBackgroundColor`
- `PrimaryTextColor`
- `SecondaryTextColor`
- `TertiaryTextColor`
- `SurfaceTranslucentColor`
- `TagBackgroundColor`
- `TagTextColor`

### Typography
```swift
// Title
.font(.system(size: 17, weight: .semibold))

// Body
.font(.system(size: 14, weight: .regular))

// Small
.font(.system(size: 12, weight: .medium))

// Tiny
.font(.system(size: 10, weight: .medium))
```

### Spacing
Standard values: 4, 6, 8, 12, 16, 18, 24, 60

### Corner Radius
Standard values: 4, 20, 24, or Capsule

### Animations
```swift
// Bouncy animation for glass effects
withAnimation(.bouncy(duration: 0.3)) { }

// Smooth animation for transitions
withAnimation(.smooth) { }

// Ease in/out for deletions
withAnimation(.easeInOut(duration: 0.25)) { }
```

## iOS 26+ / macOS 26+ Features

These examples target the latest SwiftUI enhancements:
- `.glassEffect()` API for Liquid Glass
- `@MainActor` for UI thread safety
- Improved `@Observable` and `@Published` patterns
- Enhanced toolbar APIs
- Native glass button styles

## File Organization

Each example file:
- Contains focused, simplified code
- Includes comprehensive comments
- Shows complete implementation patterns
- References the source file for full context

## How to Use These Examples

1. **Read the example** that matches your use case
2. **Understand the pattern** being demonstrated
3. **Adapt the pattern** to your specific needs
4. **Maintain consistency** with the established style
5. **Reference the source file** for complete context if needed

## Contributing

When adding new patterns to this directory:
- Extract simplified versions of production code
- Add comprehensive comments explaining decisions
- Update this README with the new example
- Ensure examples follow design system guidelines

