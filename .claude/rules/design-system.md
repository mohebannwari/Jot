# Jot Design System

Single source of truth for design tokens. Extracted from Figma and xcassets.
Figma: https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot

---

## Color Tokens

All semantic colors live in `Jot/Ressources/Assets.xcassets/`. Reference by name in SwiftUI (`Color("TokenName")`). Always support both light and dark.

| Token                                  | Light                                                        | Dark                                           |
| -------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------- |
| `AccentColor`                          | `#2563EB`                                                    | `#608DFA`                                      |
| `MainColor`                            | `#1A1A1A` (= ButtonPrimaryBgColor)                           | `#FFFFFF` (= ButtonPrimaryBgColor)             |
| `BackgroundColor`                      | `#FFFFFF5C` (36% white)                                      | `#0C0A0908` (3% near-black)                    |
| `BlockContainerColor`                  | `#D6D3D1` (stone-300)                                        | `#292524` (stone-800)                          |
| `BorderSubtleColor`                    | `#1A1A1A17` (9% black)                                       | `#FFFFFF17` (9% white)                         |
| `ButtonPrimaryBgColor`                 | `#1A1A1A`                                                    | `#FFFFFF`                                      |
| `ButtonPrimaryTextColor`               | `#FFFFFF`                                                    | `#1A1A1A`                                      |
| `ButtonSecondaryBgColor`               | `#D6D3D1` (stone-300)                                        | `#292524` (stone-800)                          |
| `CardBackgroundColor`                  | `#FFFFFFB3` (70% white)                                      | `#1C1918B3` (70% dark)                         |
| `FolderBadgeBgColor`                   | `#FFFFFF5C` (36% white)                                      | `#FFFFFF1F` (12% white)                        |
| `HoverBackgroundColor`                 | `#D1D3D0`                                                    | `#444040`                                      |
| `IconSecondaryColor`                   | `#1A1A1AB3` (70% black)                                      | `#A8A29E`                                      |
| `EditorCommandMenuItemForegroundColor` | `#1A1A1AB3` (70% black), same chroma as `IconSecondaryColor` | `#A8A29E`, same chroma as `IconSecondaryColor` |
| `InlineCodeBgColor`                    | `#D6D3D1` (stone-300)                                        | `#44403C` (stone-700)                          |
| `MenuButtonColor`                      | `#1A1A1AB3` (70% black)                                      | `#FFFFFFB3` (70% white)                        |
| `PinnedBgColor`                        | `#FEF08A` (amber)                                            | `#854D0E` (amber-dark)                         |
| `PinnedIconColor`                      | `#854D0E`                                                    | `#FEEF8A`                                      |
| `PrimaryTextColor`                     | `#1A1A1A`                                                    | `#FFFFFF`                                      |
| `SearchInputBackgroundColor`           | `#FFFFFF`                                                    | `#1C1918`                                      |
| `SecondaryBackgroundColor`             | `#E7E6E4`                                                    | `#292524`                                      |
| `SecondaryTextColor`                   | `#1A1A1AB3` (70% black)                                      | `#FFFFFFB3` (70% white)                        |
| `SettingsActiveTabColor`               | `#F5F4F4`                                                    | `#444040`                                      |
| `SettingsIconSecondaryColor`           | `#1A1A1AB3`                                                  | `#A8A29E`                                      |
| `SettingsOptionCardColor`              | `#E7E6E4`                                                    | `#0C0A09`                                      |
| `SettingsPanelPrimaryColor`            | `#FFFFFF5C` (36% white)                                      | `#1A1A1ACC` (80% black)                        |
| `SettingsPlaceholderTextColor`         | `#1A1A1AB3`                                                  | `#FFFFFFB2`                                    |
| `SettingsPrimaryTextColor`             | `#1A1A1A`                                                    | `#FFFFFF`                                      |
| `SurfaceDefaultColor`                  | `#FFFFFF`                                                    | `#1C1918`                                      |
| `SurfaceElevatedColor`                 | `#F5F4F4`                                                    | `#292524`                                      |
| `SurfaceTranslucentColor`              | `#1A1A1A0F` (6% black)                                       | `#FFFFFF0F` (6% white)                         |
| `TagBackgroundColor`                   | `#608DFA59` (35% accent)                                     | `#608DFA40` (25% accent)                       |
| `TagTextColor`                         | `#1A1A1A`                                                    | `#FFFFFF`                                      |
| `TertiaryTextColor`                    | `#52525B`                                                    | `#A19FA9`                                      |

**`EditorCommandMenuItemForegroundColor`:** Slash/command menu idle state — use for **both** row template icons and row titles (`CommandMenuItem`). Hover/selection uses `PrimaryTextColor` for icon and title together. Chroma matches `IconSecondaryColor`; the name encodes shared editor-menu usage.

**`InlineCodeBgColor`:** Inline code pills use `ThemeManager.tintedInlineCodePillNS(isDark:)` — stone-300 / stone-700 with the same tint blend **targets** as block chrome (lighter dark base than stone-800). The asset holds the untinted pair for any `Color("InlineCodeBgColor")` usage.

### Primitive Colors (Figma Variables)

```
blue/500     #3B82F6
red/500      #EF4444
icon/blue    #3B82F6
```

---

## Typography

All type uses **SF Pro**. Weights: Regular=400, Medium=500, SemiBold=600, Bold=700.

### Figma Type Scale

| Style      | Size | Line Height | Tracking (Figma) | Weights Available |
| ---------- | ---- | ----------- | ---------------- | ----------------- |
| Heading/H4 | 20   | 24          | -0.20            | Medium            |
| Label-2    | 15   | 18          | -0.50            | Medium            |
| Label-3    | 13   | 16          | -0.40            | Medium            |
| Label-4    | 12   | 14          | -0.30            | Medium, SemiBold  |
| Label-5    | 11   | 14          | -0.20            | Medium            |
| Tiny       | 10   | 12          | 0                | Medium, SemiBold  |
| Micro      | 9    | 10          | 0                | SemiBold, Bold    |

**Figma tracking is _not_ implemented in code.** The **Tracking (Figma)** column is what the design file exports for static mockups. **Apple’s SF / Human Interface guidance wins for letter spacing on shipped UI:** small UI sizes should read **slightly open**; aggressive **negative** tracking from Figma makes macOS chrome look **cramped** when pasted onto `Font.system(size:)`. Use the code ramp below — do **not** transcribe Figma letter-spacing into `.tracking(-0.3)` (etc.) for SF Pro chrome.

### Letter spacing & SF Pro chrome (Apple-first)

1. **Proportional UI chrome** — For fixed-size **SF Pro** labels, menus, palette rows, and controls, use **`FontManager.UIChromeFont`** + **`View.jotUI(_:)`** (`FontManager.swift`). That bundles **`Font.system(size:weight:)`** with **`FontManager.proportionalUITracking(pointSize:)`**, which follows Apple-style UI curves: **mild positive** tracking for small sizes (~9–13pt), **neutral** around 14–16pt, **mild negative** only for **larger** display sizes so headlines are not loose.

2. **No stacked Figma tightening** — **Do not** chain `.jotUI(FontManager.uiLabel3(…))` with extra **`.tracking(-0.2)` … `.tracking(-0.5)`** unless product documents a one-off exception. That overrides `proportionalUITracking` and reintroduces the Figma-dense look the ramp is meant to avoid.

3. **What to take from Figma** — Use Figma for **point size, weight, line height intent, and hierarchy** (`FontManager.UITextRamp` maps Label-2 … Micro). Use **code** for **letter spacing** on SF Pro chrome.

4. **SF Symbols & template icons** — Use **`.font(chrome.font)`** only on **`Image(systemName:)`** and template **`Image("…")`** marks. **Do not** use **`jotUI`** on symbols — letter spacing is for text, not glyphs.

5. **Monospace / all caps** — Static metadata: **`jotMetadataLabelTypography()`** (see `.cursor/rules/metadata_label_typography.mdc`). **Do not** apply **negative** tracking to mono all-caps chrome. Apple recommends **opening** uppercase slightly at small sizes; if an overlay is **exceptionally dense** (e.g. global search footer), a **small extra positive** `.tracking` may be added **in that component** with an inline comment pointing to this section — not by copying Figma’s negative values.

### FontManager API (code-level)

**Note body:** **SF Pro** (`.system`) is the first-launch default. **Charter** (persisted key `default`) and **monospaced** body remain user-selectable. **SF Mono** is for metadata and code.

| Method                                         | SwiftUI                                                   | Size                             | Weight             | Notes                                                                                                                                                           |
| ---------------------------------------------- | --------------------------------------------------------- | -------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `body()`                                       | Charter, `Font.system`, or monospaced per `BodyFontStyle` | User `bodyFontSize` (default 16) | As set             | Editor / note paragraph text                                                                                                                                    |
| `heading()`                                    | `Font.system` (SF Pro)                                    | 24 default                       | Medium default     | UI headings; independent of body font preference                                                                                                                |
| `metadata()`                                   | Monospaced system                                         | **11** default                   | **Medium** default | Technical labels; static labels use `jotMetadataLabelTypography()`                                                                                              |
| `icon()`                                       | SF Pro                                                    | 20 default                       | Regular            | SF Symbols                                                                                                                                                      |
| `uiPro` / `uiHeadingH4` / `uiLabel2`–`uiMicro` | SF Pro                                                    | Figma scale (20…9)               | Per style          | App chrome: apply with **`jotUI(…)`**; tracking from **`proportionalUITracking`**; see `FontManager.UITextRamp`; future: map to `Font.TextStyle` / Dynamic Type |

**Monospaced static labels (invariant):** For any non–user-input `Text` using the metadata/mono face, use **11pt, medium, all caps** — `jotMetadataLabelTypography()` in `FontManager.swift` (or `.textCase(.uppercase)` with `FontManager.metadata(size: 11, weight: .medium)`). Do not ship sentence-case mono labels except where Figma or product spec explicitly overrides. Never force all caps on `TextField` / `TextEditor` content.

Body font style: `system` (SF Pro, default when `AppBodyFontStyle` is unset), `default` (Charter, for users who chose or migrated with that key), `mono`. Line spacing: Compact (1.0x), Default (1.2x), Relaxed (1.5x) — `ThemeManager.lineSpacing`.

---

## Spacing Scale

Figma token name → pt value:

| Token  | Value |
| ------ | ----- |
| `zero` | 0     |
| `xxs`  | 2     |
| `xs2`  | 4     |
| `xs`   | 8     |
| `sm`   | 12    |
| `base` | 16    |
| `xl2`  | 32    |
| `xl4`  | 48    |
| `xl5`  | 60    |

Canonical padding values in use: `4, 6, 8, 12, 16, 18, 24, 60`

---

## Corner Radius Scale

| Token  | Value         |
| ------ | ------------- |
| `none` | 0             |
| `lg`   | 8             |
| `xl`   | 12            |
| `2xl`  | 16            |
| `md`   | 20            |
| `3xl`  | 24            |
| `full` | 999 (capsule) |

Canonical radius values in use: `4, 20, 24, Capsule`

---

## Effects

| Token          | Value                     |
| -------------- | ------------------------- |
| `bg-blur/tags` | Background blur, radius 4 |

---

## Animations & Timing

All in `Extensions.swift`:

| Animation         | Response | Damping | Duration | Usage                              |
| ----------------- | -------- | ------- | -------- | ---------------------------------- |
| **jotSpring**     | 0.35s    | 0.82    | -        | Spring response for natural motion |
| **jotBounce**     | -        | -       | 0.3s     | Bouncy easing                      |
| **jotSmoothFast** | -        | -       | 0.2s     | Fast linear transitions            |
| **jotHover**      | 0.25s    | 0.75    | -        | Hover state animations (subtle)    |
| **jotDragSnap**   | 0.18s    | 0.9     | -        | Drag-release snap-to-grid effect   |

---

## Liquid Glass (iOS 26+ / macOS 26+)

Glass behavior is governed by native `.glassEffect()`. Not a color token — a modifier.

```swift
// Standard
.glassEffect()

// Custom shape
.glassEffect(.thin, in: RoundedRectangle(cornerRadius: 20))

// Interactive
.glassEffect(.regular.interactive(true))

// Coordinated morphing
.glassEffectID("toolbar", in: namespace)
```

**Rules:**

- Apply to floating elements only (toolbars, cards, overlays)
- Never stack glass on glass — use `.implicit` display mode
- Avoid in scrollable content
- Use `.bouncy` / `.smooth` spring animations for state changes

---

## Asset Catalog Locations

| Content         | Path                              |
| --------------- | --------------------------------- |
| Semantic colors | `Jot/Ressources/Assets.xcassets/` |
| Icons & images  | `Jot/Assets.xcassets/`            |
| SVG icons       | `Jot/` (root-level .svg files)    |
