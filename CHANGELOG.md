# Changelog

All notable changes to the Jot project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-01-08

### Added
- **Liquid Glass Search Functionality**: Complete search implementation with morphing animations
  - Search button that expands into full search interface
  - Results container with proper liquid glass styling
  - Integration with note-card-thumbnail asset
  - Inline positioning with bottom actions (same level as "New note" button)
- **Morphing Animation Guidelines**: Added official Apple patterns for liquid glass morphing
  - `GlassEffectContainer` usage for proper morphing
  - `glassEffectID` and `@Namespace` for element identification
  - `.bouncy` animation integration for fluid transitions
- **Enhanced Design System Rules**: Updated with morphing animation patterns
- **Changelog System**: Established changelog for tracking major changes

### Changed
- **Search Container Structure**: Results now populate inside search bar container maintaining parent padding
- **Asset Integration**: Switched to proper asset-based thumbnails with 4px corner radius
- **Background Separation**: Added distinct background to results container for better visual separation
- **Corner Radius Compliance**: Updated to follow Apple's corner radius guidelines (4px, 12px, 24px)

### Fixed
- **Search Positioning**: Fixed search button positioning to be inline with other bottom actions
- **Button Responsiveness**: Resolved multi-click requirement issues across all interactive elements
- **Animation Compliance**: Replaced custom animations with Apple's standard liquid glass animations
- **Glass Effect Violations**: Removed glass-on-glass stacking violations

### Technical Details
- Updated ContentView.swift with proper search implementation
- Enhanced design_system_rules.mdc with morphing patterns  
- Updated CLAUDE.md with liquid glass animation guidelines
- Build compatibility maintained with Xcode-beta and macOS 26.0 SDK

---

## [0.1.0] - 2025-01-07

### Added
- **Initial Project Setup**: SwiftUI project with macOS 26.0 target
- **Liquid Glass Foundation**: Base implementation of Apple's liquid glass effects
  - `.glassEffect()` integration throughout UI components
  - Proper material backgrounds and translucent effects
- **Core Components**: 
  - NoteCard component with liquid glass styling
  - BottomBar component with interactive glass effects
  - Basic search button implementation
- **Design System Architecture**:
  - Color token system with semantic naming
  - Typography scale (10px-17px) with proper weights
  - Spacing system (4px-60px) for consistent layouts
  - Corner radius system (4px-24px, Capsule)
- **Asset Management**: SVG and PNG asset integration system
- **Project Structure**: Organized file hierarchy for scalability

### Technical Foundation  
- SwiftUI as primary UI framework
- iOS 26+ / macOS Tahoe+ SDK requirements
- Figma integration via Model Context Protocol
- Git repository initialization with proper gitignore

### Initial Features
- Note card grid display with liquid glass effects
- Bottom navigation with theme toggle
- Basic hover states and animations
- Window management (min 1109x782)

---

*Note: This changelog tracks significant functional, design, and architectural changes to maintain project development history.*