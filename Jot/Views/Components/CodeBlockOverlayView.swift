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
import QuartzCore

// MARK: - CodeBlockOverlayView

final class CodeBlockOverlayView: NSView {

    // MARK: - Constants

    static let minWidth: CGFloat = 400
    /// Maximum total height — vertical scroll kicks in beyond this.
    static let maxHeight: CGFloat = 500

    /// Set by the coordinator so drag-resize respects the actual container.
    var currentContainerWidth: CGFloat = 0
    private static let handleWidth: CGFloat = 12

    private static let copyButtonSide: CGFloat = 28
    /// Space from the block’s **right** edge to the copy control’s trailing edge (optical; keeps off the corner curve).
    private static let copyTrailingInset: CGFloat = 4
    /// The vertical resize strip is centered on the pane edge, so only ~half its width overlaps the block—reserve that much, not the full 12pt, so the copy control can sit further right.
    private static let copyTrailingResizeStripClearance: CGFloat = CodeBlockOverlayView.handleWidth / 2 + 2
    private static let copyBottomInset: CGFloat = 12
    /// Frosted scrim behind the copy glyph so code does not show through; centered in ``copyButtonSide``.
    private static let copyBackdropSide: CGFloat = 20

    // -- Design tokens (matching CalloutOverlayView shell) --------------------
    /// Fixed shell corner radius (points). Matches callout blocks; not derived from size or line count.
    private let blockRadius:        CGFloat = 22
    private let blockPaddingTop:    CGFloat = 24   // clears pill
    private let blockPaddingBottom: CGFloat = 16
    private let blockPaddingH:      CGFloat = 16
    private let pillPadding:        CGFloat = 4
    private let pillLeftOffset:     CGFloat = 18
    private let chipIconGap:        CGFloat = 5
    private let chipChevGap:        CGFloat = 3
    private let iconSize:           CGFloat = 15
    private let chevronSize:        CGFloat = 15

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
    /// One-shot after horizontal drag ends or double-click snap — mirrors `CalloutOverlayView` / tabs (`syncText` in coordinator).
    var onResizeGestureEnded: (() -> Void)?
    /// Horizontal resize drag began (host snapshots `CodeBlockData` for one undo at gesture end).
    var onResizeWidthDragBegan: (() -> Void)?

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

    /// 15×15 pt template glyphs (fixed slot ``copyButtonSide`` keeps layout stable while feedback runs).
    private let copyIdleButtonImage: NSImage = CodeBlockOverlayView.makeCopyIdleGlyph()
    private let copySuccessButtonImage: NSImage = CodeBlockOverlayView.makeCopySuccessGlyph()

    /// Icon-only; copies ``textView`` source (live buffer while editing).
    private let copyCodeButton: NSButton = {
        let btn = NSButton()
        btn.isBordered = false
        btn.bezelStyle = .shadowlessSquare
        btn.imagePosition = .imageOnly
        btn.focusRingType = .none
        btn.toolTip = "Copy"
        btn.setAccessibilityLabel("Copy")
        return btn
    }()

    /// Frosted scrim that should sit on the same surface token pair as the code body itself.
    private let copyBackdropView = _CodeCopyBackdropView()

    /// Table-matched hairline in **flipped** view space; sits above ``blockView`` and forwards mouse hits.
    /// A root-level ``CAShapeLayer`` was unreliable here (layer coords vs flipped ``NSView`` + sibling ordering).
    private let shellBorderView = _CodeBlockShellBorderView()

    // MARK: - State

    private var isApplyingHighlight = false
    /// Cancels the delayed fade back to the copy icon after a successful pasteboard write.
    private var copyFeedbackResetWorkItem: DispatchWorkItem?

    override var isFlipped: Bool { true }

    private var tintObserver: NSObjectProtocol?
    private var translucencyObserver: NSObjectProtocol?

    // MARK: - Init

    init(codeBlockData: CodeBlockData) {
        self.codeBlockData = codeBlockData
        super.init(frame: .zero)
        buildView()
        updateAppearance()
        populate()
        setupTintObserver()
        setupTranslucencyObserver()
        setupCopyButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let tintObserver {
            NotificationCenter.default.removeObserver(tintObserver)
        }
        if let translucencyObserver {
            NotificationCenter.default.removeObserver(translucencyObserver)
        }
        copyFeedbackResetWorkItem?.cancel()
    }

    /// Subscribe to tint changes so the chip pill recomputes its color
    /// when the user moves the Hue or Intensity slider in Settings.
    private func setupTintObserver() {
        tintObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.tintDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAppearance()
        }
    }

    private func setupTranslucencyObserver() {
        translucencyObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.detailPaneTranslucencyDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePaperShadowIfNeeded()
        }
    }

    private func setupCopyButton() {
        copyCodeButton.wantsLayer = true
        copyCodeButton.image = copyIdleButtonImage
        copyCodeButton.target = self
        copyCodeButton.action = #selector(copyCodeBlockSourceToPasteboard)
        // IMPORTANT: Do not parent under `blockView`. It uses `masksToBounds` for the rounded shell,
        // which clips the layer tree and typically forces `NSVisualEffectView` to a **flat** material
        // (no live blur) — the “dead gray tile” bug. Same pattern as the language chip: add to `self`
        // and convert frames from `blockView` space (see `layoutCopyButton()`).
        addSubview(copyBackdropView)
        addSubview(copyCodeButton)
    }

    /// Crossfades the button image so feedback does not jump horizontally (same ``copyButtonSide`` frame).
    private func transitionCopyButton(to image: NSImage, accessibilityLabel: String, tooltip: String, animated: Bool) {
        copyCodeButton.toolTip = tooltip
        copyCodeButton.setAccessibilityLabel(accessibilityLabel)
        guard animated, let layer = copyCodeButton.layer else {
            copyCodeButton.image = image
            return
        }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = Self.copyIconTransitionDuration
        layer.add(transition, forKey: nil)
        copyCodeButton.image = image
    }

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

        shellBorderView.forwardMouseTo = blockView
        addSubview(shellBorderView)

        // Chip pill -- floats as sibling of blockView, straddles top edge
        chipView.wantsLayer = true
        chipView.layer?.cornerCurve = .continuous
        chipView.onActivate = { [weak self] in self?.showLanguageMenu() }
        addSubview(chipView)
        chipView.addSubview(codeIconView)
        chipView.addSubview(langLabel)
        chipView.addSubview(chevronView)

        // Resize handle — `onDragEnd` drives debounced persistence like callouts/tabs (not every tick).
        resizeHandle.onDragBegan = { [weak self] in
            self?.onResizeWidthDragBegan?()
        }
        resizeHandle.onDrag = { [weak self] newWidth in
            self?.handleResize(to: newWidth)
        }
        resizeHandle.onDragEnd = { [weak self] in
            self?.onResizeGestureEnded?()
        }
        resizeHandle.onDoubleClick = { [weak self] in
            self?.snapToContentWidth()
            self?.onResizeGestureEnded?()
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
        shellBorderView.frame = blockView.frame

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

        layoutCopyButton()
        updatePaperShadowIfNeeded()
    }

    private func layoutCopyButton() {
        // `blockView` is a plain NSView (non-flipped): `origin.y` is the bottom edge.
        let trailingClearance = Self.copyTrailingInset + Self.copyTrailingResizeStripClearance
        let copyY = Self.copyBottomInset
        let side = Self.copyButtonSide
        var copyX = blockView.bounds.width - trailingClearance - side
        copyX = max(blockPaddingH, copyX)

        let copyFrameInBlock = CGRect(x: copyX, y: copyY, width: side, height: side)
        let backdrop = Self.copyBackdropSide
        let inset = (side - backdrop) / 2
        let backdropFrameInBlock = CGRect(x: copyX + inset, y: copyY + inset, width: backdrop, height: backdrop)

        copyCodeButton.frame = blockView.convert(copyFrameInBlock, to: self)
        copyBackdropView.frame = blockView.convert(backdropFrameInBlock, to: self)
    }

    /// Soft shadow on the root layer when light mode + note translucency (see LiquidPaperShadowChrome).
    /// Also drives the table-matched shell stroke on ``shellBorderView``.
    private func updatePaperShadowIfNeeded() {
        let pO = pillOverflow
        let blockH = max(bounds.height - pO, 50)
        let rect = CGRect(x: 0, y: pO, width: bounds.width, height: blockH)
        let path = NSBezierPath(roundedRect: rect, xRadius: blockRadius, yRadius: blockRadius).cgPath
        let enabled = LiquidPaperShadowChrome.shouldShowPaperShadow(effectiveAppearance: hostAppearance)
        LiquidPaperShadowChrome.applyPaperShadow(to: layer, path: path, enabled: enabled)

        shellBorderView.showsTableMatchedStroke = enabled
        shellBorderView.cornerRadius = blockRadius
        shellBorderView.needsDisplay = true
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

    /// Prefer the parent ``NSTextView`` appearance. The editor forces ``.darkAqua`` / ``.aqua`` from SwiftUI
    /// ``ColorScheme`` (see ``TodoEditorRepresentable``). Named ``NSColor`` values flattened to ``CGColor`` on
    /// layers must be read inside ``NSAppearance.performAsCurrentDrawingAppearance`` so catalog colors match that
    /// appearance; otherwise ``DetailPaneColor`` can snapshot the light asset slot while syntax stays dark-themed.
    private var hostAppearance: NSAppearance {
        parentTextView?.effectiveAppearance ?? effectiveAppearance
    }

    private var isDarkMode: Bool {
        hostAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func updateAppearance() {
        let appearance = hostAppearance
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Block background — snapshot ``CGColor`` while ``appearance`` is current so named assets match the host editor.
        blockView.layer?.backgroundColor = Self.blockBodySurfaceCGColor(isDark: dark, appearance: appearance)

        // Chip pill -- always uses the DARK variant of the tinted block
        // container so it reads as a deep, saturated pill in both light
        // and dark app modes (matches the original "stone-800 in both
        // modes" design intent, plus picks up the user's hue tint).
        chipView.layer?.backgroundColor = ThemeManager.tintedBlockContainerNS(isDark: true).cgColor

        langLabel.attributedStringValue = NSAttributedString(
            string: CodeBlockData.displayName(for: codeBlockData.language),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.white
            ]
        )

        codeIconView.contentTintColor = .white
        chevronView.contentTintColor  = .white

        // Update text view base foreground color so unstyled tokens adapt to theme
        textView.textColor = dark ? .white : .black
        textView.insertionPointColor = dark ? .white : .black

        var copyTint: NSColor = .secondaryLabelColor
        appearance.performAsCurrentDrawingAppearance {
            copyTint = (NSColor(named: "IconSecondaryColor") ?? .secondaryLabelColor)
        }
        copyCodeButton.contentTintColor = copyTint

        copyBackdropView.updateAppearance(isDark: dark, resolvingWith: appearance)

        updatePaperShadowIfNeeded()
        needsLayout = true
    }

    private func updateLanguageLabel() {
        let display = CodeBlockData.displayName(for: codeBlockData.language)
        langLabel.attributedStringValue = NSAttributedString(
            string: display,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.white
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

    @objc private func copyCodeBlockSourceToPasteboard() {
        // Live NSTextView buffer is authoritative while the user edits.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)

        copyFeedbackResetWorkItem?.cancel()
        transitionCopyButton(
            to: copySuccessButtonImage,
            accessibilityLabel: "Copied",
            tooltip: "Copied",
            animated: true
        )

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.transitionCopyButton(
                to: self.copyIdleButtonImage,
                accessibilityLabel: "Copy",
                tooltip: "Copy",
                animated: true
            )
            self.copyFeedbackResetWorkItem = nil
        }
        copyFeedbackResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: work)
    }

    @objc private func deleteCodeBlock() {
        onDeleteCodeBlock?()
    }

    // MARK: - Appearance Change

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // After ``addSubview`` onto ``InlineNSTextView``, pick up the parent’s forced ``.darkAqua`` / ``.aqua``
        // even when ``viewDidChangeEffectiveAppearance`` does not fire again.
        updateAppearance()
        applyHighlighting()
        updatePaperShadowIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
        applyHighlighting()
        updatePaperShadowIfNeeded()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    // MARK: - Unit test surface

    /// Exposes the code body shell fill so tests can assert named colors resolve like the host ``NSTextView`` appearance.
    internal var testability_blockBodyLayerBackgroundColor: CGColor? {
        blockView.layer?.backgroundColor
    }

    /// Resolves the body surface token the same way ``updateAppearance`` does, for tests that pass an explicit ``NSAppearance``.
    internal static func testability_blockBodySurfaceCGColor(isDark: Bool, appearance: NSAppearance) -> CGColor {
        blockBodySurfaceCGColor(isDark: isDark, appearance: appearance)
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

// MARK: - Shell border (table-matched stroke in flipped view space)

/// Draws the same half-point hairline as ``NoteTableOverlayView`` when translucency + light chrome is active.
/// Implemented as a flipped ``NSView`` above the white shell so coordinates match layout math; forwards mouse
/// hits to ``blockView`` so the editor keeps first responder / selection behavior.
private final class _CodeBlockShellBorderView: NSView {

    weak var forwardMouseTo: NSView?

    var showsTableMatchedStroke = false {
        didSet { needsDisplay = true }
    }

    var cornerRadius: CGFloat = 22 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let fwd = forwardMouseTo else { return nil }
        return fwd.hitTest(convert(point, to: fwd))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard showsTableMatchedStroke else { return }
        let inset = TranslucentLightPaperTableStroke.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0.5, rect.height > 0.5 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = TranslucentLightPaperTableStroke.lineWidth
        TranslucentLightPaperTableStroke.lightOuterStrokeNSColor().setStroke()
        path.stroke()
    }
}

// MARK: - Copy glyph helpers

fileprivate extension CodeBlockOverlayView {
    /// Matches the code-block text area surface: `SurfaceDefaultColor` in light, `DetailPaneColor` in dark.
    static func blockBodySurfaceColor(isDark: Bool) -> NSColor {
        if isDark {
            return NSColor(named: "DetailPaneColor")
                ?? NSColor(srgbRed: 12 / 255, green: 10 / 255, blue: 9 / 255, alpha: 1)
        }
        return NSColor(named: "SurfaceDefaultColor") ?? .white
    }

    /// Flattens ``blockBodySurfaceColor`` to ``CGColor`` under ``appearance`` so layer fills match the host editor.
    /// ``cgColor`` must be read **inside** ``performAsCurrentDrawingAppearance``; reading it afterward re-resolves
    /// against the wrong current appearance and reproduces the light-``DetailPaneColor`` / dark-syntax mismatch.
    static func blockBodySurfaceCGColor(isDark: Bool, appearance: NSAppearance) -> CGColor {
        var cg: CGColor!
        appearance.performAsCurrentDrawingAppearance {
            cg = blockBodySurfaceColor(isDark: isDark).cgColor
        }
        return cg
    }

    /// On-screen glyph size (points) for copy + checkmark inside the fixed hit rect.
    static let copyGlyphPointSize: CGFloat = 15
    /// Fade duration for copy ↔ checkmark (no horizontal layout change).
    static let copyIconTransitionDuration: CFTimeInterval = 0.18

    /// Renders a scaled copy so we never mutate the asset catalog instance’s intrinsic size.
    static func makeScaledTemplateImage(from source: NSImage, pointSize: CGFloat) -> NSImage {
        let dstSize = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: dstSize, flipped: false) { dst in
            let srcSize = source.size
            guard srcSize.width > 0, srcSize.height > 0 else { return false }
            let srcRect = NSRect(origin: .zero, size: srcSize)
            source.draw(in: dst, from: srcRect, operation: .sourceOver, fraction: 1.0, respectFlipped: false, hints: nil)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func makeCopyIdleGlyph() -> NSImage {
        if let named = NSImage(named: "IconSquareBehindSquare6") {
            return makeScaledTemplateImage(from: named, pointSize: copyGlyphPointSize)
        }
        if let sys = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy") {
            return makeScaledTemplateImage(from: sys, pointSize: copyGlyphPointSize)
        }
        // Last resort: blank template slot (should never run in a normal app bundle).
        return NSImage(size: NSSize(width: copyGlyphPointSize, height: copyGlyphPointSize), flipped: false) { _ in true }
    }

    static func makeCopySuccessGlyph() -> NSImage {
        if let named = NSImage(named: "IconCheckmark1") {
            return makeScaledTemplateImage(from: named, pointSize: copyGlyphPointSize)
        }
        if let sys = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied") {
            return makeScaledTemplateImage(from: sys, pointSize: copyGlyphPointSize)
        }
        return makeCopyIdleGlyph()
    }
}

// MARK: - Copy backdrop (code-surface token + blur)

/// Frosted **20×20** scrim using the same white/`DetailPaneColor` pair as the code body,
/// with a light tint layer so the underlying material still reads as blur instead of a flat tile.
/// Must stay **outside** ``blockView``’s `masksToBounds` rounded clip — otherwise AppKit degrades ``NSVisualEffectView`` to a flat fill (no real blur). Do **not** apply a `layer.mask` on top of the material for the same reason.
private final class _CodeCopyBackdropView: NSView {

    private let effectView = NSVisualEffectView()
    private let tintView = NSView()

    private static let innerCornerRadius: CGFloat = 7

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        // Wide, surface-colored halo so the pill feathers into the code body instead of cutting a rectangle out of it.
        layer?.shadowOffset = .zero
        layer?.shadowRadius = 10
        layer?.shadowOpacity = 0.24

        effectView.material = .popover
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.masksToBounds = true
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.cornerRadius = Self.innerCornerRadius

        tintView.wantsLayer = true
        tintView.layer?.masksToBounds = true
        tintView.layer?.cornerCurve = .continuous
        tintView.layer?.cornerRadius = Self.innerCornerRadius

        addSubview(effectView)
        addSubview(tintView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        tintView.frame = bounds
        let r = Self.innerCornerRadius
        effectView.layer?.cornerRadius = r
        tintView.layer?.cornerRadius = r
        if bounds.width > 1, bounds.height > 1 {
            layer?.shadowPath = CGPath(
                roundedRect: bounds,
                cornerWidth: r,
                cornerHeight: r,
                transform: nil
            )
        }
    }

    func updateAppearance(isDark: Bool, resolvingWith appearance: NSAppearance) {
        let tokenCG = CodeBlockOverlayView.blockBodySurfaceCGColor(isDark: isDark, appearance: appearance)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        if reduce {
            layer?.shadowOpacity = 0
            layer?.shadowPath = nil
            effectView.isHidden = true
            tintView.layer?.backgroundColor = tokenCG
        } else {
            // Opaque fill = the exact text-area token. Material still sits underneath to obscure any syntax-colored
            // characters that would otherwise bleed through at the rim. Halo uses the same token so the soft edge
            // reads as an extension of the code surface, not an outline drawn on top of it.
            layer?.shadowOpacity = isDark ? 0.28 : 0.18
            effectView.isHidden = false
            tintView.layer?.backgroundColor = tokenCG
            layer?.shadowColor = tokenCG
        }
        needsLayout = true
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

    var onDragBegan: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?
    /// After an actual drag (not plain click / double-click).
    var onDragEnd: (() -> Void)?

    private var dragStartX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    private var didDragThisGesture = false

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
        didDragThisGesture = false
        dragStartX = event.locationInWindow.x
        onDragBegan?()
        dragStartWidth = superview?.bounds.width ?? 0
    }

    override func mouseDragged(with event: NSEvent) {
        didDragThisGesture = true
        let delta = event.locationInWindow.x - dragStartX
        onDrag?(dragStartWidth + delta)
    }

    override func mouseUp(with event: NSEvent) {
        if didDragThisGesture {
            didDragThisGesture = false
            onDragEnd?()
        }
    }
}
