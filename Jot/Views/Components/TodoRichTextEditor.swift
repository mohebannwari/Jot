//
//  TodoRichTextEditor.swift
//  Jot
//
//  Rebuilt rich text editor that keeps todo checkboxes aligned,
//  clickable, and in sync with serialized markup.
//

import Combine
import SwiftUI

import AppKit
import QuartzCore
import UniformTypeIdentifiers

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

struct TodoRichTextEditor: View {
    @Binding var text: String
    var focusRequestID: UUID?
    var editorInstanceID: UUID?
    var onToolbarAction: ((EditTool) -> Void)?
    var onCommandMenuSelection: ((EditTool) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    private let baseBottomInset: CGFloat = 0

    var availableNotes: [NotePickerItem] = []
    var onNavigateToNote: ((UUID) -> Void)?

    init(
        text: Binding<String>,
        focusRequestID: UUID? = nil,
        editorInstanceID: UUID? = nil,
        onToolbarAction: ((EditTool) -> Void)? = nil,
        onCommandMenuSelection: ((EditTool) -> Void)? = nil,
        availableNotes: [NotePickerItem] = [],
        onNavigateToNote: ((UUID) -> Void)? = nil
    ) {
        self._text = text
        self.focusRequestID = focusRequestID
        self.editorInstanceID = editorInstanceID
        self.onToolbarAction = onToolbarAction
        self.onCommandMenuSelection = onCommandMenuSelection
        self.availableNotes = availableNotes
        self.onNavigateToNote = onNavigateToNote
    }


    // Command menu state (triggered by "/" character)
    @State private var showCommandMenu = false
    @State private var commandMenuRevealed = false
    @State private var commandMenuPosition: CGPoint = .zero
    @State private var commandMenuSelectedIndex = 0
    @State private var commandSlashLocation: Int = -1
    @State private var commandMenuFilterText = ""

    // Note picker state (triggered by "@" character)
    @State private var showNotePicker = false
    @State private var notePickerRevealed = false
    @State private var notePickerPosition: CGPoint = .zero
    @State private var notePickerSelectedIndex = 0
    @State private var notePickerAtLocation: Int = -1
    @State private var notePickerFilterText = ""
    @State private var notePickerItems: [NotePickerItem] = []

    private var filteredNotePickerItems: [NotePickerItem] {
        if notePickerFilterText.isEmpty {
            return notePickerItems
        }
        return notePickerItems.filter {
            $0.title.localizedCaseInsensitiveContains(notePickerFilterText)
        }
    }

    // URL paste option menu state
    @State private var showURLPasteMenu = false
    @State private var urlPasteMenuPosition: CGPoint = .zero
    @State private var urlPasteURL: String = ""
    @State private var urlPasteRange: NSRange = NSRange(location: 0, length: 0)
    static let commandMenuActions: [EditTool] = [.imageUpload, .fileLink, .voiceRecord, .link, .todo, .bulletList, .numberedList, .blockQuote, .codeBlock, .callout, .divider, .table]
    static let commandMenuOuterPadding: CGFloat = CommandMenuLayout.outerPadding
    static let commandMenuHorizontalPadding = commandMenuOuterPadding * 2
    static let commandMenuVerticalPadding = commandMenuOuterPadding * 2
    static let commandMenuTotalWidth: CGFloat =
        CommandMenuLayout.width + commandMenuHorizontalPadding

    private var filteredCommandMenuTools: [EditTool] {
        if commandMenuFilterText.isEmpty {
            return Self.commandMenuActions
        }
        return Self.commandMenuActions.filter {
            $0.name.localizedCaseInsensitiveContains(commandMenuFilterText)
        }
    }

    /// When true, the text view shows arrow cursor instead of I-beam.
    /// Set by ContentView when a full-screen panel overlay is open.
    static var isPanelOverlayActive: Bool {
        get { InlineNSTextView.isPanelOverlayActive }
        set { InlineNSTextView.isPanelOverlayActive = newValue }
    }


    init(
        text: Binding<String>,
        focusRequestID: UUID? = nil,
        onToolbarAction: ((EditTool) -> Void)? = nil,
        onCommandMenuSelection: ((EditTool) -> Void)? = nil
    ) {
        self._text = text
        self.focusRequestID = focusRequestID
        self.onToolbarAction = onToolbarAction
        self.onCommandMenuSelection = onCommandMenuSelection
    }

    private var bottomInset: CGFloat {
            return baseBottomInset
    }

    private var editorWithOverlays: some View {
        Group {
                TodoEditorRepresentable(
                    text: $text,
                    colorScheme: colorScheme,
                    bottomInset: bottomInset,
                    focusRequestID: focusRequestID,
                    editorInstanceID: editorInstanceID,
                    onNavigateToNote: onNavigateToNote
                )
        }
        .frame(maxWidth: .infinity)  // Natural height based on content
        .background(Color.clear)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showCommandMenu && !filteredCommandMenuTools.isEmpty {
                    // Tap-outside scrim to dismiss
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissCommandMenu() }
                        .zIndex(999)

                    CommandMenu(
                        tools: filteredCommandMenuTools,
                        selectedIndex: $commandMenuSelectedIndex,
                        isRevealed: $commandMenuRevealed,
                        onSelect: { tool in handleCommandMenuSelection(tool) }
                    )
                    .offset(
                        x: clampedCommandMenuPosition(for: geometry.size).x,
                        y: clampedCommandMenuPosition(for: geometry.size).y
                    )
                    .allowsHitTesting(commandMenuRevealed)
                    .transition(.identity)
                    .zIndex(1000)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showNotePicker && !filteredNotePickerItems.isEmpty {
                    NotePickerMenu(
                        notes: filteredNotePickerItems,
                        selectedIndex: $notePickerSelectedIndex,
                        isRevealed: $notePickerRevealed,
                        onSelect: { note in handleNotePickerSelection(note) }
                    )
                    .offset(
                        x: clampedNotePickerPosition(for: geometry.size).x,
                        y: clampedNotePickerPosition(for: geometry.size).y
                    )
                    .allowsHitTesting(notePickerRevealed)
                    .transition(.identity)
                    .zIndex(1001)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showURLPasteMenu {
                    URLPasteOptionMenu(
                        onMention: {
                            withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
                            InlineNSTextView.isURLPasteMenuShowing = false
                            NotificationCenter.default.post(
                                name: .urlPasteSelectMention,
                                object: [
                                    "url": urlPasteURL,
                                    "range": NSValue(range: urlPasteRange),
                                ] as [String: Any]
                            )
                        },
                        onPasteAsURL: {
                            withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
                            InlineNSTextView.isURLPasteMenuShowing = false
                            NotificationCenter.default.post(
                                name: .urlPasteSelectPlainLink,
                                object: [
                                    "url": urlPasteURL,
                                    "range": NSValue(range: urlPasteRange),
                                ] as [String: Any]
                            )
                        }
                    )
                    .offset(
                        x: clampedURLPasteMenuPosition(for: geometry.size).x,
                        y: clampedURLPasteMenuPosition(for: geometry.size).y
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                        )
                    )
                    .zIndex(999)
                }
            }
        }
    }

    private var editorWithToolbarNotifications: some View {
        editorWithOverlays
        .onReceive(
            NotificationCenter.default.publisher(for: .todoToolbarAction)
        ) { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            NotificationCenter.default.post(name: .insertTodoInEditor, object: nil, userInfo: editorInstanceID.map { ["editorInstanceID": $0] })
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InsertWebLink"))) {
            notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if let url = notification.object as? String {
                NotificationCenter.default.post(name: .insertWebClipInEditor, object: url, userInfo: editorInstanceID.map { ["editorInstanceID": $0] })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowCommandMenu")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if let info = notification.object as? [String: Any],
                let position = info["position"] as? CGPoint,
                let slashLocation = info["slashLocation"] as? Int
            {
                commandMenuPosition = position
                commandSlashLocation = slashLocation
                commandMenuSelectedIndex = 0
                commandMenuFilterText = ""

                // Show the view in the hierarchy
                showCommandMenu = true
                // Animate the reveal (scale up from cursor + item cascade)
                withAnimation(.bouncy(duration: 0.45)) {
                    commandMenuRevealed = true
                }

                InlineNSTextView.isCommandMenuShowing = true
                InlineNSTextView.commandSlashLocation = slashLocation
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HideCommandMenu")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            dismissCommandMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuFilterUpdate")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            guard showCommandMenu else { return }
            let filter = (notification.object as? String) ?? ""
            commandMenuFilterText = filter
            commandMenuSelectedIndex = 0

            // Auto-hide if no matches
            let matches = Self.commandMenuActions.filter {
                $0.name.localizedCaseInsensitiveContains(filter)
            }
            if !filter.isEmpty && matches.isEmpty {
                dismissCommandMenu()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuNavigateUp")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if showCommandMenu && commandMenuSelectedIndex > 0 {
                commandMenuSelectedIndex -= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuNavigateDown")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            let maxIndex = max(0, filteredCommandMenuTools.count - 1)
            if showCommandMenu && commandMenuSelectedIndex < maxIndex {
                commandMenuSelectedIndex += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuSelect")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if showCommandMenu {
                let tools = filteredCommandMenuTools
                if commandMenuSelectedIndex < tools.count {
                    handleCommandMenuSelection(tools[commandMenuSelectedIndex])
                }
            }
        }
    }

    private var editorWithPickerNotifications: some View {
        editorWithToolbarNotifications
        // Note picker notifications (triggered by "@")
        .onReceive(NotificationCenter.default.publisher(for: .showNotePicker))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if let info = notification.object as? [String: Any],
                let position = info["position"] as? CGPoint,
                let atLocation = info["atLocation"] as? Int
            {
                // Filter out the current note from the picker list
                let notes = availableNotes
                guard !notes.isEmpty else { return }

                notePickerPosition = position
                notePickerAtLocation = atLocation
                notePickerSelectedIndex = 0
                notePickerFilterText = ""
                notePickerItems = notes

                showNotePicker = true
                withAnimation(.bouncy(duration: 0.45)) {
                    notePickerRevealed = true
                }

                InlineNSTextView.isNotePickerShowing = true
                InlineNSTextView.notePickerAtLocation = atLocation
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hideNotePicker))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            dismissNotePicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notePickerFilterUpdate))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            guard showNotePicker else { return }
            let filter = (notification.object as? String) ?? ""
            notePickerFilterText = filter
            notePickerSelectedIndex = 0

            let matches = notePickerItems.filter {
                $0.title.localizedCaseInsensitiveContains(filter)
            }
            if !filter.isEmpty && matches.isEmpty {
                dismissNotePicker()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notePickerNavigateUp))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if showNotePicker && notePickerSelectedIndex > 0 {
                notePickerSelectedIndex -= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notePickerNavigateDown))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            let maxIndex = max(0, filteredNotePickerItems.count - 1)
            if showNotePicker && notePickerSelectedIndex < maxIndex {
                notePickerSelectedIndex += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notePickerSelect))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if showNotePicker {
                let notes = filteredNotePickerItems
                if notePickerSelectedIndex < notes.count {
                    handleNotePickerSelection(notes[notePickerSelectedIndex])
                }
            }
        }
    }

    private var editorWithURLPasteNotifications: some View {
        editorWithPickerNotifications
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteDetected)) { notification in
            guard let info = notification.object as? [String: Any],
                  let url = info["url"] as? String,
                  let rangeValue = info["range"] as? NSValue,
                  let rectValue = info["rect"] as? NSValue else { return }

            let range = rangeValue.rangeValue
            let rect = rectValue.rectValue

            urlPasteURL = url
            urlPasteRange = range

            // Center the menu 8px below the URL text
            // Total width = inner frame (160) + outer padding (12 * 2)
            let menuTotalWidth: CGFloat = 160 + CommandMenuLayout.outerPadding * 2
            let menuX = rect.midX - menuTotalWidth / 2
            let menuY = rect.maxY + 8

            urlPasteMenuPosition = CGPoint(x: max(0, menuX), y: menuY)

            withAnimation(.smooth(duration: 0.2)) {
                showURLPasteMenu = true
            }
            InlineNSTextView.isURLPasteMenuShowing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteDismiss)) { _ in
            if showURLPasteMenu {
                withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
                InlineNSTextView.isURLPasteMenuShowing = false
            }
        }
    }

    var body: some View {
        editorWithURLPasteNotifications
    }

    // MARK: - Command Menu Handlers

    /// Two-phase dismiss: reverse entrance animation, then remove from hierarchy
    private func dismissCommandMenu() {
        // Guard against re-entry: the .hideCommandMenu notification handler
        // at line 1028 also calls this function, so bail if already dismissed.
        guard showCommandMenu || InlineNSTextView.isCommandMenuShowing else { return }

        // Immediately stop keyboard interception
        InlineNSTextView.isCommandMenuShowing = false
        InlineNSTextView.commandSlashLocation = -1

        // Notify NoteDetailView to re-enable scroll (deferred to avoid
        // re-entrant SwiftUI state updates during the current transaction)
        let eidInfo: [String: Any]? = editorInstanceID.map { ["editorInstanceID": $0] }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .hideCommandMenu,
                object: nil,
                userInfo: eidInfo
            )
        }

        // Phase 1: animate reverse entrance (scale down to cursor, items cascade out)
        withAnimation(.smooth(duration: 0.25)) {
            commandMenuRevealed = false
        }

        // Phase 2: remove from hierarchy after exit animation settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !self.commandMenuRevealed else { return }
            self.showCommandMenu = false
            self.commandSlashLocation = -1
            self.commandMenuFilterText = ""
        }
    }

    private func handleCommandMenuSelection(_ tool: EditTool) {
        let filterLength = commandMenuFilterText.count
        let slashLoc = commandSlashLocation

        dismissCommandMenu()

        NotificationCenter.default.post(
            name: .applyCommandMenuTool,
            object: ["tool": tool, "slashLocation": slashLoc, "filterLength": filterLength],
            userInfo: editorInstanceID.map { ["editorInstanceID": $0] }
        )

        if let onCommandMenuSelection {
            onCommandMenuSelection(tool)
        }
    }

    private func clampedCommandMenuPosition(for containerSize: CGSize) -> CGPoint {
        let contentHeight = CommandMenuLayout.idealHeight(for: filteredCommandMenuTools.count)
        let totalHeight = contentHeight + Self.commandMenuVerticalPadding
        let maxX = max(0, containerSize.width - Self.commandMenuTotalWidth)
        let maxY = max(0, containerSize.height - totalHeight)
        let clampedX = min(max(commandMenuPosition.x, 0), maxX)
        let clampedY = min(max(commandMenuPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

    private func clampedURLPasteMenuPosition(for containerSize: CGSize) -> CGPoint {
        let menuWidth: CGFloat = 160 + CommandMenuLayout.outerPadding * 2
        let menuHeight: CGFloat = 68 + CommandMenuLayout.outerPadding * 2
        let maxX = max(0, containerSize.width - menuWidth)
        let maxY = max(0, containerSize.height - menuHeight)
        let clampedX = min(max(urlPasteMenuPosition.x, 0), maxX)
        let clampedY = min(max(urlPasteMenuPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

    // MARK: - Note Picker Helpers

    private func dismissNotePicker() {
        InlineNSTextView.isNotePickerShowing = false
        InlineNSTextView.notePickerAtLocation = -1

        withAnimation(.smooth(duration: 0.25)) {
            notePickerRevealed = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !self.notePickerRevealed else { return }
            self.showNotePicker = false
            self.notePickerAtLocation = -1
            self.notePickerFilterText = ""
            self.notePickerItems = []
        }
    }

    private func handleNotePickerSelection(_ note: NotePickerItem) {
        let filterLength = notePickerFilterText.count
        let atLoc = notePickerAtLocation

        dismissNotePicker()

        NotificationCenter.default.post(
            name: .applyNotePickerSelection,
            object: [
                "noteID": note.id.uuidString,
                "noteTitle": note.title,
                "atLocation": atLoc,
                "filterLength": filterLength,
            ] as [String: Any],
            userInfo: editorInstanceID.map { ["editorInstanceID": $0] }
        )
    }

    private func clampedNotePickerPosition(for containerSize: CGSize) -> CGPoint {
        let outerPadding = NotePickerLayout.outerPadding * 2
        let contentHeight = NotePickerLayout.idealHeight(for: filteredNotePickerItems.count)
        let totalHeight = contentHeight + outerPadding
        let totalWidth = NotePickerLayout.width + outerPadding
        let maxX = max(0, containerSize.width - totalWidth)
        let maxY = max(0, containerSize.height - totalHeight)
        let clampedX = min(max(notePickerPosition.x, 0), maxX)
        let clampedY = min(max(notePickerPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

}

// MARK: - URL Paste Option Menu

struct URLPasteOptionMenu: View {
    let onMention: () -> Void
    let onPasteAsURL: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var focusedOption: Int = 0
    @State private var hoveredOption: Int?

    private let optionCount = 2

    private var activeOption: Int {
        hoveredOption ?? focusedOption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            optionRow(
                iconName: "insert link",
                label: "Mention",
                index: 0,
                action: onMention
            )
            optionRow(
                iconName: "IconGlobe",
                label: "Paste as URL",
                index: 1,
                action: onPasteAsURL
            )
        }
        .padding(CommandMenuLayout.outerPadding)
        .frame(width: 160)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteNavigateUp)) { _ in
            withAnimation(.smooth(duration: 0.1)) {
                hoveredOption = nil
                focusedOption = max(focusedOption - 1, 0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteNavigateDown)) { _ in
            withAnimation(.smooth(duration: 0.1)) {
                hoveredOption = nil
                focusedOption = min(focusedOption + 1, optionCount - 1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteSelectFocused)) { _ in
            let selected = activeOption
            if selected == 0 {
                onMention()
            } else {
                onPasteAsURL()
            }
        }
    }

    private func optionRow(
        iconName: String,
        label: String,
        index: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(iconColor(for: index))

                Text(label)
                    .font(FontManager.heading(size: 13, weight: .regular))
                    .foregroundStyle(textColor(for: index))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                activeOption == index
                    ? Capsule().fill(Color("HoverBackgroundColor"))
                    : nil
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.12)) {
                hoveredOption = isHovered ? index : (hoveredOption == index ? nil : hoveredOption)
            }
        }
    }

    private func iconColor(for index: Int) -> Color {
        activeOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("IconSecondaryColor")
    }

    private func textColor(for index: Int) -> Color {
        activeOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("PrimaryTextColor")
    }
}

