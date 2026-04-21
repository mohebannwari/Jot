//
//  ToggleOverlayView.swift
//  Jot
//
//  Overlay NSView that renders a Notion-style collapsible toggle block inside
//  the text editor. Structure: flat title row with a right-side chevron button
//  and a collapsible rich-text content body below. When `isExpanded` is false
//  the content area collapses to height 0 and the overall block height becomes
//  `collapsedHeight` (34pt) — matching how Tabs/Callout expose a single
//  NSTextAttachment sized by a `*SizeAttachmentCell`.
//
//  Architectural parity notes:
//   - Inner content text view mirrors `TabsContainerOverlayView.contentTextView`
//     (same `_TabsTextView` / `_TabsLayoutManager` so squiggly strikethrough
//     and serializer parity follow for free).
//   - Height is measured from `layoutManager.usedRect(for:)`, never
//     `boundingRect` (matches the callout-height-measurement rule in project
//     memory).
//   - Width-timing invariant: callers set `currentContainerWidth` /
//     `setContainerWidth(_:)` BEFORE rebuilding the NSHostingView / frame in
//     the parent, matching the editor overlay convention.
//

import AppKit

// MARK: - ToggleOverlayView

final class ToggleOverlayView: NSView {

    // MARK: - Public Constants (part of the external contract)

    static let minWidth:          CGFloat = 200
    static let collapsedHeight:   CGFloat = 34
    static let minContentHeight:  CGFloat = 40

    // MARK: - Internal Layout Constants

    /// Horizontal padding applied to the title row + content body.
    private static let hPad:            CGFloat = 4
    /// Vertical padding between the title row and the content body.
    private static let rowContentGap:   CGFloat = 4
    /// Inner content body padding (matches Tabs body).
    private static let contentPadH:     CGFloat = 0
    private static let contentPadTop:   CGFloat = 2
    private static let contentPadBot:   CGFloat = 8
    /// Chevron size and trailing padding inside the title row.
    private static let chevronSize:     CGFloat = 18
    private static let chevronTrailing: CGFloat = 8
    /// Gap between chevron and title text field.
    private static let titleChevronGap: CGFloat = 6
    /// Resize handle width (only used when `includeResizeHandle` is true).
    private static let handleWidth:     CGFloat = 12
    static let resizeHitOutset:         CGFloat = handleWidth / 2

    // MARK: - Data

    /// Current data snapshot. Updated via `applyData(_:)` or user edits.
    private(set) var toggleData: ToggleData

    /// Attachment identifier (passed by parent so it can resolve the
    /// correct attachment on data-change callbacks).
    let attachmentID: UUID

    /// Width of the hosting container. Set by the coordinator BEFORE the
    /// parent rebuilds the NSHostingView / resizes this overlay, so layout
    /// calculations pick up the new width synchronously.
    var currentContainerWidth: CGFloat = 0

    // MARK: - Callbacks

    weak var parentTextView: NSTextView?
    var onDataChanged:   ((ToggleData) -> Void)?
    var onExitToParent:  (() -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?
    var onWidthChanged:  ((CGFloat?) -> Void)?

    // MARK: - Subviews

    private let titleRow = _FlippedContainerView()
    private let titleField: NSTextField = {
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.isEditable = true
        tf.isSelectable = true
        tf.focusRingType = .none
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        tf.usesSingleLineMode = true
        tf.lineBreakMode = .byTruncatingTail
        return tf
    }()
    private let chevronButton = _ToggleChevronButton()

    private let contentBody = _FlippedContainerView()
    private var contentTextView: _TabsTextView!
    private let resizeHandle = _ToggleResizeHandle()

    // MARK: - State

    /// When true, `textDidChange` (which calls `onDataChanged`) is suppressed.
    /// We toggle this during programmatic text installs so we don't echo our
    /// own edits back to the host.
    private var isSyncingContent = false

    /// When true, `applyData(_:)` is installing data and title-field delegate
    /// callbacks should not re-fire `onDataChanged`.
    private var isApplyingData = false

    /// Tint / appearance observers we own — torn down in deinit.
    private var tintObservers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }

    // MARK: - Init

    init(
        data: ToggleData,
        containerWidth: CGFloat,
        parentTextView: NSTextView?,
        attachmentID: UUID,
        onDataChanged:   @escaping (ToggleData) -> Void,
        onExitToParent:  @escaping () -> Void,
        onHeightChanged: @escaping (CGFloat) -> Void,
        onWidthChanged:  @escaping (CGFloat?) -> Void
    ) {
        self.toggleData            = data
        self.attachmentID          = attachmentID
        self.parentTextView        = parentTextView
        self.currentContainerWidth = containerWidth
        self.onDataChanged         = onDataChanged
        self.onExitToParent        = onExitToParent
        self.onHeightChanged       = onHeightChanged
        self.onWidthChanged        = onWidthChanged

        super.init(frame: CGRect(
            origin: .zero,
            size: CGSize(
                width:  max(Self.minWidth, containerWidth > 0 ? containerWidth : Self.minWidth),
                height: Self.heightForData(data, width: containerWidth > 0 ? containerWidth : Self.minWidth)
            )
        ))

        contentTextView = buildContentTextView()
        setupViews()
        installTitle(data.title)
        installContent(data.content)
        updateColors()
        applyExpandedState(animated: false)
        setupObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        for obs in tintObservers {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Public Height Measurement

    /// Total overlay height for a given data snapshot + width.
    ///
    /// When `isExpanded == false` we return `collapsedHeight` (34pt) — the
    /// content area does not contribute to height when the toggle is closed.
    /// Otherwise we use a shared sizing text view to measure the serialized
    /// content via `layoutManager.usedRect(for:)`.
    static func heightForData(_ data: ToggleData, width: CGFloat) -> CGFloat {
        guard data.isExpanded else { return collapsedHeight }

        let effectiveW = max(width, minWidth)
        let contentW   = max(effectiveW - hPad * 2 - contentPadH * 2, 40)

        let bodyH = measureContentHeight(serialized: data.content, width: contentW)
        let contentBlockH = max(bodyH + contentPadTop + contentPadBot, minContentHeight)
        return collapsedHeight + rowContentGap + contentBlockH
    }

    /// Shared sizing stack — layoutManager/textStorage/textContainer kept alive
    /// so we don't rebuild on every paragraph edit. Single sizing instance is
    /// thread-safe enough for MainActor-bound callers (the whole project is
    /// MainActor by default).
    private static let sizingStorage: NSTextStorage = NSTextStorage()
    private static let sizingLayoutManager: NSLayoutManager = {
        let lm = NSLayoutManager()
        sizingStorage.addLayoutManager(lm)
        return lm
    }()
    private static let sizingContainer: NSTextContainer = {
        let c = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        c.widthTracksTextView = false
        c.lineFragmentPadding = 0
        sizingLayoutManager.addTextContainer(c)
        return c
    }()

    private static func measureContentHeight(serialized: String, width: CGFloat) -> CGFloat {
        sizingContainer.size = NSSize(width: max(width, 10), height: CGFloat.greatestFiniteMagnitude)
        let attr = RichTextSerializer.deserializeToAttributedString(serialized)
        let mutable = NSMutableAttributedString(attributedString: attr)
        // Ensure at least one empty paragraph so placeholder sizes sanely.
        if mutable.length == 0 {
            mutable.append(NSAttributedString(
                string: " ",
                attributes: RichTextSerializer.baseTypingAttributes()
            ))
        }
        sizingStorage.setAttributedString(mutable)
        sizingLayoutManager.ensureLayout(for: sizingContainer)
        let used = sizingLayoutManager.usedRect(for: sizingContainer)
        return ceil(used.height)
    }

    // MARK: - Public API: Data / Width

    /// Replace the current data snapshot (e.g. during deserialize reloads or
    /// external undo). Does not emit `onDataChanged`.
    func applyData(_ data: ToggleData) {
        isApplyingData = true
        defer { isApplyingData = false }

        let titleChanged      = data.title          != toggleData.title
        let contentChanged    = data.content        != toggleData.content
        let expandedChanged   = data.isExpanded     != toggleData.isExpanded

        toggleData = data

        if titleChanged {
            installTitle(data.title)
        }
        if contentChanged {
            installContent(data.content)
        }
        if expandedChanged {
            applyExpandedState(animated: false)
        } else if contentChanged {
            needsLayout = true
        }
    }

    /// Called by the coordinator BEFORE resizing the hosted NSView. Ensures
    /// layout math uses the live container width.
    func setContainerWidth(_ width: CGFloat) {
        currentContainerWidth = width
        needsLayout = true
    }

    // MARK: - View Construction

    private func buildContentTextView() -> _TabsTextView {
        let storage = NSTextStorage()
        let layoutManager = _TabsLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let tv = _TabsTextView(frame: .zero, textContainer: container)
        tv.isEditable          = true
        tv.isSelectable        = true
        tv.allowsUndo          = true
        tv.drawsBackground     = false
        tv.backgroundColor     = .clear
        tv.isRichText          = true
        tv.isAutomaticQuoteSubstitutionEnabled  = false
        tv.isAutomaticDashSubstitutionEnabled   = false
        tv.isAutomaticTextReplacementEnabled    = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset      = NSSize(width: 0, height: 0)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable   = true
        tv.maxSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.focusRingType = .none
        tv.font      = FontManager.bodyNS(size: ThemeManager.currentBodyFontSize(), weight: .regular)
        tv.textColor = NSColor(named: "PrimaryTextColor") ?? .labelColor
        return tv
    }

    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = false

        // Title row (flat — no pill chrome)
        titleRow.wantsLayer = true
        addSubview(titleRow)

        // Title text field
        titleField.delegate = self
        titleField.font = FontManager.headingNS(size: 15, weight: .semibold)
        titleField.textColor = NSColor(named: "PrimaryTextColor") ?? .labelColor
        let placeholderColor = NSColor(named: "SecondaryTextColor") ?? .secondaryLabelColor
        titleField.placeholderAttributedString = NSAttributedString(
            string: "Toggle",
            attributes: [
                .font: FontManager.headingNS(size: 15, weight: .semibold),
                .foregroundColor: placeholderColor
            ]
        )
        titleRow.addSubview(titleField)

        // Chevron button
        chevronButton.onActivate = { [weak self] in self?.toggleExpanded() }
        titleRow.addSubview(chevronButton)

        // Content body
        contentBody.wantsLayer = true
        contentBody.layer?.masksToBounds = true
        addSubview(contentBody)
        contentBody.addSubview(contentTextView)
        contentTextView.delegate = self

        // Resize handle (right edge, width-only drag)
        resizeHandle.onDragBegan = { [weak self] in
            // No per-drag-start snapshot callback in the public API — host
            // treats the width change at drag-end like Callout/Tabs do.
        }
        resizeHandle.onDrag = { [weak self] newWidth in
            self?.handleResize(to: newWidth)
        }
        resizeHandle.onDragEnd = { [weak self] in
            guard let self = self else { return }
            let w = self.currentContentWidth()
            // Emit final width. If at full container width, report nil so the
            // host knows this is the "reset" state.
            if self.currentContainerWidth > 0, w >= self.currentContainerWidth - 0.5 {
                self.toggleData.preferredContentWidth = nil
                self.onWidthChanged?(nil)
            } else {
                self.toggleData.preferredContentWidth = w
                self.onWidthChanged?(w)
            }
        }
        resizeHandle.onDoubleClick = { [weak self] in
            guard let self = self, self.currentContainerWidth > 0 else { return }
            self.handleResize(to: self.currentContainerWidth)
            self.toggleData.preferredContentWidth = nil
            self.onWidthChanged?(nil)
        }
        addSubview(resizeHandle)
    }

    private func setupObservers() {
        // Tint changes — refresh any themed surface color.
        let tintObs = NotificationCenter.default.addObserver(
            forName: ThemeManager.tintDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateColors()
        }
        tintObservers.append(tintObs)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let W = bounds.width
        let contentW = currentContentWidth()

        // Title row (flat, collapsedHeight tall)
        titleRow.frame = CGRect(x: 0, y: 0, width: contentW, height: Self.collapsedHeight)

        // Chevron right-aligned
        let chevX = contentW - Self.chevronTrailing - Self.chevronSize
        let chevY = (Self.collapsedHeight - Self.chevronSize) / 2
        chevronButton.frame = CGRect(
            x: chevX, y: chevY,
            width: Self.chevronSize, height: Self.chevronSize
        )

        // Title field fills remaining space
        let titleX = Self.hPad
        let titleFieldH: CGFloat = 22
        let titleY = (Self.collapsedHeight - titleFieldH) / 2
        let titleW = max(chevX - Self.titleChevronGap - titleX, 20)
        titleField.frame = CGRect(x: titleX, y: titleY, width: titleW, height: titleFieldH)

        // Content body
        if toggleData.isExpanded {
            let bodyY = Self.collapsedHeight + Self.rowContentGap
            let bodyH = max(bounds.height - bodyY, 0)
            contentBody.isHidden = false
            contentBody.frame = CGRect(
                x: Self.hPad, y: bodyY,
                width: max(contentW - Self.hPad * 2, 20),
                height: bodyH
            )
            let txW = max(contentBody.bounds.width - Self.contentPadH * 2, 20)
            let txH = max(contentBody.bounds.height - Self.contentPadTop - Self.contentPadBot, 20)
            contentTextView.frame = CGRect(
                x: Self.contentPadH, y: Self.contentPadTop,
                width: txW, height: txH
            )
            contentTextView.minSize = CGSize(width: txW, height: txH)
            contentTextView.textContainer?.containerSize = CGSize(
                width: txW, height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            contentBody.isHidden = true
            contentBody.frame = .zero
        }

        // Resize handle straddles the right edge
        resizeHandle.frame = CGRect(
            x: contentW - Self.handleWidth / 2, y: 0,
            width: Self.handleWidth, height: bounds.height
        )

        // Keep chevron rotation in sync on re-layout (preserves state after
        // re-parent / theme flips without animating).
        chevronButton.setExpanded(toggleData.isExpanded, animated: false)
    }

    private func currentContentWidth() -> CGFloat {
        // The outer frame may include `resizeHitOutset` (parent expands the
        // frame for hit-testing on the right). Honour it when present.
        if bounds.width > Self.minWidth + Self.resizeHitOutset {
            return bounds.width - Self.resizeHitOutset
        }
        return bounds.width
    }

    // MARK: - Title + Content installation

    private func installTitle(_ title: String) {
        isApplyingData = true
        defer { isApplyingData = false }
        titleField.stringValue = title
    }

    private func installContent(_ serialized: String) {
        isSyncingContent = true
        defer { isSyncingContent = false }
        let attr = RichTextSerializer.deserializeToAttributedString(serialized)
        contentTextView.textStorage?.setAttributedString(attr)
        contentTextView.typingAttributes = RichTextSerializer.baseTypingAttributes()
    }

    // MARK: - Expand / Collapse

    private func toggleExpanded() {
        toggleData.isExpanded.toggle()
        chevronButton.setExpanded(toggleData.isExpanded, animated: true)
        onDataChanged?(toggleData)
        applyExpandedState(animated: true)
    }

    private func applyExpandedState(animated: Bool) {
        if !toggleData.isExpanded,
           let window = window,
           window.firstResponder === contentTextView {
            window.makeFirstResponder(parentTextView)
        }

        let newHeight = Self.heightForData(toggleData, width: currentContentWidth())
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = false
                self.contentBody.animator().alphaValue = self.toggleData.isExpanded ? 1.0 : 0.0
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                self.contentBody.alphaValue = self.toggleData.isExpanded ? 1.0 : 0.0
                self.contentBody.isHidden = !self.toggleData.isExpanded
                self.onHeightChanged?(newHeight)
                self.needsLayout = true
            })
            // Still notify the host right away so the attachment cell resizes
            // in lockstep with the crossfade (avoids a height pop at the end).
            onHeightChanged?(newHeight)
        } else {
            contentBody.alphaValue = toggleData.isExpanded ? 1.0 : 0.0
            contentBody.isHidden = !toggleData.isExpanded
            onHeightChanged?(newHeight)
            needsLayout = true
        }
    }

    // MARK: - Resize

    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        guard resizeHandle.frame.contains(local) else { return nil }
        return NSCursor.compatFrameResize(position: "right")
    }

    private func handleResize(to newWidth: CGFloat) {
        let effectiveMax = currentContainerWidth > 0 ? currentContainerWidth : CGFloat.greatestFiniteMagnitude
        let effectiveMin = min(Self.minWidth, effectiveMax)
        let clamped = floor(max(effectiveMin, min(effectiveMax, newWidth)))
        var f = frame
        f.size.width = clamped + Self.resizeHitOutset
        frame = f
        needsLayout = true
    }

    // MARK: - Colors

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func updateColors() {
        titleField.textColor    = NSColor(named: "PrimaryTextColor")   ?? .labelColor
        contentTextView.textColor = NSColor(named: "PrimaryTextColor") ?? .labelColor
        chevronButton.updateColor()
        let placeholderColor = NSColor(named: "SecondaryTextColor") ?? .secondaryLabelColor
        titleField.placeholderAttributedString = NSAttributedString(
            string: "Toggle",
            attributes: [
                .font: FontManager.headingNS(size: 15, weight: .semibold),
                .foregroundColor: placeholderColor
            ]
        )
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let expandItem = NSMenuItem(
            title: toggleData.isExpanded ? "Collapse" : "Expand",
            action: #selector(menuToggleExpanded),
            keyEquivalent: ""
        )
        expandItem.target = self
        menu.addItem(expandItem)
        return menu
    }

    @objc private func menuToggleExpanded() {
        toggleExpanded()
    }
}

// MARK: - NSTextFieldDelegate (title)

extension ToggleOverlayView: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        guard !isApplyingData else { return }
        toggleData.title = titleField.stringValue
        onDataChanged?(toggleData)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isApplyingData else { return }
        toggleData.title = titleField.stringValue
        onDataChanged?(toggleData)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        // Enter in the title field should jump focus into the content body
        // (expanding first if collapsed). Matches Notion's behaviour.
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if !toggleData.isExpanded {
                toggleExpanded()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.window?.makeFirstResponder(self.contentTextView)
            }
            return true
        }
        return false
    }
}

// MARK: - NSTextViewDelegate (content body)

extension ToggleOverlayView: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        guard notification.object as? _TabsTextView === contentTextView else { return }
        guard !isSyncingContent else { return }

        styleBodyParagraphs(contentTextView)
        toggleData.content = RichTextSerializer.serializeAttributedString(
            contentTextView.attributedString()
        )
        onDataChanged?(toggleData)

        // Content height likely changed — notify host so the attachment cell
        // resizes. Uses the live content width so the math matches layout().
        let newHeight = Self.heightForData(toggleData, width: currentContentWidth())
        onHeightChanged?(newHeight)
    }

    /// Mirrors `TabsContainerOverlayView.styleTabParagraphs` so headings,
    /// block quotes, ordered lists etc. keep the right paragraph style after
    /// each edit. Kept in sync with the Tabs version intentionally.
    private func styleBodyParagraphs(_ tv: _TabsTextView) {
        guard let storage = tv.textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        (storage.string as NSString).enumerateSubstrings(in: fullRange, options: .byParagraphs) { _, paraRange, _, _ in
            let isBlockQuote = storage.attribute(.blockQuote, at: paraRange.location, effectiveRange: nil) as? Bool == true
            let isOrderedList = storage.attribute(.orderedListNumber, at: paraRange.location, effectiveRange: nil) != nil

            if isBlockQuote {
                storage.addAttribute(.paragraphStyle, value: RichTextSerializer.blockQuoteParagraphStyle(), range: paraRange)
            } else if isOrderedList {
                storage.addAttribute(.paragraphStyle, value: RichTextSerializer.orderedListParagraphStyle(), range: paraRange)
            } else {
                if let font = storage.attribute(.font, at: paraRange.location, effectiveRange: nil) as? NSFont,
                   RichTextSerializer.headingLevel(for: font) != nil {
                    // Heading style already set by TextFormattingManager
                } else {
                    let existingPS = storage.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle
                    let alignment = existingPS?.alignment ?? .left
                    if alignment != .left {
                        let ps = RichTextSerializer.baseParagraphStyle().mutableCopy() as! NSMutableParagraphStyle
                        ps.alignment = alignment
                        storage.addAttribute(.paragraphStyle, value: ps, range: paraRange)
                    } else {
                        storage.addAttribute(.paragraphStyle, value: RichTextSerializer.baseParagraphStyle(), range: paraRange)
                    }
                }
            }
        }
        storage.endEditing()
    }

    /// Double-Enter exit: pressing Return on an empty paragraph when the
    /// previous paragraph is also empty (or it's the first/only paragraph and
    /// empty) returns focus to the parent text view and strips the trailing
    /// empty paragraph we'd otherwise leave in the body.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === contentTextView else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if shouldExitOnEnter() {
                stripTrailingEmptyParagraphAndExit()
                return true
            }
        }
        return false
    }

    private func shouldExitOnEnter() -> Bool {
        guard let storage = contentTextView.textStorage else { return false }
        let full = storage.string as NSString
        let caret = contentTextView.selectedRange().location
        guard caret <= full.length else { return false }

        // Paragraph range for the caret's line
        let caretParaRange = full.paragraphRange(for: NSRange(location: caret, length: 0))
        let caretLine = full.substring(with: caretParaRange)
            .trimmingCharacters(in: CharacterSet.newlines)

        // Current line must be empty (no non-newline characters)
        guard caretLine.isEmpty else { return false }

        // If we're on the first paragraph and it's empty, exit — the block
        // contains nothing meaningful anyway.
        if caretParaRange.location == 0 {
            return true
        }

        // Otherwise require the previous paragraph to also be empty.
        let prevRange = full.paragraphRange(
            for: NSRange(location: caretParaRange.location - 1, length: 0)
        )
        let prevLine = full.substring(with: prevRange)
            .trimmingCharacters(in: CharacterSet.newlines)
        return prevLine.isEmpty
    }

    private func stripTrailingEmptyParagraphAndExit() {
        guard let storage = contentTextView.textStorage else { return }
        let full = storage.string as NSString
        let caret = contentTextView.selectedRange().location
        guard caret <= full.length else { return }

        // Remove the blank line that triggered the exit (including its
        // preceding newline, if present). Only touch storage if we're past
        // the start — first-paragraph exits don't need a delete.
        if caret > 0 {
            let removeLoc = max(0, caret - 1)
            let removeLen = caret - removeLoc
            let removeRange = NSRange(location: removeLoc, length: removeLen)
            if removeRange.location + removeRange.length <= storage.length {
                let ch = full.substring(with: removeRange)
                if ch == "\n" {
                    storage.replaceCharacters(in: removeRange, with: "")
                }
            }
            // Persist cleanup to the data model
            toggleData.content = RichTextSerializer.serializeAttributedString(
                contentTextView.attributedString()
            )
            onDataChanged?(toggleData)
        }

        // Surrender focus + tell the host to move the caret out of the
        // attachment. The coordinator's `onExitToParent` decides where
        // (typically: after the attachment + a fresh paragraph).
        if let window = window, let parent = parentTextView {
            window.makeFirstResponder(parent)
        }
        onExitToParent?()
    }
}

// MARK: - Chevron Button

private final class _ToggleChevronButton: NSView {

    var onActivate: (() -> Void)?

    private let imageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.image = NSImage(systemSymbolName: "arrowtriangle.right.fill", accessibilityDescription: nil)
        iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        iv.image?.isTemplate = true
        // Pre-set anchor & transform so we can rotate in place without
        // needing to reset the frame every call.
        iv.wantsLayer = true
        iv.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        return iv
    }()

    private var expanded: Bool = true

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(imageView)
        updateColor()
        // Apply initial rotation without animation.
        setExpanded(true, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        // `anchorPoint = (0.5, 0.5)` combined with `position` at the centre
        // keeps rotation in-place regardless of frame changes.
        if let layer = imageView.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            layer.bounds = CGRect(origin: .zero, size: bounds.size)
        }
    }

    /// Set chevron rotation to match `expanded`.
    ///
    /// `chevron.right` rotates 90° clockwise to point down when expanded. In
    /// AppKit's flipped coordinate space, positive z-rotation is clockwise
    /// (`.pi / 2`).
    func setExpanded(_ isExpanded: Bool, animated: Bool) {
        expanded = isExpanded
        let targetAngle: CGFloat = isExpanded ? .pi / 2 : 0

        guard let layer = imageView.layer else { return }

        if animated {
            let anim = CABasicAnimation(keyPath: "transform.rotation.z")
            anim.fromValue = layer.presentation()?.value(forKeyPath: "transform.rotation.z") ?? layer.value(forKeyPath: "transform.rotation.z")
            anim.toValue   = targetAngle
            anim.duration  = 0.2
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(anim, forKey: "toggleRotation")
        }
        layer.setValue(targetAngle, forKeyPath: "transform.rotation.z")
    }

    func updateColor() {
        imageView.contentTintColor = NSColor(named: "MenuButtonColor") ?? .secondaryLabelColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Resize Handle (right edge, width only)

private final class _ToggleResizeHandle: NSView {

    var onDragBegan: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragEnd: (() -> Void)?

    private var dragStartX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    private var didDragThisGesture = false

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

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

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
        if let overlay = superview as? ToggleOverlayView {
            // Honour `resizeHitOutset` expansion the same way Callout does.
            dragStartWidth = max(
                0,
                overlay.bounds.width - ToggleOverlayView.resizeHitOutset
            )
        } else {
            dragStartWidth = superview?.bounds.width ?? 0
        }
        onDragBegan?()
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

// MARK: - Flipped container view

private final class _FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}
