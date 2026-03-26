//
//  CardSectionOverlayView.swift
//  Jot
//
//  Overlay NSView for card section blocks in the rich text editor.
//  Cards flow horizontally with individual colors, rich text editing,
//  resize handles, drag reorder, and an always-visible plus button.
//

#if os(macOS)
import AppKit

final class CardSectionOverlayView: NSView {

    // MARK: - Constants

    static let minWidth: CGFloat = CardSectionData.minCardWidth
    var currentContainerWidth: CGFloat = 0

    private let cardRadius   = CardSectionData.cardCornerRadius    // 22
    private let cardPad      = CardSectionData.cardPadding         // 16
    private let cardBorder   = CardSectionData.cardBorderWidth     // 2
    private let cardGap      = CardSectionData.cardGap             // 12
    private let plusBtnWidth  = CardSectionData.plusButtonWidth     // 28
    private let plusIconSize: CGFloat = 18
    private let resizeZone:  CGFloat = 20
    private let dashLength:  CGFloat = 6
    private let dashGap:     CGFloat = 4
    private let dragHandleHeight: CGFloat = 24  // drag handle strip at top of card
    private let gripDotSize: CGFloat = 2.5
    private let gripDotGap:  CGFloat = 2
    private let snapThreshold: CGFloat = 6  // magnetic snap zone for width matching

    // MARK: - Data

    /// Guards against re-entrant syncTextViews calls during textDidChange processing.
    /// textDidChange mutates the struct which triggers didSet -> syncTextViews.
    /// Without this guard, syncTextViews can overwrite in-flight edits.
    private var isSyncingContent = false

    var cardSectionData: CardSectionData {
        didSet {
            guard !isSyncingContent else {
                needsLayout = true
                needsDisplay = true
                return
            }
            syncTextViews()
            needsLayout = true
            needsDisplay = true
        }
    }

    weak var parentTextView: NSTextView?
    var editorInstanceID: UUID?
    private let formatter = TextFormattingManager()
    var onDataChanged:       ((CardSectionData) -> Void)?
    var onDeleteCardSection: (() -> Void)?
    var onWidthChanged:      ((CGFloat) -> Void)?
    var onHeightChanged:     ((CGFloat) -> Void)?

    // MARK: - Scroll state

    private var scrollOffset: CGFloat = 0

    private var viewportWidth: CGFloat { bounds.width }

    private var contentWidth: CGFloat { cardSectionData.contentWidth }

    var needsHorizontalScroll: Bool { contentWidth > viewportWidth + 1 }

    private var maxScrollOffset: CGFloat {
        max(0, contentWidth - viewportWidth + plusBtnWidth + cardGap)
    }

    private func clampScrollOffset() {
        scrollOffset = min(max(0, scrollOffset), maxScrollOffset)
    }

    // MARK: - Per-card layers and text views

    /// Each card has a border layer (outer, fill = border color) and a fill layer (inner, fill = card color).
    /// Using CALayer with cornerCurve = .continuous for true squircle corners.
    private var cardBorderLayers: [CALayer] = []
    private var cardFillLayers: [CALayer] = []
    private var cardScrollViews: [_CardScrollView] = []
    private var cardTextViews: [_CardTextView] = []
    private var rightHandles: [_CardResizeHandle] = []
    private var bottomHandles: [_CardResizeHandle] = []
    private var cornerHandles: [_CardResizeHandle] = []
    private var gripDotViews: [_GripDotsView] = []

    // MARK: - Drag reorder state

    enum DropTarget: Equatable {
        case betweenColumns(Int)                     // insert as new column at index
        case inColumn(column: Int, atRow: Int)       // stack at this row in column
    }

    private var dragSourceIndex: Int?
    private var dropTarget: DropTarget?
    private var dragOffset: CGPoint = .zero       // grab offset within the card
    private var dragGhostOrigin: CGPoint = .zero  // top-left of the ghost card in view coords
    private var isDragging = false

    // MARK: - Snap guide state

    /// CALayer-based snap guide bars (render above card layers).
    private lazy var widthSnapLayer: CALayer = {
        let l = CALayer()
        l.cornerRadius = 1.5
        l.isHidden = true
        return l
    }()
    private lazy var heightSnapLayer: CALayer = {
        let l = CALayer()
        l.cornerRadius = 1.5
        l.isHidden = true
        return l
    }()

    // MARK: - AI target state

    /// Stores the card text view that originated an AI request (selection capture).
    /// Used by replacement/insert handlers since focus has shifted away by the time
    /// the user clicks Replace/Accept.
    private weak var aiTargetCardTV: _CardTextView?

    // MARK: - Hover state

    private var hoveredCardIndex: Int?
    private var mouseMonitor: Any?

    // MARK: - Appearance

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    override var isFlipped: Bool { true }

    /// Expand hit testing to cover all cards and the plus button, even when they
    /// extend beyond the overlay's frame (which is clamped to container width).
    override func hitTest(_ point: NSPoint) -> NSView? {
        // First try normal hit testing (covers subviews within bounds)
        if let hit = super.hitTest(point) { return hit }
        // Expand: check if the point is within the full content area
        let localPoint = superview?.convert(point, to: self) ?? convert(point, from: superview)
        let expandedBounds = CGRect(x: -scrollOffset - cardBorder, y: -cardBorder,
                                     width: contentWidth + cardBorder * 2,
                                     height: bounds.height + cardBorder * 2)
        if expandedBounds.contains(localPoint) { return self }
        return nil
    }

    // MARK: - Init

    init(cardSectionData: CardSectionData) {
        self.cardSectionData = cardSectionData
        super.init(frame: CGRect(
            origin: .zero,
            size: CGSize(width: Self.minWidth,
                         height: Self.totalHeight(for: cardSectionData))
        ))
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(widthSnapLayer)
        layer?.addSublayer(heightSnapLayer)
        setupTrackingArea()
        syncTextViews()
        setupFormattingObserver()
    }

    private var mainTrackingArea: NSTrackingArea?

    private func setupTrackingArea() {
        mainTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self, userInfo: nil
        )
        addTrackingArea(mainTrackingArea!)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var formattingObservers: [NSObjectProtocol] = []

    private func setupFormattingObserver() {
        let nc = NotificationCenter.default

        // Helper: find focused card text view, or bail
        func focusedCardTV() -> _CardTextView? {
            cardTextViews.first { $0.window?.firstResponder == $0 }
        }

        // Tools cards don't support (block-level, attachments, etc.)
        let excludedTools: Set<EditTool> = [
            .divider, .imageUpload, .voiceRecord, .table, .callout,
            .codeBlock, .fileLink, .sticker, .tabs, .cards, .lineBreak, .link, .searchOnPage
        ]

        // 1. EditTool -- delegate to TextFormattingManager
        formattingObservers.append(nc.addObserver(forName: .applyEditTool, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = focusedCardTV() else { return }
            guard let raw = n.userInfo?["tool"] as? String, let tool = EditTool(rawValue: raw) else { return }
            guard !excludedTools.contains(tool) else { return }
            self.formatter.applyFormatting(to: tv, tool: tool)
            self.styleCardParagraphs(tv)
            self.syncCardContent(tv)
        })

        // 2. Font size
        formattingObservers.append(nc.addObserver(forName: .applyFontSize, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = focusedCardTV() else { return }
            guard let size = n.userInfo?["size"] as? CGFloat else { return }
            self.formatter.applyFontSize(size, to: tv, range: tv.selectedRange())
            self.syncCardContent(tv)
        })

        // 3. Font family
        formattingObservers.append(nc.addObserver(forName: .applyFontFamily, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = focusedCardTV() else { return }
            guard let styleRaw = n.userInfo?["style"] as? String,
                  let style = BodyFontStyle(rawValue: styleRaw) else { return }
            self.formatter.applyFontFamily(style, to: tv, range: tv.selectedRange())
            self.syncCardContent(tv)
        })

        // 4. Text color
        formattingObservers.append(nc.addObserver(forName: .applyTextColor, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = focusedCardTV() else { return }
            guard let hex = n.userInfo?["hex"] as? String else { return }
            self.formatter.applyTextColor(hex: hex, range: tv.selectedRange(), to: tv)
            self.syncCardContent(tv)
        })

        // 5. Remove text color
        formattingObservers.append(nc.addObserver(forName: .removeTextColor, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = focusedCardTV() else { return }
            self.formatter.removeTextColor(range: tv.selectedRange(), from: tv)
            self.syncCardContent(tv)
        })

        // 6. Highlight color
        formattingObservers.append(nc.addObserver(forName: .applyHighlightColor, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = focusedCardTV() else { return }
            guard let hex = n.userInfo?["hex"] as? String else { return }
            self.formatter.applyHighlight(hex: hex, range: tv.selectedRange(), to: tv)
            self.syncCardContent(tv)
        })

        // 7. Remove highlight
        formattingObservers.append(nc.addObserver(forName: .removeHighlightColor, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = focusedCardTV() else { return }
            self.formatter.removeHighlight(range: tv.selectedRange(), from: tv)
            self.syncCardContent(tv)
        })

        // 8. Todo toolbar action (dispatched separately from .applyEditTool).
        // No syncCardContent needed -- textDidChange fires synchronously inside
        // insertTodo's didChangeText() and handles serialization.
        formattingObservers.append(nc.addObserver(forName: .todoToolbarAction, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = focusedCardTV() else { return }
            self.formatter.applyFormatting(to: tv, tool: .todo)
        })

        // 9. AI: capture card selection for edit/translate.
        // Stores the originating card text view so replacement/insert can target it
        // even after focus shifts to the AI panel buttons.
        formattingObservers.append(nc.addObserver(forName: .aiEditRequestSelection, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = focusedCardTV() else { return }
            self.aiTargetCardTV = tv
            let range = tv.selectedRange()
            let text = (tv.string as NSString).substring(with: range)
            var windowRect = CGRect.zero
            if let lm = tv.layoutManager, let tc = tv.textContainer, range.length > 0 {
                let glyphRange = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
                windowRect = tv.convert(rect.offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y), to: nil)
            }
            NotificationCenter.default.post(name: .aiEditCaptureSelection, object: nil, userInfo: [
                "nsRange": range,
                "selectedText": text,
                "windowRect": windowRect,
                "cardOrigin": true
            ])
        })

        // 10. AI: apply replacement (translate / edit content).
        // Uses aiTargetCardTV instead of focusedCardTV() because focus has shifted
        // to the panel by the time the user clicks Replace.
        formattingObservers.append(nc.addObserver(forName: .aiEditApplyReplacement, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = self.aiTargetCardTV else { return }
            guard let replacement = n.userInfo?["replacement"] as? String else { return }
            let original = n.userInfo?["original"] as? String ?? ""
            if original.isEmpty {
                tv.selectAll(nil)
                tv.insertText(replacement, replacementRange: tv.selectedRange())
            } else {
                let searchRange = NSRange(location: 0, length: (tv.string as NSString).length)
                let foundRange = (tv.string as NSString).range(of: original, range: searchRange)
                if foundRange.location != NSNotFound {
                    tv.insertText(replacement, replacementRange: foundRange)
                }
            }
            self.syncCardContent(tv)
            self.aiTargetCardTV = nil
        })

        // 11. AI: insert generated text at cursor.
        formattingObservers.append(nc.addObserver(forName: .aiTextGenInsert, object: nil, queue: .main) { [weak self] n in
            guard let self = self, let tv = self.aiTargetCardTV else { return }
            guard let text = n.object as? String else { return }
            tv.insertText(text, replacementRange: tv.selectedRange())
            self.syncCardContent(tv)
            self.aiTargetCardTV = nil
        })
    }

    deinit {
        stopMouseMonitor()
        for obs in formattingObservers {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Card formatting

    /// Sync card text view rich text content back to data model via tag serialization.
    private func syncCardContent(_ tv: _CardTextView) {
        let idx = tv.cardIndex
        guard idx < cardSectionData.flatCardCount, let pos = cardSectionData.position(forFlatIndex: idx) else { return }
        cardSectionData.columns[pos.column][pos.row].content = RichTextSerializer.serializeAttributedString(tv.attributedString())
        onDataChanged?(cardSectionData)
    }

    /// Lightweight paragraph style enforcement for cards.
    private func styleCardParagraphs(_ tv: _CardTextView) {
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
                // Check if heading -- preserve heading paragraph style
                if let font = storage.attribute(.font, at: paraRange.location, effectiveRange: nil) as? NSFont,
                   RichTextSerializer.headingLevel(for: font) != nil {
                    // Heading style already set by TextFormattingManager
                } else {
                    // Preserve existing alignment
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

    // MARK: - Cursor for coordinator integration

    /// Called by the coordinator's `resizeCursorForPoint` to suppress NSTextView's I-beam cursor.
    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        for h in cornerHandles where !h.isHidden && h.frame.contains(local) {
            return NSCursor.compatFrameResize(position: "bottomRight")
        }
        for h in rightHandles where !h.isHidden && h.frame.contains(local) {
            return NSCursor.compatFrameResize(position: "right")
        }
        for h in bottomHandles where !h.isHidden && h.frame.contains(local) {
            return NSCursor.compatFrameResize(position: "bottom")
        }
        return nil
    }

    // MARK: - Resize handle sync

    private func syncResizeHandles() {
        let count = cardSectionData.flatCardCount

        // Sync right handles
        while rightHandles.count > count { rightHandles.removeLast().removeFromSuperview() }
        while rightHandles.count < count {
            let h = _CardResizeHandle(edge: .right)
            h.cardIndex = rightHandles.count
            h.onResize = { [weak self] idx, dx, _ in
                self?.handleResize(cardIndex: idx, dx: dx, dy: 0)
            }
            h.onResizeEnd = { [weak self] in self?.clearSnapGuide() }
            addSubview(h)
            rightHandles.append(h)
        }

        // Sync bottom handles
        while bottomHandles.count > count { bottomHandles.removeLast().removeFromSuperview() }
        while bottomHandles.count < count {
            let h = _CardResizeHandle(edge: .bottom)
            h.cardIndex = bottomHandles.count
            h.onResize = { [weak self] idx, _, dy in
                self?.handleResize(cardIndex: idx, dx: 0, dy: dy)
            }
            h.onResizeEnd = { [weak self] in self?.clearSnapGuide() }
            addSubview(h)
            bottomHandles.append(h)
        }

        // Sync corner handles
        while cornerHandles.count > count { cornerHandles.removeLast().removeFromSuperview() }
        while cornerHandles.count < count {
            let h = _CardResizeHandle(edge: .corner)
            h.cardIndex = cornerHandles.count
            h.onResize = { [weak self] idx, dx, dy in
                self?.handleResize(cardIndex: idx, dx: dx, dy: dy)
            }
            h.onResizeEnd = { [weak self] in self?.clearSnapGuide() }
            addSubview(h)
            cornerHandles.append(h)
        }

        // Update card indices
        for (i, h) in rightHandles.enumerated() { h.cardIndex = i }
        for (i, h) in bottomHandles.enumerated() { h.cardIndex = i }
        for (i, h) in cornerHandles.enumerated() { h.cardIndex = i }

        // Sync grip dot views
        while gripDotViews.count > count { gripDotViews.removeLast().removeFromSuperview() }
        while gripDotViews.count < count {
            let gv = _GripDotsView(dotSize: gripDotSize, dotGap: gripDotGap)
            gv.isHidden = true  // shown on hover
            addSubview(gv)
            gripDotViews.append(gv)
        }
    }

    private func handleResize(cardIndex: Int, dx: CGFloat, dy: CGFloat) {
        guard let pos = cardSectionData.position(forFlatIndex: cardIndex) else { return }
        let card = cardSectionData.columns[pos.column][pos.row]
        var widthSnapped = false
        var heightSnapped = false
        var heightSnapNeighborCol = pos.column

        // Width snap: match sibling widths in the same column
        if dx != 0 {
            var newWidth = card.width + dx
            let column = cardSectionData.columns[pos.column]
            for (row, sibling) in column.enumerated() where row != pos.row {
                if abs(newWidth - sibling.width) <= snapThreshold {
                    newWidth = sibling.width
                    widthSnapped = true
                    break
                }
            }
            cardSectionData.resizeCard(at: cardIndex, width: newWidth)
        }

        // Height snap: match bottom edges of cards in adjacent columns
        if dy != 0 {
            var newHeight = card.height + dy
            // Compute what the bottom Y would be with this new height
            var cardTopY = cardBorder
            for r in 0..<pos.row {
                cardTopY += cardSectionData.columns[pos.column][r].height + cardGap
            }
            let candidateBottomY = cardTopY + newHeight

            // Check adjacent columns for matching bottom edges
            let neighborCols = [pos.column - 1, pos.column + 1].filter { cardSectionData.columns.indices.contains($0) }
            for neighborCol in neighborCols {
                var y = cardBorder
                for neighborCard in cardSectionData.columns[neighborCol] {
                    y += neighborCard.height
                    if abs(candidateBottomY - y) <= snapThreshold {
                        newHeight = y - cardTopY
                        heightSnapped = true
                        heightSnapNeighborCol = neighborCol
                        break
                    }
                    y += cardGap
                }
                if heightSnapped { break }
            }
            cardSectionData.resizeCard(at: cardIndex, height: newHeight)
        }

        // Update width snap guide layer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let accentColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
        if widthSnapped {
            let colX = columnX(at: pos.column)
            let snappedWidth = cardSectionData.columns[pos.column][pos.row].width
            let x = viewX(colX + snappedWidth)
            let colY = cardBorder
            let colH = cardSectionData.columnHeight(at: pos.column)
            let overshoot: CGFloat = 6
            let barW: CGFloat = 3
            widthSnapLayer.frame = CGRect(x: x - barW / 2, y: colY - overshoot, width: barW, height: colH + overshoot * 2)
            widthSnapLayer.backgroundColor = accentColor
            widthSnapLayer.isHidden = false
            // Ensure on top
            widthSnapLayer.removeFromSuperlayer()
            layer?.addSublayer(widthSnapLayer)
        } else {
            widthSnapLayer.isHidden = true
        }

        // Update height snap guide layer
        if heightSnapped {
            var cardTopY = cardBorder
            for r in 0..<pos.row {
                cardTopY += cardSectionData.columns[pos.column][r].height + cardGap
            }
            let y = cardTopY + cardSectionData.columns[pos.column][pos.row].height
            let leftCol = min(pos.column, heightSnapNeighborCol)
            let rightCol = max(pos.column, heightSnapNeighborCol)
            let leftX = viewX(columnX(at: leftCol))
            let rightX = viewX(columnX(at: rightCol) + cardSectionData.columnWidth(at: rightCol))
            let overshoot: CGFloat = 6
            let barH: CGFloat = 3
            heightSnapLayer.frame = CGRect(x: leftX - overshoot, y: y - barH / 2, width: (rightX - leftX) + overshoot * 2, height: barH)
            heightSnapLayer.backgroundColor = accentColor
            heightSnapLayer.isHidden = false
            heightSnapLayer.removeFromSuperlayer()
            layer?.addSublayer(heightSnapLayer)
        } else {
            heightSnapLayer.isHidden = true
        }
        CATransaction.commit()

        onDataChanged?(cardSectionData)
        onHeightChanged?(cardSectionData.maxColumnHeight)
    }

    // MARK: - Height calculation

    static func totalHeight(for data: CardSectionData) -> CGFloat {
        data.maxColumnHeight + CardSectionData.cardBorderWidth * 2
    }

    // MARK: - Card geometry helpers

    /// Returns the x-origin of the column at the given index (in content space).
    private func columnX(at colIdx: Int) -> CGFloat {
        var x: CGFloat = 0
        for c in 0..<colIdx {
            x += cardSectionData.columnWidth(at: c) + cardGap
        }
        return x
    }

    /// Returns the rect of a card at the given flat index in content space.
    /// Uses the column/row position bridge for 2D layout.
    private func cardRect(at flatIndex: Int) -> CGRect {
        guard let pos = cardSectionData.position(forFlatIndex: flatIndex) else { return .zero }
        let x = columnX(at: pos.column)
        var y = cardBorder
        for r in 0..<pos.row {
            y += cardSectionData.columns[pos.column][r].height + cardGap
        }
        let card = cardSectionData.columns[pos.column][pos.row]
        return CGRect(x: x, y: y, width: card.width, height: card.height)
    }

    /// Returns the rect of the plus button in content space.
    private var plusButtonRect: CGRect {
        let x = columnX(at: cardSectionData.columns.count)
        return CGRect(x: x, y: cardBorder, width: plusBtnWidth, height: cardSectionData.maxColumnHeight)
    }

    /// Converts content-space x to view-space x.
    private func viewX(_ contentX: CGFloat) -> CGFloat {
        contentX - scrollOffset
    }

    /// Card index at the given point (in view coordinates), or nil.
    private func cardIndex(at point: CGPoint) -> Int? {
        let contentPoint = CGPoint(x: point.x + scrollOffset, y: point.y)
        for i in 0..<cardSectionData.flatCardCount {
            if cardRect(at: i).contains(contentPoint) { return i }
        }
        return nil
    }

    /// Returns true if the point is in a draggable area of the card (handle strip at top,
    /// or the padding margins on left/right/bottom that aren't covered by the scroll view).
    private func isInDragHandle(at point: CGPoint, cardIndex: Int) -> Bool {
        let rect = cardRect(at: cardIndex).offsetBy(dx: -scrollOffset, dy: 0)
        guard rect.contains(point) else { return false }
        // Only the top handle strip initiates drag
        return point.y < rect.minY + dragHandleHeight
    }

    // MARK: - Text view, layer, and resize handle management

    private func syncTextViews() {
        let allCards = cardSectionData.flatCards
        let count = allCards.count
        let dark = isDarkMode

        // ── Sync card layers (remove excess, add new as border+fill pairs) ──
        while cardBorderLayers.count > count {
            cardBorderLayers.removeLast().removeFromSuperlayer()
            cardFillLayers.removeLast().removeFromSuperlayer()
        }
        while cardBorderLayers.count < count {
            let bl = CALayer()
            bl.cornerCurve = .continuous
            let fl = CALayer()
            fl.cornerCurve = .continuous
            // addSublayer appends at the top — border first, then fill directly above it
            layer?.addSublayer(bl)
            layer?.addSublayer(fl)
            cardBorderLayers.append(bl)
            cardFillLayers.append(fl)
        }
        // ── Sync scroll views + text views ──
        while cardScrollViews.count > count {
            cardScrollViews.removeLast().removeFromSuperview()
            cardTextViews.removeLast()
        }
        while cardScrollViews.count < count {
            // Build text system with custom layout manager for squiggly strikethrough
            let storage = NSTextStorage()
            let layoutManager = _CardLayoutManager()
            storage.addLayoutManager(layoutManager)
            let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            container.widthTracksTextView = true
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)

            let tv = _CardTextView(frame: .zero, textContainer: container)
            tv.overlayView = self
            tv.isEditable = true
            tv.isSelectable = true
            tv.allowsUndo = true
            tv.drawsBackground = false
            tv.backgroundColor = .clear
            tv.isRichText = true
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.textContainerInset = NSSize(width: 0, height: 0)
            tv.isHorizontallyResizable = false
            tv.isVerticallyResizable = true
            tv.maxSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            tv.focusRingType = .none
            tv.font = FontManager.bodyNS(size: ThemeManager.currentBodyFontSize(), weight: .regular)
            tv.textColor = NSColor(named: "PrimaryTextColor") ?? .labelColor
            tv.delegate = self

            let sv = _CardScrollView()
            sv.overlayView = self
            sv.documentView = tv
            sv.hasVerticalScroller = true
            sv.hasHorizontalScroller = false
            sv.autohidesScrollers = true
            sv.drawsBackground = false
            sv.backgroundColor = .clear
            sv.scrollerStyle = .overlay
            sv.verticalScroller?.controlSize = .mini
            sv.scrollerKnobStyle = .default
            sv.contentView.drawsBackground = false

            addSubview(sv)
            cardScrollViews.append(sv)
            cardTextViews.append(tv)
        }

        // ── Update layer colors + text content ──
        for i in 0..<count {
            let card = allCards[i]
            // Border layer
            cardBorderLayers[i].cornerRadius = cardRadius + cardBorder
            cardBorderLayers[i].backgroundColor = card.color.borderColor(isDark: dark).cgColor
            // Fill layer
            cardFillLayers[i].cornerRadius = cardRadius
            cardFillLayers[i].backgroundColor = card.color.fillColor(isDark: dark).cgColor
            // Text view
            let tv = cardTextViews[i]
            tv.cardIndex = i
            // Deserialize rich text from tag format
            let currentSerialized = RichTextSerializer.serializeAttributedString(tv.attributedString())
            if currentSerialized != card.content {
                let attrString = RichTextSerializer.deserializeToAttributedString(card.content)
                tv.textStorage?.setAttributedString(attrString)
            }
            // Set typing attributes for new text (don't override existing rich text)
            tv.typingAttributes = RichTextSerializer.baseTypingAttributes()
        }

        syncResizeHandles()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let layoutCards = cardSectionData.flatCards
        for i in 0..<layoutCards.count {
            let card = layoutCards[i]
            let rect = cardRect(at: i).offsetBy(dx: -scrollOffset, dy: 0)
            let offscreen = (rect.maxX < 0) || (rect.minX > viewportWidth)

            // Border layer (expanded by cardBorder for outside border)
            if i < cardBorderLayers.count {
                cardBorderLayers[i].frame = rect.insetBy(dx: -cardBorder, dy: -cardBorder)
            }
            // Fill layer (sits inside the border layer)
            if i < cardFillLayers.count {
                cardFillLayers[i].frame = rect
            }
            // Scroll view wrapping the text view (below drag handle, inset by padding)
            if i < cardScrollViews.count {
                let sv = cardScrollViews[i]
                let x = rect.origin.x + cardPad
                let y = rect.origin.y + dragHandleHeight
                let w = card.width - cardPad * 2
                let h = card.height - dragHandleHeight - cardPad
                sv.frame = CGRect(x: x, y: y, width: max(0, w), height: max(0, h))
                sv.isHidden = offscreen
                // Ensure text view width tracks the scroll view
                if i < cardTextViews.count {
                    let tv = cardTextViews[i]
                    tv.minSize = NSSize(width: max(1, w), height: 0)
                    tv.maxSize = NSSize(width: max(1, w), height: CGFloat.greatestFiniteMagnitude)
                    tv.textContainer?.containerSize = CGSize(width: max(1, w), height: CGFloat.greatestFiniteMagnitude)
                    tv.frame.size.width = max(1, w)
                }
            }

            // Resize handles (straddling card edges)
            let hz = resizeZone
            if i < rightHandles.count {
                rightHandles[i].frame = CGRect(x: rect.maxX - hz / 2, y: rect.minY,
                                                width: hz, height: rect.height - hz)
                rightHandles[i].isHidden = offscreen
            }
            if i < bottomHandles.count {
                bottomHandles[i].frame = CGRect(x: rect.minX, y: rect.maxY - hz / 2,
                                                 width: rect.width - hz, height: hz)
                bottomHandles[i].isHidden = offscreen
            }
            if i < cornerHandles.count {
                cornerHandles[i].frame = CGRect(x: rect.maxX - hz, y: rect.maxY - hz,
                                                 width: hz, height: hz)
                cornerHandles[i].isHidden = offscreen
            }

            // Grip dots view (centered in drag handle zone)
            if i < gripDotViews.count {
                let gv = gripDotViews[i]
                let gvW: CGFloat = 30
                let gvH: CGFloat = 18
                gv.frame = CGRect(x: rect.midX - gvW / 2,
                                   y: rect.minY + (dragHandleHeight - gvH) / 2,
                                   width: gvW, height: gvH)
                // Show only on hover (unless offscreen or drag source)
                let isHovered = hoveredCardIndex == i
                let isDragSource = isDragging && dragSourceIndex == i
                gv.isHidden = offscreen || !isHovered || isDragSource
            }
        }

        CATransaction.commit()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = isDarkMode

        ctx.saveGState()

        // Grip dots are NSView subviews (gripDotViews), visibility managed in layout()

        // Draw plus button
        drawPlusButton(in: ctx, isDark: dark)

        // Draw drag insertion indicator
        if isDragging, dropTarget != nil {
            drawDropIndicator(in: ctx, isDark: dark)
        }

        // Draw drag ghost
        if isDragging, let srcIdx = dragSourceIndex {
            drawDragGhost(for: srcIdx, in: ctx, isDark: dark)
        }

        // Snap guide bars are CALayers (positioned in handleResize), not drawn here.

        ctx.restoreGState()
    }

    private func clearSnapGuide() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        widthSnapLayer.isHidden = true
        heightSnapLayer.isHidden = true
        CATransaction.commit()
    }

    private func drawPlusButton(in ctx: CGContext, isDark: Bool) {
        let rect = plusButtonRect.offsetBy(dx: -scrollOffset, dy: 0)
        let path = CGPath(roundedRect: rect, cornerWidth: rect.width / 2,
                          cornerHeight: rect.width / 2, transform: nil)

        // Dashed border
        ctx.saveGState()
        ctx.addPath(path)
        let dashColor: NSColor = isDark
            ? NSColor.white.withAlphaComponent(0.09)
            : NSColor.black.withAlphaComponent(0.09)
        ctx.setStrokeColor(dashColor.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [dashLength, dashGap])
        ctx.strokePath()
        ctx.restoreGState()

        // Plus icon
        if let plusImage = NSImage(named: "IconPlusSmall") {
            let iconRect = CGRect(
                x: rect.midX - plusIconSize / 2,
                y: rect.midY - plusIconSize / 2,
                width: plusIconSize, height: plusIconSize
            )
            let iconColor: NSColor = isDark
                ? NSColor.white.withAlphaComponent(0.3)
                : NSColor.black.withAlphaComponent(0.3)
            let tinted = plusImage.tinted(with: iconColor)
            tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    /// Draws a 2x3 grid of grip dots centered horizontally in the drag handle zone.
    private func drawGripDots(in ctx: CGContext, cardRect rect: CGRect, isDark: Bool) {
        let dotColor: NSColor = isDark
            ? .white.withAlphaComponent(0.2)
            : .black.withAlphaComponent(0.15)
        ctx.setFillColor(dotColor.cgColor)

        let cols = 3
        let rows = 2
        let totalW = CGFloat(cols) * gripDotSize + CGFloat(cols - 1) * gripDotGap
        let totalH = CGFloat(rows) * gripDotSize + CGFloat(rows - 1) * gripDotGap
        let startX = rect.midX - totalW / 2
        let startY = rect.minY + (dragHandleHeight - totalH) / 2

        for row in 0..<rows {
            for col in 0..<cols {
                let x = startX + CGFloat(col) * (gripDotSize + gripDotGap)
                let y = startY + CGFloat(row) * (gripDotSize + gripDotGap)
                let dotRect = CGRect(x: x, y: y, width: gripDotSize, height: gripDotSize)
                ctx.fillEllipse(in: dotRect)
            }
        }
    }

    private func drawDropIndicator(in ctx: CGContext, isDark: Bool) {
        guard let target = dropTarget else { return }
        let indicatorWidth: CGFloat = 3
        let color: NSColor = isDark ? .white.withAlphaComponent(0.5) : .black.withAlphaComponent(0.3)
        ctx.setFillColor(color.cgColor)

        switch target {
        case .betweenColumns(let colIdx):
            let x = viewX(columnX(at: colIdx)) - cardGap / 2
            let indicatorRect = CGRect(x: x - indicatorWidth / 2, y: 4,
                                        width: indicatorWidth, height: cardSectionData.maxColumnHeight - 8)
            ctx.fill(indicatorRect)

        case .inColumn(let col, let row):
            // Horizontal line below the target card (or at column top if row == 0)
            let colX = viewX(columnX(at: col))
            let colW = cardSectionData.columnWidth(at: col)
            var y: CGFloat = cardBorder
            let column = cardSectionData.columns[col]
            let rowClamped = min(row, column.count)
            for r in 0..<rowClamped {
                y += column[r].height + cardGap
            }
            y -= cardGap / 2
            let indicatorRect = CGRect(x: colX + 4, y: y - indicatorWidth / 2,
                                        width: colW - 8, height: indicatorWidth)
            ctx.fill(indicatorRect)
        }
    }

    private func drawDragGhost(for index: Int, in ctx: CGContext, isDark: Bool) {
        guard let pos = cardSectionData.position(forFlatIndex: index) else { return }
        let card = cardSectionData.columns[pos.column][pos.row]
        let rect = CGRect(x: dragGhostOrigin.x, y: dragGhostOrigin.y,
                          width: card.width, height: card.height)
        let borderRect = rect.insetBy(dx: -cardBorder, dy: -cardBorder)

        // Shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 16,
                       color: NSColor.black.withAlphaComponent(0.25).cgColor)
        let fillPath = CGPath(roundedRect: rect, cornerWidth: cardRadius,
                              cornerHeight: cardRadius, transform: nil)
        ctx.addPath(fillPath)
        ctx.setFillColor(card.color.fillColor(isDark: isDark).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Border
        ctx.saveGState()
        let outerPath = CGPath(roundedRect: borderRect, cornerWidth: cardRadius + cardBorder,
                                cornerHeight: cardRadius + cardBorder, transform: nil)
        ctx.addPath(outerPath)
        ctx.addPath(fillPath)
        ctx.clip(using: .evenOdd)
        ctx.setFillColor(card.color.borderColor(isDark: isDark).cgColor)
        ctx.fill(borderRect.insetBy(dx: -4, dy: -4))
        ctx.restoreGState()

        // Fill (on top of shadow)
        ctx.saveGState()
        ctx.addPath(fillPath)
        ctx.setFillColor(card.color.fillColor(isDark: isDark).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Grip dots on ghost
        drawGripDots(in: ctx, cardRect: rect, isDark: isDark)
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        if needsHorizontalScroll && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            scrollOffset -= event.scrollingDeltaX
            clampScrollOffset()
            needsLayout = true
            needsDisplay = true
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    // MARK: - Hover tracking (grip dots visibility via global mouse monitor)

    private func startMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited]) { [weak self] event in
            self?.updateHoverState(from: event)
            return event
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func updateHoverState(from event: NSEvent) {
        guard let window = self.window, event.window === window else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let newHover = cardIndex(at: localPoint)
        if newHover != hoveredCardIndex {
            hoveredCardIndex = newHover
            needsLayout = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startMouseMonitor()
        } else {
            stopMouseMonitor()
        }
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Plus button?
        let plusRect = plusButtonRect.offsetBy(dx: -scrollOffset, dy: 0)
        if plusRect.contains(point) {
            cardSectionData.addCard()
            onDataChanged?(cardSectionData)
            return
        }

        // Card hit test
        guard let idx = cardIndex(at: point) else {
            // Click outside all cards — forward to parent text view
            parentTextView?.mouseDown(with: event)
            return
        }

        // Drag handle zone (top strip + side/bottom padding)?
        if isInDragHandle(at: point, cardIndex: idx) {
            dragSourceIndex = idx
            isDragging = false
            let rect = cardRect(at: idx).offsetBy(dx: -scrollOffset, dy: 0)
            dragOffset = CGPoint(x: point.x - rect.origin.x, y: point.y - rect.origin.y)
            NSCursor.closedHand.push()
            return
        }

        // Inside a card but not on a handle — focus the card's text view.
        // Clicks on padding areas miss the scroll view hit test, so we
        // explicitly make the text view first responder and place the cursor
        // at the end of the text.
        if idx < cardTextViews.count {
            let tv = cardTextViews[idx]
            window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Handle drag reorder
        if let srcIdx = dragSourceIndex {
            if !isDragging {
                isDragging = true
                if srcIdx < cardScrollViews.count { cardScrollViews[srcIdx].isHidden = true }
                if srcIdx < cardBorderLayers.count { cardBorderLayers[srcIdx].opacity = 0.15 }
                if srcIdx < cardFillLayers.count { cardFillLayers[srcIdx].opacity = 0.15 }
            }
            dragGhostOrigin = CGPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)

            dropTarget = computeDropTarget(at: point)
            needsDisplay = true
        }
    }

    /// Compute 2D drop target from view-space point.
    private func computeDropTarget(at point: CGPoint) -> DropTarget {
        let contentX = point.x + scrollOffset
        let contentY = point.y
        let columns = cardSectionData.columns

        // Find which column the mouse is in (or between)
        for colIdx in 0..<columns.count {
            let colX = columnX(at: colIdx)
            let colW = cardSectionData.columnWidth(at: colIdx)
            let colRight = colX + colW

            // Check if mouse is in this column's horizontal extent
            if contentX >= colX && contentX <= colRight {
                let column = columns[colIdx]

                // Walk cards top-to-bottom to find vertical position
                var y = cardBorder
                for row in 0..<column.count {
                    let cardH = column[row].height
                    let cardBottom = y + cardH

                    // If mouse is in the bottom 35% of this card, stack below it
                    let stackThreshold = y + cardH * 0.65
                    if contentY >= stackThreshold && contentY <= cardBottom + cardGap {
                        return .inColumn(column: colIdx, atRow: row + 1)
                    }

                    y = cardBottom + cardGap
                }

                // If mouse is below all cards in the column, stack at end
                if contentY >= y - cardGap {
                    return .inColumn(column: colIdx, atRow: column.count)
                }

                // Otherwise, treat as column-level reorder based on horizontal midpoint
                let colMid = colX + colW / 2
                return contentX > colMid ? .betweenColumns(colIdx + 1) : .betweenColumns(colIdx)
            }

            // Check if mouse is in the gap before this column
            if colIdx == 0 && contentX < colX {
                return .betweenColumns(0)
            }
            // Check if mouse is in the gap between this column and the next
            if colIdx < columns.count - 1 {
                let nextColX = columnX(at: colIdx + 1)
                if contentX > colRight && contentX < nextColX {
                    return .betweenColumns(colIdx + 1)
                }
            }
        }

        // Past all columns
        return .betweenColumns(columns.count)
    }

    override func mouseUp(with event: NSEvent) {
        // Finish drag reorder
        if let srcIdx = dragSourceIndex, isDragging, let target = dropTarget,
           let srcPos = cardSectionData.position(forFlatIndex: srcIdx) {
            let colCountBefore = cardSectionData.columns.count
            let srcCol = srcPos.column
            if let card = cardSectionData.removeCardAt(position: srcPos) {
                let srcColWasRemoved = cardSectionData.columns.count < colCountBefore

                switch target {
                case .betweenColumns(let colIdx):
                    var adjusted = colIdx
                    if srcColWasRemoved && srcCol < colIdx { adjusted -= 1 }
                    cardSectionData.insertAsNewColumn(card, at: min(max(0, adjusted), cardSectionData.columns.count))

                case .inColumn(let col, let row):
                    var adjustedCol = col
                    var adjustedRow = row
                    if srcColWasRemoved && srcCol < col { adjustedCol -= 1 }
                    // Same-column reorder: source removal shifted rows down
                    if !srcColWasRemoved && srcCol == adjustedCol && srcPos.row < row {
                        adjustedRow -= 1
                    }
                    if cardSectionData.columns.indices.contains(adjustedCol) {
                        let clampedRow = min(adjustedRow, cardSectionData.columns[adjustedCol].count)
                        cardSectionData.stackCard(card, inColumn: adjustedCol, atRow: clampedRow)
                    } else {
                        cardSectionData.insertAsNewColumn(card, at: cardSectionData.columns.count)
                    }
                }
                onDataChanged?(cardSectionData)
                onHeightChanged?(cardSectionData.maxColumnHeight)
            }
        }

        // Restore full opacity on all card layers — syncTextViews() reuses layers
        // and does not reset opacity, so the 0.15 drag ghost persists otherwise.
        for i in 0..<cardBorderLayers.count { cardBorderLayers[i].opacity = 1.0 }
        for i in 0..<cardFillLayers.count { cardFillLayers[i].opacity = 1.0 }
        for i in 0..<cardScrollViews.count { cardScrollViews[i].isHidden = false }

        if dragSourceIndex != nil { NSCursor.pop() }
        isDragging = false
        dragSourceIndex = nil
        dropTarget = nil
        needsDisplay = true
        needsLayout = true
    }

    // MARK: - Context menu

    /// Build context menu for a card at the given index. Called from both the overlay and card text views.
    func cardContextMenu(for idx: Int) -> NSMenu? {
        guard (0..<cardSectionData.flatCardCount).contains(idx) else { return nil }

        let menu = NSMenu()

        // Color submenu
        let colorItem = NSMenuItem(title: "Change Color", action: nil, keyEquivalent: "")
        let colorSubmenu = NSMenu()
        for color in CardColor.allCases {
            let item = NSMenuItem(title: color.displayName, action: #selector(changeCardColor(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = idx
            item.representedObject = color
            colorSubmenu.addItem(item)
        }
        colorItem.submenu = colorSubmenu
        menu.addItem(colorItem)

        menu.addItem(.separator())

        // Delete card
        let deleteCardItem = NSMenuItem(title: "Delete Card", action: #selector(deleteCard(_:)),
                                         keyEquivalent: "")
        deleteCardItem.target = self
        deleteCardItem.tag = idx
        if cardSectionData.flatCardCount <= 1 {
            deleteCardItem.isEnabled = false
        }
        menu.addItem(deleteCardItem)

        menu.addItem(.separator())

        // Delete section
        let deleteSectionItem = NSMenuItem(title: "Delete Card Section",
                                            action: #selector(deleteCardSection(_:)),
                                            keyEquivalent: "")
        deleteSectionItem.target = self
        menu.addItem(deleteSectionItem)

        return menu
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let idx = cardIndex(at: point) else { return nil }
        return cardContextMenu(for: idx)
    }

    @objc private func changeCardColor(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? CardColor else { return }
        let idx = sender.tag
        cardSectionData.setCardColor(at: idx, color: color)
        onDataChanged?(cardSectionData)
    }

    @objc private func deleteCard(_ sender: NSMenuItem) {
        let idx = sender.tag
        cardSectionData.removeCard(at: idx)
        onDataChanged?(cardSectionData)
        onHeightChanged?(cardSectionData.maxColumnHeight)
    }

    @objc private func deleteCardSection(_ sender: NSMenuItem) {
        onDeleteCardSection?()
    }

    // MARK: - Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let dark = isDarkMode
        for (i, card) in cardSectionData.flatCards.enumerated() {
            if i < cardBorderLayers.count {
                cardBorderLayers[i].backgroundColor = card.color.borderColor(isDark: dark).cgColor
            }
            if i < cardFillLayers.count {
                cardFillLayers[i].backgroundColor = card.color.fillColor(isDark: dark).cgColor
            }
            if i < cardTextViews.count {
                cardTextViews[i].textColor = NSColor(named: "PrimaryTextColor") ?? .labelColor
            }
        }
        needsDisplay = true
    }
}

// MARK: - NSTextViewDelegate

extension CardSectionOverlayView: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? _CardTextView,
              (0..<cardSectionData.flatCardCount).contains(tv.cardIndex) else { return }
        styleCardParagraphs(tv)
        // Prevent struct mutations (both local and from the Coordinator write-back
        // via onDataChanged -> syncText -> updateCardSectionOverlays) from triggering
        // didSet -> syncTextViews(), which would overwrite the text view's live content
        // with a deserialized version.
        isSyncingContent = true
        cardSectionData.updateCardContent(at: tv.cardIndex, content: RichTextSerializer.serializeAttributedString(tv.attributedString()))
        onDataChanged?(cardSectionData)
        isSyncingContent = false
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? _CardTextView else { return }
        let selectedRange = tv.selectedRange()

        if selectedRange.length > 0,
           let layoutManager = tv.layoutManager,
           let textContainer = tv.textContainer {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
            let selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let selectionRectInView = selectionRect.offsetBy(dx: tv.textContainerOrigin.x,
                                                              dy: tv.textContainerOrigin.y)
            let selectionRectInWindow = tv.convert(selectionRectInView, to: nil)

            // Read real formatting state from selection
            var isBold = false, isItalic = false, isUnderline = false, isStrikethrough = false
            var isHighlight = false
            var headingLevel = 0
            var fontSize = ThemeManager.currentBodyFontSize()
            var fontFamily = "default"
            var textColorHex: String? = nil

            if let storage = tv.textStorage, selectedRange.location < storage.length {
                if let font = storage.attribute(.font, at: selectedRange.location, effectiveRange: nil) as? NSFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    isBold = traits.contains(.bold)
                    isItalic = traits.contains(.italic)
                    fontSize = font.pointSize
                    // Heading detection
                    if let hl = RichTextSerializer.headingLevel(for: font) {
                        switch hl {
                        case .h1: headingLevel = 1
                        case .h2: headingLevel = 2
                        case .h3: headingLevel = 3
                        case .none: break
                        }
                    }
                    // Font family detection
                    if let customFamily = storage.attribute(TextFormattingManager.customFontFamilyKey, at: selectedRange.location, effectiveRange: nil) as? String {
                        fontFamily = customFamily
                    } else if font.fontDescriptor.object(forKey: .family) as? String == NSFont.systemFont(ofSize: 12).familyName {
                        fontFamily = "system"
                    } else if font.isFixedPitch {
                        fontFamily = "mono"
                    }
                }
                if let ul = storage.attribute(.underlineStyle, at: selectedRange.location, effectiveRange: nil) as? Int {
                    isUnderline = ul != 0
                }
                if let st = storage.attribute(.strikethroughStyle, at: selectedRange.location, effectiveRange: nil) as? Int {
                    isStrikethrough = st != 0
                }
                isHighlight = storage.attribute(.highlightColor, at: selectedRange.location, effectiveRange: nil) != nil
                if storage.attribute(TextFormattingManager.customTextColorKey, at: selectedRange.location, effectiveRange: nil) as? Bool == true,
                   let nsColor = storage.attribute(.foregroundColor, at: selectedRange.location, effectiveRange: nil) as? NSColor {
                    textColorHex = RichTextSerializer.nsColorToHex(nsColor)
                }
            }

            let visibleRect = tv.visibleRect
            var info: [String: Any] = [
                "hasSelection": true,
                "selectionX": selectionRect.origin.x + tv.textContainerOrigin.x,
                "selectionY": selectionRect.origin.y + tv.textContainerOrigin.y - visibleRect.origin.y,
                "selectionWidth": selectionRect.width,
                "selectionHeight": selectionRect.height,
                "selectionWindowY": selectionRectInWindow.origin.y,
                "selectionWindowX": selectionRectInWindow.origin.x,
                "visibleWidth": visibleRect.width,
                "visibleHeight": visibleRect.height,
                "isBold": isBold,
                "isItalic": isItalic,
                "isUnderline": isUnderline,
                "isStrikethrough": isStrikethrough,
                "isHighlight": isHighlight,
                "headingLevel": headingLevel,
                "windowHeight": tv.window?.contentView?.bounds.height ?? 800,
                "fontSize": fontSize,
                "fontFamily": fontFamily
            ]
            if let hex = textColorHex { info["textColorHex"] = hex }
            if let eid = editorInstanceID { info["editorInstanceID"] = eid }
            NotificationCenter.default.post(name: .textSelectionChanged, object: nil, userInfo: info)
        } else {
            var info: [String: Any] = ["hasSelection": false]
            if let eid = editorInstanceID { info["editorInstanceID"] = eid }
            NotificationCenter.default.post(name: .textSelectionChanged, object: nil, userInfo: info)
        }
    }
}

// MARK: - Grip Dots View (subview that renders above CALayers)

private final class _GripDotsView: NSView {
    let dotSize: CGFloat
    let dotGap: CGFloat
    private let cols = 3
    private let rows = 2

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(dotSize: CGFloat, dotGap: CGFloat) {
        self.dotSize = dotSize
        self.dotGap = dotGap
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }  // pass-through

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color: NSColor = isDark ? .white.withAlphaComponent(0.25) : .black.withAlphaComponent(0.18)
        color.setFill()

        let totalW = CGFloat(cols) * dotSize + CGFloat(cols - 1) * dotGap
        let totalH = CGFloat(rows) * dotSize + CGFloat(rows - 1) * dotGap
        let startX = (bounds.width - totalW) / 2
        let startY = (bounds.height - totalH) / 2

        for row in 0..<rows {
            for col in 0..<cols {
                let x = startX + CGFloat(col) * (dotSize + dotGap)
                let y = startY + CGFloat(row) * (dotSize + dotGap)
                NSBezierPath(ovalIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)).fill()
            }
        }
    }
}

// MARK: - Card Resize Handle (dedicated subview, follows _TabsResizeHandle pattern)

private final class _CardResizeHandle: NSView {
    enum Edge { case right, bottom, corner }

    var onResize: ((Int, CGFloat, CGFloat) -> Void)?  // (cardIndex, deltaX, deltaY)
    var onResizeEnd: (() -> Void)?
    var cardIndex: Int = 0
    let edge: Edge
    private var dragStart: CGPoint = .zero

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    init(edge: Edge) {
        self.edge = edge
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        resizeCursor.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: resizeCursor)
    }

    private var resizeCursor: NSCursor {
        switch edge {
        case .right:  return NSCursor.compatFrameResize(position: "right")
        case .bottom: return NSCursor.compatFrameResize(position: "bottom")
        case .corner: return NSCursor.compatFrameResize(position: "bottomRight")
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        resizeCursor.push()
    }

    override func mouseDragged(with event: NSEvent) {
        let dx = event.locationInWindow.x - dragStart.x
        let dy = dragStart.y - event.locationInWindow.y  // flipped: drag down = positive delta
        dragStart = event.locationInWindow
        switch edge {
        case .right:  onResize?(cardIndex, dx, 0)
        case .bottom: onResize?(cardIndex, 0, dy)
        case .corner: onResize?(cardIndex, dx, dy)
        }
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        onResizeEnd?()
    }
}

// MARK: - Card Scroll View (forwards horizontal scroll to overlay)

private final class _CardScrollView: NSScrollView {
    weak var overlayView: CardSectionOverlayView?

    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }  // force overlay regardless of system prefs
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
           let overlay = overlayView, overlay.needsHorizontalScroll {
            overlay.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - Card Text View (forwards right-click to overlay)

final class _CardTextView: NSTextView {
    var cardIndex: Int = 0
    weak var overlayView: CardSectionOverlayView?

    override func menu(for event: NSEvent) -> NSMenu? {
        overlayView?.cardContextMenu(for: cardIndex)
    }
}

// MARK: - Card Layout Manager (squiggly strikethrough only, no typing animation)

/// Lightweight NSLayoutManager that draws the squiggly strikethrough line
/// matching the main editor's `TypingAnimationLayoutManager`, but without
/// the typing animation overhead.
final class _CardLayoutManager: NSLayoutManager {

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawSquigglyStrikethrough(forGlyphRange: glyphsToShow, at: origin)
    }

    // Suppress native straight-line strikethrough — the squiggly replaces it.
    override func drawStrikethrough(forGlyphRange glyphRange: NSRange, strikethroughType strikethroughVal: NSUnderlineStyle, baselineOffset: CGFloat, lineFragmentRect lineRect: NSRect, lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: NSPoint) {
        // Intentionally empty
    }

    private func drawSquigglyStrikethrough(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage = textStorage,
              let textContainer = textContainers.first,
              let context = NSGraphicsContext.current?.cgContext
        else { return }
        guard NSMaxRange(glyphsToShow) <= numberOfGlyphs else { return }
        guard textStorage.length > 0 else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let safeCharRange = NSIntersectionRange(charRange, NSRange(location: 0, length: textStorage.length))
        guard safeCharRange.length > 0 else { return }

        // Draw squiggly line for strikethrough ranges
        textStorage.enumerateAttribute(.strikethroughStyle, in: safeCharRange, options: []) { value, attrRange, _ in
            guard let style = value as? Int, style != 0 else { return }
            drawSquigglyLine(forAttrRange: attrRange, textStorage: textStorage, textContainer: textContainer, origin: origin, context: context)
        }
    }

    private func drawSquigglyLine(forAttrRange attrRange: NSRange, textStorage: NSTextStorage, textContainer: NSTextContainer, origin: NSPoint, context: CGContext) {
        let nsString = textStorage.string as NSString
        var trimmedEnd = NSMaxRange(attrRange)
        while trimmedEnd > attrRange.location {
            let ch = nsString.character(at: trimmedEnd - 1)
            if ch == 0x0A || ch == 0x0D || ch == 0x20 || ch == 0x09 { trimmedEnd -= 1 }
            else { break }
        }
        let trimmedRange = NSRange(location: attrRange.location, length: trimmedEnd - attrRange.location)
        guard trimmedRange.length > 0 else { return }

        let glyphRange = self.glyphRange(forCharacterRange: trimmedRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, usedRect, container, lineGlyphRange, stop in
            let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard intersection.length > 0 else { return }

            let segmentRect = self.boundingRect(forGlyphRange: intersection, in: textContainer)
            let startX = origin.x + segmentRect.origin.x + 2
            let endX = origin.x + segmentRect.origin.x + segmentRect.width - 1
            let glyphLoc = self.location(forGlyphAt: intersection.location)
            let charIdx = self.characterIndexForGlyph(at: intersection.location)
            let font = textStorage.attribute(.font, at: charIdx, effectiveRange: nil) as? NSFont
                ?? NSFont.systemFont(ofSize: 14)
            let baseline = lineRect.origin.y + glyphLoc.y
            let midY = origin.y + baseline - font.xHeight * 0.5

            guard endX - startX > 4 else { return }

            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let segmentLength = endX - startX
            let stepSize: CGFloat = 6.0
            let steps = max(1, Int(ceil(segmentLength / stepSize)))

            let text = nsString.substring(with: attrRange)
            var contentHash: UInt64 = 5381
            for scalar in text.unicodeScalars {
                contentHash = contentHash &* 33 &+ UInt64(scalar.value)
            }
            var rng = contentHash

            func nextWobble() -> CGFloat {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                let normalized = CGFloat((rng >> 33) & 0x7FFF) / CGFloat(0x7FFF)
                return (normalized - 0.5) * 5.0
            }

            path.move(to: NSPoint(x: startX, y: midY + nextWobble()))

            for i in 1...steps {
                let x = min(startX + CGFloat(i) * stepSize, endX)
                let wobble = nextWobble()
                let cpX = startX + (CGFloat(i) - 0.5) * stepSize
                let cpY = midY + nextWobble()
                path.curve(to: NSPoint(x: x, y: midY + wobble),
                           controlPoint1: NSPoint(x: min(cpX, endX), y: cpY),
                           controlPoint2: NSPoint(x: x, y: midY + wobble))
            }

            context.saveGState()
            NSColor.labelColor.setStroke()
            path.stroke()
            context.restoreGState()
        }
    }
}

// MARK: - NSColor hex init (file-private, same as CalloutOverlayView)

private extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgb) else { return nil }
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green:   CGFloat((rgb >> 8)  & 0xFF) / 255,
            blue:    CGFloat( rgb        & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - NSImage tinting helper

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = self.copy() as! NSImage
        img.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: img.size)
        rect.fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

#endif
