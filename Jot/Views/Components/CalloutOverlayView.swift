//
//  CalloutOverlayView.swift
//  Jot
//
//  Overlay NSView rendering a callout block inside the text editor.
//  Structure: outer colored shell (16px radius, 2px padding) wrapping
//  a header row (icon chip + label + chevron) and an inner content block (14px radius).
//  Figma source: node 2254:4251
//

import AppKit

final class CalloutOverlayView: NSView {

    static let minWidth: CGFloat = 400
    /// Set by the coordinator so drag-resize respects the actual container.
    var currentContainerWidth: CGFloat = 0
    private static let handleWidth: CGFloat = 12

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

    // ── Figma Design Tokens ──────────────────────────────────────────────
    private let outerRadius:   CGFloat = 22
    private let outerPadding:  CGFloat = 2   // xxs — gap between shell and inner block
    private let innerRadius:   CGFloat = 20  // concentric: 22 − 2
    private let innerPadding:  CGFloat = 16  // base
    private let headerPadding: CGFloat = 8   // xs
    private let chipPadding:   CGFloat = 2   // xxs
    private let chipIconGap:   CGFloat = 5
    private let chipChevGap:   CGFloat = 3
    private let iconSize:      CGFloat = 18
    private let chevronSize:   CGFloat = 14

    // ── Subviews ─────────────────────────────────────────────────────────
    private let headerView = NSView()
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
    private let innerBlock = NSView()
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
        tf.font = .systemFont(ofSize: 15, weight: .medium)
        tf.textColor = .labelColor
        return tf
    }()

    override var isFlipped: Bool { true }

    // Header height: 8px top + 18px icon + 8px bottom = 34pt
    private var headerHeight: CGFloat { headerPadding * 2 + iconSize }

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
        layer?.cornerRadius = outerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.borderWidth = 1.0

        addSubview(headerView)

        // Chip — type picker trigger (capsule, transparent — no masksToBounds so label
        // is never silently clipped by the chip boundary)
        chipView.wantsLayer = true
        chipView.onActivate = { [weak self] in self?.showTypePicker() }
        headerView.addSubview(chipView)
        chipView.addSubview(iconView)
        chipView.addSubview(chipLabel)
        chipView.addSubview(chevronView)

        // Inner content block
        innerBlock.wantsLayer = true
        innerBlock.layer?.cornerRadius = innerRadius
        innerBlock.layer?.cornerCurve = .continuous
        innerBlock.layer?.masksToBounds = true
        addSubview(innerBlock)

        innerBlock.addSubview(textField)
        textField.delegate = self

        // Resize handle
        resizeHandle.onDrag = { [weak self] newWidth in
            self?.handleResize(to: newWidth)
        }
        addSubview(resizeHandle)
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

    // MARK: - Appearance

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let colors = calloutData.type.viewColors

        layer?.backgroundColor = isDark ? colors.outerDark.cgColor : colors.outerLight.cgColor
        layer?.borderColor = isDark
            ? NSColor.white.withAlphaComponent(0.06).cgColor
            : NSColor.black.withAlphaComponent(0.08).cgColor

        innerBlock.layer?.backgroundColor = isDark
            ? NSColor(srgbRed: 0x0C/255, green: 0x0A/255, blue: 0x09/255, alpha: 1).cgColor
            : NSColor.white.cgColor

        // Chip label — Label/Label-5/Medium: 11px, -0.2 kerning
        let labelColor = isDark ? colors.labelDark : colors.labelLight
        chipLabel.attributedStringValue = NSAttributedString(
            string: calloutData.type.rawValue.capitalized,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: labelColor,
                .kern: NSNumber(value: -0.2)
            ]
        )

        iconView.contentTintColor = labelColor
        if let img = NSImage(named: calloutData.type.icon) {
            img.isTemplate = true
            iconView.image = img
            iconView.imageScaling = .scaleProportionallyUpOrDown
        }

        chevronView.contentTintColor = labelColor

        // Placeholder — Label/Label-2/Medium: 15px, -0.5 kerning, 70% opacity
        let placeholderColor: NSColor = isDark
            ? .white.withAlphaComponent(0.7)
            : NSColor(srgbRed: 26/255, green: 26/255, blue: 26/255, alpha: 0.7)
        textField.placeholderAttributedString = NSAttributedString(
            string: "Type callout content...",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: placeholderColor,
                .kern: NSNumber(value: -0.5)
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

        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: outerRadius,
            cornerHeight: outerRadius,
            transform: nil
        )

        let p  = outerPadding
        let W  = bounds.width - p * 2
        let hH = headerHeight  // 34

        headerView.frame = CGRect(x: p, y: p, width: W, height: hH)

        // sizeToFit uses the same measurement path as NSTextFieldCell drawing,
        // making it the only reliable way to get the true rendered width.
        chipLabel.sizeToFit()
        let labelW = ceil(chipLabel.frame.width) + 1
        let labelH = ceil(chipLabel.frame.height)
        let chipW = chipPadding + iconSize + chipIconGap + labelW + chipChevGap + chevronSize + chipPadding
        let chipH = chipPadding * 2 + iconSize
        let chipY = (hH - chipH) / 2
        chipView.frame = CGRect(
            x: headerPadding - chipPadding,
            y: chipY,
            width: chipW,
            height: chipH
        )
        chipView.layer?.cornerRadius = chipH / 2  // capsule

        // Icon
        let iconOffY = (chipH - iconSize) / 2
        iconView.frame = CGRect(x: chipPadding, y: iconOffY, width: iconSize, height: iconSize)

        // Label
        let labelOffY = (chipH - labelH) / 2
        chipLabel.frame = CGRect(
            x: chipPadding + iconSize + chipIconGap,
            y: labelOffY,
            width: labelW,
            height: labelH
        )

        // Chevron — rendered at 14pt so the SVG stroke stays at a visible weight
        let chevOffY = (chipH - chevronSize) / 2
        chevronView.frame = CGRect(
            x: chipPadding + iconSize + chipIconGap + labelW + chipChevGap,
            y: chevOffY,
            width: chevronSize,
            height: chevronSize
        )

        // Inner block
        let innerY = p + hH
        let innerH = max(bounds.height - innerY - p, 50)
        innerBlock.frame = CGRect(x: p, y: innerY, width: W, height: innerH)

        let tfW = max(W - innerPadding * 2, 40)
        let tfH = max(innerH - innerPadding * 2, 20)
        textField.frame = CGRect(x: innerPadding, y: innerPadding, width: tfW, height: tfH)

        // Resize handle — straddles right edge (half inside, half outside)
        resizeHandle.frame = CGRect(
            x: bounds.width - Self.handleWidth / 2,
            y: 0,
            width: Self.handleWidth,
            height: bounds.height
        )
    }

    // MARK: - Cursor

    /// Returns the resize cursor if the window point falls on the resize handle, nil otherwise.
    /// Called by the coordinator's resizeCursorForPoint to bypass NSTextView's I-beam override.
    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        guard resizeHandle.frame.contains(local) else { return nil }
        return NSCursor.frameResize(position: .right, directions: .all)
    }

    // MARK: - Height Calculation

    static func heightForData(_ data: CalloutData, width: CGFloat) -> CGFloat {
        let op: CGFloat = 2
        let hH: CGFloat = 34
        let ip: CGFloat = 16
        let tw  = max(width - op * 2 - ip * 2, 40)
        let text = data.content.isEmpty ? "A" : data.content
        let rect = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium)]
        ).boundingRect(
            with: CGSize(width: tw, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return op + hH + max(ceil(rect.height) + ip * 2, 50) + op
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
        let chipOriginInView = convert(chipView.frame.origin, from: headerView)
        let anchorPoint = CGPoint(x: chipOriginInView.x, y: chipOriginInView.y + chipView.frame.height)
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

// MARK: - Chip Button (type picker trigger)

private final class _ChipButton: NSView {

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

// MARK: - Per-Type View Colors

private struct CalloutTypeColors {
    let outerLight: NSColor
    let outerDark:  NSColor
    let labelLight: NSColor
    let labelDark:  NSColor
}

private extension CalloutData.CalloutType {
    var viewColors: CalloutTypeColors {
        switch self {
        case .info:
            // Matches CodeBlockOverlayView blue tokens exactly
            return CalloutTypeColors(
                outerLight: NSColor(srgbRed: 0.749, green: 0.859, blue: 0.996, alpha: 1),  // blue-200 #BFDBFE
                outerDark:  NSColor(srgbRed: 0.090, green: 0.145, blue: 0.329, alpha: 1),  // blue-950 #172554
                labelLight: NSColor(srgbRed: 0.145, green: 0.388, blue: 0.922, alpha: 1),  // blue-600
                labelDark:  NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)   // blue-500
            )
        case .warning:
            // Exact Figma yellow tokens
            return CalloutTypeColors(
                outerLight: NSColor(hex: "#fef08a"),  // yellow/200
                outerDark:  NSColor(hex: "#422006"),  // yellow/950
                labelLight: NSColor(hex: "#ca8a04"),  // yellow/600
                labelDark:  NSColor(hex: "#eab308")   // yellow/500
            )
        case .tip:
            return CalloutTypeColors(
                outerLight: NSColor(hex: "#bbf7d0"),  // green-200
                outerDark:  NSColor(hex: "#052e16"),  // green-950
                labelLight: NSColor(hex: "#16a34a"),  // green-600
                labelDark:  NSColor(hex: "#22c55e")   // green-500
            )
        case .note:
            return CalloutTypeColors(
                outerLight: NSColor(hex: "#e5e7eb"),  // gray-200
                outerDark:  NSColor(hex: "#1f2937"),  // gray-800
                labelLight: NSColor(hex: "#4b5563"),  // gray-600
                labelDark:  NSColor(hex: "#9ca3af")   // gray-400
            )
        case .important:
            return CalloutTypeColors(
                outerLight: NSColor(hex: "#fecaca"),  // red-200
                outerDark:  NSColor(hex: "#450a0a"),  // red-950
                labelLight: NSColor(hex: "#dc2626"),  // red-600
                labelDark:  NSColor(hex: "#ef4444")   // red-500
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
