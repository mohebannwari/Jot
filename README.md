# Jot

A beautiful note-taking application for macOS built with SwiftUI and Apple's Liquid Glass design system (iOS 26+/macOS 26+).

## Context Engineering Framework

This project uses **context engineering** for systematic AI-assisted development. This ensures all features follow established patterns, apply the design system correctly, and include comprehensive tests.

### Quick Start

1. **Describe your feature** - Copy `INITIAL.md` and fill in requirements
2. **Generate a PRP** - Run `/generate-prp your-feature.md`
3. **Execute implementation** - Run `/execute-prp PRPs/your-feature-name.md`

See `CONTEXT_ENGINEERING.md` for the complete guide.

### Key Resources

- **`CONTEXT_ENGINEERING.md`** - Complete framework guide
- **`INITIAL_EXAMPLE.md`** - Example feature request
- **`examples/`** - Code patterns to follow
  - `component_pattern.swift` - UI component structure
  - `manager_pattern.swift` - State management
  - `glass_effects_pattern.swift` - Liquid Glass effects
  - `view_architecture.swift` - Screen composition
  - `testing_pattern.swift` - Testing patterns
- **`PRPs/templates/`** - PRP templates
- **`PRPs/workflows/`** - Development workflows
  - `agentic_development.md` - Task decomposition
  - `validation_loops.md` - Self-correcting validation
  - `context_gathering.md` - Context collection

### Custom Commands

- **`/generate-prp`** - Generate comprehensive Product Requirements Prompt
- **`/execute-prp`** - Execute PRP to implement feature

## Design Reference

- **Figma**: https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot?node-id=0-1&p=f&t=Exr6XkLRSkF2tndZ-0
- **Design System**: Apple Liquid Glass (iOS 26+/macOS 26+)

## Documentation

### Project Guidelines
- **`CLAUDE.md`** - Architecture, patterns, and conventions
- **`AGENTS.md`** - Repository structure and commands
- **`LIQUID_GLASS_GUIDE.md`** - Liquid Glass implementation guide
- **`FIGMA.md`** - Design file usage notes

### Build & Test

```bash
# Build the app
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build

# Run tests
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test

# Clean build
xcodebuild -project Jot.xcodeproj -scheme Jot clean
```

### Project Structure

```
Jot/
├── App/                    # App lifecycle and entry point
│   ├── JotApp.swift      # Main app struct
│   └── ContentView.swift  # Root view
├── Models/                 # Data layer and business logic
│   ├── Note.swift         # Core Note model
│   ├── NotesManager.swift # Note persistence and CRUD
│   └── SearchEngine.swift # Search functionality
├── Views/
│   ├── Components/        # Reusable UI components
│   └── Screens/          # Full-screen views
├── Utils/                 # Utilities and extensions
│   ├── ThemeManager.swift # Theme management
│   └── GlassEffects.swift # Liquid Glass implementation
└── Resources/             # Assets and design tokens
    └── Assets.xcassets/   # Color sets and images
```

## Technology Stack

- **SwiftUI** (iOS 26+/macOS 26+)
- **Apple Liquid Glass** design system
- **JSON persistence** for notes
- **XCTest** for testing

## Getting Started

1. Clone the repository
2. Open `Jot.xcodeproj` in Xcode
3. Build and run on macOS target (iOS 26+/macOS 26+ required)
4. Review `CONTEXT_ENGINEERING.md` to understand the development workflow

## Contributing

When adding features:

1. Create an INITIAL.md describing the feature
2. Generate a PRP with `/generate-prp`
3. Review the generated PRP for completeness
4. Execute with `/execute-prp`
5. Verify all validation gates pass
6. Submit PR with PRP reference

See `CONTEXT_ENGINEERING.md` for detailed workflow.

## License

[Add license information]

