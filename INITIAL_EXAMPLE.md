# Feature Request: Voice Note Recording with Liquid Glass UI

This is an example of a well-structured feature request that demonstrates how to use the INITIAL.md template effectively.

---

## FEATURE

**What do you want to build?**

Add voice note recording capability to Noty with a beautiful Liquid Glass interface. Users should be able to:

1. **Start recording** by tapping a microphone button in the bottom toolbar
2. **See a real-time waveform** visualization while recording
3. **Stop recording** to automatically create a new note with:
   - Transcribed text as note content
   - Audio file attached
   - Auto-generated title from the first few words
   - Timestamp and duration metadata
4. **Play back** recorded audio from the note detail view
5. **Edit transcription** after recording completes

The interface should follow Apple's Liquid Glass design language with:
- Glass effect on recording controls
- Animated waveform with gradient colors
- Bouncy animations for state transitions
- Hover effects on interactive elements

**User Story:**

As a Noty user, I want to quickly record voice notes so that I can capture thoughts hands-free without typing.

---

## EXAMPLES

**Which example files should be referenced?**

- `examples/component_pattern.swift` - For building the recording UI component
- `examples/manager_pattern.swift` - For creating the AudioRecorder manager
- `examples/glass_effects_pattern.swift` - For applying glass effects to controls
- `examples/view_architecture.swift` - For integrating into ContentView
- `examples/testing_pattern.swift` - For writing audio manager tests

**Existing code to reference:**

- `Noty/Models/AudioRecorder.swift` - Existing audio recording infrastructure (if it exists)
- `Noty/Views/Components/NoteCard.swift` - Component structure and glass effects
- `Noty/Views/Components/BottomBar.swift` - Toolbar pattern for adding new controls
- `Noty/Models/NotesManager.swift` - Pattern for saving notes with metadata
- `Noty/Utils/GlassEffects.swift` - Available glass effect modifiers

---

## DOCUMENTATION

**External resources:**

- Apple AVFoundation: https://developer.apple.com/documentation/avfoundation/
- Speech Recognition API: https://developer.apple.com/documentation/speech
- SwiftUI Audio Visualization: Search for "SwiftUI waveform visualization"
- iOS 26 Audio enhancements: Latest WWDC session on audio

**Figma designs:**

- https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Noty
- Component: "Voice Recording Interface" (if exists)
- Reference: Microphone button with glass effect
- Reference: Waveform visualization with gradient

**Related features:**

- See `LIQUID_GLASS_GUIDE.md` for glass effect application rules
- See `CLAUDE.md` section on "Key Implementation Details" for rich text editing
- Check `TODO` for any planned audio features
- Review `Noty/Models/Note.swift` to understand note data structure

---

## OTHER CONSIDERATIONS

**Design System Requirements:**

Glass Effects:
- Microphone button: `.liquidGlass(in: Circle())` with 60pt diameter
- Recording controls: `.tintedLiquidGlass(in: Capsule(), tint: Color("SurfaceTranslucentColor"))`
- Waveform container: Thin glass background

Colors:
- Use `Color("PrimaryTextColor")` for icons
- Use `Color("AccentColor")` for recording indicator
- Gradient for waveform: from accent color to secondary color

Typography:
- Timer: `.font(.system(size: 17, weight: .semibold))`
- Duration: `.font(.system(size: 14, weight: .regular))`

Animations:
- Button press: `.bouncy(duration: 0.3)` with scale effect
- Recording pulse: Continuous animation at 1 second interval
- Waveform: Real-time updates at 60fps

**iOS 26+ / macOS 26+ Features:**

- Native `.glassEffect()` for all glass surfaces
- Enhanced `AVAudioRecorder` with better quality
- Improved Speech Recognition with on-device processing
- Use `@Observable` macro for recording state management

**Technical Constraints:**

Permissions:
- Request microphone permission before first recording
- Handle denial gracefully with explanation
- Store permission state persistently

Audio Quality:
- Use high-quality audio format (AAC 256kbps)
- Sample rate: 44.1 kHz
- Mono recording to save space

File Management:
- Store audio files in app documents directory
- Implement cleanup for deleted notes
- Consider file size limits (e.g., 10 minutes max)

Performance:
- Waveform should update smoothly without frame drops
- Transcription should happen asynchronously
- Don't block main thread during recording

**Things AI assistants commonly miss:**

1. **Microphone permission handling**: Always check and request permissions
2. **Audio session configuration**: Set proper audio session category
3. **Background recording**: Handle app backgrounding during recording
4. **File cleanup**: Delete audio files when notes are deleted
5. **Error handling**: Handle recording failures gracefully
6. **Memory management**: Release audio resources properly
7. **Interruptions**: Handle phone calls and other audio interruptions

**Testing Requirements:**

Unit Tests:
- Test audio recorder initialization
- Test recording start/stop lifecycle
- Test file creation and persistence
- Test transcription (with mocked speech recognition)
- Test permission states

Integration Tests:
- Test note creation with audio
- Test audio playback
- Test file cleanup on note deletion

Edge Cases:
- Recording while another audio plays
- Storage space full
- Microphone unavailable
- Permission denied
- App backgrounding during recording
- Very short recordings (< 1 second)
- Maximum duration recordings

Manual Testing:
1. Record a short note and verify transcription
2. Play back recorded audio
3. Edit transcription and save
4. Delete note and verify audio file deleted
5. Test with microphone permission denied
6. Test recording during low battery
7. Test with Reduce Transparency enabled

---

## IMPLEMENTATION NOTES

**Suggested Architecture:**

```
Noty/
├── Models/
│   ├── AudioRecorder.swift           # Recording manager
│   └── AudioTranscriber.swift        # Speech-to-text
├── Views/
│   └── Components/
│       ├── RecordingButton.swift     # Mic button
│       ├── WaveformView.swift        # Visualization
│       └── AudioPlayerView.swift     # Playback controls
└── Utils/
    └── AudioSessionManager.swift     # AVAudioSession config
```

**Implementation Steps (suggested):**

1. Create AudioRecorder manager with recording lifecycle
2. Create RecordingButton with glass styling
3. Implement WaveformView with real-time visualization
4. Integrate transcription with Speech framework
5. Add audio playback to note detail view
6. Implement file management and cleanup
7. Write comprehensive tests
8. Add permission handling UI

---

## NEXT STEPS

Generate a comprehensive PRP:

```
/generate-prp INITIAL_EXAMPLE.md
```

This will create a detailed PRP at `PRPs/voice-recording-feature.md` that includes:
- Complete context from this request
- Researched patterns from the codebase
- Step-by-step implementation guide
- Testing requirements
- Validation gates

Then execute it:

```
/execute-prp PRPs/voice-recording-feature.md
```

---

## Why This Example Works

This INITIAL.md demonstrates best practices:

✅ **Specific requirements**: Exactly what the feature should do  
✅ **User story**: Clear goal and benefit  
✅ **Referenced examples**: Points to relevant code patterns  
✅ **External docs**: Links to Apple APIs needed  
✅ **Design specs**: Concrete glass effects and styling  
✅ **Technical constraints**: Permissions, quality, performance  
✅ **Gotchas listed**: Things commonly missed  
✅ **Testing scenarios**: Unit, integration, and edge cases  
✅ **Architecture suggestion**: Proposed file structure  

This level of detail enables the AI assistant to generate a comprehensive, accurate PRP that leads to a successful implementation.

