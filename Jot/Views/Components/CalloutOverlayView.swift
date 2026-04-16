//
//  CalloutOverlayView.swift
//  Jot
//
//  Overlay NSView rendering a callout block inside the text editor.
//  Structure: single rounded block with a floating capsule pill straddling the
//  top edge at left: 18px. Pill contains type icon, label, and chevron dropdown.
//  Figma source: node 2448:7886
//

import AppKit

final class CalloutOverlayView: NSView {

    static let minWidth: CGFloat = 400
    /// Set by the coordinator so drag-resize respects the actual container.
    var currentContainerWidth: CGFloat = 0
    private static let handleWidth: CGFloat = 12
    /// The handle is centered on the content's right edge, so half its width sits outside the
    /// glyph/attachment rect. The overlay's `frame` must extend by this amount on the right or
    /// AppKit hit-testing never reaches the outer half (cursor shows via `cursorForPoint`, but
    /// `mouseDown` falls through to the text view). Matches the table overlay expansion pattern.
    static let resizeHitOutset: CGFloat = handleWidth / 2

    var calloutData: CalloutData {
        didSet {
            updateAppearance()
            updateContent()
        }
    }

    weak var parentTextView: NSTextView?
    var onDataChanged:  ((CalloutData) -> Void)?
    var onDeleteCallout: (() -> Void)?
    var onWidthChanged: ((CGFloat) -> Void)?
    /// Invoked once when a resize gesture completes (drag release or double-click snap).
    /// Keeps `syncText()` off the hot path so `styleTodoParagraphs` / binding churn does not flash the whole note during drag.
    var onResizeGestureEnded: (() -> Void)?
    /// Width of the callout block content (attachment width). Layout uses this instead of
    /// `bounds.width` because `bounds.width` includes `resizeHitOutset` for hit testing.
    var contentLayoutWidth: CGFloat = 0

    // -- Figma Design Tokens (node 2448:7886) --------------------------------
    /// Fixed shell corner radius (points). Same as code blocks — not derived from content height.
    private let blockRadius:        CGFloat = 22
    private let blockPaddingTop:    CGFloat = 24   // clears pill
    private let blockPaddingBottom: CGFloat = 16   // var(--base, 16px)
    private let blockPaddingH:      CGFloat = 16   // var(--base, 16px)
    private let pillPadding:        CGFloat = 4    // var(--xs2, 4px)
    private let pillLeftOffset:     CGFloat = 18   // Figma: left: 18px
    private let chipIconGap:        CGFloat = 5
    private let chipChevGap:        CGFloat = 3
    private let iconSize:           CGFloat = 15
    private let chevronSize:        CGFloat = 15   // was 14 -- updated per Figma

    /// Pill height = pillPadding(4) + iconSize(18) + pillPadding(4) = 26px
    private var pillHeight: CGFloat { pillPadding * 2 + iconSize }
    /// Half the pill extends above the block's top edge.
    private var pillOverflow: CGFloat { pillHeight / 2 }

    // -- Subviews -------------------------------------------------------------
    private let blockView  = NSView()
    private let chipView   = _ChipButton()
    private let iconView   = NSImageView()
    private let chipLabel: NSTextField = {
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
    private let resizeHandle = _CalloutResizeHandle()
    private let textField: NSTextField = {
        let tf = NSTextField()
        tf.isBordered = false
        tf.isEditable = true
        tf.isSelectable = true
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        tf.lineBreakMode = .byWordWrapping
        tf.usesSingleLineMode = false
        tf.maximumNumberOfLines = 0
        tf.font = .systemFont(ofSize: 15, weight: .regular)
        tf.textColor = .labelColor
        return tf
    }()

    override var isFlipped: Bool { true }

    // MARK: - Init

    init(calloutData: CalloutData) {
        self.calloutData = calloutData
        super.init(frame: .zero)
        buildView()
        updateAppearance()
        updateContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildView() {
        wantsLayer = true
        layer?.masksToBounds = false  // pill must extend above block bounds

        // Block -- single rounded background for content
        blockView.wantsLayer = true
        blockView.layer?.cornerRadius = blockRadius
        blockView.layer?.cornerCurve = .continuous
        blockView.layer?.masksToBounds = true
        addSubview(blockView)

        blockView.addSubview(textField)
        textField.delegate = self

        // Chip pill -- floats as sibling of blockView, straddles top edge
        chipView.wantsLayer = true
        chipView.onActivate = { [weak self] in self?.showTypePicker() }
        addSubview(chipView)
        chipView.addSubview(iconView)
        chipView.addSubview(chipLabel)
        chipView.addSubview(chevronView)

        // Resize handle
        resizeHandle.onDrag = { [weak self] newWidth in
            self?.handleResize(to: newWidth)
        }
        resizeHandle.onDragEnd = { [weak self] in
            self?.onResizeGestureEnded?()
        }
        resizeHandle.onDoubleClick = { [weak self] in
            // Double-click snaps to full container width. The coordinator's onWidthChanged
            // will update attachment, invalidate layout, and persist. See setup-doubleclick-handles todo.
            if let containerW = self?.currentContainerWidth, containerW > 0 {
                self?.handleResize(to: containerW)
                self?.onResizeGestureEnded?()
            }
        }
        addSubview(resizeHandle)
    }

    func handleResize(to newWidth: CGFloat) {
        let effectiveMax = currentContainerWidth > 0 ? currentContainerWidth : CGFloat.greatestFiniteMagnitude
        let effectiveMin = min(Self.minWidth, effectiveMax)
        let clamped = floor(max(effectiveMin, min(effectiveMax, newWidth)))
        contentLayoutWidth = clamped
        var f = frame
        f.size.width = clamped + Self.resizeHitOutset
        frame = f
        needsLayout = true
        onWidthChanged?(clamped)
    }

    // MARK: - Appearance

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let colors = calloutData.type.viewColors

        // Block background -- /950 dark, /50 light
        blockView.layer?.backgroundColor = isDark ? colors.blockDark.cgColor : colors.blockLight.cgColor

        // Chip pill -- mode-dependent accent, white contents
        chipView.layer?.backgroundColor = isDark ? colors.pillDark.cgColor : colors.pillLight.cgColor

        chipLabel.attributedStringValue = NSAttributedString(
            string: calloutData.type.rawValue.capitalized,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
                .kern: NSNumber(value: -0.2)
            ]
        )

        iconView.contentTintColor = .white
        if let img = NSImage(named: calloutData.type.icon) {
            img.isTemplate = true
            iconView.image = img
            iconView.imageScaling = .scaleProportionallyUpOrDown
        }

        chevronView.contentTintColor = .white

        // Text color -- full opacity
        textField.textColor = isDark ? .white : NSColor(srgbRed: 26/255, green: 26/255, blue: 26/255, alpha: 1)

        // Placeholder -- 70% opacity
        let placeholderColor: NSColor = isDark
            ? .white.withAlphaComponent(0.7)
            : NSColor(srgbRed: 26/255, green: 26/255, blue: 26/255, alpha: 0.7)
        textField.placeholderAttributedString = NSAttributedString(
            string: "Type callout content...",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: placeholderColor,
                .kern: NSNumber(value: 0)
            ]
        )

        needsLayout = true
    }

    private func updateContent() {
        textField.stringValue = calloutData.content
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let pO = pillOverflow  // 13px
        let contentW = contentLayoutWidth > 0 ? contentLayoutWidth : bounds.width

        // Block fills content width, offset down by pill overflow
        let blockH = max(bounds.height - pO, 50)
        blockView.frame = CGRect(x: 0, y: pO, width: contentW, height: blockH)

        // Text field inside block
        let tfW = max(contentW - blockPaddingH * 2, 40)
        let tfH = max(blockH - blockPaddingTop - blockPaddingBottom, 20)
        // blockView is non-flipped (y=0 at bottom), so y=blockPaddingBottom
        // gives 16px from bottom, leaving 24px at the top to clear the pill
        textField.frame = CGRect(x: blockPaddingH, y: blockPaddingBottom, width: tfW, height: tfH)

        // Chip pill -- straddles blockView's top edge
        chipLabel.sizeToFit()
        let labelW = ceil(chipLabel.frame.width) + 1
        let labelH = ceil(chipLabel.frame.height)
        let chipW = pillPadding + iconSize + chipIconGap + labelW + chipChevGap + chevronSize + pillPadding
        let chipH = pillHeight  // 26px
        chipView.frame = CGRect(x: pillLeftOffset, y: 0, width: chipW, height: chipH)
        chipView.layer?.cornerRadius = chipH / 2  // capsule

        // Icon inside chip
        let iconOffY = (chipH - iconSize) / 2
        iconView.frame = CGRect(x: pillPadding, y: iconOffY, width: iconSize, height: iconSize)

        // Label inside chip
        let labelOffY = (chipH - labelH) / 2
        chipLabel.frame = CGRect(
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

        // Resize handle -- straddles right edge of content (not expanded bounds)
        resizeHandle.frame = CGRect(
            x: contentW - Self.handleWidth / 2,
            y: 0,
            width: Self.handleWidth,
            height: bounds.height
        )
    }

    // MARK: - Cursor

    /// Returns the resize cursor if the window point falls on the resize handle, nil otherwise.
    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        guard resizeHandle.frame.contains(local) else { return nil }
        return NSCursor.compatFrameResize(position: "right")
    }

    // MARK: - Height Calculation

    /// Reusable sizing field configured identically to the real text field.
    /// Using cellSize(forBounds:) gives exact height -- no manual padding guesswork.
    private static let sizingField: NSTextField = {
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        tf.lineBreakMode = .byWordWrapping
        tf.usesSingleLineMode = false
        tf.maximumNumberOfLines = 0
        tf.font = .systemFont(ofSize: 15, weight: .regular)
        return tf
    }()

    static func heightForData(_ data: CalloutData, width: CGFloat) -> CGFloat {
        let pillOverflow: CGFloat = 13     // half of 26px pill
        let topPad: CGFloat = 24           // block top padding (clears pill)
        let bottomPad: CGFloat = 16        // block bottom padding
        let hPad: CGFloat = 16             // horizontal padding
        let tfW = max(width - hPad * 2, 40)
        let text = data.content.isEmpty ? "A" : data.content
        sizingField.stringValue = text
        let cellH = sizingField.cell!.cellSize(
            forBounds: NSRect(x: 0, y: 0, width: tfW, height: .greatestFiniteMagnitude)
        ).height
        return pillOverflow + topPad + max(ceil(cellH), 20) + bottomPad
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    // MARK: - Type Picker

    private func showTypePicker() {
        let menu = NSMenu()
        for type in CalloutData.CalloutType.allCases {
            let item = NSMenuItem(
                title: type.rawValue.capitalized,
                action: #selector(changeType(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = type
            if type == calloutData.type { item.state = .on }
            menu.addItem(item)
        }
        let anchorPoint = CGPoint(x: chipView.frame.origin.x, y: chipView.frame.maxY)
        menu.popUp(positioning: nil, at: anchorPoint, in: self)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let typeMenu = NSMenu()
        for type in CalloutData.CalloutType.allCases {
            let item = NSMenuItem(
                title: type.rawValue.capitalized,
                action: #selector(changeType(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = type
            if type == calloutData.type { item.state = .on }
            typeMenu.addItem(item)
        }
        let typeItem = NSMenuItem(title: "Type", action: nil, keyEquivalent: "")
        typeItem.submenu = typeMenu
        menu.addItem(typeItem)
        menu.addItem(.separator())
        let deleteItem = NSMenuItem(
            title: "Delete Callout",
            action: #selector(deleteCallout),
            keyEquivalent: ""
        )
        deleteItem.target = self
        menu.addItem(deleteItem)
        return menu
    }

    @objc private func changeType(_ sender: NSMenuItem) {
        guard let newType = sender.representedObject as? CalloutData.CalloutType else { return }
        calloutData.type = newType
        onDataChanged?(calloutData)
    }

    @objc private func deleteCallout() {
        onDeleteCallout?()
    }
}

// MARK: - NSTextFieldDelegate

extension CalloutOverlayView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        calloutData.content = textField.stringValue
        onDataChanged?(calloutData)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        calloutData.content = textField.stringValue
        onDataChanged?(calloutData)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            textView.insertNewlineIgnoringFieldEditor(nil)
            calloutData.content = textField.stringValue
            onDataChanged?(calloutData)
            return true
        }
        return false
    }
}

// MARK: - Resize Handle

private final class _CalloutResizeHandle: NSView {

    var onDrag: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?  // Supports double-click on right edge to snap to full container width (per user request for callout/code/tab blocks etc.)
    /// Called on mouse up after the user actually dragged (not plain click / double-click).
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
            // Double-click right edge snaps to full available page width (containerWidth).
            // Matches existing pattern in CodeBlockOverlayView and NoteTableOverlayView.
            // See feedback on double-click resize and TodoEditorRepresentable coordinator.
            onDoubleClick?()
            return
        }
        didDragThisGesture = false
        dragStartX = event.locationInWindow.x
        // Use content width, not overlay bounds.width (bounds include resizeHitOutset on the right).
        if let overlay = superview as? CalloutOverlayView {
            dragStartWidth = overlay.contentLayoutWidth > 0
                ? overlay.contentLayoutWidth
                : max(0, overlay.bounds.width - CalloutOverlayView.resizeHitOutset)
        } else {
            dragStartWidth = superview?.bounds.width ?? 0
        }
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

// MARK: - Chip Button (type picker trigger)

private final class _ChipButton: NSView {

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

// MARK: - Per-Type View Colors

private struct CalloutTypeColors {
    let blockLight: NSColor  // /50 or /100 shade
    let blockDark:  NSColor  // /950 shade
    let pillLight:  NSColor  // pill bg in light mode
    let pillDark:   NSColor  // pill bg in dark mode

    /// Convenience for types that use the same pill color in both modes.
    init(blockLight: NSColor, blockDark: NSColor, pillColor: NSColor) {
        self.blockLight = blockLight
        self.blockDark  = blockDark
        self.pillLight  = pillColor
        self.pillDark   = pillColor
    }

    init(blockLight: NSColor, blockDark: NSColor, pillLight: NSColor, pillDark: NSColor) {
        self.blockLight = blockLight
        self.blockDark  = blockDark
        self.pillLight  = pillLight
        self.pillDark   = pillDark
    }
}

private extension CalloutData.CalloutType {
    var viewColors: CalloutTypeColors {
        switch self {
        case .info:
            return CalloutTypeColors(
                blockLight: NSColor(hex: "#BFDBFE"),   // blue-200
                blockDark:  NSColor(hex: "#172554"),   // blue-950
                pillColor:  NSColor(hex: "#2563EB")    // blue-600
            )
        case .warning:
            return CalloutTypeColors(
                blockLight: NSColor(hex: "#FEF08A"),   // yellow-200
                blockDark:  NSColor(hex: "#422006"),   // yellow-950
                pillColor:  NSColor(hex: "#CA8A04")    // yellow-600
            )
        case .tip:
            return CalloutTypeColors(
                blockLight: NSColor(hex: "#BBF7D0"),   // green-200
                blockDark:  NSColor(hex: "#052E16"),   // green-950
                pillColor:  NSColor(hex: "#16A34A")    // green-600
            )
        case .note:
            return CalloutTypeColors(
                blockLight: NSColor(hex: "#E9D5FF"),   // purple-200
                blockDark:  NSColor(hex: "#3B0764"),   // purple-950
                pillLight:  NSColor(hex: "#6B21A8"),    // purple-800
                pillDark:   NSColor(hex: "#7E22CE")     // purple-700
            )
        case .important:
            return CalloutTypeColors(
                blockLight: NSColor(hex: "#FECACA"),   // red-200
                blockDark:  NSColor(hex: "#450A0A"),   // red-950
                pillColor:  NSColor(hex: "#DC2626")    // red-600
            )
        }
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green:   CGFloat((rgb >> 8)  & 0xFF) / 255,
            blue:    CGFloat( rgb        & 0xFF) / 255,
            alpha: 1
        )
    }
}
