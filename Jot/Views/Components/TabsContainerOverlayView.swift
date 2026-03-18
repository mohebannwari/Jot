//
//  TabsContainerOverlayView.swift
//  Jot
//
//  Overlay NSView that renders a tabs container inside the text editor.
//  Figma spec: outer border-only container 16px radius, 2px padding;
//  tabs row with chips + dividers + plus button;
//  inner content body white/dark bg, 14px concentric radius, 16/12 padding.
//

import AppKit

// MARK: - TabsContainerOverlayView

final class TabsContainerOverlayView: NSView {

    // MARK: - Constants

    static  let minWidth:       CGFloat = 400
    var currentContainerWidth:  CGFloat = 0

    private static let outerPad:      CGFloat = 2
    private static let tabsRowHeight: CGFloat = 48    // 8 + 32 + 8
    private static let tabsContentGap: CGFloat = 0
    private static let handleWidth:   CGFloat = 12

    private let outerRadius:   CGFloat = 16
    private let innerRadius:   CGFloat = 14    // concentric: 16 − 2
    private let contentPadH:   CGFloat = 16
    private let contentPadV:   CGFloat = 12
    private let tabChipCorner: CGFloat = 12
    private let tabChipPadH:   CGFloat = 12
    private let tabChipPadV:   CGFloat = 8
    private let tabsRowPad:    CGFloat = 8     // symmetric 8px all sides
    private let tabsRowGap:    CGFloat = 0
    private let dividerW:      CGFloat = 2
    private let dividerH:      CGFloat = 10
    private let plusSize:       CGFloat = 32
    private let plusIconSz:    CGFloat = 18

    // MARK: - Data

    var tabsData: TabsContainerData {
        didSet { rebuildTabsRow(); updateContentText() }
    }

    weak var parentTextView: NSTextView?
    var onDataChanged:  ((TabsContainerData) -> Void)?
    var onDeleteTabs:   (() -> Void)?
    var onWidthChanged: ((CGFloat) -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?

    // MARK: - Subviews

    private let tabsRowView  = _FlippedContainerView()
    private let contentBody  = _FlippedContainerView()
    private let contentTextView: NSTextView = {
        let tv = NSTextView()
        tv.isEditable          = true
        tv.isSelectable        = true
        tv.allowsUndo          = true
        tv.drawsBackground     = false
        tv.backgroundColor     = .clear
        tv.isRichText          = false
        tv.isAutomaticQuoteSubstitutionEnabled  = false
        tv.isAutomaticDashSubstitutionEnabled   = false
        tv.isAutomaticTextReplacementEnabled    = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset  = NSSize(width: 0, height: 0)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable   = true
        tv.maxSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.focusRingType = .none
        return tv
    }()

    private let resizeHandleRight  = _TabsResizeHandle(direction: .right)
    private let resizeHandleBottom = _TabsResizeHandle(direction: .bottom)

    private var tabChips: [_TabChipView] = []
    private var tabDividers: [(view: NSView, afterIndex: Int)] = []
    private var renameIndex: Int?

    override var isFlipped: Bool { true }

    // MARK: - Init

    init(tabsData: TabsContainerData) {
        self.tabsData = tabsData
        super.init(frame: CGRect(origin: .zero,
                                 size: CGSize(width: Self.minWidth,
                                              height: Self.totalHeight(for: tabsData))))
        setupViews()
        rebuildTabsRow()
        updateContentText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Total Height

    static func totalHeight(for data: TabsContainerData) -> CGFloat {
        outerPad + tabsRowHeight + tabsContentGap + data.containerHeight + outerPad
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius  = outerRadius
        layer?.cornerCurve   = .continuous
        layer?.masksToBounds = false

        // Tabs row
        tabsRowView.wantsLayer = true
        addSubview(tabsRowView)

        // Content body — all 4 corners rounded
        contentBody.wantsLayer = true
        contentBody.layer?.cornerRadius  = innerRadius
        contentBody.layer?.cornerCurve   = .continuous
        contentBody.layer?.masksToBounds = true
        addSubview(contentBody)

        contentBody.addSubview(contentTextView)

        // Resize handles
        resizeHandleRight.onDrag = { [weak self] newWidth in
            self?.handleResizeWidth(to: newWidth)
        }
        resizeHandleBottom.onDrag = { [weak self] newHeight in
            self?.handleResizeHeight(to: newHeight)
        }
        addSubview(resizeHandleRight)
        addSubview(resizeHandleBottom)

        contentTextView.delegate = self
        updateColors()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        needsDisplay = true  // redraw content fill when frame changes

        let W  = bounds.width
        let op = Self.outerPad
        let trh = Self.tabsRowHeight

        // Tabs row
        tabsRowView.frame = CGRect(x: op, y: op, width: W - 2 * op, height: trh)

        // Content body (4px gap below tabs row)
        let gap = Self.tabsContentGap
        let bodyH = max(bounds.height - op - trh - gap - op, 20)
        contentBody.frame = CGRect(x: op, y: op + trh + gap, width: W - 2 * op, height: bodyH)

        // Content text view
        let txW = max(contentBody.bounds.width - 2 * contentPadH, 40)
        let txH = max(contentBody.bounds.height - 2 * contentPadV, 20)
        contentTextView.frame = CGRect(x: contentPadH, y: contentPadV, width: txW, height: txH)
        contentTextView.minSize = CGSize(width: txW, height: txH)
        contentTextView.textContainer?.containerSize = CGSize(width: txW, height: CGFloat.greatestFiniteMagnitude)

        // Resize handles
        resizeHandleRight.frame = CGRect(
            x: W - Self.handleWidth / 2, y: 0,
            width: Self.handleWidth, height: bounds.height
        )
        resizeHandleBottom.frame = CGRect(
            x: 0, y: bounds.height - Self.handleWidth / 2,
            width: W, height: Self.handleWidth
        )

    }

    // MARK: - Tabs Row Rebuild

    private func rebuildTabsRow() {
        tabsRowView.subviews.forEach { $0.removeFromSuperview() }
        tabChips.removeAll()
        tabDividers.removeAll()

        var x: CGFloat = tabsRowPad
        let chipH = tabChipPadV * 2 + 16  // 8 + 16 lineHeight + 8 = 32
        let chipY = round((Self.tabsRowHeight - chipH) / 2)

        for (i, pane) in tabsData.panes.enumerated() {
            let chip = _TabChipView(
                label: pane.name,
                isActive: i == tabsData.activeIndex,
                isDark: isDarkMode,
                cornerRadius: chipH / 2,  // pill
                padH: tabChipPadH,
                padV: tabChipPadV
            )

            chip.onClick = { [weak self] in self?.selectTab(at: i) }
            chip.onDoubleClick = { [weak self] in self?.beginRename(at: i) }
            chip.onRightClick = { [weak self] event in self?.showTabContextMenu(at: i, event: event) }
            chip.onLiveResize = { [weak self] in self?.relayoutChips() }

            let chipW = chip.fittingSize.width
            chip.frame = CGRect(x: x, y: chipY, width: chipW, height: chipH)

            tabsRowView.addSubview(chip)
            tabChips.append(chip)
            x += chipW

            // Divider -- only between two inactive tabs
            let nextIdx = i + 1
            if nextIdx < tabsData.panes.count {
                if i != tabsData.activeIndex && nextIdx != tabsData.activeIndex {
                    let divider = NSView(frame: CGRect(
                        x: x + tabsRowGap / 2 - dividerW / 2,
                        y: chipY + (chipH - dividerH) / 2,
                        width: dividerW, height: dividerH))
                    divider.wantsLayer = true
                    divider.layer?.cornerRadius = dividerW / 2
                    let dark = isDarkMode
                    let divColor = dark
                        ? NSColor(srgbRed: 168/255, green: 162/255, blue: 158/255, alpha: 1)  // #A8A29E
                        : NSColor(srgbRed: 68/255, green: 64/255, blue: 60/255, alpha: 1)     // #44403C
                    divider.layer?.backgroundColor = divColor.cgColor
                    tabsRowView.addSubview(divider)
                    tabDividers.append((view: divider, afterIndex: i))
                }
                x += tabsRowGap
            } else {
                x += tabsRowGap
            }
        }

        // Plus button — far right
        let plusBtn = _TabsPlusButton(size: plusSize, iconSize: plusIconSz)
        let plusX = tabsRowView.bounds.width - tabsRowPad - plusSize
        plusBtn.frame = CGRect(x: plusX, y: chipY + (chipH - plusSize) / 2, width: plusSize, height: plusSize)
        plusBtn.onClick = { [weak self] in self?.addNewTab() }
        tabsRowView.addSubview(plusBtn)
    }

    /// Reposition existing chips and dividers without recreating them (used during live rename)
    private func relayoutChips() {
        let chipH = tabChipPadV * 2 + 16
        let chipY = round((Self.tabsRowHeight - chipH) / 2)
        var x: CGFloat = tabsRowPad

        for (i, chip) in tabChips.enumerated() {
            var f = chip.frame
            f.origin.x = x
            f.origin.y = chipY
            chip.frame = f
            x += f.width

            // Reposition divider that sits after this chip (if any)
            if let divEntry = tabDividers.first(where: { $0.afterIndex == i }) {
                var df = divEntry.view.frame
                df.origin.x = x + tabsRowGap / 2 - dividerW / 2
                df.origin.y = chipY + (chipH - dividerH) / 2
                divEntry.view.frame = df
            }

            x += tabsRowGap
        }
    }

    // MARK: - Tab Actions

    private func selectTab(at index: Int) {
        guard index != tabsData.activeIndex else { return }
        // Save current content
        tabsData.panes[tabsData.activeIndex].content = contentTextView.string
        tabsData.activeIndex = index
        onDataChanged?(tabsData)
    }

    private func addNewTab() {
        tabsData.panes[tabsData.activeIndex].content = contentTextView.string
        tabsData.addTab()
        onDataChanged?(tabsData)
    }

    private func beginRename(at index: Int) {
        guard tabChips.indices.contains(index) else { return }
        // Tell the chip to enter inline edit mode
        renameIndex = index
        tabChips[index].beginEditing { [weak self] newName in
            self?.finishRename(at: index, newName: newName)
        }
    }

    private func finishRename(at index: Int, newName: String?) {
        renameIndex = nil
        guard let name = newName else { return }  // cancelled
        tabsData.renameTab(at: index, to: name)
        onDataChanged?(tabsData)
    }

    private func showTabContextMenu(at index: Int, event: NSEvent) {
        let menu = NSMenu()
        let renameItem = NSMenuItem(title: "Rename", action: #selector(contextMenuRename(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = index
        menu.addItem(renameItem)

        if tabsData.panes.count > 1 {
            let deleteItem = NSMenuItem(title: "Delete Tab", action: #selector(contextMenuDeleteTab(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = index
            menu.addItem(deleteItem)
        }

        menu.addItem(.separator())

        let deleteBlock = NSMenuItem(title: "Delete Tabs Block", action: #selector(contextMenuDeleteBlock), keyEquivalent: "")
        deleteBlock.target = self
        menu.addItem(deleteBlock)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextMenuRename(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        beginRename(at: index)
    }

    @objc private func contextMenuDeleteTab(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        tabsData.panes[tabsData.activeIndex].content = contentTextView.string
        tabsData.removeTab(at: index)
        onDataChanged?(tabsData)
    }

    @objc private func contextMenuDeleteBlock() {
        onDeleteTabs?()
    }

    // MARK: - Content

    private func updateContentText() {
        let idx = tabsData.activeIndex
        guard tabsData.panes.indices.contains(idx) else { return }
        contentTextView.string = tabsData.panes[idx].content
        contentTextView.font = NSFont.systemFont(ofSize: 16, weight: .medium)
    }

    // MARK: - Resize

    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        if resizeHandleRight.frame.contains(local) {
            return NSCursor.frameResize(position: .right, directions: .all)
        }
        if resizeHandleBottom.frame.contains(local) {
            return NSCursor.frameResize(position: .bottom, directions: .all)
        }
        return nil
    }

    private func handleResizeWidth(to newWidth: CGFloat) {
        let effectiveMax = currentContainerWidth > 0 ? currentContainerWidth : CGFloat.greatestFiniteMagnitude
        let effectiveMin = min(Self.minWidth, effectiveMax)
        let clamped = floor(max(effectiveMin, min(effectiveMax, newWidth)))
        var f = frame
        f.size.width = clamped
        frame = f
        onWidthChanged?(clamped)
    }

    private func handleResizeHeight(to newHeight: CGFloat) {
        let bodyH = newHeight - Self.outerPad - Self.tabsRowHeight - Self.tabsContentGap - Self.outerPad
        let clamped = max(TabsContainerData.minHeight, min(TabsContainerData.maxHeight, bodyH))
        tabsData.containerHeight = clamped
        onHeightChanged?(clamped)
    }

    // MARK: - Colors

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// bg/blocks: white (light) / #0C0A09 (dark) — from Figma variable tokens
    private static func blocksColor(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 12/255, green: 10/255, blue: 9/255, alpha: 1)    // #0C0A09
            : NSColor.white
    }

    /// border/default: #D6D3D1 (light) / #44403C (dark) — from Figma variable tokens
    private static func borderColor(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 68/255, green: 64/255, blue: 60/255, alpha: 1)   // #44403C
            : NSColor(srgbRed: 214/255, green: 211/255, blue: 209/255, alpha: 1) // #D6D3D1
    }

    private func updateColors() {
        let dark = isDarkMode

        // Content body bg — bg/blocks
        contentBody.layer?.backgroundColor = Self.blocksColor(isDark: dark).cgColor

        // Border — border/default
        layer?.borderWidth = 1.0
        layer?.borderColor = Self.borderColor(isDark: dark).cgColor

        // Text color
        contentTextView.textColor = NSColor.labelColor

        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Only fill the content body region (below the tabs row) to hide
        // any underlying NSTextView text. The tabs row area is left transparent
        // so the canvas background shows through -- matching the Figma spec
        // of a border-only outer container.
        let op = Self.outerPad
        let trh = Self.tabsRowHeight
        let gap = Self.tabsContentGap
        let contentRect = NSRect(
            x: op, y: op + trh + gap,
            width: bounds.width - 2 * op,
            height: bounds.height - op - trh - gap - op
        )
        Self.blocksColor(isDark: isDarkMode).setFill()
        NSBezierPath(roundedRect: contentRect, xRadius: innerRadius, yRadius: innerRadius).fill()
    }

    // MARK: - Appearance Change

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        rebuildTabsRow()
    }
}

// MARK: - NSTextViewDelegate

extension TabsContainerOverlayView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        let idx = tabsData.activeIndex
        guard tabsData.panes.indices.contains(idx) else { return }
        tabsData.panes[idx].content = contentTextView.string
        onDataChanged?(tabsData)
    }
}


// MARK: - Private Helper Views

private final class _FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Tab Chip View

private final class _TabChipView: NSView, NSTextFieldDelegate {

    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onLiveResize: (() -> Void)?

    private let label: NSTextField
    private let isActive: Bool
    private let padH: CGFloat
    private let padV: CGFloat
    private var isEditing = false
    private var onEditComplete: ((String?) -> Void)?

    override var isFlipped: Bool { true }

    init(label text: String, isActive: Bool, isDark: Bool, cornerRadius: CGFloat, padH: CGFloat, padV: CGFloat) {
        self.isActive = isActive
        self.padH = padH
        self.padV = padV

        self.label = NSTextField(labelWithString: text)
        self.label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        // Active: text/primary (#1a1a1a / white)
        // Inactive: text/placeholder (rgba(26,26,26,0.7) / rgba(255,255,255,0.7))
        self.label.textColor = isActive
            ? (isDark ? NSColor.white : NSColor(srgbRed: 26/255, green: 26/255, blue: 26/255, alpha: 1))
            : (isDark ? NSColor(white: 1.0, alpha: 0.7) : NSColor(srgbRed: 26/255, green: 26/255, blue: 26/255, alpha: 0.7))
        self.label.isBordered = false
        self.label.drawsBackground = false
        self.label.focusRingType = .none

        super.init(frame: .zero)

        self.label.delegate = self
        wantsLayer = true

        // Pill shape — all corners rounded, continuous smoothing
        layer?.cornerRadius = (padV * 2 + ceil(self.label.frame.height)) / 2
        layer?.cornerCurve = .continuous

        addSubview(self.label)
        updateChipColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChipColor()
    }

    private func updateChipColor() {
        if isActive {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer?.backgroundColor = (dark
                ? NSColor(srgbRed: 12/255, green: 10/255, blue: 9/255, alpha: 1)
                : NSColor.white).cgColor
        } else {
            layer?.backgroundColor = CGColor.clear
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        label.sizeToFit()
        return NSSize(width: padH * 2 + ceil(label.frame.width) + 8,
                      height: padV * 2 + ceil(label.frame.height))
    }

    override func layout() {
        super.layout()
        // Pill corner radius = half height
        layer?.cornerRadius = bounds.height / 2

        label.sizeToFit()
        let lw = ceil(label.frame.width)
        let lh = ceil(label.frame.height)
        let ly = round((bounds.height - lh) / 2)
        if isEditing {
            label.frame = CGRect(x: padH, y: ly,
                                 width: bounds.width - 2 * padH, height: lh)
        } else {
            let lx = round((bounds.width - lw) / 2)
            label.frame = CGRect(x: lx, y: ly, width: lw, height: lh)
        }
    }

    // MARK: - Inline Editing

    func beginEditing(completion: @escaping (String?) -> Void) {
        onEditComplete = completion
        isEditing = true

        // Make the label editable in-place
        label.isEditable = true
        label.isSelectable = true
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = .center
        needsLayout = true

        // Focus and select all
        window?.makeFirstResponder(label)
        label.currentEditor()?.selectAll(nil)
    }

    private func endEditing(commit: Bool) {
        guard isEditing else { return }
        isEditing = false

        let newName = commit ? label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : nil

        // Restore label to non-editable
        label.isEditable = false
        label.isSelectable = false
        label.alignment = .left
        needsLayout = true

        onEditComplete?(newName)
        onEditComplete = nil
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard isEditing else { return }
        let text = label.stringValue as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: label.font ?? NSFont.systemFont(ofSize: 13, weight: .medium)]
        let textW = ceil(text.size(withAttributes: attrs).width)
        let newW = padH * 2 + textW + 8
        var f = frame
        f.size.width = max(newW, padH * 2 + 20)
        frame = f
        needsLayout = true
        onLiveResize?()
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.endEditing(commit: true)
        }
        return true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(nil)  // triggers textShouldEndEditing -> commit
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing(commit: false)
            return true
        }
        return false
    }

    func setLabelHidden(_ hidden: Bool) {
        label.isHidden = hidden
    }

    override func mouseDown(with event: NSEvent) {
        if isEditing { return }  // let the text field handle clicks during editing
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if isEditing { return }
        onRightClick?(event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isEditing ? .iBeam : .pointingHand)
    }
}

// MARK: - Plus Button

private final class _TabsPlusButton: NSView {

    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(size: CGFloat, iconSize: CGFloat) {
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
        wantsLayer = true
        layer?.cornerRadius = size / 2
        layer?.masksToBounds = true

        let iconView = NSImageView(frame: CGRect(
            x: (size - iconSize) / 2,
            y: (size - iconSize) / 2,
            width: iconSize,
            height: iconSize
        ))
        let img = NSImage(named: "IconPlusSmall") ?? NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        img?.isTemplate = true
        iconView.image = img
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = NSColor(named: "IconSecondaryColor") ?? .secondaryLabelColor
        addSubview(iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Resize Handle

private final class _TabsResizeHandle: NSView {

    enum Direction { case right, bottom }

    var onDrag: ((CGFloat) -> Void)?
    let direction: Direction

    private var dragStart: CGFloat = 0
    private var dragStartDimension: CGFloat = 0

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    init(direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
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
        let cursor: NSCursor = direction == .right
            ? NSCursor.frameResize(position: .right, directions: .all)
            : NSCursor.frameResize(position: .bottom, directions: .all)
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        if direction == .right {
            dragStart = event.locationInWindow.x
            dragStartDimension = superview?.bounds.width ?? 0
        } else {
            dragStart = event.locationInWindow.y
            dragStartDimension = superview?.bounds.height ?? 0
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if direction == .right {
            let delta = event.locationInWindow.x - dragStart
            onDrag?(dragStartDimension + delta)
        } else {
            // Note: flipped coordinates — dragging down = positive screen delta but negative window delta
            let delta = dragStart - event.locationInWindow.y
            onDrag?(dragStartDimension + delta)
        }
    }

    override func mouseUp(with event: NSEvent) { }
}
