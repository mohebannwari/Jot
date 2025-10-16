# iOS Migration Plan - Noty App

**Version:** 1.0
**Last Updated:** October 16, 2025
**Status:** Pre-Implementation

---

## Executive Summary

This document outlines the technical implementation plan for creating an iOS version of Noty while maintaining the existing macOS app. The approach uses a **shared codebase strategy** with platform-specific adaptations where necessary.

**Key Principle:** Zero destructive operations - all existing macOS functionality remains intact throughout the migration.

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Architecture Strategy](#architecture-strategy)
3. [Phase 1: Project Setup](#phase-1-project-setup)
4. [Phase 2: Code Organization](#phase-2-code-organization)
5. [Phase 3: Platform-Specific Adaptations](#phase-3-platform-specific-adaptations)
6. [Phase 4: Testing & Validation](#phase-4-testing-validation)
7. [Risk Mitigation](#risk-mitigation)
8. [Rollback Procedures](#rollback-procedures)

---

## Current State Analysis

### Project Statistics
- **Total Swift Files:** 51
- **Files with Platform-Specific Code:** 19 (already using `#if os()`)
- **Current Target:** macOS 26.0
- **Deployment Model:** Single macOS app

### Technology Stack
- **Framework:** SwiftUI (iOS 26+/macOS 26+)
- **Design System:** Apple Liquid Glass
- **Persistence:** SwiftData + JSON
- **Audio:** AVFoundation + Speech framework
- **Testing:** XCTest

### Directory Structure (Current)
```
Noty/
├── App/                    # App entry point (2 files)
│   ├── NotyApp.swift
│   └── ContentView.swift
├── Models/                 # Data layer (6 files + SwiftData)
│   ├── Note.swift
│   ├── NotesManager.swift
│   ├── SearchEngine.swift
│   ├── AudioRecorder.swift
│   ├── Transcriber.swift
│   └── SwiftData/          # SwiftData models
├── Views/
│   ├── Components/         # UI components (22 files)
│   └── Screens/           # Full screens (3 files)
├── Utils/                 # Utilities (16 files)
└── Resources/             # Assets
```

### Files Already Platform-Ready
The following files already implement cross-platform patterns:

1. **`GlassEffects.swift`** - Liquid Glass with iOS/macOS fallbacks
2. **`BackdropBlurView.swift`** - Perfect example of platform abstraction
3. **`AppWindowBackground.swift`** - Platform-specific blur implementations
4. **`ContentView.swift`** - Already has iOS-aware glass effects
5. 15+ other files with `#if os()` conditionals

### Files Requiring Platform Adaptation

#### NSKit-Dependent Files (8 files)
These files use macOS-specific APIs:
- `TodoRichTextEditor.swift` - Uses NSTextView
- `NoteDetailView.swift` - Window management
- `NoteExportService.swift` - NSPasteboard
- `TextFormattingManager.swift` - NSFont
- `ImageAttachmentView.swift` - NSImage
- `ImageStorageManager.swift` - NSImage processing
- `WebMetadataFetcher.swift` - NSImage
- `ThumbnailCache.swift` - NSImage

#### UIKit-Aware Files (6 files)
These files already reference UIKit (ready for iOS):
- `TodoRichTextEditor.swift`
- `NoteDetailView.swift`
- `BackdropBlurView.swift`
- `ImagePickerControl.swift`
- `ImageAttachmentView.swift`
- `ImageStorageManager.swift`

---

## Architecture Strategy

### Shared Code Strategy
**Goal:** Maximize code sharing (target: 85-90%)

#### What Goes in Shared/
- All Models (100% shareable)
- All Utils (95% shareable - minimal adaptations)
- Most Components (90% shareable)
- Business Logic (100% shareable)
- SwiftData schemas (100% shareable)
- Search Engine (100% shareable)
- Theme System (100% shareable)

#### What Goes in Platform-Specific/
- **macOS/**
  - `NotyApp+macOS.swift` - Window configuration
  - `ContentView+macOS.swift` - macOS navigation
  - Custom window management

- **iOS/**
  - `NotyApp+iOS.swift` - Scene configuration
  - `ContentView+iOS.swift` - NavigationStack
  - Tab bar implementation
  - iOS-specific gestures

### Liquid Glass Cross-Platform Strategy

The app already has **excellent Liquid Glass abstraction** in `GlassEffects.swift`:

```swift
// Already supports both platforms!
@ViewBuilder
func liquidGlass(in shape: some Shape) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
        self.glassEffect(.regular.interactive(true), in: shape)
    } else {
        self.background(.ultraThinMaterial, in: shape)
    }
}
```

**Status:** ✅ Liquid Glass ready for both platforms - no changes needed!

---

## Phase 1: Project Setup

### Step 1.1: Create iOS Target

**Xcode Steps:**
1. File → New → Target
2. iOS → App
3. Configuration:
   - **Product Name:** Noty iOS
   - **Bundle ID:** `com.mohebanwari.Noty.iOS`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Minimum Deployment:** iOS 26.0
   - **Include Tests:** Yes

**Result:** Creates `Noty iOS` folder with default SwiftUI template

### Step 1.2: Configure Build Settings

**iOS Target Build Settings:**
```
PRODUCT_NAME = Noty
PRODUCT_BUNDLE_IDENTIFIER = com.mohebanwari.Noty.iOS
TARGETED_DEVICE_FAMILY = 1,2 (iPhone & iPad)
IPHONEOS_DEPLOYMENT_TARGET = 26.0
SWIFT_VERSION = 5.0
ENABLE_PREVIEWS = YES
```

**Preserve macOS Target Settings:**
```
PRODUCT_NAME = Noty
PRODUCT_BUNDLE_IDENTIFIER = com.mohebanwari.Noty
MACOSX_DEPLOYMENT_TARGET = 26.0
(All existing settings remain unchanged)
```

### Step 1.3: Info.plist Configuration

**iOS-Specific Info.plist Keys:**
```xml
<key>UILaunchScreen</key>
<dict>
    <key>UIImageName</key>
    <string>LaunchImage</string>
</dict>

<key>UIRequiredDeviceCapabilities</key>
<array>
    <string>arm64</string>
</array>

<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>

<key>NSMicrophoneUsageDescription</key>
<string>Noty needs microphone access for voice note recording.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Noty needs photo library access to attach images to notes.</string>
```

---

## Phase 2: Code Organization

### Step 2.1: Create New Directory Structure

**New Structure:**
```
Noty/
├── Shared/                 # Cross-platform code (90% of codebase)
│   ├── Models/            # 100% shared
│   │   ├── Note.swift
│   │   ├── NotesManager.swift
│   │   ├── SearchEngine.swift
│   │   ├── AudioRecorder.swift
│   │   ├── Transcriber.swift
│   │   └── SwiftData/
│   ├── Utils/             # 95% shared
│   │   ├── ThemeManager.swift
│   │   ├── FontManager.swift
│   │   ├── GlassEffects.swift
│   │   ├── HapticManager.swift
│   │   ├── Extensions.swift
│   │   └── [12+ more utility files]
│   └── Views/
│       ├── Components/    # 90% shared
│       │   ├── BottomBar.swift
│       │   ├── FloatingSearch.swift
│       │   ├── NoteCard.swift
│       │   ├── AISummaryBox.swift
│       │   ├── [18+ more components]
│       │   └── PlatformSpecific/
│       │       ├── TextEditor/
│       │       │   ├── TodoRichTextEditor.swift (protocol)
│       │       │   ├── TodoRichTextEditor+macOS.swift
│       │       │   └── TodoRichTextEditor+iOS.swift
│       │       ├── ImagePicker/
│       │       │   ├── ImagePickerControl.swift (protocol)
│       │       │   ├── ImagePickerControl+macOS.swift
│       │       │   └── ImagePickerControl+iOS.swift
│       │       └── BackdropBlur/
│       │           └── BackdropBlurView.swift (already done!)
│       └── Screens/       # 80% shared
│           ├── NoteDetailView.swift
│           └── MicCaptureDemoView.swift
├── macOS/                 # macOS-specific code (5% of codebase)
│   ├── App/
│   │   ├── NotyApp+macOS.swift
│   │   └── ContentView+macOS.swift
│   ├── WindowManagement/
│   │   └── WindowConfiguration.swift
│   └── Resources/
│       └── Assets.xcassets (macOS specific)
└── iOS/                   # iOS-specific code (5% of codebase)
    ├── App/
    │   ├── NotyApp+iOS.swift
    │   └── ContentView+iOS.swift
    ├── Navigation/
    │   └── NavigationConfiguration.swift
    └── Resources/
        └── Assets.xcassets (iOS specific)
```

### Step 2.2: File Migration Strategy

**Safety-First Approach:**
1. **Git checkpoint** - Commit all current changes
2. **Create new directories** - Shared/, macOS/, iOS/
3. **Copy files** to new locations (don't move yet)
4. **Update imports** in copied files
5. **Test builds** for both targets
6. **Only then** remove old files

**Migration Order:**
1. Models first (100% shared, easiest)
2. Utils second (minimal platform differences)
3. Shared Views third
4. Platform-specific Views last

### Step 2.3: Target Membership Configuration

**Shared Files Target Membership:**
- ✅ Noty (macOS)
- ✅ Noty iOS
- ✅ NotyTests (both platforms)

**macOS-Specific Files:**
- ✅ Noty (macOS)
- ❌ Noty iOS
- ✅ NotyTests (macOS)

**iOS-Specific Files:**
- ❌ Noty (macOS)
- ✅ Noty iOS
- ✅ NotyTests (iOS)

---

## Phase 3: Platform-Specific Adaptations

### Step 3.1: App Entry Point

#### Current: NotyApp.swift (macOS only)
```swift
@main
struct NotyApp: App {
    @StateObject private var notesManager: SimpleSwiftDataManager
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notesManager)
                .environmentObject(themeManager)
        }
        .windowStyle(.hiddenTitleBar)  // ⚠️ macOS only!
    }
}
```

#### New: NotyApp.swift (Shared protocol)
```swift
// Shared/App/NotyApp.swift
protocol NotyAppProtocol {
    var notesManager: SimpleSwiftDataManager { get }
    var themeManager: ThemeManager { get }
}

// Common initialization logic
extension NotyAppProtocol {
    static func initializeManagers() -> (SimpleSwiftDataManager, ThemeManager) {
        let manager: SimpleSwiftDataManager
        do {
            manager = try SimpleSwiftDataManager()
        } catch {
            fatalError("Cannot initialize database: \(error)")
        }
        return (manager, ThemeManager())
    }
}
```

#### macOS Entry Point
```swift
// macOS/App/NotyApp+macOS.swift
#if os(macOS)
@main
struct NotyApp: App, NotyAppProtocol {
    @StateObject private var notesManager: SimpleSwiftDataManager
    @StateObject private var themeManager: ThemeManager

    init() {
        let (manager, theme) = Self.initializeManagers()
        _notesManager = StateObject(wrappedValue: manager)
        _themeManager = StateObject(wrappedValue: theme)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notesManager)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    // Command+N functionality
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
#endif
```

#### iOS Entry Point
```swift
// iOS/App/NotyApp+iOS.swift
#if os(iOS)
@main
struct NotyApp: App, NotyAppProtocol {
    @StateObject private var notesManager: SimpleSwiftDataManager
    @StateObject private var themeManager: ThemeManager

    init() {
        let (manager, theme) = Self.initializeManagers()
        _notesManager = StateObject(wrappedValue: manager)
        _themeManager = StateObject(wrappedValue: theme)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notesManager)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
        }
    }
}
#endif
```

### Step 3.2: ContentView Navigation

#### Current: ContentView.swift
Uses a simple overlay-based navigation (perfect for macOS)

#### iOS Adaptation Strategy

**Option A: Tab-Based Navigation (Recommended)**
```swift
// iOS/App/ContentView+iOS.swift
#if os(iOS)
struct ContentView: View {
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NotesListView()
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }
                .tag(0)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .glassEffect(.regular)  // iOS 26+ Liquid Glass tab bar!
    }
}
#endif
```

**Option B: Navigation Stack (Alternative)**
```swift
#if os(iOS)
struct ContentView: View {
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            NotesListView()
                .navigationTitle("Noty")
                .navigationDestination(for: Note.self) { note in
                    NoteDetailView(note: note)
                }
        }
    }
}
#endif
```

### Step 3.3: Layout Adaptations

#### Fixed Width → Adaptive Layout
```swift
// Current (macOS)
.frame(width: 400)  // ⚠️ Fixed width

// New (Cross-platform)
.frame(maxWidth: 600)  // Adapts to screen size
.padding(.horizontal, horizontalPadding)

private var horizontalPadding: CGFloat {
    #if os(macOS)
    return 30
    #else
    return UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20
    #endif
}
```

#### Safe Area Handling
```swift
// iOS needs safe area awareness
.padding(.top)  // Respects notch/Dynamic Island
.safeAreaInset(edge: .bottom) {
    // Bottom toolbar that respects home indicator
}
```

### Step 3.4: Platform-Specific Component Adaptations

#### Text Editors (TodoRichTextEditor.swift)

**Current:** Uses NSTextView (macOS only)

**Strategy:** Create protocol-based abstraction

```swift
// Shared/Views/Components/PlatformSpecific/TextEditor/TodoRichTextEditor.swift
protocol TodoRichTextEditorProtocol: View {
    var text: Binding<String> { get }
    var attributedText: Binding<AttributedString> { get }
    init(text: Binding<String>, attributedText: Binding<AttributedString>)
}

// Shared interface
struct TodoRichTextEditor: View {
    @Binding var text: String
    @Binding var attributedText: AttributedString

    var body: some View {
        #if os(macOS)
        TodoRichTextEditorMac(text: $text, attributedText: $attributedText)
        #else
        TodoRichTextEditorIOS(text: $text, attributedText: $attributedText)
        #endif
    }
}
```

```swift
// macOS/Views/TodoRichTextEditor+macOS.swift
#if os(macOS)
struct TodoRichTextEditorMac: NSViewRepresentable {
    @Binding var text: String
    @Binding var attributedText: AttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        // ... existing NSTextView setup
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // ... existing update logic
    }
}
#endif
```

```swift
// iOS/Views/TodoRichTextEditor+iOS.swift
#if os(iOS)
struct TodoRichTextEditorIOS: UIViewRepresentable {
    @Binding var text: String
    @Binding var attributedText: AttributedString

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TodoRichTextEditorIOS

        init(_ parent: TodoRichTextEditorIOS) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
#endif
```

#### Image Handling

**Current:** Uses NSImage (macOS)

**Strategy:** Type alias for cross-platform compatibility

```swift
// Shared/Utils/PlatformTypes.swift
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
typealias PlatformImageView = NSImageView
#else
import UIKit
typealias PlatformImage = UIImage
typealias PlatformImageView = UIImageView
#endif

extension PlatformImage {
    // Cross-platform convenience methods
    func resized(to size: CGSize) -> PlatformImage? {
        #if os(macOS)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: size))
        newImage.unlockFocus()
        return newImage
        #else
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        self.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
        #endif
    }
}
```

#### Image Picker

```swift
// Shared/Views/Components/PlatformSpecific/ImagePicker/ImagePickerControl.swift
struct ImagePickerControl: View {
    @Binding var selectedImage: PlatformImage?
    @State private var showPicker = false

    var body: some View {
        Button("Add Image") {
            showPicker = true
        }
        .sheet(isPresented: $showPicker) {
            #if os(macOS)
            ImagePickerMac(selectedImage: $selectedImage)
            #else
            ImagePickerIOS(selectedImage: $selectedImage)
            #endif
        }
    }
}

#if os(iOS)
struct ImagePickerIOS: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerIOS

        init(_ parent: ImagePickerIOS) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
    }
}
#endif
```

### Step 3.5: Haptics Adaptation

**Current:** HapticManager.swift (macOS with NSHapticFeedbackManager)

**iOS Version:**
```swift
// Shared/Utils/HapticManager.swift
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

class HapticManager {
    static let shared = HapticManager()
    private init() {}

    func noteInteraction() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
        #else
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }

    func buttonTap() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
        #else
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    func strong() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
        #else
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    func medium() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
        #else
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}
```

---

## Phase 4: Testing & Validation

### Step 4.1: Build Verification

**macOS Build Test:**
```bash
xcodebuild \
  -project Noty.xcodeproj \
  -scheme Noty \
  -destination 'platform=macOS' \
  build
```

**iOS Build Test:**
```bash
xcodebuild \
  -project Noty.xcodeproj \
  -scheme "Noty iOS" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

**Expected Result:** Both should build without errors

### Step 4.2: Feature Parity Checklist

#### Core Features (Must Work on Both)
- [ ] Create new notes
- [ ] Edit notes with rich text
- [ ] Delete notes
- [ ] Search notes
- [ ] Pin/unpin notes
- [ ] Voice recording with transcription
- [ ] Image attachments
- [ ] Export notes (PDF, Markdown, Text)
- [ ] Theme toggle (light/dark)
- [ ] SwiftData persistence

#### Platform-Specific Features
**macOS:**
- [ ] Window management (hidden title bar)
- [ ] Keyboard shortcuts (Cmd+N for new note)
- [ ] Context menus (right-click)
- [ ] Menu bar integration

**iOS:**
- [ ] Touch gestures (swipe to delete)
- [ ] Haptic feedback
- [ ] Share sheet integration
- [ ] Keyboard toolbar
- [ ] iPad split-view support

### Step 4.3: Liquid Glass Verification

**Test Checklist:**
- [ ] Glass effects render correctly on macOS 26+
- [ ] Glass effects render correctly on iOS 26+
- [ ] Fallback materials work on older OS versions
- [ ] Interactive glass responds to hover (macOS) / touch (iOS)
- [ ] Glass morphing animations work smoothly
- [ ] Performance metrics meet targets (see PROJECT_STATUS.md)

**Performance Targets:**
- GPU usage: 40% reduction vs standard materials
- Render time: 39% faster (10.2ms target)
- Memory: 38% less (28MB target)
- Frame rate: Consistent 60fps

### Step 4.4: Test Suite Execution

**Run macOS Tests:**
```bash
xcodebuild \
  -project Noty.xcodeproj \
  -scheme Noty \
  -destination 'platform=macOS' \
  test
```

**Run iOS Tests:**
```bash
xcodebuild \
  -project Noty.xcodeproj \
  -scheme "Noty iOS" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

**Create iOS Test Target:**
```
Target Name: Noty iOS Tests
Bundle ID: com.mohebanwari.Noty.iOS.Tests
Host Application: Noty iOS
```

---

## Risk Mitigation

### Identified Risks

#### Risk 1: Build Failures During Migration
**Probability:** Medium
**Impact:** High
**Mitigation:**
- Migrate files incrementally (Models → Utils → Views)
- Test build after each migration phase
- Keep macOS target building throughout
- Use feature flags to disable incomplete features

#### Risk 2: Liquid Glass Performance on iOS
**Probability:** Low
**Impact:** Medium
**Mitigation:**
- Already tested in simulator (see LIQUID_GLASS_GUIDE.md)
- Performance improvements documented (40% GPU reduction)
- Fallback to .ultraThinMaterial on older devices

#### Risk 3: SwiftData Cross-Platform Issues
**Probability:** Low
**Impact:** High
**Mitigation:**
- SwiftData is designed for cross-platform
- Test data migration scenarios
- Implement data backup before migration

#### Risk 4: Breaking macOS Functionality
**Probability:** Low
**Impact:** Critical
**Mitigation:**
- **Zero destructive operations** approach
- Keep macOS target building at all times
- Extensive testing before file removal
- Git checkpoints at every phase

### Pre-Migration Checklist

Before starting Phase 1:
- [ ] Commit all current changes
- [ ] Create backup branch: `git checkout -b backup-pre-ios-migration`
- [ ] Tag current state: `git tag v1.0-macos-only`
- [ ] Run full test suite on macOS
- [ ] Verify build succeeds
- [ ] Document current performance metrics
- [ ] Back up SwiftData database

---

## Rollback Procedures

### Phase 1 Rollback (Project Setup)
If iOS target creation causes issues:

```bash
# Delete iOS target from Xcode
# OR restore from git
git reset --hard HEAD
git clean -fd
```

### Phase 2 Rollback (Code Organization)
If directory reorganization breaks builds:

```bash
# Restore original structure
git checkout -- Noty/
git clean -fd Noty/Shared Noty/macOS Noty/iOS
```

### Phase 3 Rollback (Platform Adaptations)
If platform-specific code breaks macOS:

```bash
# Restore specific files
git checkout HEAD -- Noty/App/NotyApp.swift
git checkout HEAD -- Noty/App/ContentView.swift

# OR full rollback
git reset --hard backup-pre-ios-migration
```

### Complete Rollback
If migration must be abandoned:

```bash
# Return to pre-migration state
git reset --hard v1.0-macos-only
git clean -fd
```

---

## Success Criteria

### Phase 1 Success
- [ ] iOS target created
- [ ] macOS target still builds
- [ ] No existing functionality broken

### Phase 2 Success
- [ ] New directory structure created
- [ ] Files moved to Shared/macOS/iOS
- [ ] Both targets build successfully
- [ ] All tests pass on macOS

### Phase 3 Success
- [ ] Platform-specific code implemented
- [ ] Both apps launch and run
- [ ] Core features work on both platforms
- [ ] Liquid Glass effects verified

### Phase 4 Success
- [ ] All tests pass on both platforms
- [ ] Performance metrics met
- [ ] Feature parity achieved (95%+)
- [ ] Ready for App Store submission

---

## Next Steps After Completion

1. **iOS-Specific Features**
   - Widgets (Home Screen & Lock Screen)
   - Apple Pencil integration (iPad)
   - Shortcuts app integration
   - Live Activities for voice recording

2. **Cross-Platform Features**
   - iCloud sync (CloudKit)
   - Handoff between devices
   - Universal clipboard
   - Shared databases

3. **App Store Preparation**
   - iOS screenshots
   - iPad screenshots
   - App Store description
   - Privacy policy updates
   - TestFlight beta testing

---

## Timeline Estimate

**Optimistic:** 2-3 days
**Realistic:** 4-5 days
**Conservative:** 1-2 weeks

**Breakdown:**
- Phase 1 (Setup): 2-4 hours
- Phase 2 (Organization): 1-2 days
- Phase 3 (Adaptations): 2-3 days
- Phase 4 (Testing): 1 day

---

## References

- `LIQUID_GLASS_GUIDE.md` - Liquid Glass implementation patterns
- `PROJECT_STATUS.md` - Current project state
- `IOS_SEPARATION_GUIDE.md` - File separation reference
- `CONTEXT_ENGINEERING.md` - Development workflow

---

## Approval & Sign-off

**Created by:** Claude Code
**Reviewed by:** [Moheb Anwari]
**Approved by:** [Moheb Anwari]
**Date:** October 16, 2025

**Status:** ✅ Ready for Implementation
