//
//  TodoEditorRepresentable.swift
//  Jot
//
//  NSViewRepresentable bridge and InlineNSTextView for TodoRichTextEditor.
//

import Combine
import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

// MARK: - Supporting Types & Attachments
// (Moved from TodoRichTextEditor.swift — used exclusively by the Coordinator)

extension NSAttributedString.Key {
    static let webClipTitle = NSAttributedString.Key("WebClipTitle")
    static let webClipDescription = NSAttributedString.Key("WebClipDescription")
    static let webClipDomain = NSAttributedString.Key("WebClipDomain")
    static let plainLinkURL = NSAttributedString.Key("PlainLinkURL")
    static let imageFilename = NSAttributedString.Key("ImageFilename")
    static let imageWidthRatio = NSAttributedString.Key("ImageWidthRatio")
    static let fileStoredFilename = NSAttributedString.Key("FileStoredFilename")
    static let fileOriginalFilename = NSAttributedString.Key("FileOriginalFilename")
    static let fileTypeIdentifier = NSAttributedString.Key("FileTypeIdentifier")
    static let fileDisplayLabel = NSAttributedString.Key("FileDisplayLabel")
    static let orderedListNumber = NSAttributedString.Key("OrderedListNumber")
    static let blockQuote = NSAttributedString.Key("BlockQuote")
    static let highlightColor = NSAttributedString.Key("HighlightColor")
    static let marked = NSAttributedString.Key("Marked")
    static let notelinkID = NSAttributedString.Key("NotelinkID")
    static let notelinkTitle = NSAttributedString.Key("NotelinkTitle")
    static let fileLinkPath = NSAttributedString.Key("FileLinkPath")
    static let fileLinkDisplayName = NSAttributedString.Key("FileLinkDisplayName")
    static let fileLinkBookmark = NSAttributedString.Key("FileLinkBookmark")
}

enum AttachmentMarkup {
    static let imageMarkupPrefix = "[[image|"
    static let imagePattern = #"\[\[image\|\|\|([^\]|]+)(?:\|\|\|([0-9]*\.?[0-9]+))?\]\]"#
    static let imageRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: imagePattern,
        options: []
    )
    static let fileMarkupPrefix = "[[file|"
    static let filePattern = #"\[\[file\|([^|]+)\|([^|]+)\|([^\]]*)\]\]"#
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

    /// Timer that fires during active animations to drive redraw.
    private var animationTimer: Timer?

    /// The text view whose display we invalidate each frame.
    weak var animatingTextView: NSTextView?

    // MARK: Public API

    /// Register characters in a range for animation.
    /// - Parameters:
    ///   - range: The character range to animate.
    ///   - stagger: If true, each character gets an incremental delay (paste wave).
    func animateCharacters(in range: NSRange, stagger: Bool) {
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
        animationTimer?.invalidate()
        animationTimer = nil
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
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            self.animatingTextView?.needsDisplay = true

            // Prune completed animations (keep if end time is still in the future)
            let now = CACurrentMediaTime()
            self.activeAnimations = self.activeAnimations.filter {
                now < $0.value + self.animationDuration
            }

            if self.activeAnimations.isEmpty {
                self.animationTimer?.invalidate()
                self.animationTimer = nil
            }
        }
    }

    // MARK: Drawing Override

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard !activeAnimations.isEmpty,
            let context = NSGraphicsContext.current?.cgContext
        else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        let now = CACurrentMediaTime()
        var currentIndex = glyphsToShow.location
        let endIndex = NSMaxRange(glyphsToShow)

        while currentIndex < endIndex {
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
                while runEnd < endIndex {
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

    // MARK: Custom Background Drawing

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        // Block quote left bar (drawn after super, on top)
        guard let textStorage = textStorage, let textContainer = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        // Expand each .blockQuote attribute run to its full paragraph range(s),
        // then coalesce adjacent quote paragraphs into one continuous bar.
        var coveredRanges: [NSRange] = []
        textStorage.enumerateAttribute(.blockQuote, in: charRange, options: []) { value, attrRange, _ in
            guard value as? Bool == true else { return }
            let expandedRange = (textStorage.string as NSString).paragraphRange(for: attrRange)
            if let last = coveredRanges.last, NSMaxRange(last) >= expandedRange.location {
                coveredRanges[coveredRanges.count - 1] = NSUnionRange(last, expandedRange)
            } else {
                coveredRanges.append(expandedRange)
            }
        }

        let barWidth: CGFloat = 3.0
        for range in coveredRanges {
            let quoteGlyphRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard quoteGlyphRange.length > 0 else { continue }
            let rect = boundingRect(forGlyphRange: quoteGlyphRange, in: textContainer)
            let barRect = CGRect(
                x: origin.x + 6,
                y: origin.y + rect.origin.y,
                width: barWidth,
                height: rect.height)
            NSColor.labelColor.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

/// Dedicated attachment type so that we never lose the stored filename during round-trips.
final class NoteImageAttachment: NSTextAttachment {
    let storedFilename: String
    var widthRatio: CGFloat

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

    init(codeBlockData: CodeBlockData) {
        self.codeBlockData = codeBlockData
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteCodeBlockAttachment does not support init(coder:)")
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
    let displaySize: CGSize

    init(size: CGSize) {
        self.displaySize = size
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("DividerSizeAttachmentCell does not support init(coder:)")
    }

    override var cellSize: NSSize { displaySize }
    override nonisolated func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Hand-drawn squiggly divider line
        let lineY = cellFrame.midY
        let startX = cellFrame.minX + 10
        let endX = cellFrame.maxX - 10
        let totalWidth = endX - startX
        guard totalWidth > 0 else { return }

        // Seeded RNG from the cell's pointer for stable wobble across redraws
        var seed = UInt64(UInt(bitPattern: ObjectIdentifier(self)))
        func nextRand() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 1000) / 1000.0
        }

        let path = NSBezierPath()
        path.lineWidth = 0.75
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: startX, y: lineY + (nextRand() - 0.5) * 1.8))

        // Uneven segments: vary segment length between 6-16pt for organic feel
        var x = startX
        while x < endX {
            let segLen = 6 + nextRand() * 10
            let nextX = min(x + segLen, endX)
            let midX = (x + nextX) / 2
            // Control points wobble vertically, asymmetric for hand-drawn feel
            let cpY1 = lineY + (nextRand() - 0.45) * 3.6
            let cpY2 = lineY + (nextRand() - 0.55) * 3.6
            let endY = lineY + (nextRand() - 0.5) * 2.0
            path.curve(to: NSPoint(x: nextX, y: endY),
                        controlPoint1: NSPoint(x: midX - segLen * 0.15, y: cpY1),
                        controlPoint2: NSPoint(x: midX + segLen * 0.15, y: cpY2))
            x = nextX
        }

        NSColor.labelColor.withAlphaComponent(0.3).setStroke()
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

    private var pillColor: Color {
        colorScheme == .dark
            ? Color(red: 0.792, green: 0.541, blue: 0.016)  // Yellow 600 #ca8a04
            : Color(red: 0.918, green: 0.702, blue: 0.031)  // Yellow 500 #eab308
    }

    var body: some View {
        Text("@\(title.isEmpty ? "Untitled" : title)")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(pillColor, in: Capsule(style: .continuous))
            .fixedSize()
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

struct FileLinkPillView: View {
    let displayName: String
    let colorScheme: ColorScheme

    private var pillColor: Color {
        colorScheme == .dark
            ? Color(red: 0.839, green: 0.827, blue: 0.820)  // stone/300 #d6d3d1
            : Color(red: 0.161, green: 0.145, blue: 0.141)  // stone/800 #292524
    }

    private var contentColor: Color {
        colorScheme == .dark
            ? Color(red: 0.102, green: 0.102, blue: 0.102)  // #1a1a1a
            : .white
    }

    var body: some View {
        HStack(spacing: 4) {
            Image("IconFileLink")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(contentColor)
            Text(displayName.isEmpty ? "Untitled" : displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(contentColor)
                .lineLimit(1)
            Image("arrow-up-right")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(contentColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(pillColor, in: Capsule(style: .continuous))
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
    private var computedCornerRadius: CGFloat { 16 }

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
        addCursorRect(cornerRect, cursor: NSCursor.frameResize(position: .bottomRight, directions: .all))

        // Right edge (excluding corner) — extends outward by `outset`
        let rightRect = CGRect(x: bounds.maxX - zone + outset, y: bounds.minY,
                               width: zone, height: bounds.height - zone + outset)
        addCursorRect(rightRect, cursor: NSCursor.frameResize(position: .right, directions: .all))

        // Bottom edge (excluding corner) — extends outward by `outset`
        let bottomRect = CGRect(x: bounds.minX, y: bounds.maxY - zone + outset,
                                width: bounds.width - zone + outset, height: zone)
        addCursorRect(bottomRect, cursor: NSCursor.frameResize(position: .bottom, directions: .all))
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
        case .right:  NSCursor.frameResize(position: .right, directions: .all)
        case .bottom: NSCursor.frameResize(position: .bottom, directions: .all)
        case .corner: NSCursor.frameResize(position: .bottomRight, directions: .all)
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
            case .right:  NSCursor.frameResize(position: .right, directions: .all)
            case .bottom: NSCursor.frameResize(position: .bottom, directions: .all)
            case .corner: NSCursor.frameResize(position: .bottomRight, directions: .all)
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
final class NoteFileAttachment: NSTextAttachment {
    let storedFilename: String
    let originalFilename: String
    let typeIdentifier: String
    let displayLabel: String

    init(storedFilename: String, originalFilename: String, typeIdentifier: String, displayLabel: String) {
        self.storedFilename = storedFilename
        self.originalFilename = originalFilename
        self.typeIdentifier = typeIdentifier
        self.displayLabel = displayLabel
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
    let colorScheme: ColorScheme
    let bottomInset: CGFloat
    let focusRequestID: UUID?
    let editorInstanceID: UUID?
    var onNavigateToNote: ((UUID) -> Void)?
    private let unlimitedDimension = CGFloat.greatestFiniteMagnitude

    func makeNSView(context: Context) -> InlineNSTextView {
        let textView = InlineNSTextView()
        textView.delegate = context.coordinator
        textView.actionDelegate = context.coordinator
        textView.editorInstanceID = editorInstanceID
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        // Use Charter for body text as per design requirements
        textView.font = FontManager.bodyNS(size: ThemeManager.currentBodyFontSize(), weight: .regular)
        textView.textContainerInset = NSSize(width: 28, height: 16)
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
        context.coordinator.configure(with: textView)

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

                // NSColor.labelColor is dynamic — setting the appearance is sufficient.
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
        context.coordinator.onNavigateToNote = onNavigateToNote

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
            colorScheme: colorScheme,
            focusRequestID: focusRequestID,
            editorInstanceID: editorInstanceID
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
        private weak var textView: NSTextView?
        private var observers: [NSObjectProtocol] = []
        private var lastSerialized = ""
        fileprivate let formatter = TextFormattingManager()
        private var isUpdating = false
        private var textBinding: Binding<String>
        private var lastHandledFocusRequestID: UUID?
        private let editorInstanceID: UUID?

        // Typing animation state
        fileprivate weak var typingAnimationManager: TypingAnimationLayoutManager?
        private var pendingAnimationLocation: Int?
        private var pendingAnimationLength: Int?
        private struct FileAttachmentMetadata {
            let storedFilename: String
            let originalFilename: String
            let typeIdentifier: String
            let displayLabel: String
        }

        // MARK: - Inline image overlay tracking
        private var imageOverlays: [ObjectIdentifier: InlineImageOverlayView] = [:]
        private var tableOverlays: [ObjectIdentifier: NoteTableOverlayView] = [:]
        private var calloutOverlays: [ObjectIdentifier: CalloutOverlayView] = [:]
        private var codeBlockOverlays: [ObjectIdentifier: CodeBlockOverlayView] = [:]

        private weak var overlayHostView: NSView?
        /// True when applyInitialText ran but the view was not in the hierarchy
        /// yet (no enclosingScrollView), so overlay creation was deferred.
        private var needsDeferredOverlaySetup = false
        var onNavigateToNote: ((UUID) -> Void)?
        var lastKnownTextViewWidth: CGFloat = 0
        /// True once the bounds-change observer on the clip view has been registered.
        private var hasBoundsObserver = false
        /// True once the frame-change observer on the scroll view has been registered.
        private var hasFrameObserver = false
        /// True once ancestor clipping has been disabled for overlay overflow.
        private var hasDisabledAncestorClipping = false
        /// Reentrancy guard — prevents cascading overlay updates from creating
        /// an infinite layout-invalidation cycle (split-view freeze bug).
        private var isUpdatingOverlays = false
        /// Coalesces rapid overlay update requests (resize, scroll, layout
        /// completion) into a single pass on the next main-queue turn.
        private var pendingOverlayUpdate: DispatchWorkItem?

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
                self.updateImageOverlays(in: tv)
                self.updateTableOverlays(in: tv)
                self.updateCalloutOverlays(in: tv)
                self.updateCodeBlockOverlays(in: tv)
                self.updateHighlightMarkers()
            }
            pendingOverlayUpdate = work
            DispatchQueue.main.async(execute: work)
        }

        private static let inlineImageCache: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = 24
            cache.totalCostLimit = 50 * 1024 * 1024
            return cache
        }()

        // NSTextViewDelegate method to handle selection changes
        func textViewDidChangeSelection(_ notification: Notification) {
            // Ensure layout stability when selection changes to prevent attachment shifting
            if let textView = self.textView, let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            
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
                    let selectionRectInWindow = textView.convert(selectionRect, to: nil)

                    // Cache selection so Edit Content can use it even after focus shifts
                    lastKnownSelectionRange = selectedRange
                    lastKnownSelectionText = (textView.string as NSString).substring(with: selectedRange)
                    lastKnownSelectionWindowRect = selectionRectInWindow

                    // Post notification with selection info - let the view calculate toolbar position
                    var info: [String: Any] = [
                        "hasSelection": true,
                        "selectionX": selectionX,
                        "selectionY": selectionY,
                        "selectionWidth": selectionWidth,
                        "selectionHeight": selectionHeight,
                        "selectionWindowY": selectionRectInWindow.origin.y,
                        "selectionWindowX": selectionRectInWindow.origin.x,
                        "visibleWidth": visibleRect.width,
                        "visibleHeight": visibleRect.height
                    ]
                    if let eid = editorInstanceID { info["editorInstanceID"] = eid }
                    NotificationCenter.default.post(
                        name: .textSelectionChanged,
                        object: nil,
                        userInfo: info
                    )
                }
            } else {
                // No selection - hide floating toolbar
                // Clear cache only if user deliberately placed cursor (view still has focus).
                // When focus is lost (e.g. clicking AI tools button), preserve cache so the
                // selection is still available for the tool that caused the focus shift.
                if textView.window?.firstResponder == textView {
                    lastKnownSelectionRange = NSRange(location: NSNotFound, length: 0)
                    lastKnownSelectionText = ""
                    lastKnownSelectionWindowRect = .zero
                }
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

        // Highlight gutter markers — small icons in the left margin for each highlight block
        private var highlightMarkerViews: [NSView] = []

        // Last known non-empty selection — cached here so clicking the AI tools button
        // (which clears the NSTextView selection) doesn't lose context for Edit Content.
        private var lastKnownSelectionRange: NSRange = NSRange(location: NSNotFound, length: 0)
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
        private static let checkboxIconSize: CGFloat = 32
        private static let checkboxAttachmentWidth: CGFloat = 22
        private static let baseBaselineOffset: CGFloat = 0.0
        private static let todoBaselineOffset: CGFloat = {
            return 0.0
        }()
        private static var checkboxAttachmentYOffset: CGFloat { 0.0 }
        private static let checkboxBaselineOffset: CGFloat = {
            return 0.0
        }()
        private static let webClipMarkupPrefix = "[[webclip|"
        private static let webClipPattern = #"\[\[webclip\|([^|]*)\|([^|]*)\|([^\]]*)\]\]"#
        private static let webClipRegex: NSRegularExpression? = try? NSRegularExpression(
            pattern: webClipPattern,
            options: []
        )
        private static let plainLinkMarkupPrefix = "[[link|"
        private static let plainLinkPattern = #"\[\[link\|([^\]]*)\]\]"#
        private static let plainLinkRegex: NSRegularExpression? = try? NSRegularExpression(
            pattern: plainLinkPattern,
            options: []
        )
        private static func cleanedWebClipComponent(_ value: Any?) -> String {
            guard let raw = value as? String else { return "" }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            return
                trimmed
                .replacingOccurrences(of: "|", with: " ")
                .replacingOccurrences(of: "]]", with: " ]")
        }

        private static func sanitizedWebClipComponent(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            return
                trimmed
                .replacingOccurrences(of: "|", with: " ")
                .replacingOccurrences(of: "]]", with: " ")
        }

        private static func normalizedURL(from raw: String) -> String {
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
        private static func linkURLString(from attributes: [NSAttributedString.Key: Any]) -> String? {
            if let str = attributes[.link] as? String { return str }
            if let url = attributes[.link] as? URL { return url.absoluteString }
            return nil
        }

        private static func resolvedDomain(from urlString: String) -> String {
            let normalized = normalizedURL(from: urlString)
            if let host = URL(string: normalized)?.host, !host.isEmpty {
                return host
            }
            return
                normalized
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
        }

        private static func string(
            from match: NSTextCheckingResult, at index: Int, in text: String
        ) -> String {
            guard index < match.numberOfRanges else { return "" }
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: text) else { return "" }
            return String(text[swiftRange])
        }

        private func makeNotelinkAttachment(noteID: String, noteTitle: String) -> NSMutableAttributedString {
            let pillView = NotelinkPillView(title: noteTitle, colorScheme: currentColorScheme)
                .environment(\.colorScheme, currentColorScheme)
            let renderer = ImageRenderer(content: pillView)
            let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
            renderer.scale = displayScale
            renderer.isOpaque = false

            let attachment = NotelinkAttachment(noteID: noteID, noteTitle: noteTitle)

            guard let cgImage = renderer.cgImage else {
                let fallback = NSMutableAttributedString(string: "@\(noteTitle)")
                fallback.addAttributes([.notelinkID: noteID, .notelinkTitle: noteTitle],
                                       range: NSRange(location: 0, length: fallback.length))
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
            attributed.addAttributes([
                .notelinkID: noteID,
                .notelinkTitle: noteTitle,
            ], range: range)
            return attributed
        }

        private func makeFileLinkAttachment(filePath: String, displayName: String, bookmarkBase64: String = "") -> NSMutableAttributedString {
            let pillView = FileLinkPillView(displayName: displayName, colorScheme: currentColorScheme)
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

        private func makeWebClipAttachment(
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

            // Apply special paragraph style for web clips to prevent overlap
            attributed.addAttribute(
                .paragraphStyle, value: Self.webClipParagraphStyle(), range: attachmentRange)

            return attributed
        }

        /// Create a plain blue text link attachment -- looks like text, behaves like a button.
        private func makePlainLinkAttachment(url rawURL: String) -> NSMutableAttributedString {
            let normalizedURL = Self.normalizedURL(from: rawURL)
            let linkValue = normalizedURL.isEmpty ? rawURL : normalizedURL

            let linkView = Text(linkValue)
                .font(FontManager.heading(size: Self.textFont.pointSize, weight: .regular))
                .foregroundColor(.accentColor)
                .fixedSize()
                .environment(\.colorScheme, currentColorScheme)

            let renderer = ImageRenderer(content: linkView)
            let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
            renderer.scale = displayScale
            renderer.isOpaque = false

            let attachment = NSTextAttachment()

            guard let cgImage = renderer.cgImage else {
                return NSMutableAttributedString(string: linkValue)
            }

            let pixelWidth = CGFloat(cgImage.width)
            let pixelHeight = CGFloat(cgImage.height)
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
            attributed.addAttribute(.plainLinkURL, value: linkValue, range: attachmentRange)
            attributed.addAttribute(
                .paragraphStyle, value: Self.webClipParagraphStyle(), range: attachmentRange)

            return attributed
        }

        /// Create an inline image attachment tag from a filename
        /// Create a block-level image attachment with the given width ratio.
        private func makeImageAttachment(filename: String, widthRatio: CGFloat = 1.0) -> NSMutableAttributedString {
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

        /// Create an inline file attachment tag with metadata
        private func makeFileAttachment(metadata: FileAttachmentMetadata)
            -> NSMutableAttributedString
        {
            func fallbackAttributedString() -> NSMutableAttributedString {
                return NSMutableAttributedString(
                    string: "[File: \(metadata.displayLabel)]"
                )
            }

            let tagView = FileAttachmentTagView(label: metadata.displayLabel)
                .environment(\.colorScheme, currentColorScheme)
            let renderer = ImageRenderer(content: tagView)
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            renderer.scale = scale
            renderer.isOpaque = false

            guard let cgImage = renderer.cgImage else {
                NSLog("📄 makeFileAttachment: FAILED to render tag image")
                return fallbackAttributedString()
            }

            let displaySize = CGSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )

            let renderedImage = NSImage(size: displaySize)
            renderedImage.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

            let attachment = NoteFileAttachment(
                storedFilename: metadata.storedFilename,
                originalFilename: metadata.originalFilename,
                typeIdentifier: metadata.typeIdentifier,
                displayLabel: metadata.displayLabel
            )
            attachment.image = renderedImage
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: renderedImage)
            attachment.bounds = CGRect(
                x: 0,
                y: Self.imageTagVerticalOffset(for: displaySize.height),
                width: displaySize.width,
                height: displaySize.height
            )

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

            return attributed
        }


        func endAttachmentHover() {
            // No-op — hover preview system removed
        }

        func handleAttachmentHover(at point: CGPoint, in textView: NSTextView) -> Bool {
            return false
        }

        /// Checks all image overlays for a resize edge at the given window point.
        /// Returns the appropriate resize cursor, or nil if the point isn't on any edge.
        func resizeCursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
            for (_, overlay) in imageOverlays {
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
            return nil
        }

        init(text: Binding<String>, colorScheme: ColorScheme, focusRequestID: UUID?, editorInstanceID: UUID? = nil) {
            self.textBinding = text
            self.currentColorScheme = colorScheme
            self.lastHandledFocusRequestID = focusRequestID
            self.editorInstanceID = editorInstanceID
        }

        deinit {
            nonisolated(unsafe) let manager = typingAnimationManager
            let imgOverlays = imageOverlays.values.map { $0 }
            let tblOverlays = tableOverlays.values.map { $0 }
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            Task { @MainActor in
                manager?.clearAllAnimations()
                imgOverlays.forEach { $0.removeFromSuperview() }
                tblOverlays.forEach { $0.removeFromSuperview() }
            }
        }

        func configure(with textView: NSTextView) {
            self.textView = textView
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
                tableOverlays.values.forEach { $0.removeFromSuperview() }
                tableOverlays.removeAll()
                overlayHostView = newHost
            }
            // Register as layout manager delegate for overlay position tracking
            textView.layoutManager?.delegate = self
            registerBoundsObserverIfNeeded(for: textView)
            registerFrameObserverIfNeeded(for: textView)

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
                    self?.insertTodo()
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
                NSLog("📝 Coordinator: Received insertVoiceTranscriptInEditor notification")
                // We're on main queue (specified in observer), use assumeIsolated for synchronous execution
                // This prevents race condition with view dismissal that occurred with Task wrapper
                MainActor.assumeIsolated {
                    guard let self = self else {
                        NSLog("⚠️ Coordinator deallocated before transcript insertion")
                        return
                    }
                    guard let transcript = notification.object as? String else {
                        NSLog("📝 Coordinator: No transcript in notification object")
                        return
                    }
                    NSLog("📝 Coordinator: Got transcript: %@", transcript)
                    self.insertVoiceTranscript(transcript: transcript)
                    NSLog("📝 Coordinator: Transcript insertion completed")
                }
            }

            let insertImage = NotificationCenter.default.addObserver(
                forName: .insertImageInEditor, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                NSLog("📝 Coordinator: Received insertImageInEditor notification")
                guard let filename = notification.object as? String else {
                    NSLog("📝 Coordinator: No filename in notification object")
                    return
                }
                NSLog("📝 Coordinator: Got image filename: %@", filename)
                Task { @MainActor [weak self] in
                    guard let self = self else {
                        NSLog("⚠️ Coordinator deallocated before image insertion")
                        return
                    }
                    self.insertImage(filename: filename)
                }
            }

            let applyTool = NotificationCenter.default.addObserver(
                forName: .applyEditTool, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                guard let raw = notification.userInfo?["tool"] as? String else { return }
                guard let tool = EditTool(rawValue: raw) else { return }
                Task { @MainActor [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    if tool == .table {
                        self.insertTable()
                    } else if tool == .callout {
                        self.insertCallout()
                    } else if tool == .codeBlock {
                        self.insertCodeBlock()
                    } else if tool == .highlight {
                        // Mark selected text (gutter marker only, no background highlight)
                        let range = textView.selectedRange()
                        let isAdding = !self.isRangeFullyMarked(range, in: textView)
                        self.toggleMark(in: textView)
                        self.updateHighlightMarkers()
                        self.syncText()
                        // Notify so the marking can be persisted
                        if isAdding, range.length > 0,
                           let text = (textView.string as NSString?)?.substring(with: range) {
                            NotificationCenter.default.post(
                                name: .markingApplied,
                                object: nil,
                                userInfo: ["markedText": text]
                            )
                        }
                    } else {
                        self.formatter.applyFormatting(to: textView, tool: tool)
                        self.styleTodoParagraphs()
                        self.syncText()
                    }
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
                            textStorage.replaceCharacters(in: deleteRange, with: "")
                            textView.didChangeText()
                        }
                    }

                    // Apply the selected tool
                    // Special handling for todo/table to use proper attachment instead of text
                    if tool == .todo {
                        self.insertTodo()
                    } else if tool == .table {
                        self.insertTable()
                    } else if tool == .callout {
                        self.insertCallout()
                    } else if tool == .codeBlock {
                        self.insertCodeBlock()
                    } else {
                        self.formatter.applyFormatting(to: textView, tool: tool)
                    }

                    // Sync the text back
                    self.syncText()
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
                Task { @MainActor [weak self] in
                    self?.applyProofreadAnnotations(annotations, activeIndex: activeIndex)
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
                Task { @MainActor [weak self] in
                    self?.applyProofreadSuggestion(original: original, replacement: replacement)
                }
            }

            // MARK: Edit Content — capture selection
            let captureSelection = NotificationCenter.default.addObserver(
                forName: .aiEditRequestSelection, object: nil, queue: .main
            ) { [weak self] notification in
                if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
                   let myID = self?.editorInstanceID, nid != myID { return }
                Task { @MainActor [weak self] in
                    self?.captureSelectionForEditContent()
                }
            }

            let urlPasteMention = NotificationCenter.default.addObserver(
                forName: .urlPasteSelectMention, object: nil, queue: .main
            ) { [weak self] notification in
                guard let info = notification.object as? [String: Any],
                      let url = info["url"] as? String,
                      let rangeValue = info["range"] as? NSValue else { return }
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
                let range = rangeValue.rangeValue
                Task { @MainActor [weak self] in
                    self?.replaceURLPasteWithPlainLink(url: url, range: range)
                }
            }

            let urlPasteDismiss = NotificationCenter.default.addObserver(
                forName: .urlPasteDismiss, object: nil, queue: .main
            ) { [weak self] notification in
                let range = (notification.object as? NSValue)?.rangeValue
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
                let range = (notification.object as? [String: Any])?["range"] as? NSValue
                Task { @MainActor [weak self] in
                    if let r = range?.rangeValue { self?.clearCodePasteHighlight(range: r) }
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
                    // Use lastKnownSelectionRange — it survives focus changes (e.g. clicking the color picker).
                    // textView.selectedRange() would be empty after the picker button steals focus.
                    let range = self.lastKnownSelectionRange
                    self.formatter.applyTextColor(hex: hex, range: range, to: textView)
                    self.syncText()
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
                guard let userInfo = notification.userInfo,
                      let original = userInfo["original"] as? String,
                      let replacement = userInfo["replacement"] as? String else { return }
                Task { @MainActor [weak self] in
                    self?.applyEditContentReplacement(original: original, replacement: replacement)
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

            observers = [
                windowKey,
                insertTodo, insertLink, insertFileLink, insertVoiceTranscript, insertImage, applyTool, applyCommandMenuTool,
                applyNotePickerSelection, navigateNoteLink,
                performSearch, highlightSearch, clearSearch, replaceMatch, replaceAll,
                proofreadShow, proofreadClear, proofreadApply, captureSelection,
                editReplace, proofreadReplaceAll,
                urlPasteMention, urlPasteSelectPlainLink, urlPasteDismiss,
                codePasteSelectCodeBlock, codePasteSelectPlainText, codePasteDismissObserver,
                applyColor, settingsObserver,
            ]
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

            // Disable layer clipping on the text view and its immediate
            // SwiftUI hosting ancestors so table/callout/code-block overlays
            // can extend beyond the text view frame (e.g. add-column button).
            if !hasDisabledAncestorClipping {
                hasDisabledAncestorClipping = true
                textView.clipsToBounds = false
                var ancestor: NSView? = textView.superview
                for _ in 0..<4 {
                    guard let view = ancestor else { break }
                    // Stop before disabling clipping on scroll views —
                    // they need it for vertical content scrolling.
                    if view is NSScrollView || view is NSClipView { break }
                    view.clipsToBounds = false
                    if view.wantsLayer, let layer = view.layer {
                        layer.masksToBounds = false
                    }
                    ancestor = view.superview
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
                updateImageOverlays(in: textView)
                updateTableOverlays(in: textView)
                updateCalloutOverlays(in: textView)
                updateCodeBlockOverlays(in: textView)
                updateHighlightMarkers()
            }
        }

        // MARK: - Proofread Overlay Helpers

        private func applyProofreadAnnotations(_ annotations: [ProofreadAnnotation], activeIndex: Int = 0) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            clearProofreadOverlays()

            let fullString = storage.string as NSString

            // First pass: resolve all annotation ranges
            var resolved: [(annotation: ProofreadAnnotation, range: NSRange)] = []
            for annotation in annotations {
                let found = fullString.range(
                    of: annotation.original,
                    options: .literal,
                    range: NSRange(location: 0, length: fullString.length)
                )
                guard found.location != NSNotFound else { continue }
                resolved.append((annotation, found))
            }

            let isDark = currentColorScheme == .dark
            let baseColor: NSColor = NSColor.labelColor
            let dimAlpha: CGFloat = isDark ? 0.4 : 0.25
            let dimColor = baseColor.withAlphaComponent(dimAlpha)

            let fullRange = NSRange(location: 0, length: storage.length)
            let clampedIndex = resolved.isEmpty ? 0 : min(activeIndex, resolved.count - 1)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: dimColor, range: fullRange)
            if !resolved.isEmpty {
                storage.addAttribute(.foregroundColor, value: baseColor, range: resolved[clampedIndex].range)
            }
            storage.endEditing()

            // Track all resolved ranges
            for item in resolved {
                proofreadHighlightedRanges.append(item.range)
            }

            // Scroll the active annotation into view
            if !resolved.isEmpty {
                textView.scrollRangeToVisible(resolved[clampedIndex].range)
            }
        }

        private func clearProofreadOverlays() {
            guard let textView = self.textView,
                  let storage = textView.textStorage else {
                proofreadPillViews.forEach { $0.view.removeFromSuperview() }
                proofreadPillViews.removeAll()
                proofreadHighlightedRanges.removeAll()
                return
            }

            // Remove pill views
            proofreadPillViews.forEach { $0.view.removeFromSuperview() }
            proofreadPillViews.removeAll()

            // Restore full text opacity — preserve user-applied custom colors
            if storage.length > 0 {
                let fullRange = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                storage.enumerateAttribute(
                    TextFormattingManager.customTextColorKey, in: fullRange, options: []
                ) { value, range, _ in
                    if value as? Bool == true {
                        // Custom-colored text: restore full alpha but keep the original color
                        if let color = storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor {
                            storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(1.0), range: range)
                        }
                    } else {
                        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                    }
                }
                storage.endEditing()
            }
            proofreadHighlightedRanges.removeAll()
        }

        // MARK: - Mark / Gutter Markers

        /// Returns true if the entire range has the `.marked` attribute.
        func isRangeFullyMarked(_ range: NSRange, in textView: NSTextView) -> Bool {
            guard range.length > 0, let storage = textView.textStorage else { return false }
            guard NSMaxRange(range) <= storage.length else { return false }
            var fullyMarked = true
            storage.enumerateAttribute(.marked, in: range, options: []) { value, _, stop in
                if value == nil { fullyMarked = false; stop.pointee = true }
            }
            return fullyMarked
        }

        /// Toggles the `.marked` attribute on the selected range.
        /// No background color is applied -- the only visual indicator is the gutter marker.
        func toggleMark(in textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0, let storage = textView.textStorage else { return }
            guard NSMaxRange(range) <= storage.length else { return }

            // Check if the entire range is already marked
            var isFullyMarked = true
            storage.enumerateAttribute(.marked, in: range, options: []) { value, _, stop in
                if value == nil { isFullyMarked = false; stop.pointee = true }
            }

            storage.beginEditing()
            if isFullyMarked {
                storage.removeAttribute(.marked, range: range)
            } else {
                storage.addAttribute(.marked, value: true, range: range)
            }
            storage.endEditing()
        }

        /// Scans text storage for `.marked` attributes, groups contiguous
        /// marked ranges into blocks, and places a marker icon in the left gutter
        /// aligned with the first line of each block.
        func updateHighlightMarkers() {
            guard let textView = self.textView,
                  let storage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            // Remove old markers
            highlightMarkerViews.forEach { $0.removeFromSuperview() }
            highlightMarkerViews.removeAll()

            guard storage.length > 0 else { return }

            // Collect contiguous marked blocks
            let fullRange = NSRange(location: 0, length: storage.length)
            var markedBlocks: [NSRange] = []

            storage.enumerateAttribute(.marked, in: fullRange, options: []) { value, range, _ in
                guard value != nil else { return }
                // Merge with previous block if adjacent
                if let last = markedBlocks.last,
                   NSMaxRange(last) == range.location {
                    markedBlocks[markedBlocks.count - 1] = NSRange(
                        location: last.location,
                        length: last.length + range.length
                    )
                } else {
                    markedBlocks.append(range)
                }
            }

            // Ensure layout is up to date before querying glyph positions
            layoutManager.ensureLayout(for: textContainer)

            let markerSize: CGFloat = 20
            let containerOrigin = textView.textContainerOrigin

            for block in markedBlocks {
                // Get the line fragment for the first character of the block
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: block.location, length: 1),
                    actualCharacterRange: nil
                )
                let usedRect = layoutManager.lineFragmentUsedRect(
                    forGlyphAt: glyphRange.location, effectiveRange: nil
                )

                // Position marker centered in the left gutter.
                // usedRect center is biased upward because it includes descender space,
                // so nudge down by half the descender to hit the visual text center.
                let font = storage.attribute(.font, at: block.location, effectiveRange: nil) as? NSFont
                    ?? NSFont.systemFont(ofSize: 17)
                let descenderNudge = abs(font.descender) / 2
                let markerX = (containerOrigin.x - markerSize) / 2
                let textMidY = usedRect.origin.y + containerOrigin.y + usedRect.height / 2 + descenderNudge
                let markerY = textMidY - markerSize / 2

                let markerView = HighlightMarkerView(
                    frame: NSRect(x: markerX, y: markerY, width: markerSize, height: markerSize)
                )
                markerView.toolTip = "Mark"

                textView.addSubview(markerView)
                highlightMarkerViews.append(markerView)
            }
        }

        private func applyProofreadSuggestion(original: String, replacement: String) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            let fullString = storage.string as NSString
            let found = fullString.range(of: original, options: .literal, range: NSRange(location: 0, length: fullString.length))
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

        private func applyEditContentReplacement(original: String, replacement: String) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            if original.isEmpty {
                // Full-document replacement
                let fullRange = NSRange(location: 0, length: storage.length)
                if textView.shouldChangeText(in: fullRange, replacementString: replacement) {
                    storage.replaceCharacters(in: fullRange, with: replacement)
                    textView.didChangeText()
                }
            } else {
                // Selection replacement -- find original text in storage
                let fullString = storage.string as NSString
                let found = fullString.range(of: original, options: .literal)
                guard found.location != NSNotFound else { return }

                if textView.shouldChangeText(in: found, replacementString: replacement) {
                    storage.replaceCharacters(in: found, with: replacement)
                    textView.didChangeText()
                }
            }
            syncText()
        }

        // MARK: - Batch Proofread Replace All (via notification)

        private func replaceAllProofreadSuggestions(_ annotations: [ProofreadAnnotation]) {
            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            let fullString = storage.string as NSString
            var resolved: [(annotation: ProofreadAnnotation, location: Int)] = annotations.compactMap { ann in
                let range = fullString.range(of: ann.original, options: .literal)
                guard range.location != NSNotFound else { return nil }
                return (ann, range.location)
            }
            resolved.sort { $0.location > $1.location }  // Descending to preserve indices

            guard !resolved.isEmpty else { return }

            textView.undoManager?.beginUndoGrouping()
            for entry in resolved {
                let ns = storage.string as NSString
                let range = ns.range(of: entry.annotation.original, options: .literal)
                if range.location != NSNotFound,
                   textView.shouldChangeText(in: range, replacementString: entry.annotation.replacement) {
                    storage.replaceCharacters(in: range, with: entry.annotation.replacement)
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
                var info = baseInfo
                info["nsRange"] = NSRange(location: NSNotFound, length: 0)
                info["selectedText"] = ""
                info["windowRect"] = CGRect.zero
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

            // Dim non-matched text: explicit colors per mode to avoid dynamic color resolution issues
            let dimColor: NSColor = (currentColorScheme == .dark)
                ? NSColor.white.withAlphaComponent(0.4)
                : NSColor.black.withAlphaComponent(0.3)
            layoutManager.addTemporaryAttribute(.foregroundColor, value: dimColor, forCharacterRange: fullRange)

            // Remove the dim overlay on matched ranges so original colors show through
            for matchRange in ranges {
                guard matchRange.location + matchRange.length <= storage.length else { continue }
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: matchRange)
            }

            // Scroll active match into view and play impulse
            if activeIndex >= 0 && activeIndex < ranges.count {
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

            // Remove temporary dim overlay — original storage colors are untouched
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
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
                } else {
                    NSLog("📄 ingestDroppedURL: Failed to persist image at %@", url.path)
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

            NSLog("📄 ingestDroppedURL: Unhandled file type for %@", url.path)
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
            if let fileLinkAttachment = attachment as? FileLinkAttachment {
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
                            NSLog("FileLinkOpen: startAccessingSecurityScopedResource failed for %@", path)
                            Self.promptRelink(originalPath: path, textView: textView, charIndex: charIndex)
                            return true
                        }

                        // Refresh stale bookmark while we still have access
                        if isStale {
                            Self.refreshFileLinkBookmark(resolvedURL, textView: textView, charIndex: charIndex)
                        }

                        // Use async open so security scope stays active until handoff completes
                        let config = NSWorkspace.OpenConfiguration()
                        NSWorkspace.shared.open(resolvedURL, configuration: config) { _, error in
                            resolvedURL.stopAccessingSecurityScopedResource()
                            if let error {
                                NSLog("FileLinkOpen: NSWorkspace.open failed: %@", error.localizedDescription)
                            }
                        }
                        return true
                    }
                }
                // Bookmark missing or resolution failed — prompt user to re-select the file
                NSLog("FileLinkOpen: bookmark empty or resolution failed for %@", path)
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
                NSLog("FileLinkOpen: refreshed stale bookmark for %@", url.lastPathComponent)
            } catch {
                NSLog("FileLinkOpen: failed to refresh bookmark — %@", error.localizedDescription)
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
                        NSLog("FileLinkOpen: re-linked %@ via user selection", url.lastPathComponent)
                    }

                    // Now open the file
                    let config = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.open(url, configuration: config) { _, error in
                        if let error {
                            NSLog("FileLinkOpen: re-linked open failed: %@", error.localizedDescription)
                        }
                    }
                }
            }
        }

        func updateColorScheme(_ scheme: ColorScheme) {
            currentColorScheme = scheme
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
            // Create image overlays. updateImageOverlays now falls back to
            // the text view itself as host when there's no enclosingScrollView,
            // so this works even during makeNSView before the view hierarchy exists.
            // Mark deferred so completeDeferredSetup can upgrade the host later
            // if an NSScrollView appears (better coordinate system).
            updateImageOverlays(in: textView)
            updateTableOverlays(in: textView)
            updateCalloutOverlays(in: textView)
            updateCodeBlockOverlays(in: textView)

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

            guard text != lastSerialized else { return }

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
            // Ensure overlays are created for deserialized attachments
            updateImageOverlays(in: textView)
            updateTableOverlays(in: textView)
            updateCalloutOverlays(in: textView)
            updateCodeBlockOverlays(in: textView)
            // Highlight markers are repositioned by scheduleOverlayUpdate()
            // when didCompleteLayoutFor fires — no need to call here.

        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, textView == self.textView,
                !isUpdating
            else { return }

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

            // Correct any font family injection from Writing Tools, then inherit typing
            // attributes from the cursor position so bold/italic/heading/color all propagate
            // naturally to the next typed character.
            DispatchQueue.main.async {
                guard !self.isUpdating else { return }

                self.fixInconsistentFonts()

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
                    var attrs = storage.attributes(at: loc, effectiveRange: nil)
                    // Strip notelink attributes so typed text after a mention
                    // doesn't inherit them — prevents ghost duplication on serialize.
                    attrs.removeValue(forKey: .notelinkID)
                    attrs.removeValue(forKey: .notelinkTitle)
                    // Ensure adaptive text color for non-custom ranges
                    if attrs[TextFormattingManager.customTextColorKey] as? Bool != true {
                        // Block quote text uses muted color — preserve it
                        if attrs[.blockQuote] as? Bool == true {
                            attrs[.foregroundColor] = NSColor.labelColor.withAlphaComponent(0.7)
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
            NotificationCenter.default.post(name: .urlPasteDismiss, object: nil)
            NotificationCenter.default.post(name: .codePasteDismiss, object: nil)

            syncText()
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // Check for "@" to trigger note picker
            if replacementString == "@" {
                showNotePickerAtCursor(
                    textView: textView, insertLocation: affectedCharRange.location)
                return true  // Allow the "@" to be typed
            }

            // Check for "/" to trigger command menu
            if replacementString == "/" {
                // Show command menu at cursor position
                showCommandMenuAtCursor(
                    textView: textView, insertLocation: affectedCharRange.location)
                return true  // Allow the "/" to be typed
            }

            // Check for Enter key in todo paragraph
            if replacementString == "\n", isInTodoParagraph(range: affectedCharRange) {
                // If the current todo is empty, exit todo mode instead of creating another
                let storage = textView.textStorage!
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
                let storage = textView.textStorage!
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
                let storage = textView.textStorage!
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
                let storage = textView.textStorage!
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
                    storage.beginEditing()
                    storage.removeAttribute(.blockQuote, range: paraRange)
                    guard let resetStyle = Self.baseParagraphStyle().mutableCopy() as? NSMutableParagraphStyle else { return false }
                    storage.addAttribute(.paragraphStyle, value: resetStyle, range: paraRange)
                    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: paraRange)
                    storage.endEditing()
                    textView.setSelectedRange(NSRange(location: paraRange.location, length: 0))
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
                let safeLen = min(1, storage.length - newParaStart)
                if safeLen > 0 {
                    let newRange = NSRange(location: newParaStart, length: safeLen)
                    storage.addAttribute(.blockQuote, value: true, range: newRange)
                    storage.addAttribute(
                        .paragraphStyle,
                        value: Self.blockQuoteParagraphStyle(),
                        range: newRange)
                    storage.addAttribute(
                        .foregroundColor,
                        value: NSColor.labelColor.withAlphaComponent(0.7),
                        range: newRange)
                }
                storage.endEditing()
                textView.setSelectedRange(NSRange(location: newParaStart, length: 0))
                // Set typing attributes so next typed character inherits quote style
                var typingAttrs = Self.baseTypingAttributes(for: currentColorScheme)
                typingAttrs[.blockQuote] = true
                typingAttrs[.paragraphStyle] = Self.blockQuoteParagraphStyle()
                typingAttrs[.foregroundColor] = NSColor.labelColor.withAlphaComponent(0.7)
                textView.typingAttributes = typingAttrs
                isUpdating = false
                syncText()
                return false
            }

            // Smart backspace: delete an empty todo paragraph entirely
            if replacementString == "" {
                let storage = textView.textStorage!
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
            // Skip animation entirely for paste operations — instant insertion feels right.
            let isPasting = (textView as? InlineNSTextView)?.isPasting ?? false
            if !isUpdating, !isPasting, let replacement = replacementString, !replacement.isEmpty {
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
            guard isInTodoParagraph(range: sel),
                  let storage = textView.textStorage else { return false }

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

        /// Shows the command menu at the current cursor position
        /// Positions menu close to cursor with viewport bounds awareness
        private func showCommandMenuAtCursor(textView: NSTextView, insertLocation: Int) {
            // Get the rect for the cursor position to place the menu
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else {
                return
            }

            // Calculate the glyph range for the insertion point
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: insertLocation)
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

            // Convert to text view's coordinate space
            // This accounts for text container origin (insets/padding)
            let cursorX = glyphRect.origin.x + textView.textContainerOrigin.x
            let cursorY = glyphRect.origin.y + textView.textContainerOrigin.y
            let cursorHeight = glyphRect.height

            // Menu dimensions
            let menuGap: CGFloat = 4
            let safetyMargin: CGFloat = 20
            let menuContentHeight = CommandMenuLayout.idealHeight(for: TodoRichTextEditor.commandMenuActions.count)
            let menuHeight = menuContentHeight + TodoRichTextEditor.commandMenuVerticalPadding
            let menuWidth = TodoRichTextEditor.commandMenuTotalWidth

            // Get the visible rect to check against actual viewport, not total text view bounds
            let visibleRect = textView.visibleRect

            // Check if there's enough space below the cursor in the VISIBLE area
            // This is the key: we check against visibleRect.maxY, not bounds.height
            let cursorBottomY = cursorY + cursorHeight
            let spaceBelow = visibleRect.maxY - cursorBottomY
            let shouldShowAbove = spaceBelow < (menuHeight + menuGap + safetyMargin)

            // Position menu above or below cursor depending on available space
            var xPosition = cursorX
            var yPosition: CGFloat
            if shouldShowAbove {
                // Position above cursor
                yPosition = cursorY - menuHeight - menuGap
            } else {
                // Position below cursor (default)
                yPosition = cursorY + cursorHeight + menuGap
            }

            // Clamp X within visible bounds to avoid clipping
            let minX = visibleRect.minX + safetyMargin
            let maxX = visibleRect.maxX - menuWidth - safetyMargin
            if minX <= maxX {
                xPosition = min(max(xPosition, minX), maxX)
            } else {
                xPosition = max(
                    visibleRect.minX + menuGap,
                    visibleRect.maxX - menuWidth - menuGap
                )
            }

            // Clamp Y to keep menu fully visible
            let minY = visibleRect.minY + safetyMargin
            let maxY = visibleRect.maxY - menuHeight - safetyMargin
            if minY <= maxY {
                yPosition = min(max(yPosition, minY), maxY)
            } else {
                yPosition = max(
                    visibleRect.minY + menuGap,
                    visibleRect.maxY - menuHeight - menuGap
                )
            }

            let menuPosition = CGPoint(x: xPosition, y: yPosition)

            // Only need extra space when menu shows below cursor AND there's not enough space
            let needsExtraSpace = !shouldShowAbove && spaceBelow < (menuHeight + menuGap + safetyMargin)

            // Post notification to show menu
            NotificationCenter.default.post(
                name: .showCommandMenu,
                object: [
                    "position": menuPosition,
                    "slashLocation": insertLocation,
                    "needsSpace": needsExtraSpace
                ],
                userInfo: editorInstanceID.map { ["editorInstanceID": $0] }
            )
        }

        /// Shows the note picker at the current cursor position
        private func showNotePickerAtCursor(textView: NSTextView, insertLocation: Int) {
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else { return }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: insertLocation)
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

            let cursorX = glyphRect.origin.x + textView.textContainerOrigin.x
            let cursorY = glyphRect.origin.y + textView.textContainerOrigin.y
            let cursorHeight = glyphRect.height

            let visibleRect = textView.visibleRect
            let menuGap: CGFloat = 4
            let safetyMargin: CGFloat = 20
            let menuContentHeight = NotePickerLayout.idealHeight(for: 6)  // assume ~6 items
            let menuHeight = menuContentHeight + NotePickerLayout.outerPadding * 2
            let menuWidth = NotePickerLayout.width + NotePickerLayout.outerPadding * 2

            let cursorBottomY = cursorY + cursorHeight
            let spaceBelow = visibleRect.maxY - cursorBottomY
            let shouldShowAbove = spaceBelow < (menuHeight + menuGap + safetyMargin)

            var xPosition = cursorX
            var yPosition: CGFloat
            if shouldShowAbove {
                yPosition = cursorY - menuHeight - menuGap
            } else {
                yPosition = cursorY + cursorHeight + menuGap
            }

            // Clamp X
            let minX = visibleRect.minX + safetyMargin
            let maxX = visibleRect.maxX - menuWidth - safetyMargin
            if minX <= maxX {
                xPosition = min(max(xPosition, minX), maxX)
            } else {
                xPosition = max(visibleRect.minX + menuGap, visibleRect.maxX - menuWidth - menuGap)
            }

            // Clamp Y
            let minY = visibleRect.minY + safetyMargin
            let maxY = visibleRect.maxY - menuHeight - safetyMargin
            if minY <= maxY {
                yPosition = min(max(yPosition, minY), maxY)
            } else {
                yPosition = max(visibleRect.minY + menuGap, visibleRect.maxY - menuHeight - menuGap)
            }

            let menuPosition = CGPoint(x: xPosition, y: yPosition)

            NotificationCenter.default.post(
                name: .showNotePicker,
                object: [
                    "position": menuPosition,
                    "atLocation": insertLocation
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

        /// Handles command menu tool application
        private func handleCommandMenuToolApplication(_ notification: Notification) {
            guard let info = notification.object as? [String: Any],
                let tool = info["tool"] as? EditTool,
                let slashLocation = info["slashLocation"] as? Int,
                let textView = textView,
                let textStorage = textView.textStorage
            else { return }

            // Remove the "/" character that triggered the menu
            if slashLocation >= 0 && slashLocation < textStorage.length {
                let slashRange = NSRange(location: slashLocation, length: 1)
                if textView.shouldChangeText(in: slashRange, replacementString: "") {
                    textStorage.replaceCharacters(in: slashRange, with: "")
                    textView.didChangeText()
                    // Position cursor at the location where "/" was removed
                    textView.setSelectedRange(NSRange(location: slashLocation, length: 0))
                }
            }

            // Apply the selected tool
            // Special handling for todo checkbox to use proper attachment instead of text
            if tool == .todo {
                insertTodo()
            } else {
                formatter.applyFormatting(to: textView, tool: tool)
            }

            // Sync the text back
            syncText()
        }

        // MARK: - Todo Handling

        fileprivate func insertTodo() {
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

            let composed = NSMutableAttributedString()
            if textView.selectedRange().location != 0 {
                composed.append(paragraphBreak)
            }
            composed.append(todoAttachment)
            composed.append(space)

            replaceSelection(with: composed)
            styleTodoParagraphs()
            syncText()
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
            NSLog("📝 insertVoiceTranscript: Called with transcript: %@", transcript)
            guard textView != nil else {
                NSLog("📝 insertVoiceTranscript: textView is nil")
                return
            }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                NSLog("📝 insertVoiceTranscript: trimmed transcript is empty")
                return
            }

            NSLog("📝 insertVoiceTranscript: Inserting trimmed text: %@", trimmed)
            // Add proper spacing and formatting
            let formatted = trimmed + " "
            replaceSelection(
                with: NSAttributedString(
                    string: formatted,
                    attributes: Self.baseTypingAttributes(for: currentColorScheme)))
            syncText()
            NSLog("📝 insertVoiceTranscript: Completed")
        }
        
        private func insertImage(filename: String) {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            // Pre-cache the image so makeImageAttachment uses the real aspect ratio
            // instead of the 4:3 fallback.
            let cacheKey = filename as NSString
            if Self.inlineImageCache.object(forKey: cacheKey) == nil,
               let url = ImageStorageManager.shared.getImageURL(for: filename),
               let img = NSImage(contentsOf: url) {
                Self.inlineImageCache.setObject(img, forKey: cacheKey)
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

        // MARK: - Table Attachment

        private func makeTableAttachment(tableData: NoteTableData) -> NSMutableAttributedString {
            var containerWidth = textView?.textContainer?.containerSize.width ?? 400
            if containerWidth < 1 { containerWidth = 400 }
            let tableWidth = min(tableData.contentWidth, containerWidth)

            let tableHeight = NoteTableOverlayView.computeTableHeight(for: tableData) + 1  // +1 for border

            let attachment = NoteTableAttachment(tableData: tableData)
            let cellSize = CGSize(width: tableWidth, height: tableHeight)
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

            updateTableOverlays(in: textView)
            syncText()
        }

        // MARK: - Callout Insertion

        private func makeCalloutAttachment(calloutData: CalloutData, initialWidth: CGFloat? = nil) -> NSMutableAttributedString {
            // Fill container width; minimum 400pt
            var containerWidth = textView?.textContainer?.containerSize.width ?? CalloutOverlayView.minWidth
            if containerWidth < 1 { containerWidth = CalloutOverlayView.minWidth }
            let calloutWidth = containerWidth

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

        private func makeDividerAttachment() -> NSMutableAttributedString {
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

            updateCalloutOverlays(in: textView)
            updateCodeBlockOverlays(in: textView)

            syncText()
        }

        // MARK: - Code Block Insertion

        private func makeCodeBlockAttachment(codeBlockData: CodeBlockData) -> NSMutableAttributedString {
            var containerWidth = textView?.textContainer?.containerSize.width ?? CodeBlockOverlayView.minWidth
            if containerWidth < 1 { containerWidth = CodeBlockOverlayView.minWidth }
            let blockWidth = containerWidth
            let size = CGSize(width: blockWidth, height: CodeBlockOverlayView.defaultHeight)
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

            updateCodeBlockOverlays(in: textView)
            syncText()
        }

        private func insertFileAttachment(
            using storedFile: FileAttachmentStorageManager.StoredFile
        ) {
            NSLog("📄 insertFileAttachment: Called with stored filename: %@",
                  storedFile.storedFilename)
            guard let textView = textView else {
                NSLog("📄 insertFileAttachment: textView is nil")
                return
            }

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
            NSLog("📄 insertFileAttachment: Completed")
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
                
                // Check if we're inserting an attachment
                attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
                    if let attachment = value as? NSTextAttachment {
                        NSLog("📝 replaceSelection: Inserting attachment at range %@, has image: %@", NSStringFromRange(range), attachment.image != nil ? "YES" : "NO")
                    }
                }
                
                textView.textStorage?.beginEditing()
                textView.textStorage?.replaceCharacters(in: range, with: attributed)
                textView.textStorage?.endEditing()
                textView.setSelectedRange(
                    NSRange(location: range.location + attributed.length, length: 0))
                textView.didChangeText()
                isUpdating = false
            }
        }

        private func syncText() {
            guard let textView = textView else { return }
            isUpdating = true
            styleTodoParagraphs()
            lastSerialized = serialize()
            textBinding.wrappedValue = lastSerialized
            isUpdating = false
            updateImageOverlays(in: textView)
            updateTableOverlays(in: textView)
            updateCalloutOverlays(in: textView)
            updateCodeBlockOverlays(in: textView)

        }

        // MARK: - Inline Image Overlay Management

        func updateImageOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            // Always host overlays on the text view so they use text-view-local
            // coordinates and scroll naturally with content — no conversion needed.
            let hostView: NSView = textView

            if overlayHostView !== hostView {
                imageOverlays.values.forEach { $0.removeFromSuperview() }
                imageOverlays.removeAll()
                overlayHostView = hostView
            }

            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                imageOverlays.values.forEach { $0.removeFromSuperview() }
                imageOverlays.removeAll()
                return
            }

            let containerWidth = textContainer.containerSize.width

            var attachmentCount = 0
            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteImageAttachment else { return }
                attachmentCount += 1
                let filename = attachment.storedFilename
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // ── Recalculate stale attachment bounds ──
                // Bounds may be wrong because:
                //   (a) containerWidth was 0 during makeNSView (replaceLayoutManager resets it)
                //   (b) image wasn't cached at insert time, so a 4:3 fallback AR was used
                // Recalculate whenever width OR aspect ratio diverges from expected values.
                if containerWidth > 1 {
                    let expectedWidth = containerWidth * attachment.widthRatio
                    let aspectRatio: CGFloat
                    let cacheKey = filename as NSString
                    if let cachedImg = Self.inlineImageCache.object(forKey: cacheKey) {
                        aspectRatio = cachedImg.size.height / cachedImg.size.width
                    } else if let overlay = imageOverlays[id], let img = overlay.image {
                        aspectRatio = img.size.height / img.size.width
                    } else {
                        aspectRatio = 3.0 / 4.0
                    }
                    let expectedHeight = expectedWidth * aspectRatio
                    let widthDrift = abs(attachment.bounds.width - expectedWidth)
                    let heightDrift = abs(attachment.bounds.height - expectedHeight)
                    if widthDrift > 1 || heightDrift > 1 {
                        let newSize = CGSize(width: expectedWidth, height: expectedHeight)
                        attachment.attachmentCell = ImageSizeAttachmentCell(size: newSize)
                        attachment.bounds = CGRect(origin: .zero, size: newSize)
                        layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                    }
                }

                // Ensure layout is settled before querying glyph positions.
                // Without this, boundingRect can return stale Y values when
                // called right after styleTodoParagraphs invalidated layout.
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 {
                    layoutManager.ensureLayout(forGlyphRange: glyphRange)
                }

                // Get glyph rect
                guard glyphRange.length > 0 else {
                    return
                }
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: glyphRange, in: textContainer)

                // Position in text-view-local coordinates (host is always the text view)
                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                let ratio = attachment.widthRatio

                // Create or reuse overlay
                let overlay: InlineImageOverlayView
                if let existing = imageOverlays[id] {
                    overlay = existing
                } else {
                    overlay = InlineImageOverlayView(frame: .zero)
                    overlay.storedFilename = filename
                    overlay.containerWidth = containerWidth
                    overlay.currentRatio = ratio
                    overlay.parentTextView = textView

                    overlay.onResizeEnded = { [weak self, weak textStorage, weak textView] newRatio in
                        guard let self = self, let ts = textStorage, let tv = textView else { return }
                        self.updateImageRatio(newRatio, attachment: attachment, in: ts, textView: tv)
                    }

                    // Load image from cache or async
                    let cacheKey = filename as NSString
                    if let cached = Self.inlineImageCache.object(forKey: cacheKey) {
                        overlay.image = cached
                    } else {
                        // Get URL on main actor first
                        guard let url = ImageStorageManager.shared.getImageURL(for: filename) else { return }

                        Task.detached(priority: .userInitiated) {
                            guard let img = NSImage(contentsOf: url) else { return }
                            await MainActor.run { [weak self, weak overlay] in
                                guard let self = self else { return }
                                Self.inlineImageCache.setObject(img, forKey: cacheKey)
                                overlay?.image = img
                                if let tv = self.textView {
                                    self.updateImageOverlays(in: tv)
                                }
                            }
                        }
                    }

                    hostView.addSubview(overlay)
                    imageOverlays[id] = overlay
                }

                overlay.frame = overlayRect.integral
                overlay.containerWidth = containerWidth
            }

            // Remove overlays for deleted attachments
            let toRemove = imageOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemove {
                imageOverlays[key]?.removeFromSuperview()
                imageOverlays.removeValue(forKey: key)
            }
        }

        // MARK: - Inline Table Overlay Management

        func updateTableOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            let hostView: NSView = textView

            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                tableOverlays.values.forEach { $0.removeFromSuperview() }
                tableOverlays.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteTableAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // Correct size drift (row/column count may have changed).
                let containerWidth = textContainer.containerSize.width > 0 ? textContainer.containerSize.width : 400
                let expectedWidth = min(attachment.tableData.contentWidth, containerWidth)
                let expectedHeight = NoteTableOverlayView.computeTableHeight(for: attachment.tableData) + 1
                let sizeDrift = abs(attachment.bounds.height - expectedHeight) + abs(attachment.bounds.width - expectedWidth)
                if sizeDrift > 1 {
                    let newSize = CGSize(width: expectedWidth, height: expectedHeight)
                    attachment.attachmentCell = TableSizeAttachmentCell(size: newSize)
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 {
                    layoutManager.ensureLayout(forGlyphRange: glyphRange)
                }

                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                // Create or reuse overlay
                let overlay: NoteTableOverlayView
                if let existing = tableOverlays[id] {
                    overlay = existing
                    overlay.tableData = attachment.tableData
                } else {
                    overlay = NoteTableOverlayView(tableData: attachment.tableData)
                    overlay.parentTextView = textView

                    overlay.onDataChanged = { [weak self, weak textStorage, weak textView, weak attachment] newData in
                        guard let self = self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        att.tableData = newData

                        // Recalculate attachment size from content width
                        let newHeight = NoteTableOverlayView.computeTableHeight(for: newData) + 1
                        let containerWidth = tv.textContainer?.containerSize.width ?? 400
                        let newWidth = min(newData.contentWidth, containerWidth)
                        let newSize = CGSize(width: newWidth, height: newHeight)
                        att.attachmentCell = TableSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)

                        // Invalidate layout for the attachment character
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                tv.layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }

                        self.syncText()
                    }

                    overlay.onDeleteTable = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self = self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                // Delete attachment char and surrounding newlines
                                var deleteStart = charRange.location
                                var deleteEnd = charRange.location + charRange.length
                                let nsString = ts.string as NSString
                                if deleteStart > 0 {
                                    let prev = nsString.character(at: deleteStart - 1)
                                    if let scalar = Unicode.Scalar(prev), CharacterSet.newlines.contains(scalar) {
                                        deleteStart -= 1
                                    }
                                }
                                if deleteEnd < nsString.length {
                                    let next = nsString.character(at: deleteEnd)
                                    if let scalar = Unicode.Scalar(next), CharacterSet.newlines.contains(scalar) {
                                        deleteEnd += 1
                                    }
                                }
                                let deleteRange = NSRange(location: deleteStart, length: deleteEnd - deleteStart)
                                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                                    ts.replaceCharacters(in: deleteRange, with: "")
                                    tv.didChangeText()
                                }
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    hostView.addSubview(overlay)
                    tableOverlays[id] = overlay
                }

                // Expand frame to cover interactive handle areas outside the table rect.
                // Without this, NSView.hitTest is never called for out-of-frame handle clicks.
                let insets = NoteTableOverlayView.overlayInsets
                let expandedRect = CGRect(
                    x: overlayRect.origin.x - insets.left,
                    y: overlayRect.origin.y - insets.top,
                    width: overlayRect.width + insets.left + insets.right,
                    height: overlayRect.height + insets.top + insets.bottom
                )
                overlay.frame = expandedRect.integral
                overlay.bounds.origin = CGPoint(x: -insets.left, y: -insets.top)
                overlay.tableWidth = attachment.bounds.width
            }

            // Remove overlays for deleted attachments
            let toRemove = tableOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemove {
                tableOverlays[key]?.removeFromSuperview()
                tableOverlays.removeValue(forKey: key)
            }
        }

        // MARK: - Callout Overlay Management

        func updateCalloutOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let hostView: NSView = textView
            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                calloutOverlays.values.forEach { $0.removeFromSuperview() }
                calloutOverlays.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteCalloutAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // Clamp width to valid range; preserve user-resized width if within bounds
                let containerW = max(textContainer.containerSize.width, 100)
                let effectiveMinCallout = min(CalloutOverlayView.minWidth, containerW)
                let currentWidth = attachment.bounds.width
                let needsWidthCorrection = currentWidth < effectiveMinCallout || currentWidth > containerW
                let correctedWidth = needsWidthCorrection
                    ? max(effectiveMinCallout, min(containerW, currentWidth))
                    : currentWidth
                let expectedHeight = CalloutOverlayView.heightForData(
                    attachment.calloutData, width: correctedWidth)
                let heightDrift = abs(attachment.bounds.height - expectedHeight) > 1
                if needsWidthCorrection || heightDrift {
                    let newSize = CGSize(width: correctedWidth, height: expectedHeight)
                    attachment.attachmentCell = CalloutSizeAttachmentCell(size: newSize)
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 { layoutManager.ensureLayout(forGlyphRange: glyphRange) }
                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                let overlay: CalloutOverlayView
                if let existing = calloutOverlays[id] {
                    overlay = existing
                    overlay.calloutData = attachment.calloutData
                } else {
                    overlay = CalloutOverlayView(calloutData: attachment.calloutData)
                    overlay.parentTextView = textView

                    overlay.onDataChanged = { [weak self, weak textStorage, weak attachment] newData in
                        guard let self = self, let ts = textStorage, let att = attachment else { return }
                        att.calloutData = newData
                        let newHeight = CalloutOverlayView.heightForData(newData, width: att.bounds.width)
                        let newSize = CGSize(width: att.bounds.width, height: newHeight)
                        att.attachmentCell = CalloutSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                textView.layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    overlay.onDeleteCallout = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self = self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                var deleteStart = charRange.location
                                var deleteEnd = charRange.location + charRange.length
                                let nsString = ts.string as NSString
                                if deleteStart > 0 {
                                    let prev = nsString.character(at: deleteStart - 1)
                                    if let scalar = Unicode.Scalar(prev), CharacterSet.newlines.contains(scalar) {
                                        deleteStart -= 1
                                    }
                                }
                                if deleteEnd < nsString.length {
                                    let next = nsString.character(at: deleteEnd)
                                    if let scalar = Unicode.Scalar(next), CharacterSet.newlines.contains(scalar) {
                                        deleteEnd += 1
                                    }
                                }
                                let deleteRange = NSRange(location: deleteStart, length: deleteEnd - deleteStart)
                                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                                    ts.replaceCharacters(in: deleteRange, with: "")
                                    tv.didChangeText()
                                }
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    overlay.onWidthChanged = { [weak textStorage, weak layoutManager, weak attachment, weak textView] newWidth in
                        guard let ts = textStorage, let lm = layoutManager, let att = attachment,
                              let tc = textView?.textContainer else { return }
                        let effMin = min(CalloutOverlayView.minWidth, tc.containerSize.width)
                        let clamped = max(effMin, min(newWidth, tc.containerSize.width))
                        let newHeight = CalloutOverlayView.heightForData(att.calloutData, width: clamped)
                        let newSize = CGSize(width: clamped, height: newHeight)
                        att.attachmentCell = CalloutSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                    }

                    hostView.addSubview(overlay)
                    calloutOverlays[id] = overlay
                }

                overlay.currentContainerWidth = containerW
                overlay.frame = overlayRect.integral
            }

            let toRemoveCallout = calloutOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemoveCallout {
                calloutOverlays[key]?.removeFromSuperview()
                calloutOverlays.removeValue(forKey: key)
            }
        }

        // MARK: - Code Block Overlay Management

        func updateCodeBlockOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let hostView: NSView = textView
            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                codeBlockOverlays.values.forEach { $0.removeFromSuperview() }
                codeBlockOverlays.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteCodeBlockAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // Clamp width to valid range; preserve user-resized width if within bounds.
                // Blocks at minWidth after deserialization (container was unknown) get expanded
                // to full container width — minWidth is a floor for user resizing, not a default.
                let containerW = max(textContainer.containerSize.width, 100)
                let effectiveMinCode = min(CodeBlockOverlayView.minWidth, containerW)
                let currentWidth = attachment.bounds.width
                let expectedHeight = CodeBlockOverlayView.defaultHeight
                let atMinFromDeserialization = currentWidth <= effectiveMinCode && containerW > effectiveMinCode
                let needsCorrection = currentWidth < effectiveMinCode
                    || currentWidth > containerW
                    || abs(attachment.bounds.height - expectedHeight) > 1
                    || atMinFromDeserialization
                if needsCorrection {
                    let correctedWidth: CGFloat
                    if atMinFromDeserialization {
                        // Block was created at fallback width — expand to fill container
                        correctedWidth = containerW
                    } else {
                        correctedWidth = max(effectiveMinCode, min(containerW, currentWidth))
                    }
                    let newSize = CGSize(width: correctedWidth, height: expectedHeight)
                    attachment.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 { layoutManager.ensureLayout(forGlyphRange: glyphRange) }
                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                let overlay: CodeBlockOverlayView
                if let existing = codeBlockOverlays[id] {
                    overlay = existing
                    overlay.codeBlockData = attachment.codeBlockData
                } else {
                    overlay = CodeBlockOverlayView(codeBlockData: attachment.codeBlockData)
                    overlay.parentTextView = textView

                    overlay.onDataChanged = { [weak self, weak textStorage, weak attachment] newData in
                        guard let self = self, let ts = textStorage, let att = attachment else { return }
                        att.codeBlockData = newData
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                textView.layoutManager?.invalidateLayout(
                                    forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    overlay.onDeleteCodeBlock = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self = self, let ts = textStorage,
                              let tv = textView, let att = attachment else { return }
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                var deleteStart = charRange.location
                                var deleteEnd = charRange.location + charRange.length
                                let nsString = ts.string as NSString
                                if deleteStart > 0 {
                                    let prev = nsString.character(at: deleteStart - 1)
                                    if let scalar = Unicode.Scalar(prev),
                                       CharacterSet.newlines.contains(scalar) { deleteStart -= 1 }
                                }
                                if deleteEnd < nsString.length {
                                    let next = nsString.character(at: deleteEnd)
                                    if let scalar = Unicode.Scalar(next),
                                       CharacterSet.newlines.contains(scalar) { deleteEnd += 1 }
                                }
                                let deleteRange = NSRange(location: deleteStart,
                                                         length: deleteEnd - deleteStart)
                                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                                    ts.replaceCharacters(in: deleteRange, with: "")
                                    tv.didChangeText()
                                }
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    overlay.onWidthChanged = { [weak textStorage, weak layoutManager, weak attachment, weak textView] newWidth in
                        guard let ts = textStorage, let lm = layoutManager, let att = attachment,
                              let tc = textView?.textContainer else { return }
                        let effMin = min(CodeBlockOverlayView.minWidth, tc.containerSize.width)
                        let clamped = max(effMin, min(newWidth, tc.containerSize.width))
                        let newSize = CGSize(width: clamped, height: CodeBlockOverlayView.defaultHeight)
                        att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                    }

                    hostView.addSubview(overlay)
                    codeBlockOverlays[id] = overlay
                }

                overlay.currentContainerWidth = containerW
                overlay.frame = overlayRect.integral
            }

            let toRemove = codeBlockOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemove {
                codeBlockOverlays[key]?.removeFromSuperview()
                codeBlockOverlays.removeValue(forKey: key)
            }
        }

        private func updateImageRatio(
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

        // MARK: - NSLayoutManagerDelegate

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

        /// Fixes any text that has inconsistent font formatting (e.g., from Writing Tools)
        private func fixInconsistentFonts() {
            guard let textView = textView,
                let textStorage = textView.textStorage
            else { return }

            let expectedAttributes = Self.baseTypingAttributes(for: currentColorScheme)
            guard let expectedFont = expectedAttributes[.font] as? NSFont,
                let expectedColor = expectedAttributes[.foregroundColor] as? NSColor
            else { return }

            textStorage.enumerateAttributes(
                in: NSRange(location: 0, length: textStorage.length)
            ) { attributes, range, _ in
                // Attachment characters (U+FFFC) render through their NSTextAttachmentCell,
                // not through text attributes. Rewriting their attributes with setAttributes
                // can silently strip critical custom keys (.notelinkID, .notelinkTitle, etc.)
                // causing notelinks and other attachments to vanish after serialization.
                if attributes[.attachment] != nil { return }

                var needsFixing = false
                var fixedAttributes: [NSAttributedString.Key: Any] = attributes

                // Check font: correct only when the FAMILY is wrong or size is wrong.
                // Checking family (not name) preserves intentional bold/italic variants
                // in the correct family, while still catching Writing Tools injecting
                // a completely different typeface (e.g. Helvetica into a Charter doc).
                if let currentFont = attributes[.font] as? NSFont {
                    let isHeading = Self.headingLevel(for: currentFont) != nil
                    if !isHeading {
                        let currentFamily = currentFont.familyName ?? currentFont.fontName
                        let expectedFamily = expectedFont.familyName ?? expectedFont.fontName
                        if currentFamily != expectedFamily
                            || currentFont.pointSize != expectedFont.pointSize
                        {
                            // Replace font family but preserve bold/italic traits
                            let traits = NSFontManager.shared.traits(of: currentFont)
                            var replacement = expectedFont
                            if traits.contains(.boldFontMask) {
                                replacement = NSFontManager.shared.convert(
                                    replacement, toHaveTrait: .boldFontMask)
                            }
                            if traits.contains(.italicFontMask) {
                                replacement = NSFontManager.shared.convert(
                                    replacement, toHaveTrait: .italicFontMask)
                            }
                            fixedAttributes[.font] = replacement
                            needsFixing = true
                        }
                    }
                } else {
                    fixedAttributes[.font] = expectedFont
                    needsFixing = true
                }

                // Check text color — skip ranges with a user-intentional custom color or block quote
                let hasCustomColor = attributes[TextFormattingManager.customTextColorKey] as? Bool == true
                let isBlockQuote = attributes[.blockQuote] as? Bool == true
                if !hasCustomColor && !isBlockQuote {
                    if let currentColor = attributes[.foregroundColor] as? NSColor {
                        if !currentColor.isEqual(expectedColor) {
                            fixedAttributes[.foregroundColor] = expectedColor
                            needsFixing = true
                        }
                    } else {
                        fixedAttributes[.foregroundColor] = expectedColor
                        needsFixing = true
                    }
                }

                if needsFixing {
                    textStorage.setAttributes(fixedAttributes, range: range)
                }
            }
        }

        private func styleTodoParagraphs() {
            guard let textStorage = textView?.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.beginEditing()
            // Do NOT blanket-remove .paragraphStyle — heading and alignment styles live there.
            textStorage.removeAttribute(.baselineOffset, range: fullRange)

            var paragraphRange = NSRange(location: 0, length: 0)
            while paragraphRange.location < textStorage.length {
                let substringRange = (textStorage.string as NSString).paragraphRange(
                    for: NSRange(location: paragraphRange.location, length: 0))
                if substringRange.length == 0 { break }
                defer { paragraphRange.location = NSMaxRange(substringRange) }

                var isTodoParagraph = false
                var isWebClipParagraph = false
                var isImageParagraph = false
                var isTableParagraph = false

                textStorage.enumerateAttribute(
                    .attachment,
                    in: NSRange(
                        location: substringRange.location, length: min(1, substringRange.length)
                    ), options: []
                ) { value, _, stop in
                    if let attachment = value as? NSTextAttachment {
                        // Check if it's a todo checkbox
                        if let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell {
                            isTodoParagraph = true
                            cell.invalidateAppearance()
                            stop.pointee = true
                        }
                        // Check if it's a web clip attachment (has webClipTitle attribute)
                        else if textStorage.attribute(
                            .webClipTitle, at: substringRange.location, effectiveRange: nil)
                            != nil
                        {
                            isWebClipParagraph = true
                            stop.pointee = true
                        }
                        // Table attachments need extra top spacing for grab handles
                        else if attachment is NoteTableAttachment {
                            isTableParagraph = true
                            stop.pointee = true
                        }
                        // Other block-level attachments (image, callout, code block)
                        else if attachment is NoteImageAttachment
                                || attachment is NoteCalloutAttachment
                                || attachment is NoteCodeBlockAttachment {
                            isImageParagraph = true
                            stop.pointee = true
                        }
                    }
                }

                // Detect numbered list paragraphs
                var isNumberedListParagraph = false
                if !isTodoParagraph && !isWebClipParagraph && !isImageParagraph && !isTableParagraph {
                    if substringRange.location < textStorage.length,
                       textStorage.attribute(.orderedListNumber, at: substringRange.location, effectiveRange: nil) != nil {
                        isNumberedListParagraph = true
                    }
                }

                // Detect block quote paragraphs
                var isBlockQuoteParagraph = false
                if !isTodoParagraph && !isWebClipParagraph && !isImageParagraph && !isTableParagraph && !isNumberedListParagraph {
                    if substringRange.location < textStorage.length,
                       textStorage.attribute(.blockQuote, at: substringRange.location, effectiveRange: nil) as? Bool == true {
                        isBlockQuoteParagraph = true
                    }
                }

                // Detect heading paragraphs — heading paragraph style is set during
                // deserialization and must not be overwritten here.
                var isHeadingParagraph = false
                if !isTodoParagraph && !isWebClipParagraph && !isNumberedListParagraph && !isBlockQuoteParagraph {
                    textStorage.enumerateAttribute(.font, in: substringRange, options: []) { val, _, stop in
                        if let f = val as? NSFont, Self.headingLevel(for: f) != nil {
                            isHeadingParagraph = true
                            stop.pointee = true
                        }
                    }
                }

                // Apply appropriate paragraph style based on content type
                if isTableParagraph {
                    // Tables need extra top spacing so column grab handles don't overlap content above
                    let tableStyle = NSMutableParagraphStyle()
                    tableStyle.alignment = .left
                    tableStyle.paragraphSpacing = 8
                    tableStyle.paragraphSpacingBefore = 30
                    textStorage.addAttribute(.paragraphStyle, value: tableStyle, range: substringRange)
                } else if isImageParagraph {
                    // Preserve block image paragraph style — do not override
                    let imgStyle = NSMutableParagraphStyle()
                    imgStyle.alignment = .left
                    imgStyle.paragraphSpacing = 8
                    imgStyle.paragraphSpacingBefore = 8
                    textStorage.addAttribute(.paragraphStyle, value: imgStyle, range: substringRange)
                } else if isWebClipParagraph {
                    textStorage.addAttribute(.paragraphStyle, value: Self.webClipParagraphStyle(), range: substringRange)
                } else if isTodoParagraph {
                    textStorage.addAttribute(.paragraphStyle, value: Self.todoParagraphStyle(), range: substringRange)
                } else if isNumberedListParagraph {
                    textStorage.addAttribute(.paragraphStyle, value: Self.orderedListParagraphStyle(), range: substringRange)
                } else if isBlockQuoteParagraph {
                    // Actively enforce block quote paragraph style on every text change,
                    // just like every other block type. Preserves custom alignment if set.
                    guard let quoteStyle = Self.blockQuoteParagraphStyle().mutableCopy() as? NSMutableParagraphStyle else { return }
                    textStorage.enumerateAttribute(.paragraphStyle, in: substringRange, options: []) { val, _, stop in
                        if let ps = val as? NSParagraphStyle, ps.alignment != .left {
                            quoteStyle.alignment = ps.alignment
                            stop.pointee = true
                        }
                    }
                    textStorage.addAttribute(.paragraphStyle, value: quoteStyle, range: substringRange)
                } else if !isHeadingParagraph {
                    // Body paragraph: apply base style but preserve any custom alignment
                    guard let mutableStyle = Self.baseParagraphStyle().mutableCopy() as? NSMutableParagraphStyle else { return }
                    var existingAlignment: NSTextAlignment = .left
                    textStorage.enumerateAttribute(.paragraphStyle, in: substringRange, options: []) { val, _, stop in
                        if let ps = val as? NSParagraphStyle, ps.alignment != .left {
                            existingAlignment = ps.alignment
                            stop.pointee = true
                        }
                    }
                    if existingAlignment != .left { mutableStyle.alignment = existingAlignment }
                    textStorage.addAttribute(.paragraphStyle, value: mutableStyle, range: substringRange)
                }

                // Don't adjust baseline for todo, web clip, heading, image, table, numbered list, or block quote paragraphs
                if !isTodoParagraph && !isWebClipParagraph && !isHeadingParagraph && !isImageParagraph && !isTableParagraph && !isNumberedListParagraph && !isBlockQuoteParagraph {
                    textStorage.addAttribute(
                        .baselineOffset, value: Self.baseBaselineOffset, range: substringRange)
                }

                if isTodoParagraph {
                    textStorage.enumerateAttribute(.attachment, in: substringRange, options: [])
                    { value, attachmentRange, _ in
                        guard let attachment = value as? NSTextAttachment,
                            let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell
                        else { return }
                        attachment.bounds = CGRect(
                            x: 0, y: Self.checkboxAttachmentYOffset,
                            width: Self.checkboxAttachmentWidth, height: Self.checkboxIconSize)
                        textStorage.addAttribute(
                            .baselineOffset, value: Self.checkboxBaselineOffset,
                            range: attachmentRange)
                        cell.invalidateAppearance()
                    }
                }
            }
            textStorage.endEditing()
        }

        private func isInTodoParagraph(range: NSRange) -> Bool {
            guard let storage = textView?.textStorage else { return false }
            let location = max(0, min(storage.length, range.location))
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
            let location = max(0, min(storage.length, range.location))
            guard location < storage.length else { return false }
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

        private func serialize() -> String {
            guard let storage = textView?.textStorage else { return "" }
            let fullRange = NSRange(location: 0, length: storage.length)
            var output = ""
            storage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                if let attachment = attributes[.attachment] as? NSTextAttachment,
                    let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell
                {
                    output.append(cell.isChecked ? "[x]" : "[ ]")
                } else if let urlString = attributes[.plainLinkURL] as? String {
                    let sanitizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                    output.append("[[link|\(sanitizedURL)]]")
                } else if let attachment = attributes[.attachment] as? NSTextAttachment,
                    !(attachment.attachmentCell is TodoCheckboxAttachmentCell),
                    let urlString = Self.linkURLString(from: attributes)
                {
                    var title = Self.cleanedWebClipComponent(attributes[.webClipTitle])
                    let description = Self.cleanedWebClipComponent(
                        attributes[.webClipDescription])
                    let domain = Self.cleanedWebClipComponent(attributes[.webClipDomain])
                    if title.isEmpty {
                        title = domain
                    }
                    let sanitizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                    output.append("[[webclip|\(title)|\(description)|\(sanitizedURL)]]")
                } else if let filePath = attributes[.fileLinkPath] as? String {
                    let displayName = (attributes[.fileLinkDisplayName] as? String) ?? URL(fileURLWithPath: filePath).lastPathComponent
                    let bookmark = (attributes[.fileLinkBookmark] as? String) ?? ""
                    let sanitizedPath = Self.sanitizedWebClipComponent(filePath)
                    let sanitizedName = Self.sanitizedWebClipComponent(displayName)
                    if bookmark.isEmpty {
                        output.append("[[filelink|\(sanitizedPath)|\(sanitizedName)]]")
                    } else {
                        output.append("[[filelink|\(sanitizedPath)|\(sanitizedName)|\(bookmark)]]")
                    }
                } else if let storedFilename = attributes[.fileStoredFilename] as? String {
                    let typeIdentifierRaw = (attributes[.fileTypeIdentifier] as? String) ?? "public.data"
                    let originalNameRaw = (attributes[.fileOriginalFilename] as? String) ?? storedFilename
                    let typeIdentifier = Self.sanitizedWebClipComponent(typeIdentifierRaw)
                    let originalName = Self.sanitizedWebClipComponent(originalNameRaw)
                    output.append("[[file|\(typeIdentifier)|\(storedFilename)|\(originalName)]]")
                } else if let tableAttachment = attributes[.attachment] as? NoteTableAttachment {
                    output.append(tableAttachment.tableData.serialize())
                } else if let calloutAttachment = attributes[.attachment] as? NoteCalloutAttachment {
                    output.append(calloutAttachment.calloutData.serialize())
                } else if let codeBlockAttachment = attributes[.attachment] as? NoteCodeBlockAttachment {
                    output.append(codeBlockAttachment.codeBlockData.serialize())
                } else if attributes[.attachment] is NoteDividerAttachment {
                    output.append("[[divider]]")
                } else if let notelinkAttachment = attributes[.attachment] as? NotelinkAttachment {
                    output.append("[[notelink|\(notelinkAttachment.noteID)|\(notelinkAttachment.noteTitle)]]")
                } else if let nlID = attributes[.notelinkID] as? String,
                          let nlTitle = attributes[.notelinkTitle] as? String {
                    // Notelink fallback — the NotelinkAttachment subclass may have been
                    // degraded to a plain NSTextAttachment by AppKit copy/undo operations,
                    // but the text attributes survive. Catch them before the generic handler.
                    output.append("[[notelink|\(nlID)|\(nlTitle)]]")
                } else if attributes[.webClipTitle] != nil {
                    // Webclip fallback — .link attribute may have been stripped by AppKit,
                    // but webclip metadata attributes survive. Recover the webclip.
                    var title = Self.cleanedWebClipComponent(attributes[.webClipTitle])
                    let description = Self.cleanedWebClipComponent(attributes[.webClipDescription])
                    let domain = Self.cleanedWebClipComponent(attributes[.webClipDomain])
                    if title.isEmpty { title = domain }
                    let url = Self.linkURLString(from: attributes)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? domain
                    output.append("[[webclip|\(title)|\(description)|\(url)]]")
                } else if let attachment = attributes[.attachment] as? NSTextAttachment,
                    !(attachment.attachmentCell is TodoCheckboxAttachmentCell)
                {
                    if let filename = attributes[.imageFilename] as? String {
                        let ratio = attributes[.imageWidthRatio] as? CGFloat ?? 1.0
                        if abs(ratio - 1.0) < 0.001 {
                            output.append("[[image|||\(filename)]]")
                        } else {
                            output.append("[[image|||\(filename)|||\(String(format: "%.4f", ratio))]]")
                        }
                    } else if let noteAttachment = attachment as? NoteImageAttachment {
                        let ratio = noteAttachment.widthRatio
                        if abs(ratio - 1.0) < 0.001 {
                            output.append("[[image|||\(noteAttachment.storedFilename)]]")
                        } else {
                            output.append("[[image|||\(noteAttachment.storedFilename)|||\(String(format: "%.4f", ratio))]]")
                        }
                    } else if let fileWrapper = attachment.fileWrapper,
                            let filename = fileWrapper.preferredFilename ?? fileWrapper.filename,
                            !filename.isEmpty,
                            filename.hasSuffix(".jpg")
                    {
                        output.append("[[image|||\(filename)]]")
                    } else {
                        output.append((storage.string as NSString).substring(with: range))
                        NSLog("⚠️ Serialization CRITICAL: Could not find filename for image attachment. Data may be lost.")
                    }
                } else {
                    // Ordered list prefix: the "N. " characters carry orderedListNumber
                    // Emit [[ol|N]] tag and skip the prefix text — it's encoded in the tag
                    if let olNum = attributes[.orderedListNumber] as? Int {
                        output.append("[[ol|\(olNum)]]")
                        return  // Skip the prefix text — it's reconstructed during deserialization
                    }

                    let rangeText = (storage.string as NSString).substring(with: range)

                    // Determine inline formatting for this run
                    let font = attributes[.font] as? NSFont
                    let isBlockQuote = attributes[.blockQuote] as? Bool == true
                    let highlightHex = attributes[.highlightColor] as? String
                    let isMarked = attributes[.marked] as? Bool == true
                    let heading = font.flatMap { Self.headingLevel(for: $0) }

                    var runBold = false
                    var runItalic = false
                    if heading == nil, let f = font {
                        let traits = NSFontManager.shared.traits(of: f)
                        runBold = traits.contains(.boldFontMask)
                        runItalic = traits.contains(.italicFontMask)
                    }
                    let hasUnderline = (attributes[.underlineStyle] as? Int ?? 0) != 0
                    let hasStrikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                    let alignment: NSTextAlignment
                    if let ps = attributes[.paragraphStyle] as? NSParagraphStyle {
                        alignment = ps.alignment
                    } else {
                        alignment = .left
                    }

                    // Build open/close tag wrappers (outer → inner)
                    var openTags = ""
                    var closeTags = ""

                    // Block quote (outermost)
                    if isBlockQuote { openTags += "[[quote]]"; closeTags = "[[/quote]]" + closeTags }

                    // Alignment — emit only for non-left
                    if alignment != .left {
                        switch alignment {
                        case .center:
                            openTags += "[[align:center]]"; closeTags = "[[/align]]" + closeTags
                        case .right:
                            openTags += "[[align:right]]"; closeTags = "[[/align]]" + closeTags
                        case .justified:
                            openTags += "[[align:justify]]"; closeTags = "[[/align]]" + closeTags
                        default:
                            break
                        }
                    }

                    // Heading or bold/italic
                    if let h = heading {
                        switch h {
                        case .h1: openTags += "[[h1]]"; closeTags = "[[/h1]]" + closeTags
                        case .h2: openTags += "[[h2]]"; closeTags = "[[/h2]]" + closeTags
                        case .h3: openTags += "[[h3]]"; closeTags = "[[/h3]]" + closeTags
                        case .none: break
                        }
                    } else {
                        if runBold   { openTags += "[[b]]"; closeTags = "[[/b]]" + closeTags }
                        if runItalic { openTags += "[[i]]"; closeTags = "[[/i]]" + closeTags }
                    }

                    // Underline / strikethrough
                    if hasUnderline     { openTags += "[[u]]"; closeTags = "[[/u]]" + closeTags }
                    if hasStrikethrough { openTags += "[[s]]"; closeTags = "[[/s]]" + closeTags }

                    // Color + highlight (innermost)
                    if attributes[TextFormattingManager.customTextColorKey] as? Bool == true,
                       let nsColor = attributes[.foregroundColor] as? NSColor
                    {
                        let hex = Self.nsColorToHex(nsColor)
                        openTags += "[[color|\(hex)]]"; closeTags = "[[/color]]" + closeTags
                    }
                    if let hlHex = highlightHex {
                        openTags += "[[hl|\(hlHex)]]"; closeTags = "[[/hl]]" + closeTags
                    }
                    if isMarked {
                        openTags += "[[mark]]"; closeTags = "[[/mark]]" + closeTags
                    }

                    output.append(openTags)
                    output.append(rangeText)
                    output.append(closeTags)

                }
            }
            return output
        }

        private func deserialize(_ text: String) -> NSAttributedString {
            // Handle empty text case
            if text.isEmpty {
                return NSAttributedString(
                    string: "", attributes: Self.baseTypingAttributes(for: currentColorScheme))
            }

            // Strip AI metadata block if present — it lives outside the editor's domain.
            // NoteDetailView handles AI persistence separately; the editor only renders content.
            var text = text
            if let aiStart = text.range(of: "\n[[ai-block]]") ?? text.range(of: "[[ai-block]]") {
                text = String(text[text.startIndex..<aiStart.lowerBound])
            }
            guard !text.isEmpty else {
                return NSAttributedString(
                    string: "", attributes: Self.baseTypingAttributes(for: currentColorScheme))
            }

            let result = NSMutableAttributedString()
            var index = text.startIndex
            var lastWasWebClip = false

            // Inline formatting state
            var fmtBold = false
            var fmtItalic = false
            var fmtUnderline = false
            var fmtStrikethrough = false
            var fmtHeading: TextFormattingManager.HeadingLevel = .none
            var fmtAlignment: NSTextAlignment = .left
            var fmtBlockQuote = false
            var fmtHighlightHex: String? = nil
            var fmtMarked = false

            // Buffer for accumulating plain text characters with the same attributes.
            // Flushed as a single NSAttributedString when formatting changes or a tag is hit.
            var textBuffer = ""
            let colorSchemeForBuffer = currentColorScheme
            func flushBuffer() {
                guard !textBuffer.isEmpty else { return }
                var attrs = Self.formattingAttributes(
                    base: colorSchemeForBuffer,
                    heading: fmtHeading,
                    bold: fmtBold,
                    italic: fmtItalic,
                    underline: fmtUnderline, strikethrough: fmtStrikethrough,
                    alignment: fmtAlignment)
                if fmtBlockQuote {
                    attrs[.blockQuote] = true
                    attrs[.paragraphStyle] = Self.blockQuoteParagraphStyle()
                    attrs[.foregroundColor] = NSColor.labelColor.withAlphaComponent(0.7)
                }
                if let hlHex = fmtHighlightHex {
                    attrs[.highlightColor] = hlHex
                    let hlColor = TextFormattingManager.nsColorFromHex(hlHex).withAlphaComponent(0.35)
                    attrs[.backgroundColor] = hlColor
                }
                if fmtMarked {
                    attrs[.marked] = true
                }
                result.append(NSAttributedString(string: textBuffer, attributes: attrs))
                textBuffer = ""
            }

            while index < text.endIndex {
                if text[index...].hasPrefix("[x]") || text[index...].hasPrefix("[ ]") {
                    flushBuffer()
                    let isChecked = text[index...].hasPrefix("[x]")
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = TodoCheckboxAttachmentCell(isChecked: isChecked)
                    attachment.bounds = CGRect(
                        x: 0, y: Self.checkboxAttachmentYOffset, width: Self.checkboxAttachmentWidth,
                        height: Self.checkboxIconSize)
                    let attString = NSMutableAttributedString(attachment: attachment)
                    attString.addAttribute(
                        .baselineOffset, value: Self.checkboxBaselineOffset,
                        range: NSRange(location: 0, length: attString.length))
                    result.append(attString)
                    index = text.index(index, offsetBy: 3)
                    lastWasWebClip = false
                    continue
                } else if text[index...].hasPrefix(Self.webClipMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let webclipText = String(text[index..<endIndex])
                        if let regex = Self.webClipRegex,
                            let match = regex.firstMatch(
                                in: webclipText,
                                options: [],
                                range: NSRange(location: 0, length: webclipText.utf16.count)
                            )
                        {
                            let rawTitle = Self.string(from: match, at: 1, in: webclipText)
                            let rawDescription = Self.string(
                                from: match, at: 2, in: webclipText)
                            let rawURL = Self.string(from: match, at: 3, in: webclipText)

                            let cleanedTitle = Self.sanitizedWebClipComponent(rawTitle)
                            let cleanedDescription = Self.sanitizedWebClipComponent(
                                rawDescription)
                            let normalizedURL = Self.normalizedURL(from: rawURL)
                            let linkForAttachment =
                                normalizedURL.isEmpty ? rawURL : normalizedURL
                            let domain = Self.sanitizedWebClipComponent(
                                Self.resolvedDomain(from: linkForAttachment)
                            )

                            let attachment = makeWebClipAttachment(
                                url: linkForAttachment,
                                title: cleanedTitle.isEmpty ? nil : cleanedTitle,
                                description: cleanedDescription.isEmpty
                                    ? nil : cleanedDescription,
                                domain: domain.isEmpty ? nil : domain
                            )
                            result.append(attachment)

                            // Add space after webclip for horizontal spacing
                            let space = NSAttributedString(
                                string: " ",
                                attributes: Self.baseTypingAttributes(for: currentColorScheme))
                            result.append(space)

                            index = endIndex
                            lastWasWebClip = true
                            continue
                        }
                    }
                } else if text[index...].hasPrefix(Self.plainLinkMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let linkText = String(text[index..<endIndex])
                        if let regex = Self.plainLinkRegex,
                           let match = regex.firstMatch(
                               in: linkText, options: [],
                               range: NSRange(location: 0, length: linkText.utf16.count))
                        {
                            let rawURL = Self.string(from: match, at: 1, in: linkText)
                            let attachment = makePlainLinkAttachment(url: rawURL)
                            result.append(attachment)

                            let space = NSAttributedString(
                                string: " ",
                                attributes: Self.baseTypingAttributes(for: currentColorScheme))
                            result.append(space)

                            index = endIndex
                            lastWasWebClip = true
                            continue
                        }
                    }
                } else if text[index...].hasPrefix(AttachmentMarkup.fileLinkMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let fileLinkText = String(text[index..<endIndex])
                        if let regex = AttachmentMarkup.fileLinkRegex,
                           let match = regex.firstMatch(
                               in: fileLinkText,
                               options: [],
                               range: NSRange(location: 0, length: fileLinkText.utf16.count)
                           )
                        {
                            let filePath = Self.string(from: match, at: 1, in: fileLinkText)
                            let displayName = Self.string(from: match, at: 2, in: fileLinkText)
                            let bookmarkBase64 = Self.string(from: match, at: 3, in: fileLinkText)

                            let baseAttributes = Self.baseTypingAttributes(
                                for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.whitespacesAndNewlines.contains(lastScalar)
                            {
                                let leadingSpace = NSAttributedString(
                                    string: " ", attributes: baseAttributes)
                                result.append(leadingSpace)
                            }

                            let attachment = makeFileLinkAttachment(filePath: filePath, displayName: displayName, bookmarkBase64: bookmarkBase64)
                            result.append(attachment)

                            let shouldAddTrailingSpace: Bool
                            if endIndex < text.endIndex {
                                let nextCharacter = text[endIndex]
                                shouldAddTrailingSpace = !nextCharacter.isWhitespace
                            } else {
                                shouldAddTrailingSpace = true
                            }

                            if shouldAddTrailingSpace {
                                let trailingSpace = NSAttributedString(
                                    string: " ", attributes: baseAttributes)
                                result.append(trailingSpace)
                            }

                            index = endIndex
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix(AttachmentMarkup.fileMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let fileText = String(text[index..<endIndex])
                        if let regex = AttachmentMarkup.fileRegex,
                           let match = regex.firstMatch(
                               in: fileText,
                               options: [],
                               range: NSRange(location: 0, length: fileText.utf16.count)
                           )
                        {
                            let rawType = Self.string(from: match, at: 1, in: fileText)
                            let storedFilename = Self.string(from: match, at: 2, in: fileText)
                            let rawOriginal = Self.string(from: match, at: 3, in: fileText)

                            let typeIdentifier = rawType.isEmpty ? "public.data" : rawType
                            let originalName = rawOriginal.isEmpty ? storedFilename : rawOriginal

                            let storedFile = FileAttachmentStorageManager.StoredFile(
                                storedFilename: storedFilename,
                                originalFilename: originalName,
                                typeIdentifier: typeIdentifier
                            )

                            let metadata = FileAttachmentMetadata(
                                storedFilename: storedFile.storedFilename,
                                originalFilename: storedFile.originalFilename,
                                typeIdentifier: storedFile.typeIdentifier,
                                displayLabel: AttachmentMarkup.displayLabel(for: storedFile)
                            )

                            let baseAttributes = Self.baseTypingAttributes(
                                for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.whitespacesAndNewlines.contains(lastScalar)
                            {
                                let leadingSpace = NSAttributedString(
                                    string: " ", attributes: baseAttributes)
                                result.append(leadingSpace)
                            }

                            let attachment = makeFileAttachment(metadata: metadata)
                            result.append(attachment)

                            let shouldAddTrailingSpace: Bool
                            if endIndex < text.endIndex {
                                let nextCharacter = text[endIndex]
                                shouldAddTrailingSpace = !nextCharacter.isWhitespace
                            } else {
                                shouldAddTrailingSpace = true
                            }

                            if shouldAddTrailingSpace {
                                let trailingSpace = NSAttributedString(
                                    string: " ", attributes: baseAttributes)
                                result.append(trailingSpace)
                            }

                            index = endIndex
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix(AttachmentMarkup.imageMarkupPrefix) {
                    flushBuffer()
                    if let endIndex = text[index...].range(of: "]]")?.upperBound {
                        let imageText = String(text[index..<endIndex])
                        if let regex = AttachmentMarkup.imageRegex,
                            let match = regex.firstMatch(
                                in: imageText,
                                options: [],
                                range: NSRange(location: 0, length: imageText.utf16.count)
                            )
                        {
                            let filename = Self.string(from: match, at: 1, in: imageText)
                            let ratioString = Self.string(from: match, at: 2, in: imageText)
                            let widthRatio = Double(ratioString).map { CGFloat($0) } ?? 1.0

                            // Block-level: ensure newline before image
                            let baseAttributes = Self.baseTypingAttributes(
                                for: currentColorScheme)
                            if result.length > 0,
                                let lastScalar = result.string.unicodeScalars.last,
                                !CharacterSet.newlines.contains(lastScalar)
                            {
                                result.append(NSAttributedString(
                                    string: "\n", attributes: baseAttributes))
                            }

                            let attachment = makeImageAttachment(
                                filename: filename,
                                widthRatio: widthRatio
                            )
                            result.append(attachment)

                            // Ensure newline after so text doesn't flow inline
                            if endIndex < text.endIndex {
                                let nextChar = text[endIndex]
                                if !nextChar.isNewline {
                                    result.append(NSAttributedString(
                                        string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(
                                    string: "\n", attributes: baseAttributes))
                            }

                            index = endIndex
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[table|") {
                    flushBuffer()
                    // Find [[/table]] closing tag
                    let remaining = text[index...]
                    if let closingRange = remaining.range(of: "[[/table]]") {
                        let tableBlock = String(remaining[remaining.startIndex..<closingRange.upperBound])
                        if let tableData = NoteTableData.deserialize(from: tableBlock) {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            // Ensure newline before table
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            let attachment = makeTableAttachment(tableData: tableData)
                            result.append(attachment)

                            // Ensure newline after
                            let afterClosing = closingRange.upperBound
                            if afterClosing < text.endIndex {
                                if !text[afterClosing].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[codeblock|") {
                    flushBuffer()
                    let remaining = text[index...]
                    if let closingRange = remaining.range(of: "[[/codeblock]]") {
                        let codeBlockText = String(remaining[remaining.startIndex..<closingRange.upperBound])
                        if let codeBlockData = CodeBlockData.deserialize(from: codeBlockText) {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                            let attachment = makeCodeBlockAttachment(codeBlockData: codeBlockData)
                            result.append(attachment)
                            let afterClosing = closingRange.upperBound
                            if afterClosing < text.endIndex {
                                if !text[afterClosing].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[callout|") {
                    flushBuffer()
                    let remaining = text[index...]
                    if let closingRange = remaining.range(of: "[[/callout]]") {
                        let calloutBlock = String(remaining[remaining.startIndex..<closingRange.upperBound])
                        if let calloutData = CalloutData.deserialize(from: calloutBlock) {
                            let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                            if result.length > 0,
                               let lastScalar = result.string.unicodeScalars.last,
                               !CharacterSet.newlines.contains(lastScalar) {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            let attachment = makeCalloutAttachment(calloutData: calloutData)
                            result.append(attachment)

                            let afterClosing = closingRange.upperBound
                            if afterClosing < text.endIndex {
                                if !text[afterClosing].isNewline {
                                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                                }
                            } else {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }

                            index = closingRange.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[divider]]") {
                    flushBuffer()
                    let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                    // Ensure preceding newline
                    if result.length > 0,
                       let lastScalar = result.string.unicodeScalars.last,
                       !CharacterSet.newlines.contains(lastScalar) {
                        result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                    }
                    let attachment = makeDividerAttachment()
                    result.append(attachment)
                    result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                    index = text.index(index, offsetBy: "[[divider]]".count)
                    lastWasWebClip = false
                    continue
                } else if text[index...].hasPrefix("[[notelink|") {
                    flushBuffer()
                    let prefixLen = "[[notelink|".count
                    let afterPrefix = text.index(index, offsetBy: prefixLen)
                    if let closeBracket = text[afterPrefix...].range(of: "]]") {
                        let body = String(text[afterPrefix..<closeBracket.lowerBound])
                        let parts = body.split(separator: "|", maxSplits: 1)
                        if parts.count == 2 {
                            let noteIDStr = String(parts[0])
                            let noteTitle = String(parts[1])

                            let notelinkStr = makeNotelinkAttachment(noteID: noteIDStr, noteTitle: noteTitle)
                            result.append(notelinkStr)

                            index = closeBracket.upperBound
                            lastWasWebClip = false
                            continue
                        }
                    }
                } else if text[index...].hasPrefix("[[b]]") {
                    flushBuffer()
                    fmtBold = true
                    index = text.index(index, offsetBy: 5)
                    continue
                } else if text[index...].hasPrefix("[[/b]]") {
                    flushBuffer()
                    fmtBold = false
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[i]]") {
                    flushBuffer()
                    fmtItalic = true
                    index = text.index(index, offsetBy: 5)
                    continue
                } else if text[index...].hasPrefix("[[/i]]") {
                    flushBuffer()
                    fmtItalic = false
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[u]]") {
                    flushBuffer()
                    fmtUnderline = true
                    index = text.index(index, offsetBy: 5)
                    continue
                } else if text[index...].hasPrefix("[[/u]]") {
                    flushBuffer()
                    fmtUnderline = false
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[s]]") {
                    flushBuffer()
                    fmtStrikethrough = true
                    index = text.index(index, offsetBy: 5)
                    continue
                } else if text[index...].hasPrefix("[[/s]]") {
                    flushBuffer()
                    fmtStrikethrough = false
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[code]]") {
                    // Legacy inline code block — migrate to a plaintext code block attachment
                    flushBuffer()
                    let remaining = text[index...]
                    let prefixLen = "[[code]]".count
                    let contentStart = text.index(index, offsetBy: prefixLen)
                    if let closingRange = remaining.range(of: "[[/code]]") {
                        let rawCode = String(remaining[remaining.index(remaining.startIndex, offsetBy: prefixLen)..<closingRange.lowerBound])
                        let legacyData = CodeBlockData(language: "plaintext", code: rawCode)
                        let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                        if result.length > 0,
                           let lastScalar = result.string.unicodeScalars.last,
                           !CharacterSet.newlines.contains(lastScalar) {
                            result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                        }
                        let attachment = makeCodeBlockAttachment(codeBlockData: legacyData)
                        result.append(attachment)
                        let afterClosing = closingRange.upperBound
                        if afterClosing < text.endIndex {
                            if !text[afterClosing].isNewline {
                                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                            }
                        } else {
                            result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                        }
                        index = closingRange.upperBound
                        lastWasWebClip = false
                        continue
                    }
                    // Malformed — skip the tag
                    index = contentStart
                    continue
                } else if text[index...].hasPrefix("[[/code]]") {
                    // Orphaned close tag from legacy format — skip
                    index = text.index(index, offsetBy: 9)
                    continue
                } else if text[index...].hasPrefix("[[ol|") {
                    flushBuffer()
                    // Parse [[ol|N]] — extract the number
                    let prefixLen = "[[ol|".count
                    let afterPrefix = text.index(index, offsetBy: prefixLen)
                    if let closeBracket = text[afterPrefix...].range(of: "]]") {
                        let numStr = String(text[afterPrefix..<closeBracket.lowerBound])
                        let num = Int(numStr) ?? 1
                        let prefix = "\(num). "
                        var attrs = Self.formattingAttributes(
                            base: currentColorScheme,
                            heading: fmtHeading,
                            bold: fmtBold, italic: fmtItalic,
                            underline: fmtUnderline, strikethrough: fmtStrikethrough,
                            alignment: fmtAlignment)
                        attrs[.orderedListNumber] = num
                        result.append(NSAttributedString(string: prefix, attributes: attrs))
                        index = closeBracket.upperBound
                        lastWasWebClip = false
                        continue
                    }
                } else if text[index...].hasPrefix("[[quote]]") {
                    flushBuffer()
                    fmtBlockQuote = true
                    index = text.index(index, offsetBy: 9)
                    continue
                } else if text[index...].hasPrefix("[[/quote]]") {
                    flushBuffer()
                    fmtBlockQuote = false
                    index = text.index(index, offsetBy: 10)
                    continue
                } else if text[index...].hasPrefix("[[hl|") {
                    flushBuffer()
                    let prefixLen = "[[hl|".count
                    let afterPrefix = text.index(index, offsetBy: prefixLen)
                    if let closeBracket = text[afterPrefix...].range(of: "]]") {
                        fmtHighlightHex = String(text[afterPrefix..<closeBracket.lowerBound])
                        index = closeBracket.upperBound
                        continue
                    }
                } else if text[index...].hasPrefix("[[/hl]]") {
                    flushBuffer()
                    fmtHighlightHex = nil
                    index = text.index(index, offsetBy: 7)
                    continue
                } else if text[index...].hasPrefix("[[mark]]") {
                    flushBuffer()
                    fmtMarked = true
                    index = text.index(index, offsetBy: 8)
                    continue
                } else if text[index...].hasPrefix("[[/mark]]") {
                    flushBuffer()
                    fmtMarked = false
                    index = text.index(index, offsetBy: 9)
                    continue
                } else if text[index...].hasPrefix("[[h1]]") {
                    flushBuffer()
                    fmtHeading = .h1
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[/h1]]") {
                    flushBuffer()
                    fmtHeading = .none
                    index = text.index(index, offsetBy: 7)
                    continue
                } else if text[index...].hasPrefix("[[h2]]") {
                    flushBuffer()
                    fmtHeading = .h2
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[/h2]]") {
                    flushBuffer()
                    fmtHeading = .none
                    index = text.index(index, offsetBy: 7)
                    continue
                } else if text[index...].hasPrefix("[[h3]]") {
                    flushBuffer()
                    fmtHeading = .h3
                    index = text.index(index, offsetBy: 6)
                    continue
                } else if text[index...].hasPrefix("[[/h3]]") {
                    flushBuffer()
                    fmtHeading = .none
                    index = text.index(index, offsetBy: 7)
                    continue
                } else if text[index...].hasPrefix("[[align:center]]") {
                    flushBuffer()
                    fmtAlignment = .center
                    index = text.index(index, offsetBy: 16)
                    continue
                } else if text[index...].hasPrefix("[[align:right]]") {
                    flushBuffer()
                    fmtAlignment = .right
                    index = text.index(index, offsetBy: 15)
                    continue
                } else if text[index...].hasPrefix("[[align:justify]]") {
                    flushBuffer()
                    fmtAlignment = .justified
                    index = text.index(index, offsetBy: 17)
                    continue
                } else if text[index...].hasPrefix("[[/align]]") {
                    flushBuffer()
                    fmtAlignment = .left
                    index = text.index(index, offsetBy: 10)
                    continue
                } else if text[index...].hasPrefix("[[color|") {
                    flushBuffer()
                    let prefixLen = "[[color|".count
                    let afterPrefix = text.index(index, offsetBy: prefixLen)
                    if text.distance(from: afterPrefix, to: text.endIndex) >= 8 {
                        let hexEnd = text.index(afterPrefix, offsetBy: 6)
                        let hex = String(text[afterPrefix..<hexEnd])
                        if text[hexEnd...].hasPrefix("]]") {
                            let contentStart = text.index(hexEnd, offsetBy: 2)
                            if let closingRange = text[contentStart...].range(of: "[[/color]]") {
                                let coloredText = String(text[contentStart..<closingRange.lowerBound])
                                var attrs = Self.formattingAttributes(
                                    base: currentColorScheme,
                                    heading: fmtHeading,
                                    bold: fmtBold, italic: fmtItalic,
                                    underline: fmtUnderline, strikethrough: fmtStrikethrough,
                                    alignment: fmtAlignment)
                                attrs[.foregroundColor] = TextFormattingManager.nsColorFromHex(hex)
                                attrs[TextFormattingManager.customTextColorKey] = true
                                result.append(NSAttributedString(string: coloredText, attributes: attrs))
                                index = closingRange.upperBound
                                lastWasWebClip = false
                                continue
                            }
                        }
                    }
                    // Malformed -- fall through to single-char handler
                }

                // Accumulate plain text into buffer instead of one-char-at-a-time appends.
                let char = text[index]

                // Convert newline to space if between webclips
                if char == "\n" && lastWasWebClip {
                    // Check if next non-whitespace char is a webclip
                    var nextIndex = text.index(after: index)
                    while nextIndex < text.endIndex && text[nextIndex].isWhitespace && text[nextIndex] != "\n" {
                        nextIndex = text.index(after: nextIndex)
                    }
                    if nextIndex < text.endIndex && text[nextIndex...].hasPrefix(Self.webClipMarkupPrefix) {
                        textBuffer.append(" ")  // Convert newline to space between webclips
                    } else {
                        textBuffer.append(char)
                    }
                } else {
                    textBuffer.append(char)
                }

                index = text.index(after: index)
                lastWasWebClip = false
            }

            flushBuffer()
            return result
        }

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
            style.maximumLineHeight = scaledHeight + 4
            style.paragraphSpacing = 10
            style.firstLineHeadIndent = 0
            style.headIndent = checkboxAttachmentWidth + 2
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
            return style
        }

        // Paragraph style for web clip attachments — matches base style so line
        // heights stay consistent whether the clip is inline or on its own line.
        static func webClipParagraphStyle() -> NSParagraphStyle {
            return baseParagraphStyle()
        }
        
        static func imageTagVerticalOffset(for height: CGFloat) -> CGFloat {
            let offset = (textFont.capHeight - height) / 2
            return offset
        }

        private static func headingLevel(for font: NSFont) -> TextFormattingManager.HeadingLevel? {
            switch font.pointSize {
            case TextFormattingManager.HeadingLevel.h1.fontSize: return .h1
            case TextFormattingManager.HeadingLevel.h2.fontSize: return .h2
            case TextFormattingManager.HeadingLevel.h3.fontSize: return .h3
            default: return nil
            }
        }

        private static func nsColorToHex(_ color: NSColor) -> String {
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
        private static func formattingAttributes(
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
            // Store text before Writing Tools starts
            textBeforeWritingTools = textView.string
        }

        @available(macOS 15.0, *)
        func textViewWritingToolsDidEnd(_ textView: NSTextView) {
            // Writing Tools finished - textDidChange will handle summary detection
        }
    }
}

final class InlineNSTextView: NSTextView {
    // Static flag to track command menu visibility for keyboard event handling
    static var isCommandMenuShowing = false
    static var commandSlashLocation: Int = -1

    // URL paste menu state
    static var isURLPasteMenuShowing = false
    static var isCodePasteMenuShowing = false

    // Note picker state (triggered by "@")
    static var isNotePickerShowing = false
    static var notePickerAtLocation: Int = -1

    /// When true, mouseMoved sets arrow cursor instead of allowing NSTextView's I-beam.
    /// Set by ContentView when any full-screen panel overlay (settings, search, trash) is open.
    static var isPanelOverlayActive = false

    weak var actionDelegate: TodoEditorRepresentable.Coordinator?
    var editorInstanceID: UUID?
    private var hoverTrackingArea: NSTrackingArea?

    /// Set during paste operations so the coordinator can skip the typing animation.
    var isPasting = false

    override func paste(_ sender: Any?) {
        isPasting = true

        let pastedText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isURL = Self.isLikelyURL(pastedText)
        let beforeLocation = selectedRange().location

        super.paste(sender)
        isPasting = false

        if isURL && !pastedText.isEmpty {
            let afterLocation = selectedRange().location
            let pastedLength = afterLocation - beforeLocation
            if pastedLength > 0 {
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

                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .urlPasteDetected,
                            object: [
                                "url": pastedText,
                                "range": NSValue(range: pastedRange),
                                "rect": NSValue(rect: adjustedRect),
                            ] as [String: Any]
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
                if pastedLength > 0 {
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

                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .codePasteDetected,
                                object: [
                                    "code": insertedText,
                                    "range": NSValue(range: pastedRange),
                                    "rect": NSValue(rect: adjustedRect),
                                    "language": language,
                                ] as [String: Any]
                            )
                        }
                    }
                }
            }
        }
    }

    private static func isLikelyURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else {
            return false
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return true }
        let domainPattern = #"^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+(/.*)?$"#
        return trimmed.range(of: domainPattern, options: .regularExpression) != nil
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
        if fullText.range(of: #"\w+\("#, options: .regularExpression) != nil { mediumCount += 1 }

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
        super.pasteAsPlainText(sender)
        isPasting = false
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
        // Notelink / webclip / plain link hover: show pointing hand cursor
        let mousePoint = convert(event.locationInWindow, from: nil)
        if let textStorage = self.textStorage,
           let layoutManager = self.layoutManager,
           let textContainer = self.textContainer {
            let ptInContainer = CGPoint(
                x: mousePoint.x - textContainerOrigin.x,
                y: mousePoint.y - textContainerOrigin.y)
            let gi = layoutManager.glyphIndex(for: ptInContainer, in: textContainer)
            if gi < layoutManager.numberOfGlyphs {
                let charIdx = layoutManager.characterIndexForGlyph(at: gi)
                if charIdx < textStorage.length {
                    let isNotelink = textStorage.attribute(.attachment, at: charIdx, effectiveRange: nil) is NotelinkAttachment
                        || textStorage.attribute(.notelinkID, at: charIdx, effectiveRange: nil) != nil
                    let isWebclip = textStorage.attribute(.webClipTitle, at: charIdx, effectiveRange: nil) != nil
                    let isPlainLink = textStorage.attribute(.plainLinkURL, at: charIdx, effectiveRange: nil) != nil
                    let isFileLink = textStorage.attribute(.attachment, at: charIdx, effectiveRange: nil) is FileLinkAttachment
                        || textStorage.attribute(.fileLinkPath, at: charIdx, effectiveRange: nil) != nil
                    if isNotelink || isWebclip || isPlainLink || isFileLink {
                        NSCursor.pointingHand.set()
                        return
                    }
                }
            }
        }

        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if actionDelegate?.handleAttachmentHover(at: point, in: self) != true {
            actionDelegate?.endAttachmentHover()
        }
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
        if InlineNSTextView.isURLPasteMenuShowing {
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
                NotificationCenter.default.post(name: .urlPasteDismiss, object: nil)
                return
            default:
                // Any other key dismisses the menu and passes through
                NotificationCenter.default.post(name: .urlPasteDismiss, object: nil)
                super.keyDown(with: event)
                return
            }
        }

        // Handle code paste menu keyboard navigation
        if InlineNSTextView.isCodePasteMenuShowing {
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
        if InlineNSTextView.isNotePickerShowing {
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
                let atLoc = InlineNSTextView.notePickerAtLocation
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
                let atLoc = InlineNSTextView.notePickerAtLocation
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
        guard InlineNSTextView.isCommandMenuShowing else {
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
            let slashLoc = InlineNSTextView.commandSlashLocation
            if cursor <= slashLoc || slashLoc < 0 {
                NotificationCenter.default.post(name: .hideCommandMenu, object: nil, userInfo: eidInfo)
            } else {
                let filterText = readCommandFilterText()
                NotificationCenter.default.post(
                    name: Notification.Name("CommandMenuFilterUpdate"), object: filterText, userInfo: eidInfo)
            }
            return

        default:
            super.keyDown(with: event)
        }
    }

    @available(macOS 10.11, *)
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let eidInfo: [String: Any]? = editorInstanceID.map { ["editorInstanceID": $0] }

        // Check if we're inserting "@" to trigger note picker
        if let str = string as? String, str == "@" {
            // Dismiss if already showing
            if InlineNSTextView.isNotePickerShowing {
                NotificationCenter.default.post(name: .hideNotePicker, object: nil, userInfo: eidInfo)
            }

            let location = selectedRange().location
            super.insertText(string, replacementRange: replacementRange)

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
        if InlineNSTextView.isNotePickerShowing {
            super.insertText(string, replacementRange: replacementRange)
            let filterText = readNotePickerFilterText()
            NotificationCenter.default.post(
                name: .notePickerFilterUpdate, object: filterText, userInfo: eidInfo)
            return
        }

        // Check if we're inserting "/" to trigger command menu
        if let str = string as? String, str == "/" {
            // If menu is already showing, hide it and start fresh
            if InlineNSTextView.isCommandMenuShowing {
                NotificationCenter.default.post(name: .hideCommandMenu, object: nil, userInfo: eidInfo)
            }

            // Get the cursor position before insertion
            let location = selectedRange().location

            // Allow the "/" to be inserted first
            super.insertText(string, replacementRange: replacementRange)

            // Then show the command menu at that position
            if actionDelegate != nil {
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
                        name: .showCommandMenu,
                        object: ["position": menuPosition, "slashLocation": location],
                        userInfo: eidInfo
                    )
                }
            }
            return
        }

        // If command menu is showing, insert the character and update the filter
        if InlineNSTextView.isCommandMenuShowing {
            super.insertText(string, replacementRange: replacementRange)
            let filterText = readCommandFilterText()
            NotificationCenter.default.post(
                name: Notification.Name("CommandMenuFilterUpdate"), object: filterText, userInfo: eidInfo)
            return
        }

        super.insertText(string, replacementRange: replacementRange)

        // Check for markdown shortcuts after insertion
        if let str = string as? String {
            handleMarkdownShortcuts(inserted: str)
        }
    }

    /// Base typing attributes for markdown shortcut results
    private var markdownBaseAttributes: [NSAttributedString.Key: Any] {
        let font = FontManager.bodyNS()
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
    }

    /// Detects and applies markdown-style shortcuts after text insertion
    private func handleMarkdownShortcuts(inserted: String) {
        guard let textStorage = self.textStorage else { return }
        let cursor = selectedRange().location

        // --- Block-level shortcuts (trigger on Space) ---
        if inserted == " " {
            let paraRange = (textStorage.string as NSString).paragraphRange(
                for: NSRange(location: max(0, cursor - 1), length: 0))
            let lineText = (textStorage.string as NSString).substring(with: paraRange)
            let trimmed = lineText.trimmingCharacters(in: .newlines)

            // Only trigger if cursor is right after the pattern (at start of line)
            let cursorInPara = cursor - paraRange.location
            struct BlockPattern {
                let prefix: String
                let action: String
            }
            let patterns: [BlockPattern] = [
                .init(prefix: "- ", action: "bullet"),
                .init(prefix: "* ", action: "bullet"),
                .init(prefix: "[ ] ", action: "todo"),
                .init(prefix: "> ", action: "quote"),
            ]

            for pattern in patterns {
                if trimmed == pattern.prefix.trimmingCharacters(in: .whitespaces)
                    || (cursorInPara == pattern.prefix.count && lineText.hasPrefix(pattern.prefix)) {
                    // Verify cursor position matches end of prefix
                    guard cursorInPara == pattern.prefix.count else { continue }

                    let deleteRange = NSRange(
                        location: paraRange.location,
                        length: pattern.prefix.count)

                    switch pattern.action {
                    case "bullet":
                        textStorage.replaceCharacters(in: deleteRange, with: "")
                        let newCursorPos = paraRange.location
                        setSelectedRange(NSRange(location: newCursorPos, length: 0))
                        if let coord = actionDelegate {
                            coord.formatter.applyFormatting(to: self, tool: .bulletList)
                        }
                        // Position cursor after "• " — toggleBulletList leaves it past the newline
                        setSelectedRange(NSRange(location: paraRange.location + 2, length: 0))
                    case "todo":
                        textStorage.replaceCharacters(in: deleteRange, with: "")
                        let newCursorPos = paraRange.location
                        setSelectedRange(NSRange(location: newCursorPos, length: 0))
                        if let coord = actionDelegate {
                            coord.insertTodo()
                        }
                    case "quote":
                        // Remove "> " prefix and apply block quote formatting atomically.
                        // beginEditing/endEditing prevents processEditing from firing
                        // between the character removal and attribute application — without
                        // this, styleTodoParagraphs() runs before .blockQuote is set
                        // and applies baseParagraphStyle (no indent).
                        textStorage.beginEditing()
                        textStorage.replaceCharacters(in: deleteRange, with: "")
                        let newCursorPos = paraRange.location
                        let newParaRange = (textStorage.string as NSString).paragraphRange(
                            for: NSRange(location: newCursorPos, length: 0))
                        let quoteStyle = TodoEditorRepresentable.Coordinator.blockQuoteParagraphStyle()
                        textStorage.addAttribute(.blockQuote, value: true, range: newParaRange)
                        textStorage.addAttribute(.paragraphStyle, value: quoteStyle, range: newParaRange)
                        textStorage.addAttribute(
                            .foregroundColor,
                            value: NSColor.labelColor.withAlphaComponent(0.7),
                            range: newParaRange)
                        textStorage.endEditing()
                        setSelectedRange(NSRange(location: newCursorPos, length: 0))
                        // Set typing attributes so first typed character gets the full style
                        var quoteTyping = TodoEditorRepresentable.Coordinator.baseTypingAttributes(
                            for: actionDelegate?.currentColorScheme)
                        quoteTyping[.blockQuote] = true
                        quoteTyping[.paragraphStyle] = quoteStyle
                        quoteTyping[.foregroundColor] = NSColor.labelColor.withAlphaComponent(0.7)
                        typingAttributes = quoteTyping
                    default:
                        break
                    }
                    return
                }
            }

            // Check for numbered list pattern: "1. " at line start
            let olPattern = /^(\d+)\. $/
            if let match = trimmed.wholeMatch(of: olPattern),
               cursorInPara == trimmed.count {
                let num = Int(match.1) ?? 1
                let deleteRange = NSRange(
                    location: paraRange.location,
                    length: trimmed.count)
                let prefix = "\(num). "
                textStorage.replaceCharacters(in: deleteRange, with: prefix)
                let prefixRange = NSRange(location: paraRange.location, length: prefix.count)
                textStorage.addAttribute(.orderedListNumber, value: num, range: prefixRange)
                setSelectedRange(NSRange(location: paraRange.location + prefix.count, length: 0))
                return
            }
        }

        // --- Inline shortcuts (trigger on closing delimiter) ---
        if inserted == "*" || inserted == "`" || inserted == "~" {
            let paraRange = (textStorage.string as NSString).paragraphRange(
                for: NSRange(location: max(0, cursor - 1), length: 0))
            let lineStart = paraRange.location
            let textBeforeCursor = (textStorage.string as NSString).substring(
                with: NSRange(location: lineStart, length: cursor - lineStart))

            // Bold: **text**
            if inserted == "*" && textBeforeCursor.hasSuffix("*") {
                // Look for opening **
                let searchStr = textBeforeCursor
                if let range = searchStr.range(of: "**", options: .backwards,
                                                range: searchStr.startIndex..<searchStr.index(before: searchStr.endIndex)) {
                    let openOffset = searchStr.distance(from: searchStr.startIndex, to: range.lowerBound)
                    let contentStart = openOffset + 2
                    let contentEnd = searchStr.count - 1  // before the last *
                    if contentEnd > contentStart {
                        let content = String(searchStr[searchStr.index(searchStr.startIndex, offsetBy: contentStart)..<searchStr.index(searchStr.startIndex, offsetBy: contentEnd)])
                        if !content.isEmpty && !content.hasPrefix("*") {
                            // Replace **content** with bold content
                            let absStart = lineStart + openOffset
                            let fullLen = cursor - absStart  // includes closing *
                            let replaceRange = NSRange(location: absStart, length: fullLen)
                            var attrs = markdownBaseAttributes
                            if let font = attrs[.font] as? NSFont {
                                attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                            }
                            textStorage.replaceCharacters(in: replaceRange, with: NSAttributedString(string: content, attributes: attrs))
                            setSelectedRange(NSRange(location: absStart + content.count, length: 0))
                            return
                        }
                    }
                }
            }

            // Italic: *text* (single asterisk, not **)
            if inserted == "*" {
                let searchStr = textBeforeCursor
                // Find last single * that isn't part of **
                if let lastStar = searchStr.lastIndex(of: "*"),
                   lastStar != searchStr.index(before: searchStr.endIndex) {
                    let beforeStar = searchStr.index(before: lastStar)
                    let afterStar = searchStr.index(after: lastStar)
                    // Make sure it's a single * (not **)
                    if (lastStar == searchStr.startIndex || searchStr[beforeStar] != "*")
                        && searchStr[afterStar] != "*" {
                        let openOffset = searchStr.distance(from: searchStr.startIndex, to: lastStar)
                        let contentStart = openOffset + 1
                        let contentEnd = searchStr.count  // before closing *
                        if contentEnd > contentStart {
                            let content = String(searchStr[searchStr.index(searchStr.startIndex, offsetBy: contentStart)...])
                            if !content.isEmpty {
                                let absStart = lineStart + openOffset
                                let fullLen = cursor - absStart
                                let replaceRange = NSRange(location: absStart, length: fullLen)
                                var attrs = markdownBaseAttributes
                                if let font = attrs[.font] as? NSFont {
                                    attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                                }
                                textStorage.replaceCharacters(in: replaceRange, with: NSAttributedString(string: content, attributes: attrs))
                                setSelectedRange(NSRange(location: absStart + content.count, length: 0))
                                return
                            }
                        }
                    }
                }
            }

            // Strikethrough: ~~text~~
            if inserted == "~" && textBeforeCursor.hasSuffix("~") {
                let searchStr = textBeforeCursor
                if let range = searchStr.range(of: "~~", options: .backwards,
                                                range: searchStr.startIndex..<searchStr.index(before: searchStr.endIndex)) {
                    let openOffset = searchStr.distance(from: searchStr.startIndex, to: range.lowerBound)
                    let contentStart = openOffset + 2
                    let contentEnd = searchStr.count - 1
                    if contentEnd > contentStart {
                        let content = String(searchStr[searchStr.index(searchStr.startIndex, offsetBy: contentStart)..<searchStr.index(searchStr.startIndex, offsetBy: contentEnd)])
                        if !content.isEmpty && !content.hasPrefix("~") {
                            let absStart = lineStart + openOffset
                            let fullLen = cursor - absStart
                            let replaceRange = NSRange(location: absStart, length: fullLen)
                            var attrs = markdownBaseAttributes
                            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                            textStorage.replaceCharacters(in: replaceRange, with: NSAttributedString(string: content, attributes: attrs))
                            setSelectedRange(NSRange(location: absStart + content.count, length: 0))
                            return
                        }
                    }
                }
            }
        }

        // --- Divider shortcut: --- or *** at line start, trigger on Enter ---
        // (handled separately since Enter triggers newline insertion)
    }

    /// Reads the text typed after the "@" character to use as a filter for note picker
    private func readNotePickerFilterText() -> String {
        let atLoc = InlineNSTextView.notePickerAtLocation
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
        let slashLoc = InlineNSTextView.commandSlashLocation
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
        // Create a custom context menu for the text editor
        let menu = NSMenu()
        
        // Standard text editing actions
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "v"))
        
        menu.addItem(NSMenuItem.separator())
        
        // Text formatting actions
        menu.addItem(NSMenuItem(title: "Bold", action: #selector(toggleBold(_:)), keyEquivalent: "b"))
        menu.addItem(NSMenuItem(title: "Italic", action: #selector(toggleItalic(_:)), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "Underline", action: #selector(toggleUnderline(_:)), keyEquivalent: "u"))
        
        menu.addItem(NSMenuItem.separator())
        
        // Special formatting actions
        menu.addItem(NSMenuItem(title: "Insert Todo", action: #selector(insertTodo(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Insert Bullet List", action: #selector(insertBulletList(_:)), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        // Select all
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a"))
        
        return menu
    }
    
    // MARK: - Context Menu Actions
    
    @objc private func toggleBold(_ sender: Any?) {
        NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "bold"])
    }
    
    @objc private func toggleItalic(_ sender: Any?) {
        NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "italic"])
    }
    
    @objc private func toggleUnderline(_ sender: Any?) {
        NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "underline"])
    }
    
    @objc private func insertTodo(_ sender: Any?) {
        NotificationCenter.default.post(name: .todoToolbarAction, object: nil)
    }
    
    @objc private func insertBulletList(_ sender: Any?) {
        NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "bulletList"])
    }
}

// MARK: - Highlight Marker View

/// Custom-drawn marker tab that sits in the left gutter next to marked text.
/// Uses `MarkerFillColor` and `MarkerStrokeColor` color sets from the asset
/// catalog so it adapts correctly to light and dark appearances.
private final class HighlightMarkerView: NSView {
    override var isFlipped: Bool { true }

    // Pointy tip at y=9.18 in 18x18 viewBox → 51% down
    static let tipNormalized: CGFloat = 9.18 / 18.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let fillColor = NSColor(named: "MarkerFillColor") ?? .systemBlue
        let strokeColor = NSColor(named: "MarkerStrokeColor") ?? .systemBlue

        // Scale from 18x18 design space, centered in bounds
        let scale = min(bounds.width, bounds.height) / 18.0
        let offsetX = (bounds.width - 18 * scale) / 2
        let offsetY = (bounds.height - 18 * scale) / 2

        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: offsetX + x * scale, y: offsetY + y * scale)
        }

        let path = NSBezierPath()
        path.move(to: p(14.0039, 9.18164))
        path.curve(to: p(13.5674, 10.1416), controlPoint1: p(13.9921, 9.57105), controlPoint2: p(13.8056, 9.87548))
        path.curve(to: p(12.623, 11), controlPoint1: p(13.3386, 10.3971), controlPoint2: p(13.0084, 10.6742))
        path.line(to: p(11.5488, 11.9092))
        path.curve(to: p(10.8164, 12.4082), controlPoint1: p(11.2995, 12.12), controlPoint2: p(11.0853, 12.3097))
        path.curve(to: p(10.1719, 12.5), controlPoint1: p(10.6146, 12.4821), controlPoint2: p(10.4028, 12.4974))
        path.line(to: p(6, 12.5))
        path.curve(to: p(4.83594, 12.459), controlPoint1: p(5.54273, 12.5), controlPoint2: p(5.14931, 12.5011))
        path.curve(to: p(3.93945, 12.0605), controlPoint1: p(4.50824, 12.4149), controlPoint2: p(4.19424, 12.3153))
        path.curve(to: p(3.54102, 11.1641), controlPoint1: p(3.68466, 11.8058), controlPoint2: p(3.58509, 11.4918))
        path.curve(to: p(3.5, 10), controlPoint1: p(3.49888, 10.8507), controlPoint2: p(3.5, 10.4573))
        path.line(to: p(3.5, 8))
        path.curve(to: p(3.54102, 6.83594), controlPoint1: p(3.5, 7.54273), controlPoint2: p(3.49888, 7.14931))
        path.curve(to: p(3.93945, 5.93945), controlPoint1: p(3.58509, 6.50824), controlPoint2: p(3.68466, 6.19424))
        path.curve(to: p(4.83594, 5.54102), controlPoint1: p(4.19424, 5.68466), controlPoint2: p(4.50824, 5.58509))
        path.curve(to: p(6, 5.5), controlPoint1: p(5.14931, 5.49888), controlPoint2: p(5.54273, 5.5))
        path.line(to: p(9.86523, 5.5))
        path.curve(to: p(10.8242, 5.60742), controlPoint1: p(10.2215, 5.5), controlPoint2: p(10.5349, 5.49153))
        path.curve(to: p(11.5918, 6.19141), controlPoint1: p(11.1134, 5.72335), controlPoint2: p(11.3341, 5.94552))
        path.line(to: p(12.7354, 7.28223))
        path.curve(to: p(13.626, 8.19629), controlPoint1: p(13.1004, 7.63062), controlPoint2: p(13.413, 7.92752))
        path.curve(to: p(14.0039, 9.18164), controlPoint1: p(13.8479, 8.47633), controlPoint2: p(14.0156, 8.79205))
        path.close()

        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = scale
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }
}

private final class TodoCheckboxAttachmentCell: NSTextAttachmentCell {
    var isChecked: Bool
    private let size = NSSize(width: 20, height: 32)
    private let checkSize: CGFloat = 16
    private let cornerRadius: CGFloat = 8  // checkSize / 2 → fully circular
    private let borderWidth: CGFloat = 1.5

    init(isChecked: Bool = false) {
        self.isChecked = isChecked
        super.init(imageCell: nil)
    }

    required init(coder: NSCoder) {
        self.isChecked = false
        super.init(coder: coder)
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
        isChecked.toggle()
        if let textView = controlView as? NSTextView {
            textView.didChangeText()
            NotificationCenter.default.post(name: NSText.didChangeNotification, object: textView)
        }
        return true
    }

    func invalidateAppearance() {}

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

                // SF Symbol checkmark
                if let symbolImage = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) {
                    let sizeConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
                    let colorConfig = NSImage.SymbolConfiguration(paletteColors: [NSColor(named: "ButtonPrimaryTextColor") ?? .white])
                    if let configured = symbolImage.withSymbolConfiguration(sizeConfig.applying(colorConfig)) {
                        let symSize = configured.size
                        let symX = xInset + (checkSize - symSize.width) / 2
                        let symY = yInset + (checkSize - symSize.height) / 2
                        configured.draw(in: NSRect(x: symX, y: symY, width: symSize.width, height: symSize.height))
                    }
                }
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
    static let deleteWebClipAttachment = Notification.Name("deleteWebClipAttachment")
    static let applyEditTool = Notification.Name("applyEditTool")
    static let markingApplied = Notification.Name("markingApplied")
    static let markingRemoved = Notification.Name("markingRemoved")

    // Command menu notifications
    static let showCommandMenu = Notification.Name("ShowCommandMenu")
    static let hideCommandMenu = Notification.Name("HideCommandMenu")
    static let commandMenuNavigateUp = Notification.Name("CommandMenuNavigateUp")
    static let commandMenuNavigateDown = Notification.Name("CommandMenuNavigateDown")
    static let commandMenuSelect = Notification.Name("CommandMenuSelect")
    static let applyCommandMenuTool = Notification.Name("ApplyCommandMenuTool")

    // URL paste option menu notifications
    static let urlPasteDetected = Notification.Name("URLPasteDetected")
    static let urlPasteSelectMention = Notification.Name("URLPasteSelectMention")
    static let urlPasteSelectPlainLink = Notification.Name("URLPasteSelectPlainLink")
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
