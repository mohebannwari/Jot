# Repository Guidelines

## Context Engineering Workflow

This repository uses a **context engineering framework** for systematic feature development with AI assistance.

### Quick Start
1. Create feature request: Copy `INITIAL.md` and describe your feature
2. Generate PRP: `/generate-prp your-feature.md` 
3. Execute implementation: `/execute-prp PRPs/your-feature-name.md`

### Key Resources
- `CONTEXT_ENGINEERING.md` - Complete framework guide
- `INITIAL_EXAMPLE.md` - Example feature request
- `examples/` - Code patterns to follow
- `PRPs/workflows/` - Development workflows

This ensures all implementations follow project conventions and design system requirements.

## Project Structure & Module Organization
- Entry point lives in `Noty/App/NotyApp.swift` with the root view defined in `Noty/App/ContentView.swift`.
- Screens reside under `Noty/Views/Screens`, while reusable UI components belong in `Noty/Views/Components`.
- Domain logic and managers (e.g., `NotesManager`, `SearchManager`) are placed in `Noty/Models`.
- Helpers and extensions live in `Noty/Utils`; assets are stored in `Noty/Ressources` and `Noty/Ressources/Assets.xcassets`.
- Maintain one primary type per Swift file; align filenames with the contained type.

## Build, Test, and Development Commands
- `open Noty.xcodeproj` — launch the project in Xcode, choose the `Noty` scheme, select a Simulator, then Run.
- `xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build` — perform a command-line build of the Debug configuration.
- `xcodebuild -project Noty.xcodeproj -scheme Noty clean` — clean derived build artifacts before a fresh build.
- When tests exist: `xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=iOS Simulator,name=iPhone 15' test` — execute the XCTest suite on the chosen simulator.

## Coding Style & Naming Conventions
- Target Swift 5+, using 4-space indentation and keeping lines under roughly 120 characters.
- Types adopt PascalCase (`NoteCard`, `ThemeManager`); properties, methods, and variables use camelCase; enum cases stay lowerCamelCase.
- Organize views by feature, keep shared UI generic, and document any public-facing APIs.

## Testing Guidelines
- Use XCTest under a `NotyTests` target; name files `FeatureNameTests.swift` and methods `test...`.
- Focus coverage on `Models` and `Utils`, adding lightweight UI smoke tests as needed.
- Run tests via Xcode (Command-U) or the CLI command listed above; ensure new tests fail before fixes and pass afterward.

## Commit & Pull Request Guidelines
- Write concise, imperative commits reflecting scope (e.g., `feat: add note search`, `fix(models): prevent empty titles`).
- PRs should include a clear summary, rationale, relevant issue links, and screenshots for visual changes.
- Verify builds succeed, remove unused assets, and update documentation before requesting review.

## Security & Configuration Tips
- Never commit secrets or credentials to `Info.plist` or source files.
- Place new assets only under `Noty/Ressources` or `Noty/Ressources/Assets.xcassets`, and update project settings if folders move.
