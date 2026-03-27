# Meeting Notes Feature -- Design Spec

**Date:** 2026-03-27
**Status:** Approved
**Approach:** Lightweight Extension (Approach A)

---

## Context

Jot's AI toolkit currently offers summarization, key points, proofreading, content editing, translation, and text generation -- all powered by on-device Apple Intelligence via `AppleIntelligenceService`. The app also has voice recording (mic capture via `AVAudioEngine` + transcription via `SFSpeechRecognizer`) in the bottom toolbar.

This feature adds AI Meeting Notes -- long-form mic recording with real-time transcription and post-meeting AI summarization -- positioned as a new tool in the AI toolbar. The goal is a Notion-level meeting notes experience built entirely on-device with zero cloud dependency.

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Distribution | Direct download (notarized) | No sandbox restrictions |
| Audio capture | Mic-only (AVAudioEngine) | User preference; simplifies architecture |
| Transcription | SpeechAnalyzer (macOS 26) | On-device, fast, no model download; WhisperKit + diarization deferred to v2 |
| Data model | Tabbed view inside one note | Mirrors Notion; clean UX |
| UX placement | New tool in AI toolbar; voice record stays in bottom bar | Both features coexist |
| Summarization | FoundationModels with chunked pipeline | 4K token limit requires hierarchical summarization |
| MVP approach | Functionality first with polished Liquid Glass UI | User iterates on design after core works |

---

## Data Model

### Note / NoteEntity Extensions

```swift
// Added to Note.swift
var isMeetingNote: Bool = false
var meetingTranscript: String = ""      // serialized transcript segments
var meetingSummary: String = ""         // AI-generated summary (rich text serialized)
var meetingDuration: TimeInterval = 0   // recording duration in seconds
var meetingLanguage: String = ""        // detected language code (e.g., "en-US")
```

```swift
// Added to NoteEntity.swift (SwiftData @Model)
var isMeetingNote: Bool = false
var meetingTranscript: String = ""
var meetingSummary: String = ""
var meetingDuration: Double = 0
var meetingLanguage: String = ""
```

Sidebar: meeting notes display a meeting icon badge on `NoteListCard`. Sort and filter like any other note.

### Supporting Types

```swift
// MeetingModels.swift

struct TranscriptSegment: Codable, Identifiable {
    let id: UUID
    var text: String
    var timestamp: TimeInterval     // seconds from recording start
    var isFinal: Bool               // false while SpeechAnalyzer is still refining
}

@Generable
struct MeetingChunkSummary {
    @Guide(description: "3-5 key points from this portion of the meeting")
    var keyPoints: [String]
    @Guide(description: "Action items with assignee if mentioned")
    var actionItems: [MeetingActionItem]
    @Guide(description: "Decisions or conclusions reached")
    var decisions: [String]
}

@Generable
struct MeetingActionItem {
    var description: String
    @Guide(description: "Person responsible, or 'Unassigned' if not mentioned")
    var assignee: String
}

@Generable
struct MeetingSummaryResult {
    @Guide(description: "One-sentence title summarizing the meeting")
    var title: String
    @Guide(description: "2-3 paragraph summary of the meeting")
    var summary: String
    @Guide(description: "All key points from the meeting")
    var keyPoints: [String]
    @Guide(description: "All action items extracted")
    var actionItems: [MeetingActionItem]
    @Guide(description: "Key decisions made")
    var decisions: [String]
}
```

---

## Audio Capture

### AudioRecorder Extension

Add `startLongFormRecording()` to the existing `AudioRecorder` class:

- Same `AVAudioEngine` pipeline, same M4A/AAC format (44.1kHz, mono, 96kbps)
- No duration cap (voice notes have implicit short-clip expectations; meeting mode removes those)
- Existing level metering (28-bar waveform) stays active for the recording UI
- Existing pause/resume already works -- no changes needed
- Audio saved to `/var/tmp/MeetingCapture/{UUID}.m4a`
- File retained until meeting note is fully processed, then cleaned up via `cleanupMeetingAudio(id:)`

### Permissions

Already in place:
- `com.apple.security.device.audio-input` in `Jot.entitlements`
- `NSMicrophoneUsageDescription` in `Info.plist`

No new permissions required.

---

## Transcription Service

### MeetingTranscriptionService

New class wrapping `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26):

```swift
@MainActor
class MeetingTranscriptionService: ObservableObject {
    @Published var segments: [TranscriptSegment] = []
    @Published var isTranscribing: Bool = false
    @Published var detectedLanguage: String = ""

    // Preset: .progressiveLiveTranscription for real-time results
    // Feeds audio buffers from AVAudioEngine installTap in real-time
    // Emits TranscriptSegment updates via @Published
    // Each segment updates in place until isFinal, then new segment begins

    func startTranscription(audioEngine: AVAudioEngine) async
    func stopTranscription()
    func serializedTranscript() -> String  // for persistence
}
```

**Availability guard:** `#if canImport(Speech)` with `SpeechAnalyzer` availability check. Falls back to `SFSpeechRecognizer` on macOS < 26 (unlikely given deployment target but defensive).

**Real-time flow:**
1. `AVAudioEngine` tap provides `AVAudioPCMBuffer` at ~100ms intervals
2. Buffers fed to `SpeechAnalyzer.analyzeSequence()` as `AsyncStream`
3. `SpeechTranscriber` emits progressive results
4. Each result mapped to `TranscriptSegment` with timestamp
5. UI observes `@Published segments` and auto-scrolls

---

## Chunked Summarization Pipeline

### MeetingSummaryGenerator

New class using existing `AppleIntelligenceService`:

```swift
@MainActor
class MeetingSummaryGenerator {
    // Step 1: Chunk transcript into ~1,000-token segments (~3,000 chars)
    // Step 2: For each chunk, generate MeetingChunkSummary via FoundationModels
    // Step 3: Merge all chunk summaries into combined text
    // Step 4: Final pass -- generate MeetingSummaryResult from merged summaries
    // Step 5: Format into rich text with headings, bullets, checkboxes

    func generateSummary(
        from transcript: [TranscriptSegment],
        manualNotes: String
    ) async throws -> MeetingSummaryResult

    func formatAsRichText(_ summary: MeetingSummaryResult) -> String
    // Returns serialized rich text matching Jot's format:
    // [[h1]]Meeting Title[[/h1]]
    // [[h2]]Summary[[/h2]]
    // paragraph text...
    // [[h2]]Key Points[[/h2]]
    // bullet points...
    // [[h2]]Action Items[[/h2]]
    // [x]/[ ] checkbox items...
    // [[h2]]Decisions[[/h2]]
    // bullet points...
}
```

**Token estimation:** ~4 characters per token. 1,000 tokens = ~4,000 characters per chunk. Each chunk summary is ~200-300 tokens. Final merge pass receives all chunk summaries (~200-300 tokens each) plus instructions (~200 tokens). For a 30-minute meeting (~4,000 words / ~20,000 chars), that's ~5-7 chunks, producing ~1,500-2,100 tokens of merged summaries, well within the 4K limit for the final pass.

**Manual notes integration:** The user's manual notes from the "Notes" tab are appended to the final summarization prompt as additional context, improving summary relevance (same approach as Notion).

---

## AI Toolbar Integration

### AIToolsOverlay Changes

Add to the expanded toolbar state (after the existing 4 buttons):

- New button: custom Meeting Notes icon from Figma (node `2574-1484` in Jot design file)
- Same styling as sibling buttons (18pt icon, glass pill, tooltip)
- Tapping posts `.aiMeetingNotesStart` notification
- When recording is active, the button shows a red recording indicator

### AITool Enum Extension

```swift
case meetingNotes  // new case
```

---

## Meeting Notes Floating Panel

### MeetingNotesFloatingPanel

New SwiftUI view following existing panel patterns:

**Layout:**
```
┌──────────────────────────────────────────────┐
│  ● REC  00:12:34              [Pause] [Stop] │  Recording header
├──────────────────────────────────────────────┤
│  [Summary]  [Transcript]  [Notes]            │  Tab bar (glass segmented)
├──────────────────────────────────────────────┤
│                                              │
│  (Tab content area -- scrollable)            │
│                                              │
│  Summary:   Shimmer while generating,        │
│             then formatted rich text         │
│  Transcript: Live streaming segments,        │
│             auto-scroll, timestamps          │
│  Notes:     TextEditor for manual notes      │
│                                              │
└──────────────────────────────────────────────┘
```

**Styling:**
- Width: ~400pt (wider than existing AI panels)
- Corner radius: 22pt
- Background: `liquidGlass` + `appleIntelligenceGlow` during AI processing
- Recording dot: `Color.red` with 1s pulse animation
- Tab bar: glass segmented control with capsule selection indicator
- Transcript segments: monospace or body font, subtle timestamp markers
- Action items in summary: rendered as checkboxes

**States:**
1. **Recording** -- live transcript tab active, red dot pulsing, timer counting
2. **Processing** -- recording stopped, shimmer skeleton on Summary tab, glow active
3. **Complete** -- all tabs populated, "Save to Note" button appears in header
4. **Saved** -- panel can be dismissed, note updated in sidebar

**Interactions:**
- Pause: pauses recording + transcription, button toggles to Resume
- Stop: stops recording, triggers summarization pipeline
- Save: persists meetingTranscript + meetingSummary + meetingDuration to note
- Dismiss: option to discard if not saved (confirmation dialog)

---

## Notification Flow

```
Notification                    Source              Handler              Action
.aiMeetingNotesStart           AIToolsOverlay      NoteDetailView       Create meeting note, show panel, start recording
.aiMeetingNotesPause           Panel controls      NoteDetailView       Pause AudioRecorder + transcription
.aiMeetingNotesResume          Panel controls      NoteDetailView       Resume AudioRecorder + transcription
.aiMeetingNotesStop            Panel controls      NoteDetailView       Stop recording, start summarization
.aiMeetingNotesComplete        SummaryGenerator    NoteDetailView       Update panel with summary, enable Save
.aiMeetingNotesSave            Panel Save button   NoteDetailView       Persist to note, update sidebar
.aiMeetingNotesDismiss         Panel close         NoteDetailView       Cleanup audio files, dismiss panel
```

---

## Files

### New Files (~4-5)

| File | Purpose |
|------|---------|
| `Jot/Models/MeetingTranscriptionService.swift` | SpeechAnalyzer wrapper, real-time transcription |
| `Jot/Models/MeetingSummaryGenerator.swift` | Chunked FoundationModels summarization pipeline |
| `Jot/Views/Components/MeetingNotesFloatingPanel.swift` | Tabbed panel UI (recording, transcript, summary, notes) |
| `Jot/Models/MeetingModels.swift` | TranscriptSegment, @Generable structs, MeetingActionItem |

### Modified Files (~6-7)

| File | Changes |
|------|---------|
| `Jot/Models/Note.swift` | Add isMeetingNote, meetingTranscript, meetingSummary, meetingDuration, meetingLanguage |
| `Jot/Models/SwiftData/NoteEntity.swift` | Add corresponding SwiftData fields + toNote/toEntity mapping |
| `Jot/Models/AudioRecorder.swift` | Add startLongFormRecording(), cleanupMeetingAudio() |
| `Jot/Views/Components/AIToolsOverlay.swift` | Add Meeting Notes button to expanded state |
| `Jot/Views/Screens/NoteDetailView+Actions.swift` | Handle meeting notification flow |
| `Jot/Utils/Extensions.swift` | Add notification names (.aiMeetingNotes*) |
| `Jot/Views/Components/NotePreviewCard.swift` | Meeting icon badge for sidebar |

---

## Implementation Pipeline & Tools

| Phase | Skills & Tools |
|-------|---------------|
| All Swift code | Swift LSP for type verification, jump-to-definition, diagnostics |
| API documentation | Context7 MCP for SpeechAnalyzer, FoundationModels, AVAudioEngine docs |
| Design tokens | Figma MCP for colors, spacing, typography from Jot design system |
| UI implementation | `figma-to-swiftui` + `frontend-design` + `make-interfaces-feel-better` skills |
| Testing | `superpowers:test-driven-development` for each component |
| Debugging | `debugging` skill -- root cause only, no log-based debugging |
| Code review | `superpowers:requesting-code-review` after each major component |
| Completion | `superpowers:verification-before-completion` before any commit |

---

## What's NOT in v1

- No system audio capture (mic only)
- No speaker diarization (SpeechAnalyzer doesn't support it; WhisperKit deferred to v2)
- No automatic meeting detection (user manually starts recording)
- No calendar integration
- No Shortcuts / AppIntents
- No pre-recorded file import
- No timestamps visible in transcript UI (segments are sequential; timestamps stored but not displayed)

---

## v2 Roadmap (Future)

- WhisperKit + SpeakerKit for speaker diarization ("Speaker 1:", "Speaker 2:")
- System audio capture via Core Audio Process Taps (capture other side of calls)
- Meeting detection via NSWorkspace + EventKit calendar polling
- AppIntents / Shortcuts integration ("Start Meeting Notes" shortcut)
- Transcript timestamps and jump-to-source from summary citations
- Pre-recorded audio file import
