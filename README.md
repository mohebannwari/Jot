# Jot

A note-taking app for macOS built with SwiftUI and Apple's Liquid Glass design system (macOS 26+).

## Features

- **Liquid Glass UI** -- Native Apple design language with morphing animations and glass material effects
- **Rich Text Editor** -- Bold, italic, underline, strikethrough, headings (H1/H2/H3), alignment, and custom text colors
- **Todo Checkboxes** -- Inline checkable items with serialized markup persistence
- **Split-Pane Editing** -- Drag-to-split for side-by-side dual-note editing with adjustable ratio
- **Folders** -- Color-coded folder organization with archive support
- **Pinning** -- Pin important notes to keep them at the top of the sidebar
- **Search** -- Debounced full-text search with recent query history
- **Image Attachments** -- Inline images with width ratio control and gallery preview
- **File Attachments** -- Attach and preview files (PDFs, documents) with QuickLook
- **Web Clips** -- Save web content with Open Graph metadata into notes
- **Voice Recording** -- Audio capture with waveform visualization and speech-to-text transcription
- **AI Writing Tools** -- Summarization, key points, proofreading, and content editing via Apple Intelligence
- **Export** -- PDF, Markdown, and HTML export with embedded images
- **Themes** -- Light, dark, and system mode with body font selection (Charter, System, Mono)
- **Trash** -- Soft-delete with restore and permanent deletion

## Requirements

- macOS 26+ (Tahoe)
- Xcode 26+ with macOS 26 SDK

## Getting Started

1. Clone the repository
2. Open `Jot.xcodeproj` in Xcode
3. Select the macOS target and build

## Build & Test

```bash
# Build
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build

# Run tests
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test

# Clean build
xcodebuild -project Jot.xcodeproj -scheme Jot clean
```

## Project Structure

```
Jot/
├── App/
│   ├── JotApp.swift                    # App entry point, window config, theme application
│   └── ContentView.swift               # Sidebar, note list, split sessions, overlay routing
├── Models/
│   ├── Note.swift                      # Core note model
│   ├── Folder.swift                    # Folder model with color coding
│   ├── SearchEngine.swift              # Debounced full-text search
│   ├── AudioRecorder.swift             # Voice recording via AVFoundation
│   ├── Transcriber.swift               # Speech-to-text transcription
│   ├── NoteDragItem.swift              # Drag-and-drop transfer
│   ├── NoteSelectionPolicy.swift       # Multi-selection logic
│   ├── NoteSelectionInteraction.swift  # Selection gesture handling
│   └── SwiftData/
│       ├── NoteEntity.swift            # SwiftData note persistence
│       ├── FolderEntity.swift          # SwiftData folder persistence
│       └── SimpleSwiftDataManager.swift # CRUD operations and queries
├── Views/
│   ├── Components/
│   │   ├── TodoRichTextEditor.swift    # Rich text editor with markup serialization
│   │   ├── FloatingEditToolbar.swift   # Formatting toolbar (bold, italic, headings, etc.)
│   │   ├── FloatingColorPicker.swift   # Text color picker
│   │   ├── FloatingSearch.swift        # Search overlay
│   │   ├── FloatingSettings.swift      # Preferences panel (theme, font)
│   │   ├── AIToolsOverlay.swift        # AI writing tools interface
│   │   ├── AIResultPanel.swift         # AI output display
│   │   ├── EditContentFloatingPanel.swift # AI content rewriting
│   │   ├── ProofreadPillView.swift     # Proofread annotation pills
│   │   ├── NoteToolsBar.swift          # Note-level actions bar
│   │   ├── MicCaptureControl.swift     # Voice recording + transcription
│   │   ├── WebClipView.swift           # Web clip display with OG metadata
│   │   ├── ImagePickerControl.swift    # Image insertion
│   │   ├── FileAttachmentTagView.swift # File attachment inline display
│   │   ├── QuickLookOverlayView.swift  # File preview
│   │   ├── FolderSection.swift         # Sidebar folder list
│   │   ├── ArchivedNoteRow.swift       # Archived note display
│   │   ├── SplitNotePickerView.swift   # Split session note selector
│   │   ├── SplitOptionMenu.swift       # Split layout options
│   │   ├── CreateFolderSheet.swift     # New folder dialog
│   │   ├── TrashSheet.swift            # Trash management
│   │   ├── ExportFormatSheet.swift     # Export format selection
│   │   ├── CommandMenu.swift           # Global keyboard shortcuts
│   │   ├── BackdropBlurView.swift      # NSVisualEffectView bridge
│   │   └── WaveformView.swift          # Audio waveform visualization
│   └── Screens/
│       ├── NoteDetailView.swift        # Note editing container
│       └── NoteDetailView+Actions.swift # Note action handlers
├── Utils/
│   ├── ThemeManager.swift              # Light/dark/system theme with KVO
│   ├── FontManager.swift               # Charter/System/Mono body font styles
│   ├── GlassEffects.swift              # Liquid Glass helpers and modifiers
│   ├── TextFormattingManager.swift     # Rich text formatting operations with undo
│   ├── AppleIntelligenceService.swift  # FoundationModels AI integration
│   ├── NoteExportService.swift         # PDF/Markdown/HTML export
│   ├── ImageStorageManager.swift       # Image persistence
│   ├── FileAttachmentStorageManager.swift # File attachment persistence
│   ├── WebMetadataFetcher.swift        # Open Graph metadata fetching
│   ├── ThumbnailCache.swift            # Image thumbnail caching
│   ├── FloatingToolbarPositioner.swift # Toolbar positioning logic
│   ├── TrafficLightAligner.swift       # macOS window chrome alignment
│   ├── HapticManager.swift             # Haptic feedback
│   └── Extensions.swift               # SwiftUI and Foundation extensions
└── Ressources/
    └── Assets.xcassets/                # Colors, images, and icon assets
```

## Technology Stack

- **SwiftUI** (macOS 26+) with Liquid Glass
- **SwiftData** for persistent storage
- **FoundationModels** for Apple Intelligence features
- **AVFoundation** for audio recording
- **Speech** for voice transcription
- **CoreGraphics** for PDF export

## Design

- **Figma**: [Jot Design File](https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot)
- **Design System**: `.claude/rules/design-system.md`

## License

All rights reserved.
