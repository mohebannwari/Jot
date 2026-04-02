# File Attachment Extract & Inline Preview

**Date:** 2026-04-01
**Status:** Approved

---

## Context

File attachments in Jot currently render as compact capsule pills (`FileAttachmentTagView`). Users can hover for a Quick Look tooltip or click to open files in their default app. However, there's no way to preview file contents inline within the note -- the user must either open the Quick Look overlay (modal) or launch an external app.

This feature adds an **Extract** action that transforms a file tag into an inline preview container, rendering the file's contents directly on the note page. The preview container supports category-specific renderers (PDF pages, images, audio waveforms with playback, video thumbnails, office doc thumbnails), persistent view modes (Medium / Full Width / Tag), and a context menu for file management.

---

## Data Model & Serialization

### Extended Format

Current: `[[file|typeIdentifier|storedFilename|originalFilename]]`

Extended: `[[file|typeIdentifier|storedFilename|originalFilename|viewMode]]`

- `viewMode` values: empty/absent = `tag`, `medium`, `full`
- Backwards compatible: existing notes without `viewMode` default to `tag` -- no migration needed
- The 4th pipe-separated field is optional during deserialization

### NoteFileAttachment Extension

```swift
enum FileViewMode: String, Codable {
    case tag      // Capsule pill (current behavior)
    case medium   // 400px min-width preview, left-aligned
    case full     // Full note-width preview
}

// Add to existing NoteFileAttachment:
var viewMode: FileViewMode = .tag
```

### Attachment Behavior by Mode

| Mode | Attachment Cell Size | Rendering |
|------|---------------------|-----------|
| `tag` | Small capsule (current) | `FileAttachmentTagView` bitmap via `ImageRenderer` |
| `medium` | `min(400, containerWidth)` x computed height (400px unless container is narrower) | `FilePreviewOverlayView` (NSView overlay) |
| `full` | `containerWidth` x computed height | `FilePreviewOverlayView` (NSView overlay) |

---

## Hover Tooltip Extension

When hovering over a **tag-mode** file attachment, two side-by-side glass pills appear:

```
[ (search icon)  Quick Look ]  4pt gap  [ (extract icon)  Extract ]
```

### Implementation

New view: `FileHoverTooltips` (composes both pills in an HStack)

```swift
struct FileHoverTooltips: View {
    var body: some View {
        HStack(spacing: 4) {
            // Existing Quick Look pill
            LinkQuickLookTooltip()
            
            // New Extract pill
            ExtractTooltipPill()
        }
    }
}
```

`ExtractTooltipPill` mirrors `LinkQuickLookTooltip` styling:
- Icon: "IconExtract" asset (from Figma node 2648-8269, the zip/archive icon)
- Text: "Extract"
- Font: `FontManager.heading(size: 11, weight: .medium)`
- Color: `Color("PrimaryTextColor")`
- Background: `.liquidGlassTooltip(shape: RoundedRectangle(cornerRadius: 999))`
- Cursor: pointing hand on hover

### Behavior Rules

- Pills appear only when `viewMode == .tag`
- When file is already extracted (medium/full), hover shows no tooltip pills
- Clicking "Extract" changes `viewMode` from `.tag` to `.medium` (default extraction size)
- Clicking "Quick Look" opens the existing `QuickLookOverlayView` (unchanged behavior)

---

## FilePreviewOverlayView (NSView Overlay)

Follows the established `CodeBlockOverlayView` pattern:

### Architecture

```
FilePreviewOverlayView (NSView)
  └── NSHostingView<FilePreviewContent> (SwiftUI)
        ├── Header Bar (HStack)
        │     ├── Filename + Chevron (tappable -> NSMenu)
        │     └── "Open in [App]" button
        └── Content Area
              └── Category-specific renderer
```

### FilePreviewOverlayView (NSView)

```swift
final class FilePreviewOverlayView: NSView {
    var fileData: FileAttachmentMetadata
    var viewMode: FileViewMode
    weak var parentTextView: NSTextView?
    
    // Callbacks (same pattern as CodeBlockOverlayView)
    var onDataChanged: ((FileAttachmentMetadata, FileViewMode) -> Void)?
    var onDelete: (() -> Void)?
    var onViewModeChanged: ((FileViewMode) -> Void)?
    var onRename: ((String) -> Void)?
    
    private var hostingView: NSHostingView<FilePreviewContent>?
}
```

### Size Calculation

```swift
static func heightForData(_ metadata: FileAttachmentMetadata, 
                          viewMode: FileViewMode, 
                          width: CGFloat) -> CGFloat {
    let headerHeight: CGFloat = 38  // 12 top + 14 text + 12 gap
    let bottomPad: CGFloat = 12
    let contentHeight: CGFloat = {
        switch fileCategory(for: metadata.typeIdentifier) {
        case .pdf:      return 483  // From Figma: 2 pages visible
        case .image:    return min(imageAspectHeight(width), 500)
        case .audio:    return 80   // Waveform + controls
        case .video:    return 300  // 16:9 aspect
        case .office:   return 300  // QL thumbnail
        case .text:     return 200  // Text preview
        case .other:    return 200  // Generic thumbnail
        }
    }()
    return headerHeight + contentHeight + bottomPad
}
```

### Overlay Lifecycle (in TodoEditorRepresentable)

New dictionary: `var filePreviewOverlays: [ObjectIdentifier: FilePreviewOverlayView] = [:]`

New function: `func updateFilePreviewOverlays(in textView: NSTextView)` following the exact pattern from `updateCodeBlockOverlays`:

1. Enumerate `.attachment` attributes in text storage
2. Filter for `NoteFileAttachment` where `viewMode != .tag`
3. Get glyph rect via `layoutManager.boundingRect(forGlyphRange:in:)`
4. Convert to view coordinates (add `textContainerOrigin`)
5. Create or reuse `FilePreviewOverlayView`, update frame
6. Clean up stale overlays

Called from `scheduleOverlayUpdate()` alongside existing overlay updates.

---

## FilePreviewContent (SwiftUI View)

### Header Bar

```swift
HStack(spacing: 0) {
    // Left: Filename + Chevron
    Button(action: showContextMenu) {
        HStack(spacing: 2) {
            Text(originalFilename)
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(Color("PrimaryTextColor"))
                .lineLimit(1)
            Image("IconChevronDownSmall")
                .renderingMode(.template)
                .frame(width: 18, height: 18)
                .foregroundStyle(Color("PrimaryTextColor"))
        }
    }
    .buttonStyle(.plain)
    
    Spacer()
    
    // Right: Open in [App]
    Button(action: openInDefaultApp) {
        HStack(spacing: 0) {
            // App icon (12x12, rounded)
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 12, height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            
            Text("Open in \(appName)")
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(Color("PrimaryTextColor"))
                .lineLimit(1)
                .padding(.horizontal, 4)
            
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10))
                .foregroundStyle(Color("PrimaryTextColor"))
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color("HoverBackgroundColor").opacity(0.001)) // Hit target
        )
    }
    .buttonStyle(.plain)
}
.padding(.horizontal, 12)
```

### Container Styling

- Padding: 12pt all sides (`--sm`)
- Corner radius: 22pt (`--3xl`)
- Gap between header and content: 8pt
- Outer container: `.thinLiquidGlass(in: RoundedRectangle(cornerRadius: 22))` (Liquid Glass per user requirement; Figma shows transparent but user explicitly wants glass material)
- Page cards have shadow: `0px 5px 10px 0px rgba(0,0,0,0.1)`
- Page card corner radius: 20pt

---

## Category-Specific Renderers

### PDFPreviewRenderer

- Uses `PDFDocument` from PDFKit
- Renders each page as an `NSImage` via `PDFPage.thumbnail(of:for:)`
- Pages displayed in a horizontal `ScrollView(.horizontal)` as an `HStack(spacing: 8)`
- Each page card: aspect-ratio-preserving image, 20pt corner radius, subtle drop shadow
- Two pages visible at a time (computed from container width)
- Page image height: ~483pt (from Figma), width derived from page aspect ratio

### ImagePreviewRenderer

- Loads `NSImage` from `FileAttachmentStorageManager.shared.getFileURL(for:)`
- Displays with `.aspectFit` scaling within the content area
- 20pt corner radius on the image
- Capped at 500pt height

### AudioPreviewRenderer

- Reuses existing `WaveformView` pattern for visualization
- `AVAudioPlayer` for playback
- Controls: Play/Pause button (SF Symbol), seek bar (Slider), current time / duration labels
- ~80pt total height

### VideoPreviewRenderer

- `AVPlayerView` wrapped in `NSViewRepresentable`
- Initially displays thumbnail frame with play button overlay
- On play: inline video playback
- ~300pt height (16:9 aspect ratio)

### ThumbnailPreviewRenderer (Office Docs + Fallback)

- `QLThumbnailGenerator.shared.generateBestRepresentation(for:)`
- Request size: container dimensions
- Multi-page office docs: generates multiple thumbnails, displays side-by-side like PDFs
- Falls back to large file type icon (`NSWorkspace.shared.icon(forFile:)`) if no thumbnail available

### TextPreviewRenderer

- Loads file content as `String(contentsOf:encoding:)`
- Displays in read-only `ScrollView` with `Text` view
- Monospace font for `.swift`, `.py`, `.js`, `.json`, `.xml`, `.html`, `.css`, code files
- System font for `.txt`, `.md`, `.rtf`
- ~200pt height with scroll

---

## Context Menu

### Menu Structure

Triggered by tapping the filename + chevron button in the header:

```
NSMenu:
  ├── "View As"                    (submenu)
  │     ├── "Medium" (checkmark if active)
  │     ├── "Full Width" (checkmark if active)
  │     └── "Display as Tag" (checkmark if active)
  ├── NSMenuItem.separator()
  ├── "Rename Attachment..."       (action: showRenameDialog)
  ├── "Copy"                       (action: copyFileToPasteboard)
  ├── NSMenuItem.separator()
  └── "Delete"                     (action: deleteAttachment, destructive styling)
```

### Actions

**View As**: Changes `viewMode` on the attachment. Triggers:
1. Update `attachment.viewMode`
2. If switching to `tag`: remove overlay, resize attachment cell to tag size
3. If switching to `medium`/`full`: create overlay, resize attachment cell to preview size
4. Invalidate layout for the attachment's character range
5. `syncText()` to persist

**Rename Attachment...**: 
- Presents `NSAlert` with `.informational` style
- Text field pre-filled with `originalFilename`
- On "Rename": updates `attachment.originalFilename`, refreshes header, `syncText()`
- On "Cancel": no-op

**Copy**:
- Gets file URL from `FileAttachmentStorageManager.shared.getFileURL(for: storedFilename)`
- `NSPasteboard.general.clearContents()`
- `NSPasteboard.general.writeObjects([fileURL as NSURL])`

**Delete**:
- Finds the attachment's character range in text storage
- `textStorage.replaceCharacters(in: range, with: "")`
- Removes overlay from superview and dictionary
- `syncText()` to persist
- File on disk cleaned up by existing `cleanupUnusedFiles()` on next note load

---

## Default App Detection

```swift
private func detectDefaultApp(for storedFilename: String) -> (icon: NSImage, name: String)? {
    let fileURL = FileAttachmentStorageManager.shared.getFileURL(for: storedFilename)
    guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: fileURL) else { return nil }
    
    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
    icon.size = NSSize(width: 12, height: 12)
    
    let name = FileManager.default.displayName(atPath: appURL.path)
        .replacingOccurrences(of: ".app", with: "")
    
    return (icon, name)
}
```

"Open in [App]" button calls:
```swift
NSWorkspace.shared.open(fileURL, configuration: NSWorkspace.OpenConfiguration())
```

---

## New Files

| File | Purpose |
|------|---------|
| `Jot/Views/Components/FilePreviewOverlayView.swift` | NSView overlay -- frame management + NSHostingView host |
| `Jot/Views/Components/FilePreviewContent.swift` | SwiftUI view -- header, content, context menu, glass styling |
| `Jot/Views/Components/FileHoverTooltips.swift` | Composite hover tooltip (Quick Look + Extract pills) |
| `Jot/Views/Components/Renderers/PDFPreviewRenderer.swift` | PDFKit horizontal page scroll |
| `Jot/Views/Components/Renderers/ImagePreviewRenderer.swift` | Image display |
| `Jot/Views/Components/Renderers/AudioPreviewRenderer.swift` | WaveformView + AVAudioPlayer controls |
| `Jot/Views/Components/Renderers/VideoPreviewRenderer.swift` | AVPlayerView wrapper |
| `Jot/Views/Components/Renderers/ThumbnailPreviewRenderer.swift` | QLThumbnailGenerator for office docs + fallback |
| `Jot/Views/Components/Renderers/TextPreviewRenderer.swift` | Read-only text content |

## Modified Files

| File | Changes |
|------|---------|
| `TodoEditorRepresentable.swift` | Add `filePreviewOverlays` dict, `updateFilePreviewOverlays(in:)`, extend `makeFileAttachment()` for view modes, extend serialization regex for 5th field, wire Extract action from hover, add to `scheduleOverlayUpdate()` |
| `TodoRichTextEditor.swift` | Replace `LinkQuickLookTooltip` with `FileHoverTooltips` for file attachments, pass Extract callback |
| `Jot/Ressources/Assets.xcassets/` | Add `IconExtract.imageset` with SVG from Figma |

---

## Verification

1. **Build**: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build`
2. **PDF**: Attach PDF -> hover -> see both pills -> Extract -> horizontal page scroll -> Open in [App] -> View As menu works
3. **Image**: Attach PNG/JPG -> Extract -> image preview renders -> resize via View As
4. **Audio**: Attach MP3 -> Extract -> waveform + play/pause/seek works
5. **Video**: Attach MP4 -> Extract -> thumbnail + play button -> inline playback
6. **Office**: Attach DOCX -> Extract -> QL thumbnail renders
7. **Text**: Attach .txt/.md -> Extract -> text content renders
8. **Persistence**: Close note -> reopen -> extracted previews persist with correct view mode
9. **Backwards compat**: Old `[[file|type|stored|name]]` notes -> render as tag (no regression)
10. **Context menu**: All actions (View As, Rename, Copy, Delete) work correctly
11. **Light + Dark mode**: All renderers and glass styling correct in both modes
