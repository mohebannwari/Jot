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
    fileprivate static let webClipTitle = NSAttributedString.Key("WebClipTitle")
    fileprivate static let webClipDescription = NSAttributedString.Key("WebClipDescription")
    fileprivate static let webClipDomain = NSAttributedString.Key("WebClipDomain")
    fileprivate static let plainLinkURL = NSAttributedString.Key("PlainLinkURL")
    fileprivate static let imageFilename = NSAttributedString.Key("ImageFilename")
    fileprivate static let imageWidthRatio = NSAttributedString.Key("ImageWidthRatio")
    fileprivate static let fileStoredFilename = NSAttributedString.Key("FileStoredFilename")
    fileprivate static let fileOriginalFilename = NSAttributedString.Key("FileOriginalFilename")
    fileprivate static let fileTypeIdentifier = NSAttributedString.Key("FileTypeIdentifier")
    fileprivate static let fileDisplayLabel = NSAttributedString.Key("FileDisplayLabel")
}

private enum AttachmentMarkup {
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
fileprivate final class TypingAnimationLayoutManager: NSLayoutManager {

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
}

/// Dedicated attachment type so that we never lose the stored filename during round-trips.
private final class NoteImageAttachment: NSTextAttachment {
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
private final class ImageSizeAttachmentCell: NSTextAttachmentCell {
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

/// Floating view hosted in the scroll view's clip view that renders an image
/// with rounded corners, drop shadow, subtle border, and edge-based resizing.
/// No visible handle — resize is indicated purely by cursor changes on the
/// right edge, bottom edge, and bottom-right corner. Captures the entire image
/// bounds for hit testing; non-edge clicks are forwarded to the text view.
private final class InlineImageOverlayView: NSView {
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

    /// Corner radius scales proportionally with image width.
    private var computedCornerRadius: CGFloat {
        min(24, max(12, bounds.width * 0.06))
    }

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
            ? NSColor.white.withAlphaComponent(0.12).cgColor
            : NSColor.black.withAlphaComponent(0.08).cgColor
        shadowLayer.shadowOpacity = isDark ? 0.18 : 0.25
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

        // Corner (bottom-right) — added first; edges exclude this region
        let cornerRect = CGRect(x: bounds.maxX - zone, y: bounds.maxY - zone,
                                width: zone, height: zone)
        addCursorRect(cornerRect, cursor: NSCursor.frameResize(position: .bottomRight, directions: .all))

        // Right edge (excluding corner)
        let rightRect = CGRect(x: bounds.maxX - zone, y: bounds.minY,
                               width: zone, height: bounds.height - zone)
        addCursorRect(rightRect, cursor: NSCursor.frameResize(position: .right, directions: .all))

        // Bottom edge (excluding corner)
        let bottomRect = CGRect(x: bounds.minX, y: bounds.maxY - zone,
                                width: bounds.width - zone, height: zone)
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
        guard bounds.contains(point) else { return nil }
        let onRight = point.x >= bounds.maxX - edgeZone
        let onBottom = point.y >= bounds.maxY - edgeZone
        if onRight && onBottom { return .corner }
        if onRight { return .right }
        if onBottom { return .bottom }
        return nil
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if isDragging { return self }
        return bounds.contains(local) ? self : nil
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
private final class NoteFileAttachment: NSTextAttachment {
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

struct TodoRichTextEditor: View {
    @Binding var text: String
    var focusRequestID: UUID?
    var editorInstanceID: UUID?
    var onToolbarAction: ((EditTool) -> Void)?
    var onCommandMenuSelection: ((EditTool) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    private let baseBottomInset: CGFloat = 0

    init(
        text: Binding<String>,
        focusRequestID: UUID? = nil,
        editorInstanceID: UUID? = nil,
        onToolbarAction: ((EditTool) -> Void)? = nil,
        onCommandMenuSelection: ((EditTool) -> Void)? = nil
    ) {
        self._text = text
        self.focusRequestID = focusRequestID
        self.editorInstanceID = editorInstanceID
        self.onToolbarAction = onToolbarAction
        self.onCommandMenuSelection = onCommandMenuSelection
    }


    // Command menu state (triggered by "/" character)
    @State private var showCommandMenu = false
    @State private var commandMenuPosition: CGPoint = .zero
    @State private var commandMenuSelectedIndex = 0
    @State private var commandSlashLocation: Int = -1

    // URL paste option menu state
    @State private var showURLPasteMenu = false
    @State private var urlPasteMenuPosition: CGPoint = .zero
    @State private var urlPasteURL: String = ""
    @State private var urlPasteRange: NSRange = NSRange(location: 0, length: 0)
    fileprivate static let commandMenuActions: [EditTool] = [.imageUpload, .voiceRecord, .link, .todo]
    fileprivate static let commandMenuBaseWidth: CGFloat = CommandMenuLayout.width
    fileprivate static let commandMenuOuterPadding: CGFloat = CommandMenuLayout.outerPadding
    fileprivate static let commandMenuHorizontalPadding = commandMenuOuterPadding * 2
    fileprivate static let commandMenuVerticalPadding = commandMenuOuterPadding * 2
    fileprivate static let commandMenuContentHeight: CGFloat = CommandMenuLayout.idealHeight(
        for: TodoRichTextEditor.commandMenuActions.count)
    fileprivate static let commandMenuTotalWidth: CGFloat =
        commandMenuBaseWidth + commandMenuHorizontalPadding
    fileprivate static let commandMenuTotalHeight: CGFloat =
        commandMenuContentHeight + commandMenuVerticalPadding
    private let commandMenuTools = TodoRichTextEditor.commandMenuActions

    // Static accessor for command menu showing flag (used by keyboard handlers)
    static var isCommandMenuShowing: Bool {
        get { InlineNSTextView.isCommandMenuShowing }
        set { InlineNSTextView.isCommandMenuShowing = newValue }
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

    var body: some View {
        Group {
                TodoEditorRepresentable(
                    text: $text,
                    colorScheme: colorScheme,
                    bottomInset: bottomInset,
                    focusRequestID: focusRequestID,
                    editorInstanceID: editorInstanceID
                )
        }
        .frame(maxWidth: .infinity)  // Natural height based on content
        .background(Color.clear)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showCommandMenu {
                    CommandMenu(
                        tools: commandMenuTools,
                        selectedIndex: $commandMenuSelectedIndex,
                        onSelect: { tool in handleCommandMenuSelection(tool) }
                    )
                    .offset(
                        x: clampedCommandMenuPosition(for: geometry.size).x,
                        y: clampedCommandMenuPosition(for: geometry.size).y
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                        )
                    )
                    .zIndex(1000)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showURLPasteMenu {
                    URLPasteOptionMenu(
                        onMention: {
                            withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
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
            if let info = notification.object as? [String: Any],
                let position = info["position"] as? CGPoint,
                let slashLocation = info["slashLocation"] as? Int
            {
                commandMenuPosition = position
                commandSlashLocation = slashLocation
                commandMenuSelectedIndex = 0

                withAnimation(.smooth(duration: 0.2)) {
                    showCommandMenu = true
                }

                    InlineNSTextView.isCommandMenuShowing = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HideCommandMenu")))
        { _ in
            withAnimation(.smooth(duration: 0.15)) {
                showCommandMenu = false
            }
            commandSlashLocation = -1

                InlineNSTextView.isCommandMenuShowing = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuNavigateUp")))
        { _ in
            if showCommandMenu && commandMenuSelectedIndex > 0 {
                commandMenuSelectedIndex -= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuNavigateDown")))
        { _ in
            let maxIndex = max(0, commandMenuTools.count - 1)
            if showCommandMenu && commandMenuSelectedIndex < maxIndex {
                commandMenuSelectedIndex += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuSelect")))
        { _ in
            if showCommandMenu {
                if commandMenuSelectedIndex < commandMenuTools.count {
                    handleCommandMenuSelection(commandMenuTools[commandMenuSelectedIndex])
                }
            }
        }
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
            let menuWidth: CGFloat = 160
            let menuX = rect.midX - menuWidth / 2
            let menuY = rect.maxY + 8

            urlPasteMenuPosition = CGPoint(x: max(0, menuX), y: menuY)

            withAnimation(.smooth(duration: 0.2)) {
                showURLPasteMenu = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteDismiss)) { _ in
            if showURLPasteMenu {
                withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
            }
        }
    }

    // MARK: - Command Menu Handlers

    private func handleCommandMenuSelection(_ tool: EditTool) {
        withAnimation(.smooth(duration: 0.15)) {
            showCommandMenu = false
        }

            InlineNSTextView.isCommandMenuShowing = false

        NotificationCenter.default.post(
            name: .applyCommandMenuTool,
            object: ["tool": tool, "slashLocation": commandSlashLocation]
        )

        if let onCommandMenuSelection {
            onCommandMenuSelection(tool)
        }

        commandSlashLocation = -1
    }

    private func clampedCommandMenuPosition(for containerSize: CGSize) -> CGPoint {
        let maxX = max(0, containerSize.width - TodoRichTextEditor.commandMenuTotalWidth)
        let maxY = max(0, containerSize.height - TodoRichTextEditor.commandMenuTotalHeight)
        let clampedX = min(max(commandMenuPosition.x, 0), maxX)
        let clampedY = min(max(commandMenuPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

    private func clampedURLPasteMenuPosition(for containerSize: CGSize) -> CGPoint {
        let menuWidth: CGFloat = 160
        let menuHeight: CGFloat = 68
        let maxX = max(0, containerSize.width - menuWidth)
        let maxY = max(0, containerSize.height - menuHeight)
        let clampedX = min(max(urlPasteMenuPosition.x, 0), maxX)
        let clampedY = min(max(urlPasteMenuPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

}

// MARK: - URL Paste Option Menu

struct URLPasteOptionMenu: View {
    let onMention: () -> Void
    let onPasteAsURL: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredOption: Int?

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
                hoveredOption == index
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
        hoveredOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("IconSecondaryColor")
    }

    private func textColor(for index: Int) -> Color {
        hoveredOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("PrimaryTextColor")
    }
}

// MARK: - Representable Implementations


    struct TodoEditorRepresentable: NSViewRepresentable {
        @Binding var text: String
        let colorScheme: ColorScheme
        let bottomInset: CGFloat
        let focusRequestID: UUID?
        let editorInstanceID: UUID?
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
            textView.font = FontManager.bodyNS(size: 16, weight: .regular)
            textView.textContainerInset = NSSize(width: 0, height: 16)
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
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false

            // Critical: Ensure text view accepts text input
            textView.insertionPointColor = NSColor.controlAccentColor

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

            // Update container size only if needed
            if let container = textView.textContainer, let layoutManager = textView.layoutManager {
                let width = textView.bounds.width
                if width > 0 && abs(container.containerSize.width - width) > 0.5 {
                    container.containerSize = NSSize(width: width, height: unlimitedDimension)
                    layoutManager.ensureLayout(for: container)
                }
            }

            // Only update text if it has actually changed
            context.coordinator.updateIfNeeded(with: text)
            context.coordinator.requestFocusIfNeeded(focusRequestID)

            // During makeNSView the text view isn't in the hierarchy yet, so overlay
            // creation and the bounds-change observer registration are deferred.
            // By the time SwiftUI calls updateNSView the view IS hosted — finish setup.
            context.coordinator.completeDeferredSetup(in: textView)

            // Reposition overlays on every SwiftUI layout pass — catches frame
            // changes from sizeThatFits, AI panel insertion/removal, etc.
            context.coordinator.updateImageOverlays(in: textView)
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

            // Update container size for layout calculation
            if abs(container.containerSize.width - targetWidth) > 0.5 {
                container.containerSize = NSSize(width: targetWidth, height: unlimitedDimension)
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
            private let formatter = TextFormattingManager()
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
            private weak var overlayHostView: NSView?
            /// True when applyInitialText ran but the view was not in the hierarchy
            /// yet (no enclosingScrollView), so overlay creation was deferred.
            private var needsDeferredOverlaySetup = false
            /// True once the bounds-change observer on the clip view has been registered.
            private var hasBoundsObserver = false


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

            // Last known non-empty selection — cached here so clicking the AI tools button
            // (which clears the NSTextView selection) doesn't lose context for Edit Content.
            private var lastKnownSelectionRange: NSRange = NSRange(location: NSNotFound, length: 0)
            private var lastKnownSelectionText: String = ""
            private var lastKnownSelectionWindowRect: CGRect = .zero

            // Use Charter for body text as per design requirements
            private static var textFont: NSFont { FontManager.bodyNS(size: 16, weight: .regular) }
            private static let baseLineHeight: CGFloat = 24
            private static let todoLineHeight: CGFloat = 24
            private static let checkboxIconSize: CGFloat = 18
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
                return nil
            }

            init(text: Binding<String>, colorScheme: ColorScheme, focusRequestID: UUID?, editorInstanceID: UUID? = nil) {
                self.textBinding = text
                self.currentColorScheme = colorScheme
                self.lastHandledFocusRequestID = focusRequestID
                self.editorInstanceID = editorInstanceID
            }

            deinit {
                typingAnimationManager?.clearAllAnimations()
                observers.forEach { NotificationCenter.default.removeObserver($0) }
                observers.removeAll()
                imageOverlays.values.forEach { $0.removeFromSuperview() }
                imageOverlays.removeAll()
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
                    overlayHostView = newHost
                }
                // Register as layout manager delegate for overlay position tracking
                textView.layoutManager?.delegate = self
                registerBoundsObserverIfNeeded(for: textView)

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
                        self.formatter.applyFormatting(to: textView, tool: tool)
                        self.styleTodoParagraphs()
                        self.syncText()
                    }
                }

                let applyCommandMenuTool = NotificationCenter.default.addObserver(
                    forName: .applyCommandMenuTool, object: nil, queue: .main
                ) { [weak self] notification in
                    // Extract notification data before passing to MainActor context
                    guard let info = notification.object as? [String: Any],
                          let tool = info["tool"] as? EditTool,
                          let slashLocation = info["slashLocation"] as? Int else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        guard let self = self,
                              let textView = self.textView,
                              let textStorage = textView.textStorage else {
                            return
                        }
                        
                        // Remove the "/" character that triggered the menu
                        if slashLocation >= 0 && slashLocation < textStorage.length {
                            let slashRange = NSRange(location: slashLocation, length: 1)
                            if textView.shouldChangeText(in: slashRange, replacementString: "") {
                                textStorage.replaceCharacters(in: slashRange, with: "")
                                textView.didChangeText()
                            }
                        }

                        // Apply the selected tool
                        // Special handling for todo checkbox to use proper attachment instead of text
                        if tool == .todo {
                            self.insertTodo()
                        } else {
                            self.formatter.applyFormatting(to: textView, tool: tool)
                        }

                        // Sync the text back
                        self.syncText()
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
                    Task { @MainActor [weak self] in
                        self?.replaceURLPasteWithWebClip(url: url, range: rangeValue.rangeValue)
                    }
                }

                let urlPasteSelectPlainLink = NotificationCenter.default.addObserver(
                    forName: .urlPasteSelectPlainLink, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let info = notification.object as? [String: Any],
                          let url = info["url"] as? String,
                          let rangeValue = info["range"] as? NSValue else { return }
                    Task { @MainActor [weak self] in
                        self?.replaceURLPasteWithPlainLink(url: url, range: rangeValue.rangeValue)
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

                observers = [
                    windowKey,
                    insertTodo, insertLink, insertVoiceTranscript, insertImage, applyTool, applyCommandMenuTool,
                    highlightSearch, clearSearch,
                    proofreadShow, proofreadClear, proofreadApply, captureSelection,
                    urlPasteMention, urlPasteSelectPlainLink, urlPasteDismiss,
                    applyColor,
                ]
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
                        if let tv = self?.textView {
                            self?.updateImageOverlays(in: tv)
                        }
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

                // Ensure overlay host is the text view (may still be nil from
                // initial configure if called before the view was in hierarchy).
                if overlayHostView !== textView {
                    needsDeferredOverlaySetup = true
                }

                // If applyInitialText couldn't create overlays, do it now.
                if needsDeferredOverlaySetup {
                    needsDeferredOverlaySetup = false
                    updateImageOverlays(in: textView)
                }
            }

            // MARK: - Proofread Overlay Helpers

            private func applyProofreadAnnotations(_ annotations: [ProofreadAnnotation], activeIndex: Int = 0) {
                guard let textView = self.textView,
                      let storage = textView.textStorage,
                      let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer else { return }

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

                // Restore full text opacity
                if storage.length > 0 {
                    storage.beginEditing()
                    storage.addAttribute(
                        .foregroundColor,
                        value: NSColor.labelColor,
                        range: NSRange(location: 0, length: storage.length)
                    )
                    storage.endEditing()
                }
                proofreadHighlightedRanges.removeAll()
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

            // MARK: - Search Highlighting

            private var searchImpulseView: NSView?

            func applySearchHighlighting(ranges: [NSRange], activeIndex: Int) {
                guard let textView = self.textView,
                      let storage = textView.textStorage else { return }
                let fullRange = NSRange(location: 0, length: storage.length)
                guard fullRange.length > 0 else { return }

                storage.beginEditing()

                // Dim all text to 30% opacity
                storage.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                    if let color = value as? NSColor {
                        storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.3), range: range)
                    }
                }

                // Restore matched ranges to full opacity
                for matchRange in ranges {
                    guard matchRange.location + matchRange.length <= storage.length else { continue }
                    storage.enumerateAttribute(.foregroundColor, in: matchRange, options: []) { value, range, _ in
                        if let color = value as? NSColor {
                            storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(1.0), range: range)
                        }
                    }
                }

                storage.endEditing()

                // Scroll active match into view and play impulse
                if activeIndex >= 0 && activeIndex < ranges.count {
                    textView.scrollRangeToVisible(ranges[activeIndex])
                    playMatchGlow(for: ranges[activeIndex])
                }
            }

            func clearSearchHighlighting() {
                guard let textView = self.textView,
                      let storage = textView.textStorage else { return }
                let fullRange = NSRange(location: 0, length: storage.length)
                guard fullRange.length > 0 else { return }

                // Remove any lingering impulse view
                searchImpulseView?.removeFromSuperview()
                searchImpulseView = nil

                storage.beginEditing()

                // Restore all text to full opacity
                storage.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                    if let color = value as? NSColor {
                        storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(1.0), range: range)
                    }
                }

                storage.endEditing()
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
                guard let urls = fileURLs(from: info) else {
                    return false
                }
                return !urls.isEmpty
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

                if let storedFile = await FileAttachmentStorageManager.shared.saveFile(from: url) {
                    insertFileAttachment(using: storedFile)
                    return
                }

                NSLog("📄 ingestDroppedURL: Unhandled file type for %@", url.path)
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
                }

                let action: AttachmentAction?
                if let storedFilename = attributes[.fileStoredFilename] as? String,
                   let fileURL = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) {
                    action = .file(url: fileURL)
                } else if attributes[.webClipTitle] != nil,
                          let linkValue = attributes[.link] as? String,
                          let url = URL(string: linkValue) {
                    action = .webClip(url: url)
                } else if attributes[.plainLinkURL] != nil,
                          let linkValue = attributes[.link] as? String,
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
                    NSWorkspace.shared.open(url)
                    return true
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
                // Ensure image overlays are created for deserialized attachments
                updateImageOverlays(in: textView)
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
                        let loc = sel.location > 0 ? min(sel.location - 1, storage.length - 1) : 0
                        var attrs = storage.attributes(at: loc, effectiveRange: nil)
                        // Ensure adaptive text color for non-custom ranges
                        if attrs[TextFormattingManager.customTextColorKey] as? Bool != true {
                            attrs[.foregroundColor] = NSColor.labelColor
                        }
                        textView.typingAttributes = attrs
                    } else {
                        textView.typingAttributes = Self.baseTypingAttributes(for: self.currentColorScheme)
                    }
                }

                // Dismiss URL paste menu on any text change
                NotificationCenter.default.post(name: .urlPasteDismiss, object: nil)

                syncText()
            }

            func textView(
                _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                replacementString: String?
            ) -> Bool {
                // Check for "/" to trigger command menu
                if replacementString == "/" {
                    // Show command menu at cursor position
                    showCommandMenuAtCursor(
                        textView: textView, insertLocation: affectedCharRange.location)
                    return true  // Allow the "/" to be typed
                }

                // Check for Enter key in todo paragraph
                if replacementString == "\n", isInTodoParagraph(range: affectedCharRange) {
                    insertTodo()
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
                if isInTodoParagraph(range: textView.selectedRange()) {
                    insertTodo()
                    return true
                }
                return false
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
                let menuHeight = TodoRichTextEditor.commandMenuTotalHeight
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
                    ]
                )
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

            private func insertTodo() {
                guard let textView = textView else { return }
                let attachment = NSTextAttachment()
                let cell = TodoCheckboxAttachmentCell(isChecked: false)
                attachment.attachmentCell = cell
                attachment.bounds = CGRect(
                    x: 0, y: Self.checkboxAttachmentYOffset, width: Self.checkboxIconSize,
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

            private func deleteWebClipAttachment(url: String) {
                guard let textStorage = textView?.textStorage else { return }

                textStorage.enumerateAttribute(
                    .attachment, in: NSRange(location: 0, length: textStorage.length)
                ) { value, range, stop in
                    if value as? NSTextAttachment != nil,
                        let linkValue = textStorage.attribute(
                            .link, at: range.location, effectiveRange: nil) as? String,
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
                var needsLayoutInvalidation = false
                textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                    guard let attachment = val as? NoteImageAttachment else { return }
                    attachmentCount += 1
                    let filename = attachment.storedFilename
                    let id = ObjectIdentifier(attachment)
                    seenIDs.insert(id)

                    // ── Recalculate stale attachment bounds ──
                    // During makeNSView, containerWidth is 0 (replaceLayoutManager resets it).
                    // Attachments created then get bounds={0,0}. Once the real width is known,
                    // recalculate bounds so the layout manager allocates proper glyph space.
                    if containerWidth > 1 {
                        let expectedWidth = containerWidth * attachment.widthRatio
                        if abs(attachment.bounds.width - expectedWidth) > 1 {
                            let aspectRatio: CGFloat
                            let cacheKey = filename as NSString
                            if let cachedImg = Self.inlineImageCache.object(forKey: cacheKey) {
                                aspectRatio = cachedImg.size.height / cachedImg.size.width
                            } else if let overlay = imageOverlays[id], let img = overlay.image {
                                aspectRatio = img.size.height / img.size.width
                            } else {
                                // Use default ratio; the async overlay load will correct
                                // bounds once the image arrives — no synchronous disk I/O.
                                aspectRatio = 3.0 / 4.0
                            }
                            let newSize = CGSize(width: expectedWidth, height: expectedWidth * aspectRatio)
                            attachment.attachmentCell = ImageSizeAttachmentCell(size: newSize)
                            attachment.bounds = CGRect(origin: .zero, size: newSize)
                            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                            needsLayoutInvalidation = true
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
                            Task.detached(priority: .userInitiated) { [weak overlay] in
                                guard let url = ImageStorageManager.shared.getImageURL(for: filename),
                                      let img = NSImage(contentsOf: url) else {
                                    return
                                }
                                Self.inlineImageCache.setObject(img, forKey: cacheKey)
                                let overlayAlive = overlay != nil
                                await MainActor.run { overlay?.image = img }
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
                    guard let self = self, let tv = self.textView else { return }
                    self.updateImageOverlays(in: tv)
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

                    // Check text color — skip ranges with a user-intentional custom color
                    let hasCustomColor = attributes[TextFormattingManager.customTextColorKey] as? Bool == true
                    if !hasCustomColor {
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
                            // Check if it's a block-level image attachment
                            else if attachment is NoteImageAttachment {
                                isImageParagraph = true
                                stop.pointee = true
                            }
                        }
                    }

                    // Detect heading paragraphs — heading paragraph style is set during
                    // deserialization and must not be overwritten here.
                    var isHeadingParagraph = false
                    if !isTodoParagraph && !isWebClipParagraph {
                        textStorage.enumerateAttribute(.font, in: substringRange, options: []) { val, _, stop in
                            if let f = val as? NSFont, Self.headingLevel(for: f) != nil {
                                isHeadingParagraph = true
                                stop.pointee = true
                            }
                        }
                    }

                    // Apply appropriate paragraph style based on content type
                    if isImageParagraph {
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
                    } else if !isHeadingParagraph {
                        // Body paragraph: apply base style but preserve any custom alignment
                        let mutableStyle = Self.baseParagraphStyle().mutableCopy() as! NSMutableParagraphStyle
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

                    // Don't adjust baseline for todo, web clip, heading, or image paragraphs
                    if !isTodoParagraph && !isWebClipParagraph && !isHeadingParagraph && !isImageParagraph {
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
                                width: Self.checkboxIconSize, height: Self.checkboxIconSize)
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

            private func serialize() -> String {
                guard let storage = textView?.textStorage else { return "" }
                let fullRange = NSRange(location: 0, length: storage.length)
                var output = ""
                storage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                    if let attachment = attributes[.attachment] as? NSTextAttachment,
                        let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell
                    {
                        output.append(cell.isChecked ? "[x]" : "[ ]")
                    } else if attributes[.plainLinkURL] is String,
                        let urlString = attributes[.link] as? String
                    {
                        let sanitizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                        output.append("[[link|\(sanitizedURL)]]")
                    } else if let attachment = attributes[.attachment] as? NSTextAttachment,
                        !(attachment.attachmentCell is TodoCheckboxAttachmentCell),
                        let urlString = attributes[.link] as? String
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
                    } else if let storedFilename = attributes[.fileStoredFilename] as? String {
                        let typeIdentifierRaw = (attributes[.fileTypeIdentifier] as? String) ?? "public.data"
                        let originalNameRaw = (attributes[.fileOriginalFilename] as? String) ?? storedFilename
                        let typeIdentifier = Self.sanitizedWebClipComponent(typeIdentifierRaw)
                        let originalName = Self.sanitizedWebClipComponent(originalNameRaw)
                        output.append("[[file|\(typeIdentifier)|\(storedFilename)|\(originalName)]]")
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
                        let rangeText = (storage.string as NSString).substring(with: range)

                        // Determine inline formatting for this run
                        let font = attributes[.font] as? NSFont
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

                        // Alignment (outermost) — emit only for non-left
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

                        // Color (innermost) — preserve existing serialization log
                        if attributes[TextFormattingManager.customTextColorKey] as? Bool == true,
                           let nsColor = attributes[.foregroundColor] as? NSColor
                        {
                            let hex = Self.nsColorToHex(nsColor)
                            output.append(openTags)
                            output.append("[[color|\(hex)]]")
                            output.append(rangeText)
                            output.append("[[/color]]")
                            output.append(closeTags)
                        } else {
                            output.append(openTags)
                            output.append(rangeText)
                            output.append(closeTags)
                        }

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

                let result = NSMutableAttributedString()
                var index = text.startIndex
                var lastWasWebClip = false
                var imageCounter = 0

                // Inline formatting state
                var fmtBold = false
                var fmtItalic = false
                var fmtUnderline = false
                var fmtStrikethrough = false
                var fmtHeading: TextFormattingManager.HeadingLevel = .none
                var fmtAlignment: NSTextAlignment = .left

                // Buffer for accumulating plain text characters with the same attributes.
                // Flushed as a single NSAttributedString when formatting changes or a tag is hit.
                var textBuffer = ""
                let colorSchemeForBuffer = currentColorScheme
                func flushBuffer() {
                    guard !textBuffer.isEmpty else { return }
                    let attrs = Self.formattingAttributes(
                        base: colorSchemeForBuffer,
                        heading: fmtHeading,
                        bold: fmtBold, italic: fmtItalic,
                        underline: fmtUnderline, strikethrough: fmtStrikethrough,
                        alignment: fmtAlignment)
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
                            x: 0, y: Self.checkboxAttachmentYOffset, width: Self.checkboxIconSize,
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
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.2
                style.minimumLineHeight = baseLineHeight
                style.maximumLineHeight = baseLineHeight + 4
                style.paragraphSpacing = 8
                return style
            }

            static func todoParagraphStyle() -> NSParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.2
                style.minimumLineHeight = todoLineHeight
                style.maximumLineHeight = todoLineHeight + 4
                style.paragraphSpacing = 10
                style.firstLineHeadIndent = 0
                style.headIndent = 30
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
            // Check image overlay edges BEFORE calling super — NSTextView's
            // mouseMoved forcibly resets the cursor to i-beam, overriding any
            // cursor rects on subviews. Suppressing super is the only way to win.
            if let cursor = actionDelegate?.resizeCursorForPoint(event.locationInWindow) {
                cursor.set()
                return
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
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "z" {
                undoManager?.undo()
                return true
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
               event.charactersIgnoringModifiers == "z" {
                undoManager?.redo()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func insertNewline(_ sender: Any?) {
            if actionDelegate?.handleReturn(in: self) == true { return }
            super.insertNewline(sender)
        }

        override func keyDown(with event: NSEvent) {
            // Only intercept keys if command menu is showing
            guard InlineNSTextView.isCommandMenuShowing else {
                super.keyDown(with: event)
                return
            }

            // Handle special keys for command menu navigation
            // keyCode 126 = Up Arrow, 125 = Down Arrow, 36 = Return, 53 = Escape
            switch event.keyCode {
            case 126:  // Up Arrow
                // Post notification to navigate up in command menu
                NotificationCenter.default.post(name: .commandMenuNavigateUp, object: nil)
                return  // Don't pass to super to prevent cursor movement

            case 125:  // Down Arrow
                // Post notification to navigate down in command menu
                NotificationCenter.default.post(name: .commandMenuNavigateDown, object: nil)
                return  // Don't pass to super to prevent cursor movement

            case 36, 76:  // Return or Enter key
                // Post notification to select current command menu item
                NotificationCenter.default.post(name: .commandMenuSelect, object: nil)
                // If command menu handles it, don't pass to super
                // The notification handler will determine if it was consumed
                return

            case 53:  // Escape key
                // Post notification to hide command menu
                NotificationCenter.default.post(name: .hideCommandMenu, object: nil)
                return

            default:
                // For all other keys, check if we should hide the command menu
                // Any character input (other than arrow keys) should hide the menu
                if event.characters != nil && event.characters != "" {
                    NotificationCenter.default.post(name: .hideCommandMenu, object: nil)
                }
                super.keyDown(with: event)
            }
        }

        @available(macOS 10.11, *)
        override func insertText(_ string: Any, replacementRange: NSRange) {
            // Check if we're inserting "/" to trigger command menu
            if let str = string as? String, str == "/" {
                // Get the cursor position before insertion
                let location = selectedRange().location

                // Allow the "/" to be inserted first
                super.insertText(string, replacementRange: replacementRange)

                // Then show the command menu at that position
                if actionDelegate != nil {
                    // Post notification to show command menu
                    // We need to get the rect for the inserted "/" character
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

                        let xPosition = cursorX
                        let yPosition = cursorY + cursorHeight + 4

                        let menuPosition = CGPoint(x: xPosition, y: yPosition)

                        NotificationCenter.default.post(
                            name: .showCommandMenu,
                            object: ["position": menuPosition, "slashLocation": location]
                        )
                    }
                }
                return
            }

            super.insertText(string, replacementRange: replacementRange)
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

    private final class TodoCheckboxAttachmentCell: NSTextAttachmentCell {
        var isChecked: Bool
        private let size = NSSize(width: 18, height: 18)

        init(isChecked: Bool = false) {
            self.isChecked = isChecked
            super.init(imageCell: nil)
        }

        required init(coder: NSCoder) {
            self.isChecked = false
            super.init(coder: coder)
        }

        override var cellSize: NSSize { size }

        // CRITICAL: Override cellBaselineOffset to control vertical positioning
        // This is what actually determines where the attachment sits relative to the baseline
        override nonisolated func cellBaselineOffset() -> NSPoint {
            // Use the actual font metrics for perfect alignment
            // Use Charter for body text alignment calculations
            // Using inline font creation to avoid actor isolation issues in nonisolated context
            let font = NSFont(name: "Charter", size: 16) ?? NSFont.systemFont(ofSize: 16)

            // Center the checkbox with the cap height (height of capital letters)
            // This provides the best optical alignment with mixed-case text
            // Formula from Apple docs: (capHeight - imageHeight) / 2
            let offset = (font.capHeight - size.height) / 2

            return NSPoint(x: 0, y: offset)
        }

        override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
            guard let image = image(for: controlView) else { return }
            // Draw the image directly at the cellFrame position
            // The attachment.bounds.origin.y already handles vertical positioning
            // Don't add extra centering here - it causes misalignment
            let target = NSRect(
                x: cellFrame.minX,
                y: cellFrame.minY,
                width: size.width,
                height: size.height)
            image.draw(in: target)
        }

        override func wantsToTrackMouse() -> Bool {
            true
        }

        override func trackMouse(
            with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?,
            atCharacterIndex charIndex: Int, untilMouseUp flag: Bool
        ) -> Bool {
            isChecked.toggle()
            if let textView = controlView as? NSTextView {
                let range = NSRange(location: charIndex, length: 1)
                textView.layoutManager?.invalidateDisplay(forGlyphRange: range)
                textView.didChangeText()
                NotificationCenter.default.post(
                    name: NSText.didChangeNotification, object: textView)
            }
            return true
        }

        func invalidateAppearance() {
            // no-op placeholder to keep API symmetrical with iOS implementation
        }

        private func image(for controlView: NSView?) -> NSImage? {
            // Detect dark mode
            let isDark: Bool
            if let appearance = controlView?.effectiveAppearance {
                isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            } else {
                isDark = false
            }

            // Use SF Symbols for perfect alignment and consistency
            let symbolName = isChecked ? "checkmark.circle.fill" : "circle"
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)

            // Create the image with proper configuration
            guard
                let baseImage = NSImage(
                    systemSymbolName: symbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
            else { return nil }

            // Create tinted version
            let tinted = NSImage(size: baseImage.size)
            tinted.lockFocus()

            let rect = NSRect(origin: .zero, size: baseImage.size)

            if isChecked {
                // Checked state: black in light mode, white in dark mode
                if isDark {
                    NSColor.white.set()
                } else {
                    NSColor.black.set()
                }
            } else {
                // Unchecked state: adapt to color scheme
                if isDark {
                    // White/light gray circle in dark mode for visibility
                    NSColor(white: 0.85, alpha: 1.0).set()
                } else {
                    // Dark gray circle in light mode
                    NSColor(white: 0.3, alpha: 1.0).set()
                }
            }

            // Draw the symbol with the color
            baseImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            rect.fill(using: .sourceAtop)

            tinted.unlockFocus()
            return tinted
        }
    }


// MARK: - Notifications

extension Notification.Name {
    static let insertTodoInEditor = Notification.Name("insertTodoInEditor")
    static let insertWebClipInEditor = Notification.Name("insertWebClipInEditor")
    static let insertVoiceTranscriptInEditor = Notification.Name("insertVoiceTranscriptInEditor")
    static let insertImageInEditor = Notification.Name("insertImageInEditor")
    static let deleteWebClipAttachment = Notification.Name("deleteWebClipAttachment")
    static let applyEditTool = Notification.Name("applyEditTool")

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

    // In-note search notifications
    static let showInNoteSearch = Notification.Name("ShowInNoteSearch")
    static let highlightSearchMatches = Notification.Name("HighlightSearchMatches")
    static let clearSearchHighlights = Notification.Name("ClearSearchHighlights")
}
