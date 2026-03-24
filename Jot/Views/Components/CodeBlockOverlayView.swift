//
//  CodeBlockOverlayView.swift
//  Jot
//
//  Overlay NSView that renders a code block inside the text editor.
//  Structure: single rounded block with a floating capsule pill straddling the
//  top edge at left: 18px. Pill contains code icon, language label, and chevron.
//  Mirrors CalloutOverlayView layout exactly (stone/note palette).
//

import AppKit

// MARK: - CodeBlockOverlayView

final class CodeBlockOverlayView: NSView {

    // MARK: - Constants

    static let minWidth: CGFloat = 400
    /// Maximum total height — vertical scroll kicks in beyond this.
    static let maxHeight: CGFloat = 500

    /// Height of a single line at the code font size (mono 13pt).
    private static let singleLineHeight: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return ceil(font.ascender - font.descender + font.leading)
    }()

    /// Set by the coordinator so drag-resize respects the actual container.
    var currentContainerWidth: CGFloat = 0
    private static let handleWidth: CGFloat = 12

    // -- Design tokens (matching CalloutOverlayView / callout .note) -----------
    private let blockRadius:        CGFloat = 16
    private let blockPaddingTop:    CGFloat = 24   // clears pill
    private let blockPaddingBottom: CGFloat = 16
    private let blockPaddingH:      CGFloat = 16
    private let pillPadding:        CGFloat = 4
    private let pillLeftOffset:     CGFloat = 18
    private let chipIconGap:        CGFloat = 5
    private let chipChevGap:        CGFloat = 3
    private let iconSize:           CGFloat = 18
    private let chevronSize:        CGFloat = 18

    /// Pill height = pillPadding(4) + iconSize(18) + pillPadding(4) = 26px
    private var pillHeight: CGFloat { pillPadding * 2 + iconSize }
    /// Half the pill extends above the block's top edge.
    private var pillOverflow: CGFloat { pillHeight / 2 }

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

    // MARK: - Subviews

    private let blockView  = NSView()
    private let chipView   = _LangChipButton()

    private let codeIconView: NSImageView = {
        let iv = NSImageView()
        let img = NSImage(named: "IconCode")
        img?.isTemplate = true
        iv.image = img
        iv.imageScaling = .scaleProportionallyUpOrDown
        return iv
    }()

    private let langLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.isBordered = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.isSelectable = false
        return tf
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

    private let resizeHandle = _CodeResizeHandle()

    // MARK: - State

    private var isApplyingHighlight = false

    override var isFlipped: Bool { true }

    // MARK: - Init

    init(codeBlockData: CodeBlockData) {
        self.codeBlockData = codeBlockData
        super.init(frame: .zero)
        buildView()
        updateAppearance()
        populate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildView() {
        wantsLayer = true
        layer?.masksToBounds = false  // pill must extend above block bounds

        // Block -- single rounded background for content
        blockView.wantsLayer = true
        blockView.layer?.cornerRadius = blockRadius
        blockView.layer?.cornerCurve = .continuous
        blockView.layer?.masksToBounds = true
        addSubview(blockView)

        scrollView.documentView = textView
        blockView.addSubview(scrollView)

        // Chip pill -- floats as sibling of blockView, straddles top edge
        chipView.wantsLayer = true
        chipView.layer?.cornerCurve = .continuous
        chipView.onActivate = { [weak self] in self?.showLanguageMenu() }
        addSubview(chipView)
        chipView.addSubview(codeIconView)
        chipView.addSubview(langLabel)
        chipView.addSubview(chevronView)

        // Resize handle
        resizeHandle.onDrag = { [weak self] newWidth in
            self?.handleResize(to: newWidth)
        }
        resizeHandle.onDoubleClick = { [weak self] in
            self?.snapToContentWidth()
        }
        addSubview(resizeHandle)

        textView.delegate = self
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let pO = pillOverflow  // 13px

        // Block fills width, offset down by pill overflow
        let blockH = max(bounds.height - pO, 50)
        blockView.frame = CGRect(x: 0, y: pO, width: bounds.width, height: blockH)

        // Dynamic corner radius: 16 for single-line, 22 for multiline
        let contentH = blockH - blockPaddingTop - blockPaddingBottom
        let dynamicRadius = contentH > Self.singleLineHeight + 4 ? 22 : blockRadius
        blockView.layer?.cornerRadius = dynamicRadius

        // ScrollView inside block (blockView is non-flipped: y=0 at bottom)
        let svW = max(bounds.width - blockPaddingH * 2, 40)
        let svH = max(blockH - blockPaddingTop - blockPaddingBottom, 20)
        scrollView.frame = CGRect(x: blockPaddingH, y: blockPaddingBottom, width: svW, height: svH)
        textView.minSize = CGSize(width: svW, height: svH)
        textView.textContainer?.containerSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Chip pill -- straddles blockView's top edge
        langLabel.sizeToFit()
        let labelW = ceil(langLabel.frame.width) + 1
        let labelH = ceil(langLabel.frame.height)
        let chipW = pillPadding + iconSize + chipIconGap + labelW + chipChevGap + chevronSize + pillPadding
        let chipH = pillHeight  // 26px
        chipView.frame = CGRect(x: pillLeftOffset, y: 0, width: chipW, height: chipH)
        chipView.layer?.cornerRadius = chipH / 2  // capsule

        // Icon inside chip
        let iconOffY = (chipH - iconSize) / 2
        codeIconView.frame = CGRect(x: pillPadding, y: iconOffY, width: iconSize, height: iconSize)

        // Label inside chip
        let labelOffY = (chipH - labelH) / 2
        langLabel.frame = CGRect(
            x: pillPadding + iconSize + chipIconGap,
            y: labelOffY,
            width: labelW,
            height: labelH
        )

        // Chevron inside chip
        let chevOffY = (chipH - chevronSize) / 2
        chevronView.frame = CGRect(
            x: pillPadding + iconSize + chipIconGap + labelW + chipChevGap,
            y: chevOffY,
            width: chevronSize,
            height: chevronSize
        )

        // Resize handle -- straddles right edge
        resizeHandle.frame = CGRect(
            x: bounds.width - Self.handleWidth / 2,
            y: 0,
            width: Self.handleWidth,
            height: bounds.height
        )
    }

    // MARK: - Resize

    /// Returns the resize cursor if the window point falls on the resize handle, nil otherwise.
    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        guard resizeHandle.frame.contains(local) else { return nil }
        return NSCursor.compatFrameResize(position: "right")
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

    /// Measure the longest line and snap the block width to fit it (clamped to min/max).
    private func snapToContentWidth() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let lines = codeBlockData.code.components(separatedBy: "\n")
        var maxLineWidth: CGFloat = 0
        for line in lines {
            let w = (line as NSString).size(withAttributes: [.font: font]).width
            if w > maxLineWidth { maxLineWidth = w }
        }
        // Add horizontal padding on both sides
        let fittingWidth = ceil(maxLineWidth) + blockPaddingH * 2
        handleResize(to: fittingWidth)
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

    // MARK: - Appearance

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func updateAppearance() {
        let dark = isDarkMode

        // Block background -- stone-950 dark, stone-100 light (callout .note tokens)
        blockView.layer?.backgroundColor = dark
            ? NSColor(srgbRed: 12/255, green: 10/255, blue: 9/255, alpha: 1).cgColor      // #0C0A09
            : NSColor(srgbRed: 245/255, green: 245/255, blue: 244/255, alpha: 1).cgColor  // #F5F5F4

        // Chip pill -- stone-800 light, stone-700 dark, white contents
        chipView.layer?.backgroundColor = dark
            ? NSColor(srgbRed: 68/255, green: 64/255, blue: 60/255, alpha: 1).cgColor     // #44403C
            : NSColor(srgbRed: 41/255, green: 37/255, blue: 36/255, alpha: 1).cgColor     // #292524

        langLabel.attributedStringValue = NSAttributedString(
            string: CodeBlockData.displayName(for: codeBlockData.language),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
                .kern: NSNumber(value: -0.2)
            ]
        )

        codeIconView.contentTintColor = .white
        chevronView.contentTintColor  = .white

        // Update text view base foreground color so unstyled tokens adapt to theme
        textView.textColor = dark ? .white : .black
        textView.insertionPointColor = dark ? .white : .black

        needsLayout = true
    }

    private func updateLanguageLabel() {
        let display = CodeBlockData.displayName(for: codeBlockData.language)
        langLabel.attributedStringValue = NSAttributedString(
            string: display,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
                .kern: NSNumber(value: -0.2)
            ]
        )
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
        let anchorPoint = CGPoint(x: chipView.frame.origin.x, y: chipView.frame.maxY)
        menu.popUp(positioning: nil, at: anchorPoint, in: self)
    }

    @objc private func languageMenuItemSelected(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? String else { return }
        codeBlockData.language = lang
        onDataChanged?(codeBlockData)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        // Language submenu
        let langMenu = NSMenu()
        for lang in CodeBlockData.supportedLanguages {
            let item = NSMenuItem(
                title:  CodeBlockData.displayName(for: lang),
                action: #selector(languageMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.representedObject = lang
            item.target = self
            if lang == codeBlockData.language { item.state = .on }
            langMenu.addItem(item)
        }
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: "Delete Code Block",
            action: #selector(deleteCodeBlock),
            keyEquivalent: ""
        )
        deleteItem.target = self
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func deleteCodeBlock() {
        onDeleteCodeBlock?()
    }

    // MARK: - Appearance Change

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
        applyHighlighting()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    // MARK: - Static Height Helper

    /// Content-hugging height: pillOverflow + paddingTop + codeContent + paddingBottom, capped at maxHeight.
    static func heightForData(_ data: CodeBlockData, width: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let lineCount = max(data.code.components(separatedBy: "\n").count, 1)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let codeH = CGFloat(lineCount) * lineHeight
        // pillOverflow(13) + paddingTop(24) + content(min 20) + paddingBottom(16)
        return min(13 + 24 + max(codeH, 20) + 16, maxHeight)
    }
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

// MARK: - Chip Button (language picker trigger)

private final class _LangChipButton: NSView {

    var onActivate: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Resize Handle

private final class _CodeResizeHandle: NSView {

    var onDrag: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?

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
        addCursorRect(bounds, cursor: NSCursor.compatFrameResize(position: "right"))
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        dragStartX = event.locationInWindow.x
        dragStartWidth = superview?.bounds.width ?? 0
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = event.locationInWindow.x - dragStartX
        onDrag?(dragStartWidth + delta)
    }

    override func mouseUp(with event: NSEvent) { }
}
