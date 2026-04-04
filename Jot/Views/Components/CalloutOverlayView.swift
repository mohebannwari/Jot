//
//  CalloutOverlayView.swift
//  Jot
//
//  Overlay NSView rendering a callout block inside the text editor.
//  Structure: asymmetric rounded body (Figma node 2704:5189) plus a full-height
//  left accent rail (2704:5191) with type icon, label, and chevron.
//  Supersedes prior floating top capsule (legacy Figma 2448:7886).
//

import AppKit
import QuartzCore

final class CalloutOverlayView: NSView {

    static let minWidth: CGFloat = 400

    /// Single line height at Label-2 / 15pt Medium (Figma 2704:5190).
    private static let singleLineHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        return ceil(font.ascender - font.descender + font.leading)
    }()

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

    // -- Figma node 2704:5188 geometry ----------------------------------------
    /// Main body padding (2704:5189): 16 on all sides; text starts after rail + this gap.
    private let blockPadding: CGFloat = 16
    /// Space between accent rail trailing edge and body text (content inset).
    private let contentGapAfterRail: CGFloat = 16

    /// Body corner radii — topLeading, topTrailing, bottomTrailing, bottomLeading (layer / CG coords).
    private let bodyRadii = _CornerRadii(topLeading: 4, topTrailing: 16, bottomTrailing: 16, bottomLeading: 16)
    /// Accent rail corner radii (2704:5191).
    private let railRadii = _CornerRadii(topLeading: 16, topTrailing: 32, bottomTrailing: 32, bottomLeading: 4)

    private let railPaddingLeading: CGFloat = 12   // sm
    private let railPaddingTrailing: CGFloat = 4   // xs2
    private let railPaddingVertical: CGFloat = 4   // xs2
    private let labelHorizontalPadding: CGFloat = 4 // Text Label wrapper px in Figma
    private let iconSize: CGFloat = 18
    private let chevronSize: CGFloat = 18

    // -- Subviews -------------------------------------------------------------
    private let blockView = NSView()
    private let blockMaskLayer = CAShapeLayer()
    private let accentRailView = _AccentRailButton()
    private let railMaskLayer = CAShapeLayer()
    private let iconView = NSImageView()
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
        tf.font = .systemFont(ofSize: 15, weight: .medium)
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
        layer?.masksToBounds = false

        blockView.wantsLayer = true
        blockView.layer?.masksToBounds = true
        blockView.layer?.cornerRadius = 0
        blockMaskLayer.fillColor = NSColor.black.cgColor
        blockView.layer?.mask = blockMaskLayer
        addSubview(blockView)

        blockView.addSubview(textField)
        textField.delegate = self

        accentRailView.wantsLayer = true
        accentRailView.layer?.masksToBounds = true
        accentRailView.layer?.cornerRadius = 0
        railMaskLayer.fillColor = NSColor.black.cgColor
        accentRailView.layer?.mask = railMaskLayer
        accentRailView.onActivate = { [weak self] in self?.showTypePicker() }
        addSubview(accentRailView)
        accentRailView.addSubview(iconView)
        accentRailView.addSubview(chipLabel)
        accentRailView.addSubview(chevronView)

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

        blockView.layer?.backgroundColor = isDark ? colors.blockDark.cgColor : colors.blockLight.cgColor
        accentRailView.layer?.backgroundColor = isDark ? colors.pillDark.cgColor : colors.pillLight.cgColor

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

        textField.font = .systemFont(ofSize: 15, weight: .medium)
        // Semantic secondary / placeholder — catalog tokens adapt light & dark (AGENTS.md).
        let bodyColor = NSColor(named: "SecondaryTextColor") ?? .secondaryLabelColor
        textField.textColor = bodyColor

        let placeholderColor = NSColor(named: "SettingsPlaceholderTextColor") ?? .placeholderTextColor
        textField.placeholderAttributedString = NSAttributedString(
            string: "Type callout content...",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: placeholderColor,
                .kern: NSNumber(value: -0.5)
            ]
        )

        _ = isDark // appearance-driven redraw if we add type-specific text colors later
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

        let H = bounds.height
        let W = bounds.width

        chipLabel.sizeToFit()
        let labelW = ceil(chipLabel.frame.width) + 1
        let labelH = ceil(chipLabel.frame.height)
        let railW = Self.railWidth(labelWidth: labelW)

        blockView.frame = CGRect(x: 0, y: 0, width: W, height: H)
        blockMaskLayer.frame = blockView.bounds
        blockMaskLayer.path = Self.cgPathUnevenRoundedRect(
            bounds: blockView.bounds,
            radii: bodyRadii
        )

        let textLeading = railW + contentGapAfterRail
        let tfW = max(W - textLeading - blockPadding, 40)
        let tfH = max(H - blockPadding * 2, 20)
        textField.frame = CGRect(x: textLeading, y: blockPadding, width: tfW, height: tfH)

        accentRailView.frame = CGRect(x: 0, y: 0, width: railW, height: H)
        railMaskLayer.frame = accentRailView.bounds
        railMaskLayer.path = Self.cgPathUnevenRoundedRect(
            bounds: accentRailView.bounds,
            radii: railRadii
        )

        let rowH = iconSize
        let iconY = (H - rowH) / 2
        iconView.frame = CGRect(x: railPaddingLeading, y: iconY, width: iconSize, height: iconSize)

        let labelX = railPaddingLeading + iconSize + labelHorizontalPadding
        let labelY = (H - labelH) / 2
        chipLabel.frame = CGRect(x: labelX, y: labelY, width: labelW, height: labelH)

        let chevX = labelX + labelW + labelHorizontalPadding
        let chevY = (H - chevronSize) / 2
        chevronView.frame = CGRect(x: chevX, y: chevY, width: chevronSize, height: chevronSize)

        resizeHandle.frame = CGRect(
            x: W - Self.handleWidth / 2,
            y: 0,
            width: Self.handleWidth,
            height: H
        )
    }

    // MARK: - Cursor

    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        guard resizeHandle.frame.contains(local) else { return nil }
        return NSCursor.compatFrameResize(position: "right")
    }

    // MARK: - Height Calculation

    static func heightForData(_ data: CalloutData, width: CGFloat) -> CGFloat {
        let vPad: CGFloat = 16
        let trailPad: CGFloat = 16
        let rw = railWidthForType(data.type)
        let textLeading = rw + 16
        let tw = max(width - textLeading - trailPad, 40)
        let cellInset: CGFloat = 4
        let text = data.content.isEmpty ? "A" : data.content
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .kern: -0.5
        ]
        let rect = NSAttributedString(string: text, attributes: bodyAttrs).boundingRect(
            with: CGSize(width: tw, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return vPad + max(ceil(rect.height) + cellInset, 20) + vPad
    }

    /// Width of the left rail for a given type label string width.
    private static func railWidth(labelWidth: CGFloat) -> CGFloat {
        railPaddingLeading + 18 + labelHorizontalPaddingStatic + labelWidth
            + labelHorizontalPaddingStatic + 18 + railPaddingTrailingStatic
    }

    private static let labelHorizontalPaddingStatic: CGFloat = 4
    private static let railPaddingLeading: CGFloat = 12
    private static let railPaddingTrailingStatic: CGFloat = 4

    private static func railWidthForType(_ type: CalloutData.CalloutType) -> CGFloat {
        let label = type.rawValue.capitalized
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .kern: -0.2
        ]
        let w = ceil((label as NSString).size(withAttributes: attrs).width) + 1
        return railWidth(labelWidth: w)
    }

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
        let anchorPoint = CGPoint(x: accentRailView.frame.midX, y: accentRailView.frame.maxY)
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

    // MARK: - Uneven rounded rect (CG, origin bottom-left, y increasing upward)

    private struct _CornerRadii {
        var topLeading: CGFloat
        var topTrailing: CGFloat
        var bottomTrailing: CGFloat
        var bottomLeading: CGFloat
    }

    /// Rounded rectangle path for `bounds` using standard Core Graphics coordinates (layer space).
    private static func cgPathUnevenRoundedRect(bounds b: CGRect, radii r: _CornerRadii) -> CGPath {
        let x = b.minX
        let y = b.minY
        let w = b.width
        let h = b.height
        let tl = min(r.topLeading, w / 2, h / 2)
        let tr = min(r.topTrailing, w / 2, h / 2)
        let br = min(r.bottomTrailing, w / 2, h / 2)
        let bl = min(r.bottomLeading, w / 2, h / 2)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: x + bl, y: y))
        path.addLine(to: CGPoint(x: x + w - br, y: y))
        path.addArc(
            center: CGPoint(x: x + w - br, y: y + br),
            radius: br,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: x + w, y: y + h - tr))
        path.addArc(
            center: CGPoint(x: x + w - tr, y: y + h - tr),
            radius: tr,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: x + tl, y: y + h))
        path.addArc(
            center: CGPoint(x: x + tl, y: y + h - tl),
            radius: tl,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: x, y: y + bl))
        path.addArc(
            center: CGPoint(x: x + bl, y: y + bl),
            radius: bl,
            startAngle: .pi,
            endAngle: -.pi / 2,
            clockwise: false
        )
        path.closeSubpath()
        return path
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
        addCursorRect(bounds, cursor: NSCursor.compatFrameResize(position: "right"))
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

// MARK: - Accent rail (type picker)

private final class _AccentRailButton: NSView {

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
    let blockLight: NSColor
    let blockDark:  NSColor
    let pillLight:  NSColor
    let pillDark:   NSColor

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
                blockLight: NSColor(hex: "#BFDBFE"),
                blockDark:  NSColor(hex: "#172554"),
                pillColor:  NSColor(hex: "#2563EB")
            )
        case .warning:
            return CalloutTypeColors(
                blockLight: NSColor(hex: "#FEF08A"),
                blockDark:  NSColor(hex: "#422006"),
                pillColor:  NSColor(hex: "#CA8A04")
            )
        case .tip:
            return CalloutTypeColors(
                blockLight: NSColor(hex: "#BBF7D0"),
                blockDark:  NSColor(hex: "#052E16"),
                pillColor:  NSColor(hex: "#16A34A")
            )
        case .note:
            return CalloutTypeColors(
                blockLight: NSColor(hex: "#E9D5FF"),
                blockDark:  NSColor(hex: "#3B0764"),
                pillLight:  NSColor(hex: "#6B21A8"),
                pillDark:   NSColor(hex: "#7E22CE")
            )
        case .important:
            return CalloutTypeColors(
                blockLight: NSColor(hex: "#FECACA"),
                blockDark:  NSColor(hex: "#450A0A"),
                pillColor:  NSColor(hex: "#DC2626")
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
