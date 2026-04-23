//
//  TodoEditorRepresentable.swift
//  Jot
//
//  NSViewRepresentable bridge and InlineNSTextView for TodoRichTextEditor.
//

import Combine
import SwiftUI
import AppKit
import MapKit
import Quartz
import QuartzCore
import UniformTypeIdentifiers

// MARK: - Supporting Types & Attachments
// (Moved from TodoRichTextEditor.swift — used exclusively by the Coordinator)

/// Dynamic color for checked/struck-through text — resolves at draw time so it adapts to light/dark.
/// NSColor.labelColor.withAlphaComponent() freezes the catalog color at call time; this doesn't.
let checkedTodoTextColor = NSColor(name: nil) { appearance in
    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.7)
}

/// Dynamic color for block quote text — resolves at draw time so it adapts to light/dark.
/// `internal` (default access) because `InlineNSTextView+MarkdownShortcuts` reads it from
/// a sibling file; matches `checkedTodoTextColor`'s access level above.
let blockQuoteTextColor = NSColor(name: nil) { appearance in
    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.7)
}

extension NSAttributedString.Key {
    static let webClipTitle = NSAttributedString.Key("WebClipTitle")
    static let webClipDescription = NSAttributedString.Key("WebClipDescription")
    static let webClipDomain = NSAttributedString.Key("WebClipDomain")
    static let webClipFullURL = NSAttributedString.Key("WebClipFullURL")
    static let plainLinkURL = NSAttributedString.Key("PlainLinkURL")
    /// Optional display label for `[[link|URL|LABEL]]` plain links (when absent, the URL string is shown).
    static let plainLinkLabel = NSAttributedString.Key("PlainLinkLabel")
    /// Inline monospaced "code pill" spans (`[[ic]]...[[/ic]]` in serialized markup).
    static let inlineCode = NSAttributedString.Key("InlineCode")
    static let linkCardTitle = NSAttributedString.Key("LinkCardTitle")
    static let linkCardDescription = NSAttributedString.Key("LinkCardDescription")
    static let linkCardDomain = NSAttributedString.Key("LinkCardDomain")
    static let linkCardFullURL = NSAttributedString.Key("LinkCardFullURL")
    static let imageFilename = NSAttributedString.Key("ImageFilename")
    static let imageWidthRatio = NSAttributedString.Key("ImageWidthRatio")
    static let mapSerializedData = NSAttributedString.Key("MapSerializedData")
    static let fileStoredFilename = NSAttributedString.Key("FileStoredFilename")
    static let fileOriginalFilename = NSAttributedString.Key("FileOriginalFilename")
    static let fileTypeIdentifier = NSAttributedString.Key("FileTypeIdentifier")
    static let fileDisplayLabel = NSAttributedString.Key("FileDisplayLabel")
    static let fileViewMode = NSAttributedString.Key("FileViewMode")
    static let orderedListNumber = NSAttributedString.Key("OrderedListNumber")
    static let blockQuote = NSAttributedString.Key("BlockQuote")
    static let highlightColor = NSAttributedString.Key("HighlightColor")
    static let highlightVariant = NSAttributedString.Key("HighlightVariant")
    static let notelinkID = NSAttributedString.Key("NotelinkID")
    static let notelinkTitle = NSAttributedString.Key("NotelinkTitle")
    static let fileLinkPath = NSAttributedString.Key("FileLinkPath")
    static let fileLinkDisplayName = NSAttributedString.Key("FileLinkDisplayName")
    static let fileLinkBookmark = NSAttributedString.Key("FileLinkBookmark")
    static let todoChecked = NSAttributedString.Key("TodoChecked")
    static let corruptedBlock = NSAttributedString.Key("CorruptedBlock")
}

struct AttachmentMarkup {
    private init() {}
    static let imageMarkupPrefix = "[[image|"
    static let imagePattern = #"\[\[image\|\|\|([^\]|]+)(?:\|\|\|([0-9]*\.?[0-9]+))?\]\]"#
    static let imageRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: imagePattern,
        options: []
    )
    static let fileMarkupPrefix = "[[file|"
    static let mapMarkupPrefix = MapBlockData.markupPrefix
    static let filePattern = #"\[\[file\|([^|]+)\|([^|]+)\|([^|\]]*?)(?:\|([^\]]*))?\]\]"#
    static let fileRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: filePattern,
        options: []
    )
    static let fileLinkMarkupPrefix = "[[filelink|"
    static let fileLinkPattern = #"\[\[filelink\|([^|]+)\|([^|\]]*?)(?:\|([^\]]*))?\]\]"#
    static let fileLinkRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: fileLinkPattern,
        options: []
    )

    static func displayLabel(for storedFile: FileAttachmentStorageManager.StoredFile) -> String {
        #if canImport(UniformTypeIdentifiers)
        if #available(macOS 11.0, iOS 14.0, *) {
            if let type = UTType(storedFile.typeIdentifier) {
                if type.conforms(to: .pdf) { return "PDF" }
                if type.conforms(to: .image) { return "Image" }
                if type.conforms(to: .audio) { return "Audio" }
                if type.conforms(to: .movie) { return "Video" }
            }
        }
        #endif

        let ext = (storedFile.originalFilename as NSString).pathExtension
        if !ext.isEmpty {
            return ext.uppercased()
        }

        return "File"
    }

    static func sanitizedComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "]]", with: " ")
    }
}

// Notification names for floating toolbar coordination
extension Notification.Name {
    static let textSelectionChanged = Notification.Name("TextSelectionChanged")
    static let editorDidBecomeFirstResponder = Notification.Name("EditorDidBecomeFirstResponder")
    /// Drains debounced editor `serialize()` into the SwiftUI `editedContent` binding before note-switch
    /// saves read `@State` (see `NoteDetailView.onChange(of: note.id)`).
    static let jotFlushEditorSerializationBeforeNoteSwitch = Notification.Name(
        "jotFlushEditorSerializationBeforeNoteSwitch")
    /// Broadcast flush: every live editor Coordinator drains its pending serialization. Used before
    /// `NSApp.terminate(nil)` paths (e.g. `BackupManager.restoreBackup`) so in-flight 150ms-debounced
    /// edits land on the binding before the process exits. Unlike the note-switch flush, this has
    /// no `editorInstanceID` filter — every editor flushes.
    static let jotFlushEditorSerializationBeforeTerminate = Notification.Name(
        "jotFlushEditorSerializationBeforeTerminate")
}

// MARK: - Typing Animation Layout Manager

/// Custom layout manager that animates newly-typed glyphs floating up from below.
/// Each character rises from an initial Y offset with an opacity fade, driven by
/// a high-frequency timer that suspends when no animations are active.
final class TypingAnimationLayoutManager: NSLayoutManager {

    // MARK: Animation Parameters

    private let animationDuration: CFTimeInterval = 0.32
    private let initialYOffset: CGFloat = 8.0
    private let staggerDelay: CFTimeInterval = 0.06

    // MARK: State

    /// Maps character index to its animation start time.
    private var activeAnimations: [Int: CFTimeInterval] = [:]

    /// Display-linked timer (CADisplayLink on macOS 14+, fallback Timer) for animation.
    private var animationTimer: AnyObject?

    /// The text view whose display we invalidate each frame.
    weak var animatingTextView: NSTextView?

    // MARK: Public API

    /// Maximum characters to animate per insertion. Large pastes skip animation
    /// to avoid 120Hz invalidation scaling linearly with paste size.
    private let maxAnimatedCharacters = 50

    /// Register characters in a range for animation.
    /// - Parameters:
    ///   - range: The character range to animate.
    ///   - stagger: If true, each character gets an incremental delay (paste wave).
    func animateCharacters(in range: NSRange, stagger: Bool) {
        // Skip animation for large insertions to avoid performance degradation
        guard range.length <= maxAnimatedCharacters else { return }
        let now = CACurrentMediaTime()
        for i in 0..<range.length {
            let charIndex = range.location + i
            let delay = stagger ? Double(i) * staggerDelay : 0.0
            activeAnimations[charIndex] = now + delay
        }
        startTimerIfNeeded()
    }

    /// Immediately cancel all running animations.
    func clearAllAnimations() {
        activeAnimations.removeAll()
        stopAnimationTimer()
    }

    // MARK: Easing

    /// Cubic ease-out: fast arrival, gentle settle. No overshoot.
    private func easeOut(_ t: Double) -> Double {
        let p = 1.0 - t
        return 1.0 - p * p * p
    }

    // MARK: Timer

    private func startTimerIfNeeded() {
        guard animationTimer == nil else { return }
        // Use a common-mode timer at display refresh rate (60Hz).
        // RunLoop.Mode.common ensures it fires during scroll tracking,
        // unlike default-mode timers which pause during scroll.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickAnimation()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func tickAnimation() {
        animatingTextView?.needsDisplay = true
        let now = CACurrentMediaTime()
        activeAnimations = activeAnimations.filter { now < $0.value + animationDuration }
        if activeAnimations.isEmpty {
            stopAnimationTimer()
        }
    }

    private func stopAnimationTimer() {
        (animationTimer as? Timer)?.invalidate()
        animationTimer = nil
    }

    deinit {
        // Invalidate directly — cannot call stopAnimationTimer() from deinit
        // when the method may be actor-isolated in future Swift concurrency contexts.
        (animationTimer as? Timer)?.invalidate()
        animationTimer = nil
    }

    // MARK: Drawing Override

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Guard against drawing during mid-edit when glyph/character maps may be stale
        if activeAnimations.isEmpty || NSGraphicsContext.current?.cgContext == nil
            || textStorage?.editedMask.contains(.editedCharacters) == true {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        } else {
            let totalGlyphs = numberOfGlyphs
            guard glyphsToShow.location < totalGlyphs else {
                super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
                return
            }
            let context = NSGraphicsContext.current!.cgContext
            let now = CACurrentMediaTime()
            var currentIndex = glyphsToShow.location
            let endIndex = min(NSMaxRange(glyphsToShow), totalGlyphs)

            while currentIndex < endIndex {
                guard currentIndex < totalGlyphs else { break }
                let charIndex = characterIndexForGlyph(at: currentIndex)

                if let startTime = activeAnimations[charIndex], now >= startTime {
                    let elapsed = now - startTime
                    let progress = min(elapsed / animationDuration, 1.0)

                    if progress < 1.0 {
                        let easedProgress = easeOut(progress)
                        let yOffset = initialYOffset * CGFloat(1.0 - easedProgress)
                        let alpha = CGFloat(easedProgress)

                        context.saveGState()
                        context.translateBy(x: 0, y: yOffset)
                        context.setAlpha(alpha)
                        super.drawGlyphs(
                            forGlyphRange: NSRange(location: currentIndex, length: 1), at: origin)
                        context.restoreGState()
                    } else {
                        activeAnimations.removeValue(forKey: charIndex)
                        super.drawGlyphs(
                            forGlyphRange: NSRange(location: currentIndex, length: 1), at: origin)
                    }
                    currentIndex += 1
                } else if activeAnimations[charIndex] != nil {
                    // Start time is in the future (staggered), draw invisible
                    context.saveGState()
                    context.setAlpha(0)
                    super.drawGlyphs(
                        forGlyphRange: NSRange(location: currentIndex, length: 1), at: origin)
                    context.restoreGState()
                    currentIndex += 1
                } else {
                    // Batch consecutive non-animating glyphs for performance
                    var runEnd = currentIndex + 1
                    while runEnd < endIndex, runEnd < totalGlyphs {
                        let nextCharIndex = characterIndexForGlyph(at: runEnd)
                        if activeAnimations[nextCharIndex] != nil { break }
                        runEnd += 1
                    }
                    super.drawGlyphs(
                        forGlyphRange: NSRange(location: currentIndex, length: runEnd - currentIndex),
                        at: origin)
                    currentIndex = runEnd
                }
            }
        }

        // Draw squiggly strikethrough on top of rendered glyphs
        drawSquigglyStrikethrough(forGlyphRange: glyphsToShow, at: origin)
    }

    // MARK: - Squiggly Strikethrough

    /// Draws a hand-drawn squiggly line through checked todo text AND body text with strikethrough.
    /// Uses a seeded random based on character content so the wobble is stable across redraws.
    private func drawSquigglyStrikethrough(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage = textStorage,
              let textContainer = textContainers.first,
              let context = NSGraphicsContext.current?.cgContext
        else { return }
        guard NSMaxRange(glyphsToShow) <= numberOfGlyphs else { return }
        guard textStorage.length > 0 else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let safeCharRange = NSIntersectionRange(charRange, NSRange(location: 0, length: textStorage.length))
        guard safeCharRange.length > 0 else { return }

        // Pass 1: Checked todo items (marked with .todoChecked)
        textStorage.enumerateAttribute(.todoChecked, in: safeCharRange, options: []) { value, attrRange, _ in
            guard value as? Bool == true else { return }
            drawSquigglyLine(forAttrRange: attrRange, textStorage: textStorage, textContainer: textContainer, origin: origin, context: context)
        }

        // Pass 2: Body text with .strikethroughStyle (skip ranges already handled by .todoChecked)
        textStorage.enumerateAttribute(.strikethroughStyle, in: safeCharRange, options: []) { value, attrRange, _ in
            guard let style = value as? Int, style != 0 else { return }
            // Don't double-draw on checked todos
            let hasTodoChecked = textStorage.attribute(.todoChecked, at: attrRange.location, effectiveRange: nil) as? Bool ?? false
            guard !hasTodoChecked else { return }
            drawSquigglyLine(forAttrRange: attrRange, textStorage: textStorage, textContainer: textContainer, origin: origin, context: context)
        }
    }

    /// Shared squiggly line drawing for a given attributed range.
    private func drawSquigglyLine(forAttrRange attrRange: NSRange, textStorage: NSTextStorage, textContainer: NSTextContainer, origin: NSPoint, context: CGContext) {
        // Trim trailing newlines/whitespace so the squiggly line only spans visible text
        let nsString = textStorage.string as NSString
        var trimmedEnd = NSMaxRange(attrRange)
        while trimmedEnd > attrRange.location {
            let ch = nsString.character(at: trimmedEnd - 1)
            if ch == 0x0A || ch == 0x0D || ch == 0x20 || ch == 0x09 { trimmedEnd -= 1 }
            else { break }
        }
        let trimmedRange = NSRange(location: attrRange.location, length: trimmedEnd - attrRange.location)
        guard trimmedRange.length > 0 else { return }

        let glyphRange = self.glyphRange(forCharacterRange: trimmedRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, usedRect, container, lineGlyphRange, stop in
            let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard intersection.length > 0 else { return }

            let segmentRect = self.boundingRect(forGlyphRange: intersection, in: textContainer)
            let startX = origin.x + segmentRect.origin.x + 2
            let endX = origin.x + segmentRect.origin.x + segmentRect.width - 1
            let glyphLoc = self.location(forGlyphAt: intersection.location)
            let charIdx = self.characterIndexForGlyph(at: intersection.location)
            let font = textStorage.attribute(.font, at: charIdx, effectiveRange: nil) as? NSFont
                ?? NSFont.systemFont(ofSize: 14)
            let baseline = lineRect.origin.y + glyphLoc.y
            let midY = origin.y + baseline - font.xHeight * 0.5

            guard endX - startX > 4 else { return }

            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let segmentLength = endX - startX
            let stepSize: CGFloat = 6.0
            let steps = max(1, Int(ceil(segmentLength / stepSize)))

            // Seed based on content hash for stable wobble (immune to position shifts)
            let text = nsString.substring(with: attrRange)
            var contentHash: UInt64 = 5381
            for scalar in text.unicodeScalars {
                contentHash = contentHash &* 33 &+ UInt64(scalar.value)
            }
            var rng = contentHash

            func nextWobble() -> CGFloat {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                let normalized = CGFloat((rng >> 33) & 0x7FFF) / CGFloat(0x7FFF)
                return (normalized - 0.5) * 5.0  // wobble amplitude +/- 2.5pt
            }

            path.move(to: NSPoint(x: startX, y: midY + nextWobble()))

            for i in 1...steps {
                let x = min(startX + CGFloat(i) * stepSize, endX)
                let wobble = nextWobble()
                let cpX = startX + (CGFloat(i) - 0.5) * stepSize
                let cpY = midY + nextWobble()
                path.curve(to: NSPoint(x: x, y: midY + wobble),
                           controlPoint1: NSPoint(x: min(cpX, endX), y: cpY),
                           controlPoint2: NSPoint(x: x, y: midY + wobble))
            }

            context.saveGState()
            NSColor.labelColor.setStroke()
            path.stroke()
            context.restoreGState()
        }
    }

    // MARK: - Suppress Native Strikethrough

    override func drawStrikethrough(forGlyphRange glyphRange: NSRange, strikethroughType strikethroughVal: NSUnderlineStyle, baselineOffset: CGFloat, lineFragmentRect lineRect: NSRect, lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: NSPoint) {
        // Intentionally empty — squiggly strikethrough drawn in drawGlyphs() instead
    }

    // MARK: Custom Background Drawing

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        // Block quote left bar (drawn after super, on top)
        guard let textStorage = textStorage, let textContainer = textContainers.first else { return }
        let storageLength = textStorage.length
        guard storageLength > 0 else { return }
        // Bail if glyph range exceeds current glyph count (stale range during mid-edit)
        guard NSMaxRange(glyphsToShow) <= numberOfGlyphs else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // Clamp to storage bounds -- during mid-edit the glyph-to-char mapping can exceed storage
        let safeCharRange = NSIntersectionRange(charRange, NSRange(location: 0, length: storageLength))
        guard safeCharRange.length > 0 else { return }

        // Expand each .blockQuote attribute run to its full paragraph range(s),
        // then coalesce adjacent quote paragraphs into one continuous bar.
        var coveredRanges: [NSRange] = []
        textStorage.enumerateAttribute(.blockQuote, in: safeCharRange, options: []) { value, attrRange, _ in
            guard value as? Bool == true else { return }
            let expandedRange = (textStorage.string as NSString).paragraphRange(for: attrRange)
            // Clamp expanded range to storage bounds
            let clampedRange = NSIntersectionRange(expandedRange, NSRange(location: 0, length: storageLength))
            guard clampedRange.length > 0 else { return }
            if let last = coveredRanges.last, NSMaxRange(last) >= clampedRange.location {
                coveredRanges[coveredRanges.count - 1] = NSUnionRange(last, clampedRange)
            } else {
                coveredRanges.append(clampedRange)
            }
        }

        let barWidth: CGFloat = 3.0
        let totalGlyphs = numberOfGlyphs
        for range in coveredRanges {
            let quoteGlyphRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard quoteGlyphRange.length > 0,
                  quoteGlyphRange.location != NSNotFound,
                  NSMaxRange(quoteGlyphRange) <= totalGlyphs else { continue }
            let rect = boundingRect(forGlyphRange: quoteGlyphRange, in: textContainer)
            let barRect = CGRect(
                x: origin.x + 6,
                y: origin.y + rect.origin.y,
                width: barWidth,
                height: rect.height)
            NSColor.labelColor.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        // Draw organic highlight shapes (after block-quote bars so they don't obscure the bar)
        if let ctx = NSGraphicsContext.current?.cgContext {
            drawHighlightShapes(forGlyphRange: glyphsToShow, at: origin,
                                textStorage: textStorage, textContainer: textContainer,
                                safeCharRange: safeCharRange, context: ctx)
        }

        // Inline code pills — one tight rounded rect per line fragment so wrapped monospace runs
        // do not get a single stretched pill across the full union bounding box. The vertical
        // extent is computed from font metrics (capHeight + descender) rather than from
        // `boundingRect(forGlyphRange:in:)`, which returns line-fragment-sized rects and would
        // leave the pill much taller than the actual glyphs.
        //
        // Fill uses stone-300 / stone-700 (dark) with the same UserDefaults tint blend **targets**
        // as block chrome (`ThemeManager.tintedInlineCodePillNS`), not the static asset name.
        let pillAppearance = animatingTextView?.window?.effectiveAppearance
            ?? animatingTextView?.effectiveAppearance
            ?? NSApp.effectiveAppearance
        let isDarkPill = pillAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let inlineCodeFill = ThemeManager.tintedInlineCodePillNS(isDark: isDarkPill)
        textStorage.enumerateAttribute(.inlineCode, in: safeCharRange, options: []) { value, attrRange, _ in
            guard value as? Bool == true else { return }
            let fullGlyphRange = self.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            guard fullGlyphRange.length > 0, NSMaxRange(fullGlyphRange) <= totalGlyphs else { return }
            self.enumerateLineFragments(forGlyphRange: fullGlyphRange) { lineRect, _, container, lineGlyphRange, _ in
                let lineCharRange = self.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
                let overlap = NSIntersectionRange(attrRange, lineCharRange)
                guard overlap.length > 0 else { return }
                let overlapGlyphs = self.glyphRange(forCharacterRange: overlap, actualCharacterRange: nil)
                guard overlapGlyphs.length > 0, NSMaxRange(overlapGlyphs) <= totalGlyphs else { return }
                let segmentRect = self.boundingRect(forGlyphRange: overlapGlyphs, in: container)
                let charIdx = self.characterIndexForGlyph(at: overlapGlyphs.location)
                let font = (textStorage.attribute(.font, at: charIdx, effectiveRange: nil) as? NSFont)
                    ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                let baselineLocation = self.location(forGlyphAt: overlapGlyphs.location)
                let tightRect = TypingAnimationLayoutManager.inlineCodePillRect(
                    lineRect: lineRect,
                    segmentRect: segmentRect,
                    baselineLocation: baselineLocation,
                    font: font
                )
                let pillRect = tightRect.offsetBy(dx: origin.x, dy: origin.y)
                inlineCodeFill.setFill()
                NSBezierPath(roundedRect: pillRect, xRadius: 3, yRadius: 3).fill()
            }
        }
    }

    /// Tight pill rect around an inline-code glyph run within a single line fragment.
    ///
    /// Vertical extent comes from font metrics: `baseline − capHeight − padding` to
    /// `baseline + |descender| + padding`. Horizontal extent is the bounding rect of the
    /// glyphs plus a small bleed on each side. This replaces the earlier approach that
    /// used `boundingRect(forGlyphRange:in:)` directly — that API returns line-fragment-sized
    /// rects, which made the pill fill span the full line height (~1.5× font size) rather
    /// than hugging the glyphs.
    ///
    /// - Parameters:
    ///   - lineRect: the line fragment rect in container coords (from `enumerateLineFragments`).
    ///   - segmentRect: `boundingRect(forGlyphRange:in:)` for the per-line glyph range.
    ///   - baselineLocation: `location(forGlyphAt:)` for the first glyph; `.y` is the baseline
    ///     offset within the line fragment.
    ///   - font: the font at the run's first character.
    ///   - verticalPadding: bleed above cap-height and below descender (default 1.5pt).
    ///   - horizontalBleed: bleed on each side of the glyph run (default 2pt).
    /// - Returns: pill rect in container coords; the caller offsets by draw origin.
    static func inlineCodePillRect(
        lineRect: CGRect,
        segmentRect: CGRect,
        baselineLocation: CGPoint,
        font: NSFont,
        verticalPadding: CGFloat = 1.5,
        horizontalBleed: CGFloat = 2
    ) -> CGRect {
        let baselineY = lineRect.origin.y + baselineLocation.y
        let top = baselineY - font.capHeight - verticalPadding
        let height = font.capHeight + abs(font.descender) + verticalPadding * 2
        return CGRect(
            x: segmentRect.origin.x - horizontalBleed,
            y: top,
            width: segmentRect.width + horizontalBleed * 2,
            height: height
        )
    }

    // MARK: - Organic Highlight Shape Drawing

    // MARK: - Hand-Drawn Highlight Rendering

    /// Deterministic linear congruential RNG used to seed per-highlight noise.
    /// The same seed always produces the same wobble, so highlights remain stable
    /// across redraws, scrolls, and app launches.
    private struct SeededRNG {
        private var state: UInt64

        init(seed: Int) {
            // Mix the seed with a golden-ratio constant so seed == 0 still produces
            // useful output, then advance once so the first call doesn't leak the seed.
            let mixed = UInt64(bitPattern: Int64(seed)) &* 0x9E3779B97F4A7C15
            state = mixed ^ 0xDEADBEEFCAFEBABE
            _ = nextUnit()
        }

        /// Returns noise in [0, 1) — standard Numerical Recipes LCG constants.
        mutating func nextUnit() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let top = Double(state >> 40) / Double(1 << 24)
            return CGFloat(top)
        }

        /// Returns signed noise in [-1, 1).
        mutating func nextSigned() -> CGFloat { nextUnit() * 2 - 1 }
    }

    /// Tunable constants for the procedural highlight shape. These are the four
    /// knobs to turn when refining the aesthetic — no other code changes needed.
    /// - `highlightAmplitude`: wobble magnitude in points (how uneven the top/bottom edges look)
    /// - `highlightCapRadiusFactor`: corner softness as a fraction of the shape height
    /// - `highlightControlPointSpacing`: distance (pt) between noise samples along the width
    /// - `highlightHeightFactor`: shape height as a fraction of the line fragment height.
    ///   Values > 1.0 make adjacent highlighted lines overlap, which is the core
    ///   "marker on paper" effect from the reference.
    private static let highlightAmplitude: CGFloat = 1.0
    private static let highlightCapRadiusFactor: CGFloat = 0.35
    private static let highlightControlPointSpacing: CGFloat = 18
    private static let highlightHeightFactor: CGFloat = 1.15

    /// Generates a smooth hand-drawn highlight shape inside `rect`, with subtly wobbling
    /// top and bottom edges plus soft rounded corners. Deterministic for a given `seed`,
    /// so the same highlight always redraws identically.
    private static func generateHandDrawnHighlightPath(in rect: CGRect, seed: Int) -> CGPath {
        guard rect.width > 2, rect.height > 2 else {
            return CGPath(rect: rect, transform: nil)
        }

        let amplitude = highlightAmplitude
        let maxRadius = min(rect.height * 0.5, rect.width * 0.5)
        let capRadius = min(rect.height * highlightCapRadiusFactor, maxRadius)

        // Region where the wobbly edges live (between the two rounded corners)
        let innerLeft = rect.minX + capRadius
        let innerRight = rect.maxX - capRadius
        let innerTop = rect.minY + capRadius
        let innerBottom = rect.maxY - capRadius
        let innerWidth = max(innerRight - innerLeft, 0)

        // Sample count scales with width; at least 3 so short highlights still wobble
        let sampleCount = max(3, Int((innerWidth / highlightControlPointSpacing).rounded(.up)))

        // Independent seeds for top and bottom so the two edges don't mirror each other
        var topRNG = SeededRNG(seed: seed &* 2)
        var bottomRNG = SeededRNG(seed: seed &* 2 &+ 1)

        // Top edge anchors: (innerLeft, minY) -> wavy interior -> (innerRight, minY)
        var topPoints: [CGPoint] = [CGPoint(x: innerLeft, y: rect.minY)]
        for i in 1..<sampleCount {
            let t = CGFloat(i) / CGFloat(sampleCount)
            let x = innerLeft + t * innerWidth
            let y = rect.minY + topRNG.nextSigned() * amplitude
            topPoints.append(CGPoint(x: x, y: y))
        }
        topPoints.append(CGPoint(x: innerRight, y: rect.minY))

        // Bottom edge anchors (right -> left): (innerRight, maxY) -> wavy interior -> (innerLeft, maxY)
        var bottomPoints: [CGPoint] = [CGPoint(x: innerRight, y: rect.maxY)]
        for i in 1..<sampleCount {
            let t = CGFloat(i) / CGFloat(sampleCount)
            let x = innerRight - t * innerWidth
            let y = rect.maxY + bottomRNG.nextSigned() * amplitude
            bottomPoints.append(CGPoint(x: x, y: y))
        }
        bottomPoints.append(CGPoint(x: innerLeft, y: rect.maxY))

        let path = CGMutablePath()
        path.move(to: topPoints[0])

        // Smooth cubic curves through top anchors. Control points are offset horizontally
        // by half the segment width, giving C1-continuous waves that interpolate every anchor.
        for i in 1..<topPoints.count {
            let prev = topPoints[i - 1]
            let curr = topPoints[i]
            let dx = (curr.x - prev.x) * 0.5
            path.addCurve(
                to: curr,
                control1: CGPoint(x: prev.x + dx, y: prev.y),
                control2: CGPoint(x: curr.x - dx, y: curr.y)
            )
        }

        // Top-right rounded corner
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: innerBottom),
            radius: capRadius
        )

        // Right wall (straight vertical segment between the two right corners)
        path.addLine(to: CGPoint(x: rect.maxX, y: innerBottom))

        // Bottom-right rounded corner
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: innerLeft, y: rect.maxY),
            radius: capRadius
        )

        // Smooth cubic curves through bottom anchors (right -> left). Same formula as the
        // top edge; the negative dx handles the reverse direction naturally.
        for i in 1..<bottomPoints.count {
            let prev = bottomPoints[i - 1]
            let curr = bottomPoints[i]
            let dx = (curr.x - prev.x) * 0.5
            path.addCurve(
                to: curr,
                control1: CGPoint(x: prev.x + dx, y: prev.y),
                control2: CGPoint(x: curr.x - dx, y: curr.y)
            )
        }

        // Bottom-left rounded corner
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: innerTop),
            radius: capRadius
        )

        // Left wall (straight vertical segment between the two left corners)
        path.addLine(to: CGPoint(x: rect.minX, y: innerTop))

        // Top-left rounded corner — closes the shape
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: innerLeft, y: rect.minY),
            radius: capRadius
        )

        path.closeSubpath()
        return path
    }

    private func drawHighlightShapes(
        forGlyphRange glyphsToShow: NSRange,
        at origin: NSPoint,
        textStorage: NSTextStorage,
        textContainer: NSTextContainer,
        safeCharRange: NSRange,
        context: CGContext
    ) {
        let totalGlyphs = numberOfGlyphs
        guard textStorage.length > 0 else { return }

        textStorage.enumerateAttribute(.highlightColor, in: safeCharRange, options: []) { colorValue, attrCharRange, _ in
            guard let hex = colorValue as? String else { return }

            guard let variant = textStorage.attribute(
                .highlightVariant, at: attrCharRange.location, effectiveRange: nil
            ) as? Int else { return }

            let hlGlyphRange = self.glyphRange(forCharacterRange: attrCharRange, actualCharacterRange: nil)
            guard hlGlyphRange.location != NSNotFound else { return }
            let clampedGlyphs = NSIntersectionRange(hlGlyphRange, glyphsToShow)
            guard clampedGlyphs.length > 0,
                  NSMaxRange(clampedGlyphs) <= totalGlyphs else { return }

            let tintColor = TextFormattingManager.nsColorFromHex(hex).withAlphaComponent(0.45)

            self.enumerateLineFragments(forGlyphRange: clampedGlyphs) { lineRect, _, _, lineGlyphRange, _ in
                let lineHighlight = NSIntersectionRange(lineGlyphRange, clampedGlyphs)
                guard lineHighlight.length > 0 else { return }

                let segmentRect = self.boundingRect(forGlyphRange: lineHighlight, in: textContainer)
                guard segmentRect.width > 2 else { return }

                // Height is a multiple of the line fragment height so adjacent highlighted
                // lines overlap slightly — the "marker on paper" effect from the reference.
                // Centered on the line midY, the overflow splits evenly above and below.
                let shapeHeight = lineRect.height * Self.highlightHeightFactor
                let centerY = origin.y + lineRect.midY

                let drawRect = CGRect(
                    x: origin.x + segmentRect.origin.x,
                    y: centerY - shapeHeight * 0.5,
                    width: segmentRect.width,
                    height: shapeHeight
                )

                // Use the persisted variant (0–7) as the noise seed so existing notes
                // render stably under the new system without any migration.
                let shapePath = Self.generateHandDrawnHighlightPath(in: drawRect, seed: variant)
                context.saveGState()
                context.addPath(shapePath)
                context.setFillColor(tintColor.cgColor)
                context.fillPath()
                context.restoreGState()
            }
        }
    }
}

/// Dedicated attachment type so that we never lose the stored filename during round-trips.
final class NoteImageAttachment: NSTextAttachment {
    let storedFilename: String
    var widthRatio: CGFloat
    /// Cached aspect ratio (width/height) to avoid 4:3 fallback reflow on cold open
    var cachedAspectRatio: CGFloat?

    init(filename: String, widthRatio: CGFloat = 1.0) {
        self.storedFilename = filename
        self.widthRatio = widthRatio
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteImageAttachment does not support init(coder:)")
    }
}

final class NoteMapAttachment: NSTextAttachment {
    var mapData: MapBlockData

    init(mapData: MapBlockData) {
        self.mapData = mapData
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteMapAttachment does not support init(coder:)")
    }
}

/// Cell that allocates space for an image attachment but draws nothing visible.
/// The InlineImageOverlayView handles rendering.
final class ImageSizeAttachmentCell: NSTextAttachmentCell {
    let displaySize: CGSize

    init(size: CGSize) {
        self.displaySize = size
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("ImageSizeAttachmentCell does not support init(coder:)")
    }

    override var cellSize: NSSize { displaySize }

    override nonisolated func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Intentionally empty — overlay view renders the image
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        // Intentionally empty — overlay view renders the image
    }
}

final class MapSizeAttachmentCell: NSTextAttachmentCell {
    let displaySize: CGSize
    let mapData: MapBlockData

    init(size: CGSize, mapData: MapBlockData) {
        self.displaySize = size
        self.mapData = mapData
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("MapSizeAttachmentCell does not support init(coder:)")
    }

    override var cellSize: NSSize { displaySize }

    override nonisolated func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        drawSnapshot(in: cellFrame, controlView: controlView)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        drawSnapshot(in: cellFrame, controlView: controlView)
    }

    static func shouldDrawSnapshot(for controlView: NSView?) -> Bool {
        controlView?.window == nil
    }

    private func drawSnapshot(in cellFrame: NSRect, controlView: NSView?) {
        guard Self.shouldDrawSnapshot(for: controlView) else { return }

        let appearance = controlView?.effectiveAppearance ?? NSApp.effectiveAppearance
        let image: NSImage?
        if let cached = MapBlockSnapshotRenderer.cachedImage(
            for: mapData,
            size: displaySize,
            appearance: appearance
        ) {
            image = cached
        } else {
            image = MapBlockSnapshotRenderer.blockingSnapshot(
                for: mapData,
                size: displaySize,
                appearance: appearance
            )
        }

        NSGraphicsContext.saveGraphicsState()
        let clipPath = NSBezierPath(
            roundedRect: cellFrame,
            xRadius: MapBlockData.cornerRadius,
            yRadius: MapBlockData.cornerRadius
        )
        clipPath.addClip()

        if let image {
            image.draw(in: cellFrame)
        } else {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            (isDark ? NSColor.windowBackgroundColor : NSColor.white).setFill()
            cellFrame.fill()
        }
        let strokePath = NSBezierPath(
            roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5),
            xRadius: MapBlockData.cornerRadius - 0.5,
            yRadius: MapBlockData.cornerRadius - 0.5
        )
        strokePath.lineWidth = 1
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (isDark
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.black.withAlphaComponent(0.08)
        ).setStroke()
        strokePath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class NoteLinkCardAttachment: NSTextAttachment {
    var title: String
    var descriptionText: String
    var domain: String
    var url: String
    var thumbnailImage: NSImage?
    var thumbnailTintColor: NSColor?
    let cardID = UUID()

    init(title: String, description: String, domain: String, url: String) {
        self.title = title
        self.descriptionText = description
        self.domain = domain
        self.url = url
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteLinkCardAttachment does not support init(coder:)")
    }
}

final class NoteTableAttachment: NSTextAttachment {
    var tableData: NoteTableData
    let tableID = UUID()

    init(tableData: NoteTableData) {
        self.tableData = tableData
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteTableAttachment does not support init(coder:)")
    }
}

/// Figma `IconArrowRight` (18x18) as inline storage — serializes as `[[arrow]]` (see `NoteImportService` / export).
final class NoteArrowAttachment: NSTextAttachment {
    /// Asset catalog name (must match `Jot/Assets.xcassets/IconArrowRight.imageset`).
    static let assetName = "IconArrowRight"

    override init(data: Data?, ofType uti: String?) {
        super.init(data: data, ofType: uti)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteArrowAttachment does not support init(coder:)")
    }
}

/// Cell that allocates space for a table attachment but draws nothing visible.
/// The NoteTableOverlayView handles rendering.
final class TableSizeAttachmentCell: NSTextAttachmentCell {
    let displaySize: CGSize

    init(size: CGSize) {
        self.displaySize = size
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("TableSizeAttachmentCell does not support init(coder:)")
    }

    override var cellSize: NSSize { displaySize }

    override nonisolated func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Intentionally empty — overlay view renders the table
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        // Intentionally empty — overlay view renders the table
    }
}

// MARK: - Callout Attachment

final class NoteCalloutAttachment: NSTextAttachment {
    var calloutData: CalloutData
    let calloutID = UUID()

    init(calloutData: CalloutData) {
        self.calloutData = calloutData
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteCalloutAttachment does not support init(coder:)")
    }
}

final class CalloutSizeAttachmentCell: NSTextAttachmentCell {
    let displaySize: CGSize

    init(size: CGSize) {
        self.displaySize = size
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("CalloutSizeAttachmentCell does not support init(coder:)")
    }

    override var cellSize: NSSize { displaySize }
    override nonisolated func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Intentionally empty — overlay view renders the callout
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        // Intentionally empty — overlay view renders the callout
    }
}

// MARK: - Code Block Attachment

final class NoteCodeBlockAttachment: NSTextAttachment {
    var codeBlockData: CodeBlockData
    let codeBlockID = UUID()
    /// Distinguishes "user dragged to minWidth" from "block created at minWidth because
    /// container was unknown at deserialization." Prevents the snap-to-full-width bug.
    var hasBeenUserResized: Bool = false

    init(codeBlockData: CodeBlockData) {
        self.codeBlockData = codeBlockData
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteCodeBlockAttachment does not support init(coder:)")
    }
}

// MARK: - Tabs Container Attachment

final class NoteTabsAttachment: NSTextAttachment {
    var tabsData: TabsContainerData
    let tabsID = UUID()

    init(tabsData: TabsContainerData) {
        self.tabsData = tabsData
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteTabsAttachment does not support init(coder:)")
    }
}

final class CodeBlockSizeAttachmentCell: NSTextAttachmentCell {
    let displaySize: CGSize

    init(size: CGSize) {
        self.displaySize = size
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("CodeBlockSizeAttachmentCell does not support init(coder:)")
    }

    override var cellSize: NSSize { displaySize }
    override nonisolated func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?,
                       characterIndex charIndex: Int, layoutManager: NSLayoutManager) {}
}

// MARK: - Card Section Attachment

final class NoteCardSectionAttachment: NSTextAttachment {
    var cardSectionData: CardSectionData
    let cardSectionID = UUID()

    init(cardSectionData: CardSectionData) {
        self.cardSectionData = cardSectionData
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteCardSectionAttachment does not support init(coder:)")
    }
}

// MARK: - Divider Attachment

final class NoteDividerAttachment: NSTextAttachment {
    let dividerID = UUID()

    override init(data: Data?, ofType uti: String?) {
        super.init(data: data, ofType: uti)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteDividerAttachment does not support init(coder:)")
    }
}

final class DividerSizeAttachmentCell: NSTextAttachmentCell {
    /// Width is updated by `updateDividerAttachments` when the text container resizes so
    /// layout and drawing stay in sync (avoids "line cut off in the middle" vs stale cellSize).
    var displaySize: CGSize

    init(size: CGSize) {
        self.displaySize = size
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("DividerSizeAttachmentCell does not support init(coder:)")
    }

    /// Resize the cell when the text container width changes (window/split, first layout).
    func updateWidth(_ width: CGFloat) {
        if abs(displaySize.width - width) > 0.5 {
            displaySize = CGSize(width: width, height: displaySize.height)
        }
    }

    override var cellSize: NSSize { displaySize }
    override nonisolated func cellBaselineOffset() -> NSPoint { .zero }

    // Deterministic pseudo-random: consistent across redraws, no flicker
    private func hash(_ seed: Int) -> CGFloat {
        var h = UInt64(bitPattern: Int64(seed))
        h = h &* 6364136223846793005 &+ 1442695040888963407
        h = (h >> 33) ^ h
        return CGFloat(h % 10000) / 10000.0  // 0.0 ..< 1.0
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // `cellSize` / `cellFrame` are kept in sync with the live container via
        // `updateDividerAttachments`; stroke the full allocated width.
        let baseY = cellFrame.midY
        let startX = cellFrame.minX
        let endX = cellFrame.maxX

        let path = NSBezierPath()
        path.lineWidth = 0.9
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        // Walk across with irregular steps, drifting vertically like a real hand
        var x = startX
        var y = baseY
        var drift: CGFloat = 0  // slow vertical wander
        var i = 0

        path.move(to: NSPoint(x: x, y: y))

        while x < endX {
            let r1 = hash(i &* 31 &+ 7)
            let r2 = hash(i &* 47 &+ 13)
            let r3 = hash(i &* 73 &+ 29)
            let r4 = hash(i &* 97 &+ 41)

            // Irregular segment length: 6–18pt (a hand doesn't move in equal steps)
            let segLen = 6.0 + r1 * 12.0
            let nextX = min(x + segLen, endX)
            let midX = (x + nextX) / 2

            // Slow vertical drift: the baseline wanders up/down over the line
            drift += (r2 - 0.5) * 1.2
            drift *= 0.85  // dampen so it doesn't wander too far

            // Per-segment jitter: small, asymmetric bumps
            let bumpUp = (r3 - 0.5) * 2.8
            let bumpDown = (r4 - 0.5) * 2.8

            let nextY = baseY + drift

            path.curve(to: NSPoint(x: nextX, y: nextY),
                       controlPoint1: NSPoint(x: midX - segLen * 0.15, y: y + bumpUp),
                       controlPoint2: NSPoint(x: midX + segLen * 0.15, y: nextY + bumpDown))

            x = nextX
            y = nextY
            i += 1
        }

        NSColor.labelColor.withAlphaComponent(0.2).setStroke()
        path.stroke()
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?,
                       characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }
}

// MARK: - Notelink Attachment

final class NotelinkAttachment: NSTextAttachment {
    let noteID: String
    let noteTitle: String

    init(noteID: String, noteTitle: String) {
        self.noteID = noteID
        self.noteTitle = noteTitle
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NotelinkAttachment does not support init(coder:)")
    }
}

// MARK: - Notelink Pill View (SwiftUI — rendered to image via ImageRenderer)

struct NotelinkPillView: View {
    let title: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 4) {
            Text("@")
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.2)

            Text(title.isEmpty ? "Untitled" : title)
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.2)
                .lineLimit(1)

            Image("IconArrowRightUpCircle")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        }
        .foregroundColor(.black)
        .padding(.horizontal, FontManager.InlineEditorPillRasterPadding.horizontal)
        .padding(.vertical, FontManager.InlineEditorPillRasterPadding.vertical)
        .background(Color("NotelinkPillBgColor"), in: Capsule())
        .fixedSize()
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct FileLinkPillView: View {
    let displayName: String

    var body: some View {
        HStack(spacing: 4) {
            Image("IconFileLink")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)

            Text(displayName.isEmpty ? "Untitled" : displayName)
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.2)
                .lineLimit(1)

            Image("IconArrowRightUpCircle")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        }
        // Match properties-panel file pills: untinted ButtonPrimary* tokens.
        .foregroundColor(Color("ButtonPrimaryTextColor"))
        .padding(.horizontal, FontManager.InlineEditorPillRasterPadding.horizontal)
        .padding(.vertical, FontManager.InlineEditorPillRasterPadding.vertical)
        .background(Color("ButtonPrimaryBgColor"), in: Capsule())
        .fixedSize()
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

/// Floating view hosted in the scroll view's clip view that renders an image
/// with rounded corners, drop shadow, subtle border, and edge-based resizing.
/// No visible handle — resize is indicated purely by cursor changes on the
/// right edge, bottom edge, and bottom-right corner. Captures the entire image
/// bounds for hit testing; non-edge clicks are forwarded to the text view.
final class InlineImageOverlayView: NSView {
    var image: NSImage? {
        didSet { imageLayer.contents = image }
    }
    var onResizeEnded: ((CGFloat) -> Void)?
    var containerWidth: CGFloat = 0
    var currentRatio: CGFloat = 1.0
    var storedFilename: String = ""
    weak var parentTextView: NSTextView?

    private let imageLayer = CALayer()
    private let shadowLayer = CALayer()
    private let borderLayer = CALayer()

    /// Large edge zones for comfortable resize grabbing.
    /// Right edge: rightmost 40px. Bottom edge: bottommost 40px. Corner: overlap of both.
    private let edgeZone: CGFloat = 40

    /// How far outside the image bounds the resize zone extends (straddles the edge).
    private let edgeOutset: CGFloat = 6

    /// Corner radius scales proportionally with image width.
    private var computedCornerRadius: CGFloat { 22 }

    private enum ResizeEdge { case right, bottom, corner }
    private var isDragging = false
    private var activeEdge: ResizeEdge?
    private var dragStartPoint: CGPoint = .zero
    private var dragStartWidth: CGFloat = 0
    private var dragStartHeight: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        // Drop shadow
        shadowLayer.backgroundColor = NSColor.black.cgColor
        shadowLayer.cornerCurve = .continuous
        shadowLayer.masksToBounds = false
        shadowLayer.shadowOpacity = 0.18
        shadowLayer.shadowRadius = 10
        shadowLayer.shadowOffset = CGSize(width: 0, height: 3)
        shadowLayer.shadowColor = NSColor.black.cgColor
        layer?.addSublayer(shadowLayer)

        // Image with continuous rounded corners
        imageLayer.masksToBounds = true
        imageLayer.cornerCurve = .continuous
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.allowsEdgeAntialiasing = true
        layer?.addSublayer(imageLayer)

        // Subtle border — continuous corners, adapts to light/dark mode
        borderLayer.cornerCurve = .continuous
        borderLayer.borderWidth = 1.0
        borderLayer.masksToBounds = true
        layer?.addSublayer(borderLayer)

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        for l: CALayer in [imageLayer, shadowLayer, borderLayer] {
            l.contentsScale = scale
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InlineImageOverlayView does not support init(coder:)")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearanceDependentLayers()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceDependentLayers()
    }

    private func updateAppearanceDependentLayers() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.borderColor = isDark
            ? NSColor.white.withAlphaComponent(0.06).cgColor
            : NSColor.black.withAlphaComponent(0.08).cgColor
        shadowLayer.shadowOpacity = 0
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let radius = computedCornerRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        imageLayer.cornerRadius = radius
        shadowLayer.frame = bounds
        shadowLayer.cornerRadius = radius
        borderLayer.frame = bounds
        borderLayer.cornerRadius = radius
        CATransaction.commit()
    }

    // MARK: - Cursor Rects

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        let zone = edgeZone
        let outset = edgeOutset

        // Corner (bottom-right) — extends outward by `outset` on both axes
        let cornerRect = CGRect(x: bounds.maxX - zone + outset, y: bounds.maxY - zone + outset,
                                width: zone, height: zone)
        addCursorRect(cornerRect, cursor: NSCursor.compatFrameResize(position: "bottomRight"))

        // Right edge (excluding corner) — extends outward by `outset`
        let rightRect = CGRect(x: bounds.maxX - zone + outset, y: bounds.minY,
                               width: zone, height: bounds.height - zone + outset)
        addCursorRect(rightRect, cursor: NSCursor.compatFrameResize(position: "right"))

        // Bottom edge (excluding corner) — extends outward by `outset`
        let bottomRect = CGRect(x: bounds.minX, y: bounds.maxY - zone + outset,
                                width: bounds.width - zone + outset, height: zone)
        addCursorRect(bottomRect, cursor: NSCursor.compatFrameResize(position: "bottom"))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { window?.invalidateCursorRects(for: self) }
    }

    // MARK: - Edge Detection

    /// Returns the appropriate resize cursor if `windowPoint` falls on an edge zone, nil otherwise.
    /// Called by the coordinator from InlineNSTextView.mouseMoved to bypass NSTextView's cursor override.
    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        guard let edge = resizeEdge(at: local) else { return nil }
        return switch edge {
        case .right:  NSCursor.compatFrameResize(position: "right")
        case .bottom: NSCursor.compatFrameResize(position: "bottom")
        case .corner: NSCursor.compatFrameResize(position: "bottomRight")
        }
    }

    private func resizeEdge(at point: NSPoint) -> ResizeEdge? {
        // Expand hit area by edgeOutset so the resize zone straddles the image edge
        let expandedBounds = bounds.insetBy(dx: -edgeOutset, dy: -edgeOutset)
        guard expandedBounds.contains(point) else { return nil }
        let onRight = point.x >= bounds.maxX - edgeZone + edgeOutset
        let onBottom = point.y >= bounds.maxY - edgeZone + edgeOutset
        if onRight && onBottom { return .corner }
        if onRight { return .right }
        if onBottom { return .bottom }
        return nil
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if isDragging { return self }
        // Expand hit area so resize zones that straddle the edge are reachable
        let expandedBounds = bounds.insetBy(dx: -edgeOutset, dy: -edgeOutset)
        return expandedBounds.contains(local) ? self : nil
    }

    // MARK: - Resize Drag + Event Forwarding

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if let edge = resizeEdge(at: local) {
            isDragging = true
            activeEdge = edge
            dragStartPoint = event.locationInWindow
            dragStartWidth = bounds.width
            dragStartHeight = bounds.height
            // Lock cursor during drag so it persists even outside view bounds
            let resizeCursor: NSCursor = switch edge {
            case .right:  NSCursor.compatFrameResize(position: "right")
            case .bottom: NSCursor.compatFrameResize(position: "bottom")
            case .corner: NSCursor.compatFrameResize(position: "bottomRight")
            }
            resizeCursor.push()
        } else {
            parentTextView?.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let edge = activeEdge,
              let imgSize = image?.size, imgSize.width > 0 else {
            if !isDragging { parentTextView?.mouseDragged(with: event) }
            return
        }
        let aspect = imgSize.height / imgSize.width

        let newWidth: CGFloat
        switch edge {
        case .right, .corner:
            let dx = event.locationInWindow.x - dragStartPoint.x
            newWidth = dragStartWidth + dx
        case .bottom:
            let dy = dragStartPoint.y - event.locationInWindow.y
            newWidth = (dragStartHeight + dy) / aspect
        }

        let clamped = max(100, min(containerWidth, newWidth))
        frame = CGRect(x: frame.minX, y: frame.minY, width: clamped, height: clamped * aspect)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else {
            parentTextView?.mouseUp(with: event)
            return
        }
        NSCursor.pop()  // Balance the push() from mouseDown
        isDragging = false
        activeEdge = nil
        guard containerWidth > 0 else { return }
        let newRatio = min(1.0, max(0.1, frame.width / containerWidth))
        currentRatio = newRatio
        onResizeEnded?(newRatio)
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// Attachment type that captures metadata for non-image files.
enum FileViewMode: String, Codable {
    case tag      // Capsule pill (current behavior)
    case medium   // 400px min-width preview, left-aligned
    case full     // Full note-width preview
}

final class NoteFileAttachment: NSTextAttachment {
    var storedFilename: String
    var originalFilename: String
    let typeIdentifier: String
    let displayLabel: String
    var viewMode: FileViewMode

    // Preserved from original FileLinkAttachment for tag reversion
    var originalFileLinkPath: String?
    var originalFileLinkDisplayName: String?
    var originalFileLinkBookmark: String?
    var cachedImageAspectRatio: CGFloat? // width/height, nil for non-images
    var cachedPdfPageAspectRatio: CGFloat? // width/height of first page, nil for non-PDFs

    init(storedFilename: String, originalFilename: String, typeIdentifier: String, displayLabel: String, viewMode: FileViewMode = .tag) {
        self.storedFilename = storedFilename
        self.originalFilename = originalFilename
        self.typeIdentifier = typeIdentifier
        self.displayLabel = displayLabel
        self.viewMode = viewMode
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteFileAttachment does not support init(coder:)")
    }
}

final class FileLinkAttachment: NSTextAttachment {
    let filePath: String
    let displayName: String
    let bookmarkBase64: String

    init(filePath: String, displayName: String, bookmarkBase64: String = "") {
        self.filePath = filePath
        self.displayName = displayName
        self.bookmarkBase64 = bookmarkBase64
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FileLinkAttachment does not support init(coder:)")
    }
}

// MARK: - Representable Implementations

struct TodoEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    var noteID: UUID? = nil
    let colorScheme: ColorScheme
    let focusRequestID: UUID?
    let editorInstanceID: UUID?
    var readOnly: Bool = false
    var onNavigateToNote: ((UUID) -> Void)?
    var fetchNote: ((UUID) -> Note?)?
    /// Delivers the editor text view's `undoManager` for sticker / pane-level undo integration.
    var onUndoManagerAvailable: ((UndoManager?) -> Void)? = nil
    private let unlimitedDimension = CGFloat.greatestFiniteMagnitude

    func makeNSView(context: Context) -> InlineNSTextView {
        let textView = InlineNSTextView()
        textView.delegate = context.coordinator
        textView.actionDelegate = context.coordinator
        textView.editorInstanceID = editorInstanceID
        textView.isEditable = !readOnly
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = !readOnly
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        // Use Charter for body text as per design requirements
        textView.font = FontManager.bodyNS(size: ThemeManager.currentBodyFontSize(), weight: .regular)
        // Slightly taller vertical inset so rasterized pill attachments (notelinks, file links)
        // that extend above the body cap height stay inside the text view instead of clipping
        // against the scroll clip view or stacked panels above the editor.
        textView.textContainerInset = NSSize(width: 28, height: 20)
        textView.linkTextAttributes = [
            .underlineStyle: 0,
            .underlineColor: NSColor.clear,
        ]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: unlimitedDimension, height: unlimitedDimension)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // Ensure text view can receive focus and input
        let defaults = UserDefaults.standard
        textView.isAutomaticQuoteSubstitutionEnabled = defaults.bool(forKey: ThemeManager.smartQuotesKey)
        textView.isAutomaticDashSubstitutionEnabled = defaults.bool(forKey: ThemeManager.smartDashesKey)
        textView.isContinuousSpellCheckingEnabled = defaults.bool(forKey: ThemeManager.spellCheckKey)
        textView.isAutomaticSpellingCorrectionEnabled = defaults.bool(forKey: ThemeManager.autocorrectKey)

        // Critical: Ensure text view accepts text input
        textView.insertionPointColor = NSColor.controlAccentColor

        // Only set background highlight for selection — omit foreground override
        // so custom text colors (e.g. purple) remain visible while selected.
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor
        ]

        // Enable Writing Tools when text is selected (without standalone button)
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .complete
        }
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            container.lineFragmentPadding = 0
            container.containerSize = NSSize(width: 600, height: unlimitedDimension)

            // Install custom layout manager for typing animation
            let typingLayoutManager = TypingAnimationLayoutManager()
            container.replaceLayoutManager(typingLayoutManager)
            typingLayoutManager.animatingTextView = textView
            context.coordinator.typingAnimationManager = typingLayoutManager
        }

        let initialScheme = colorScheme
        if let resolvedAppearance = appearance(for: initialScheme) {
            textView.appearance = resolvedAppearance
        }

        let resolvedColor = resolvedTextColor(
            for: initialScheme, appearance: textView.appearance)
        textView.textColor = resolvedColor
        textView.typingAttributes = Coordinator.baseTypingAttributes(for: initialScheme)
        textView.defaultParagraphStyle = Coordinator.baseParagraphStyle()

        context.coordinator.updateColorScheme(initialScheme)
        context.coordinator.onUndoManagerAvailable = onUndoManagerAvailable
        context.coordinator.configure(with: textView)
        context.coordinator.onUndoManagerAvailable?(textView.undoManager)

        context.coordinator.applyInitialText(text)

        // Ensure layout is complete before returning
        if let container = textView.textContainer, let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: container)
        }

        // Defer first responder setup to avoid focus issues
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            // Position cursor at start so empty notes show a blinking caret immediately
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            // Force redraw so block quote bars render (needsDisplay in makeNSView fires
            // before the view is in the window hierarchy, so AppKit skips the draw)
            textView.needsDisplay = true
        }

        return textView
    }

    func updateNSView(_ nsView: InlineNSTextView, context: Context) {
        let textView = nsView
        let resolvedScheme = colorScheme

        // Only update appearance/colors when the color scheme has actually changed
        if context.coordinator.currentColorScheme != resolvedScheme {
            if let resolvedAppearance = appearance(for: resolvedScheme) {
                textView.appearance = resolvedAppearance
                // Do NOT call textView.textColor — its setter walks the whole storage and
                // overwrites every foreground-color attribute, destroying custom hex colors.
                // NSColor.labelColor in the storage adapts automatically when appearance changes.
                textView.typingAttributes = Coordinator.baseTypingAttributes(for: resolvedScheme)
                textView.linkTextAttributes = [
                    .underlineStyle: 0,
                    .underlineColor: NSColor.clear,
                ]
                context.coordinator.updateColorScheme(resolvedScheme)
                textView.needsDisplay = true
            }
        }

        // Update container size only if needed (account for horizontal textContainerInset)
        if let container = textView.textContainer, let layoutManager = textView.layoutManager {
            let width = textView.bounds.width - textView.textContainerInset.width * 2
            if width > 0 && abs(container.containerSize.width - width) > 0.5 {
                container.containerSize = NSSize(width: width, height: unlimitedDimension)
                layoutManager.ensureLayout(for: container)
            }
        }

        // Sync navigate callback
        context.coordinator.updateNoteContext(noteID)
        context.coordinator.onNavigateToNote = onNavigateToNote
        context.coordinator.fetchNote = fetchNote
        context.coordinator.onUndoManagerAvailable = onUndoManagerAvailable
        context.coordinator.onUndoManagerAvailable?(textView.undoManager)

        // Only update text if it has actually changed
        context.coordinator.updateIfNeeded(with: text)
        context.coordinator.requestFocusIfNeeded(focusRequestID)

        // During makeNSView the text view isn't in the hierarchy yet, so overlay
        // creation and the bounds-change observer registration are deferred.
        // By the time SwiftUI calls updateNSView the view IS hosted — finish setup.
        context.coordinator.completeDeferredSetup(in: textView)

        // Reposition overlays only when the frame has actually changed — avoids
        // redundant full-storage enumeration on every SwiftUI layout pass.
        // Uses coalesced dispatch to prevent layout-invalidation storms during
        // split-view resize (multiple triggers collapse into one pass).
        if context.coordinator.lastKnownTextViewWidth != textView.bounds.width {
            context.coordinator.lastKnownTextViewWidth = textView.bounds.width
            context.coordinator.scheduleOverlayUpdate()
        }
    }

    // Report dynamic size to SwiftUI so the editor grows with its content naturally
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: InlineNSTextView, context: Context)
        -> CGSize
    {
        guard let container = nsView.textContainer,
            let layoutManager = nsView.layoutManager
        else {
            let fallbackWidth = proposal.width ?? 600
            return CGSize(width: fallbackWidth, height: 24)
        }

        let proposedWidth = proposal.width ?? nsView.bounds.width
        let targetWidth = max(proposedWidth, 100)

        // Update container size for layout calculation (account for horizontal textContainerInset)
        let containerWidth = max(targetWidth - nsView.textContainerInset.width * 2, 100)
        if abs(container.containerSize.width - containerWidth) > 0.5 {
            container.containerSize = NSSize(width: containerWidth, height: unlimitedDimension)
        }

        // Ensure layout is up to date
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)

        let lineHeight =
            nsView.font?.boundingRectForFont.size.height
            ?? nsView.defaultParagraphStyle?.minimumLineHeight
            ?? 24
        let minHeight = lineHeight + nsView.textContainerInset.height * 2
        let contentHeight = used.height + nsView.textContainerInset.height * 2
        let height = max(contentHeight, minHeight)
        return CGSize(width: targetWidth, height: height)
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(
            text: $text,
            noteID: noteID,
            colorScheme: colorScheme,
            focusRequestID: focusRequestID,
            editorInstanceID: editorInstanceID,
            readOnly: readOnly
        )
    }

    private func resolvedColorScheme(for view: NSView?) -> ColorScheme? {
        if let appearance = view?.window?.effectiveAppearance ?? view?.effectiveAppearance,
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        {
            return match == .darkAqua ? .dark : .light
        }
        let appAppearance = NSApplication.shared.effectiveAppearance
        if let match = appAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return match == .darkAqua ? .dark : .light
        }
        return nil
    }

    private func appearance(for scheme: ColorScheme) -> NSAppearance? {
        switch scheme {
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .light:
            return NSAppearance(named: .aqua)
        @unknown default:
            return nil
        }
    }

    private func resolvedTextColor(for scheme: ColorScheme, appearance: NSAppearance?)
        -> NSColor
    {
        return NSColor.labelColor
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        weak var textView: NSTextView?
        private var observers: [NSObjectProtocol] = []
        private var lastSerialized = ""
        private var currentHoveredCharIndex: Int? = nil
        // `internal` (default) because `InlineNSTextView+MarkdownShortcuts.swift` reaches it
        // from a sibling file via `actionDelegate.formatter`.
        let formatter = TextFormattingManager()
        /// Reentrancy counter — supports nested isUpdating = true/false pairs safely.
        /// Read as Bool for backward compatibility; set true increments, set false decrements.
        private var _updatingCount = 0
        private var isUpdating: Bool {
            get { _updatingCount > 0 }
            set {
                if newValue {
                    _updatingCount += 1
                } else {
                    _updatingCount = max(0, _updatingCount - 1)
                }
            }
        }
        private var textBinding: Binding<String>
        private var lastHandledFocusRequestID: UUID?
        let editorInstanceID: UUID?
        private var noteID: UUID?

        // Debounce timer for fixInconsistentFonts — prevents running on every keystroke
        private var fixFontsWorkItem: DispatchWorkItem?
        // Accumulated edited range across debounce intervals for scoped font fixing
        private var pendingFontFixRange: NSRange?
        // Debounce timer for serialize() — avoids O(n) attribute enumeration on every keystroke
        private var serializeWorkItem: DispatchWorkItem?

        // Cache for ImageRenderer-rasterized pill images (notelinks, webclips, filelinks).
        // Keyed by "<type>|<id>|<colorScheme>" to avoid redundant synchronous renders.
        // Invalidated on color scheme change and rerenderPillAttachments().
        private let pillImageCache: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = 100
            cache.totalCostLimit = 20 * 1024 * 1024 // 20 MB advisory limit
            return cache
        }()

        // Typing animation state
        fileprivate weak var typingAnimationManager: TypingAnimationLayoutManager?
        private var pendingAnimationLocation: Int?
        private var pendingAnimationLength: Int?
        struct FileAttachmentMetadata {
            let storedFilename: String
            let originalFilename: String
            let typeIdentifier: String
            let displayLabel: String
            var viewMode: FileViewMode = .tag
        }

        // MARK: - Inline image overlay tracking
        var imageLoadTasks: [String: Task<Void, Never>] = [:]
        var imageOverlays: [ObjectIdentifier: InlineImageOverlayView] = [:]
        var mapOverlays: [ObjectIdentifier: MapBlockOverlayView] = [:]
        var tableOverlays: [ObjectIdentifier: NoteTableOverlayView] = [:]
        var calloutOverlays: [ObjectIdentifier: CalloutOverlayView] = [:]
        var codeBlockOverlays: [ObjectIdentifier: CodeBlockOverlayView] = [:]
        var tabsOverlays: [ObjectIdentifier: TabsContainerOverlayView] = [:]
        var cardSectionOverlays: [ObjectIdentifier: CardSectionOverlayView] = [:]
        var linkCardOverlays: [ObjectIdentifier: NSView] = [:]
        var linkCardThumbnailLoadAttempted: Set<ObjectIdentifier> = []
        var filePreviewOverlays: [ObjectIdentifier: FilePreviewOverlayView] = [:]

        /// Last container width we ran the divider-attachment sync against. `updateDividerAttachments`
        /// short-circuits when the width hasn't moved (within 0.5pt) since every `frameDidChange`
        /// would otherwise re-enumerate `.attachment` across the entire text storage.
        var lastKnownDividerContainerWidth: CGFloat?

        weak var overlayHostView: NSView?
        /// True when applyInitialText ran but the view was not in the hierarchy
        /// yet (no enclosingScrollView), so overlay creation was deferred.
        private var needsDeferredOverlaySetup = false
        var onNavigateToNote: ((UUID) -> Void)?
        var fetchNote: ((UUID) -> Note?)?
        var lastKnownTextViewWidth: CGFloat = 0
        /// True once the bounds-change observer on the clip view has been registered.
        /// Note: these flags are never reset because NSViewRepresentable does not provide
        /// a teardown hook for the Coordinator. If SwiftUI recreates the NSView while reusing
        /// the Coordinator, re-registration would need a reset path (e.g. dismantleNSView).
        private var hasBoundsObserver = false
        /// True once the frame-change observer on the scroll view has been registered.
        private var hasFrameObserver = false
        /// True once ancestor clipping has been disabled for overlay overflow.
        private var hasDisabledAncestorClipping = false
        /// Reentrancy guard — prevents cascading overlay updates from creating
        /// an infinite layout-invalidation cycle (split-view freeze bug).
        private var isUpdatingOverlays = false
        /// Snapshot of `NoteTableData` at column-divider drag began; consumed when resize ends.
        var pendingTableColumnResizeSnapshot: [ObjectIdentifier: NoteTableData] = [:]
        var pendingCodeBlockWidthResizeSnapshot: [ObjectIdentifier: CodeBlockData] = [:]
        var pendingCalloutWidthResizeSnapshot: [ObjectIdentifier: CalloutData] = [:]
        var pendingTabsWidthResizeSnapshot: [ObjectIdentifier: TabsContainerData] = [:]
        var pendingTabsHeightResizeSnapshot: [ObjectIdentifier: TabsContainerData] = [:]

        /// Parent (e.g. `NoteDetailView`) hooks the editor `NSUndoManager` for sticker mutations.
        var onUndoManagerAvailable: ((UndoManager?) -> Void)?

        /// Coalesces rapid overlay update requests (resize, scroll, layout
        /// completion) into a single pass on the next main-queue turn.
        private var pendingOverlayUpdate: DispatchWorkItem?
        /// After `updateIfNeeded` replaces storage, overlay frames must wait until SwiftUI/AppKit
        /// finish the current layout transaction — otherwise glyph rects stay wrong for a frame (G4).
        private var pendingPostNoteSwitchOverlayWork: DispatchWorkItem?

        func updateNoteContext(_ noteID: UUID?) {
            guard self.noteID != noteID else { return }
            self.noteID = noteID
        }

        /// Coalesces overlay update requests so multiple triggers
        /// (updateNSView, didCompleteLayoutFor, boundsDidChange) within
        /// the same run-loop turn collapse into a single pass.
        func scheduleOverlayUpdate() {
            pendingOverlayUpdate?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, !self.isUpdatingOverlays,
                      let tv = self.textView else { return }
                self.isUpdatingOverlays = true
                defer { self.isUpdatingOverlays = false }
                self.performSynchronizedOverlayLayoutPass(in: tv)
            }
            pendingOverlayUpdate = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        /// Forces text layout to finish, then updates every overlay **without** implicit
        /// NSView/CALayer animations. Note switches used to skip `ensureLayout` (unlike
        /// `applyInitialText`), so glyph rects were stale for the first overlay frame —
        /// combined with SwiftUI layout transactions that produced visible slide/crop glitches.
        private func performSynchronizedOverlayLayoutPass(in textView: NSTextView) {
            if let lm = textView.layoutManager, let tc = textView.textContainer {
                lm.ensureLayout(for: tc)
            }
            textView.layoutSubtreeIfNeeded()

            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            updateImageOverlays(in: textView)
            updateMapOverlays(in: textView)
            updateTableOverlays(in: textView)
            updateDividerAttachments(in: textView)
            updateCalloutOverlays(in: textView)
            updateCodeBlockOverlays(in: textView)
            updateTabsOverlays(in: textView)
            updateCardSectionOverlays(in: textView)
            updateLinkCardOverlays(in: textView)
            updateFilePreviewOverlays(in: textView)

            CATransaction.commit()
            NSAnimationContext.endGrouping()
        }

        static let inlineImageCache: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = 48
            cache.totalCostLimit = 50 * 1024 * 1024
            return cache
        }()

        // NSTextViewDelegate method to handle selection changes
        func textViewDidChangeSelection(_ notification: Notification) {
            // Post notification about selection change for floating toolbar
            guard let textView = self.textView else { return }
            let selectedRange = textView.selectedRange()

            // Only show floating toolbar if there's actual text selected (not just cursor)
            if selectedRange.length > 0 {
                // Calculate selection rectangle in text view's local coordinate space (same as CommandMenu)
                if let layoutManager = textView.layoutManager,
                   let textContainer = textView.textContainer {
                    
                    // Get the glyph range for the selection
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
                    
                    // Get the bounding rect for the selection in the text container
                    let selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    
                    // Get visible rect to understand scroll position
                    let visibleRect = textView.visibleRect
                    
                    // Convert selection rect to visible coordinates
                    // selectionRect is in text container space, we need to adjust for scroll
                    let selectionX = selectionRect.origin.x + textView.textContainerOrigin.x
                    let selectionYInContainer = selectionRect.origin.y + textView.textContainerOrigin.y
                    
                    // Adjust Y position relative to visible rect (accounts for scroll)
                    let selectionY = selectionYInContainer - visibleRect.origin.y
                    let selectionWidth = selectionRect.width
                    let selectionHeight = selectionRect.height

                    // Convert to window coordinates for proper positioning
                    // selectionRect is in text-container space; offset by textContainerOrigin
                    // to get view-local coordinates before converting to window space.
                    let selectionRectInView = selectionRect.offsetBy(
                        dx: textView.textContainerOrigin.x,
                        dy: textView.textContainerOrigin.y)
                    let selectionRectInWindow = textView.convert(selectionRectInView, to: nil)

                    // Cache selection so Edit Content can use it even after focus shifts
                    lastKnownSelectionRange = selectedRange
                    lastKnownSelectionText = (textView.string as NSString).substring(with: selectedRange)
                    lastKnownSelectionWindowRect = selectionRectInWindow

                    // Update formatting state for the current selection
                    formatter.updateFormattingState(from: textView)

                    // Post notification with selection info - let the view calculate toolbar position
                    // Extract font size, family, and text color from selection start
                    var selFontSize: CGFloat = ThemeManager.currentBodyFontSize()
                    var selFontFamily: String = "default"
                    var selTextColorHex: String? = nil
                    if let storage = textView.textStorage, selectedRange.location < storage.length {
                        if let font = storage.attribute(.font, at: selectedRange.location, effectiveRange: nil) as? NSFont {
                            selFontSize = font.pointSize
                            let familyName = font.familyName ?? ""
                            if familyName.contains("Charter") {
                                selFontFamily = "default"
                            } else if familyName.contains("Menlo") || familyName.contains("SF Mono") || familyName.contains("Courier") {
                                selFontFamily = "mono"
                            } else {
                                selFontFamily = "system"
                            }
                        }
                        if let colorHex = storage.attribute(.foregroundColor, at: selectedRange.location, effectiveRange: nil) as? NSColor {
                            let c = colorHex.usingColorSpace(.sRGB) ?? colorHex
                            let hex = String(format: "#%02x%02x%02x",
                                             Int(round(c.redComponent * 255)),
                                             Int(round(c.greenComponent * 255)),
                                             Int(round(c.blueComponent * 255)))
                            // Only report non-default colors (not label color)
                            if colorHex != NSColor.labelColor {
                                selTextColorHex = hex
                            }
                        }
                    }

                    var info: [String: Any] = [
                        "hasSelection": true,
                        "selectionX": selectionX,
                        "selectionY": selectionY,
                        "selectionWidth": selectionWidth,
                        "selectionHeight": selectionHeight,
                        "selectionWindowY": selectionRectInWindow.origin.y,
                        "selectionWindowX": selectionRectInWindow.origin.x,
                        "visibleWidth": visibleRect.width,
                        "visibleHeight": visibleRect.height,
                        "isBold": formatter.isBold,
                        "isItalic": formatter.isItalic,
                        "isUnderline": formatter.isUnderline,
                        "isStrikethrough": formatter.isStrikethrough,
                        "isHighlight": formatter.isHighlight,
                        "headingLevel": formatter.currentHeadingLevel,
                        "windowHeight": textView.window?.contentView?.bounds.height ?? 800,
                        "fontSize": selFontSize,
                        "fontFamily": selFontFamily
                    ]
                    if let hex = selTextColorHex { info["textColorHex"] = hex }
                    if let eid = editorInstanceID { info["editorInstanceID"] = eid }
                    NotificationCenter.default.post(
                        name: .textSelectionChanged,
                        object: nil,
                        userInfo: info
                    )
                }
            } else {
                // No selection - hide floating toolbar.
                // Do NOT clear the selection cache here. The cache exists specifically
                // to survive toolbar clicks (which cause AppKit to deselect the textView
                // synchronously during mouse-down, before SwiftUI's onChange fires).
                // The cache is naturally overwritten when the user makes a new selection,
                // and its only consumers (translate/edit) are gated behind the floating
                // toolbar which requires a selection to appear.
                var info: [String: Any] = ["hasSelection": false]
                if let eid = editorInstanceID { info["editorInstanceID"] = eid }
                NotificationCenter.default.post(
                    name: .textSelectionChanged,
                    object: nil,
                    userInfo: info
                )
            }
        }
        private var textBeforeWritingTools = ""
        var currentColorScheme: ColorScheme

        // Proofread inline overlay tracking: (pill view, highlighted NSRange, original text color attributes)
        private var proofreadPillViews: [(view: NSView, range: NSRange)] = []
        private var proofreadHighlightedRanges: [NSRange] = []
        private var proofreadScopeRange: NSRange = NSRange(location: NSNotFound, length: 0)

        // Last known non-empty selection — cached here so clicking the AI tools button
        // (which clears the NSTextView selection) doesn't lose context for Edit Content.
        private var lastKnownSelectionRange: NSRange = NSRange(location: NSNotFound, length: 0)
        var highlightEditRange: NSRange = NSRange(location: NSNotFound, length: 0)
        private var lastKnownSelectionText: String = ""
        private var lastKnownSelectionWindowRect: CGRect = .zero

        // Use Charter for body text as per design requirements
        private static var textFont: NSFont {
            FontManager.bodyNS(size: ThemeManager.currentBodyFontSize(), weight: .regular)
        }
        private static var baseLineHeight: CGFloat {
            ThemeManager.currentBodyFontSize() * 1.5
        }
        private static let todoLineHeight: CGFloat = 24
        // Access promoted from `private` to internal (default) so `NoteParagraphStyler`
        // (sibling file) can read these while styling paragraphs. The constants are
        // intentionally unchanged — only the visibility moved.
        static let checkboxIconSize: CGFloat = 26
        static let checkboxAttachmentWidth: CGFloat = 30
        static let baseBaselineOffset: CGFloat = 0.0
        private static let todoBaselineOffset: CGFloat = {
            return 0.0
        }()
        static var checkboxAttachmentYOffset: CGFloat { 0.0 }
        static let checkboxBaselineOffset: CGFloat = {
            return 0.0
        }()
        static let webClipMarkupPrefix = "[[webclip|"
        private static let webClipPattern = #"\[\[webclip\|([^|]*)\|([^|]*)\|([^\]]*)\]\]"#
        static let webClipRegex: NSRegularExpression? = try? NSRegularExpression(
            pattern: webClipPattern,
            options: []
        )
        static let plainLinkMarkupPrefix = "[[link|"
        static let linkCardMarkupPrefix = "[[linkcard|"
        private static let linkCardPattern = #"\[\[linkcard\|([^|]*)\|([^|]*)\|([^\]]*)\]\]"#
        static let linkCardRegex: NSRegularExpression? = try? NSRegularExpression(
            pattern: linkCardPattern,
            options: []
        )
        // Access promoted from `private` to internal so `NoteSerializer`
        // (sibling file) can reach these while serializing attachment metadata.
        static func cleanedWebClipComponent(_ value: Any?) -> String {
            guard let raw = value as? String else { return "" }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            return
                trimmed
                .replacingOccurrences(of: "|", with: " ")
                .replacingOccurrences(of: "]]", with: " ]")
        }

        static func sanitizedWebClipComponent(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            return
                trimmed
                .replacingOccurrences(of: "|", with: " ")
                .replacingOccurrences(of: "]]", with: " ")
        }

        static func normalizedURL(from raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                return trimmed
            }
            return "https://\(trimmed)"
        }

        /// Extract URL string from `.link` attribute regardless of type.
        /// AppKit may silently convert `.link` String values to URL objects,
        /// so we must handle both representations.
        /// Access promoted from `private` to internal for `NoteSerializer`.
        static func linkURLString(from attributes: [NSAttributedString.Key: Any]) -> String? {
            if let str = attributes[.link] as? String { return str }
            if let url = attributes[.link] as? URL { return url.absoluteString }
            return nil
        }

        static func resolvedDomain(from urlString: String) -> String {
            let normalized = normalizedURL(from: urlString)
            if let host = URL(string: normalized)?.host, !host.isEmpty {
                return host
            }
            return
                normalized
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
        }

        /// Access promoted from `private` to internal for `TodoEditorRepresentable+Deserializer.swift`.
        static func string(
            from match: NSTextCheckingResult, at index: Int, in text: String
        ) -> String {
            guard index < match.numberOfRanges else { return "" }
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: text) else { return "" }
            return String(text[swiftRange])
        }

        func makeNotelinkAttachment(noteID: String, noteTitle: String) -> NSMutableAttributedString {
            let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
            // Bump token when ``FontManager.InlineEditorPillRasterPadding`` or offset math changes so cached bitmaps refresh.
            let cacheKey = "notelink|ipr1|\(noteTitle)|\(currentColorScheme)|\(displayScale)" as NSString

            let attachment = NotelinkAttachment(noteID: noteID, noteTitle: noteTitle)

            let nsImage: NSImage
            if let cached = pillImageCache.object(forKey: cacheKey) {
                nsImage = cached
            } else {
                let pillView = NotelinkPillView(title: noteTitle, colorScheme: currentColorScheme)
                    .environment(\.colorScheme, currentColorScheme)
                let renderer = ImageRenderer(content: pillView)
                renderer.scale = displayScale
                renderer.isOpaque = false

                guard let cgImage = renderer.cgImage else {
                    let fallback = NSMutableAttributedString(string: "@\(noteTitle)")
                    fallback.addAttributes([.notelinkID: noteID, .notelinkTitle: noteTitle],
                                           range: NSRange(location: 0, length: fallback.length))
                    return fallback
                }

                let pixelWidth = CGFloat(cgImage.width)
                let pixelHeight = CGFloat(cgImage.height)
                let displaySize = CGSize(width: pixelWidth / displayScale, height: pixelHeight / displayScale)

                let img = NSImage(size: displaySize)
                img.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
                pillImageCache.setObject(img, forKey: cacheKey)
                nsImage = img
            }

            attachment.image = nsImage
            let pillSize = nsImage.size
            attachment.bounds = CGRect(
                x: 0,
                y: Self.imageTagVerticalOffset(for: pillSize.height),
                width: pillSize.width,
                height: pillSize.height
            )

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)
            attributed.addAttributes([
                .notelinkID: noteID,
                .notelinkTitle: noteTitle,
            ], range: range)
            return attributed
        }

        func makeFileLinkAttachment(filePath: String, displayName: String, bookmarkBase64: String = "") -> NSMutableAttributedString {
            let pillView = FileLinkPillView(displayName: displayName)
                .environment(\.colorScheme, currentColorScheme)
            let renderer = ImageRenderer(content: pillView)
            let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
            renderer.scale = displayScale
            renderer.isOpaque = false

            let attachment = FileLinkAttachment(filePath: filePath, displayName: displayName, bookmarkBase64: bookmarkBase64)

            guard let cgImage = renderer.cgImage else {
                let fallback = NSMutableAttributedString(string: displayName)
                var attrs: [NSAttributedString.Key: Any] = [.fileLinkPath: filePath, .fileLinkDisplayName: displayName]
                if !bookmarkBase64.isEmpty { attrs[.fileLinkBookmark] = bookmarkBase64 }
                fallback.addAttributes(attrs, range: NSRange(location: 0, length: fallback.length))
                return fallback
            }

            let pixelWidth = CGFloat(cgImage.width)
            let pixelHeight = CGFloat(cgImage.height)
            let displaySize = CGSize(width: pixelWidth / displayScale, height: pixelHeight / displayScale)

            let nsImage = NSImage(size: displaySize)
            nsImage.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

            attachment.image = nsImage
            attachment.bounds = CGRect(
                x: 0,
                y: Self.imageTagVerticalOffset(for: displaySize.height),
                width: displaySize.width,
                height: displaySize.height
            )

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)
            var attrs: [NSAttributedString.Key: Any] = [
                .fileLinkPath: filePath,
                .fileLinkDisplayName: displayName,
            ]
            if !bookmarkBase64.isEmpty { attrs[.fileLinkBookmark] = bookmarkBase64 }
            attributed.addAttributes(attrs, range: range)
            return attributed
        }

        private func insertFileLink(filePath: String, displayName: String, bookmarkBase64: String = "") {
            guard let textView = self.textView,
                  let textStorage = textView.textStorage else { return }

            let fileLinkString = makeFileLinkAttachment(filePath: filePath, displayName: displayName, bookmarkBase64: bookmarkBase64)
            let spaceStr = NSAttributedString(string: " ", attributes: Self.baseTypingAttributes(for: nil))
            let combined = NSMutableAttributedString()
            combined.append(fileLinkString)
            combined.append(spaceStr)

            let insertRange = textView.selectedRange()
            if textView.shouldChangeText(in: insertRange, replacementString: combined.string) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: insertRange, with: combined)
                textStorage.endEditing()
                textView.didChangeText()
                isUpdating = false
            }

            let newCursorPos = insertRange.location + combined.length
            textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
            textView.typingAttributes = Self.baseTypingAttributes(for: nil)
            syncText()
        }

        func makeWebClipAttachment(
            url rawURL: String,
            title: String?,
            description: String?,
            domain: String?
        ) -> NSMutableAttributedString {
            let normalizedURL = Self.normalizedURL(from: rawURL)
            let linkValue = normalizedURL.isEmpty ? rawURL : normalizedURL
            let resolvedDomain =
                (domain?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? domain!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : Self.resolvedDomain(from: linkValue))

            let fallbackTitle =
                (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                ? resolvedDomain
                : title!.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackExcerpt =
                (description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                ? "Open link to view the full preview."
                : description!.trimmingCharacters(in: .whitespacesAndNewlines)

                // Create the view without artificial width constraints - let it size to content
                let cardView = WebClipView(
                    title: fallbackTitle,
                    domain: resolvedDomain,
                    url: linkValue
                )
                .fixedSize()  // Size to fit content naturally
                .environment(\.colorScheme, currentColorScheme)

                let renderer = ImageRenderer(content: cardView)
                // Use display's native backing scale for pixel-perfect rendering
                let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
                renderer.scale = displayScale
                renderer.isOpaque = false

                let attachment = NSTextAttachment()

                guard let cgImage = renderer.cgImage else {
                    let attributed = NSMutableAttributedString(
                        string: "[WebClip: \(fallbackTitle)]")
                    return attributed
                }

                // Create NSImage from CGImage with proper pixel dimensions
                let pixelWidth = CGFloat(cgImage.width)
                let pixelHeight = CGFloat(cgImage.height)

                // Calculate display size (points) from pixel size
                let displaySize = CGSize(
                    width: pixelWidth / displayScale,
                    height: pixelHeight / displayScale)

                let nsImage = NSImage(size: displaySize)
                nsImage.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

                attachment.image = nsImage

                attachment.bounds = CGRect(
                    x: 0,
                    y: Self.imageTagVerticalOffset(for: displaySize.height),
                    width: displaySize.width,
                    height: displaySize.height
                )
                let attributed = NSMutableAttributedString(attachment: attachment)

            let attachmentRange = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.link, value: linkValue, range: attachmentRange)
            attributed.addAttribute(.underlineStyle, value: 0, range: attachmentRange)
            attributed.addAttribute(.webClipTitle, value: fallbackTitle, range: attachmentRange)
            attributed.addAttribute(
                .webClipDescription, value: fallbackExcerpt, range: attachmentRange)
            attributed.addAttribute(
                .webClipDomain, value: resolvedDomain, range: attachmentRange)
            // Store the full URL separately so it survives AppKit stripping the .link attribute
            attributed.addAttribute(
                .webClipFullURL, value: linkValue, range: attachmentRange)

            // Apply special paragraph style for web clips to prevent overlap
            attributed.addAttribute(
                .paragraphStyle, value: Self.webClipParagraphStyle(), range: attachmentRange)

            return attributed
        }

        /// Pre-tints a template NSImage with the given color. AppKit does NOT auto-tint template
        /// images set on an ``NSTextAttachment`` — it draws the raw alpha. Without this, our Figma
        /// arrow renders in a muted default gray regardless of the attribute foreground color.
        private static func tintedImage(_ source: NSImage, with color: NSColor) -> NSImage {
            let size = source.size
            guard size.width > 0, size.height > 0 else { return source }
            let tinted = NSImage(size: size, flipped: false) { rect in
                source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.isTemplate = false
            return tinted
        }

        /// Inline arrow from Figma `IconArrowRight` — stored as `[[arrow]]` in note markup.
        /// - Parameter textAttrs: Optional attributes from surrounding context (typing or deserialize).
        ///   Uses `.font` for scale and `.foregroundColor` so template rendering matches body / block quote.
        ///   Does not copy `.paragraphStyle` here; paragraph styling comes from ``styleTodoParagraphs``.
        func makeArrowAttachment(merging textAttrs: [NSAttributedString.Key: Any]? = nil) -> NSMutableAttributedString {
            let font = (textAttrs?[.font] as? NSFont) ?? Self.textFont
            let foreground = (textAttrs?[.foregroundColor] as? NSColor) ?? NSColor.labelColor
            let attachment = NoteArrowAttachment(data: nil, ofType: nil)
            guard let image = NSImage(named: NoteArrowAttachment.assetName) else {
                var attrs = Self.baseTypingAttributes(for: currentColorScheme)
                attrs[.font] = font
                attrs[.foregroundColor] = foreground
                return NSMutableAttributedString(string: "\u{2192}", attributes: attrs)
            }
            // Slightly larger than cap height so the arrow reads as a full-weight glyph next to body
            // text (Figma shaft is thin at pure capHeight). ~capHeight * 1.35 matches Unicode U+2192.
            let cap = font.capHeight
            let targetHeight = max(13, cap * 1.35)
            let scale = targetHeight / max(image.size.height, 1)
            let w = image.size.width * scale
            let h = image.size.height * scale
            // Render the template alpha filled with the resolved foreground so color matches the
            // body text around it. Paragraph styling is re-applied by ``styleTodoParagraphs``.
            attachment.image = Self.tintedImage(image, with: foreground)
            // Sit on the text baseline like a capital letter: image bottom at baseline, top near
            // cap line. Tiny negative nudge centers the shaft on x-height for optical alignment.
            let opticalDrop: CGFloat = -((h - cap) / 2.0)
            attachment.bounds = CGRect(x: 0, y: opticalDrop, width: w, height: h)
            let attributed = NSMutableAttributedString(attachment: attachment)
            let attachmentRange = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.font, value: font, range: attachmentRange)
            attributed.addAttribute(.foregroundColor, value: foreground, range: attachmentRange)
            if textAttrs?[.blockQuote] as? Bool == true {
                attributed.addAttribute(.blockQuote, value: true, range: attachmentRange)
            }
            if let hlHex = textAttrs?[.highlightColor] as? String {
                attributed.addAttribute(.highlightColor, value: hlHex, range: attachmentRange)
                if let hlVar = textAttrs?[.highlightVariant] as? Int {
                    attributed.addAttribute(.highlightVariant, value: hlVar, range: attachmentRange)
                }
            }
            return attributed
        }

        /// Create a plain blue text link attachment -- looks like text, behaves like a button.
        /// - Parameters:
        ///   - rawURL: Destination URL string from markup (may contain percent escapes).
        ///   - label: Optional `[[link|URL|LABEL]]` display string; when nil or equal to the URL, the URL is shown.
        func makePlainLinkAttachment(url rawURL: String, label: String? = nil) -> NSMutableAttributedString {
            let normalizedURL = Self.normalizedURL(from: rawURL)
            let linkValue = normalizedURL.isEmpty ? rawURL : normalizedURL

            let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayText: String
            if let trimmedLabel, !trimmedLabel.isEmpty, trimmedLabel != linkValue {
                displayText = trimmedLabel
            } else {
                displayText = linkValue
            }

            // Body font + single-line truncation so bare URLs share the same raster height as short
            // labels; vertical offset uses cap-height, not variable bitmap height (alignment fix).
            let linkView = Text(displayText)
                .font(FontManager.body(size: Self.textFont.pointSize, weight: .regular))
                .foregroundColor(.accentColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .environment(\.colorScheme, currentColorScheme)

            let renderer = ImageRenderer(content: linkView)
            let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
            renderer.scale = displayScale
            renderer.isOpaque = false

            let attachment = NSTextAttachment()

            guard let cgImage = renderer.cgImage else {
                // Fall back to plain text matching the pill label (not only the raw URL).
                return NSMutableAttributedString(string: displayText)
            }

            let pixelWidth = CGFloat(cgImage.width)
            let pixelHeight = CGFloat(cgImage.height)
            let displaySize = CGSize(
                width: pixelWidth / displayScale,
                height: pixelHeight / displayScale)

            let nsImage = NSImage(size: displaySize)
            nsImage.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

            attachment.image = nsImage
            // The rasterized Text is a bare glyph block (no pill padding). Its internal baseline
            // sits `|descender|` above the image bottom. Using the pill-centering helper shifts
            // the baseline; align directly to font metrics instead.
            attachment.bounds = CGRect(
                x: 0,
                y: Self.textFont.descender,
                width: displaySize.width,
                height: displaySize.height
            )

            let attributed = NSMutableAttributedString(attachment: attachment)
            let attachmentRange = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.link, value: linkValue, range: attachmentRange)
            attributed.addAttribute(.underlineStyle, value: 0, range: attachmentRange)
            attributed.addAttribute(.plainLinkURL, value: linkValue, range: attachmentRange)
            if let trimmedLabel, !trimmedLabel.isEmpty, trimmedLabel != linkValue {
                attributed.addAttribute(.plainLinkLabel, value: trimmedLabel, range: attachmentRange)
            }
            attributed.addAttribute(
                .paragraphStyle, value: Self.webClipParagraphStyle(), range: attachmentRange)

            return attributed
        }

        /// Create an inline image attachment tag from a filename
        /// Create a block-level image attachment with the given width ratio.
        func makeImageAttachment(filename: String, widthRatio: CGFloat = 1.0) -> NSMutableAttributedString {
            // Get aspect ratio from in-memory cache to avoid blocking disk I/O.
            // Falls back to 4:3 if not cached — updateImageOverlays will correct
            // bounds asynchronously once the image loads.
            let imageSize: CGSize
            let cacheKey = filename as NSString
            if let cachedImg = Self.inlineImageCache.object(forKey: cacheKey) {
                imageSize = cachedImg.size
            } else {
                imageSize = CGSize(width: 4, height: 3)
            }

            var containerWidth = textView?.textContainer?.containerSize.width ?? 400
            // During makeNSView, replaceLayoutManager resets the container width to 0.
            // Fall back to a sensible default so attachments aren't zero-sized.
            if containerWidth < 1 { containerWidth = 400 }
            let maxDisplayWidth = containerWidth
            let displayWidth = min(maxDisplayWidth, maxDisplayWidth * widthRatio)
            let aspectRatio = imageSize.height / imageSize.width
            let displayHeight = displayWidth * aspectRatio

            let attachment = NoteImageAttachment(filename: filename, widthRatio: widthRatio)
            // Cache the aspect ratio so overlay updates don't need to wait for disk I/O
            if imageSize.width > 0 && imageSize.height > 0 {
                attachment.cachedAspectRatio = imageSize.width / imageSize.height
            }
            let cellSize = CGSize(width: displayWidth, height: displayHeight)
            attachment.attachmentCell = ImageSizeAttachmentCell(size: cellSize)
            attachment.bounds = CGRect(origin: .zero, size: cellSize)

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.imageFilename, value: filename, range: range)
            attributed.addAttribute(.imageWidthRatio, value: widthRatio, range: range)

            // Block paragraph style
            let blockStyle = NSMutableParagraphStyle()
            blockStyle.alignment = .left
            blockStyle.paragraphSpacing = 8
            blockStyle.paragraphSpacingBefore = 8
            attributed.addAttribute(.paragraphStyle, value: blockStyle, range: range)

            return attributed
        }

        func resolvedMapBlockWidth(
            for widthRatio: CGFloat,
            containerWidth: CGFloat
        ) -> CGFloat {
            let clampedContainerWidth = max(containerWidth, 1)
            let minimumWidth = MapBlockLayoutMetrics.minimumDisplayWidth(
                for: clampedContainerWidth
            )
            let proposedWidth = clampedContainerWidth * max(widthRatio, 0.0001)
            return min(clampedContainerWidth, max(minimumWidth, proposedWidth))
        }

        func makeMapAttachment(mapData: MapBlockData) -> NSMutableAttributedString {
            var containerWidth = textView?.textContainer?.containerSize.width ?? 400
            if containerWidth < 1 { containerWidth = 400 }

            let displayWidth = resolvedMapBlockWidth(
                for: mapData.widthRatio,
                containerWidth: containerWidth
            )
            let displayHeight = displayWidth * MapBlockData.aspectHeightRatio

            let attachment = NoteMapAttachment(mapData: mapData)
            let cellSize = CGSize(width: displayWidth, height: displayHeight)
            attachment.attachmentCell = MapSizeAttachmentCell(size: cellSize, mapData: mapData)
            attachment.bounds = CGRect(origin: .zero, size: cellSize)

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.mapSerializedData, value: mapData.serialize(), range: range)

            let blockStyle = NSMutableParagraphStyle()
            blockStyle.alignment = .left
            blockStyle.paragraphSpacing = 8
            blockStyle.paragraphSpacingBefore = 8
            attributed.addAttribute(.paragraphStyle, value: blockStyle, range: range)

            let appearance = textView?.window?.effectiveAppearance
                ?? textView?.effectiveAppearance
                ?? NSApp.effectiveAppearance
            MapBlockSnapshotRenderer.requestSnapshot(
                for: mapData,
                size: cellSize,
                appearance: appearance,
                controlView: textView
            )

            return attributed
        }

        /// Create an inline file attachment tag with metadata
        func makeFileAttachment(metadata: FileAttachmentMetadata)
            -> NSMutableAttributedString
        {
            func fallbackAttributedString() -> NSMutableAttributedString {
                return NSMutableAttributedString(
                    string: "[File: \(metadata.displayLabel)]"
                )
            }

            let attachment = NoteFileAttachment(
                storedFilename: metadata.storedFilename,
                originalFilename: metadata.originalFilename,
                typeIdentifier: metadata.typeIdentifier,
                displayLabel: metadata.displayLabel,
                viewMode: metadata.viewMode
            )

            // Cache aspect ratios for accurate height reservation
            let category = FileCategory.classify(metadata.typeIdentifier)
            if category == .image {
                attachment.cachedImageAspectRatio = FileAttachmentStorageManager.imageAspectRatio(
                    for: metadata.storedFilename)
            } else if category == .pdf {
                attachment.cachedPdfPageAspectRatio = FileAttachmentStorageManager.pdfPageAspectRatio(
                    for: metadata.storedFilename)
            }

            if metadata.viewMode == .tag {
                // Tag mode: render as capsule pill bitmap (original behavior)
                let tagView = FileAttachmentTagView(label: metadata.displayLabel)
                    .environment(\.colorScheme, currentColorScheme)
                let renderer = ImageRenderer(content: tagView)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                renderer.scale = scale
                renderer.isOpaque = false

                guard let cgImage = renderer.cgImage else {
                    return fallbackAttributedString()
                }

                let displaySize = CGSize(
                    width: CGFloat(cgImage.width) / scale,
                    height: CGFloat(cgImage.height) / scale
                )

                let renderedImage = NSImage(size: displaySize)
                renderedImage.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

                attachment.image = renderedImage
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: renderedImage)
                attachment.bounds = CGRect(
                    x: 0,
                    y: Self.imageTagVerticalOffset(for: displaySize.height),
                    width: displaySize.width,
                    height: displaySize.height
                )
            } else {
                // Extracted mode: reserve space for overlay view
                var containerWidth = textView?.textContainer?.containerSize.width ?? 400
                if containerWidth < 1 { containerWidth = 400 }
                let previewWidth: CGFloat = metadata.viewMode == .full
                    ? containerWidth
                    : min(400, containerWidth)
                let info = FilePreviewOverlayView.FileAttachmentInfo(
                    storedFilename: metadata.storedFilename,
                    originalFilename: metadata.originalFilename,
                    typeIdentifier: metadata.typeIdentifier,
                    displayLabel: metadata.displayLabel,
                    imageAspectRatio: attachment.cachedImageAspectRatio,
                    pdfPageAspectRatio: attachment.cachedPdfPageAspectRatio
                )
                let previewHeight = FilePreviewOverlayView.heightForData(
                    info, viewMode: metadata.viewMode, width: previewWidth)
                let cellSize = CGSize(width: previewWidth, height: previewHeight)
                attachment.attachmentCell = CalloutSizeAttachmentCell(size: cellSize)
                attachment.bounds = CGRect(origin: .zero, size: cellSize)
            }

            let attributed = NSMutableAttributedString(attachment: attachment)
            let attachmentRange = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(
                .fileStoredFilename,
                value: metadata.storedFilename,
                range: attachmentRange
            )
            attributed.addAttribute(
                .fileOriginalFilename,
                value: metadata.originalFilename,
                range: attachmentRange
            )
            attributed.addAttribute(
                .fileTypeIdentifier,
                value: metadata.typeIdentifier,
                range: attachmentRange
            )
            attributed.addAttribute(
                .fileDisplayLabel,
                value: metadata.displayLabel,
                range: attachmentRange
            )
            attributed.addAttribute(
                .fileViewMode,
                value: metadata.viewMode.rawValue,
                range: attachmentRange
            )

            if metadata.viewMode != .tag {
                let blockStyle = NSMutableParagraphStyle()
                blockStyle.alignment = .left
                blockStyle.paragraphSpacing = 8
                blockStyle.paragraphSpacingBefore = 8
                attributed.addAttribute(.paragraphStyle, value: blockStyle, range: attachmentRange)
            }

            return attributed
        }


        func endAttachmentHover() {
            guard currentHoveredCharIndex != nil else { return }
            currentHoveredCharIndex = nil
            var userInfo: [String: Any] = [:]
            if let eid = editorInstanceID { userInfo["editorInstanceID"] = eid }
            NotificationCenter.default.post(name: .linkHoverDismiss, object: nil, userInfo: userInfo)
        }

        func handleAttachmentHover(at point: CGPoint, in textView: NSTextView) -> Bool {
            guard let layoutManager = textView.layoutManager,
                  let textStorage = textView.textStorage,
                  let textContainer = textView.textContainer else { return false }

            let ptInContainer = CGPoint(
                x: point.x - textView.textContainerOrigin.x,
                y: point.y - textView.textContainerOrigin.y)
            let gi = layoutManager.glyphIndex(for: ptInContainer, in: textContainer)
            guard gi < layoutManager.numberOfGlyphs else { return false }
            let charIdx = layoutManager.characterIndexForGlyph(at: gi)
            guard charIdx < textStorage.length else { return false }

            // Check for any hoverable link or attachment type.
            // Cache the attachment lookup — it's used for both type
            // checking and tight bounding-rect computation below.
            let attachment = textStorage.attribute(.attachment, at: charIdx, effectiveRange: nil)
            let isNotelink = attachment is NotelinkAttachment
                || textStorage.attribute(.notelinkID, at: charIdx, effectiveRange: nil) != nil
            let isWebclip = textStorage.attribute(.webClipTitle, at: charIdx, effectiveRange: nil) != nil
            let isPlainLink = textStorage.attribute(.plainLinkURL, at: charIdx, effectiveRange: nil) != nil
            let isLinkCard = attachment is NoteLinkCardAttachment
            let isFileLink = attachment is FileLinkAttachment
                || textStorage.attribute(.fileLinkPath, at: charIdx, effectiveRange: nil) != nil
            let isStoredFile: Bool
            if let nfa = attachment as? NoteFileAttachment {
                isStoredFile = nfa.viewMode == .tag
            } else if textStorage.attribute(.fileStoredFilename, at: charIdx, effectiveRange: nil) != nil {
                let rawMode = textStorage.attribute(.fileViewMode, at: charIdx, effectiveRange: nil) as? String
                isStoredFile = rawMode == nil || FileViewMode(rawValue: rawMode!) == .tag
            } else {
                isStoredFile = false
            }

            guard isNotelink || isWebclip || isPlainLink || isLinkCard || isFileLink || isStoredFile else {
                if currentHoveredCharIndex != nil { endAttachmentHover() }
                return false
            }

            // Compute a tight bounding rect and verify the point is
            // actually inside the visual bounds of the element.
            //
            // For attachment characters we use the attachment's own
            // width and the line-fragment-used rect (which excludes
            // paragraph spacing) instead of boundingRect(forGlyphRange:)
            // — that API returns the full container width and includes
            // paragraphSpacing, causing false-positive triggers in the
            // whitespace beside and between pills.
            let adjustedRect: CGRect
            if let att = attachment as? NSTextAttachment, att.bounds.width > 0 {
                let lineFragRect = layoutManager.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
                let loc = layoutManager.location(forGlyphAt: gi)
                let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: gi, effectiveRange: nil)
                adjustedRect = CGRect(
                    x: lineFragRect.origin.x + loc.x + textView.textContainerOrigin.x,
                    y: usedRect.origin.y + textView.textContainerOrigin.y,
                    width: att.bounds.width,
                    height: usedRect.height)
            } else {
                let glyphRange = NSRange(location: gi, length: 1)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                adjustedRect = CGRect(
                    x: rect.origin.x + textView.textContainerOrigin.x,
                    y: rect.origin.y + textView.textContainerOrigin.y,
                    width: rect.width,
                    height: rect.height)
            }

            guard adjustedRect.contains(point) else {
                if currentHoveredCharIndex != nil { endAttachmentHover() }
                return false
            }

            // Same link -- no need to re-post
            if currentHoveredCharIndex == charIdx { return true }

            currentHoveredCharIndex = charIdx
            var userInfo: [String: Any] = [
                "rect": NSValue(rect: adjustedRect),
                "charIndex": charIdx,
                "isFileAttachment": isStoredFile || isFileLink,
            ]
            if let eid = editorInstanceID { userInfo["editorInstanceID"] = eid }
            NotificationCenter.default.post(name: .linkHoverDetected, object: nil, userInfo: userInfo)
            return true
        }

        /// Checks all image overlays for a resize edge at the given window point.
        /// Returns the appropriate resize cursor, or nil if the point isn't on any edge.
        func resizeCursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
            for (_, overlay) in imageOverlays {
                if let cursor = overlay.cursorForPoint(windowPoint) {
                    return cursor
                }
            }
            for (_, overlay) in mapOverlays {
                if let cursor = overlay.cursorForPoint(windowPoint) {
                    return cursor
                }
            }
            for (_, overlay) in codeBlockOverlays {
                if let cursor = overlay.cursorForPoint(windowPoint) {
                    return cursor
                }
            }
            for (_, overlay) in calloutOverlays {
                if let cursor = overlay.cursorForPoint(windowPoint) {
                    return cursor
                }
            }
            for (_, overlay) in tableOverlays {
                if let cursor = overlay.cursorForPoint(windowPoint) {
                    return cursor
                }
            }
            for (_, overlay) in tabsOverlays {
                if let cursor = overlay.cursorForPoint(windowPoint) {
                    return cursor
                }
            }
            for (_, overlay) in cardSectionOverlays {
                if let cursor = overlay.cursorForPoint(windowPoint) {
                    return cursor
                }
            }
            return nil
        }

        let readOnly: Bool

        init(text: Binding<String>, noteID: UUID? = nil, colorScheme: ColorScheme, focusRequestID: UUID?, editorInstanceID: UUID? = nil, readOnly: Bool = false) {
            self.textBinding = text
            self.noteID = noteID
            self.currentColorScheme = colorScheme
            self.lastHandledFocusRequestID = focusRequestID
            self.editorInstanceID = editorInstanceID
            self.readOnly = readOnly
        }

        /// Remove all overlay subviews immediately. Used by NoteSnapshotRenderer
        /// to clean up overlays created for an offscreen (windowless) text view.
        // `removeAllOverlays()` moved to `TodoEditorRepresentable+OverlayManagement.swift` (Batch 5).

        deinit {
            pendingOverlayUpdate?.cancel()
            pendingPostNoteSwitchOverlayWork?.cancel()
            imageLoadTasks.values.forEach { $0.cancel() }
            imageLoadTasks.removeAll()
            nonisolated(unsafe) let manager = typingAnimationManager
            let imgOverlays = imageOverlays.values.map { $0 }
            let liveMapOverlays = mapOverlays.values.map { $0 }
            let tblOverlays = tableOverlays.values.map { $0 }
            let callOverlays = calloutOverlays.values.map { $0 }
            let codeOverlays = codeBlockOverlays.values.map { $0 }
            let tabOverlays = tabsOverlays.values.map { $0 }
            let cardOverlays = cardSectionOverlays.values.map { $0 }
            let fileOverlays = filePreviewOverlays.values.map { $0 }
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            Task { @MainActor in
                manager?.clearAllAnimations()
                imgOverlays.forEach { $0.removeFromSuperview() }
                liveMapOverlays.forEach { $0.removeFromSuperview() }
                tblOverlays.forEach { $0.removeFromSuperview() }
                callOverlays.forEach { $0.removeFromSuperview() }
                codeOverlays.forEach { $0.removeFromSuperview() }
                tabOverlays.forEach { $0.removeFromSuperview() }
                cardOverlays.forEach { $0.removeFromSuperview() }
                fileOverlays.forEach { $0.removeFromSuperview() }
            }
        }

        func configure(with textView: NSTextView) {
            self.textView = textView
            // Remove all existing notification observers before re-registering
            // to prevent accumulation when updateNSView calls configure() repeatedly.
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            // Always host overlays on the text view itself so they are
            // positioned in text-view-local coordinates and scroll
            // naturally with the content. Using the clip view required
            // coordinate conversion (textView.convert → clipView) that
            // became stale whenever SwiftUI re-laid-out the view hierarchy
            // (e.g. AI panels appearing) without triggering an overlay update.
            let newHost: NSView = textView
            if overlayHostView !== newHost {
                imageOverlays.values.forEach { $0.removeFromSuperview() }
                imageOverlays.removeAll()
                mapOverlays.values.forEach { $0.removeFromSuperview() }
                mapOverlays.removeAll()
                tableOverlays.values.forEach { $0.removeFromSuperview() }
                tableOverlays.removeAll()
                filePreviewOverlays.values.forEach { $0.removeFromSuperview() }
                filePreviewOverlays.removeAll()
                overlayHostView = newHost
            }
            // Register as layout manager delegate for overlay position tracking
            textView.layoutManager?.delegate = self
            registerBoundsObserverIfNeeded(for: textView)
            registerFrameObserverIfNeeded(for: textView)
            registerDisplayScaleObserver()

            // Prevent layout shifts when gaining focus
            let windowKey = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: textView.window,
                queue: .main
            ) { [weak self] _ in
                // Ensure layout is stable when window becomes key
                Task { @MainActor [weak self] in
                    if let textView = self?.textView, let textContainer = textView.textContainer {
                        textView.layoutManager?.ensureLayout(for: textContainer)
                    }
                }
            }

            let insertTodo = NotificationCenter.default.addObserver(
                forName: .insertTodoInEditor, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                Task { @MainActor [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    // Skip if a card text view is first responder — the card overlay handles its own todo insertion.
                    if let firstResp = textView.window?.firstResponder as? NSTextView,
                       firstResp !== textView { return }
                    self.insertTodo()
                }
            }

            let insertLink = NotificationCenter.default.addObserver(
                forName: .insertWebClipInEditor, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let url = notification.object as? String else { return }
                Task { @MainActor [weak self] in
                    self?.insertWebClip(url: url)
                }
            }

            let convertToWebClip = NotificationCenter.default.addObserver(
                forName: .convertSelectedTextToWebClip, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                Task { @MainActor [weak self] in
                    self?.convertSelectedTextToWebClip()
                }
            }

            let insertFileLink = NotificationCenter.default.addObserver(
                forName: .insertFileLinkInEditor, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let filePath = notification.userInfo?["filePath"] as? String,
                      let displayName = notification.userInfo?["displayName"] as? String else { return }
                let bookmarkBase64 = notification.userInfo?["bookmarkBase64"] as? String ?? ""
                Task { @MainActor [weak self] in
                    self?.insertFileLink(filePath: filePath, displayName: displayName, bookmarkBase64: bookmarkBase64)
                }
            }

            let insertVoiceTranscript = NotificationCenter.default.addObserver(
                forName: .insertVoiceTranscriptInEditor, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                // We're on main queue (specified in observer), use assumeIsolated for synchronous execution
                // This prevents race condition with view dismissal that occurred with Task wrapper
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    guard let transcript = notification.object as? String else { return }
                    self.insertVoiceTranscript(transcript: transcript)
                }
            }

            let insertImage = NotificationCenter.default.addObserver(
                forName: .insertImageInEditor, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let filename = notification.object as? String else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.insertImage(filename: filename)
                }
            }

            let insertMap = NotificationCenter.default.addObserver(
                forName: .insertMapInEditor, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let serializedMapData = notification.object as? String else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.insertMap(serializedMapData: serializedMapData)
                }
            }

            let applyTool = NotificationCenter.default.addObserver(
                forName: .applyEditTool, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let raw = notification.userInfo?["tool"] as? String else { return }
                guard let tool = EditTool(rawValue: raw) else { return }
                MainActor.assumeIsolated { [weak self] in
                    guard let self = self, let textView = self.textView else { return }

                    let isBlockInsertion = [EditTool.table, .callout, .codeBlock, .tabs, .cards].contains(tool)

                    // For inline formatting, skip if another NSTextView has focus
                    // (overlay text views handle their own formatting).
                    // For block insertions, always target the main editor -- restore focus if needed.
                    if !isBlockInsertion {
                        if let firstResp = textView.window?.firstResponder as? NSTextView,
                           firstResp !== textView {
                            return
                        }
                    } else {
                        textView.window?.makeFirstResponder(textView)
                    }

                    if isBlockInsertion {
                        // Block insertions run without CATransaction (setDisableActions
                        // suppresses initial layer display for overlay NSViews).
                        // isUpdating must be set so that updateIfNeeded (called from
                        // updateNSView when SwiftUI sees the binding change) skips its
                        // textStorage.setAttributedString replacement -- which would
                        // destroy the just-inserted attachment and its overlay.
                        self.isUpdating = true
                        if tool == .table {
                            self.insertTable()
                        } else if tool == .callout {
                            self.insertCallout()
                        } else if tool == .codeBlock {
                            self.insertCodeBlock()
                        } else if tool == .tabs {
                            self.insertTabs()
                        } else if tool == .cards {
                            self.insertCardSection()
                        }
                        self.isUpdating = false
                    } else {
                        // Suppress typing animation and disable CA/NS animations
                        // so toolbar-initiated inline formatting applies instantly.
                        self.isUpdating = true
                        NSAnimationContext.beginGrouping()
                        NSAnimationContext.current.duration = 0
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        self.formatter.applyFormatting(to: textView, tool: tool)
                        self.styleTodoParagraphs()
                        CATransaction.commit()
                        NSAnimationContext.endGrouping()
                        self.isUpdating = false
                        self.syncText()
                    }
                    // Re-broadcast formatting state so the floating toolbar updates
                    self.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
                }
            }

            let applyCommandMenuTool = NotificationCenter.default.addObserver(
                forName: .applyCommandMenuTool, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                // Extract notification data before passing to MainActor context
                guard let info = notification.object as? [String: Any],
                      let tool = info["tool"] as? EditTool,
                      let slashLocation = info["slashLocation"] as? Int else {
                    return
                }
                let filterLength = (info["filterLength"] as? Int) ?? 0
                Task { @MainActor [weak self] in
                    guard let self = self,
                          let textView = self.textView,
                          let textStorage = textView.textStorage else {
                        return
                    }

                    // Remove the "/" character and any filter text that follows it
                    let deleteLength = min(1 + filterLength, textStorage.length - slashLocation)
                    if slashLocation >= 0 && slashLocation < textStorage.length && deleteLength > 0 {
                        let deleteRange = NSRange(location: slashLocation, length: deleteLength)
                        if textView.shouldChangeText(in: deleteRange, replacementString: "") {
                            // Treat slash deletion as part of the same logical command-menu insert.
                            // If we let textDidChange sync here, the binding is updated once for the
                            // slash removal, then again for the actual insert, which causes extra
                            // redraw churn during a single command pick.
                            self.isUpdating = true
                            textStorage.replaceCharacters(in: deleteRange, with: "")
                            textView.didChangeText()
                            self.isUpdating = false
                        }
                    }

                    // Apply the selected tool
                    // Some command-menu tools already call syncText() internally after they
                    // finish their own atomic insert. Avoid a second sync from this wrapper.
                    let toolPerformsOwnSync = [EditTool.todo, .table, .callout, .codeBlock, .tabs, .cards].contains(tool)

                    if toolPerformsOwnSync {
                        self.isUpdating = true
                        if tool == .todo {
                            self.insertTodo()
                        } else if tool == .table {
                            self.insertTable()
                        } else if tool == .callout {
                            self.insertCallout()
                        } else if tool == .codeBlock {
                            self.insertCodeBlock()
                        } else if tool == .tabs {
                            self.insertTabs()
                        } else if tool == .cards {
                            self.insertCardSection()
                        }
                        self.isUpdating = false
                    } else {
                        // Match the toolbar inline-formatting path: keep the storage mutation
                        // and the final binding sync in one controlled step.
                        self.isUpdating = true
                        self.formatter.applyFormatting(to: textView, tool: tool)
                        self.styleTodoParagraphs()
                        self.isUpdating = false
                        self.syncText()
                    }
                }
            }

            let applyNotePickerSelection = NotificationCenter.default.addObserver(
                forName: .applyNotePickerSelection, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let info = notification.object as? [String: Any],
                      let noteIDStr = info["noteID"] as? String,
                      let noteID = UUID(uuidString: noteIDStr),
                      let noteTitle = info["noteTitle"] as? String,
                      let atLocation = info["atLocation"] as? Int else { return }
                let filterLength = (info["filterLength"] as? Int) ?? 0
                Task { @MainActor [weak self] in
                    self?.insertNoteLink(noteID: noteID, title: noteTitle, atLocation: atLocation, filterLength: filterLength)
                }
            }

            let navigateNoteLink = NotificationCenter.default.addObserver(
                forName: .navigateToNoteLink, object: nil, queue: .main
            ) { [weak self] notification in
                guard let noteID = notification.userInfo?["noteID"] as? UUID else { return }
                Task { @MainActor [weak self] in
                    self?.onNavigateToNote?(noteID)
                }
            }

            let performSearch = NotificationCenter.default.addObserver(
                forName: .performSearchOnPage, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let query = notification.userInfo?["query"] as? String else { return }
                Task { @MainActor [weak self] in
                    self?.performAndReportSearch(query: query)
                }
            }

            let highlightSearch = NotificationCenter.default.addObserver(
                forName: .highlightSearchMatches, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let userInfo = notification.userInfo,
                      let ranges = userInfo["ranges"] as? [NSRange],
                      let activeIndex = userInfo["activeIndex"] as? Int else { return }
                Task { @MainActor [weak self] in
                    self?.applySearchHighlighting(ranges: ranges, activeIndex: activeIndex)
                }
            }

            let clearSearch = NotificationCenter.default.addObserver(
                forName: .clearSearchHighlights, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                Task { @MainActor [weak self] in
                    self?.clearSearchHighlighting()
                }
            }

            // MARK: Proofread show annotations
            let proofreadShow = NotificationCenter.default.addObserver(
                forName: .aiProofreadShowAnnotations, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let annotations = notification.object as? [ProofreadAnnotation] else { return }
                let activeIndex = notification.userInfo?["activeIndex"] as? Int ?? 0
                let scopeRange = (notification.userInfo?["scopeRange"] as? NSValue)?.rangeValue
                Task { @MainActor [weak self] in
                    self?.applyProofreadAnnotations(
                        annotations,
                        activeIndex: activeIndex,
                        scopeRange: scopeRange
                    )
                }
            }

            // MARK: Proofread clear overlays
            let proofreadClear = NotificationCenter.default.addObserver(
                forName: .aiProofreadClearOverlays, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                Task { @MainActor [weak self] in
                    self?.clearProofreadOverlays()
                }
            }

            // MARK: Proofread apply suggestion
            let proofreadApply = NotificationCenter.default.addObserver(
                forName: .aiProofreadApplySuggestion, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let userInfo = notification.userInfo,
                      let original = userInfo["original"] as? String,
                      let replacement = userInfo["replacement"] as? String else { return }
                let originalRange = (userInfo["originalRange"] as? NSValue)?.rangeValue
                Task { @MainActor [weak self] in
                    self?.applyProofreadSuggestion(
                        original: original,
                        replacement: replacement,
                        originalRange: originalRange
                    )
                }
            }

            // MARK: Edit Content — capture selection
            // Runs synchronously on the main queue so `.aiEditCaptureSelection` is posted before any
            // chained `.aiToolAction` (e.g. proofread with `followWithTool`) is handled.
            let captureSelection = NotificationCenter.default.addObserver(
                forName: .aiEditRequestSelection, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let self = self, let textView = self.textView else { return }
                // Skip if a card text view is first responder — the card overlay
                // captures its own selection. But DO NOT skip for field editors
                // (e.g. the TranslateInputSubmenu's TextField), which are also
                // NSTextView instances but aren't card editors.
                if let firstResp = textView.window?.firstResponder as? NSTextView,
                   firstResp !== textView,
                   !firstResp.isFieldEditor { return }
                self.captureSelectionForEditContent()
                // Proofread: chain tool after capture so `handleAITool` gets `selectedText` in userInfo
                // (avoids race with SwiftUI `capturedSelectionText` and async Task ordering).
                if let raw = notification.userInfo?["followWithTool"] as? String,
                   raw == AITool.proofread.rawValue {
                    var info: [String: Any] = [:]
                    if let eid = self.editorInstanceID { info["editorInstanceID"] = eid }
                    if self.lastKnownSelectionRange.length > 0 {
                        info["selectedText"] = self.lastKnownSelectionText
                        info["selectedRange"] = NSValue(range: self.lastKnownSelectionRange)
                    }
                    NotificationCenter.default.post(
                        name: .aiToolAction,
                        object: AITool.proofread,
                        userInfo: info
                    )
                }
            }

            let urlPasteMention = NotificationCenter.default.addObserver(
                forName: .urlPasteSelectMention, object: nil, queue: .main
            ) { [weak self] notification in
                guard let info = notification.object as? [String: Any],
                      let url = info["url"] as? String,
                      let rangeValue = info["range"] as? NSValue else { return }
                if let nid = info["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                let range = rangeValue.rangeValue
                Task { @MainActor [weak self] in
                    self?.replaceURLPasteWithWebClip(url: url, range: range)
                }
            }

            let urlPasteSelectPlainLink = NotificationCenter.default.addObserver(
                forName: .urlPasteSelectPlainLink, object: nil, queue: .main
            ) { [weak self] notification in
                guard let info = notification.object as? [String: Any],
                      let url = info["url"] as? String,
                      let rangeValue = info["range"] as? NSValue else { return }
                if let nid = info["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                let range = rangeValue.rangeValue
                Task { @MainActor [weak self] in
                    self?.replaceURLPasteWithPlainLink(url: url, range: range)
                }
            }

            let urlPasteSelectCard = NotificationCenter.default.addObserver(
                forName: .urlPasteSelectCard, object: nil, queue: .main
            ) { [weak self] notification in
                guard let info = notification.object as? [String: Any],
                      let url = info["url"] as? String,
                      let rangeValue = info["range"] as? NSValue else { return }
                if let nid = info["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                let range = rangeValue.rangeValue
                Task { @MainActor [weak self] in
                    self?.replaceURLPasteWithLinkCard(url: url, range: range)
                }
            }

            let urlPasteDismiss = NotificationCenter.default.addObserver(
                forName: .urlPasteDismiss, object: nil, queue: .main
            ) { [weak self] notification in
                if let info = notification.object as? [String: Any],
                   let nid = info["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                let range: NSRange?
                if let info = notification.object as? [String: Any] {
                    range = (info["range"] as? NSValue)?.rangeValue
                } else {
                    range = (notification.object as? NSValue)?.rangeValue
                }
                Task { @MainActor [weak self] in
                    if let range { self?.clearURLPasteHighlight(range: range) }
                }
            }

            let codePasteSelectCodeBlock = NotificationCenter.default.addObserver(
                forName: .codePasteSelectCodeBlock, object: nil, queue: .main
            ) { [weak self] notification in
                guard let info = notification.object as? [String: Any],
                      let code = info["code"] as? String,
                      let rangeValue = info["range"] as? NSValue,
                      let language = info["language"] as? String else { return }
                let range = rangeValue.rangeValue
                Task { @MainActor [weak self] in
                    self?.replaceCodePasteWithCodeBlock(code: code, range: range, language: language)
                }
            }

            let codePasteSelectPlainText = NotificationCenter.default.addObserver(
                forName: .codePasteSelectPlainText, object: nil, queue: .main
            ) { [weak self] notification in
                guard let info = notification.object as? [String: Any],
                      let rangeValue = info["range"] as? NSValue else { return }
                let range = rangeValue.rangeValue
                Task { @MainActor [weak self] in
                    self?.clearCodePasteHighlight(range: range)
                }
            }

            let codePasteDismissObserver = NotificationCenter.default.addObserver(
                forName: .codePasteDismiss, object: nil, queue: .main
            ) { [weak self] notification in
                let rangeValue = (notification.object as? [String: Any])?["range"] as? NSValue
                let rangeToClear: NSRange? = rangeValue.map { $0.rangeValue }
                Task { @MainActor [weak self] in
                    if let r = rangeToClear { self?.clearCodePasteHighlight(range: r) }
                }
            }

            let applyColor = NotificationCenter.default.addObserver(
                forName: Notification.Name("applyTextColor"), object: nil, queue: .main
            ) { [weak self] notification in
                guard let hex = notification.userInfo?["hex"] as? String else { return }
                // Filter by editorInstanceID — only apply if this notification targets our pane
                if let expectedID = self?.editorInstanceID,
                   let notifID = notification.userInfo?["editorInstanceID"] as? UUID,
                   notifID != expectedID { return }
                // Run synchronously on the main actor — we are already on .main (queue: .main),
                // so MainActor.assumeIsolated is safe and avoids the async Task hop that would
                // let a note-switch fire persistIfNeeded() before editedContent is updated.
                MainActor.assumeIsolated { [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    if let fr = textView.window?.firstResponder as? NSTextView, fr !== textView { return }
                    let range = self.lastKnownSelectionRange
                    guard range.length > 0 else { return }
                    self.formatter.applyTextColor(hex: hex, range: range, to: textView)
                    self.syncText()
                }
            }

            let removeColor = NotificationCenter.default.addObserver(
                forName: .removeTextColor, object: nil, queue: .main
            ) { [weak self] notification in
                if let expectedID = self?.editorInstanceID,
                   let notifID = notification.userInfo?["editorInstanceID"] as? UUID,
                   notifID != expectedID { return }
                MainActor.assumeIsolated { [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    if let fr = textView.window?.firstResponder as? NSTextView, fr !== textView { return }
                    let range = self.lastKnownSelectionRange
                    guard range.length > 0 else { return }
                    self.formatter.removeTextColor(range: range, from: textView)
                    self.syncText()
                }
            }

            let applyHighlight = NotificationCenter.default.addObserver(
                forName: .applyHighlightColor, object: nil, queue: .main
            ) { [weak self] notification in
                guard let hex = notification.userInfo?["hex"] as? String else { return }
                if let expectedID = self?.editorInstanceID,
                   let notifID = notification.userInfo?["editorInstanceID"] as? UUID,
                   notifID != expectedID { return }
                MainActor.assumeIsolated { [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    if let fr = textView.window?.firstResponder as? NSTextView, fr !== textView { return }
                    let range = self.highlightEditRange.length > 0
                        ? self.highlightEditRange
                        : self.lastKnownSelectionRange
                    guard range.length > 0 else { return }
                    self.formatter.applyHighlight(hex: hex, range: range, to: textView)
                    self.syncText()
                    // Save range for subsequent color changes from the picker
                    self.highlightEditRange = range
                    // Collapse selection so highlight color is visible (not hidden by blue selection)
                    textView.setSelectedRange(NSRange(location: range.location + range.length, length: 0))

                    // Post layout-accurate position for the color picker
                    if let layoutManager = textView.layoutManager,
                       let textContainer = textView.textContainer {
                        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                        let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                        let rectInView = NSRect(
                            x: boundingRect.origin.x + textView.textContainerOrigin.x,
                            y: boundingRect.origin.y + textView.textContainerOrigin.y,
                            width: boundingRect.width,
                            height: boundingRect.height)
                        let rectInWindow = textView.convert(rectInView, to: nil)
                        var posInfo: [String: Any] = [
                            "selectionWindowX": rectInWindow.origin.x,
                            "selectionWindowY": rectInWindow.origin.y,
                            "selectionWidth": rectInWindow.width,
                            "selectionHeight": rectInWindow.height,
                            "windowHeight": textView.window?.contentView?.bounds.height ?? 800,
                            "charRange": NSValue(range: range)
                        ]
                        if let eid = self.editorInstanceID { posInfo["editorInstanceID"] = eid }
                        NotificationCenter.default.post(
                            name: .highlightTextClicked, object: nil, userInfo: posInfo
                        )
                    }
                }
            }

            let setHighlightRange = NotificationCenter.default.addObserver(
                forName: .setHighlightEditRange, object: nil, queue: .main
            ) { [weak self] notification in
                if let expectedID = self?.editorInstanceID,
                   let notifID = notification.userInfo?["editorInstanceID"] as? UUID,
                   notifID != expectedID { return }
                MainActor.assumeIsolated { [weak self] in
                    if let rangeValue = notification.userInfo?["range"] as? NSValue {
                        self?.highlightEditRange = rangeValue.rangeValue
                    }
                }
            }

            let removeHighlight = NotificationCenter.default.addObserver(
                forName: .removeHighlightColor, object: nil, queue: .main
            ) { [weak self] notification in
                if let expectedID = self?.editorInstanceID,
                   let notifID = notification.userInfo?["editorInstanceID"] as? UUID,
                   notifID != expectedID { return }
                MainActor.assumeIsolated { [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    if let fr = textView.window?.firstResponder as? NSTextView, fr !== textView { return }
                    var range = self.highlightEditRange.length > 0
                        ? self.highlightEditRange
                        : self.lastKnownSelectionRange
                    guard range.length > 0 else { return }
                    // Expand to full contiguous highlight span
                    if let storage = textView.textStorage,
                       range.location != NSNotFound,
                       NSMaxRange(range) <= storage.length,
                       storage.attribute(.highlightColor, at: range.location, effectiveRange: nil) != nil {
                        var fullRange = range
                        _ = storage.attribute(.highlightColor, at: range.location,
                                              longestEffectiveRange: &fullRange,
                                              in: NSRange(location: 0, length: storage.length))
                        range = fullRange
                    }
                    // Only proceed if range actually contains highlighted text
                    guard range.location != NSNotFound,
                          NSMaxRange(range) <= (textView.textStorage?.length ?? 0) else { return }
                    var hasHighlight = false
                    textView.textStorage?.enumerateAttribute(.highlightColor, in: range, options: []) { value, _, stop in
                        if value != nil { hasHighlight = true; stop.pointee = true }
                    }
                    guard hasHighlight else { return }

                    self.formatter.removeHighlight(range: range, from: textView)
                    self.syncText()
                    self.highlightEditRange = NSRange(location: NSNotFound, length: 0)
                }
            }

            let settingsObserver = NotificationCenter.default.addObserver(
                forName: ThemeManager.editorSettingsChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyEditorSettings()
                }
            }

            // Inline-code pill fills read tint from UserDefaults in `drawBackground`; redraw when
            // hue or intensity changes so pills match tabs / code-block chip without a note switch.
            let tintDidChangeObserver = NotificationCenter.default.addObserver(
                forName: ThemeManager.tintDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.textView?.needsDisplay = true
                }
            }

            // MARK: Replace search match
            let replaceMatch = NotificationCenter.default.addObserver(
                forName: .replaceCurrentSearchMatch, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let userInfo = notification.userInfo,
                      let query = userInfo["query"] as? String,
                      let replacement = userInfo["replacement"] as? String,
                      let matchIndex = userInfo["matchIndex"] as? Int else { return }
                Task { @MainActor [weak self] in
                    self?.replaceSearchMatch(query: query, replacement: replacement, matchIndex: matchIndex)
                }
            }

            // MARK: Replace all search matches
            let replaceAll = NotificationCenter.default.addObserver(
                forName: .replaceAllSearchMatches, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let userInfo = notification.userInfo,
                      let query = userInfo["query"] as? String,
                      let replacement = userInfo["replacement"] as? String else { return }
                Task { @MainActor [weak self] in
                    self?.replaceAllSearchMatches(query: query, replacement: replacement)
                }
            }

            // MARK: Edit Content -- apply replacement through text storage
            let editReplace = NotificationCenter.default.addObserver(
                forName: .aiEditApplyReplacement, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                // Skip if a card overlay originated this AI session (card stores its own target).
                if notification.userInfo?["cardOrigin"] as? Bool == true { return }
                guard let userInfo = notification.userInfo,
                      let original = userInfo["original"] as? String,
                      let replacement = userInfo["replacement"] as? String else { return }
                let originalRange = (userInfo["originalRange"] as? NSValue)?.rangeValue
                Task { @MainActor [weak self] in
                    self?.applyEditContentReplacement(
                        original: original,
                        replacement: replacement,
                        originalRange: originalRange
                    )
                }
            }

            // MARK: Proofread -- batch replace all through text storage
            let proofreadReplaceAll = NotificationCenter.default.addObserver(
                forName: .aiProofreadReplaceAll, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let annotations = notification.userInfo?["annotations"] as? [ProofreadAnnotation] else { return }
                Task { @MainActor [weak self] in
                    self?.replaceAllProofreadSuggestions(annotations)
                }
            }

            // MARK: Text Generation -- insert generated text at cursor
            let textGenInsert = NotificationCenter.default.addObserver(
                forName: .aiTextGenInsert, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                // Skip if a card overlay originated this AI session.
                if notification.userInfo?["cardOrigin"] as? Bool == true { return }
                guard let text = notification.object as? String else { return }
                Task { @MainActor [weak self] in
                    self?.insertTextAtCursor(text)
                }
            }

            // Sync menu state from SwiftUI → InlineNSTextView instance vars
            let syncMenuState = NotificationCenter.default.addObserver(
                forName: .syncEditorMenuState, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                let isCommandMenuShowing = notification.userInfo?["isCommandMenuShowing"] as? Bool
                let commandSlashLocation = notification.userInfo?["commandSlashLocation"] as? Int
                let isURLPasteMenuShowing = notification.userInfo?["isURLPasteMenuShowing"] as? Bool
                let isCodePasteMenuShowing = notification.userInfo?["isCodePasteMenuShowing"] as? Bool
                let isNotePickerShowing = notification.userInfo?["isNotePickerShowing"] as? Bool
                let notePickerAtLocation = notification.userInfo?["notePickerAtLocation"] as? Int
                Task { @MainActor [weak self] in
                    guard let self = self,
                          let textView = self.textView as? InlineNSTextView else { return }
                    if let v = isCommandMenuShowing { textView.isCommandMenuShowing = v }
                    if let v = commandSlashLocation { textView.commandSlashLocation = v }
                    if let v = isURLPasteMenuShowing { textView.isURLPasteMenuShowing = v }
                    if let v = isCodePasteMenuShowing { textView.isCodePasteMenuShowing = v }
                    if let v = isNotePickerShowing { textView.isNotePickerShowing = v }
                    if let v = notePickerAtLocation { textView.notePickerAtLocation = v }
                }
            }

            let applyFontSize = NotificationCenter.default.addObserver(
                forName: .applyFontSize, object: nil, queue: .main
            ) { [weak self] notification in
                guard let size = notification.userInfo?["size"] as? CGFloat else { return }
                if let expectedID = self?.editorInstanceID,
                   let notifID = notification.userInfo?["editorInstanceID"] as? UUID,
                   notifID != expectedID { return }
                MainActor.assumeIsolated { [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    if let fr = textView.window?.firstResponder as? NSTextView, fr !== textView { return }
                    let range = self.lastKnownSelectionRange
                    guard range.length > 0 else { return }
                    self.formatter.applyFontSize(size, to: textView, range: range)
                    self.syncText()
                }
            }

            let applyFontFamily = NotificationCenter.default.addObserver(
                forName: .applyFontFamily, object: nil, queue: .main
            ) { [weak self] notification in
                guard let styleRaw = notification.userInfo?["style"] as? String,
                      let style = BodyFontStyle(rawValue: styleRaw) else { return }
                if let expectedID = self?.editorInstanceID,
                   let notifID = notification.userInfo?["editorInstanceID"] as? UUID,
                   notifID != expectedID { return }
                MainActor.assumeIsolated { [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    if let fr = textView.window?.firstResponder as? NSTextView, fr !== textView { return }
                    let range = self.lastKnownSelectionRange
                    guard range.length > 0 else { return }
                    self.formatter.applyFontFamily(style, to: textView, range: range)
                    self.syncText()
                }
            }

            let printNote = NotificationCenter.default.addObserver(
                forName: .printCurrentNote, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                Task { @MainActor [weak self] in
                    self?.handlePrint()
                }
            }

            let quickLookTrigger = NotificationCenter.default.addObserver(
                forName: .triggerQuickLook, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                Task { @MainActor [weak self] in
                    self?.triggerQuickLookForLinkAtCursor()
                }
            }

            let quickLookHoverTrigger = NotificationCenter.default.addObserver(
                forName: .linkHoverQuickLookTriggered, object: nil, queue: .main
            ) { [weak self] notification in
                guard let charIndex = notification.userInfo?["charIndex"] as? Int else { return }
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                Task { @MainActor [weak self] in
                    self?.triggerQuickLookForCharIndex(charIndex)
                }
            }

            let fileExtractTrigger = NotificationCenter.default.addObserver(
                forName: .fileExtractTriggered, object: nil, queue: .main
            ) { [weak self] notification in
                guard let charIndex = notification.userInfo?["charIndex"] as? Int else { return }
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                Task { @MainActor [weak self] in
                    self?.extractFileAtCharIndex(charIndex)
                }
            }

            let flushSerializationBeforeNoteSwitch = NotificationCenter.default.addObserver(
                forName: .jotFlushEditorSerializationBeforeNoteSwitch,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                guard let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                      let myID = self.editorInstanceID,
                      nid == myID
                else { return }
                MainActor.assumeIsolated {
                    self.flushPendingSerialization()
                }
            }

            // Broadcast flush before `NSApp.terminate` paths (e.g. backup restore). Every live
            // Coordinator flushes — no editorInstanceID filter, since we're about to die.
            let flushSerializationBeforeTerminate = NotificationCenter.default.addObserver(
                forName: .jotFlushEditorSerializationBeforeTerminate,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.flushPendingSerialization()
                }
            }

            observers = [
                windowKey,
                insertTodo, insertLink, convertToWebClip, insertFileLink, insertVoiceTranscript, insertImage, insertMap, applyTool, applyCommandMenuTool,
                applyNotePickerSelection, navigateNoteLink,
                performSearch, highlightSearch, clearSearch, replaceMatch, replaceAll,
                proofreadShow, proofreadClear, proofreadApply, captureSelection,
                editReplace, proofreadReplaceAll, textGenInsert,
                urlPasteMention, urlPasteSelectPlainLink, urlPasteSelectCard, urlPasteDismiss,
                codePasteSelectCodeBlock, codePasteSelectPlainText, codePasteDismissObserver,
                applyColor, removeColor, applyHighlight, removeHighlight, setHighlightRange,
                applyFontSize, applyFontFamily,
                settingsObserver, tintDidChangeObserver, syncMenuState, printNote, quickLookTrigger, quickLookHoverTrigger,
                fileExtractTrigger,
                flushSerializationBeforeNoteSwitch,
                flushSerializationBeforeTerminate,
            ]
        }

        @MainActor
        private func handlePrint() {
            guard let textView = self.textView,
                  let window = textView.window,
                  // Only print from the focused editor (prevents both editors
                  // printing simultaneously in split view)
                  window.firstResponder === textView else { return }

            guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else { return }
            printInfo.leftMargin = 72
            printInfo.rightMargin = 72
            printInfo.topMargin = 72
            printInfo.bottomMargin = 72
            printInfo.isHorizontallyCentered = false
            printInfo.isVerticallyCentered = false

            // Force light appearance for readable print output
            let savedAppearance = textView.appearance
            textView.appearance = NSAppearance(named: .aqua)

            let op = NSPrintOperation(view: textView, printInfo: printInfo)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            // runModal pins to a specific window -- avoids responder chain
            // validation that fails in non-document SwiftUI apps
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)

            textView.appearance = savedAppearance
        }

        // MARK: - Quick Look

        private struct QuickLookPreviewTarget {
            let url: URL
            let requiresSecurityScope: Bool
        }

        @MainActor
        private func triggerQuickLookForLinkAtCursor() {
            guard let textView = self.textView as? InlineNSTextView,
                  let textStorage = textView.textStorage,
                  let window = textView.window,
                  window.firstResponder === textView else { return }

            let loc = textView.selectedRange().location
            guard loc != NSNotFound, loc < textStorage.length else {
                NSSound.beep()
                return
            }

            guard let previewTarget = resolveQuickLookTarget(at: loc, in: textStorage) else {
                NSSound.beep()
                return
            }

            openQuickLookPreview(previewTarget, in: textView)
        }

        @MainActor
        private func triggerQuickLookForCharIndex(_ charIndex: Int) {
            guard let textView = self.textView as? InlineNSTextView,
                  let textStorage = textView.textStorage,
                  charIndex < textStorage.length else { return }

            guard let previewTarget = resolveQuickLookTarget(at: charIndex, in: textStorage) else {
                NSSound.beep()
                return
            }

            openQuickLookPreview(previewTarget, in: textView)
        }

        /// Extracts a file attachment from tag mode into an inline preview.
        @MainActor
        private func extractFileAtCharIndex(_ charIndex: Int) {
            guard let textView = self.textView,
                  let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  charIndex < textStorage.length else { return }

            var effectiveRange = NSRange(location: 0, length: 0)
            let att = textStorage.attribute(.attachment, at: charIndex, effectiveRange: &effectiveRange)

            if let fileAttachment = att as? NoteFileAttachment, fileAttachment.viewMode == .tag {
                // Stored file: switch view mode directly
                extractStoredFile(fileAttachment, range: effectiveRange, textView: textView,
                                  textStorage: textStorage, layoutManager: layoutManager)
            } else if let fileLinkAtt = att as? FileLinkAttachment {
                // File link: import into storage first, then extract
                extractFileLink(fileLinkAtt, range: effectiveRange, textView: textView,
                                textStorage: textStorage, layoutManager: layoutManager)
            }
        }

        @MainActor
        private func extractStoredFile(_ attachment: NoteFileAttachment, range: NSRange,
                                       textView: NSTextView, textStorage: NSTextStorage,
                                       layoutManager: NSLayoutManager) {
            // Preserve original file link data for tag reversion
            let origPath = attachment.originalFileLinkPath
            let origDisplayName = attachment.originalFileLinkDisplayName
            let origBookmark = attachment.originalFileLinkBookmark

            // Build a completely new attachment with correct cell sizing.
            // In-place mutation doesn't work: the layout manager caches the
            // old tag-cell metrics and won't re-query after property changes.
            // Replacement via replaceCharacters forces a full re-typeset --
            // the same pattern code blocks and extractFileLink use.
            let metadata = FileAttachmentMetadata(
                storedFilename: attachment.storedFilename,
                originalFilename: attachment.originalFilename,
                typeIdentifier: attachment.typeIdentifier,
                displayLabel: attachment.displayLabel,
                viewMode: .medium
            )
            let newAttStr = makeFileAttachment(metadata: metadata)

            if textView.shouldChangeText(in: range, replacementString: nil) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: range, with: newAttStr)
                textStorage.endEditing()
                textView.didChangeText()
                isUpdating = false
            }

            // Restore original file link data on the new NoteFileAttachment
            let insertedRange = NSRange(location: range.location, length: newAttStr.length)
            if insertedRange.location + insertedRange.length <= textStorage.length {
                textStorage.enumerateAttribute(.attachment, in: insertedRange, options: []) { val, _, stop in
                    if let fileAtt = val as? NoteFileAttachment {
                        fileAtt.originalFileLinkPath = origPath
                        fileAtt.originalFileLinkDisplayName = origDisplayName
                        fileAtt.originalFileLinkBookmark = origBookmark
                        stop.pointee = true
                    }
                }
            }

            syncText()
            updateFilePreviewOverlays(in: textView)
        }

        @MainActor
        private func extractFileLink(_ fileLinkAtt: FileLinkAttachment, range: NSRange,
                                     textView: NSTextView, textStorage: NSTextStorage,
                                     layoutManager: NSLayoutManager) {
            // Preserve original file link data for tag reversion
            let origPath = fileLinkAtt.filePath
            let origDisplayName = fileLinkAtt.displayName
            let origBookmark = fileLinkAtt.bookmarkBase64

            // Resolve the file URL (handle security-scoped bookmark)
            guard let resolvedURL = resolveFileLinkURL(
                path: origPath, bookmark: origBookmark
            ) else { return }

            // Import the file into JotFiles storage asynchronously
            Task { @MainActor in
                let accessed = resolvedURL.startAccessingSecurityScopedResource()
                defer { if accessed { resolvedURL.stopAccessingSecurityScopedResource() } }

                guard let storedFile = await FileAttachmentStorageManager.shared.saveFile(from: resolvedURL) else { return }

                let metadata = FileAttachmentMetadata(
                    storedFilename: storedFile.storedFilename,
                    originalFilename: storedFile.originalFilename,
                    typeIdentifier: storedFile.typeIdentifier,
                    displayLabel: AttachmentMarkup.displayLabel(for: storedFile),
                    viewMode: .medium
                )

                let newAttStr = self.makeFileAttachment(metadata: metadata)
                if textView.shouldChangeText(in: range, replacementString: nil) {
                    self.isUpdating = true
                    textStorage.beginEditing()
                    textStorage.replaceCharacters(in: range, with: newAttStr)
                    textStorage.endEditing()
                    textView.didChangeText()
                    self.isUpdating = false
                }

                // Set original file link data on the new NoteFileAttachment for tag reversion
                let insertedRange = NSRange(location: range.location, length: newAttStr.length)
                if insertedRange.location + insertedRange.length <= textStorage.length {
                    textStorage.enumerateAttribute(.attachment, in: insertedRange, options: []) { val, _, stop in
                        if let fileAtt = val as? NoteFileAttachment {
                            fileAtt.originalFileLinkPath = origPath
                            fileAtt.originalFileLinkDisplayName = origDisplayName
                            fileAtt.originalFileLinkBookmark = origBookmark
                            stop.pointee = true
                        }
                    }
                }

                self.syncText()
                if let tv = self.textView {
                    self.updateFilePreviewOverlays(in: tv)
                }
            }
        }

        /// Serializes the given note to a styled HTML temp file and returns its URL for QLPreviewPanel.
        @MainActor
        private func generateNotePreviewHTML(for note: Note) -> URL? {
            let html = NotePreviewHTMLGenerator.generate(note: note)
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("jot_note_preview_\(note.id.uuidString).html")
            do {
                try html.write(to: tempURL, atomically: true, encoding: .utf8)
                return tempURL
            } catch {
                return nil
            }
        }

        @MainActor
        private func openQuickLookPreview(_ previewTarget: QuickLookPreviewTarget, in textView: InlineNSTextView) {
            var stopAccessing: (() -> Void)?
            if previewTarget.requiresSecurityScope {
                guard previewTarget.url.startAccessingSecurityScopedResource() else {
                    NSSound.beep()
                    return
                }
                stopAccessing = { previewTarget.url.stopAccessingSecurityScopedResource() }
            }

            textView.setQuickLookPreview(url: previewTarget.url, stopAccessing: stopAccessing)
            QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
        }

        /// Examines text attributes at the given character index and returns a Quick Look-compatible file URL.
        /// For web URLs, creates a temporary `.webloc` file so QLPreviewPanel can render the page.
        @MainActor
        private func resolveQuickLookTarget(at charIndex: Int, in textStorage: NSTextStorage) -> QuickLookPreviewTarget? {
            let attrs = textStorage.attributes(at: charIndex, effectiveRange: nil)

            // 1. File link with security-scoped bookmark
            if let fileLinkAttachment = attrs[.attachment] as? FileLinkAttachment {
                return resolveFileLinkPreviewTarget(
                    path: fileLinkAttachment.filePath,
                    bookmark: fileLinkAttachment.bookmarkBase64
                )
            }
            if let filePath = attrs[.fileLinkPath] as? String {
                let bookmark = (attrs[.fileLinkBookmark] as? String) ?? ""
                return resolveFileLinkPreviewTarget(path: filePath, bookmark: bookmark)
            }

            // 2. Stored file attachment
            if let storedFilename = attrs[.fileStoredFilename] as? String,
               let fileURL = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) {
                return QuickLookPreviewTarget(url: fileURL, requiresSecurityScope: false)
            }

            // Note mention — serialize note content to a temp HTML file
            if let idStr = attrs[.notelinkID] as? String,
               let noteID = UUID(uuidString: idStr),
               let note = fetchNote?(noteID) {
                guard let previewURL = generateNotePreviewHTML(for: note) else { return nil }
                return QuickLookPreviewTarget(url: previewURL, requiresSecurityScope: false)
            }

            // 3. Web clip URL
            if attrs[.webClipTitle] != nil,
               let linkStr = Self.linkURLString(from: attrs),
               let webURL = URL(string: linkStr) {
                guard let previewURL = createWeblocFile(for: webURL) else { return nil }
                return QuickLookPreviewTarget(url: previewURL, requiresSecurityScope: false)
            }

            // 3b. Link card URL
            if let linkCard = attrs[.attachment] as? NoteLinkCardAttachment,
               let webURL = URL(string: linkCard.url) {
                guard let previewURL = createWeblocFile(for: webURL) else { return nil }
                return QuickLookPreviewTarget(url: previewURL, requiresSecurityScope: false)
            }

            // 4. Plain link URL
            if let linkStr = attrs[.plainLinkURL] as? String,
               let webURL = URL(string: linkStr) {
                guard let previewURL = createWeblocFile(for: webURL) else { return nil }
                return QuickLookPreviewTarget(url: previewURL, requiresSecurityScope: false)
            }

            // 5. Standard .link attribute (bare link text)
            if let url = attrs[.link] as? URL {
                if url.isFileURL {
                    return QuickLookPreviewTarget(url: url, requiresSecurityScope: false)
                }
                guard let previewURL = createWeblocFile(for: url) else { return nil }
                return QuickLookPreviewTarget(url: previewURL, requiresSecurityScope: false)
            }
            if let linkStr = attrs[.link] as? String, let url = URL(string: linkStr) {
                if url.isFileURL {
                    return QuickLookPreviewTarget(url: url, requiresSecurityScope: false)
                }
                guard let previewURL = createWeblocFile(for: url) else { return nil }
                return QuickLookPreviewTarget(url: previewURL, requiresSecurityScope: false)
            }

            return nil
        }

        private func resolveFileLinkPreviewTarget(path: String, bookmark: String) -> QuickLookPreviewTarget? {
            if !bookmark.isEmpty, let data = Data(base64Encoded: bookmark) {
                var isStale = false
                if let resolvedURL = try? URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    return QuickLookPreviewTarget(url: resolvedURL, requiresSecurityScope: true)
                }
            }

            guard let resolvedURL = resolveFileLinkURL(path: path, bookmark: "") else { return nil }
            return QuickLookPreviewTarget(url: resolvedURL, requiresSecurityScope: false)
        }

        private func resolveFileLinkURL(path: String, bookmark: String) -> URL? {
            if !bookmark.isEmpty, let data = Data(base64Encoded: bookmark) {
                var isStale = false
                if let resolved = try? URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    return resolved
                }
            }
            let fileURL = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: path) ? fileURL : nil
        }

        private func createWeblocFile(for url: URL) -> URL? {
            let tempDir = FileManager.default.temporaryDirectory
            let safeName = (url.host ?? "preview").replacingOccurrences(of: "/", with: "_")
            let fileURL = tempDir.appendingPathComponent("\(safeName).webloc")
            let plist: [String: Any] = ["URL": url.absoluteString]
            guard let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            ) else { return nil }
            try? data.write(to: fileURL, options: .atomic)
            return fileURL
        }

        private func applyEditorSettings() {
            guard let textView = self.textView else { return }
            let defaults = UserDefaults.standard
            textView.isAutomaticQuoteSubstitutionEnabled = defaults.bool(forKey: ThemeManager.smartQuotesKey)
            textView.isAutomaticDashSubstitutionEnabled = defaults.bool(forKey: ThemeManager.smartDashesKey)
            textView.isContinuousSpellCheckingEnabled = defaults.bool(forKey: ThemeManager.spellCheckKey)
            textView.isAutomaticSpellingCorrectionEnabled = defaults.bool(forKey: ThemeManager.autocorrectKey)

            // Update typing attributes with current font + paragraph style
            let newBaseStyle = Self.baseParagraphStyle()
            textView.defaultParagraphStyle = newBaseStyle
            textView.typingAttributes = Self.baseTypingAttributes(for: nil)

            // Re-apply font size to existing body text (skip headings)
            let bodySize = ThemeManager.currentBodyFontSize()
            let headingSizes: Set<CGFloat> = [
                TextFormattingManager.HeadingLevel.h1.fontSize,
                TextFormattingManager.HeadingLevel.h2.fontSize,
                TextFormattingManager.HeadingLevel.h3.fontSize,
            ]
            if let storage = textView.textStorage {
                storage.beginEditing()
                storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
                    guard let font = value as? NSFont else { return }
                    if headingSizes.contains(font.pointSize) { return }
                    let updated = FontManager.bodyNS(size: bodySize, weight: font.fontDescriptor.symbolicTraits.contains(.bold) ? .bold : .regular)
                    // Preserve italic trait
                    let finalFont: NSFont
                    if font.fontDescriptor.symbolicTraits.contains(.italic) {
                        finalFont = NSFontManager.shared.convert(updated, toHaveTrait: .italicFontMask)
                    } else {
                        finalFont = updated
                    }
                    storage.addAttribute(.font, value: finalFont, range: range)
                }
                storage.endEditing()
            }

            // Re-apply paragraph styles to all existing text
            styleTodoParagraphs()

            // Force layout + redraw
            if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                layoutManager.ensureLayout(for: container)
            }
            textView.needsDisplay = true
        }

        /// Registers a bounds-change observer on the text view's clip view so
        /// overlays are repositioned on scroll. Safe to call multiple times — it
        /// no-ops when the observer is already registered or the scroll view is
        /// not yet available (will be retried from completeDeferredSetup).
        private func registerBoundsObserverIfNeeded(for textView: NSTextView) {
            guard !hasBoundsObserver,
                  let clipView = textView.enclosingScrollView?.contentView else { return }
            hasBoundsObserver = true
            clipView.postsBoundsChangedNotifications = true
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleOverlayUpdate()
                }
            }
            observers.append(observer)
        }

        /// Registers a frame-change observer on the enclosing scroll view so
        /// overlays resize when the container width changes (e.g. split view).
        /// boundsDidChangeNotification only fires on scroll — this catches
        /// actual frame/size changes from SwiftUI layout.
        private func registerFrameObserverIfNeeded(for textView: NSTextView) {
            guard !hasFrameObserver,
                  let scrollView = textView.enclosingScrollView else { return }
            hasFrameObserver = true
            scrollView.postsFrameChangedNotifications = true
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, let tv = self.textView else { return }
                    // Sync container width with the text view's actual frame
                    // (widthTracksTextView may not fire after replaceLayoutManager)
                    if let container = tv.textContainer {
                        let width = tv.bounds.width - tv.textContainerInset.width * 2
                        if width > 0 && abs(container.containerSize.width - width) > 0.5 {
                            container.containerSize = NSSize(
                                width: width,
                                height: CGFloat.greatestFiniteMagnitude)
                            tv.layoutManager?.ensureLayout(for: container)
                        }
                    }
                    self.lastKnownTextViewWidth = tv.bounds.width
                    self.scheduleOverlayUpdate()
                }
            }
            observers.append(observer)
        }

        /// Re-render pill attachments when the display's backing scale changes
        /// (e.g. window moved between Retina and non-Retina displays).
        private func registerDisplayScaleObserver() {
            let observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rerenderPillAttachments()
                }
            }
            observers.append(observer)
        }

        /// Called from updateNSView once the view is in the hierarchy.
        /// Completes any overlay work that was deferred during makeNSView.
        func completeDeferredSetup(in textView: NSTextView) {
            // Finish bounds-observer registration if configure() ran before
            // the view had an enclosingScrollView.
            if !hasBoundsObserver {
                registerBoundsObserverIfNeeded(for: textView)
            }
            if !hasFrameObserver {
                registerFrameObserverIfNeeded(for: textView)
            }

            // Disable layer clipping on the text view and hosting ancestors so block overlays
            // (tables, cards, callouts) can extend past the text column. Previously the loop
            // bailed on `NSClipView` without changing it, so the scroll document stayed hard-clipped
            // horizontally — wide tables looked "boxed" with a sharp right edge.
            if !hasDisabledAncestorClipping {
                hasDisabledAncestorClipping = true
                textView.clipsToBounds = false
                var ancestor: NSView? = textView.superview
                for _ in 0..<24 {
                    guard let view = ancestor else { break }
                    if view is NSWindow { break }
                    if view is NSScrollView { break }
                    if view is NSClipView {
                        view.clipsToBounds = false
                        if view.wantsLayer, let layer = view.layer {
                            layer.masksToBounds = false
                        }
                        break
                    }
                    view.clipsToBounds = false
                    if view.wantsLayer, let layer = view.layer {
                        layer.masksToBounds = false
                    }
                    ancestor = view.superview
                }
                // Some hierarchies wrap the document view so the clip view is not the first
                // superview; always relax the enclosing scroll view's content clip if present.
                if let clip = textView.enclosingScrollView?.contentView {
                    clip.clipsToBounds = false
                    if clip.wantsLayer, let layer = clip.layer {
                        layer.masksToBounds = false
                    }
                }
            }

            // Ensure overlay host is the text view (may still be nil from
            // initial configure if called before the view was in hierarchy).
            if overlayHostView !== textView {
                needsDeferredOverlaySetup = true
            }

            // If applyInitialText couldn't create overlays, do it now.
            if needsDeferredOverlaySetup {
                needsDeferredOverlaySetup = false
                performSynchronizedOverlayLayoutPass(in: textView)
            }
        }

        // MARK: - Proofread Overlay Helpers

        nonisolated static func validatedProofreadScope(
            _ candidateRange: NSRange?,
            in fullString: NSString
        ) -> NSRange? {
            guard let candidateRange else { return nil }
            guard candidateRange.location != NSNotFound else { return nil }
            guard candidateRange.length > 0 else { return nil }
            guard NSMaxRange(candidateRange) <= fullString.length else { return nil }
            return candidateRange
        }

        private nonisolated static func proofreadRangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
            NSIntersectionRange(lhs, rhs).length > 0
        }

        private nonisolated static func firstUnconsumedProofreadMatch(
            of original: String,
            in fullString: NSString,
            scope: NSRange,
            usedRanges: [NSRange],
            caseInsensitive: Bool
        ) -> NSRange? {
            let options: NSString.CompareOptions = caseInsensitive ? [.literal, .caseInsensitive] : .literal
            let scopeEnd = NSMaxRange(scope)
            var searchLocation = scope.location

            while searchLocation < scopeEnd {
                let searchRange = NSRange(location: searchLocation, length: scopeEnd - searchLocation)
                let found = fullString.range(of: original, options: options, range: searchRange)
                guard found.location != NSNotFound else { return nil }
                if !usedRanges.contains(where: { Self.proofreadRangesOverlap($0, found) }) {
                    return found
                }
                searchLocation = max(found.location + max(found.length, 1), searchLocation + 1)
            }

            return nil
        }

        nonisolated static func resolveProofreadAnnotations(
            in fullString: NSString,
            suggestions: [ProofreadSuggestion],
            scope: NSRange
        ) -> [ProofreadAnnotation] {
            guard let validatedScope = validatedProofreadScope(scope, in: fullString) else { return [] }

            var usedRanges: [NSRange] = []
            var resolved: [ProofreadAnnotation] = []

            for suggestion in suggestions {
                let found =
                    firstUnconsumedProofreadMatch(
                        of: suggestion.original,
                        in: fullString,
                        scope: validatedScope,
                        usedRanges: usedRanges,
                        caseInsensitive: false
                    )
                    ?? firstUnconsumedProofreadMatch(
                        of: suggestion.original,
                        in: fullString,
                        scope: validatedScope,
                        usedRanges: usedRanges,
                        caseInsensitive: true
                    )

                guard let found else { continue }
                usedRanges.append(found)
                resolved.append(
                    ProofreadAnnotation(
                        original: fullString.substring(with: found),
                        replacement: suggestion.replacement,
                        range: found
                    )
                )
            }

            return resolved.sorted {
                if $0.range.location == $1.range.location {
                    return $0.range.length < $1.range.length
                }
                return $0.range.location < $1.range.location
            }
        }

        private nonisolated static func derivedProofreadScope(
            from annotations: [ProofreadAnnotation],
            fullLength: Int
        ) -> NSRange? {
            guard let first = annotations.min(by: { $0.range.location < $1.range.location }),
                  let last = annotations.max(by: { NSMaxRange($0.range) < NSMaxRange($1.range) }) else {
                return nil
            }
            let location = first.range.location
            let upperBound = min(NSMaxRange(last.range), fullLength)
            guard upperBound > location else { return nil }
            return NSRange(location: location, length: upperBound - location)
        }

        nonisolated static func validProofreadAnnotationsForReplacement(
            in fullString: NSString,
            annotations: [ProofreadAnnotation]
        ) -> [ProofreadAnnotation] {
            annotations
                .filter { annotation in
                    resolvedAIReplacementRange(
                        in: fullString,
                        original: annotation.original,
                        originalRange: annotation.range
                    ) != nil
                }
                .sorted {
                    if $0.range.location == $1.range.location {
                        return $0.range.length > $1.range.length
                    }
                    return $0.range.location > $1.range.location
                }
        }

        private func applyProofreadAnnotations(
            _ annotations: [ProofreadAnnotation],
            activeIndex: Int = 0,
            scopeRange: NSRange? = nil
        ) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            clearProofreadOverlays(resetScope: false)

            let fullString = storage.string as NSString

            let resolved = annotations.filter { annotation in
                Self.resolvedAIReplacementRange(
                    in: fullString,
                    original: annotation.original,
                    originalRange: annotation.range
                ) != nil
            }

            if let explicitScope = Self.validatedProofreadScope(scopeRange, in: fullString) {
                proofreadScopeRange = explicitScope
            } else if Self.validatedProofreadScope(proofreadScopeRange, in: fullString) == nil {
                proofreadScopeRange =
                    Self.derivedProofreadScope(from: resolved, fullLength: storage.length)
                    ?? NSRange(location: 0, length: storage.length)
            }

            let isDark = currentColorScheme == .dark
            let dimColor: NSColor = (isDark ? NSColor.white : NSColor.black)
                .withAlphaComponent(isDark ? 0.4 : 0.25)

            let dimRange =
                Self.validatedProofreadScope(proofreadScopeRange, in: fullString)
                ?? NSRange(location: 0, length: storage.length)
            let clampedIndex = resolved.isEmpty ? 0 : min(activeIndex, resolved.count - 1)

            guard let layoutManager = textView.layoutManager else { return }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: dimColor, forCharacterRange: dimRange)
            if !resolved.isEmpty {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: resolved[clampedIndex].range)
            }

            // Track all resolved ranges
            for item in resolved {
                proofreadHighlightedRanges.append(item.range)
            }

            // Scroll the active annotation into view
            if !resolved.isEmpty {
                textView.scrollRangeToVisible(resolved[clampedIndex].range)
            }
        }

        private func clearProofreadOverlays(resetScope: Bool = true) {
            guard let textView = self.textView,
                  let layoutManager = textView.layoutManager,
                  let storage = textView.textStorage else {
                proofreadPillViews.forEach { $0.view.removeFromSuperview() }
                proofreadPillViews.removeAll()
                proofreadHighlightedRanges.removeAll()
                if resetScope {
                    proofreadScopeRange = NSRange(location: NSNotFound, length: 0)
                }
                return
            }

            // Remove pill views
            proofreadPillViews.forEach { $0.view.removeFromSuperview() }
            proofreadPillViews.removeAll()

            // Remove temporary dim overlay — original storage colors are untouched
            if storage.length > 0 {
                let fullRange = NSRange(location: 0, length: storage.length)
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            }
            proofreadHighlightedRanges.removeAll()
            if resetScope {
                proofreadScopeRange = NSRange(location: NSNotFound, length: 0)
            }
        }

        private func applyProofreadSuggestion(
            original: String,
            replacement: String,
            originalRange: NSRange?
        ) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            let fullString = storage.string as NSString
            let found: NSRange
            if let resolvedRange = Self.resolvedAIReplacementRange(
                in: fullString,
                original: original,
                originalRange: originalRange
            ) {
                found = resolvedRange
            } else {
                // Preserve the legacy path for callers that do not yet send `originalRange`.
                let cursorLoc = textView.selectedRange().location
                var fallback = fullString.range(
                    of: original,
                    options: .literal,
                    range: NSRange(location: cursorLoc, length: fullString.length - cursorLoc)
                )
                if fallback.location == NSNotFound {
                    fallback = fullString.range(
                        of: original,
                        options: .literal,
                        range: NSRange(location: 0, length: fullString.length)
                    )
                }
                found = fallback
            }
            guard found.location != NSNotFound else {
                clearProofreadOverlays()
                return
            }

            if textView.shouldChangeText(in: found, replacementString: replacement) {
                storage.replaceCharacters(in: found, with: replacement)
                textView.didChangeText()
            }
            syncText()
            var clearInfo: [String: Any] = [:]
            if let eid = editorInstanceID { clearInfo["editorInstanceID"] = eid }
            NotificationCenter.default.post(name: .aiProofreadClearOverlays, object: nil, userInfo: clearInfo.isEmpty ? nil : clearInfo)
        }

        // MARK: - Edit Content Replacement (via notification)

        nonisolated static func resolvedAIReplacementRange(
            in fullString: NSString,
            original: String,
            originalRange: NSRange?
        ) -> NSRange? {
            guard let originalRange else { return nil }
            guard originalRange.location != NSNotFound else { return nil }
            guard originalRange.length > 0 else { return nil }
            guard NSMaxRange(originalRange) <= fullString.length else { return nil }
            guard fullString.substring(with: originalRange) == original else { return nil }
            return originalRange
        }

        private func applyEditContentReplacement(
            original: String,
            replacement: String,
            originalRange: NSRange?
        ) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            isUpdating = true
            defer {
                isUpdating = false
                NSAnimationContext.endGrouping()
                syncText()
            }

            if original.isEmpty {
                // Full-document replacement
                let fullRange = NSRange(location: 0, length: storage.length)
                if textView.shouldChangeText(in: fullRange, replacementString: replacement) {
                    storage.beginEditing()
                    storage.replaceCharacters(in: fullRange, with: replacement)
                    storage.endEditing()
                    textView.didChangeText()
                }
            } else {
                let fullString = storage.string as NSString
                guard let found = Self.resolvedAIReplacementRange(
                    in: fullString,
                    original: original,
                    originalRange: originalRange
                ) else { return }

                if textView.shouldChangeText(in: found, replacementString: replacement) {
                    storage.beginEditing()
                    storage.replaceCharacters(in: found, with: replacement)
                    storage.endEditing()
                    textView.didChangeText()
                }
            }
        }

        // MARK: - Batch Proofread Replace All (via notification)

        private func replaceAllProofreadSuggestions(_ annotations: [ProofreadAnnotation]) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            let fullString = storage.string as NSString
            let resolved = Self.validProofreadAnnotationsForReplacement(
                in: fullString,
                annotations: annotations
            )

            guard !resolved.isEmpty else { return }

            textView.undoManager?.beginUndoGrouping()
            for annotation in resolved {
                let ns = storage.string as NSString
                guard let range = Self.resolvedAIReplacementRange(
                    in: ns,
                    original: annotation.original,
                    originalRange: annotation.range
                ) else { continue }
                if textView.shouldChangeText(in: range, replacementString: annotation.replacement) {
                    storage.replaceCharacters(in: range, with: annotation.replacement)
                    textView.didChangeText()
                }
            }
            textView.undoManager?.endUndoGrouping()
            syncText()

            clearProofreadOverlays()
        }

        // MARK: - Edit Content Selection Capture

        private func captureSelectionForEditContent() {
            // Clicking the AI tools button clears the text view selection before this fires,
            // so we use the last cached non-empty selection rather than reading the live selection.
            var baseInfo: [String: Any] = [:]
            if let eid = editorInstanceID { baseInfo["editorInstanceID"] = eid }

            guard lastKnownSelectionRange.length > 0 else {
                // For zero-length selections (cursor), compute the cursor rect so
                // overlays (e.g. text-gen shimmer) can position at the insertion point.
                var cursorWindowRect = CGRect.zero
                if let textView = self.textView,
                   let layoutManager = textView.layoutManager,
                   textView.textContainer != nil {
                    let insertionPoint = textView.selectedRange().location
                    if insertionPoint != NSNotFound && insertionPoint <= (textView.string as NSString).length {
                        let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(insertionPoint, max((textView.string as NSString).length - 1, 0)))
                        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                        let cursorRect = CGRect(
                            x: lineRect.origin.x + textView.textContainerOrigin.x,
                            y: lineRect.origin.y + textView.textContainerOrigin.y,
                            width: lineRect.width,
                            height: lineRect.height
                        )
                        cursorWindowRect = textView.convert(cursorRect, to: nil)
                    }
                }
                var info = baseInfo
                info["nsRange"] = NSRange(location: textView?.selectedRange().location ?? NSNotFound, length: 0)
                info["selectedText"] = ""
                info["windowRect"] = cursorWindowRect
                NotificationCenter.default.post(
                    name: .aiEditCaptureSelection,
                    object: nil,
                    userInfo: info
                )
                return
            }

            var info = baseInfo
            info["nsRange"] = lastKnownSelectionRange
            info["selectedText"] = lastKnownSelectionText
            info["windowRect"] = lastKnownSelectionWindowRect
            NotificationCenter.default.post(
                name: .aiEditCaptureSelection,
                object: nil,
                userInfo: info
            )
        }

        // MARK: - Search Replace

        /// Replace a single search match at the given index in the text storage.
        func replaceSearchMatch(query: String, replacement: String, matchIndex: Int) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            // Find all matches in the text storage (not editedContent) to get correct ranges
            let fullString = storage.string as NSString
            var ranges: [NSRange] = []
            var searchRange = NSRange(location: 0, length: fullString.length)
            while searchRange.location < fullString.length {
                let found = fullString.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }
                ranges.append(found)
                searchRange.location = found.location + found.length
                searchRange.length = fullString.length - searchRange.location
            }

            guard matchIndex >= 0, matchIndex < ranges.count else { return }
            let targetRange = ranges[matchIndex]

            if textView.shouldChangeText(in: targetRange, replacementString: replacement) {
                storage.replaceCharacters(in: targetRange, with: replacement)
                textView.didChangeText()
            }
            syncText()
        }

        /// Replace all occurrences of query with replacement in a single undo group.
        func replaceAllSearchMatches(query: String, replacement: String) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            let fullString = storage.string as NSString
            var ranges: [NSRange] = []
            var searchRange = NSRange(location: 0, length: fullString.length)
            while searchRange.location < fullString.length {
                let found = fullString.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }
                ranges.append(found)
                searchRange.location = found.location + found.length
                searchRange.length = fullString.length - searchRange.location
            }

            guard !ranges.isEmpty else { return }

            // Replace in reverse order to preserve earlier range positions
            textView.undoManager?.beginUndoGrouping()
            for range in ranges.reversed() {
                if textView.shouldChangeText(in: range, replacementString: replacement) {
                    storage.replaceCharacters(in: range, with: replacement)
                    textView.didChangeText()
                }
            }
            textView.undoManager?.endUndoGrouping()
            syncText()
        }

        // MARK: - Search Highlighting

        func performAndReportSearch(query: String) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }
            let text = storage.string as NSString
            var ranges: [NSRange] = []
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.location < text.length {
                let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }
                ranges.append(found)
                searchRange.location = found.location + found.length
                searchRange.length = text.length - searchRange.location
            }
            applySearchHighlighting(ranges: ranges, activeIndex: 0)
            var info: [String: Any] = ["ranges": ranges, "matchCount": ranges.count]
            if let eid = editorInstanceID { info["editorInstanceID"] = eid }
            NotificationCenter.default.post(name: .searchOnPageResults, object: nil, userInfo: info)
        }

        private var searchImpulseView: NSView?

        func applySearchHighlighting(ranges: [NSRange], activeIndex: Int) {
            guard let textView = self.textView,
                  let layoutManager = textView.layoutManager,
                  let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return }

            // Clear any previous temporary highlighting
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

            // Dim non-matched text with a single full-range pass
            let dimColor: NSColor = (currentColorScheme == .dark)
                ? NSColor.white.withAlphaComponent(0.4)
                : NSColor.black.withAlphaComponent(0.3)
            layoutManager.addTemporaryAttribute(.foregroundColor, value: dimColor, forCharacterRange: fullRange)

            // Un-dim matched ranges so original foreground colors show through
            for matchRange in ranges {
                guard matchRange.location + matchRange.length <= storage.length else { continue }
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: matchRange)
            }

            // Scroll active match into view and play impulse
            if activeIndex >= 0 && activeIndex < ranges.count {
                if let textContainer = textView.textContainer {
                    layoutManager.ensureLayout(for: textContainer)
                }
                textView.scrollRangeToVisible(ranges[activeIndex])
                playMatchGlow(for: ranges[activeIndex])
            }
        }

        func clearSearchHighlighting() {
            guard let textView = self.textView,
                  let layoutManager = textView.layoutManager,
                  let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return }

            // Remove any lingering impulse view
            searchImpulseView?.removeFromSuperview()
            searchImpulseView = nil

            // Remove temporary search overlays — original storage colors are untouched
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        }

        private func playMatchGlow(for range: NSRange) {
            guard let textView = self.textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            // Remove previous glow
            searchImpulseView?.removeFromSuperview()
            searchImpulseView = nil

            // Get the glyph rect for the matched range
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var matchRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            // Offset for text container inset
            let origin = textView.textContainerOrigin
            matchRect.origin.x += origin.x
            matchRect.origin.y += origin.y

            // Pad for diffuse glow breathing room
            let padding: CGFloat = 10
            matchRect = matchRect.insetBy(dx: -padding, dy: -padding)

            // Determine glow color based on appearance
            let isDark: Bool = {
                let appearance = textView.window?.effectiveAppearance ?? textView.effectiveAppearance
                if let match = appearance.bestMatch(from: [.darkAqua, .aqua]) {
                    return match == .darkAqua
                }
                return true
            }()
            let glowColor = isDark
                ? NSColor(white: 1.0, alpha: 0.45)
                : NSColor(white: 0.0, alpha: 0.50)

            // -- Outer Glow View (no visible background) --
            let glowView = NSView(frame: matchRect)
            glowView.wantsLayer = true
            guard let glowLayer = glowView.layer else { return }

            // No background -- the glow is purely the shadow cast from shadowPath
            glowLayer.backgroundColor = NSColor.clear.cgColor
            glowLayer.shadowPath = CGPath(
                roundedRect: CGRect(origin: .zero, size: matchRect.size),
                cornerWidth: 3, cornerHeight: 3, transform: nil
            )
            glowLayer.shadowColor = glowColor.cgColor
            glowLayer.shadowOffset = .zero
            glowLayer.shadowRadius = 0
            glowLayer.shadowOpacity = 0

            textView.addSubview(glowView)
            searchImpulseView = glowView

            // -- Layer 2: Sparkle Emitter --
            let emitter = CAEmitterLayer()
            emitter.emitterPosition = CGPoint(x: matchRect.width / 2, y: matchRect.height / 2)
            emitter.emitterSize = CGSize(width: matchRect.width, height: 1)
            emitter.emitterShape = .line
            emitter.renderMode = .additive

            let sparkleCell = CAEmitterCell()
            sparkleCell.contents = {
                let size: CGFloat = 4
                let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                    let path = NSBezierPath(ovalIn: rect)
                    NSColor.white.setFill()
                    path.fill()
                    return true
                }
                return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }()
            sparkleCell.birthRate = 40
            sparkleCell.lifetime = 0.5
            sparkleCell.lifetimeRange = 0.15
            sparkleCell.velocity = 20
            sparkleCell.velocityRange = 10
            sparkleCell.emissionRange = .pi * 2
            sparkleCell.scale = 0.4
            sparkleCell.scaleRange = 0.2
            sparkleCell.scaleSpeed = -0.3
            sparkleCell.alphaSpeed = -1.5
            sparkleCell.color = glowColor.withAlphaComponent(0.8).cgColor

            emitter.emitterCells = [sparkleCell]
            glowLayer.addSublayer(emitter)

            // -- Animations --
            // Shadow radius: 0 -> 20 -> 0 (wide feathered bloom, no hard edge)
            let radiusAnim = CAKeyframeAnimation(keyPath: "shadowRadius")
            radiusAnim.values = [0, 20, 0]
            radiusAnim.keyTimes = [0, 0.33, 1.0]
            radiusAnim.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn)
            ]
            radiusAnim.duration = 0.6

            // Shadow opacity: 0 -> 0.45 -> 0
            let opacityAnim = CAKeyframeAnimation(keyPath: "shadowOpacity")
            opacityAnim.values = [0, 0.45, 0]
            opacityAnim.keyTimes = [0, 0.33, 1.0]
            opacityAnim.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn)
            ]
            opacityAnim.duration = 0.6

            // Stop emitting after brief burst, let existing particles fade
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                emitter.birthRate = 0
            }

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                // Allow sparkle particles to finish their lifetime before removal
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Task { @MainActor [weak self] in
                        // Only remove if this is still the current glow view
                        if self?.searchImpulseView === glowView {
                            glowView.removeFromSuperview()
                            self?.searchImpulseView = nil
                        }
                    }
                }
            }
            glowLayer.add(radiusAnim, forKey: "glowRadius")
            glowLayer.add(opacityAnim, forKey: "glowOpacity")
            CATransaction.commit()
        }

        func requestFocusIfNeeded(_ focusRequestID: UUID?) {
            guard let focusRequestID else { return }
            guard lastHandledFocusRequestID != focusRequestID else { return }
            lastHandledFocusRequestID = focusRequestID
            guard let textView else { return }

            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                let endPosition = textView.string.utf16.count
                textView.setSelectedRange(NSRange(location: endPosition, length: 0))
            }
        }

        func canHandleFileDrop(_ info: NSDraggingInfo, in textView: NSTextView) -> Bool {
            guard let urls = fileURLs(from: info), !urls.isEmpty else {
                return false
            }
            // CSV files are handled inline as tables. Other importable note
            // formats (PDF, Markdown, etc.) go through NoteImportService.
            let hasNonCSVImportable = urls.contains { url in
                guard let format = NoteImportFormat.from(url: url) else { return false }
                return format != .csv
            }
            return !hasNonCSVImportable
        }

        func handleFileDrop(_ info: NSDraggingInfo, in textView: NSTextView) -> Bool {
            guard let urls = fileURLs(from: info), !urls.isEmpty else {
                return false
            }
            processDroppedURLs(urls)
            return true
        }

        private func fileURLs(from info: NSDraggingInfo) -> [URL]? {
            let classes: [AnyClass] = [NSURL.self]
            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true
            ]
            guard let objects = info.draggingPasteboard.readObjects(
                forClasses: classes,
                options: options
            ) as? [URL] else {
                return nil
            }
            return objects
        }

        private func processDroppedURLs(_ urls: [URL]) {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                for url in urls {
                    await self.ingestDroppedURL(url)
                }
            }
        }

        private func ingestDroppedURL(_ url: URL) async {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if isImageURL(url) {
                if let filename = await ImageStorageManager.shared.saveImage(from: url) {
                    insertImage(filename: filename)
                    return
                }
            }

            // CSV files → inline table conversion
            if url.pathExtension.lowercased() == "csv" {
                if let tableData = tableDataFromCSV(at: url) {
                    insertTable(with: tableData)
                    return
                }
            }

            if let storedFile = await FileAttachmentStorageManager.shared.saveFile(from: url) {
                insertFileAttachment(using: storedFile)
                return
            }

        }

        /// Parse a CSV file into NoteTableData for inline table insertion.
        private func tableDataFromCSV(at url: URL) -> NoteTableData? {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let rows = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard !rows.isEmpty else { return nil }

            let parsedRows = rows.map { NoteImportService.parseCSVRow($0) }
            let maxColumns = parsedRows.map { $0.count }.max() ?? 1
            let normalizedRows = parsedRows.map { row in
                row + Array(repeating: "", count: max(0, maxColumns - row.count))
            }
            let widths = Array(repeating: NoteTableData.defaultColumnWidth, count: maxColumns)
            return NoteTableData(columns: maxColumns, cells: normalizedRows, columnWidths: widths)
        }

        private func isImageURL(_ url: URL) -> Bool {
            if let values = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
               let identifier = values.typeIdentifier {
                if #available(macOS 11.0, *) {
                    if let type = UTType(identifier) {
                        return type.conforms(to: .image)
                    }
                }
            }

            let ext = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif"].contains(
                ext
            )
        }

        func handleAttachmentClick(at point: CGPoint, in textView: NSTextView) -> Bool {
            guard let layoutManager = textView.layoutManager,
                let textStorage = textView.textStorage,
                let textContainer = textView.textContainer
            else { return false }

            // Use text container coordinates directly to avoid textContainerOrigin issues
            let pointInContainer = CGPoint(
                x: point.x - textView.textContainerOrigin.x,
                y: point.y - textView.textContainerOrigin.y)

            let glyphIndex = layoutManager.glyphIndex(for: pointInContainer, in: textContainer)
            if glyphIndex >= layoutManager.numberOfGlyphs { return false }

            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            guard charIndex < textStorage.length else { return false }

            let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
            guard let attachment = attributes[.attachment] as? NSTextAttachment else {
                return false
            }

            enum AttachmentAction {
                case webClip(url: URL)
                case file(url: URL)
                case fileLink(path: String, bookmark: String)
            }

            let action: AttachmentAction?
            if let fileAtt = attachment as? NoteFileAttachment, fileAtt.viewMode != .tag {
                // Extracted file preview -- overlay handles interaction, don't open on click
                action = nil
            } else if let fileLinkAttachment = attachment as? FileLinkAttachment {
                action = .fileLink(path: fileLinkAttachment.filePath, bookmark: fileLinkAttachment.bookmarkBase64)
            } else if let filePath = attributes[.fileLinkPath] as? String {
                let bookmark = (attributes[.fileLinkBookmark] as? String) ?? ""
                action = .fileLink(path: filePath, bookmark: bookmark)
            } else if let storedFilename = attributes[.fileStoredFilename] as? String,
               let fileURL = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) {
                action = .file(url: fileURL)
            } else if attributes[.webClipTitle] != nil,
                      let linkValue = Self.linkURLString(from: attributes),
                      let url = URL(string: linkValue) {
                action = .webClip(url: url)
            } else if let linkCard = attributes[.attachment] as? NoteLinkCardAttachment,
                      let url = URL(string: linkCard.url) {
                action = .webClip(url: url)
            } else if let linkValue = attributes[.plainLinkURL] as? String,
                      let url = URL(string: linkValue) {
                action = .webClip(url: url)
            } else {
                action = nil
            }

            guard let action else { return false }

            // Get the actual glyph bounding rect for the attachment character
            // This gives us the EXACT position where the attachment is drawn
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

            // The attachment's actual visual rect is the glyph rect (which respects bounds.origin)
            // plus the attachment's size
            let attachmentRect = CGRect(
                origin: glyphRect.origin,
                size: attachment.bounds.size
            ).integral

            // Only handle clicks within the actual visible attachment area
            guard attachmentRect.contains(pointInContainer) else { return false }

            switch action {
            case let .webClip(url):
                NSWorkspace.shared.open(url)
                return true
            case let .file(url):
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
                return true
            case let .fileLink(path, bookmark):
                // Try security-scoped bookmark first (required for sandboxed apps)
                if !bookmark.isEmpty,
                   let bookmarkData = Data(base64Encoded: bookmark) {
                    var isStale = false
                    if let resolvedURL = try? URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    ) {
                        let accessed = resolvedURL.startAccessingSecurityScopedResource()
                        guard accessed else {
                            Self.promptRelink(originalPath: path, textView: textView, charIndex: charIndex)
                            return true
                        }

                        // Refresh stale bookmark while we still have access
                        if isStale {
                            Self.refreshFileLinkBookmark(resolvedURL, textView: textView, charIndex: charIndex)
                        }

                        // Use async open so security scope stays active until handoff completes
                        let config = NSWorkspace.OpenConfiguration()
                        NSWorkspace.shared.open(resolvedURL, configuration: config) { _, _ in
                            resolvedURL.stopAccessingSecurityScopedResource()
                        }
                        return true
                    }
                }
                // Bookmark missing or resolution failed — prompt user to re-select the file
                Self.promptRelink(originalPath: path, textView: textView, charIndex: charIndex)
                return true
            }

        }

        /// Re-create the security-scoped bookmark for a file link whose bookmark went stale.
        private static func refreshFileLinkBookmark(_ url: URL, textView: NSTextView, charIndex: Int) {
            guard let storage = textView.textStorage else { return }
            do {
                let freshBookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                let base64 = freshBookmark.base64EncodedString()
                storage.addAttribute(.fileLinkBookmark, value: base64, range: NSRange(location: charIndex, length: 1))
            } catch {
                // Bookmark refresh failed — stale bookmark will trigger re-link prompt on next open
            }
        }

        /// Bookmark is missing or irrecoverably stale — ask the user to re-select the file.
        private static func promptRelink(originalPath: String, textView: NSTextView, charIndex: Int) {
            let filename = (originalPath as NSString).lastPathComponent
            let alert = NSAlert()
            alert.messageText = "Cannot Open \"\(filename)\""
            alert.informativeText = "Jot no longer has permission to access this file. Would you like to locate it again?"
            alert.addButton(withTitle: "Locate File...")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning

            guard let window = textView.window else {
                NSSound.beep()
                return
            }

            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }

                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.message = "Select \"\(filename)\" to restore access"
                panel.nameFieldStringValue = filename

                panel.beginSheetModal(for: window) { result in
                    guard result == .OK, let url = panel.url else { return }

                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                    // Create a fresh bookmark
                    if let bookmarkData = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        let base64 = bookmarkData.base64EncodedString()
                        if let storage = textView.textStorage, charIndex < storage.length {
                            storage.addAttribute(.fileLinkBookmark, value: base64, range: NSRange(location: charIndex, length: 1))
                            storage.addAttribute(.fileLinkPath, value: url.path, range: NSRange(location: charIndex, length: 1))
                        }
                        // Also update the FileLinkAttachment if present
                        if let storage = textView.textStorage,
                           charIndex < storage.length,
                           let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? FileLinkAttachment {
                            let updated = FileLinkAttachment(
                                filePath: url.path,
                                displayName: attachment.displayName,
                                bookmarkBase64: base64
                            )
                            storage.addAttribute(.attachment, value: updated, range: NSRange(location: charIndex, length: 1))
                        }
                        // Successfully re-linked file via user selection
                    }

                    // Now open the file
                    let config = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.open(url, configuration: config) { _, _ in
                    }
                }
            }
        }

        func updateColorScheme(_ scheme: ColorScheme) {
            guard scheme != currentColorScheme else { return }
            currentColorScheme = scheme
            rerenderPillAttachments()
        }

        /// Re-renders all notelink and filelink pill images to match the current
        /// color scheme. Called after appearance changes; safe to call at any time.
        private func rerenderPillAttachments() {
            // Invalidate cached pill images since appearance changed
            pillImageCache.removeAllObjects()

            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  textStorage.length > 0 else { return }

            isUpdating = true
            textStorage.beginEditing()

            var pillRanges: [(range: NSRange, replacement: NSAttributedString)] = []

            textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length), options: []) { value, charRange, _ in
                let attrs = textStorage.attributes(at: charRange.location, effectiveRange: nil)
                if let attachment = value as? NotelinkAttachment {
                    let newPill = makeNotelinkAttachment(noteID: attachment.noteID, noteTitle: attachment.noteTitle)
                    pillRanges.append((range: charRange, replacement: newPill))
                } else if let nlID = attrs[.notelinkID] as? String,
                          let nlTitle = attrs[.notelinkTitle] as? String {
                    let newPill = makeNotelinkAttachment(noteID: nlID, noteTitle: nlTitle)
                    pillRanges.append((range: charRange, replacement: newPill))
                } else if let attachment = value as? FileLinkAttachment {
                    let newPill = makeFileLinkAttachment(filePath: attachment.filePath, displayName: attachment.displayName, bookmarkBase64: attachment.bookmarkBase64)
                    pillRanges.append((range: charRange, replacement: newPill))
                } else if let filePath = attrs[.fileLinkPath] as? String {
                    let displayName = (attrs[.fileLinkDisplayName] as? String) ?? URL(fileURLWithPath: filePath).lastPathComponent
                    let bookmark = (attrs[.fileLinkBookmark] as? String) ?? ""
                    let newPill = makeFileLinkAttachment(filePath: filePath, displayName: displayName, bookmarkBase64: bookmark)
                    pillRanges.append((range: charRange, replacement: newPill))
                } else if let fileAtt = value as? NoteFileAttachment, fileAtt.viewMode == .tag {
                    let meta = FileAttachmentMetadata(
                        storedFilename: fileAtt.storedFilename,
                        originalFilename: fileAtt.originalFilename,
                        typeIdentifier: fileAtt.typeIdentifier,
                        displayLabel: fileAtt.originalFilename,
                        viewMode: .tag
                    )
                    let newPill = makeFileAttachment(metadata: meta)
                    pillRanges.append((range: charRange, replacement: newPill))
                }
            }

            // Apply replacements in reverse order to preserve character offsets
            for item in pillRanges.reversed() {
                textStorage.replaceCharacters(in: item.range, with: item.replacement)
            }

            textStorage.endEditing()
            isUpdating = false
        }

        func applyInitialText(_ text: String) {
            guard let textView = textView, let textStorage = textView.textStorage else {
                return
            }

            typingAnimationManager?.clearAllAnimations()
            isUpdating = true

            // setAttributedString replaces the entire storage — do NOT pre-set textColor
            // (that setter walks-and-wipes all foreground attributes).
            let attributedText = deserialize(text)
            textStorage.setAttributedString(attributedText)

            textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)
            styleTodoParagraphs()

            // Cache the input directly — deserialize+serialize is a stable round-trip,
            // so we avoid a redundant O(n) enumeration pass here.
            lastSerialized = text

            if let container = textView.textContainer,
                let layoutManager = textView.layoutManager
            {
                layoutManager.ensureLayout(for: container)
            }
            textView.invalidateIntrinsicContentSize()
            textView.needsDisplay = true
            textView.needsLayout = true

            isUpdating = false
            // Create image overlays. Host may be the text view until `completeDeferredSetup`.
            // Use the same synchronized layout + no-animation path as note switches.
            performSynchronizedOverlayLayoutPass(in: textView)

            needsDeferredOverlaySetup = true
        }

        // Ensures all text has the correct foreground color attribute
        private func ensureTextColor() {
            // NSColor.labelColor is dynamic — a display refresh is all that's needed.
            textView?.needsDisplay = true
        }

        func updateIfNeeded(with text: String) {
            guard !isUpdating, let textView = textView, let textStorage = textView.textStorage
            else { return }

            // Flush any pending debounced serialization before switching notes.
            // If the incoming text differs from lastSerialized the note is changing; synchronously
            // drain the work item so the outgoing note's edits reach the binding before we
            // overwrite lastSerialized with the incoming note's content.
            if text != lastSerialized, let pending = serializeWorkItem {
                pending.cancel()
                serializeWorkItem = nil
                let serialized = serialize()
                if serialized != lastSerialized {
                    lastSerialized = serialized
                    textBinding.wrappedValue = serialized
                }
            }

            guard text != lastSerialized else { return }

            // Tear down stale chrome before new text lands; cancel debounced passes that
            // would otherwise reconcile against the wrong note mid-transaction (G4).
            pendingOverlayUpdate?.cancel()
            pendingOverlayUpdate = nil
            pendingPostNoteSwitchOverlayWork?.cancel()
            pendingPostNoteSwitchOverlayWork = nil

            let selectedRange = textView.selectedRange()

            typingAnimationManager?.clearAllAnimations()
            isUpdating = true

            let attributedText = deserialize(text)
            textStorage.setAttributedString(attributedText)

            textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)
            styleTodoParagraphs()

            lastSerialized = text
            textView.setSelectedRange(selectedRange)

            isUpdating = false

            // Drop every overlay view immediately so the user never sees the *previous* note's
            // callout/table/chrome parented on the new storage for a frame (wrong glyph mapping).
            removeAllOverlays()

            // Defer rebuild to the next main-queue turn so `textContainer`/`textView` geometry
            // matches the SwiftUI layout pass that triggered the binding change (fixes slide/crop).
            let overlayWork = DispatchWorkItem { [weak self] in
                guard let self, let tv = self.textView else { return }
                self.pendingPostNoteSwitchOverlayWork = nil
                tv.window?.layoutIfNeeded()
                self.performSynchronizedOverlayLayoutPass(in: tv)
            }
            pendingPostNoteSwitchOverlayWork = overlayWork
            DispatchQueue.main.async(execute: overlayWork)

        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, textView == self.textView,
                !isUpdating
            else { return }

            // Invalidate stale highlight edit range — text edits shift character positions
            highlightEditRange = NSRange(location: NSNotFound, length: 0)

            // Trigger typing animation for newly inserted characters
            if let location = pendingAnimationLocation,
                let length = pendingAnimationLength,
                length > 0
            {
                let stagger = length > 1
                typingAnimationManager?.animateCharacters(
                    in: NSRange(location: location, length: length),
                    stagger: stagger
                )
                pendingAnimationLocation = nil
                pendingAnimationLength = nil
            }

            // Inherit typing attributes immediately; debounce font family correction
            // to avoid running fixInconsistentFonts on every keystroke.
            // Accumulate edited ranges across debounce intervals so the eventual fix
            // is scoped to only the paragraphs that changed during the debounce window.
            self.fixFontsWorkItem?.cancel()
            if let editedRange = textView.textStorage?.editedRange,
               editedRange.location != NSNotFound {
                if let existing = pendingFontFixRange {
                    pendingFontFixRange = NSUnionRange(existing, editedRange)
                } else {
                    pendingFontFixRange = editedRange
                }
            }
            let fontFixWork = DispatchWorkItem { [weak self] in
                guard let self = self, !self.isUpdating else { return }
                let range = self.pendingFontFixRange
                self.pendingFontFixRange = nil
                self.fixInconsistentFonts(in: range)
            }
            self.fixFontsWorkItem = fontFixWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: fontFixWork)

            DispatchQueue.main.async {
                guard !self.isUpdating else { return }

                // Derive typing attributes from the character at/before the cursor.
                // This is how every modern text editor works: the next typed character
                // inherits the formatting of its immediate left neighbour.
                if let storage = textView.textStorage, storage.length > 0 {
                    let sel = textView.selectedRange()
                    var loc = sel.location > 0 ? min(sel.location - 1, storage.length - 1) : 0
                    // When cursor is at a paragraph boundary (right after \n),
                    // loc points to the previous paragraph. If the CURRENT paragraph
                    // is a block quote, we must read from the current paragraph instead
                    // so the indent / block quote attributes aren't lost.
                    let str = storage.string as NSString
                    if sel.location > 0,
                       sel.location < storage.length,
                       str.character(at: sel.location - 1) == 0x0A,
                       storage.attribute(.blockQuote, at: sel.location, effectiveRange: nil) as? Bool == true {
                        loc = sel.location
                    }
                    // Skip backward over attachment characters (U+FFFC) to avoid
                    // inheriting attachment-scoped attributes like .attachment,
                    // .baselineOffset, or block paragraph styles
                    while loc > 0,
                          str.character(at: loc) == 0xFFFC,
                          storage.attribute(.attachment, at: loc, effectiveRange: nil) != nil {
                        loc -= 1
                    }
                    var attrs = storage.attributes(at: loc, effectiveRange: nil)
                    // Strip notelink attributes so typed text after a mention
                    // doesn't inherit them — prevents ghost duplication on serialize.
                    attrs.removeValue(forKey: .notelinkID)
                    attrs.removeValue(forKey: .notelinkTitle)
                    // Ensure adaptive text color for non-custom ranges
                    if attrs[TextFormattingManager.customTextColorKey] as? Bool != true {
                        // Block quote text uses muted color — preserve it
                        if attrs[.blockQuote] as? Bool == true {
                            attrs[.foregroundColor] = blockQuoteTextColor
                        } else {
                            attrs[.foregroundColor] = NSColor.labelColor
                        }
                    }
                    textView.typingAttributes = attrs
                } else {
                    textView.typingAttributes = Self.baseTypingAttributes(for: self.currentColorScheme)
                }
            }

            // Dismiss URL/code paste menus on any text change
            let dismissPayload: [String: Any]? = editorInstanceID.map { ["editorInstanceID": $0] }
            NotificationCenter.default.post(name: .urlPasteDismiss, object: dismissPayload)
            NotificationCenter.default.post(name: .codePasteDismiss, object: nil)

            // Pass the text storage's edited range so styleTodoParagraphs can scope
            // its work to just the affected paragraphs instead of the full document.
            let edited = textView.textStorage?.editedRange
            syncText(editedRange: edited)
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // Reject bare newlines into an empty document. This prevents a
            // leaked Return key (e.g. from the SwiftUI title field's responder
            // chain transition) from injecting a blank first line.
            if replacementString == "\n",
               let storage = textView.textStorage, storage.length == 0 {
                return false
            }

            // Block-level attachments own their entire paragraph — no text beside them.
            // When the user tries to type on a line containing a block attachment,
            // redirect the insertion to a new line after the block.
            if let replacement = replacementString, !replacement.isEmpty,
               replacement != "\n",
               let storage = textView.textStorage, storage.length > 0 {
                // Block inserts (toolbar, slash menu, paste) reach here with a replacement
                // string that includes U+FFFC (NSTextAttachment.character). The redirect below
                // is only for ordinary typing beside an existing block; it must not run for
                // those programmatic inserts. Coordinator batch work also sets isUpdating.
                if isUpdating { return true }
                if replacement.unicodeScalars.contains(where: { $0.value == 0xFFFC }) {
                    return true
                }

                let nsString = storage.string as NSString
                let insertionLocation = max(0, min(affectedCharRange.location, storage.length))
                var checkRanges: [NSRange] = []
                if insertionLocation < storage.length {
                    checkRanges.append(
                        nsString.paragraphRange(for: NSRange(location: insertionLocation, length: 0))
                    )
                }
                if insertionLocation > 0 {
                    let previousRange = nsString.paragraphRange(
                        for: NSRange(location: insertionLocation - 1, length: 0)
                    )
                    if !checkRanges.contains(where: { NSEqualRanges($0, previousRange) }) {
                        checkRanges.append(previousRange)
                    }
                }

                func isBlockAttachment(_ value: Any?) -> Bool {
                    value is NoteCalloutAttachment
                        || value is NoteMapAttachment
                        || value is NoteCodeBlockAttachment
                        || value is NoteTableAttachment
                        || value is NoteTabsAttachment
                        || value is NoteCardSectionAttachment
                        || value is NoteDividerAttachment
                        || value is NoteLinkCardAttachment
                        || ((value as? NoteFileAttachment).map { $0.viewMode != .tag } ?? false)
                }

                var blockParaRange: NSRange?
                for range in checkRanges {
                    var rangeHasBlockAttachment = false
                    storage.enumerateAttribute(.attachment, in: range, options: []) { value, _, stop in
                        if isBlockAttachment(value) {
                            rangeHasBlockAttachment = true
                            stop.pointee = true
                        }
                    }
                    if rangeHasBlockAttachment {
                        blockParaRange = range
                        break
                    }
                }

                if let blockParaRange {
                    let landingLocation = NSMaxRange(blockParaRange)
                    let alreadyOnLandingLine =
                        insertionLocation == landingLocation
                        && insertionLocation > 0
                        && nsString.character(at: insertionLocation - 1) == 0x0A

                    if alreadyOnLandingLine {
                        // The caret is already on the writable line after the block
                        // (or at EOF right after the block's trailing newline). Let
                        // AppKit insert normally instead of manufacturing another blank line.
                    } else {
                        // Redirect typing to the first writable location after the block.
                        // Reuse an existing landing line when the block already ends with
                        // a newline; only synthesize one if the block paragraph reaches EOF
                        // without leaving a writable landing position behind.
                        let needsInsertedNewline =
                            landingLocation == 0
                            || landingLocation > storage.length
                            || nsString.character(at: landingLocation - 1) != 0x0A

                        let attrs = Self.baseTypingAttributes(for: currentColorScheme)
                        var insertPoint = min(landingLocation, storage.length)

                        isUpdating = true
                        storage.beginEditing()
                        if needsInsertedNewline {
                            storage.insert(
                                NSAttributedString(string: "\n", attributes: attrs),
                                at: insertPoint
                            )
                            insertPoint += 1
                        }
                        storage.insert(
                            NSAttributedString(string: replacement, attributes: attrs),
                            at: insertPoint
                        )
                        storage.endEditing()
                        textView.setSelectedRange(NSRange(
                            location: insertPoint + replacement.utf16.count,
                            length: 0
                        ))
                        isUpdating = false
                        syncText()

                        if replacement == "/" {
                            let slashIndex = insertPoint
                            let tv = textView
                            DispatchQueue.main.async { [weak self] in
                                guard let self else { return }
                                self.showCommandMenuAtCursor(
                                    textView: tv,
                                    slashCharacterIndex: slashIndex
                                )
                            }
                        } else if replacement == "@",
                                  let inlineTextView = textView as? InlineNSTextView {
                            inlineTextView.redirectedNotePickerLocation = insertPoint
                        }

                        return false
                    }
                }
            }

            // Check for "/" to trigger command menu
            if replacementString == "/" {
                // Defer menu placement to the next run-loop turn so the "/" is already
                // in `textStorage` and `layoutManager` reflects it. Measuring inside
                // `shouldChangeText` (before the change commits) uses the pre-insert
                // layout; at the document tail that often yields a zero / wrong glyph
                // rect, which posts CGPoint near the origin — SwiftUI then draws the
                // menu at the top while `updateCommandMenuPlaceholder` (after sync)
                // correctly tracks the real slash.
                let slashIndex = affectedCharRange.location
                let tv = textView
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.showCommandMenuAtCursor(textView: tv, slashCharacterIndex: slashIndex)
                }
                return true  // Allow the "/" to be typed
            }

            // Check for Enter key in todo paragraph
            if replacementString == "\n", isInTodoParagraph(range: affectedCharRange) {
                // If the current todo is empty, exit todo mode instead of creating another
                guard let storage = textView.textStorage else { return true }
                let loc = max(0, min(storage.length, affectedCharRange.location))
                let paraRange = (storage.string as NSString).paragraphRange(
                    for: NSRange(location: loc, length: 0))
                // Todo structure: [attachment][space][space][text...]\n
                let contentStart = paraRange.location + 3
                let contentText: String
                if contentStart < NSMaxRange(paraRange) && contentStart < storage.length {
                    let contentRange = NSRange(
                        location: contentStart,
                        length: NSMaxRange(paraRange) - contentStart)
                    contentText = (storage.string as NSString)
                        .substring(with: contentRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    contentText = ""
                }

                if contentText.isEmpty {
                    // Empty todo — remove it and insert a plain newline to exit todo mode
                    isUpdating = true
                    let deleteStart = paraRange.location > 0 ? paraRange.location - 1 : paraRange.location
                    let deleteLen = min(
                        paraRange.length + (paraRange.location > 0 ? 1 : 0),
                        storage.length - deleteStart)
                    storage.replaceCharacters(
                        in: NSRange(location: deleteStart, length: deleteLen),
                        with: "\n")
                    textView.setSelectedRange(NSRange(location: deleteStart + 1, length: 0))
                    isUpdating = false
                    syncText()
                    return false
                }

                insertTodo()
                return false
            }

            // Check for Enter key in numbered list paragraph
            if replacementString == "\n", let olNum = orderedListNumber(at: affectedCharRange) {
                guard let storage = textView.textStorage else { return true }
                let loc = max(0, min(storage.length, affectedCharRange.location))
                let paraRange = (storage.string as NSString).paragraphRange(
                    for: NSRange(location: loc, length: 0))
                let prefixLen = orderedListPrefixLength(for: olNum)
                let contentStart = paraRange.location + prefixLen
                let contentText: String
                if contentStart < NSMaxRange(paraRange) && contentStart < storage.length {
                    let contentRange = NSRange(
                        location: contentStart,
                        length: NSMaxRange(paraRange) - contentStart)
                    contentText = (storage.string as NSString)
                        .substring(with: contentRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    contentText = ""
                }

                if contentText.isEmpty {
                    // Empty numbered list item — exit list mode
                    isUpdating = true
                    let deleteStart = paraRange.location > 0 ? paraRange.location - 1 : paraRange.location
                    let deleteLen = min(
                        paraRange.length + (paraRange.location > 0 ? 1 : 0),
                        storage.length - deleteStart)
                    storage.replaceCharacters(
                        in: NSRange(location: deleteStart, length: deleteLen),
                        with: "\n")
                    textView.setSelectedRange(NSRange(location: deleteStart + 1, length: 0))
                    isUpdating = false
                    syncText()
                    return false
                }

                // Insert next numbered list item
                let nextNum = olNum + 1
                let nextPrefix = "\(nextNum). "
                let insertionPoint = affectedCharRange.location
                isUpdating = true
                storage.beginEditing()
                storage.replaceCharacters(
                    in: NSRange(location: insertionPoint, length: 0),
                    with: "\n" + nextPrefix)
                let prefixRange = NSRange(
                    location: insertionPoint + 1,
                    length: nextPrefix.count)
                storage.addAttribute(.orderedListNumber, value: nextNum, range: prefixRange)
                // Apply body font to the prefix
                let bodyFont = FontManager.bodyNS()
                storage.addAttribute(.font, value: bodyFont, range: prefixRange)
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: prefixRange)
                storage.endEditing()
                textView.setSelectedRange(
                    NSRange(location: insertionPoint + 1 + nextPrefix.count, length: 0))
                isUpdating = false
                syncText()
                return false
            }

            // Check for Enter key in bullet list paragraph
            if replacementString == "\n", isInBulletParagraph(range: affectedCharRange) {
                guard let storage = textView.textStorage else { return true }
                let loc = max(0, min(storage.length, affectedCharRange.location))
                let paraRange = (storage.string as NSString).paragraphRange(
                    for: NSRange(location: loc, length: 0))
                // Bullet structure: "• " + text + optional "\n"
                let bulletPrefixLen = 2
                let contentStart = paraRange.location + bulletPrefixLen
                let contentText: String
                if contentStart < NSMaxRange(paraRange) && contentStart < storage.length {
                    let contentRange = NSRange(
                        location: contentStart,
                        length: NSMaxRange(paraRange) - contentStart)
                    contentText = (storage.string as NSString)
                        .substring(with: contentRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    contentText = ""
                }

                if contentText.isEmpty {
                    // Empty bullet — remove it and exit bullet mode
                    isUpdating = true
                    let deleteStart = paraRange.location > 0 ? paraRange.location - 1 : paraRange.location
                    let deleteLen = min(
                        paraRange.length + (paraRange.location > 0 ? 1 : 0),
                        storage.length - deleteStart)
                    storage.replaceCharacters(
                        in: NSRange(location: deleteStart, length: deleteLen),
                        with: "\n")
                    textView.setSelectedRange(NSRange(location: deleteStart + 1, length: 0))
                    isUpdating = false
                    syncText()
                    return false
                }

                // Insert new bullet on next line
                let bulletPrefix = "• "
                let insertionPoint = affectedCharRange.location
                isUpdating = true
                storage.beginEditing()
                storage.replaceCharacters(
                    in: NSRange(location: insertionPoint, length: 0),
                    with: "\n" + bulletPrefix)
                let prefixRange = NSRange(
                    location: insertionPoint + 1,
                    length: bulletPrefix.count)
                let bodyFont = FontManager.bodyNS()
                storage.addAttribute(.font, value: bodyFont, range: prefixRange)
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: prefixRange)
                storage.endEditing()
                textView.setSelectedRange(
                    NSRange(location: insertionPoint + 1 + bulletPrefix.count, length: 0))
                isUpdating = false
                syncText()
                return false
            }

            // Check for Enter key in block quote paragraph
            if replacementString == "\n",
               isInBlockQuoteParagraph(range: affectedCharRange) {
                guard let storage = textView.textStorage else { return true }
                let loc = max(0, min(storage.length, affectedCharRange.location))
                let paraRange = (storage.string as NSString).paragraphRange(
                    for: NSRange(location: loc, length: 0))

                // Content is everything in the paragraph except the trailing \n
                let contentLen = max(0, paraRange.length - 1)
                let contentText = contentLen > 0
                    ? (storage.string as NSString)
                        .substring(with: NSRange(location: paraRange.location, length: contentLen))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                if contentText.isEmpty {
                    // Empty block quote line — exit quote mode
                    isUpdating = true
                    // Prepare the reset style BEFORE beginEditing — if this guard fails,
                    // we must not leave the storage in a permanently locked editing session.
                    guard let resetStyle = Self.baseParagraphStyle().mutableCopy() as? NSMutableParagraphStyle else {
                        isUpdating = false
                        return false
                    }
                    storage.beginEditing()
                    storage.removeAttribute(.blockQuote, range: paraRange)
                    storage.addAttribute(.paragraphStyle, value: resetStyle, range: paraRange)
                    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: paraRange)
                    storage.endEditing()
                    textView.setSelectedRange(NSRange(location: paraRange.location, length: 0))
                    // Reset typing attributes so next typed character does NOT inherit .blockQuote
                    textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                    isUpdating = false
                    syncText()
                    return false
                }

                // Non-empty line — insert \n and apply block quote to the new paragraph
                let insertionPoint = affectedCharRange.location
                isUpdating = true
                storage.beginEditing()
                storage.replaceCharacters(
                    in: NSRange(location: insertionPoint, length: 0), with: "\n")
                let newParaStart = insertionPoint + 1
                // Use the full new paragraph range so .blockQuote covers the entire
                // paragraph including any trailing newline -- prevents attribute gaps
                // that cause isInBlockQuoteParagraph to miss the next Enter check.
                let newParaRange = (storage.string as NSString).paragraphRange(
                    for: NSRange(location: newParaStart, length: 0))
                if newParaRange.length > 0 {
                    storage.addAttribute(.blockQuote, value: true, range: newParaRange)
                    storage.addAttribute(
                        .paragraphStyle,
                        value: Self.blockQuoteParagraphStyle(),
                        range: newParaRange)
                    storage.addAttribute(
                        .foregroundColor,
                        value: blockQuoteTextColor,
                        range: newParaRange)
                }
                storage.endEditing()
                textView.setSelectedRange(NSRange(location: newParaStart, length: 0))
                // Set typing attributes so next typed character inherits quote style
                var typingAttrs = Self.baseTypingAttributes(for: currentColorScheme)
                typingAttrs[.blockQuote] = true
                typingAttrs[.paragraphStyle] = Self.blockQuoteParagraphStyle()
                typingAttrs[.foregroundColor] = blockQuoteTextColor
                textView.typingAttributes = typingAttrs
                isUpdating = false
                syncText()
                return false
            }

            // Smart backspace: delete an empty todo paragraph entirely
            if replacementString == "" {
                guard let storage = textView.textStorage else { return true }
                if isInTodoParagraph(range: affectedCharRange) {
                    let loc = max(0, min(storage.length, affectedCharRange.location))
                    let paraRange = (storage.string as NSString).paragraphRange(
                        for: NSRange(location: loc, length: 0))
                    // Todo structure: [attachment][space][space][text...]\n
                    let contentStart = paraRange.location + 3
                    guard contentStart <= NSMaxRange(paraRange),
                          NSMaxRange(paraRange) <= storage.length else {
                        return true
                    }
                    let contentRange = NSRange(
                        location: contentStart,
                        length: NSMaxRange(paraRange) - contentStart)
                    let contentText = (storage.string as NSString)
                        .substring(with: contentRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let cursorAtOrBeforeContent = affectedCharRange.location <= contentStart

                    if contentText.isEmpty || cursorAtOrBeforeContent {
                        let deleteStart = paraRange.location > 0 ? paraRange.location - 1 : paraRange.location
                        let deleteLen = min(
                            paraRange.length + (paraRange.location > 0 ? 1 : 0),
                            storage.length - deleteStart)
                        let safeRange = NSRange(location: deleteStart, length: deleteLen)
                        isUpdating = true
                        storage.replaceCharacters(in: safeRange, with: "")
                        textView.setSelectedRange(NSRange(location: safeRange.location, length: 0))
                        isUpdating = false
                        syncText()
                        return false
                    }
                }

                // Smart backspace for numbered list: remove prefix when cursor is at or before content
                if let olNum = orderedListNumber(at: affectedCharRange) {
                    let loc = max(0, min(storage.length, affectedCharRange.location))
                    let paraRange = (storage.string as NSString).paragraphRange(
                        for: NSRange(location: loc, length: 0))
                    let prefixLen = orderedListPrefixLength(for: olNum)
                    let contentStart = paraRange.location + prefixLen
                    let cursorAtOrBeforeContent = affectedCharRange.location <= contentStart

                    if cursorAtOrBeforeContent {
                        // Remove the "N. " prefix, keep the content
                        let prefixRange = NSRange(location: paraRange.location, length: min(prefixLen, paraRange.length))
                        isUpdating = true
                        storage.replaceCharacters(in: prefixRange, with: "")
                        textView.setSelectedRange(NSRange(location: paraRange.location, length: 0))
                        isUpdating = false
                        syncText()
                        return false
                    }
                }

                // Smart backspace for bullet list: remove "• " prefix when cursor is at or before content
                if isInBulletParagraph(range: affectedCharRange) {
                    let loc = max(0, min(storage.length, affectedCharRange.location))
                    let paraRange = (storage.string as NSString).paragraphRange(
                        for: NSRange(location: loc, length: 0))
                    let bulletPrefixLen = 2
                    let contentStart = paraRange.location + bulletPrefixLen
                    let cursorAtOrBeforeContent = affectedCharRange.location <= contentStart

                    if cursorAtOrBeforeContent {
                        let prefixRange = NSRange(location: paraRange.location, length: min(bulletPrefixLen, paraRange.length))
                        isUpdating = true
                        storage.replaceCharacters(in: prefixRange, with: "")
                        textView.setSelectedRange(NSRange(location: paraRange.location, length: 0))
                        isUpdating = false
                        syncText()
                        return false
                    }
                }

                // Smart backspace for block quote: strip formatting when paragraph is empty
                // or cursor is at the very start of the paragraph.
                //
                // Must use the CURSOR position (selectedRange), NOT affectedCharRange.
                // When cursor is at the start of a block quote, affectedCharRange points
                // to the previous paragraph's trailing \n, which has no .blockQuote
                // attribute — causing the entire handler to be skipped and the wrong
                // character to be deleted instead.
                let cursorPos = textView.selectedRange().location
                if cursorPos > 0,
                   isInBlockQuoteParagraph(range: NSRange(location: cursorPos, length: 0)) {
                    let paLoc = max(0, min(storage.length, cursorPos))
                    let paraRange = (storage.string as NSString).paragraphRange(
                        for: NSRange(location: paLoc, length: 0))
                    let contentLen = max(0, paraRange.length - 1)
                    let contentText = contentLen > 0
                        ? (storage.string as NSString).substring(with: NSRange(location: paraRange.location, length: contentLen))
                        : ""
                    // cursorAtStart: cursor is at or before the first character of the paragraph.
                    // Use cursorPos (not affectedCharRange.location) to avoid the off-by-one
                    // that fires on deletion of the first actual character in the paragraph.
                    let cursorAtStart = cursorPos <= paraRange.location

                    if contentText.isEmpty || cursorAtStart {
                        isUpdating = true
                        storage.beginEditing()
                        storage.removeAttribute(.blockQuote, range: paraRange)
                        storage.enumerateAttribute(.paragraphStyle, in: paraRange, options: []) { value, subRange, _ in
                            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                                ?? NSMutableParagraphStyle()
                            style.firstLineHeadIndent = 0
                            style.headIndent = 0
                            storage.addAttribute(.paragraphStyle, value: style, range: subRange)
                        }
                        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: paraRange)
                        storage.endEditing()
                        textView.setSelectedRange(NSRange(location: paraRange.location, length: 0))
                        isUpdating = false
                        syncText()
                        return false
                    }
                }
            }

            // Record pending animation for newly inserted text.
            // Skip animation entirely for paste and undo/redo operations — instant insertion feels right.
            let isPasting = (textView as? InlineNSTextView)?.isPasting ?? false
            let isUndoingOrRedoing = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            if !isUpdating, !isPasting, !isUndoingOrRedoing, let replacement = replacementString, !replacement.isEmpty {
                pendingAnimationLocation = affectedCharRange.location
                pendingAnimationLength = replacement.count
            } else {
                pendingAnimationLocation = nil
                pendingAnimationLength = nil
            }

            return true
        }

        func handleReturn(in textView: NSTextView) -> Bool {
            let sel = textView.selectedRange()
            guard let storage = textView.textStorage else { return false }

            // Block quote: Enter on empty quoted line exits the quote
            let curLoc = max(0, min(storage.length, sel.location))
            if curLoc < storage.length,
               storage.attribute(.blockQuote, at: curLoc, effectiveRange: nil) as? Bool == true {
                let paraRange = (storage.string as NSString).paragraphRange(
                    for: NSRange(location: curLoc, length: 0))
                let paraText = (storage.string as NSString).substring(with: paraRange)
                    .trimmingCharacters(in: .newlines)
                if paraText.isEmpty {
                    // Remove block quote from this empty paragraph
                    isUpdating = true
                    storage.beginEditing()
                    storage.removeAttribute(.blockQuote, range: paraRange)
                    let bodyStyle = NSMutableParagraphStyle()
                    bodyStyle.paragraphSpacing = 4
                    storage.addAttribute(.paragraphStyle, value: bodyStyle, range: paraRange)
                    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: paraRange)
                    storage.endEditing()
                    textView.setSelectedRange(NSRange(location: paraRange.location, length: 0))
                    // Reset typing attributes to body
                    var typingAttrs = Self.baseTypingAttributes(for: currentColorScheme)
                    typingAttrs.removeValue(forKey: .blockQuote)
                    textView.typingAttributes = typingAttrs
                    isUpdating = false
                    syncText()
                    return true
                }
            }

            guard isInTodoParagraph(range: sel) else { return false }

            let loc = max(0, min(storage.length, sel.location))
            let paraRange = (storage.string as NSString).paragraphRange(
                for: NSRange(location: loc, length: 0))
            let contentStart = paraRange.location + 3
            let contentText: String
            if contentStart < NSMaxRange(paraRange) && contentStart < storage.length {
                let contentRange = NSRange(
                    location: contentStart,
                    length: NSMaxRange(paraRange) - contentStart)
                contentText = (storage.string as NSString)
                    .substring(with: contentRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                contentText = ""
            }

            if contentText.isEmpty {
                // Exit todo mode: strip the checkbox content from this paragraph,
                // keeping the trailing newline so the empty line stays visible as a
                // regular paragraph. Deleting the whole paragraph would collapse the
                // line and shrink the editor — the opposite of what pressing Enter
                // on an empty line should do.
                isUpdating = true
                let contentOnlyLen = max(0, paraRange.length - 1)  // exclude trailing \n
                storage.replaceCharacters(
                    in: NSRange(location: paraRange.location, length: contentOnlyLen),
                    with: "")
                textView.setSelectedRange(NSRange(location: paraRange.location, length: 0))
                isUpdating = false
                syncText()
                return true
            }

            insertTodo()
            return true
        }

        // MARK: - Command Menu Handling

        /// Shows the command menu anchored to the "/" character at `slashCharacterIndex`.
        /// Call only after that character exists in `textStorage` (layout must include the slash).
        private func showCommandMenuAtCursor(textView: NSTextView, slashCharacterIndex: Int) {
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer,
                let textStorage = textView.textStorage,
                slashCharacterIndex >= 0,
                slashCharacterIndex < textStorage.length
            else {
                return
            }

            let slashChar = (textStorage.string as NSString).substring(
                with: NSRange(location: slashCharacterIndex, length: 1))
            guard slashChar == "/" else { return }

            layoutManager.ensureLayout(for: textContainer)

            // Match `updateCommandMenuPlaceholder`: bounding rect of the "/" glyph in
            // the text container, then shift by `textContainerOrigin` into text-view
            // coordinates. The pre-commit `lineFragmentUsedRect` path disagreed with
            // this at the end of long documents and could collapse toward (0,0).
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: slashCharacterIndex)
            let slashRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )

            let cursorX = slashRect.origin.x + textView.textContainerOrigin.x
            let cursorY = slashRect.origin.y + textView.textContainerOrigin.y
            let cursorHeight = max(slashRect.height, 1)

            let visibleRect = textView.visibleRect
            let menuVerticalGap = CommandMenuLayout.verticalAnchorGap
            /// Tight inset when clamping into a narrow visible rect (horizontal squeeze).
            let menuEdgeGap: CGFloat = 4
            let safetyMargin: CGFloat = 20
            let menuHeight = CommandMenuLayout.totalHeight(for: CommandMenuLayout.maxVisibleItems)
            let menuWidth = CommandMenuLayout.width + CommandMenuLayout.outerPadding * 2

            let cursorBottomY = cursorY + cursorHeight
            let spaceBelow = visibleRect.maxY - cursorBottomY
            let shouldShowAbove = spaceBelow < (menuHeight + menuVerticalGap + safetyMargin)

            var xPosition = cursorX
            var yPosition: CGFloat
            if shouldShowAbove {
                yPosition = cursorY - menuHeight - menuVerticalGap
            } else {
                yPosition = cursorY + cursorHeight + menuVerticalGap
            }

            let minX = visibleRect.minX + safetyMargin
            let maxX = visibleRect.maxX - menuWidth - safetyMargin
            if minX <= maxX {
                xPosition = min(max(xPosition, minX), maxX)
            } else {
                xPosition = max(visibleRect.minX + menuEdgeGap, visibleRect.maxX - menuWidth - menuEdgeGap)
            }

            let minY = visibleRect.minY + safetyMargin
            let maxY = visibleRect.maxY - menuHeight - safetyMargin
            if minY <= maxY {
                yPosition = min(max(yPosition, minY), maxY)
            } else {
                yPosition = max(
                    visibleRect.minY + menuVerticalGap,
                    visibleRect.maxY - menuHeight - menuVerticalGap)
            }

            let menuPosition = CGPoint(x: xPosition, y: yPosition)

            NotificationCenter.default.post(
                name: .showCommandMenu,
                object: [
                    "position": NSValue(point: menuPosition),
                    "cursorHeight": cursorHeight,
                    "slashLocation": slashCharacterIndex,
                    "needsSpace": false,
                    // SwiftUI recomputes menu top Y from these as the filter narrows
                    // so the card stays anchored to "/" when placed above the line.
                    "showsAbove": shouldShowAbove,
                    "anchorCursorY": NSNumber(value: Double(cursorY))
                ],
                userInfo: editorInstanceID.map { ["editorInstanceID": $0] }
            )
        }

        /// Inserts a notelink at the position where "@" was typed, replacing "@" + filter text
        private func insertNoteLink(noteID: UUID, title: String, atLocation: Int, filterLength: Int) {
            guard let textView = self.textView,
                  let textStorage = textView.textStorage else { return }

            // Validate the deletion range before touching the storage
            let deleteLength = min(1 + filterLength, textStorage.length - atLocation)
            guard atLocation >= 0 && atLocation < textStorage.length && deleteLength > 0 else { return }

            // Build the notelink attachment (SwiftUI-rendered pill)
            let notelinkString = makeNotelinkAttachment(noteID: noteID.uuidString, noteTitle: title)

            let spaceStr = NSAttributedString(string: " ", attributes: Self.baseTypingAttributes(for: nil))
            let combined = NSMutableAttributedString()
            combined.append(notelinkString)
            combined.append(spaceStr)

            // Single atomic edit: delete "@" + filter, then insert attachment + space.
            // Wrapping in isUpdating prevents textDidChange → syncText() from firing
            // mid-operation, which caused the double-rendering bug.
            let deleteRange = NSRange(location: atLocation, length: deleteLength)
            if textView.shouldChangeText(in: deleteRange, replacementString: combined.string) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: deleteRange, with: combined)
                textStorage.endEditing()
                textView.didChangeText()
                isUpdating = false
            }

            // Move cursor to after the trailing space
            let newCursorPos = atLocation + combined.length
            textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))

            // Reset typing attributes to normal body text
            textView.typingAttributes = Self.baseTypingAttributes(for: nil)

            syncText()
        }

        // MARK: - Todo Handling

        /// Line-start markdown `-> ` shortcut — builds the Figma arrow attachment (see `handleMarkdownShortcuts`).
        /// `internal` (default) because the markdown-shortcut handler lives in a sibling file.
        func makeArrowGlyphForMarkdownShortcut(merging textAttrs: [NSAttributedString.Key: Any])
            -> NSAttributedString
        {
            makeArrowAttachment(merging: textAttrs)
        }

        /// `internal` (default) so `InlineNSTextView+MarkdownShortcuts.swift` can call it.
        func insertTodo() {
            guard let textView = textView else { return }
            let attachment = NSTextAttachment()
            let cell = TodoCheckboxAttachmentCell(isChecked: false)
            attachment.attachmentCell = cell
            attachment.bounds = CGRect(
                x: 0, y: Self.checkboxAttachmentYOffset, width: Self.checkboxAttachmentWidth,
                height: Self.checkboxIconSize)

            let todoAttachment = NSMutableAttributedString(attachment: attachment)
            todoAttachment.addAttribute(
                .baselineOffset, value: Self.checkboxBaselineOffset,
                range: NSRange(location: 0, length: todoAttachment.length))
            // Add comfortable spacing between checkbox and text (2 spaces)
            let space = NSAttributedString(
                string: "  ", attributes: Self.baseTypingAttributes(for: currentColorScheme))
            let paragraphBreak = NSAttributedString(
                string: "\n", attributes: Self.baseTypingAttributes(for: currentColorScheme))

            // Preserve selected text — place it after the checkbox instead of deleting it
            let selectedRange = textView.selectedRange()
            var selectedText: NSAttributedString?
            if selectedRange.length > 0, let storage = textView.textStorage,
               NSMaxRange(selectedRange) <= storage.length {
                selectedText = storage.attributedSubstring(from: selectedRange)
            }

            let composed = NSMutableAttributedString()
            if selectedRange.location != 0 {
                composed.append(paragraphBreak)
            }
            composed.append(todoAttachment)
            composed.append(space)
            if let selectedText {
                composed.append(selectedText)
            }

            replaceSelection(with: composed)
            let insertRange = NSRange(location: selectedRange.location, length: composed.length)
            styleTodoParagraphs(editedRange: insertRange)
            syncText(editedRange: insertRange)
        }

        private func insertWebClip(url: String) {
            guard let textView = textView else { return }
            let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedURL = Self.normalizedURL(from: cleanURL)
            let linkValue = normalizedURL.isEmpty ? cleanURL : normalizedURL
            let attachment = makeWebClipAttachment(
                url: linkValue,
                title: nil,
                description: nil,
                domain: nil
            )

            let composed = NSMutableAttributedString()
            let selectedRange = textView.selectedRange()

            // Check if we need a newline before (only if not at start and previous char is not whitespace)
            if selectedRange.location > 0 {
                if let textStorage = textView.textStorage,
                   selectedRange.location <= textStorage.length {
                    let prevChar = (textStorage.string as NSString).substring(
                        with: NSRange(location: selectedRange.location - 1, length: 1)
                    )
                    // Add newline only if previous character is not already whitespace or newline
                    if prevChar != " " && prevChar != "\n" && prevChar != "\t" {
                        let paragraphBreak = NSAttributedString(
                            string: "\n",
                            attributes: Self.baseTypingAttributes(for: currentColorScheme)
                        )
                        composed.append(paragraphBreak)
                    }
                }
            }

            composed.append(attachment)

            // Always add a space after the web clip for horizontal spacing
            let space = NSAttributedString(
                string: " ",
                attributes: Self.baseTypingAttributes(for: currentColorScheme)
            )
            composed.append(space)

            replaceSelection(with: composed)
            syncText()
        }

        private func replaceURLPasteWithWebClip(url: String, range: NSRange) {
            guard let textView = textView, let textStorage = textView.textStorage else { return }

            // Clear the blue highlight
            if range.location + range.length <= textStorage.length {
                textStorage.removeAttribute(.foregroundColor, range: range)
            }

            // Select the pasted URL text range and replace with web clip
            textView.setSelectedRange(range)
            insertWebClip(url: url)
        }

        private func convertSelectedTextToWebClip() {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0,
                  let textStorage = textView.textStorage,
                  selectedRange.location + selectedRange.length <= textStorage.length else { return }

            let selectedText = textStorage.attributedSubstring(from: selectedRange).string
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // If the entire selection is a URL, use it directly
            if InlineNSTextView.isLikelyURL(selectedText) {
                let normalizedURL = Self.normalizedURL(from: selectedText)
                let url = normalizedURL.isEmpty ? selectedText : normalizedURL
                insertWebClip(url: url)
                return
            }

            // Otherwise extract the first URL found within the selected text
            if let detected = InlineNSTextView.firstURL(in: selectedText) {
                insertWebClip(url: detected.absoluteString)
            }
        }

        private func replaceURLPasteWithPlainLink(url: String, range: NSRange) {
            guard let textView = textView, let textStorage = textView.textStorage else { return }

            if range.location + range.length <= textStorage.length {
                textStorage.removeAttribute(.foregroundColor, range: range)
            }

            textView.setSelectedRange(range)

            let attachment = makePlainLinkAttachment(url: url)
            let composed = NSMutableAttributedString()
            composed.append(attachment)
            let space = NSAttributedString(
                string: " ",
                attributes: Self.baseTypingAttributes(for: currentColorScheme))
            composed.append(space)

            replaceSelection(with: composed)
            syncText()
        }

        private func replaceURLPasteWithLinkCard(url: String, range: NSRange) {
            guard let textView = textView, let textStorage = textView.textStorage else { return }

            if range.location + range.length <= textStorage.length {
                textStorage.removeAttribute(.foregroundColor, range: range)
            }

            textView.setSelectedRange(range)

            let normalizedURL = Self.normalizedURL(from: url)
            let linkValue = normalizedURL.isEmpty ? url : normalizedURL
            let domain = Self.resolvedDomain(from: linkValue)

            // Insert using the code-block overlay pattern — card needs its own paragraph
            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            // Leading newline if not at paragraph start.
            // NSRange.location is a UTF-16 offset — use NSString.character(at:)
            // to index correctly through emoji / non-BMP / combining marks.
            // (Mirrors the sibling pattern in replaceCodePasteWithCodeBlock.)
            let nsString = textStorage.string as NSString
            if range.location > 0 {
                let prevChar = nsString.character(at: range.location - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }

            composed.append(makeLinkCardAttachment(
                url: linkValue, title: domain, description: "", domain: domain))
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            replaceSelection(with: composed)
            updateLinkCardOverlays(in: textView)
            syncText()

            // Fetch real metadata and update the attachment data in place
            let fetcher = WebMetadataFetcher()
            fetcher.fetchMetadata(from: linkValue) { [weak self] metadata in
                guard let self = self,
                      let textView = self.textView,
                      let textStorage = textView.textStorage else { return }

                let fullRange = NSRange(location: 0, length: textStorage.length)
                textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, stop in
                    guard let att = val as? NoteLinkCardAttachment, att.url == linkValue else { return }
                    att.title = metadata.title
                    att.descriptionText = metadata.description
                    att.domain = metadata.domain
                    att.thumbnailImage = metadata.thumbnail
                    att.thumbnailTintColor = metadata.thumbnail.flatMap { LinkCardView.averageColor(of: $0) }

                    // Persist thumbnail to disk cache
                    if let thumb = metadata.thumbnail {
                        ThumbnailCache.shared.cacheThumbnail(thumb, for: linkValue)
                    }

                    // Resize attachment to accommodate thumbnail
                    let newHeight = LinkCardView.heightForCard(hasThumbnail: metadata.thumbnail != nil)
                    let newSize = CGSize(width: 224, height: newHeight)
                    att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                    att.bounds = CGRect(origin: .zero, size: newSize)
                    if let lm = textView.layoutManager {
                        lm.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                    }

                    self.updateLinkCardOverlays(in: textView)
                    self.syncText()
                    stop.pointee = true
                }
            }
        }

        func makeLinkCardAttachment(
            url rawURL: String,
            title: String,
            description: String,
            domain: String
        ) -> NSMutableAttributedString {
            let normalizedURL = Self.normalizedURL(from: rawURL)
            let linkValue = normalizedURL.isEmpty ? rawURL : normalizedURL
            let resolvedDomain = domain.isEmpty ? Self.resolvedDomain(from: linkValue) : domain

            let cardWidth: CGFloat = 224
            let cardHeight = LinkCardView.fixedHeight
            let size = CGSize(width: cardWidth, height: cardHeight)

            let attachment = NoteLinkCardAttachment(
                title: title.isEmpty ? resolvedDomain : title,
                description: description,
                domain: resolvedDomain,
                url: linkValue)
            attachment.attachmentCell = CodeBlockSizeAttachmentCell(size: size)
            attachment.bounds = CGRect(origin: .zero, size: size)

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)
            let blockStyle = NSMutableParagraphStyle()
            blockStyle.alignment = .left
            blockStyle.paragraphSpacing = 8
            blockStyle.paragraphSpacingBefore = 8
            attributed.addAttribute(.paragraphStyle, value: blockStyle, range: range)
            return attributed
        }

        private func clearURLPasteHighlight(range: NSRange) {
            guard let textStorage = textView?.textStorage else { return }
            guard range.location + range.length <= textStorage.length else { return }
            // Restore base text attributes (keep the URL text as-is but remove special styling)
            let base = Self.baseTypingAttributes(for: currentColorScheme)
            textStorage.addAttributes(base, range: range)
        }

        private func replaceCodePasteWithCodeBlock(code: String, range: NSRange, language: String) {
            guard let textView = textView, let textStorage = textView.textStorage else { return }

            // Clear highlight
            if range.location + range.length <= textStorage.length {
                textStorage.removeAttribute(.backgroundColor, range: range)
            }

            // Select the pasted text range and replace with code block
            textView.setSelectedRange(range)
            let data = CodeBlockData(language: language, code: code)
            let attachment = makeCodeBlockAttachment(codeBlockData: data)

            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            let nsString = textStorage.string as NSString
            if range.location > 0 {
                let prevChar = nsString.character(at: range.location - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }
            composed.append(attachment)
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            replaceSelection(with: composed)
            syncText()
        }

        private func clearCodePasteHighlight(range: NSRange) {
            guard let textStorage = textView?.textStorage else { return }
            guard range.location + range.length <= textStorage.length else { return }
            textStorage.removeAttribute(.backgroundColor, range: range)
        }

        private func deleteWebClipAttachment(url: String) {
            guard let textStorage = textView?.textStorage else { return }

            textStorage.enumerateAttribute(
                .attachment, in: NSRange(location: 0, length: textStorage.length)
            ) { value, range, stop in
                guard value as? NSTextAttachment != nil else { return }
                let attrs = textStorage.attributes(at: range.location, effectiveRange: nil)
                if let linkValue = Self.linkURLString(from: attrs),
                   Self.normalizedURL(from: linkValue) == Self.normalizedURL(from: url)
                {
                    textStorage.deleteCharacters(in: range)
                    stop.pointee = true
                }
            }
            syncText()
        }

        private func insertVoiceTranscript(transcript: String) {
            guard textView != nil else { return }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let formatted = trimmed + " "
            replaceSelection(
                with: NSAttributedString(
                    string: formatted,
                    attributes: Self.baseTypingAttributes(for: currentColorScheme)))
            syncText()
        }

        private func insertTextAtCursor(_ text: String) {
            guard textView != nil else { return }
            // Preserve intentional leading/trailing whitespace from AI output;
            // only skip completely blank text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            replaceSelection(
                with: NSAttributedString(
                    string: text,
                    attributes: Self.baseTypingAttributes(for: currentColorScheme)))

            syncText()
        }

        func insertImage(filename: String) {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            // Pre-cache the image so makeImageAttachment uses the real aspect ratio
            // instead of the 4:3 fallback.
            let cacheKey = filename as NSString
            if Self.inlineImageCache.object(forKey: cacheKey) == nil,
               let url = ImageStorageManager.shared.getImageURL(for: filename),
               let img = NSImage(contentsOf: url) {
                Self.inlineImageCache.setObject(img, forKey: cacheKey, cost: Int(img.size.width * img.size.height * 4))
            }

            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            let insertAt = min(textView.selectedRange().location, textStorage.length)
            let nsString = textStorage.string as NSString

            // Ensure we start on a new line
            if insertAt > 0 {
                let prevChar = nsString.character(at: insertAt - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }

            // Block-level image attachment
            let imageAttrib = makeImageAttachment(filename: filename, widthRatio: 0.33)
            composed.append(imageAttrib)

            // Newline after so the cursor lands on the next line
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            let replaceRange = NSRange(location: insertAt, length: 0)
            if textView.shouldChangeText(in: replaceRange, replacementString: composed.string) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: replaceRange, with: composed)
                textStorage.endEditing()
                textView.setSelectedRange(NSRange(location: insertAt + composed.length, length: 0))
                textView.didChangeText()
                isUpdating = false
            }

            syncText()
        }

        func insertMap(serializedMapData: String) {
            guard let mapData = MapBlockData.deserialize(from: serializedMapData),
                  let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            let insertAt = min(textView.selectedRange().location, textStorage.length)
            let nsString = textStorage.string as NSString

            if insertAt > 0 {
                let prevChar = nsString.character(at: insertAt - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }

            composed.append(makeMapAttachment(mapData: mapData))
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            let replaceRange = NSRange(location: insertAt, length: 0)
            if textView.shouldChangeText(in: replaceRange, replacementString: composed.string) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: replaceRange, with: composed)
                textStorage.endEditing()
                textView.setSelectedRange(NSRange(location: insertAt + composed.length, length: 0))
                textView.didChangeText()
                isUpdating = false
            }

            performSynchronizedOverlayLayoutPass(in: textView)
            syncText()
        }

        // MARK: - Table Attachment

        func makeTableAttachment(tableData: NoteTableData) -> NSMutableAttributedString {
            var containerWidth = textView?.textContainer?.containerSize.width ?? 400
            if containerWidth < 1 { containerWidth = 400 }
            // Match card sections: reserve the note-column viewport in text layout, then let the
            // overlay render wide content past that viewport without the old mask gradients.
            let tableWidth = min(tableData.contentWidth, containerWidth)

            let tableHeight = NoteTableOverlayView.computeTableHeight(for: tableData) + 1  // +1 for border
            let addRowButtonPadding: CGFloat = 8 + 24 + 4  // gap + button height + breathing room

            let attachment = NoteTableAttachment(tableData: tableData)
            let cellSize = CGSize(width: tableWidth, height: tableHeight + addRowButtonPadding)
            attachment.attachmentCell = TableSizeAttachmentCell(size: cellSize)
            attachment.bounds = CGRect(origin: .zero, size: cellSize)

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)

            // Block paragraph style — spacingBefore must accommodate the column grab handles
            // that render above the table (overlayInsets.top = 26pt)
            let blockStyle = NSMutableParagraphStyle()
            blockStyle.alignment = .left
            blockStyle.paragraphSpacing = 8
            blockStyle.paragraphSpacingBefore = 30
            attributed.addAttribute(.paragraphStyle, value: blockStyle, range: range)

            return attributed
        }

        private func insertTable() {
            insertTable(with: NoteTableData.empty())
        }

        private func insertTable(with tableData: NoteTableData) {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            let insertAt = min(textView.selectedRange().location, textStorage.length)
            let nsString = textStorage.string as NSString

            // Ensure we start on a new line
            if insertAt > 0 {
                let prevChar = nsString.character(at: insertAt - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }

            // Block-level table attachment
            let tableAttrib = makeTableAttachment(tableData: tableData)
            composed.append(tableAttrib)

            // Newline after so the cursor lands on the next line
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            let replaceRange = NSRange(location: insertAt, length: 0)
            if textView.shouldChangeText(in: replaceRange, replacementString: composed.string) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: replaceRange, with: composed)
                textStorage.endEditing()
                textView.setSelectedRange(NSRange(location: insertAt + composed.length, length: 0))
                textView.didChangeText()
                isUpdating = false
            }

            performSynchronizedOverlayLayoutPass(in: textView)
            syncText()
        }

        // MARK: - Callout Insertion

        func makeCalloutAttachment(calloutData: CalloutData, initialWidth: CGFloat? = nil) -> NSMutableAttributedString {
            // Full container width when `preferredContentWidth` is nil; otherwise clamp stored width to container.
            var containerWidth = textView?.textContainer?.containerSize.width ?? CalloutOverlayView.minWidth
            if containerWidth < 1 { containerWidth = CalloutOverlayView.minWidth }
            let effectiveMin = min(CalloutOverlayView.minWidth, containerWidth)
            let calloutWidth: CGFloat
            if let pref = calloutData.preferredContentWidth {
                calloutWidth = max(effectiveMin, min(containerWidth, pref))
            } else {
                calloutWidth = containerWidth
            }

            let calloutHeight = CalloutOverlayView.heightForData(calloutData, width: calloutWidth)

            let attachment = NoteCalloutAttachment(calloutData: calloutData)
            let cellSize = CGSize(width: calloutWidth, height: calloutHeight)
            attachment.attachmentCell = CalloutSizeAttachmentCell(size: cellSize)
            attachment.bounds = CGRect(origin: .zero, size: cellSize)

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)

            let blockStyle = NSMutableParagraphStyle()
            blockStyle.alignment = .left
            blockStyle.paragraphSpacing = 8
            blockStyle.paragraphSpacingBefore = 8
            attributed.addAttribute(.paragraphStyle, value: blockStyle, range: range)

            return attributed
        }

        func makeDividerAttachment() -> NSMutableAttributedString {
            var containerWidth = textView?.textContainer?.containerSize.width ?? 400
            if containerWidth < 1 { containerWidth = 400 }

            let dividerHeight: CGFloat = 20  // vertical space including line
            let attachment = NoteDividerAttachment(data: nil, ofType: nil)
            let cellSize = CGSize(width: containerWidth, height: dividerHeight)
            attachment.attachmentCell = DividerSizeAttachmentCell(size: cellSize)
            attachment.bounds = CGRect(origin: .zero, size: cellSize)

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)

            let blockStyle = NSMutableParagraphStyle()
            blockStyle.alignment = .left
            blockStyle.paragraphSpacing = 4
            blockStyle.paragraphSpacingBefore = 4
            attributed.addAttribute(.paragraphStyle, value: blockStyle, range: range)

            return attributed
        }

        private func insertCallout(type: CalloutData.CalloutType = .info) {
            let data = CalloutData.empty(type: type)
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            let insertAt = min(textView.selectedRange().location, textStorage.length)
            let nsString = textStorage.string as NSString

            if insertAt > 0 {
                let prevChar = nsString.character(at: insertAt - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }

            let calloutAttrib = makeCalloutAttachment(calloutData: data)
            composed.append(calloutAttrib)
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            let replaceRange = NSRange(location: insertAt, length: 0)
            if textView.shouldChangeText(in: replaceRange, replacementString: composed.string) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: replaceRange, with: composed)
                textStorage.endEditing()
                textView.setSelectedRange(NSRange(location: insertAt + composed.length, length: 0))
                textView.didChangeText()
                isUpdating = false
            }

            performSynchronizedOverlayLayoutPass(in: textView)

            syncText()
        }

        // MARK: - Code Block Insertion

        func makeCodeBlockAttachment(codeBlockData: CodeBlockData) -> NSMutableAttributedString {
            var containerWidth = textView?.textContainer?.containerSize.width ?? CodeBlockOverlayView.minWidth
            if containerWidth < 1 { containerWidth = CodeBlockOverlayView.minWidth }
            let effectiveMin = min(CodeBlockOverlayView.minWidth, containerWidth)
            let blockWidth: CGFloat
            if let pref = codeBlockData.preferredContentWidth {
                blockWidth = max(effectiveMin, min(containerWidth, pref))
            } else {
                blockWidth = containerWidth
            }
            let blockHeight = CodeBlockOverlayView.heightForData(codeBlockData, width: blockWidth)
            let size = CGSize(width: blockWidth, height: blockHeight)
            let attachment = NoteCodeBlockAttachment(codeBlockData: codeBlockData)
            attachment.attachmentCell = CodeBlockSizeAttachmentCell(size: size)
            attachment.bounds = CGRect(origin: .zero, size: size)

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)
            let blockStyle = NSMutableParagraphStyle()
            blockStyle.alignment = .left
            blockStyle.paragraphSpacing = 8
            blockStyle.paragraphSpacingBefore = 8
            attributed.addAttribute(.paragraphStyle, value: blockStyle, range: range)
            return attributed
        }

        private func insertCodeBlock() {
            let data = CodeBlockData.empty()
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            let insertAt = min(textView.selectedRange().location, textStorage.length)
            let nsString = textStorage.string as NSString

            if insertAt > 0 {
                let prevChar = nsString.character(at: insertAt - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }

            composed.append(makeCodeBlockAttachment(codeBlockData: data))
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            let replaceRange = NSRange(location: insertAt, length: 0)
            if textView.shouldChangeText(in: replaceRange, replacementString: composed.string) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: replaceRange, with: composed)
                textStorage.endEditing()
                textView.setSelectedRange(NSRange(location: insertAt + composed.length, length: 0))
                textView.didChangeText()
                isUpdating = false
            }

            performSynchronizedOverlayLayoutPass(in: textView)
            syncText()
        }

        // MARK: - Tabs Container Insertion

        func makeTabsAttachment(tabsData: TabsContainerData) -> NSMutableAttributedString {
            var containerWidth = textView?.textContainer?.containerSize.width ?? TabsContainerOverlayView.minWidth
            if containerWidth < 1 { containerWidth = TabsContainerOverlayView.minWidth }
            let effectiveMin = min(TabsContainerOverlayView.minWidth, containerWidth)
            let tabsWidth: CGFloat
            if let pref = tabsData.preferredContentWidth {
                tabsWidth = max(effectiveMin, min(containerWidth, pref))
            } else {
                tabsWidth = containerWidth
            }
            let height = TabsContainerOverlayView.totalHeight(for: tabsData)
            let size = CGSize(width: tabsWidth, height: height)

            let attachment = NoteTabsAttachment(tabsData: tabsData)
            attachment.attachmentCell = CodeBlockSizeAttachmentCell(size: size)
            attachment.bounds = CGRect(origin: .zero, size: size)

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)
            let blockStyle = NSMutableParagraphStyle()
            blockStyle.alignment = .left
            blockStyle.paragraphSpacing = 8
            blockStyle.paragraphSpacingBefore = 8
            attributed.addAttribute(.paragraphStyle, value: blockStyle, range: range)
            return attributed
        }

        private func insertTabs() {
            let data = TabsContainerData.empty()
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            let insertAt = min(textView.selectedRange().location, textStorage.length)
            let nsString = textStorage.string as NSString

            if insertAt > 0 {
                let prevChar = nsString.character(at: insertAt - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }

            composed.append(makeTabsAttachment(tabsData: data))
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            let replaceRange = NSRange(location: insertAt, length: 0)
            if textView.shouldChangeText(in: replaceRange, replacementString: composed.string) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: replaceRange, with: composed)
                textStorage.endEditing()
                textView.setSelectedRange(NSRange(location: insertAt + composed.length, length: 0))
                textView.didChangeText()
                isUpdating = false
            }

            performSynchronizedOverlayLayoutPass(in: textView)
            syncText()
        }

        // MARK: - Card Section Insertion

        func makeCardSectionAttachment(cardSectionData: CardSectionData) -> NSMutableAttributedString {
            var containerWidth = textView?.textContainer?.containerSize.width ?? CardSectionOverlayView.minWidth
            if containerWidth < 1 { containerWidth = CardSectionOverlayView.minWidth }
            let height = CardSectionOverlayView.totalHeight(for: cardSectionData)
            let size = CGSize(width: containerWidth, height: height)

            let attachment = NoteCardSectionAttachment(cardSectionData: cardSectionData)
            attachment.attachmentCell = CodeBlockSizeAttachmentCell(size: size)
            attachment.bounds = CGRect(origin: .zero, size: size)

            let attributed = NSMutableAttributedString(attachment: attachment)
            let range = NSRange(location: 0, length: attributed.length)
            let blockStyle = NSMutableParagraphStyle()
            blockStyle.alignment = .left
            blockStyle.paragraphSpacing = 8
            blockStyle.paragraphSpacingBefore = 8
            attributed.addAttribute(.paragraphStyle, value: blockStyle, range: range)
            return attributed
        }

        private func insertCardSection() {
            let data = CardSectionData.empty()
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            let insertAt = min(textView.selectedRange().location, textStorage.length)
            let nsString = textStorage.string as NSString

            if insertAt > 0 {
                let prevChar = nsString.character(at: insertAt - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }

            composed.append(makeCardSectionAttachment(cardSectionData: data))
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            let replaceRange = NSRange(location: insertAt, length: 0)
            if textView.shouldChangeText(in: replaceRange, replacementString: composed.string) {
                isUpdating = true
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: replaceRange, with: composed)
                textStorage.endEditing()
                textView.setSelectedRange(NSRange(location: insertAt + composed.length, length: 0))
                textView.didChangeText()
                isUpdating = false
            }

            performSynchronizedOverlayLayoutPass(in: textView)
            syncText()
        }

        private func insertFileAttachment(
            using storedFile: FileAttachmentStorageManager.StoredFile
        ) {
            guard let textView = textView else { return }

            let selectionRange = textView.selectedRange()
            let storageString = textView.textStorage?.string ?? ""
            let nsString = storageString as NSString
            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)

            let displayLabel = AttachmentMarkup.displayLabel(for: storedFile)
            let metadata = FileAttachmentMetadata(
                storedFilename: storedFile.storedFilename,
                originalFilename: storedFile.originalFilename,
                typeIdentifier: storedFile.typeIdentifier,
                displayLabel: displayLabel
            )

            let composed = NSMutableAttributedString()

            if needsLeadingSpace(before: selectionRange, in: nsString) {
                let leadingSpace = NSAttributedString(string: " ", attributes: baseAttributes)
                composed.append(leadingSpace)
            }

            let attachment = makeFileAttachment(metadata: metadata)
            composed.append(attachment)

            if needsTrailingSpace(after: selectionRange, in: nsString) {
                let trailingSpace = NSAttributedString(string: " ", attributes: baseAttributes)
                composed.append(trailingSpace)
            }

            replaceSelection(with: composed)
            syncText()
        }

        private func needsLeadingSpace(before range: NSRange, in text: NSString) -> Bool {
            guard range.location > 0 else { return false }
            let previousIndex = range.location - 1
            let previousCharacter = text.character(at: previousIndex)
            guard let scalar = UnicodeScalar(previousCharacter) else { return false }
            return !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }

        private func needsTrailingSpace(after range: NSRange, in text: NSString) -> Bool {
            let endIndex = range.location + range.length
            if endIndex >= text.length {
                return true
            }
            let nextCharacter = text.character(at: endIndex)
            guard let scalar = UnicodeScalar(nextCharacter) else { return false }
            return !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }

        private func replaceSelection(with attributed: NSAttributedString) {
            guard let textView = textView else { return }
            var range = textView.selectedRange()
            let storageLength = textView.textStorage?.length ?? 0

            if range.location == NSNotFound {
                range = NSRange(location: storageLength, length: 0)
                textView.setSelectedRange(range)
            } else {
                if range.location > storageLength {
                    range.location = storageLength
                    range.length = 0
                    textView.setSelectedRange(range)
                } else if range.location + range.length > storageLength {
                    range.length = max(0, storageLength - range.location)
                    textView.setSelectedRange(range)
                }
            }

            if textView.shouldChangeText(in: range, replacementString: attributed.string) {
                isUpdating = true
                textView.textStorage?.beginEditing()
                textView.textStorage?.replaceCharacters(in: range, with: attributed)
                textView.textStorage?.endEditing()
                textView.setSelectedRange(
                    NSRange(location: range.location + attributed.length, length: 0))
                textView.didChangeText()
                isUpdating = false
            }
        }

        func syncText(editedRange: NSRange? = nil) {
            guard textView != nil, !readOnly else { return }
            isUpdating = true
            styleTodoParagraphs(editedRange: editedRange)
            isUpdating = false

            // Debounce serialization to avoid O(n) attribute enumeration on every keystroke.
            // styleTodoParagraphs runs synchronously above for visual correctness; only the
            // binding update is deferred.
            serializeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.textView != nil else { return }
                let serialized = self.serialize()
                if serialized != self.lastSerialized {
                    self.lastSerialized = serialized
                    self.textBinding.wrappedValue = serialized
                }
            }
            serializeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)

            // Coalesce overlay updates through the shared debounce —
            // scheduleOverlayUpdate already cancels and reschedules correctly
            scheduleOverlayUpdate()
        }

        /// Test-only: cancel any pending debounced serialization and run it
        /// synchronously. The 150 ms `serializeWorkItem` debounce above is the
        /// right trade-off for production (coalesces keystroke-driven binding
        /// writes so `serialize()` doesn't enumerate attributes on every
        /// character) but it races the tight run-loop pump that unit tests use
        /// to exercise the insert pipeline. Tests call this after pumping the
        /// main loop so they can assert on the binding state deterministically.
        /// This is a no-op in any code path that doesn't call it — production
        /// behavior is unchanged.
        func flushPendingSerialization() {
            serializeWorkItem?.cancel()
            serializeWorkItem = nil
            guard textView != nil else { return }
            let serialized = serialize()
            if serialized != lastSerialized {
                lastSerialized = serialized
                textBinding.wrappedValue = serialized
            }
        }

        // MARK: - Inline Image Overlay Management

        // `update*Overlays(in:)` / `updateDividerAttachments(in:)` moved to `TodoEditorRepresentable+OverlayManagement.swift` (Batch 5).

        func updateImageRatio(
            _ newRatio: CGFloat,
            attachment: NoteImageAttachment,
            in textStorage: NSTextStorage,
            textView: NSTextView
        ) {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            var foundRange: NSRange?
            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, stop in
                if val as AnyObject === attachment {
                    foundRange = range
                    stop.pointee = true
                }
            }
            guard let charRange = foundRange else { return }

            // Get image size for aspect ratio
            let imageSize: CGSize
            if let overlay = imageOverlays[ObjectIdentifier(attachment)],
               let img = overlay.image {
                imageSize = img.size
            } else {
                imageSize = CGSize(width: 4, height: 3)
            }

            let containerWidth = textView.textContainer?.containerSize.width ?? 400
            let displayWidth = containerWidth * newRatio
            let aspectRatio = imageSize.height / imageSize.width
            let displayHeight = displayWidth * aspectRatio

            attachment.widthRatio = newRatio
            let cellSize = CGSize(width: displayWidth, height: displayHeight)
            attachment.attachmentCell = ImageSizeAttachmentCell(size: cellSize)
            attachment.bounds = CGRect(origin: .zero, size: cellSize)

            textStorage.beginEditing()
            textStorage.addAttribute(.imageWidthRatio, value: newRatio, range: charRange)
            textStorage.endEditing()

            textView.layoutManager?.invalidateLayout(
                forCharacterRange: charRange, actualCharacterRange: nil)

            syncText()
        }

        func updateMapData(
            _ newData: MapBlockData,
            attachment: NoteMapAttachment,
            in textStorage: NSTextStorage,
            textView: NSTextView
        ) {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            var foundRange: NSRange?
            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, stop in
                if value as AnyObject === attachment {
                    foundRange = range
                    stop.pointee = true
                }
            }
            guard let charRange = foundRange else { return }

            attachment.mapData = newData

            let containerWidth = textView.textContainer?.containerSize.width ?? 400
            let displayWidth = resolvedMapBlockWidth(
                for: newData.widthRatio,
                containerWidth: containerWidth
            )
            let displayHeight = displayWidth * MapBlockData.aspectHeightRatio
            let cellSize = CGSize(width: displayWidth, height: displayHeight)

            attachment.attachmentCell = MapSizeAttachmentCell(size: cellSize, mapData: newData)
            attachment.bounds = CGRect(origin: .zero, size: cellSize)

            textStorage.beginEditing()
            textStorage.addAttribute(.mapSerializedData, value: newData.serialize(), range: charRange)
            textStorage.endEditing()

            textView.layoutManager?.invalidateLayout(
                forCharacterRange: charRange,
                actualCharacterRange: nil
            )

            syncText()
        }

        // MARK: - NSLayoutManagerDelegate

        nonisolated func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
            properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
            characterIndexes charIndexes: UnsafePointer<Int>,
            font: NSFont,
            forGlyphRange glyphRange: NSRange
        ) -> Int {
            // Collapsed-heading glyph hiding was removed with the old collapsible-section feature;
            // keep the delegate hook so AppKit can call through without custom glyph substitution.
            return 0
        }

        nonisolated func layoutManager(
            _ layoutManager: NSLayoutManager,
            didCompleteLayoutFor textContainer: NSTextContainer?,
            atEnd layoutFinishedFlag: Bool
        ) {
            guard layoutFinishedFlag else { return }
            Task { @MainActor [weak self] in
                self?.scheduleOverlayUpdate()
            }
        }

        /// Facade for `NoteParagraphStyler.fixInconsistentFonts`. Keeps the existing call sites
        /// unchanged while the body lives in a sibling file. Manages `isUpdating` here (the
        /// extracted function stays Coordinator-agnostic).
        private func fixInconsistentFonts(in scopeRange: NSRange? = nil) {
            guard let textStorage = textView?.textStorage else { return }
            // Suppress textDidChange during font corrections to prevent
            // re-scheduling this function in an infinite 300ms loop
            isUpdating = true
            defer { isUpdating = false }
            NoteParagraphStyler.fixInconsistentFonts(
                in: textStorage,
                scopeRange: scopeRange,
                expectedAttributes: Self.baseTypingAttributes(for: currentColorScheme)
            )
        }

        /// Facade for `NoteParagraphStyler.styleTodoParagraphs`. Existing call sites call this
        /// method on the Coordinator; the implementation lives in a sibling file for testability.
        private func styleTodoParagraphs(editedRange: NSRange? = nil) {
            guard let textStorage = textView?.textStorage else { return }
            NoteParagraphStyler.styleTodoParagraphs(in: textStorage, editedRange: editedRange)
        }

        private func isInTodoParagraph(range: NSRange) -> Bool {
            guard let storage = textView?.textStorage, storage.length > 0 else { return false }
            let location = max(0, min(storage.length - 1, range.location))
            let paragraphRange = (storage.string as NSString).paragraphRange(
                for: NSRange(location: location, length: 0))
            var isTodo = false
            storage.enumerateAttribute(
                .attachment,
                in: NSRange(
                    location: paragraphRange.location, length: min(1, paragraphRange.length)),
                options: []
            ) { value, _, _ in
                if (value as? NSTextAttachment)?.attachmentCell is TodoCheckboxAttachmentCell {
                    isTodo = true
                }
            }
            return isTodo
        }

        /// Returns true if the cursor is inside a bullet list paragraph ("• " prefix)
        private func isInBulletParagraph(range: NSRange) -> Bool {
            guard let storage = textView?.textStorage else { return false }
            let location = max(0, min(storage.length, range.location))
            let paraRange = (storage.string as NSString).paragraphRange(
                for: NSRange(location: location, length: 0))
            let text = (storage.string as NSString).substring(with: paraRange)
            return text.hasPrefix("• ")
        }

        /// Returns true if the cursor is inside a block quote paragraph
        private func isInBlockQuoteParagraph(range: NSRange) -> Bool {
            guard let storage = textView?.textStorage else { return false }
            guard storage.length > 0 else { return false }
            var location = max(0, min(storage.length, range.location))
            // When cursor is at the very end of storage (no trailing newline),
            // check the attribute on the last character instead of bailing out
            if location >= storage.length { location = storage.length - 1 }
            return storage.attribute(.blockQuote, at: location, effectiveRange: nil) as? Bool == true
        }

        /// Returns the ordered list number if cursor is in a numbered list paragraph, nil otherwise
        private func orderedListNumber(at range: NSRange) -> Int? {
            guard let storage = textView?.textStorage else { return nil }
            let location = max(0, min(storage.length, range.location))
            let paraRange = (storage.string as NSString).paragraphRange(
                for: NSRange(location: location, length: 0))
            guard paraRange.length > 0, paraRange.location < storage.length else { return nil }
            return storage.attribute(.orderedListNumber, at: paraRange.location, effectiveRange: nil) as? Int
        }

        /// Returns the length of the "N. " prefix for a given list number
        private func orderedListPrefixLength(for number: Int) -> Int {
            return "\(number). ".count
        }

        /// Facade for `NoteSerializer.serialize(_:)`. Keeps the 3 existing call sites
        /// (`syncText`, `applyInitialText`, debounced serialize pipeline) unchanged while the
        /// attachment-aware serializer body lives in a sibling file for testability.
        private func serialize() -> String {
            guard let storage = textView?.textStorage else { return "" }
            return NoteSerializer.serialize(storage)
        }

        // `deserialize(_ text: String) -> NSAttributedString` moved to
        // `TodoEditorRepresentable+Deserializer.swift` (Batch 4).

        // MARK: - Helpers

        static func baseParagraphStyle() -> NSParagraphStyle {
            let spacing = ThemeManager.currentLineSpacing()
            // Scale min/max line height proportionally so the multiplier
            // actually produces visible differences (1.2x is the reference).
            let scaledHeight = baseLineHeight * spacing.multiplier / 1.2
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = spacing.multiplier
            style.minimumLineHeight = scaledHeight
            style.maximumLineHeight = scaledHeight + 4
            style.paragraphSpacing = 8
            return style
        }

        static func todoParagraphStyle() -> NSParagraphStyle {
            let spacing = ThemeManager.currentLineSpacing()
            // Never shrink below checkboxIconSize or the checkbox clips
            let scaledHeight = max(checkboxIconSize, checkboxIconSize * spacing.multiplier / 1.2)
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = spacing.multiplier
            style.minimumLineHeight = scaledHeight
            style.maximumLineHeight = scaledHeight
            style.paragraphSpacing = 4
            style.firstLineHeadIndent = 0
            // Indent wrapped lines to align with text after checkbox
            // checkboxAttachmentWidth (30) + approximate width of 2 spaces (~8pt at body size)
            style.headIndent = checkboxAttachmentWidth + 8
            return style
        }

        static func orderedListParagraphStyle() -> NSParagraphStyle {
            let spacing = ThemeManager.currentLineSpacing()
            let scaledHeight = baseLineHeight * spacing.multiplier / 1.2
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = spacing.multiplier
            style.minimumLineHeight = scaledHeight
            style.maximumLineHeight = scaledHeight + 4
            style.paragraphSpacing = 4
            // Indent wrapping lines to align with text after "N. "
            style.firstLineHeadIndent = 0
            style.headIndent = 22  // Approximate width of "1. " in body font
            return style
        }

        static func blockQuoteParagraphStyle() -> NSParagraphStyle {
            let spacing = ThemeManager.currentLineSpacing()
            let scaledHeight = baseLineHeight * spacing.multiplier / 1.2
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = spacing.multiplier
            style.minimumLineHeight = scaledHeight
            style.maximumLineHeight = scaledHeight + 4
            style.paragraphSpacing = 8
            style.firstLineHeadIndent = 20
            style.headIndent = 20
            style.tailIndent = -4
            style.lineBreakMode = .byWordWrapping
            return style
        }

        // Paragraph style for web clip attachments — matches base style so line
        // heights stay consistent whether the clip is inline or on its own line.
        static func webClipParagraphStyle() -> NSParagraphStyle {
            return baseParagraphStyle()
        }
        
        /// Positions rasterized pill images on the body baseline row. Pure cap-height centering
        /// drifts from the paragraph line box used by ``baseParagraphStyle()``; blending the two
        /// plus sub-point constants aligns SF capsules with Charter line metrics after ImageRenderer.
        static func imageTagVerticalOffset(for height: CGFloat) -> CGFloat {
            let spacing = ThemeManager.currentLineSpacing()
            let paragraphLine = baseLineHeight * spacing.multiplier / 1.2
            let cap = textFont.capHeight
            let centeredOnCap = (cap - height) / 2.0
            let centeredOnLine = (paragraphLine - height) / 2.0
            let blended = centeredOnCap * 0.4375 + centeredOnLine * 0.5625
            let opticalFineTune: CGFloat = 0.09375
            return blended + opticalFineTune
        }

        // `headingLevel(for:)` moved to `NoteParagraphStyler.headingLevel(for:)`.

        /// Access promoted from `private` to internal for `NoteSerializer`.
        static func nsColorToHex(_ color: NSColor) -> String {
            let c = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? color
            return String(format: "%02x%02x%02x",
                          Int(round(c.redComponent * 255)),
                          Int(round(c.greenComponent * 255)),
                          Int(round(c.blueComponent * 255)))
        }

        static func baseTypingAttributes(for colorScheme: ColorScheme? = nil)
            -> [NSAttributedString.Key: Any]
        {
            return [
                .font: textFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: baseParagraphStyle(),
                .underlineStyle: 0,
            ]
        }

        /// Builds an attribute dictionary that applies inline formatting state on top of the
        /// base typing attributes. Used during deserialization to reconstruct rich text.
        static func formattingAttributes(
            base colorScheme: ColorScheme?,
            heading: TextFormattingManager.HeadingLevel,
            bold: Bool, italic: Bool,
            underline: Bool, strikethrough: Bool,
            alignment: NSTextAlignment
        ) -> [NSAttributedString.Key: Any] {
            var attrs = baseTypingAttributes(for: colorScheme)

            // Font: heading or body with traits
            if heading != .none {
                let weight: FontManager.Weight = heading.fontWeight == .semibold ? .semibold : .regular
                attrs[.font] = FontManager.headingNS(size: heading.fontSize, weight: weight)
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.paragraphSpacingBefore = 8
                paraStyle.paragraphSpacing = 12
                if alignment != .left { paraStyle.alignment = alignment }
                attrs[.paragraphStyle] = paraStyle
            } else {
                var font = attrs[.font] as? NSFont ?? textFont
                if bold   { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                attrs[.font] = font

                if alignment != .left {
                    let paraStyle = (attrs[.paragraphStyle] as? NSParagraphStyle)?
                        .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    paraStyle.alignment = alignment
                    attrs[.paragraphStyle] = paraStyle
                }
            }

            attrs[.underlineStyle] = underline ? NSUnderlineStyle.single.rawValue : 0
            if strikethrough {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.foregroundColor] = checkedTodoTextColor
            } else {
                attrs[.strikethroughStyle] = 0
            }

            return attrs
        }

        private static func baselineOffset(forLineHeight lineHeight: CGFloat, font: NSFont)
            -> CGFloat
        {
            let metrics = font.ascender - font.descender + font.leading
            let delta = max(0, lineHeight - metrics)
            return delta / 2
        }

        // MARK: - Writing Tools Support (macOS 15+)
        @available(macOS 15.0, *)
        func textViewWritingToolsWillBegin(_ textView: NSTextView) {
            // Store text before Writing Tools starts, suppress sync during session
            textBeforeWritingTools = textView.string
            isUpdating = true
        }

        @available(macOS 15.0, *)
        func textViewWritingToolsDidEnd(_ textView: NSTextView) {
            // Unconditional reset — Writing Tools owns the outermost session frame.
            // Internal shouldChangeText/textDidChange pairs may have nested the counter
            // during the session; the session boundary itself must be authoritative.
            _updatingCount = 0
            // Writing Tools may strip custom attributes (todoChecked, foregroundColor)
            // from todo paragraphs while preserving the attachment cells themselves.
            // Re-apply checked styling so the visual state matches the cell's isChecked flag.
            styleTodoParagraphs()
            syncText()
        }
    }
}

final class InlineNSTextView: NSTextView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    // Per-instance menu state for keyboard event handling (avoids cross-editor contamination in split views)
    var isCommandMenuShowing = false {
        didSet {
            // Reset filter state on open/close transitions so the placeholder
            // starts in its "empty filter → show ghost" state on reopen and
            // doesn't briefly flash a stale filter from a previous session.
            if isCommandMenuShowing != oldValue {
                commandMenuFilterText = ""
            }
            updateCommandMenuPlaceholder()
        }
    }
    var commandSlashLocation: Int = -1 {
        didSet { updateCommandMenuPlaceholder() }
    }

    /// Current filter text typed after the slash. Drives the "Type to search"
    /// ghost placeholder visibility — when empty AND the menu is showing,
    /// the placeholder is drawn next to the slash; as soon as the user types
    /// a filter character, the placeholder hides. Mirrors the filter text
    /// broadcast over `.commandMenuFilterUpdate`.
    var commandMenuFilterText: String = "" {
        didSet { updateCommandMenuPlaceholder() }
    }

    /// When a block-attachment redirect manually inserts "@", the text view's
    /// pre-insert selection is stale for anchoring the picker. The coordinator
    /// records the actual inserted character location here during `shouldChangeTextIn`
    /// so `insertText` can anchor the first picker to the normalized landing line.
    var redirectedNotePickerLocation: Int?

    /// Ghost placeholder NSTextField shown next to the "/" when the command
    /// menu opens. Subview of the text view itself, positioned in text-view-
    /// local coordinates via `updateCommandMenuPlaceholder()`.
    private var commandMenuPlaceholderField: NSTextField?

    // URL paste menu state
    var isURLPasteMenuShowing = false
    var isCodePasteMenuShowing = false

    // Note picker state (triggered by "@")
    var isNotePickerShowing = false
    var notePickerAtLocation: Int = -1

    /// When true, mouseMoved sets arrow cursor instead of allowing NSTextView's I-beam.
    /// Set by ContentView when any full-screen panel overlay (settings, search, trash) is open.
    /// NOTE: This is a static var which means all editor instances share the same flag.
    /// If multiple editors exist simultaneously, this flag would incorrectly apply to all of them.
    /// A future improvement would be to make this an instance var propagated via notification.
    static var isPanelOverlayActive = false

    weak var actionDelegate: TodoEditorRepresentable.Coordinator?
    var editorInstanceID: UUID?

    // MARK: - Quick Look

    /// Set before calling QLPreviewPanel.shared.makeKeyAndOrderFront(nil).
    var quickLookPreviewURL: URL?
    var quickLookStopAccessingHandler: (() -> Void)?
    private var qlClickOutsideMonitor: Any?

    func setQuickLookPreview(url: URL, stopAccessing: (() -> Void)? = nil) {
        releaseQuickLookPreviewAccess()
        quickLookPreviewURL = url
        quickLookStopAccessingHandler = stopAccessing
    }

    func releaseQuickLookPreviewAccess() {
        quickLookStopAccessingHandler?()
        quickLookStopAccessingHandler = nil
    }

    func clearQuickLookPreview() {
        releaseQuickLookPreviewAccess()
        quickLookPreviewURL = nil
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return quickLookPreviewURL != nil
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self

        // Dismiss the panel when clicking outside it.
        qlClickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak panel] event in
            guard let panel = panel else { return event }
            if event.window !== panel {
                panel.close()
            }
            return event
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        clearQuickLookPreview()
        if let monitor = qlClickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            qlClickOutsideMonitor = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return quickLookPreviewURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        return quickLookPreviewURL as? NSURL
    }
    private var hoverTrackingArea: NSTrackingArea?

    /// Set during paste operations so the coordinator can skip the typing animation.
    var isPasting = false

    override func paste(_ sender: Any?) {
        // Intercept clipboard images (screenshots, copy from Photos, etc.)
        // These arrive as TIFF/PNG data and must be saved as files before insertion,
        // otherwise they become inline NSTextAttachments that are lost on serialize.
        let pb = NSPasteboard.general
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        if let imageType = imageTypes.first(where: { pb.data(forType: $0) != nil }),
           let imageData = pb.data(forType: imageType),
           let image = NSImage(data: imageData) {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let filename = await ImageStorageManager.shared.saveImageData(image) {
                    self.actionDelegate?.insertImage(filename: filename)
                }
            }
            return
        }

        isPasting = true

        // Try RTF paste: preserve bold/italic/underline/links from external rich text
        if let rtfData = pb.data(forType: .rtf) ?? pb.data(forType: NSPasteboard.PasteboardType.rtfd),
           let richText = NSAttributedString(rtf: rtfData, documentAttributes: nil),
           richText.length > 0,
           let storage = textStorage {
            let mapped = Self.mapExternalRichText(richText)
            let insertRange = selectedRange()
            if shouldChangeText(in: insertRange, replacementString: mapped.string) {
                storage.beginEditing()
                storage.replaceCharacters(in: insertRange, with: mapped)
                storage.endEditing()
                didChangeText()
                setSelectedRange(NSRange(location: insertRange.location + mapped.length, length: 0))
            }
            isPasting = false
            return
        }

        let pastedText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isURL = Self.isLikelyURL(pastedText)
        let beforeLocation = selectedRange().location

        super.paste(sender)
        isPasting = false

        if isURL && !pastedText.isEmpty {
            let afterLocation = selectedRange().location
            let pastedLength = afterLocation - beforeLocation
            let storageLen = textStorage?.length ?? 0
            if pastedLength > 0, beforeLocation + pastedLength <= storageLen {
                let pastedRange = NSRange(location: beforeLocation, length: pastedLength)

                // Style the pasted URL with blue text
                textStorage?.addAttribute(
                    .foregroundColor, value: NSColor.controlAccentColor, range: pastedRange)

                // Calculate position for the option menu
                if let layoutManager = layoutManager, let textContainer = textContainer {
                    let glyphRange = layoutManager.glyphRange(
                        forCharacterRange: pastedRange, actualCharacterRange: nil)
                    let rect = layoutManager.boundingRect(
                        forGlyphRange: glyphRange, in: textContainer)
                    let adjustedRect = CGRect(
                        x: rect.origin.x + textContainerOrigin.x,
                        y: rect.origin.y + textContainerOrigin.y,
                        width: rect.width,
                        height: rect.height
                    )

                    let eid = self.editorInstanceID
                    DispatchQueue.main.async {
                        var payload: [String: Any] = [
                            "url": pastedText,
                            "range": NSValue(range: pastedRange),
                            "rect": NSValue(rect: adjustedRect),
                        ]
                        if let eid = eid { payload["editorInstanceID"] = eid }
                        NotificationCenter.default.post(
                            name: .urlPasteDetected,
                            object: payload
                        )
                    }
                }
            }
        }

        // Code paste detection — only if URL detection didn't trigger
        if !isURL && !pastedText.isEmpty {
            let pb = NSPasteboard.general
            let hasCodeType = pb.types?.contains(where: { type in
                let raw = type.rawValue
                return raw == "com.apple.dt.Xcode.pboard.source-code"
                    || raw == "public.source-code"
            }) ?? false

            let (isCode, language) = hasCodeType
                ? (true, Self.detectCodeLanguage(pastedText))
                : Self.isLikelyCode(pastedText)

            if isCode {
                let afterLocation = selectedRange().location
                let pastedLength = afterLocation - beforeLocation
                let codeStorageLen = textStorage?.length ?? 0
                if pastedLength > 0, beforeLocation + pastedLength <= codeStorageLen {
                    let pastedRange = NSRange(location: beforeLocation, length: pastedLength)

                    let insertedText: String
                    if let storage = textStorage,
                       pastedRange.location + pastedRange.length <= storage.length {
                        insertedText = (storage.string as NSString).substring(with: pastedRange)
                    } else {
                        insertedText = pastedText
                    }

                    textStorage?.addAttribute(
                        .backgroundColor,
                        value: NSColor.labelColor.withAlphaComponent(0.08),
                        range: pastedRange)

                    if let layoutManager = layoutManager, let textContainer = textContainer {
                        let glyphRange = layoutManager.glyphRange(
                            forCharacterRange: pastedRange, actualCharacterRange: nil)
                        let rect = layoutManager.boundingRect(
                            forGlyphRange: glyphRange, in: textContainer)
                        let adjustedRect = CGRect(
                            x: rect.origin.x + textContainerOrigin.x,
                            y: rect.origin.y + textContainerOrigin.y,
                            width: rect.width,
                            height: rect.height
                        )

                        let eid = self.editorInstanceID
                        DispatchQueue.main.async {
                            var payload: [String: Any] = [
                                "code": insertedText,
                                "range": NSValue(range: pastedRange),
                                "rect": NSValue(rect: adjustedRect),
                                "language": language,
                            ]
                            if let eid = eid { payload["editorInstanceID"] = eid }
                            NotificationCenter.default.post(
                                name: .codePasteDetected,
                                object: payload
                            )
                        }
                    }
                }
            }
        }
    }

    /// Maps external rich text (from Safari, Pages, Word, etc.) to Jot's font stack
    /// while preserving bold, italic, underline, strikethrough, and links.
    private static func mapExternalRichText(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = FontManager.bodyNS()
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length), options: []) { attrs, range, _ in
            let text = (source.string as NSString).substring(with: range)
            var mapped: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: NSColor.labelColor,
            ]

            // Preserve bold/italic from external font
            if let extFont = attrs[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: extFont)
                var font = bodyFont
                if traits.contains(.boldFontMask) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                if traits.contains(.italicFontMask) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                mapped[.font] = font
            }

            // Preserve underline
            if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                mapped[.underlineStyle] = underline
            }

            // Preserve strikethrough
            if let strikethrough = attrs[.strikethroughStyle] as? Int, strikethrough != 0 {
                mapped[.strikethroughStyle] = strikethrough
            }

            // Preserve links
            if let link = attrs[.link] {
                mapped[.link] = link
                mapped[.foregroundColor] = NSColor.controlAccentColor
                mapped[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            result.append(NSAttributedString(string: text, attributes: mapped))
        }
        return result
    }

    static func isLikelyURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else {
            return false
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }
        let fullRange = NSRange(location: 0, length: (trimmed as NSString).length)
        let matches = detector.matches(in: trimmed, options: [], range: fullRange)
        // The detected link must span the entire trimmed text
        return matches.count == 1 && matches[0].range.location == 0 && matches[0].range.length == fullRange.length
    }

    /// Extracts the first URL found within arbitrary text using NSDataDetector.
    static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let fullRange = NSRange(location: 0, length: (trimmed as NSString).length)
        return detector.firstMatch(in: trimmed, options: [], range: fullRange)?.url
    }

    /// Detect if pasted text is likely source code.
    private static func isLikelyCode(_ text: String) -> (isCode: Bool, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "plaintext") }

        let lines = trimmed.components(separatedBy: .newlines)
        let isMultiline = lines.count > 1

        // Strong signals — any one sufficient for multi-line, required for single-line
        let strongPatterns: [String] = [
            #"^import\s+"#, #"^from\s+\S+\s+import"#,
            #"^func\s+"#, #"^def\s+"#, #"^class\s+"#, #"^struct\s+"#,
            #"^enum\s+"#, #"^#include\s+"#, #"^package\s+"#,
            #"^use\s+"#, #"^module\s+"#,
            #"=>\s*\{"#, #"->\s*\{"#,
        ]
        let lineEndPatterns: [String] = [
            #"\{\s*$"#, #"\};\s*$"#,
        ]

        var strongCount = 0
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            for pattern in strongPatterns {
                if t.range(of: pattern, options: .regularExpression) != nil {
                    strongCount += 1
                    break
                }
            }
            for pattern in lineEndPatterns {
                if t.range(of: pattern, options: .regularExpression) != nil {
                    strongCount += 1
                    break
                }
            }
        }

        // Medium signals — need 2+ to trigger
        var mediumCount = 0
        let fullText = trimmed

        if fullText.contains("{") && fullText.contains("}") { mediumCount += 1 }
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix(";") }) { mediumCount += 1 }
        if fullText.contains("->") { mediumCount += 1 }
        if lines.contains(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("//") || (t.hasPrefix("#") && !t.hasPrefix("# ") && !t.hasPrefix("## "))
        }) { mediumCount += 1 }
        if fullText.range(of: #"(let|var|const|val)\s+\w+\s*="#, options: .regularExpression) != nil { mediumCount += 1 }
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if nonEmptyLines.count > 1 {
            let indentedCount = nonEmptyLines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
            if Double(indentedCount) / Double(nonEmptyLines.count) >= 0.5 { mediumCount += 1 }
        }
        // Function call pattern: word immediately followed by ( with no space
        // (excludes prose like "the function (which is called)")
        if fullText.range(of: #"\w+\([^)]*\)"#, options: .regularExpression) != nil { mediumCount += 1 }

        // Negative signals
        var negativeCount = 0
        for line in lines {
            let words = line.split(separator: " ")
            let hasOperators = line.contains("{") || line.contains("}") || line.contains(";")
                || line.contains("=") || line.contains("(") || line.contains("->")
            if words.count >= 5 && !hasOperators {
                negativeCount += 1
            }
        }
        if lines.contains(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }) { negativeCount += 1 }
        if trimmed.count < 8 && strongCount == 0 { return (false, "plaintext") }

        let isCode: Bool
        if isMultiline {
            isCode = strongCount > 0 || (mediumCount >= 2 && negativeCount < nonEmptyLines.count / 2)
        } else {
            isCode = strongCount > 0
        }

        if !isCode { return (false, "plaintext") }
        let language = detectCodeLanguage(trimmed)
        return (true, language)
    }

    /// Detect programming language from keyword clusters.
    private static func detectCodeLanguage(_ text: String) -> String {
        struct LangScore {
            let language: String
            let exclusiveKeywords: [String]
            let keywords: [String]
        }

        let languages: [LangScore] = [
            LangScore(language: "swift", exclusiveKeywords: ["guard ", "@State", "@Published", "import SwiftUI", "import UIKit"], keywords: ["func ", "let ", "var "]),
            LangScore(language: "go", exclusiveKeywords: [":=", "fmt.", "go func", "package main"], keywords: ["func ", "package "]),
            LangScore(language: "python", exclusiveKeywords: ["elif ", "__init__", "self."], keywords: ["def ", "import "]),
            LangScore(language: "javascript", exclusiveKeywords: ["===", "console.log", "require("], keywords: ["function ", "const ", "=> "]),
            LangScore(language: "typescript", exclusiveKeywords: [": string", ": number", ": boolean", "interface "], keywords: ["function ", "const ", "=> "]),
            LangScore(language: "rust", exclusiveKeywords: ["fn ", "mut ", "impl ", "pub fn"], keywords: ["::"]),
            LangScore(language: "java", exclusiveKeywords: ["public static void", "System.out", "@Override"], keywords: ["class ", "import "]),
            LangScore(language: "cpp", exclusiveKeywords: ["#include", "std::", "nullptr", "int main"], keywords: ["::", "cout"]),
            LangScore(language: "sql", exclusiveKeywords: ["SELECT ", "INSERT INTO", "CREATE TABLE"], keywords: ["FROM ", "WHERE ", "JOIN "]),
            LangScore(language: "html", exclusiveKeywords: ["<div", "<span", "<html", "className="], keywords: ["</"]),
            LangScore(language: "css", exclusiveKeywords: ["font-size:", "margin:", "padding:", "display:"], keywords: ["{", "}"]),
            LangScore(language: "bash", exclusiveKeywords: ["#!/bin/bash", "#!/bin/sh"], keywords: ["echo ", "export "]),
            LangScore(language: "ruby", exclusiveKeywords: ["puts ", "require '", "attr_accessor"], keywords: ["def ", "end"]),
        ]

        var bestLang = "plaintext"
        var bestScore = 0

        for lang in languages {
            var score = 0
            for kw in lang.exclusiveKeywords {
                if text.contains(kw) { score += 3 }
            }
            for kw in lang.keywords {
                if text.contains(kw) { score += 1 }
            }
            if score > bestScore {
                bestScore = score
                bestLang = lang.language
            }
        }

        return bestScore > 0 ? bestLang : "plaintext"
    }

    override func pasteAsPlainText(_ sender: Any?) {
        isPasting = true
        let pastedText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isURL = Self.isLikelyURL(pastedText)
        let beforeLocation = selectedRange().location

        super.pasteAsPlainText(sender)
        isPasting = false

        // Run URL detection on plain-text paste too (Cmd+Shift+V)
        if isURL && !pastedText.isEmpty {
            let afterLocation = selectedRange().location
            let pastedLength = afterLocation - beforeLocation
            let storageLen = textStorage?.length ?? 0
            if pastedLength > 0, beforeLocation + pastedLength <= storageLen {
                let pastedRange = NSRange(location: beforeLocation, length: pastedLength)
                textStorage?.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: pastedRange)

                if let layoutManager = layoutManager, let textContainer = textContainer {
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: pastedRange, actualCharacterRange: nil)
                    let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    let adjustedRect = CGRect(
                        x: rect.origin.x + textContainerOrigin.x,
                        y: rect.origin.y + textContainerOrigin.y,
                        width: rect.width, height: rect.height)

                    let eid = self.editorInstanceID
                    DispatchQueue.main.async {
                        var payload: [String: Any] = [
                            "url": pastedText,
                            "range": NSValue(range: pastedRange),
                            "rect": NSValue(rect: adjustedRect),
                        ]
                        if let eid = eid { payload["editorInstanceID"] = eid }
                        NotificationCenter.default.post(name: .urlPasteDetected, object: payload)
                    }
                }
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager,
            let textContainer = textContainer
        else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = usedRect.height + textContainerInset.height * 2

        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        registerForDraggedTypes([.fileURL])
        // When removed from the window hierarchy, stop the typing animation timer
        // to prevent a 60Hz timer from leaking if the text view is deallocated
        // while animations are still in flight.
        if window == nil {
            (layoutManager as? TypingAnimationLayoutManager)?.clearAllAnimations()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [
            .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        // When a full-screen panel (settings/search/trash) covers the editor,
        // suppress the I-beam entirely — show arrow instead.
        if Self.isPanelOverlayActive {
            NSCursor.arrow.set()
            return
        }
        // If another view (e.g., overlay toolbar buttons) owns this point,
        // don't force I-beam — let that view's cursor rects take effect.
        if let contentView = window?.contentView {
            let hitView = contentView.hitTest(event.locationInWindow)
            if let hitView, hitView !== self, !hitView.isDescendant(of: self) {
                return
            }
        }
        // Check image overlay edges BEFORE calling super — NSTextView's
        // mouseMoved forcibly resets the cursor to i-beam, overriding any
        // cursor rects on subviews. Suppressing super is the only way to win.
        if let cursor = actionDelegate?.resizeCursorForPoint(event.locationInWindow) {
            cursor.set()
            return
        }
        // Link hover: use containment-gated handleAttachmentHover as single
        // source of truth. Must check BEFORE super.mouseMoved — NSTextView's
        // implementation forcibly resets the cursor to I-beam.
        let mousePoint = convert(event.locationInWindow, from: nil)
        if actionDelegate?.handleAttachmentHover(at: mousePoint, in: self) == true {
            NSCursor.pointingHand.set()
            return
        }

        super.mouseMoved(with: event)
        actionDelegate?.endAttachmentHover()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        actionDelegate?.endAttachmentHover()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            insertionPointColor = NSColor.controlAccentColor
            needsDisplay = true
            if let eid = self.editorInstanceID {
                NotificationCenter.default.post(
                    name: .editorDidBecomeFirstResponder,
                    object: nil,
                    userInfo: ["editorInstanceID": eid]
                )
            }
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if actionDelegate?.handleAttachmentClick(at: point, in: self) == true {
            return
        }

        // Notelink click: navigate to linked note.
        // Use layout-manager-based hit testing (same approach as handleAttachmentClick)
        // rather than characterIndex(for:) which expects screen coordinates.
        if let textStorage = self.textStorage,
           let layoutManager = self.layoutManager,
           let textContainer = self.textContainer {
            let pointInContainer = CGPoint(
                x: point.x - textContainerOrigin.x,
                y: point.y - textContainerOrigin.y)
            let glyphIndex = layoutManager.glyphIndex(for: pointInContainer, in: textContainer)
            if glyphIndex < layoutManager.numberOfGlyphs {
                let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                if charIndex < textStorage.length {
                    // Attachment-based notelink (new format)
                    if let nlAttachment = textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NotelinkAttachment,
                       let noteID = UUID(uuidString: nlAttachment.noteID) {
                        NotificationCenter.default.post(
                            name: .navigateToNoteLink,
                            object: nil,
                            userInfo: ["noteID": noteID]
                        )
                        return
                    }
                    // Text-based notelink (legacy format)
                    if let noteIDStr = textStorage.attribute(.notelinkID, at: charIndex, effectiveRange: nil) as? String,
                       textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) == nil,
                       let noteID = UUID(uuidString: noteIDStr) {
                        NotificationCenter.default.post(
                            name: .navigateToNoteLink,
                            object: nil,
                            userInfo: ["noteID": noteID]
                        )
                        return
                    }
                }
            }
        }

        actionDelegate?.endAttachmentHover()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)

        // After click completes, check if we clicked on highlighted text (single click only)
        if event.clickCount == 1,
           let textStorage = self.textStorage,
           let layoutManager = self.layoutManager,
           let textContainer = self.textContainer {
            let point = convert(event.locationInWindow, from: nil)
            let pointInContainer = CGPoint(
                x: point.x - textContainerOrigin.x,
                y: point.y - textContainerOrigin.y)
            let glyphIndex = layoutManager.glyphIndex(for: pointInContainer, in: textContainer)
            if glyphIndex < layoutManager.numberOfGlyphs {
                let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                if charIndex < textStorage.length,
                   let highlightHex = textStorage.attribute(.highlightColor, at: charIndex, effectiveRange: nil) as? String {
                    // Find the full contiguous highlighted range (longestEffectiveRange spans across attribute runs that differ in other keys like .underlineStyle)
                    var effectiveRange = NSRange()
                    _ = textStorage.attribute(.highlightColor, at: charIndex, longestEffectiveRange: &effectiveRange, in: NSRange(location: 0, length: textStorage.length))

                    // Get the rect of the highlighted range for positioning
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)
                    let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    let rectInView = NSRect(
                        x: boundingRect.origin.x + textContainerOrigin.x,
                        y: boundingRect.origin.y + textContainerOrigin.y,
                        width: boundingRect.width,
                        height: boundingRect.height)
                    let rectInWindow = convert(rectInView, to: nil)

                    var info: [String: Any] = [
                        "hex": highlightHex,
                        "fromClick": true,
                        "selectionWindowX": rectInWindow.origin.x,
                        "selectionWindowY": rectInWindow.origin.y,
                        "selectionWidth": rectInWindow.width,
                        "selectionHeight": rectInWindow.height,
                        "windowHeight": window?.contentView?.bounds.height ?? 800,
                        "charRange": NSValue(range: effectiveRange)
                    ]
                    if let eid = editorInstanceID { info["editorInstanceID"] = eid }
                    NotificationCenter.default.post(
                        name: .highlightTextClicked,
                        object: nil,
                        userInfo: info
                    )
                }
            }
        }
    }

    // Prevent initiating internal text drags when the selection contains custom
    // block-level attachments (images, tables, callouts, etc.) that can't survive
    // an RTFD pasteboard round-trip. Their subclass identity would be lost.
    override func dragSelection(with event: NSEvent, offset mouseOffset: NSSize, slideBack: Bool) -> Bool {
        guard let storage = textStorage else {
            return super.dragSelection(with: event, offset: mouseOffset, slideBack: slideBack)
        }
        let sel = selectedRange()
        guard sel.length > 0 else {
            return super.dragSelection(with: event, offset: mouseOffset, slideBack: slideBack)
        }
        var hasBlockAttachment = false
        storage.enumerateAttribute(.attachment, in: sel, options: []) { value, _, stop in
            if value is NoteImageAttachment || value is NoteTableAttachment
                || value is NoteMapAttachment || value is NoteCalloutAttachment || value is NoteCodeBlockAttachment
                || value is NoteTabsAttachment || value is NoteCardSectionAttachment
                || value is NoteDividerAttachment || value is NoteLinkCardAttachment {
                hasBlockAttachment = true
                stop.pointee = true
            }
        }
        if hasBlockAttachment { return false }
        return super.dragSelection(with: event, offset: mouseOffset, slideBack: slideBack)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if actionDelegate?.canHandleFileDrop(sender, in: self) == true {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if actionDelegate?.canHandleFileDrop(sender, in: self) == true {
            return .copy
        }
        return super.draggingUpdated(sender)
    }


    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if actionDelegate?.canHandleFileDrop(sender, in: self) == true {
            return true
        }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if actionDelegate?.handleFileDrop(sender, in: self) == true {
            return true
        }
        return super.performDragOperation(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "z" {
            undoManager?.undo()
            return true
        }
        if flags == [.command, .shift], event.charactersIgnoringModifiers == "z" {
            undoManager?.redo()
            return true
        }
        // Cmd+A: select all text in the editor, not sidebar notes
        if flags == .command, event.charactersIgnoringModifiers == "a" {
            selectAll(nil)
            return true
        }
        // Cmd+B/I/U — standard macOS formatting shortcuts
        if flags == .command, let chars = event.charactersIgnoringModifiers,
           let fmt = actionDelegate?.formatter {
            switch chars {
            case "b":
                fmt.applyFormatting(to: self, tool: .bold)
                return true
            case "i":
                fmt.applyFormatting(to: self, tool: .italic)
                return true
            case "u":
                fmt.applyFormatting(to: self, tool: .underline)
                return true
            case "0":
                fmt.applyFormatting(to: self, tool: .body)
                return true
            case "f":
                // Cmd+F — trigger in-app search
                NotificationCenter.default.post(name: .performSearchOnPage, object: nil, userInfo: editorInstanceID.map { ["editorInstanceID": $0 as Any] })
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if actionDelegate?.handleReturn(in: self) == true { return }
        super.insertNewline(sender)
    }

    override func keyDown(with event: NSEvent) {
        // Check formatting shortcuts before command menu handling
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)

        if hasCommand, let chars = event.charactersIgnoringModifiers,
           let fmt = actionDelegate?.formatter {
            // Cmd+1/2/3 — Headings
            if !hasShift {
                switch chars {
                case "1":
                    fmt.applyFormatting(to: self, tool: .h1)
                    return
                case "2":
                    fmt.applyFormatting(to: self, tool: .h2)
                    return
                case "3":
                    fmt.applyFormatting(to: self, tool: .h3)
                    return
                default:
                    break
                }
            }

            // Cmd+Shift shortcuts
            if hasShift {
                switch chars {
                case "x", "X":
                    // Cmd+Shift+X — Strikethrough
                    fmt.applyFormatting(to: self, tool: .strikethrough)
                    return
                case "8":
                    // Cmd+Shift+8 — Bullet list
                    fmt.applyFormatting(to: self, tool: .bulletList)
                    return
                case "7":
                    // Cmd+Shift+7 — Numbered list
                    fmt.applyFormatting(to: self, tool: .numberedList)
                    return
                case ".":
                    // Cmd+Shift+. — Block quote
                    fmt.applyFormatting(to: self, tool: .blockQuote)
                    return
                case "h", "H":
                    // Cmd+Shift+H — Highlight (yellow default)
                    fmt.applyHighlight(hex: "FFFF00", range: selectedRange(), to: self)
                    return
                case "k", "K":
                    // Cmd+Shift+K — Insert link
                    fmt.applyFormatting(to: self, tool: .link)
                    return
                default:
                    break
                }
            }
        }

        let eidInfo: [String: Any]? = editorInstanceID.map { ["editorInstanceID": $0] }

        // Handle URL paste menu keyboard navigation
        if isURLPasteMenuShowing {
            switch event.keyCode {
            case 126:  // Up Arrow
                NotificationCenter.default.post(name: .urlPasteNavigateUp, object: nil, userInfo: eidInfo)
                return
            case 125:  // Down Arrow
                NotificationCenter.default.post(name: .urlPasteNavigateDown, object: nil, userInfo: eidInfo)
                return
            case 36, 76:  // Return/Enter
                NotificationCenter.default.post(name: .urlPasteSelectFocused, object: nil, userInfo: eidInfo)
                return
            case 53:  // Escape
                let dismissPayload: [String: Any]? = editorInstanceID.map { ["editorInstanceID": $0] }
                NotificationCenter.default.post(name: .urlPasteDismiss, object: dismissPayload)
                return
            default:
                // Any other key dismisses the menu and passes through
                let dismissPayload: [String: Any]? = editorInstanceID.map { ["editorInstanceID": $0] }
                NotificationCenter.default.post(name: .urlPasteDismiss, object: dismissPayload)
                super.keyDown(with: event)
                return
            }
        }

        // Handle code paste menu keyboard navigation
        if isCodePasteMenuShowing {
            switch event.keyCode {
            case 126:  // Up Arrow
                NotificationCenter.default.post(name: .codePasteNavigateUp, object: nil, userInfo: eidInfo)
                return
            case 125:  // Down Arrow
                NotificationCenter.default.post(name: .codePasteNavigateDown, object: nil, userInfo: eidInfo)
                return
            case 36, 76:  // Return/Enter
                NotificationCenter.default.post(name: .codePasteSelectFocused, object: nil, userInfo: eidInfo)
                return
            case 53:  // Escape
                NotificationCenter.default.post(name: .codePasteDismiss, object: nil)
                return
            default:
                NotificationCenter.default.post(name: .codePasteDismiss, object: nil)
                super.keyDown(with: event)
                return
            }
        }

        // Handle note picker keyboard navigation (triggered by "@")
        if isNotePickerShowing {
            switch event.keyCode {
            case 126:  // Up Arrow
                NotificationCenter.default.post(name: .notePickerNavigateUp, object: nil, userInfo: eidInfo)
                return
            case 125:  // Down Arrow
                NotificationCenter.default.post(name: .notePickerNavigateDown, object: nil, userInfo: eidInfo)
                return
            case 36, 76:  // Return/Enter
                NotificationCenter.default.post(name: .notePickerSelect, object: nil, userInfo: eidInfo)
                return
            case 53:  // Escape
                NotificationCenter.default.post(name: .hideNotePicker, object: nil, userInfo: eidInfo)
                return
            case 51:  // Backspace
                super.keyDown(with: event)
                let cursor = selectedRange().location
                let atLoc = notePickerAtLocation
                if cursor <= atLoc || atLoc < 0 {
                    NotificationCenter.default.post(name: .hideNotePicker, object: nil, userInfo: eidInfo)
                } else {
                    let filterText = readNotePickerFilterText()
                    NotificationCenter.default.post(name: .notePickerFilterUpdate, object: filterText, userInfo: eidInfo)
                }
                return
            default:
                super.keyDown(with: event)
                // Update the note picker filter after the character is inserted
                let cursor = selectedRange().location
                let atLoc = notePickerAtLocation
                if cursor <= atLoc || atLoc < 0 {
                    NotificationCenter.default.post(name: .hideNotePicker, object: nil, userInfo: eidInfo)
                } else {
                    let filterText = readNotePickerFilterText()
                    NotificationCenter.default.post(name: .notePickerFilterUpdate, object: filterText, userInfo: eidInfo)
                }
                return
            }
        }

        // Only intercept keys if command menu is showing
        guard isCommandMenuShowing else {
            super.keyDown(with: event)
            return
        }

        // Handle special keys for command menu navigation
        // keyCode 126 = Up Arrow, 125 = Down Arrow, 36 = Return, 53 = Escape
        switch event.keyCode {
        case 126:  // Up Arrow
            NotificationCenter.default.post(name: .commandMenuNavigateUp, object: nil, userInfo: eidInfo)
            return

        case 125:  // Down Arrow
            NotificationCenter.default.post(name: .commandMenuNavigateDown, object: nil, userInfo: eidInfo)
            return

        case 36, 76:  // Return or Enter key
            NotificationCenter.default.post(name: .commandMenuSelect, object: nil, userInfo: eidInfo)
            return

        case 53:  // Escape key
            NotificationCenter.default.post(name: .hideCommandMenu, object: nil, userInfo: eidInfo)
            return

        case 51:  // Backspace
            super.keyDown(with: event)
            let cursor = selectedRange().location
            let slashLoc = commandSlashLocation
            if cursor <= slashLoc || slashLoc < 0 {
                NotificationCenter.default.post(name: .hideCommandMenu, object: nil, userInfo: eidInfo)
            } else {
                let filterText = readCommandFilterText()
                self.commandMenuFilterText = filterText
                NotificationCenter.default.post(
                    name: .commandMenuFilterUpdate, object: filterText, userInfo: eidInfo)
            }
            return

        default:
            super.keyDown(with: event)
        }
    }

    @available(macOS 10.11, *)
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let eidInfo: [String: Any]? = editorInstanceID.map { ["editorInstanceID": $0] }

        // Skip @/ interception during active IME composition (CJK input)
        // to prevent accidentally triggering menus mid-composition
        guard !hasMarkedText() else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        // Check if we're inserting "@" to trigger note picker
        if let str = string as? String, str == "@" {
            // Dismiss if already showing
            if isNotePickerShowing {
                NotificationCenter.default.post(name: .hideNotePicker, object: nil, userInfo: eidInfo)
            }

            let fallbackLocation = selectedRange().location
            super.insertText(string, replacementRange: replacementRange)
            let location = redirectedNotePickerLocation ?? fallbackLocation
            redirectedNotePickerLocation = nil

            // Show note picker at cursor position
            if let layoutManager = self.layoutManager,
               let textContainer = self.textContainer
            {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 1),
                    in: textContainer)

                let cursorX = glyphRect.origin.x + self.textContainerOrigin.x
                let cursorY = glyphRect.origin.y + self.textContainerOrigin.y
                let cursorHeight = glyphRect.height

                let menuPosition = CGPoint(x: cursorX, y: cursorY + cursorHeight + 4)

                NotificationCenter.default.post(
                    name: .showNotePicker,
                    object: [
                        "position": menuPosition,
                        "atLocation": location
                    ],
                    userInfo: eidInfo
                )
            }
            return
        }

        // If note picker is showing, insert character and update filter
        if isNotePickerShowing {
            super.insertText(string, replacementRange: replacementRange)
            let filterText = readNotePickerFilterText()
            NotificationCenter.default.post(
                name: .notePickerFilterUpdate, object: filterText, userInfo: eidInfo)
            return
        }

        // Check if we're inserting "/" to trigger command menu
        if let str = string as? String, str == "/" {
            // If menu is already showing, hide it and start fresh
            if isCommandMenuShowing {
                NotificationCenter.default.post(name: .hideCommandMenu, object: nil, userInfo: eidInfo)
            }

            // Allow the "/" to be inserted. `shouldChangeTextIn` schedules
            // `showCommandMenuAtCursor` on the next run loop after the slash is
            // in storage (see Coordinator). Do not post `.showCommandMenu` here.
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        // If command menu is showing, insert the character and update the filter
        if isCommandMenuShowing {
            super.insertText(string, replacementRange: replacementRange)
            let filterText = readCommandFilterText()
            self.commandMenuFilterText = filterText
            NotificationCenter.default.post(
                name: .commandMenuFilterUpdate, object: filterText, userInfo: eidInfo)
            return
        }

        super.insertText(string, replacementRange: replacementRange)

        // Check for markdown shortcuts after insertion.
        // `handleMarkdownShortcuts(inserted:)` is defined in `InlineNSTextView+MarkdownShortcuts.swift`.
        if let str = string as? String {
            handleMarkdownShortcuts(inserted: str)
        }
    }

    // `handleMarkdownShortcuts(inserted:)` and its `markdownBaseAttributes` helper
    // moved to `InlineNSTextView+MarkdownShortcuts.swift`.

    /// Reads the text typed after the "@" character to use as a filter for note picker
    private func readNotePickerFilterText() -> String {
        let atLoc = notePickerAtLocation
        guard atLoc >= 0,
              let textStorage = self.textStorage else { return "" }
        let cursor = selectedRange().location
        let filterStart = atLoc + 1  // skip the "@" itself
        guard filterStart <= cursor && cursor <= textStorage.length else { return "" }
        if filterStart == cursor { return "" }
        let filterRange = NSRange(location: filterStart, length: cursor - filterStart)
        return (textStorage.string as NSString).substring(with: filterRange)
    }

    /// Reads the text typed after the slash character to use as a filter
    private func readCommandFilterText() -> String {
        let slashLoc = commandSlashLocation
        guard slashLoc >= 0,
              let textStorage = self.textStorage else { return "" }
        let cursor = selectedRange().location
        let filterStart = slashLoc + 1  // skip the "/" itself
        guard filterStart < cursor && cursor <= textStorage.length else { return "" }
        let filterRange = NSRange(location: filterStart, length: cursor - filterStart)
        return (textStorage.string as NSString).substring(with: filterRange)
    }
    
    // MARK: - Context Menu Implementation
    
    override func menu(for event: NSEvent) -> NSMenu? {
        // Start with the system menu so Writing Tools, Lookup, and all standard
        // system items are preserved intact.
        let menu = super.menu(for: event) ?? NSMenu()

        // Jot-specific formatting actions inserted at the top, before system items.
        let boldItem = NSMenuItem(title: "Bold", action: #selector(toggleBold(_:)), keyEquivalent: "")
        let italicItem = NSMenuItem(title: "Italic", action: #selector(toggleItalic(_:)), keyEquivalent: "")
        let underlineItem = NSMenuItem(title: "Underline", action: #selector(toggleUnderline(_:)), keyEquivalent: "")
        let todoItem = NSMenuItem(title: "Insert Todo", action: #selector(insertTodo(_:)), keyEquivalent: "")
        let bulletItem = NSMenuItem(title: "Insert Bullet List", action: #selector(insertBulletList(_:)), keyEquivalent: "")
        let separator = NSMenuItem.separator()

        // Insert in reverse order so they appear in the intended top-to-bottom sequence.
        menu.insertItem(separator, at: 0)
        menu.insertItem(bulletItem, at: 0)
        menu.insertItem(todoItem, at: 0)
        menu.insertItem(NSMenuItem.separator(), at: 0)
        menu.insertItem(underlineItem, at: 0)
        menu.insertItem(italicItem, at: 0)
        menu.insertItem(boldItem, at: 0)

        return menu
    }
    
    // MARK: - Context Menu Actions

    private var contextMenuUserInfo: [String: Any] {
        var info: [String: Any] = [:]
        if let eid = editorInstanceID { info["editorInstanceID"] = eid }
        return info
    }

    @objc private func toggleBold(_ sender: Any?) {
        var info = contextMenuUserInfo
        info["tool"] = "bold"
        NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: info)
    }

    @objc private func toggleItalic(_ sender: Any?) {
        var info = contextMenuUserInfo
        info["tool"] = "italic"
        NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: info)
    }

    @objc private func toggleUnderline(_ sender: Any?) {
        var info = contextMenuUserInfo
        info["tool"] = "underline"
        NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: info)
    }

    @objc private func insertTodo(_ sender: Any?) {
        NotificationCenter.default.post(name: .todoToolbarAction, object: nil, userInfo: contextMenuUserInfo)
    }

    @objc private func insertBulletList(_ sender: Any?) {
        var info = contextMenuUserInfo
        info["tool"] = "bulletList"
        NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: info)
    }

    // MARK: - Command Menu Placeholder

    /// Shows a dimmed "Type to search" ghost text right after the "/" when
    /// the slash command menu is open and no filter text has been typed yet.
    /// Hides automatically when the user types any filter character or when
    /// the menu closes. Called from didSet on `isCommandMenuShowing`,
    /// `commandSlashLocation`, and `commandMenuFilterText`.
    func updateCommandMenuPlaceholder() {
        // Show only when the menu is open, a valid slash location is recorded,
        // and the user has not yet typed any filter characters.
        let shouldShow = isCommandMenuShowing
            && commandSlashLocation >= 0
            && commandMenuFilterText.isEmpty

        guard shouldShow else {
            commandMenuPlaceholderField?.removeFromSuperview()
            commandMenuPlaceholderField = nil
            return
        }

        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer,
              let textStorage = self.textStorage,
              commandSlashLocation < textStorage.length
        else { return }

        // Compute the glyph rect for the "/" character so we can position
        // the placeholder immediately to its right.
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: commandSlashLocation)
        let slashRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )

        // Get the "/" glyph's baseline position within its line fragment so
        // we can baseline-align the placeholder field to it. Without this,
        // the field's TOP would align with the line fragment's top — which
        // looks visibly higher than the "/" character because the placeholder
        // font (12pt) is shorter than the body font (16pt) and its text ends
        // up floating above the "/" vertical center.
        let lineFragmentRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        let glyphBaselineInLine = layoutManager.location(forGlyphAt: glyphIndex)
        let slashBaselineY = lineFragmentRect.origin.y + glyphBaselineInLine.y + textContainerOrigin.y

        let originX = slashRect.origin.x + textContainerOrigin.x + slashRect.width + 4

        // Reuse or create the placeholder field.
        let field: NSTextField
        if let existing = commandMenuPlaceholderField {
            field = existing
        } else {
            field = NSTextField(labelWithString: "Type to search")
            field.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            field.textColor = NSColor(named: "SecondaryTextColor") ?? .secondaryLabelColor
            field.backgroundColor = .clear
            field.isBezeled = false
            field.isEditable = false
            field.isSelectable = false
            field.drawsBackground = false
            field.isHidden = false
            // Don't intercept any events — the field is purely decorative.
            field.refusesFirstResponder = true
            addSubview(field)
            commandMenuPlaceholderField = field
        }

        field.sizeToFit()

        // NSTextField's text baseline sits at `frame.origin.y + (height - descender)`
        // (descender is negative). To make the field's baseline match the "/"
        // glyph's baseline, subtract the ascender from the baseline Y.
        let fieldAscender = field.font?.ascender ?? 0
        let originY = slashBaselineY - fieldAscender
        field.frame.origin = NSPoint(x: originX, y: originY)
    }
}

// Access promoted from `private` to file-internal so `NoteParagraphStyler`
// (sibling file) can detect todo paragraphs via `attachment.attachmentCell as?`.
final class TodoCheckboxAttachmentCell: NSTextAttachmentCell {
    var isChecked: Bool
    private let size = NSSize(width: 30, height: 26)
    private let checkSize: CGFloat = 18
    private let cornerRadius: CGFloat = 9  // checkSize / 2 → fully circular
    private let borderWidth: CGFloat = 1.5

    // Checkmark pen-stroke animation
    private var checkAnimationStart: CFTimeInterval?
    private weak var animatingTextView: NSTextView?
    private var animationTimer: Timer?
    private let checkAnimationDuration: CFTimeInterval = 0.3

    init(isChecked: Bool = false) {
        self.isChecked = isChecked
        super.init(imageCell: nil)
    }

    required init(coder: NSCoder) {
        self.isChecked = false
        super.init(coder: coder)
    }

    deinit {
        animationTimer?.invalidate()
    }

    override var cellSize: NSSize { size }

    override nonisolated func cellBaselineOffset() -> NSPoint {
        let font = NSFont(name: "Charter", size: 16) ?? NSFont.systemFont(ofSize: 16)
        let offset = (font.capHeight - size.height) / 2
        return NSPoint(x: 0, y: offset)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let img = renderImage(for: controlView) else { return }
        img.draw(in: cellFrame)
    }

    override func wantsToTrackMouse() -> Bool { true }

    override func trackMouse(
        with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?,
        atCharacterIndex charIndex: Int, untilMouseUp flag: Bool
    ) -> Bool {
        guard let textView = controlView as? NSTextView,
              let storage = textView.textStorage else {
            isChecked.toggle()
            return true
        }

        // Register the change with the undo manager via shouldChangeText/didChangeText
        let attachmentRange = NSRange(location: charIndex, length: 1)
        guard attachmentRange.location < storage.length else {
            isChecked.toggle()
            return true
        }

        if textView.shouldChangeText(in: attachmentRange, replacementString: nil) {
            isChecked.toggle()

            // Animate the checkmark being drawn
            if isChecked {
                startCheckAnimation(in: textView)
            } else {
                stopCheckAnimation()
            }

            // Apply/remove checked styling on the todo text (everything after checkbox on same paragraph)
            // Todo structure: [attachment][space][space][text...] — skip all 3 prefix chars
            let paragraphRange = (storage.string as NSString).paragraphRange(for: attachmentRange)
            let textStart = charIndex + 3
            let textEnd = NSMaxRange(paragraphRange)
            if textStart < textEnd {
                let textRange = NSRange(location: textStart, length: textEnd - textStart)
                storage.beginEditing()
                if isChecked {
                    // Mark text as checked: dimmed opacity + squiggly strikethrough marker
                    storage.addAttribute(.todoChecked, value: true, range: textRange)
                    storage.addAttribute(.foregroundColor, value: checkedTodoTextColor, range: textRange)
                } else {
                    // Remove checked styling: restore full opacity + remove strikethrough marker
                    storage.removeAttribute(.todoChecked, range: textRange)
                    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: textRange)
                }
                // Force re-render of the attachment cell image (must be inside beginEditing/endEditing)
                storage.edited(.editedAttributes, range: attachmentRange, changeInLength: 0)
                storage.endEditing()
            } else {
                // No text range to style, but still need to re-render the checkbox
                storage.beginEditing()
                storage.edited(.editedAttributes, range: attachmentRange, changeInLength: 0)
                storage.endEditing()
            }

            textView.didChangeText()
            NotificationCenter.default.post(name: NSText.didChangeNotification, object: textView)
        }
        return true
    }

    func invalidateAppearance() {}

    // MARK: - Checkmark Animation

    private func startCheckAnimation(in textView: NSTextView) {
        checkAnimationStart = CACurrentMediaTime()
        animatingTextView = textView
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.animatingTextView?.needsDisplay = true
            if let start = self.checkAnimationStart,
               CACurrentMediaTime() - start > self.checkAnimationDuration {
                timer.invalidate()
                self.animationTimer = nil
                self.checkAnimationStart = nil
                self.animatingTextView?.needsDisplay = true
            }
        }
    }

    private func stopCheckAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        checkAnimationStart = nil
    }

    // MARK: - Rendering

    private func renderImage(for controlView: NSView?) -> NSImage? {
        let isDark: Bool
        if let appearance = controlView?.effectiveAppearance {
            isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        } else {
            isDark = false
        }

        let image = NSImage(size: size)
        image.lockFocus()

        let drawBlock = { [self] in
            let accentColor = NSColor(named: "ButtonPrimaryBgColor") ?? NSColor.controlAccentColor

            let xInset = (size.width - checkSize) / 2
            let yInset = (size.height - checkSize) / 2
            let checkRect = NSRect(x: xInset, y: yInset, width: checkSize, height: checkSize)

            if isChecked {
                // Filled accent circle
                let fillPath = NSBezierPath(roundedRect: checkRect, xRadius: cornerRadius, yRadius: cornerRadius)
                accentColor.setFill()
                fillPath.fill()

                // Animated pen-stroke checkmark
                // Three points: start (left-mid), valley (bottom of V), end (top-right)
                // Coordinate system: origin bottom-left, y increases upward
                let p1 = NSPoint(x: checkRect.minX + checkSize * 0.32,
                                 y: checkRect.minY + checkSize * 0.54)
                let p2 = NSPoint(x: checkRect.minX + checkSize * 0.46,
                                 y: checkRect.minY + checkSize * 0.32)
                let p3 = NSPoint(x: checkRect.minX + checkSize * 0.70,
                                 y: checkRect.minY + checkSize * 0.70)

                let seg1Len = hypot(p2.x - p1.x, p2.y - p1.y)
                let seg2Len = hypot(p3.x - p2.x, p3.y - p2.y)
                let totalLen = seg1Len + seg2Len

                // Calculate animation progress (1.0 = fully drawn)
                var progress: CGFloat = 1.0
                if let start = checkAnimationStart {
                    let t = min(CGFloat((CACurrentMediaTime() - start) / checkAnimationDuration), 1.0)
                    // Cubic ease-out: fast start, gentle settle
                    let inv = 1.0 - t
                    progress = 1.0 - inv * inv * inv
                }

                let drawDist = progress * totalLen

                let checkPath = NSBezierPath()
                checkPath.lineWidth = 1.5
                checkPath.lineCapStyle = .round
                checkPath.lineJoinStyle = .round
                checkPath.move(to: p1)

                if drawDist <= seg1Len {
                    // Still drawing the down-stroke
                    let frac = drawDist / seg1Len
                    checkPath.line(to: NSPoint(
                        x: p1.x + (p2.x - p1.x) * frac,
                        y: p1.y + (p2.y - p1.y) * frac))
                } else {
                    // Down-stroke complete, drawing the up-stroke
                    checkPath.line(to: p2)
                    let frac = (drawDist - seg1Len) / seg2Len
                    checkPath.line(to: NSPoint(
                        x: p2.x + (p3.x - p2.x) * frac,
                        y: p2.y + (p3.y - p2.y) * frac))
                }

                let checkColor = NSColor(named: "ButtonPrimaryTextColor") ?? .white
                checkColor.setStroke()
                checkPath.stroke()
            } else {
                // Empty circle with border
                let fillPath = NSBezierPath(roundedRect: checkRect, xRadius: cornerRadius, yRadius: cornerRadius)
                (isDark ? NSColor(white: 0.18, alpha: 1) : NSColor.white).setFill()
                fillPath.fill()

                let bInset = borderWidth / 2
                let strokeRect = checkRect.insetBy(dx: bInset, dy: bInset)
                let strokePath = NSBezierPath(
                    roundedRect: strokeRect,
                    xRadius: cornerRadius - bInset,
                    yRadius: cornerRadius - bInset)
                strokePath.lineWidth = borderWidth
                (isDark ? NSColor(white: 0.35, alpha: 1) : NSColor(white: 0.72, alpha: 1)).setStroke()
                strokePath.stroke()
            }
        }

        if let appearance = controlView?.effectiveAppearance {
            appearance.performAsCurrentDrawingAppearance(drawBlock)
        } else {
            drawBlock()
        }

        image.unlockFocus()
        return image
    }
}



// MARK: - Notifications

extension Notification.Name {
    static let insertTodoInEditor = Notification.Name("insertTodoInEditor")
    static let insertWebClipInEditor = Notification.Name("insertWebClipInEditor")
    static let insertFileLinkInEditor = Notification.Name("insertFileLinkInEditor")
    static let insertVoiceTranscriptInEditor = Notification.Name("insertVoiceTranscriptInEditor")
    static let insertImageInEditor = Notification.Name("insertImageInEditor")
    static let insertMapInEditor = Notification.Name("insertMapInEditor")
    static let deleteWebClipAttachment = Notification.Name("deleteWebClipAttachment")
    static let convertSelectedTextToWebClip = Notification.Name("convertSelectedTextToWebClip")
    static let applyEditTool = Notification.Name("applyEditTool")
    static let triggerQuickLook = Notification.Name("triggerQuickLook")
    static let linkHoverDetected = Notification.Name("linkHoverDetected")
    static let linkHoverDismiss = Notification.Name("linkHoverDismiss")
    static let linkHoverQuickLookTriggered = Notification.Name("linkHoverQuickLookTriggered")
    static let fileExtractTriggered = Notification.Name("fileExtractTriggered")

    // Command menu notifications
    static let showCommandMenu = Notification.Name("ShowCommandMenu")
    static let hideCommandMenu = Notification.Name("HideCommandMenu")
    static let commandMenuNavigateUp = Notification.Name("CommandMenuNavigateUp")
    static let commandMenuNavigateDown = Notification.Name("CommandMenuNavigateDown")
    static let commandMenuFilterUpdate = Notification.Name("CommandMenuFilterUpdate")
    static let commandMenuSelect = Notification.Name("CommandMenuSelect")
    static let applyCommandMenuTool = Notification.Name("ApplyCommandMenuTool")
    static let insertWebLink = Notification.Name("InsertWebLink")

    // URL paste option menu notifications
    static let urlPasteDetected = Notification.Name("URLPasteDetected")
    static let urlPasteSelectMention = Notification.Name("URLPasteSelectMention")
    static let urlPasteSelectPlainLink = Notification.Name("URLPasteSelectPlainLink")
    static let urlPasteSelectCard = Notification.Name("URLPasteSelectCard")
    static let urlPasteDismiss = Notification.Name("URLPasteDismiss")
    static let urlPasteNavigateUp = Notification.Name("URLPasteNavigateUp")
    static let urlPasteNavigateDown = Notification.Name("URLPasteNavigateDown")
    static let urlPasteSelectFocused = Notification.Name("URLPasteSelectFocused")

    // Code paste option menu notifications
    static let codePasteDetected = Notification.Name("CodePasteDetected")
    static let codePasteSelectCodeBlock = Notification.Name("CodePasteSelectCodeBlock")
    static let codePasteSelectPlainText = Notification.Name("CodePasteSelectPlainText")
    static let codePasteDismiss = Notification.Name("CodePasteDismiss")
    static let codePasteNavigateUp = Notification.Name("CodePasteNavigateUp")
    static let codePasteNavigateDown = Notification.Name("CodePasteNavigateDown")
    static let codePasteSelectFocused = Notification.Name("CodePasteSelectFocused")

    // Note picker notifications (triggered by "@")
    static let showNotePicker = Notification.Name("ShowNotePicker")
    static let hideNotePicker = Notification.Name("HideNotePicker")
    static let notePickerFilterUpdate = Notification.Name("NotePickerFilterUpdate")
    static let notePickerNavigateUp = Notification.Name("NotePickerNavigateUp")
    static let notePickerNavigateDown = Notification.Name("NotePickerNavigateDown")
    static let notePickerSelect = Notification.Name("NotePickerSelect")
    static let applyNotePickerSelection = Notification.Name("ApplyNotePickerSelection")

    // Editor menu state sync (SwiftUI → NSTextView instance)
    static let syncEditorMenuState = Notification.Name("SyncEditorMenuState")

    // Notelink navigation
    static let navigateToNoteLink = Notification.Name("NavigateToNoteLink")

    // In-note search notifications
    static let showInNoteSearch = Notification.Name("ShowInNoteSearch")
    static let highlightSearchMatches = Notification.Name("HighlightSearchMatches")
    static let clearSearchHighlights = Notification.Name("ClearSearchHighlights")
    static let replaceCurrentSearchMatch = Notification.Name("ReplaceCurrentSearchMatch")
    static let replaceAllSearchMatches = Notification.Name("ReplaceAllSearchMatches")
    static let performSearchOnPage = Notification.Name("PerformSearchOnPage")
    static let searchOnPageResults = Notification.Name("SearchOnPageResults")
    static let showInNoteSearchAndReplace = Notification.Name("ShowInNoteSearchAndReplace")

}
