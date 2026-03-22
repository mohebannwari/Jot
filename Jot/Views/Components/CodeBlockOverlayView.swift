//
//  CodeBlockOverlayView.swift
//  Jot
//
//  Overlay NSView that renders a code block inside the text editor.
//  Figma spec: outer stone wrapper (stone-300/stone-800), 16px radius, 2px padding;
//  header row with icon + language picker left;
//  inner code body white/#0C0A09, 14px concentric radius, 16px padding.
//

import AppKit

// MARK: - CodeBlockOverlayView

final class CodeBlockOverlayView: NSView {

    // MARK: - Constants

    static  let minWidth:     CGFloat = 400
    /// Set by the coordinator so drag-resize respects the actual container.
    var currentContainerWidth: CGFloat = 0
    static  let defaultHeight: CGFloat = outerPad + hdrHeight + bodyHeight + outerPad  // 342

    private static let outerPad:     CGFloat = 2
    private static let hdrHeight:    CGFloat = 38   // 8 + 22 + 8
    private static let bodyHeight:   CGFloat = 300
    private static let handleWidth:  CGFloat = 12

    private let outerRadius: CGFloat = 22
    private let innerRadius: CGFloat = 20   // concentric: 22 − 2
    private let hdrPad:      CGFloat = 8
    private let codePad:     CGFloat = 16
    private let iconSz:      CGFloat = 18
    private let iconGap:     CGFloat = 5
    private let chipPad:     CGFloat = 2    // xxs — matches callout chip padding
    private let chevGap:     CGFloat = 3    // gap between label and chevron
    private let chevSz:      CGFloat = 14   // chevron rendered size

    // MARK: - Data

    var codeBlockData: CodeBlockData {
        didSet {
            if codeBlockData.code != oldValue.code { syncTextViewIfNeeded() }
            if codeBlockData.language != oldValue.language || codeBlockData.code != oldValue.code {
                applyHighlighting()
                updateLanguageLabel()
            }
        }
    }

    weak var parentTextView: NSTextView?
    var onDataChanged:     ((CodeBlockData) -> Void)?
    var onDeleteCodeBlock: (() -> Void)?
    var onWidthChanged:    ((CGFloat) -> Void)?

    // MARK: - Header Subviews

    private let codeIconView: NSImageView = {
        let iv = NSImageView()
        let img = NSImage(named: "IconCode")
        img?.isTemplate = true
        iv.image = img
        iv.imageScaling = .scaleProportionallyUpOrDown
        return iv
    }()

    private let langLabel: NSTextField = {
        let f = NSTextField(labelWithString: "Plaintext")
        f.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        f.isBordered = false
        f.drawsBackground = false
        return f
    }()

    private let chevronView: NSImageView = {
        let iv = NSImageView()
        let img = NSImage(named: "IconChevronDownSmall")
            ?? NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        img?.isTemplate = true
        iv.image = img
        iv.imageScaling = .scaleProportionallyUpOrDown
        return iv
    }()

    // MARK: - Code Body

    private let codeBodyView = _FlippedView()

    private let scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.hasVerticalScroller   = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers    = true
        sv.drawsBackground       = false
        sv.backgroundColor       = .clear
        sv.borderType            = .noBorder
        sv.scrollerStyle         = .overlay
        return sv
    }()

    private let textView: NSTextView = {
        let tv = NSTextView()
        tv.isEditable            = true
        tv.isSelectable          = true
        tv.allowsUndo            = true
        tv.drawsBackground       = false
        tv.backgroundColor       = .clear
        tv.isRichText            = false
        tv.isAutomaticQuoteSubstitutionEnabled  = false
        tv.isAutomaticDashSubstitutionEnabled   = false
        tv.isAutomaticTextReplacementEnabled    = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset    = NSSize(width: 0, height: 0)
        tv.textContainer?.lineFragmentPadding   = 0
        tv.textContainer?.widthTracksTextView   = false
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable   = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.focusRingType         = .none
        return tv
    }()

    // MARK: - Chip (language picker trigger — mirrors callout's _ChipButton)

    private let langChip = _LangChipButton()

    // MARK: - Resize Handle

    private let resizeHandle = _ResizeHandle()

    // MARK: - State

    private var isApplyingHighlight = false

    override var isFlipped: Bool { true }

    // MARK: - Init

    init(codeBlockData: CodeBlockData) {
        self.codeBlockData = codeBlockData
        super.init(frame: CGRect(origin: .zero,
                                 size: CGSize(width: Self.minWidth, height: Self.defaultHeight)))
        setupViews()
        populate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup (subviews only — frames are computed in layout())

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius  = outerRadius
        layer?.cornerCurve   = .continuous
        layer?.masksToBounds = false
        layer?.borderWidth   = 1.0

        // Code body
        codeBodyView.wantsLayer = true
        codeBodyView.layer?.cornerRadius  = innerRadius
        codeBodyView.layer?.cornerCurve   = .continuous
        codeBodyView.layer?.masksToBounds = true
        addSubview(codeBodyView)

        scrollView.documentView = textView
        codeBodyView.addSubview(scrollView)

        // Language chip — icon + label + chevron, left side
        langChip.wantsLayer = true
        langChip.onActivate = { [weak self] in self?.showLanguageMenu() }
        addSubview(langChip)
        langChip.addSubview(codeIconView)
        langChip.addSubview(langLabel)
        langChip.addSubview(chevronView)

        // Resize handle
        resizeHandle.onDrag = { [weak self] newWidth in
            self?.handleResize(to: newWidth)
        }
        addSubview(resizeHandle)

        textView.delegate = self
        updateColors()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        needsDisplay = true

        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: outerRadius,
            cornerHeight: outerRadius,
            transform: nil
        )

        let W  = bounds.width
        let op = Self.outerPad
        let hh = Self.hdrHeight

        // ── Code body ──────────────────────────────────────────────────────
        let bodyH = max(bounds.height - op - hh - op, 20)
        codeBodyView.frame = CGRect(x: op, y: op + hh, width: W - 2 * op, height: bodyH)

        let innerW = max(codeBodyView.bounds.width  - 2 * codePad, 40)
        let innerH = max(codeBodyView.bounds.height - 2 * codePad, 20)
        scrollView.frame = CGRect(x: codePad, y: codePad, width: innerW, height: innerH)
        textView.minSize = CGSize(width: innerW, height: innerH)
        textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // ── Header: left — chip (icon + language + chevron) ────────────────
        langLabel.sizeToFit()
        let labelW = ceil(langLabel.frame.width) + 1
        let labelH = ceil(langLabel.frame.height)
        let chipH  = chipPad * 2 + iconSz
        let chipW  = chipPad + iconSz + iconGap + labelW + chevGap + chevSz + chipPad
        let chipY  = op + (hh - chipH) / 2
        langChip.frame = CGRect(
            x: op + hdrPad - chipPad,
            y: chipY,
            width: chipW,
            height: chipH
        )
        langChip.layer?.cornerRadius = chipH / 2  // capsule

        let iconOffY = (chipH - iconSz) / 2
        codeIconView.frame = CGRect(x: chipPad, y: iconOffY, width: iconSz, height: iconSz)

        let labelOffY = (chipH - labelH) / 2
        langLabel.frame = CGRect(
            x: chipPad + iconSz + iconGap,
            y: labelOffY,
            width: labelW,
            height: labelH
        )

        let chevOffY = (chipH - chevSz) / 2
        chevronView.frame = CGRect(
            x: chipPad + iconSz + iconGap + labelW + chevGap,
            y: chevOffY,
            width: chevSz,
            height: chevSz
        )

        // ── Resize handle — straddles right edge (half inside, half outside) ──
        resizeHandle.frame = CGRect(
            x: W - Self.handleWidth / 2,
            y: 0,
            width: Self.handleWidth,
            height: bounds.height
        )
    }

    // MARK: - Resize

    /// Returns the resize cursor if the window point falls on the resize handle, nil otherwise.
    /// Called by the coordinator's resizeCursorForPoint to bypass NSTextView's I-beam override.
    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        guard resizeHandle.frame.contains(local) else { return nil }
        return NSCursor.frameResize(position: .right, directions: .all)
    }

    func handleResize(to newWidth: CGFloat) {
        let effectiveMax = currentContainerWidth > 0 ? currentContainerWidth : CGFloat.greatestFiniteMagnitude
        let effectiveMin = min(Self.minWidth, effectiveMax)
        let clamped = floor(max(effectiveMin, min(effectiveMax, newWidth)))
        var f = frame
        f.size.width = clamped
        frame = f
        onWidthChanged?(clamped)
    }

    // MARK: - Populate

    private func populate() {
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        isApplyingHighlight = true
        textView.string = codeBlockData.code
        isApplyingHighlight = false

        applyHighlighting()
        updateLanguageLabel()
    }

    // MARK: - Colors

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func updateColors() {
        let dark = isDarkMode

        codeBodyView.layer?.backgroundColor = dark
            ? NSColor(srgbRed: 12/255,  green: 10/255,  blue: 9/255,   alpha: 1).cgColor   // #0C0A09
            : NSColor.white.cgColor

        let iconSecondary = NSColor(named: "IconSecondaryColor") ?? .secondaryLabelColor
        codeIconView.contentTintColor = iconSecondary

        let secondary = NSColor(named: "SecondaryTextColor") ?? .secondaryLabelColor
        langLabel.textColor          = secondary
        chevronView.contentTintColor = secondary

        // Match settings tile border: black 8% (light) / white 6% (dark)
        layer?.borderColor = dark
            ? NSColor(white: 1.0, alpha: 0.06).cgColor
            : NSColor(white: 0.0, alpha: 0.08).cgColor

        needsDisplay = true
    }

    private func updateLanguageLabel() {
        let display = CodeBlockData.displayName(for: codeBlockData.language)
        langLabel.stringValue = display
        needsLayout = true
    }

    // MARK: - Highlighting

    private func applyHighlighting() {
        guard let ts = textView.textStorage else { return }
        let highlighted = SyntaxHighlighter.highlight(
            code: ts.string, language: codeBlockData.language, isDark: isDarkMode)
        let fullLen = ts.length

        isApplyingHighlight = true
        ts.beginEditing()
        highlighted.enumerateAttributes(
            in: NSRange(location: 0, length: highlighted.length), options: []
        ) { attrs, range, _ in
            guard range.upperBound <= fullLen else { return }
            for (key, value) in attrs { ts.addAttribute(key, value: value, range: range) }
        }
        ts.endEditing()
        isApplyingHighlight = false
    }

    private func syncTextViewIfNeeded() {
        guard textView.string != codeBlockData.code else { return }
        isApplyingHighlight = true
        let sel = textView.selectedRange()
        textView.string = codeBlockData.code
        let safeLen = textView.string.utf16.count
        textView.setSelectedRange(NSRange(location: min(sel.location, safeLen), length: 0))
        isApplyingHighlight = false
    }

    // MARK: - Language Menu

    private func showLanguageMenu() {
        let menu = NSMenu()
        for lang in CodeBlockData.supportedLanguages {
            let item = NSMenuItem(
                title:  CodeBlockData.displayName(for: lang),
                action: #selector(languageMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.representedObject = lang
            item.target = self
            if lang == codeBlockData.language { item.state = .on }
            menu.addItem(item)
        }
        let chipOrigin = langChip.frame.origin
        let anchorPoint = NSPoint(x: chipOrigin.x, y: chipOrigin.y + langChip.frame.height)
        menu.popUp(positioning: nil, at: anchorPoint, in: self)
    }

    @objc private func languageMenuItemSelected(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? String else { return }
        codeBlockData.language = lang
        onDataChanged?(codeBlockData)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Only fill the code body region — outer container is border-only
        let bodyBg = isDarkMode
            ? NSColor(srgbRed: 12/255, green: 10/255, blue: 9/255, alpha: 1)   // #0C0A09
            : NSColor.white
        bodyBg.setFill()
        NSBezierPath(roundedRect: codeBodyView.frame, xRadius: innerRadius, yRadius: innerRadius).fill()
    }

    // MARK: - Appearance Change

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        applyHighlighting()
    }

    // MARK: - Static Height Helper

    static func heightForData(_ data: CodeBlockData, width: CGFloat) -> CGFloat { defaultHeight }
}

// MARK: - NSTextViewDelegate

extension CodeBlockOverlayView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !isApplyingHighlight else { return }
        let newCode = textView.string
        guard newCode != codeBlockData.code else { return }
        codeBlockData.code = newCode
        applyHighlighting()
        onDataChanged?(codeBlockData)
    }
}

// MARK: - Private Helpers

private final class _FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class _LangChipButton: NSView {

    var onActivate: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private final class _ResizeHandle: NSView {

    var onDrag: ((CGFloat) -> Void)?

    private var dragStartX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.frameResize(position: .right, directions: .all))
    }

    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        dragStartWidth = superview?.bounds.width ?? 0
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = event.locationInWindow.x - dragStartX
        onDrag?(dragStartWidth + delta)
    }

    override func mouseUp(with event: NSEvent) { }
}

private extension NSImage {
    func tinting(with color: NSColor) -> NSImage {
        guard let image = self.copy() as? NSImage else { return self }
        image.lockFocus()
        color.set()
        CGRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
