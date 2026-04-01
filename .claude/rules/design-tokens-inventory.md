# Jot Design System — Complete Token Inventory
**Generated:** March 24, 2026  
**Scope:** macOS 26+ / iOS 26+ (Apple Liquid Glass design system)

---

## 1. COLOR TOKENS FROM ASSET CATALOG

All colors defined in `Jot/Ressources/Assets.xcassets/*.colorset`. Each token includes light and dark variants (RGB in 0-1 scale, converted to hex where applicable).

### Semantic Colors

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| **AccentColor** | #1663EB (rgb 22, 99, 235) | #6004F7 (rgb 96, 4, 247) | Primary action, links, highlights |
| **ButtonPrimaryBgColor** | #0C0A0C (rgb 12, 10, 12) | #E5E6E8 (rgb 229, 230, 232) | Primary button backgrounds |
| **ButtonPrimaryTextColor** | #FFFFFF (rgb 255, 255, 255) | #0C0A0C (rgb 12, 10, 12) | Primary button text |
| **ButtonSecondaryBgColor** | #D1D3D1 (rgb 209, 211, 209) | #242529 (rgb 36, 37, 41) | Secondary button backgrounds |
| **PrimaryTextColor** | #1A1A1A (rgb 26, 26, 26) | #FFFFFF (rgb 255, 255, 255) | Primary text (body, headings) |
| **SecondaryTextColor** | #1A1A1A @ 70% (rgb 26, 26, 26) | #FFFFFF @ 70% (rgb 255, 255, 255) | Secondary text, captions |
| **TertiaryTextColor** | #525B5B (rgb 82, 91, 91) | #A1A1AA (rgb 161, 161, 170) | Tertiary text, metadata |
| **BackgroundColor** | #FFFFFF @ 36% (rgb 255, 255, 255) | #0C0C0C @ 30% (rgb 12, 12, 12) | App background (translucent) |
| **SecondaryBackgroundColor** | #E5E6E8 (rgb 229, 230, 232) | #292529 (rgb 41, 37, 41) | Secondary backgrounds, surfaces |
| **SurfaceElevatedColor** | #F5F5F5 (rgb 245, 245, 245) | #242529 (rgb 36, 37, 41) | Elevated surfaces, cards |
| **SurfaceTranslucentColor** | #1A1A1A @ 6% (rgb 26, 26, 26) | #FFFFFF @ 6% (rgb 255, 255, 255) | Subtle translucent overlays |
| **CardBackgroundColor** | #FFFFFF @ 70% (rgb 255, 255, 255) | #1A1818 @ 70% (rgb 26, 24, 24) | Card containers (translucent) |
| **SearchInputBackgroundColor** | #FFFFFF (rgb 255, 255, 255) | #1C1920 (rgb 28, 25, 32) | Search/input fields |

### Icon & Interactive Colors

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| **IconSecondaryColor** | #1A1A1A @ 70% (rgb 26, 26, 26) | #A8A3A8 (rgb 168, 163, 168) | Secondary icons, muted UI |
| **SettingsIconSecondaryColor** | #1A1A1A @ 70% (rgb 26, 26, 26) | #A8A3A8 (rgb 168, 163, 168) | Settings panel secondary icons |
| **HoverBackgroundColor** | #000000 @ 8% (rgb 0, 0, 0) | #FFFFFF @ 12% (rgb 255, 255, 255) | Hover state background |

### Component-Specific Colors

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| **BlockContainerColor** | #D6D3D1 (rgb 214, 211, 209) | #292925 (rgb 41, 41, 37) | Code/block containers |
| **BorderSubtleColor** | #1A1A1A @ 9% (rgb 26, 26, 26) | #FFFFFF @ 5% (rgb 255, 255, 255) | Subtle borders |
| **PinnedBgColor** | #FEDC8B (rgb 254, 220, 139) | #85A8D5 (rgb 133, 168, 213) | Pinned note background |
| **PinnedIconColor** | #85A8D5 (rgb 133, 168, 213) | #FEDC8B (rgb 254, 220, 139) | Pinned note icon (inverted) |
| **TagBackgroundColor** | #6004F7 @ 35% (rgb 96, 4, 247) | #6004F7 @ 25% (rgb 96, 4, 247) | Tag/label backgrounds |
| **TagTextColor** | #1A1A1A (rgb 26, 26, 26) | #FFFFFF (rgb 255, 255, 255) | Tag/label text |

### Settings Panel Colors

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| **SettingsPrimaryTextColor** | #1A1A1A (rgb 26, 26, 26) | #FFFFFF (rgb 255, 255, 255) | Settings text |
| **SettingsPlaceholderTextColor** | #1A1A1A @ 70% (rgb 26, 26, 26) | #FFFFFF @ 70% (rgb 255, 255, 255) | Settings placeholders |
| **SettingsPanelPrimaryColor** | #FFFFFF @ 36% (rgb 255, 255, 255) | #1A1A1A @ 80% (rgb 26, 26, 26) | Settings panel background |
| **SettingsOptionCardColor** | #E5E6E8 (rgb 229, 230, 232) | #0C0A0C (rgb 12, 10, 12) | Settings option cards |
| **SettingsActiveTabColor** | #F5F5F5 (rgb 245, 245, 245) | #43404B (rgb 67, 64, 75) | Active settings tab |
| **SettingsInnerPillColor** | #E5E6E8 (rgb 229, 230, 232) | #1C1920 (rgb 28, 25, 32) | Settings pill backgrounds |

---

## 2. TYPOGRAPHY

### Font Families

Three core font families across the app:

| Family | Usage | File | Weights |
|--------|-------|------|---------|
| **Charter** (serif) | Body text, note content, paragraph text | System font, fallback: Georgia, system | Regular, Bold (via fontDescriptor) |
| **SF Pro Compact** (system) | Headings, note titles, section headers | System (NSFont.system / Font.system) | Regular, Medium, Semibold, Bold |
| **SF Mono** (monospaced) | Dates, timestamps, metadata, code | System monospaced (NSFont.monospacedSystemFont) | Regular, Medium |

### Typography Scale

| Role | SwiftUI | AppKit (NS) | Size | Weight | Notes |
|------|---------|------------|------|--------|-------|
| **body()** | `Font.custom("Charter", size:)` | `FontManager.bodyNS(size:, weight:)` | 16 (default) | Regular | Primary body text; follows bodyFontStyle setting |
| **heading()** | `Font.system(size:, weight:)` | `FontManager.headingNS(size:, weight:)` | 24 (default) | Medium | Note titles, section headers; respects bodyFontStyle |
| **metadata()** | `Font.system(monospaced, size:)` | `FontManager.metadataNS(size:, weight:)` | 12 (default) | Medium | Timestamps, dates, technical text |
| **icon()** | `Font.system(size:)` | N/A | 20 (default) | Regular | UI symbols, SF Symbols |

### Font Weight Enum

```
FontManager.Weight:
  case regular   → Font.Weight.regular
  case medium    → Font.Weight.medium
  case semibold  → Font.Weight.semibold
  case bold      → Font.Weight.bold
```

### Line Spacing (User-Configurable)

| Preset | Multiplier | UILabel Property |
|--------|------------|------------------|
| Compact | 1.0x | lineSpacing: 0.0 |
| Default | 1.2x | lineSpacing: 0.0 (system default) |
| Relaxed | 1.5x | lineSpacing: 0.0 (user-set value) |

Stored in `ThemeManager.lineSpacing`, notified via `editorSettingsChangedNotification`.

### Body Font Style (User-Configurable)

```
BodyFontStyle (ThemeManager.currentBodyFontStyle):
  case default  → Charter (serif)
  case system   → SF Pro (system font)
  case mono     → SF Mono (monospaced)
```

---

## 3. SPACING & LAYOUT TOKENS

### Hardcoded Spacing

| Value | Context | File | Usage |
|-------|---------|------|-------|
| **4pt** | Glass effect horizontal padding | GlassEffects.swift | `liquidGlass()`, `tintedLiquidGlass()` |
| **3pt** | Glass effect vertical padding | GlassEffects.swift | `liquidGlass()`, `tintedLiquidGlass()` |
| **3pt** | Thin glass horizontal padding | GlassEffects.swift | `thinLiquidGlass()` |
| **2pt** | Thin glass vertical padding | GlassEffects.swift | `thinLiquidGlass()` |
| **8pt** | Hover padding horizontal | Extensions.swift | `hoverContainer()` |
| **4pt** | Hover padding vertical | Extensions.swift | `hoverContainer()` |
| **20pt** | Floating toolbar edge padding | FloatingToolbarPositioner.swift | Toolbar boundary constraint |
| **34pt** | Sidebar note row height | CLAUDE.md | All NoteListCard instances |
| **16pt** | Default glass container radius | GlassEffects.swift | `thinLiquidGlass()` default shape |
| **12pt** | Default hover container radius | Extensions.swift | `hoverContainer()` default |
| **20pt** | LiquidGlassContainer spacing | GlassEffects.swift | Space between glass elements |

### Corner Radius Conventions

From CLAUDE.md (Sidebar Design Conventions):

| Context | Radius | Parent | Child | Rule |
|---------|--------|--------|-------|------|
| **Nested containers (concentric)** | 16 (outer) | Container | - | Outer frame cornerRadius |
| **Nested containers (concentric)** | 12 (inner) | - | Card | Inner cards = outer - padding(4) = 12 |
| **NoteListCard** | 12 (default) | - | - | Customizable via `cornerRadius` parameter |
| **Pinned notes context** | 8 (override) | - | Card | Smaller radius in compact layouts |
| **Default divider radius** | Continuous | - | - | `.continuous` style for smoother corners |

---

## 4. GLASS EFFECTS HELPERS

All in `GlassEffects.swift`. Available on iOS 26.0+ / macOS 26.0+, fallback to `.ultraThinMaterial` or `.borderedProminent` on older OS.

### Main Modifiers

| Modifier | Purpose | Fallback | Notes |
|----------|---------|----------|-------|
| `.liquidGlass(in: shape)` | Standard interactive glass surface | `.ultraThinMaterial` + stroke | Default for interactive UI (buttons, toolbars) |
| `.tintedLiquidGlass(in:, tint:, strokeOpacity:, tintOpacity:)` | Colored glass with native tint | `.ultraThinMaterial` + tint | For semantic colored elements (accents, status) |
| `.thinLiquidGlass(in: shape)` | Subtle glass without interactivity | `.ultraThinMaterial` | Plain glass for non-interactive surfaces |
| `.prominentGlassStyle()` | Prominent button style | `.borderedProminent` | Button styling only |
| `.translucent()` | Full-window translucent background | `.ultraThinMaterial` @ 85% opacity | Overlay backgrounds, modals |
| `.appGlassBackground()` | Intense app-window glass | `BackdropBlurView` (pre-26) | Entire window, max blur (radius 8) |

### Glass Effect Container

```swift
LiquidGlassContainer(spacing: 20) { content }
  // Wraps GlassEffectContainer for coordinated morphing animations
  // Only iOS 26.0+ / macOS 26.0+
```

### Glass ID for Morphing

```swift
view.glassID(id, in: namespace)
  // Assigns unique ID for glass effect animations within GlassEffectContainer
  // Enables smooth shape morphing transitions
```

---

## 5. ANIMATIONS & TIMING

All in `Extensions.swift`:

| Animation | Response | Damping | Duration | Usage |
|-----------|----------|---------|----------|-------|
| **jotSpring** | 0.35s | 0.82 | - | Spring response for natural motion |
| **jotBounce** | - | - | 0.3s | Bouncy easing |
| **jotSmoothFast** | - | - | 0.2s | Fast linear transitions |
| **jotHover** | 0.25s | 0.75 | - | Hover state animations (subtle) |
| **jotDragSnap** | 0.18s | 0.9 | - | Drag-release snap-to-grid effect |

---

## 6. COMPONENT INVENTORY

All SwiftUI views in `Jot/Views/Components/`:

| Component | Purpose |
|-----------|---------|
| AIResultPanel | Display AI tool results (translate, edit, text gen) |
| AIToolsOverlay | Overlay menu for AI writing tools |
| ArchivedNoteRow | Archived note in list view |
| BackdropBlurView | Pre-26 OS blur effect wrapper |
| BackupSettingsPanel | Backup folder & frequency controls |
| CalloutOverlayView | Callout block editor overlay |
| CodeBlockOverlayView | Code block editor with syntax highlighting |
| CommandMenu | Global command palette / shortcuts |
| CreateFolderSheet | Folder creation dialog |
| EditContentFloatingPanel | Floating panel for content editing (AI) |
| EditContentInputSubmenu | Submenu for AI edit content prompts |
| ExportFormatSheet | Note export format picker |
| FileAttachmentTagView | File attachment tag display |
| FileDropOverlay | File drag-and-drop target overlay |
| FloatingColorPicker | Color picker for note/text coloring |
| FloatingEditToolbar | Floating text formatting toolbar |
| FloatingSearch | Floating search interface |
| FloatingSettings | Floating settings panel |
| FolderSection | Folder and its contents in sidebar |
| FontFamilySubmenu | Font family selection submenu |
| FontSizeSubmenu | Font size adjustment submenu |
| ImagePickerControl | Image selection/capture control |
| MicCaptureControl | Audio/voice recording control |
| NotePickerMenu | Menu for picking notes (split view) |
| NotePreviewCard | Note preview on hover/click |
| NoteTableOverlayView | Table editor overlay |
| NoteToolsBar | Toolbar with note actions |
| NoteVersionHistoryPanel | Version history & restoration UI |
| ProofreadPillView | Proofreading status indicator |
| QuickLookOverlayView | Quick Look file preview |
| SplitNotePickerView | Note picker for split view |
| SplitOptionMenu | Split view layout options |
| StickerCanvasOverlay | Sticker drawing canvas |
| StickerView | Individual sticker display |
| TabsContainerOverlayView | Tabs/collections editor |
| TextGenFloatingPanel | Text generation floating panel |
| TextOptionsSubmenu | Text formatting options submenu |
| TodoEditorRepresentable | NSTextView wrapper for todo editing |
| TodoRichTextEditor | Primary rich text editor (4500+ lines) |
| TranslateFloatingPanel | Translation tool floating panel |
| TranslateInputSubmenu | Translation language/options submenu |
| TrashSheet | Trash/deleted notes view |
| UndoToast | Undo action toast notification |
| WaveformView | Audio waveform visualization |
| WebClipView | Web clip display |

---

## 7. THEME MANAGEMENT

`ThemeManager.swift` provides:

### Theme Modes

```swift
enum AppTheme: String {
  case system  // Follows OS appearance
  case light   // Force light mode
  case dark    // Force dark mode
}
```

### Published Properties

- `currentTheme` → AppTheme (persisted in UserDefaults)
- `resolvedColorScheme` → ColorScheme (actual light/dark, non-nil)
- `currentBodyFontStyle` → BodyFontStyle
- `spellCheckEnabled`, `autocorrectEnabled`, `smartQuotesEnabled`, `smartDashesEnabled` → Bool
- `lineSpacing` → LineSpacing (user preference)
- `bodyFontSize` → CGFloat (default: 16)
- `noteSortOrder` → NoteSortOrder (dateEdited, dateCreated, title)
- `groupNotesByDate`, `resumeToLastQuickNote`, `autoSortCheckedItems` → Bool
- `useTouchID`, `lockPasswordType` → Bool, LockPasswordType
- `backupFrequency`, `backupMaxCount`, `versionRetentionDays` → user prefs

### Key Methods

- `toggleTheme()` — Switch light/dark
- `setTheme(_ theme)` — Set explicit theme
- `setBodyFontStyle(_ style)` — Change body font

### Notifications

- `editorSettingsChangedNotification` — Posted when editor prefs change

---

## 8. RICH TEXT SERIALIZATION (Feb 2026+)

From memory, TodoRichTextEditor uses markup tags:

| Tag | Purpose | Example |
|-----|---------|---------|
| `[[b]]...[[/b]]` | Bold | `[[b]]important[[/b]]` |
| `[[i]]...[[/i]]` | Italic | `[[i]]emphasis[[/i]]` |
| `[[u]]...[[/u]]` | Underline | `[[u]]underlined[[/u]]` |
| `[[s]]...[[/s]]` | Strikethrough | `[[s]]removed[[/s]]` |
| `[[h1]]...[[/h1]]` | Heading 1 | `[[h1]]Title[[/h1]]` |
| `[[h2]]...[[/h2]]` | Heading 2 | `[[h2]]Subtitle[[/h2]]` |
| `[[h3]]...[[/h3]]` | Heading 3 | `[[h3]]Section[[/h3]]` |
| `[[align:center]]...[[/align]]` | Center align | `[[align:center]]Centered[[/align]]` |
| `[[align:right]]...[[/align]]` | Right align | `[[align:right]]Right[[/align]]` |
| `[[align:justify]]...[[/align]]` | Justify | `[[align:justify]]Justified[[/align]]` |
| `[[color\|RRGGBB]]...[[/color]]` | Custom color | `[[color\|FF0000]]Red text[[/color]]` |
| `[x]` / `[ ]` | Todo checkbox | `[x] Done` / `[ ] Pending` |
| `[[image\|\|\|filename]]` | Image attachment | (pre-existing) |
| `[[webclip\|...]]` | Web clip | (pre-existing) |

Nesting order in serialized form: **align > heading/bold/italic > underline > strikethrough > color**

---

## 9. DESIGN SYSTEM SOURCES

- **Figma source:** https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot
- **Asset catalog:** `/Jot/Ressources/Assets.xcassets/`
- **Design system docs:** `Jot/.claude/rules/design-system.md` (comprehensive token reference)
- **CLAUDE.md:** `/Jot/.claude/CLAUDE.md` (project conventions, sidebar rules, liquid glass patterns)

---

## 10. BUILD & RENDERING

### SVG Icon Rules

All SVG `.imageset/Contents.json` must include:

```json
"properties": {
  "template-rendering-intent": "template",
  "preserves-vector-representation": true
}
```

Without `preserves-vector-representation`, Xcode rasterizes at 1x = blur on Retina.

### Stroke Weight Formula

Target stroke ratio: **1/12 of viewBox size**

| Grid Size | Stroke Width |
|-----------|--------------|
| 10×10 | 0.833 |
| 12×12 | 1.0 |
| 15×15 | 1.25 |
| 16×16 | 1.333 |
| 18×18 | 1.5 |
| 20×20 | 1.667 |
| 24×24 | 2.0 |

Calculate: `stroke-width = viewBox_size ÷ 12`

### Build Commands

```bash
# Build
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build

# Test
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test

# Clean
xcodebuild -project Jot.xcodeproj -scheme Jot clean
```

After build, restart app (from CLAUDE.md):

```bash
pkill -x Jot 2>/dev/null
touch ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
killall iconservicesagent 2>/dev/null || true
sleep 1 && open ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
```

---

## Summary

**28 color tokens** across semantic, icon, component, and settings categories (all with light/dark variants).  
**3 font families** (Charter, SF Pro, SF Mono) with configurable body style.  
**Liquid Glass** effects with pre-26 OS fallbacks.  
**Rich text markup** system for headings, alignment, colors, bold/italic/underline/strikethrough.  
**User-configurable** theme, fonts, line spacing, sort order, backup preferences.

