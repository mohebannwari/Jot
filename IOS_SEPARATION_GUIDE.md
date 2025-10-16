# iOS Separation Guide - File Organization Reference

**Version:** 1.0
**Last Updated:** October 16, 2025
**Companion Document:** IOS_MIGRATION_PLAN.md

---

## Purpose

This guide provides a **quick reference** for understanding:
1. Which files go where (Shared/ vs macOS/ vs iOS/)
2. Which files need platform-specific adaptations
3. Safety checklist for each migration phase
4. File-by-file migration instructions

---

## Quick Reference: File Categories

### 🟢 100% Shared Files (No Changes Needed)
These files work identically on both platforms.

**Target Membership:** ✅ Noty (macOS) + ✅ Noty iOS

**Location:** `Shared/`

**Files:**
- All Models (except platform-specific helpers)
- Most Utils
- Most Components
- Business Logic
- SwiftData schemas

### 🟡 95% Shared Files (Minor Platform Conditionals)
These files need small `#if os()` additions but remain in Shared/.

**Target Membership:** ✅ Noty (macOS) + ✅ Noty iOS

**Location:** `Shared/` (with conditional compilation)

**Files:**
- GlassEffects.swift (already done!)
- BackdropBlurView.swift (already done!)
- HapticManager.swift
- Extensions.swift
- FontManager.swift

### 🔴 Platform-Specific Files (Separate Implementations)
These files have distinct macOS and iOS versions.

**Target Membership:**
- macOS version: ✅ Noty (macOS)
- iOS version: ✅ Noty iOS

**Location:** `macOS/` or `iOS/`

**Files:**
- NotyApp.swift → NotyApp+macOS.swift / NotyApp+iOS.swift
- ContentView.swift → ContentView+macOS.swift / ContentView+iOS.swift
- TodoRichTextEditor.swift → Split into protocol + implementations
- ImagePickerControl.swift → Split into protocol + implementations

---

## Detailed File Mapping

### App/ Directory

| Current File | New Location | Status | Target Membership | Changes Needed |
|-------------|--------------|--------|-------------------|----------------|
| `NotyApp.swift` | `Shared/App/NotyAppProtocol.swift` | 🟡 Split | Both | Extract shared init logic |
| | `macOS/App/NotyApp+macOS.swift` | 🔴 New | macOS | Window configuration |
| | `iOS/App/NotyApp+iOS.swift` | 🔴 New | iOS | Scene configuration |
| `ContentView.swift` | `macOS/App/ContentView+macOS.swift` | 🔴 Keep | macOS | Overlay navigation |
| | `iOS/App/ContentView+iOS.swift` | 🔴 New | iOS | TabView/NavigationStack |

**Safety Checklist:**
- [ ] NotyAppProtocol compiles for both targets
- [ ] macOS version builds and runs
- [ ] iOS version builds and runs
- [ ] Environment objects propagate correctly
- [ ] Theme manager works on both platforms

---

### Models/ Directory

| Current File | New Location | Status | Target Membership | Changes Needed |
|-------------|--------------|--------|-------------------|----------------|
| `Note.swift` | `Shared/Models/Note.swift` | 🟢 Move | Both | None |
| `NotesManager.swift` | `Shared/Models/NotesManager.swift` | 🟢 Move | Both | None |
| `SearchEngine.swift` | `Shared/Models/SearchEngine.swift` | 🟢 Move | Both | None |
| `AudioRecorder.swift` | `Shared/Models/AudioRecorder.swift` | 🟡 Move | Both | Microphone permissions (Info.plist) |
| `Transcriber.swift` | `Shared/Models/Transcriber.swift` | 🟢 Move | Both | None |
| `SwiftData/NoteEntity.swift` | `Shared/Models/SwiftData/NoteEntity.swift` | 🟢 Move | Both | None |
| `SwiftData/SimpleSwiftDataManager.swift` | `Shared/Models/SwiftData/SimpleSwiftDataManager.swift` | 🟢 Move | Both | None |
| `SwiftData/TagEntity.swift` | `Shared/Models/SwiftData/TagEntity.swift` | 🟢 Move | Both | None |

**Safety Checklist:**
- [ ] All Models compile for both targets
- [ ] SwiftData schemas identical on both platforms
- [ ] No platform-specific imports (AppKit/UIKit)
- [ ] Codable/Identifiable conformances work
- [ ] Test suite passes for Models

---

### Utils/ Directory

| Current File | New Location | Status | Target Membership | Changes Needed |
|-------------|--------------|--------|-------------------|----------------|
| `ThemeManager.swift` | `Shared/Utils/ThemeManager.swift` | 🟢 Move | Both | None |
| `FontManager.swift` | `Shared/Utils/FontManager.swift` | 🟡 Move | Both | Add iOS font handling |
| `GlassEffects.swift` | `Shared/Utils/GlassEffects.swift` | 🟢 Keep | Both | Already cross-platform! |
| `HapticManager.swift` | `Shared/Utils/HapticManager.swift` | 🟡 Update | Both | Add UIFeedbackGenerator for iOS |
| `Extensions.swift` | `Shared/Utils/Extensions.swift` | 🟡 Update | Both | Add iOS-specific extensions |
| `FeatureFlags.swift` | `Shared/Utils/FeatureFlags.swift` | 🟢 Move | Both | None |
| `ThumbnailCache.swift` | `Shared/Utils/ThumbnailCache.swift` | 🟡 Update | Both | NSImage → PlatformImage |
| `DataBackupManager.swift` | `Shared/Utils/DataBackupManager.swift` | 🟢 Move | Both | None |
| `DataIntegrityManager.swift` | `Shared/Utils/DataIntegrityManager.swift` | 🟢 Move | Both | None |
| `DeploymentManager.swift` | `Shared/Utils/DeploymentManager.swift` | 🟢 Move | Both | None |
| `PerformanceMonitor.swift` | `Shared/Utils/PerformanceMonitor.swift` | 🟢 Move | Both | None |
| `FileAttachmentStorageManager.swift` | `Shared/Utils/FileAttachmentStorageManager.swift` | 🟢 Move | Both | None |
| `WebMetadataFetcher.swift` | `Shared/Utils/WebMetadataFetcher.swift` | 🟡 Update | Both | NSImage → PlatformImage |
| `TextFormattingManager.swift` | `Shared/Utils/TextFormattingManager.swift` | 🟡 Update | Both | NSFont → PlatformFont |
| `ImageStorageManager.swift` | `Shared/Utils/ImageStorageManager.swift` | 🟡 Update | Both | NSImage → PlatformImage |
| `NoteExportService.swift` | `Shared/Utils/NoteExportService.swift` | 🟡 Update | Both | NSPasteboard → Platform abstraction |

**Safety Checklist:**
- [ ] All Utils compile for both targets
- [ ] Platform-specific code wrapped in `#if os()`
- [ ] Type aliases (PlatformImage/PlatformFont) defined
- [ ] No direct AppKit/UIKit imports without conditionals
- [ ] Performance Monitor works on both platforms

---

### Views/Components/ Directory

| Current File | New Location | Status | Target Membership | Changes Needed |
|-------------|--------------|--------|-------------------|----------------|
| `BottomBar.swift` | `Shared/Views/Components/BottomBar.swift` | 🟢 Move | Both | None (pure SwiftUI) |
| `FloatingSearch.swift` | `Shared/Views/Components/FloatingSearch.swift` | 🟢 Move | Both | None |
| `NoteCard.swift` | `Shared/Views/Components/NoteCard.swift` | 🟢 Move | Both | None |
| `AISummaryBox.swift` | `Shared/Views/Components/AISummaryBox.swift` | 🟢 Move | Both | None |
| `WaveformView.swift` | `Shared/Views/Components/WaveformView.swift` | 🟢 Move | Both | None |
| `WebClipView.swift` | `Shared/Views/Components/WebClipView.swift` | 🟢 Move | Both | None |
| `FileAttachmentTagView.swift` | `Shared/Views/Components/FileAttachmentTagView.swift` | 🟢 Move | Both | None |
| `ImageAttachmentTagView.swift` | `Shared/Views/Components/ImageAttachmentTagView.swift` | 🟢 Move | Both | None |
| `ThemeToggle.swift` | `Shared/Views/Components/ThemeToggle.swift` | 🟢 Move | Both | None |
| `PerformanceDashboard.swift` | `Shared/Views/Components/PerformanceDashboard.swift` | 🟢 Move | Both | None |
| `CommandMenu.swift` | `macOS/Views/Components/CommandMenu.swift` | 🔴 Keep | macOS | macOS-specific menu |
| `ExportFormatSheet.swift` | `Shared/Views/Components/ExportFormatSheet.swift` | 🟢 Move | Both | None |
| `EditToolbar.swift` | `Shared/Views/Components/EditToolbar.swift` | 🟢 Move | Both | None |
| `FloatingEditToolbar.swift` | `Shared/Views/Components/FloatingEditToolbar.swift` | 🟢 Move | Both | None |
| `AppWindowBackground.swift` | `Shared/Views/Components/AppWindowBackground.swift` | 🟢 Keep | Both | Already cross-platform! |
| `BackdropBlurView.swift` | `Shared/Views/Components/BackdropBlurView.swift` | 🟢 Keep | Both | Already cross-platform! |
| `GalleryGridOverlay.swift` | `Shared/Views/Components/GalleryGridOverlay.swift` | 🟢 Move | Both | None |
| `GalleryPreviewOverlay.swift` | `Shared/Views/Components/GalleryPreviewOverlay.swift` | 🟢 Move | Both | None |
| `MicCaptureControl.swift` | `Shared/Views/Components/MicCaptureControl.swift` | 🟡 Move | Both | Microphone permissions |

**Platform-Specific Components (Need Splitting):**

| Current File | New Structure | Target Membership | Changes Needed |
|-------------|--------------|-------------------|----------------|
| `TodoRichTextEditor.swift` | `Shared/Views/Components/PlatformSpecific/TextEditor/` | | |
| | `TodoRichTextEditor.swift` (protocol) | Both | Define interface |
| | `TodoRichTextEditor+macOS.swift` | macOS | NSTextView implementation |
| | `TodoRichTextEditor+iOS.swift` | iOS | UITextView implementation |
| `ImagePickerControl.swift` | `Shared/Views/Components/PlatformSpecific/ImagePicker/` | | |
| | `ImagePickerControl.swift` (protocol) | Both | Define interface |
| | `ImagePickerControl+macOS.swift` | macOS | NSOpenPanel implementation |
| | `ImagePickerControl+iOS.swift` | iOS | UIImagePickerController |
| `ImageAttachmentView.swift` | `Shared/Views/Components/PlatformSpecific/ImageViews/` | | |
| | `ImageAttachmentView.swift` (wrapper) | Both | Platform detection |
| | `ImageAttachmentView+macOS.swift` | macOS | NSImage rendering |
| | `ImageAttachmentView+iOS.swift` | iOS | UIImage rendering |

**Safety Checklist:**
- [ ] All Shared components build for both targets
- [ ] Liquid Glass effects preserved
- [ ] Platform-specific components properly split
- [ ] Protocols define clear interfaces
- [ ] No direct AppKit/UIKit usage in Shared
- [ ] Context menus work on both platforms

---

### Views/Screens/ Directory

| Current File | New Location | Status | Target Membership | Changes Needed |
|-------------|--------------|--------|-------------------|----------------|
| `CanvasView.swift` | `Shared/Views/Screens/CanvasView.swift` | 🟢 Move | Both | None (placeholder) |
| `MicCaptureDemoView.swift` | `Shared/Views/Screens/MicCaptureDemoView.swift` | 🟢 Move | Both | None |
| `NoteDetailView.swift` | `Shared/Views/Screens/NoteDetailView.swift` | 🟡 Update | Both | Add iOS sheet presentation |

**Safety Checklist:**
- [ ] NoteDetailView works as overlay (macOS) and sheet (iOS)
- [ ] Navigation handled correctly on both platforms
- [ ] Keyboard handling platform-appropriate
- [ ] Safe areas respected on iOS

---

## Platform-Specific Type Aliases

Create this file to handle cross-platform types:

### Shared/Utils/PlatformTypes.swift

```swift
import SwiftUI

#if os(macOS)
import AppKit

// Image Types
typealias PlatformImage = NSImage
typealias PlatformImageView = NSImageView

// Font Types
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor

// View Types
typealias PlatformView = NSView
typealias PlatformViewController = NSViewController

// Pasteboard
typealias PlatformPasteboard = NSPasteboard

#else
import UIKit

// Image Types
typealias PlatformImage = UIImage
typealias PlatformImageView = UIImageView

// Font Types
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor

// View Types
typealias PlatformView = UIView
typealias PlatformViewController = UIViewController

// Pasteboard
typealias PlatformPasteboard = UIPasteboard

#endif

// Cross-platform extensions
extension PlatformImage {
    /// Resizes image to target size (works on both platforms)
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

    /// Returns JPEG data representation
    var jpegData: Data? {
        #if os(macOS)
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #else
        return self.jpegData(compressionQuality: 0.8)
        #endif
    }
}
```

**Target Membership:** ✅ Both

**Status:** 🔴 Create new file

---

## Migration Workflow: Step-by-Step

### Phase 1: Initial Setup

#### Step 1.1: Create Backup
```bash
cd /Users/mohebanwari/development/Noty
git add .
git commit -m "Pre-iOS migration checkpoint"
git tag v1.0-macos-only
git checkout -b ios-migration
```

**Safety Checkpoint:**
- [ ] All changes committed
- [ ] Tag created for rollback
- [ ] Working on feature branch

#### Step 1.2: Create Directory Structure
```bash
cd Noty
mkdir -p Shared/Models
mkdir -p Shared/Views/Components/PlatformSpecific
mkdir -p Shared/Views/Screens
mkdir -p Shared/Utils
mkdir -p macOS/App
mkdir -p macOS/Views/Components
mkdir -p macOS/Resources
mkdir -p iOS/App
mkdir -p iOS/Views/Components
mkdir -p iOS/Resources
```

**Safety Checkpoint:**
- [ ] Directories created
- [ ] No files moved yet
- [ ] macOS build still works

---

### Phase 2: Migrate Models (Safest First)

#### Step 2.1: Copy Models to Shared/
```bash
cp Noty/Models/*.swift Noty/Shared/Models/
cp -r Noty/Models/SwiftData Noty/Shared/Models/
```

#### Step 2.2: Update Xcode Target Membership
1. Open Xcode
2. Select each file in `Shared/Models/`
3. In File Inspector, check:
   - ✅ Noty (macOS)
   - ✅ Noty iOS (when created)

#### Step 2.3: Test Build
```bash
xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' build
```

**Safety Checkpoint:**
- [ ] Models copied
- [ ] Build succeeds
- [ ] No errors introduced
- [ ] Old files not deleted yet

**If Build Fails:**
```bash
# Rollback
rm -rf Noty/Shared/Models
git checkout Noty/Models/
```

---

### Phase 3: Migrate Utils

#### Step 3.1: Copy Utils to Shared/
```bash
cp Noty/Utils/*.swift Noty/Shared/Utils/
```

#### Step 3.2: Update Platform-Specific Utils

**Files needing updates:**
1. `HapticManager.swift` - Add iOS haptics
2. `ImageStorageManager.swift` - Add PlatformImage
3. `WebMetadataFetcher.swift` - Add PlatformImage
4. `TextFormattingManager.swift` - Add PlatformFont

**Example: HapticManager.swift**
```swift
// Add to Shared/Utils/HapticManager.swift

#if os(iOS)
import UIKit
#endif

class HapticManager {
    func noteInteraction() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        #else
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    // ... rest of methods
}
```

#### Step 3.3: Test Build
```bash
xcodebuild -project Noty.xcodeproj -scheme Noty build
```

**Safety Checkpoint:**
- [ ] Utils copied
- [ ] Platform conditionals added
- [ ] Build succeeds
- [ ] No warnings introduced

---

### Phase 4: Migrate Views

#### Step 4.1: Copy Shared Components
```bash
cp Noty/Views/Components/BottomBar.swift Noty/Shared/Views/Components/
cp Noty/Views/Components/FloatingSearch.swift Noty/Shared/Views/Components/
cp Noty/Views/Components/NoteCard.swift Noty/Shared/Views/Components/
# ... continue for all 🟢 files
```

#### Step 4.2: Split Platform-Specific Components

**TodoRichTextEditor Example:**

1. Create protocol:
```swift
// Shared/Views/Components/PlatformSpecific/TextEditor/TodoRichTextEditor.swift
protocol TodoRichTextEditorProtocol: View {
    var text: Binding<String> { get }
    init(text: Binding<String>)
}

struct TodoRichTextEditor: View {
    @Binding var text: String

    var body: some View {
        #if os(macOS)
        TodoRichTextEditorMac(text: $text)
        #else
        TodoRichTextEditorIOS(text: $text)
        #endif
    }
}
```

2. Create macOS implementation:
```swift
// macOS/Views/Components/TodoRichTextEditor+macOS.swift
#if os(macOS)
struct TodoRichTextEditorMac: NSViewRepresentable {
    // ... existing NSTextView code
}
#endif
```

3. Create iOS implementation:
```swift
// iOS/Views/Components/TodoRichTextEditor+iOS.swift
#if os(iOS)
struct TodoRichTextEditorIOS: UIViewRepresentable {
    // ... new UITextView code
}
#endif
```

#### Step 4.3: Test Build
```bash
xcodebuild -project Noty.xcodeproj -scheme Noty build
```

**Safety Checkpoint:**
- [ ] Components copied
- [ ] Platform splits working
- [ ] Build succeeds
- [ ] UI still functions correctly

---

### Phase 5: Create iOS Target

#### Step 5.1: Add iOS Target in Xcode
1. File → New → Target
2. iOS → App
3. Product Name: "Noty iOS"
4. Bundle ID: `com.mohebanwari.Noty.iOS`
5. Minimum Deployment: iOS 26.0

#### Step 5.2: Configure Target Membership
Go through each file in Shared/ and add to both targets.

**Bulk Operation:**
1. Select all files in `Shared/`
2. File Inspector → Target Membership
3. Check both ✅ Noty and ✅ Noty iOS

#### Step 5.3: Create iOS App Entry
```swift
// iOS/App/NotyApp+iOS.swift
#if os(iOS)
@main
struct NotyApp: App {
    @StateObject private var notesManager: SimpleSwiftDataManager
    @StateObject private var themeManager = ThemeManager()

    init() {
        let manager: SimpleSwiftDataManager
        do {
            manager = try SimpleSwiftDataManager()
        } catch {
            fatalError("Cannot initialize database: \(error)")
        }
        _notesManager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notesManager)
                .environmentObject(themeManager)
        }
    }
}
#endif
```

#### Step 5.4: Build Both Targets
```bash
# macOS
xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' build

# iOS
xcodebuild -project Noty.xcodeproj -scheme "Noty iOS" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

**Safety Checkpoint:**
- [ ] iOS target created
- [ ] macOS build still works
- [ ] iOS build compiles
- [ ] No shared code broken

---

## Final Verification Checklist

### Pre-Cleanup Verification
Before deleting old files:

#### macOS App
- [ ] App launches
- [ ] Can create notes
- [ ] Can edit notes
- [ ] Can search notes
- [ ] Voice recording works
- [ ] Image attachments work
- [ ] Export works
- [ ] Theme toggle works
- [ ] Performance metrics acceptable
- [ ] All tests pass

#### iOS App
- [ ] App launches on simulator
- [ ] Can create notes
- [ ] Can edit notes
- [ ] Can search notes
- [ ] Voice recording works (with permissions)
- [ ] Image picker works
- [ ] Export/share works
- [ ] Theme toggle works
- [ ] Liquid Glass effects render
- [ ] Gestures work (swipe, pinch, etc.)

### Code Quality
- [ ] No build warnings
- [ ] No deprecated APIs
- [ ] No force unwraps in critical paths
- [ ] Proper error handling
- [ ] Comments updated
- [ ] No dead code

### File Organization
- [ ] All files in correct directories
- [ ] No duplicate files
- [ ] Target memberships correct
- [ ] Info.plist files correct
- [ ] Asset catalogs organized

---

## Post-Migration Cleanup

### Step 1: Remove Old Files
**Only after verification passes!**

```bash
# Remove old directory structure
rm -rf Noty/App
rm -rf Noty/Models
rm -rf Noty/Views
rm -rf Noty/Utils
```

### Step 2: Update .gitignore
Add iOS-specific ignores:
```gitignore
# iOS
*.ipa
DerivedData/
*.hmap
*.xccheckout
*.moved-aside
*.xcuserstate
*.xcscmblueprint
```

### Step 3: Commit Changes
```bash
git add .
git commit -m "Complete iOS migration - both platforms working"
git tag v2.0-cross-platform
```

---

## Quick Reference: Safety Rules

### ✅ Always Safe
- Creating new directories
- Copying files (not moving)
- Adding `#if os()` conditionals
- Creating new targets
- Updating target membership
- Adding new files

### ⚠️ Requires Testing
- Moving files
- Renaming files
- Changing imports
- Updating Info.plist
- Modifying SwiftData schemas
- Changing build settings

### ❌ Never Do Without Backup
- Deleting files
- Force pushing to git
- Modifying project.pbxproj directly
- Changing deployment targets below 26.0
- Removing error handling

---

## Emergency Contacts & Resources

### If Something Goes Wrong

1. **Build Fails:**
   - Check target membership
   - Verify imports
   - Look for missing files
   - Run `xcodebuild clean`

2. **iOS Crashes:**
   - Check permissions in Info.plist
   - Verify iOS-specific code paths
   - Test on multiple simulators
   - Check console logs

3. **macOS Breaks:**
   - **IMMEDIATE ROLLBACK**: `git reset --hard v1.0-macos-only`
   - Verify no macOS-specific code deleted
   - Check window management code
   - Restore from backup branch

### Useful Commands

```bash
# Full clean
xcodebuild clean -project Noty.xcodeproj -scheme Noty
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Reset to checkpoint
git reset --hard v1.0-macos-only

# Check target membership
xcodebuild -project Noty.xcodeproj -list

# View build settings
xcodebuild -project Noty.xcodeproj -scheme Noty -showBuildSettings
```

---

## Appendix: File-by-File Migration Order

Recommended migration order for maximum safety:

### Round 1: Pure Swift Files (Lowest Risk)
1. Note.swift
2. SearchEngine.swift
3. NoteCard.swift
4. BottomBar.swift
5. FloatingSearch.swift

**Checkpoint:** Build & test

### Round 2: SwiftData Files (Low Risk)
1. NoteEntity.swift
2. TagEntity.swift
3. SimpleSwiftDataManager.swift
4. NotesManager.swift

**Checkpoint:** Build & test persistence

### Round 3: Utilities (Medium Risk)
1. ThemeManager.swift
2. FeatureFlags.swift
3. Extensions.swift
4. HapticManager.swift
5. FontManager.swift

**Checkpoint:** Build & test

### Round 4: Complex Components (Higher Risk)
1. BackdropBlurView.swift (already done)
2. GlassEffects.swift (already done)
3. AppWindowBackground.swift (already done)
4. MicCaptureControl.swift
5. GalleryGridOverlay.swift

**Checkpoint:** Build & test UI

### Round 5: Platform-Specific (Highest Risk)
1. TodoRichTextEditor.swift → Split
2. ImagePickerControl.swift → Split
3. ImageAttachmentView.swift → Adapt
4. NotyApp.swift → Split
5. ContentView.swift → Split

**Checkpoint:** Build & test both platforms

---

## Success Metrics

### Code Organization
- [ ] <10% duplicated code between platforms
- [ ] All platform conditionals documented
- [ ] Clear separation of concerns
- [ ] Easy to find files

### Build Health
- [ ] Zero warnings
- [ ] Zero errors
- [ ] Build time <1 minute (both platforms)
- [ ] Clean build succeeds

### App Quality
- [ ] Feature parity: 95%+
- [ ] Performance: Matches macOS metrics
- [ ] Liquid Glass: Working on both platforms
- [ ] Tests: 90%+ passing

---

## Document Version History

**v1.0 (October 16, 2025)**
- Initial version
- Complete file mapping
- Safety checklists
- Migration workflow

---

**For questions or issues, refer to:**
- IOS_MIGRATION_PLAN.md (technical details)
- LIQUID_GLASS_GUIDE.md (Liquid Glass specifics)
- CONTEXT_ENGINEERING.md (development workflow)
