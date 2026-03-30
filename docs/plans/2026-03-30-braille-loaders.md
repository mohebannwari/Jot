# Braille CLI-Style Loading Animations

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add braille Unicode character-based loading animations across 3 areas of the app.

**Architecture:** Reusable `BrailleLoader` SwiftUI component with 4 animation patterns (pulse, wave, orbit, breathe), integrated into AI panels, Meeting Notes, and Update Panel.

**Tech Stack:** SwiftUI, Unicode braille characters (U+2800-U+28FF), structured concurrency (Task)

---

## Files Changed

### Created
- `Jot/Views/Components/BrailleLoader.swift` -- Reusable loader with 4 patterns + 3 speed presets

### Modified
- `Jot/Views/Components/AIResultPanel.swift` -- Added BrailleLoader + "Thinking..." label above shimmer
- `Jot/Views/Components/EditContentFloatingPanel.swift` -- Added BrailleLoader + "Editing..." label
- `Jot/Views/Components/TranslateFloatingPanel.swift` -- Added BrailleLoader + "Translating..." label
- `Jot/Views/Components/TextGenFloatingPanel.swift` -- Added BrailleLoader + "Generating..." label
- `Jot/Views/Components/MeetingNotesFloatingPanel.swift` -- Replaced purple pulsing dot with wave BrailleLoader
- `Jot/Views/Components/UpdatePanelView.swift` -- Added `.downloading` variant with orbit BrailleLoader
- `Jot/Utils/UpdateManager.swift` -- Added `isDownloading` state, proper Sparkle lifecycle (found -> downloading -> ready)
- `Jot/App/ContentView.swift` -- Wired downloading state panel in both sidebar layouts

## Pattern Assignments
| Area | Pattern | Rationale |
|------|---------|-----------|
| AI panels | `.pulse` | Calm, thoughtful -- matches "thinking" metaphor |
| Meeting Notes | `.wave` | Flowing data -- echoes audio/transcription |
| Update Panel | `.orbit` | Progress feel -- something is actively happening |
