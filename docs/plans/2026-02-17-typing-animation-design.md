# Typing Animation Effect -- Design

## Goal

Per-character float-up animation in the rich text editor. As the user types, each character appears to rise from below its final position with a smooth opacity fade. Paste and bulk inserts cascade with a staggered wave. Inspired by ATChimeBellEffect from jasudev/AnimateText, adapted for NSTextView's layout manager pipeline.

## Approach

Custom `NSLayoutManager` subclass that overrides `drawGlyphs(forGlyphRange:at:)`. For recently-inserted characters, apply a CGContext transform (vertical translation + alpha) before drawing. A 120Hz timer drives redraws during active animations.

### Why This Over Alternatives

- **Layer animation on the whole view:** Animates all text, not just new characters.
- **Snapshot overlay layers per character:** Fragile, requires bitmap snapshots and temporary attribute toggling.
- **Custom NSLayoutManager:** Native, zero-overhead, per-glyph control. Hooks directly into AppKit's text rendering pipeline.

## Animation Parameters

| Parameter | Value |
|-----------|-------|
| Initial Y offset | 8px below final position |
| Opacity | 0 to 1 |
| Duration | 0.32s per character |
| Easing | Cubic ease-out: `1 - (1-t)^3` |
| Paste stagger | 0.06s delay per character index |
| Timer frequency | 120Hz (only during active animations) |

## Components

### TypingAnimationLayoutManager

Private class in `TodoRichTextEditor.swift`.

- `activeAnimations: [Int: CFTimeInterval]` -- character index to animation start time
- `animateCharacters(in:stagger:)` -- registers a range for animation
- `drawGlyphs(forGlyphRange:at:)` -- core rendering with per-glyph transforms
- `clearAllAnimations()` -- emergency stop for note switches and deserialization
- `animationTimer: Timer?` -- auto-starts/stops based on active animation count

### Integration Points

1. **`makeNSView`**: Replace default layout manager via `textContainer?.replaceLayoutManager()`
2. **Coordinator**: Track layout manager reference; detect insertions in `shouldChangeTextIn` and feed character indices
3. **Guards**: Call `clearAllAnimations()` in `applyInitialText()`, `updateIfNeeded()`, and deserialization paths

### Trigger Logic

| Scenario | Action |
|----------|--------|
| Single keystroke | Animate 1 character, no stagger |
| Paste / bulk insert | Animate range with stagger |
| `isUpdating == true` | Skip animation |
| Initial text load | `clearAllAnimations()` |
| Note switch | `clearAllAnimations()` |

## Edge Cases

- **Fast typing:** Max ~4 characters animating simultaneously. Timer coalesces redraws.
- **Backspace:** Dead entries pruned on timer expiration. Imperceptible visual glitch at worst.
- **Attachments:** Drawn via `drawAttachment`, bypasses `drawGlyphs` override. No interference.
- **Memory:** ~50 entries max during large paste. 24 bytes each. Negligible.
- **Thread safety:** All operations main thread only.
