# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Noty is a SwiftUI-based note-taking application for macOS that implements Apple's 2025 Liquid Glass design system. The app features a card-based interface with advanced search capabilities, rich text editing, and cross-platform glass effects. Built for iOS 26+ and macOS 26+ to leverage the latest SwiftUI enhancements and performance improvements.

## Build & Development Commands

### Building the Project
```bash
# Build the app
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build

# Build for release
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Release build

# Clean build folder
xcodebuild -project Noty.xcodeproj -scheme Noty clean
```

### Testing
```bash
# Run all tests
xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' test

# Run specific test class
xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' -only-testing:NotyTests/NotesManagerTests test
```

### Working with Xcode
- Open `Noty.xcodeproj` in Xcode
- Main scheme: `Noty`
- Test target: `NotyTests`

## Architecture & Code Organization

### Project Structure
```
Noty/
├── App/                    # App lifecycle and entry point
│   ├── NotyApp.swift      # Main app struct with environment setup
│   └── ContentView.swift  # Root view coordinating main UI
├── Models/                 # Data layer and business logic
│   ├── Note.swift         # Core Note model
│   ├── NotesManager.swift # Note persistence and CRUD operations
│   └── SearchEngine.swift # Search functionality
├── Views/
│   ├── Components/        # Reusable UI components
│   └── Screens/          # Full-screen views
├── Utils/                 # Utilities and extensions
│   ├── ThemeManager.swift # Theme state management
│   └── GlassEffects.swift # Liquid Glass implementation
└── Resources/             # Assets and design tokens
    └── Assets.xcassets/   # Color sets and image sets
```

### Key Architectural Patterns

**State Management**: Uses `@StateObject` and `@EnvironmentObject` pattern:
- `NotesManager`: Handles all note data operations and persistence
- `ThemeManager`: Manages light/dark theme switching
- Passed down through environment from `NotyApp.swift`

**Data Flow**:
- `NotesManager` provides `@Published` properties that trigger UI updates
- All note operations go through `NotesManager` methods
- Persistence handled automatically via JSON file storage

**Component Structure**:
- Follow established pattern: props → computed properties → body
- Use private computed properties for complex view logic
- Prefer composition over inheritance for reusable components

## Design System Integration

### Figma Integration
- **Primary Design File**: https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Noty?node-id=0-1&p=f&t=Exr6XkLRSkF2tndZ-0
- Always reference Figma for design tokens, spacing, and component specs
- Use figma-mcp tools for code generation from designs

### Apple Liquid Glass Implementation (iOS 26+/macOS 26+)
**Priority Order** (use first available):
1. Native `.glassEffect()` with `Glass` struct (iOS 26+, macOS 26+)
   - Default: `.glassEffect()` uses `.regular` glass with `Capsule` shape
   - Custom: `.glassEffect(.thin, in: RoundedRectangle(cornerRadius: 20))`
   - Interactive: `.glassEffect(.regular.interactive(true))`
2. `.glassBackgroundEffect()` for visionOS (visionOS 2.4+)
3. SwiftGlass library (cross-platform fallback)
4. `.ultraThinMaterial` (legacy fallback for < iOS 26)

**Key Rules**:
- Use `GlassEffectContainer` to combine multiple glass shapes for morphing animations
- Apply glass effects to floating UI elements only (toolbars, cards, overlays)
- Never stack glass on glass (use `.implicit` display mode when needed)
- Avoid glass backgrounds in scrollable content
- Use `.bouncy` and `.smooth` spring animations for glass state changes
- Assign unique IDs with `.glassEffectID()` for coordinated animations

### Design Tokens Location
- **Colors**: `Noty/Resources/Assets.xcassets/` - semantic color sets
- **Typography**: System fonts with specific size/weight combinations
- **Spacing**: Standardized padding values (4, 6, 8, 12, 16, 18, 24, 60)
- **Corner Radius**: (4, 20, 24, Capsule)

## Development Guidelines

### Component Development
- Always check existing components before creating new ones
- Follow the established component structure pattern
- Use design tokens from Assets.xcassets, never hardcode values
- Implement proper accessibility labels and hints
- Use new button styles: `.buttonStyle(.glass)` or `.buttonStyle(.glassProminent)`

### Code Style
- Use SwiftUI's native APIs and modifiers
- Apply modifiers in logical order: content → layout → styling → behavior
- Use `@MainActor` for ObservableObject classes that update UI
- Prefer `LazyVGrid` for performance with large lists
- Leverage new SwiftUI enhancements (iOS 26+):
  - `@Entry` macro for environment values
  - Improved `@Observable` macro with automatic UI updates
  - New `TabView` with `.sidebarAdaptable` behavior
  - Enhanced toolbar APIs with `.toolbarSpacer()`

### Testing
- Unit tests located in `NotyTests/`
- Focus on testing `NotesManager` operations and `SearchEngine` functionality
- Mock data operations for component testing

## Key Implementation Details

### Notes Persistence
- JSON file storage in user documents directory
- Automatic saving on all CRUD operations
- Seed data generated if storage is empty

### Rich Text Editing (iOS 26+/macOS 26+)
- TextEditor now supports AttributedString for rich text formatting
- Built-in support for bold, italic, underline, strikethrough
- Text styling with fonts, colors, and sizes
- Link detection and custom attributes
- Use `.richTextCapabilities()` modifier to enable/disable features

### Web Content Integration (iOS 26+/macOS 26+)
- Native `WebView` component for embedding web content
- No need for WKWebView wrapping
- Declarative API: `WebView(url: URL(string: "..."))`
- Support for JavaScript interaction and navigation delegates

### Search System
- Full-text search across note title, content, and tags
- Real-time search with debouncing
- Results sorted by relevance and recency
- New section index support for large lists (iOS 26+)

### Performance Improvements (iOS 26+/macOS 26+)
- 40% reduction in GPU usage with Liquid Glass effects
- 39% faster render times (10.2ms vs 16.7ms)
- 38% less memory usage (28MB vs 45MB)
- Improved scroll performance with new instruments

### Theme Management
- System appearance detection with manual override
- Color assets automatically adapt to theme changes
- Theme state persisted across app launches
- New material active appearance control (iOS 26+)

## Working with Assets
- **SVG files**: Custom vector graphics in `Resources/` folder
- **Image assets**: Organized in `Assets.xcassets` with proper naming
- **Color assets**: Semantic naming (BackgroundColor, PrimaryTextColor, etc.)
- Export assets from Figma in appropriate formats (SVG for vectors, PNG for rasters)
- Always make use of the Context7 mcp to retrieve relevant developer documentation about new SDK's and other new updates of an OS
- Never search for ios 18 and macos 15 again, only versions 26 and higher

## Looking for issues / fixing bugs
- Always make a broad examination of the codebase if something doesn't work the way it is intended or if there is a bug.
