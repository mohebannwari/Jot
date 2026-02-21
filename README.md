# Jot

A note-taking application for macOS built with SwiftUI and Apple's Liquid Glass design system (macOS 26+).

## Features

- **Liquid Glass UI** - Native Apple design language with morphing animations and backdrop blur
- **Rich Text Editor** - Formatting toolbar with bold, italic, strikethrough, and more
- **Folders** - Organize notes into collapsible folder sections
- **Pinning** - Pin important notes to keep them at the top
- **Archive** - Archive notes without deleting them
- **Search** - Real-time full-text search with animated glass interface
- **Image Attachments** - Inline image display with gallery preview
- **Voice Recording** - Audio capture with waveform visualization and speech transcription
- **AI Tools** - Note summarization and AI-powered enhancements
- **Web Clips** - Save web content with metadata into notes
- **Export** - Export notes to PDF, Markdown, or HTML
- **Themes** - Light and dark mode toggle

## Requirements

- macOS 26+ (Tahoe)
- Xcode 16+ with macOS 26 SDK

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
├── App/                        # App lifecycle and entry point
│   ├── JotApp.swift
│   └── ContentView.swift
├── Models/                     # Data layer and business logic
│   ├── Note.swift              # Core note model
│   ├── Folder.swift            # Folder model
│   ├── NotesManager.swift      # Note persistence and CRUD
│   ├── SearchEngine.swift      # Full-text search
│   ├── AudioRecorder.swift     # Voice recording
│   ├── Transcriber.swift       # Speech-to-text transcription
│   └── SwiftData/              # SwiftData persistence layer
│       ├── NoteEntity.swift
│       ├── FolderEntity.swift
│       └── TagEntity.swift
├── Views/
│   ├── Components/             # Reusable UI components
│   │   ├── NoteCard.swift
│   │   ├── FolderSection.swift
│   │   ├── NoteToolsBar.swift
│   │   ├── EditToolbar.swift
│   │   ├── FloatingSearch.swift
│   │   ├── AIToolsOverlay.swift
│   │   ├── ImageAttachmentView.swift
│   │   ├── TodoRichTextEditor.swift
│   │   ├── ExportFormatSheet.swift
│   │   └── ...
│   └── Screens/                # Full-screen views
│       ├── CanvasView.swift     # Main notes canvas
│       └── NoteDetailView.swift # Note editing view
├── Utils/                      # Utilities and extensions
│   ├── ThemeManager.swift
│   ├── GlassEffects.swift
│   ├── NoteExportService.swift
│   ├── ImageStorageManager.swift
│   ├── TextFormattingManager.swift
│   └── ...
└── Resources/                  # Assets and design tokens
    └── Assets.xcassets/
```

## Technology Stack

- **SwiftUI** (macOS 26+)
- **SwiftData** - Persistent storage
- **AVFoundation** - Audio recording
- **Speech** - Voice transcription
- **Liquid Glass** - Apple's design system (macOS Tahoe)
- **XCTest** - Unit testing

## Design Reference

- **Figma**: https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot?node-id=0-1&p=f&t=Exr6XkLRSkF2tndZ-0
- **Guide**: `LIQUID_GLASS_GUIDE.md`

## Development Workflow

This project uses a context engineering framework for AI-assisted development. Features are specified via Product Requirements Prompts (PRPs).

```
1. Describe your feature in INITIAL.md
2. Generate a PRP: /generate-prp INITIAL.md
3. Execute: /execute-prp PRPs/your-feature.md
```

See `CONTEXT_ENGINEERING.md` for the complete guide.

## Documentation

| File | Description |
|------|-------------|
| `CLAUDE.md` | Architecture, patterns, and AI instructions |
| `AGENTS.md` | Repository structure and commands |
| `LIQUID_GLASS_GUIDE.md` | Liquid Glass implementation guide |
| `CONTEXT_ENGINEERING.md` | AI-assisted development workflow |
| `CHANGELOG.md` | Version history |
| `PROJECT_STATUS.md` | Current state and known issues |

## License

[Add license information]
