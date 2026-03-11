//
//  NoteTableOverlayView.swift
//  Jot
//
//  Custom NSView that renders and handles interaction for inline tables.
//  Positioned over a NoteTableAttachment in the text view, following the
//  same overlay pattern as InlineImageOverlayView.
//
//  Coordinate system: isFlipped = true (y=0 at top, increases downward)
//  so row 0 is at the top, matching natural table ordering.
//

import AppKit
import SwiftUI

final class NoteTableOverlayView: NSView {

    override var isFlipped: Bool { true }

    // MARK: - Public State

    var tableData: NoteTableData {
        didSet {
            if tableData != oldValue {
                invalidateLayout()
            }
        }
    }

    var onDataChanged: ((NoteTableData) -> Void)?
    var onDeleteTable: (() -> Void)?
    weak var parentTextView: NSTextView?

    /// Actual table viewport width set externally by updateTableOverlays.
    /// Content scrolls within this width when columns overflow.
    var tableWidth: CGFloat = 0 {
        didSet {
            if tableWidth != oldValue {
                invalidateLayout()
            }
        }
    }

    /// Frame expansion margins so the NSView frame covers interactive handle areas.
    /// Without this, NSView.hitTest is never called for out-of-frame handle clicks.
    static let overlayInsets = NSEdgeInsets(top: 26, left: 26, bottom: 40, right: 40)

    // MARK: - Layout Constants

    private let rowHeight: CGFloat = 36
    private let outerCornerRadius: CGFloat = 16
    private let gridLineWidth: CGFloat = 0.5

    /// Generates a continuous (squircle) rounded rect path matching Apple's design language.
    private func continuousPath(for rect: NSRect, radius: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(in: rect)
            .cgPath
    }

    private func continuousBezierPath(for rect: NSRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(cgPath: continuousPath(for: rect, radius: radius))
    }
    private let cellPaddingH: CGFloat = 10
    private let cellPaddingV: CGFloat = 8

    // Grab handle pills: compact capsules outside table bounds
    private let handleGap: CGFloat = 2
    private let handleHitThickness: CGFloat = 20
    private let handleDotDiameter: CGFloat = 3
    private let handleDotSpacing: CGFloat = 4
    private let handlePadding: CGFloat = 4

    // Computed pill dimensions (horizontal dots for columns)
    private var colHandlePillWidth: CGFloat { handleDotDiameter + 2 * handleDotSpacing + 2 * handlePadding }
    private var colHandlePillHeight: CGFloat { handleDotDiameter + 2 * handlePadding }

    // + buttons: drawn outside table bounds
    private let addButtonHeight: CGFloat = 24
    private let addButtonGap: CGFloat = 8
    private let addButtonDashPattern: [CGFloat] = [4, 3]
    private let addIconSize: CGFloat = 8

    // Horizontal scroll
    private let minColumnWidth: CGFloat = 50

    // Cell drag threshold (pixels before click becomes drag)
    private let dragThreshold: CGFloat = 4

    // MARK: - Internal State

    private var editingCell: (row: Int, column: Int)?
    private var editField: NSTextField?
    private var hoveredColumnHandle: Int?
    private var hoveredRowHandle: Int?
    private var isHoveringAddRow = false
    private var isHoveringAddColumn = false
    private var trackingArea: NSTrackingArea?

    // Row/column drag via grab handles
    private var isDraggingRow = false
    private var isDraggingColumn = false
    private var dragSourceIndex: Int = -1
    private var dragStartPos: CGFloat = 0
    private var dragCurrentPos: CGFloat = 0

    // Cell drag (grab cell content, drop elsewhere)
    private var isDraggingCell = false
    private var dragCellSource: (row: Int, column: Int)?
    private var dragCellMousePos: NSPoint = .zero

    // Pending edit: disambiguate click (edit) vs drag (move cell)
    private var pendingEdit: (row: Int, column: Int)?
    private var mouseDownPoint: NSPoint = .zero

    // Column divider resize state
    private var isDraggingDivider = false
    private var draggingDividerIndex: Int = -1
    private var dividerStartX: CGFloat = 0
    private var dividerStartWidths: [CGFloat] = []
    private var isHoveringDivider = false
    private var hoveredDividerIndex: Int = -1
    private let dividerHitWidth: CGFloat = 14

    // Body hover tracking — show grab handles when mouse is in a row/column
    private var hoveredBodyRow: Int?
    private var hoveredBodyColumn: Int?

    // Horizontal scroll (when columns overflow the view width)
    private var scrollOffset: CGFloat = 0

    // Context menu indices
    private var contextRowIndex: Int = 0
    private var contextColumnIndex: Int = 0

    // MARK: - Colors

    private var borderColor: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.black.withAlphaComponent(0.08)
    }
    private var gridColor: NSColor { .separatorColor }
    private var cellBackgroundColor: NSColor {
        isDarkMode
            ? NSColor(red: 0x0C/255.0, green: 0x0A/255.0, blue: 0x09/255.0, alpha: 1)
            : .white
    }

    /// Matches the note detail pane background for gradient fade edges.
    private var paneBackgroundColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.110, green: 0.098, blue: 0.090, alpha: 1)
            : NSColor(red: 0.906, green: 0.898, blue: 0.894, alpha: 1)
    }

    private var iconSecondaryColor: NSColor {
        NSColor(named: "IconSecondaryColor") ?? .secondaryLabelColor
    }
    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua]) == .darkAqua
    }
    private var handleIdleColor: NSColor {
        isDarkMode ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.07)
    }
    private var handleHoverColor: NSColor {
        isDarkMode ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.12)
    }
    private var addButtonFillColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(isDarkMode ? 0.18 : 0.08)
    }
    private var addButtonStrokeColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(isDarkMode ? 0.55 : 0.4)
    }
    private var addButtonIconColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(isDarkMode ? 0.85 : 0.7)
    }
    private var headerBackgroundColor: NSColor {
        NSColor(named: "BlockContainerColor")
            ?? (isDarkMode
                ? NSColor(srgbRed: 41/255, green: 37/255, blue: 36/255, alpha: 1)
                : NSColor(srgbRed: 214/255, green: 211/255, blue: 209/255, alpha: 1))
    }

    // MARK: - Init

    init(tableData: NoteTableData) {
        self.tableData = tableData
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteTableOverlayView does not support init(coder:)")
    }

    // MARK: - Computed Geometry

    /// Viewport width for visible content
    private var viewportWidth: CGFloat {
        tableWidth > 0 ? tableWidth : bounds.width
    }

    /// Total content width from column widths
    private var contentWidth: CGFloat {
        tableData.contentWidth
    }

    private var needsHorizontalScroll: Bool { contentWidth > viewportWidth + 1 }
    private var maxScrollOffset: CGFloat {
        let base = contentWidth - viewportWidth
        // Extend scroll range so the add-column button is fully reachable
        let buttonExtra = addButtonGap + addButtonHeight + 4
        return max(0, base + buttonExtra)
    }

    /// Table content rect in content-space coordinates
    private var tableContentRect: NSRect {
        NSRect(x: 0, y: 0, width: contentWidth, height: tableHeight)
    }

    /// Visible table rect in view coordinates
    private var tableRect: NSRect {
        NSRect(x: 0, y: 0, width: viewportWidth, height: tableHeight)
    }

    private var tableHeight: CGFloat {
        CGFloat(tableData.rows) * rowHeight
    }

    // MARK: Per-Column Geometry

    /// X position of column `col` in content space
    private func colX(_ col: Int) -> CGFloat {
        guard col > 0 else { return 0 }
        let end = min(col, tableData.columnWidths.count)
        return tableData.columnWidths[0..<end].reduce(0, +)
    }

    /// Width of column `col` in content space
    private func colW(_ col: Int) -> CGFloat {
        guard col >= 0, col < tableData.columnWidths.count else {
            return NoteTableData.defaultColumnWidth
        }
        return tableData.columnWidths[col]
    }

    /// Cell rect in content-space coordinates
    private func cellRect(row: Int, column: Int) -> NSRect {
        let x = colX(column)
        let y = CGFloat(row) * rowHeight
        return NSRect(x: x, y: y, width: colW(column), height: rowHeight)
    }

    /// Cell rect offset to view coordinates (accounts for scroll)
    private func visibleCellRect(row: Int, column: Int) -> NSRect {
        cellRect(row: row, column: column).offsetBy(dx: -scrollOffset, dy: 0)
    }

    private func cellAt(point: NSPoint) -> (row: Int, column: Int)? {
        let scrolledX = point.x + scrollOffset
        guard scrolledX >= 0, scrolledX < contentWidth,
              point.y >= 0, point.y < tableHeight else { return nil }
        var col = tableData.columns - 1
        for c in 0..<tableData.columns {
            if scrolledX < colX(c + 1) { col = c; break }
        }
        let row = min(Int(point.y / rowHeight), tableData.rows - 1)
        guard row >= 0, col >= 0 else { return nil }
        return (row, col)
    }

    private func clampScrollOffset() {
        scrollOffset = max(0, min(scrollOffset, maxScrollOffset))
    }

    // Handle hit rects (generous click target, in view coordinates)
    private func columnHandleRect(for col: Int) -> NSRect {
        let x = colX(col) - scrollOffset
        let y = -(handleGap + handleHitThickness)
        return NSRect(x: x, y: y, width: colW(col), height: handleHitThickness)
    }

    private func rowHandleRect(for row: Int) -> NSRect {
        let y = CGFloat(row) * rowHeight
        let x = -(handleGap + handleHitThickness)
        return NSRect(x: x, y: y, width: handleHitThickness, height: rowHeight)
    }

    /// Hit zone for row handles — matches the visible handle strip only (no inward extension).
    private func rowHandleHitZone(for row: Int) -> NSRect {
        return rowHandleRect(for: row)
    }

    /// Hit rect for column divider between col and col+1
    private func columnDividerRect(at col: Int) -> NSRect {
        let x = colX(col + 1) - scrollOffset - dividerHitWidth / 2
        return NSRect(x: x, y: 0, width: dividerHitWidth, height: tableHeight)
    }

    private var addRowButtonRect: NSRect {
        NSRect(x: 0, y: tableHeight + addButtonGap,
               width: viewportWidth, height: addButtonHeight)
    }

    /// Content-space rect for the add-column button.
    private var addColumnButtonRect: NSRect {
        let baseX: CGFloat
        if needsHorizontalScroll {
            baseX = contentWidth + addButtonGap
        } else {
            baseX = contentWidth + addButtonGap
        }
        return NSRect(x: baseX, y: 0, width: addButtonHeight, height: tableHeight)
    }

    /// View-space rect for hit testing (accounts for scroll offset).
    private var addColumnButtonViewRect: NSRect {
        var rect = addColumnButtonRect
        rect.origin.x -= scrollOffset
        return rect
    }

    /// The full interactive rect including all handles and buttons outside bounds.
    private var interactiveRect: NSRect {
        let margin = handleGap + handleHitThickness + 4
        let bottomMargin = addButtonGap + addButtonHeight + 4
        let rightMargin: CGFloat = needsHorizontalScroll ? 4 : (addButtonGap + addButtonHeight + 4)
        return NSRect(
            x: -margin, y: -margin,
            width: viewportWidth + margin + rightMargin,
            height: tableHeight + margin + bottomMargin
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        layer?.masksToBounds = false
        updateShadowPath()
    }

    private func invalidateLayout() {
        clampScrollOffset()
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
        updateShadowPath()
    }

    override func layout() {
        super.layout()
        updateShadowPath()
    }

    private func updateShadowPath() {
        // Shadow must fade *under* the gradient overlays so no hard edge is visible.
        // Inset the shadow path from any edge that has a gradient fade.
        let visibleTableEnd = contentWidth - scrollOffset
        let vp = viewportWidth > 0 ? viewportWidth : contentWidth
        let visibleRight = min(visibleTableEnd, vp)

        let fadeInset: CGFloat = 32  // pull shadow back so gradient covers its edge

        var left: CGFloat = 0
        var right: CGFloat = visibleRight

        if needsHorizontalScroll {
            // Right overflow → pull shadow back from right edge
            let rightOverflow = contentWidth - scrollOffset - viewportWidth
            if rightOverflow > 1 {
                right = visibleRight - fadeInset
            }
            // Left overflow (scrolled past start) → pull shadow back from left edge
            if scrollOffset > 1 {
                left = fadeInset
            }
        }

        let width = max(0, right - left)
        let rect = NSRect(x: left, y: 0, width: width, height: tableHeight)
        layer?.shadowPath = continuousPath(for: rect, radius: outerCornerRadius)
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return super.hitTest(point) }
        let local = convert(point, from: sv)

        guard interactiveRect.contains(local) else { return nil }

        // Check subviews first (edit field gets priority)
        for sub in subviews.reversed() {
            if let hit = sub.hitTest(local) { return hit }
        }

        return self
    }

    // MARK: - Drag Target Calculation

    private func dragTargetIndex(isRow: Bool) -> Int {
        if isRow {
            let dragOffset = dragCurrentPos - dragStartPos
            let draggedCenterY = (CGFloat(dragSourceIndex) + 0.5) * rowHeight + dragOffset
            return max(0, min(tableData.rows, Int(round(draggedCenterY / rowHeight))))
        } else {
            let dragOffset = dragCurrentPos - dragStartPos
            let srcCenter = colX(dragSourceIndex) + colW(dragSourceIndex) / 2
            let draggedCenterX = srcCenter + dragOffset
            var best = 0
            var bestDist = abs(draggedCenterX - colX(0))
            for c in 1...tableData.columns {
                let boundary = colX(c)
                let dist = abs(draggedCenterX - boundary)
                if dist < bestDist { bestDist = dist; best = c }
            }
            return best
        }
    }

    // MARK: - Scroll Fade Edges

    /// Draws gradient fade overlays on the edges where content is clipped.
    /// Uses the note detail pane's background color to fade table content
    /// into the surrounding pane, matching the pane's own vertical fade style.
    /// Drawn OUTSIDE the table's content clip so it overlays the hard edge.
    private func drawScrollFadeEdges() {
        guard needsHorizontalScroll else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let fadeWidth: CGFloat = 48
        let bgColor = paneBackgroundColor

        // --- Right fade (when content overflows right) ---
        let rightOverflow = contentWidth - scrollOffset - viewportWidth
        if rightOverflow > 1 {
            let rightFadeW = min(fadeWidth, rightOverflow)
            // Push inward slightly so the fade is noticeable before the edge
            let inset: CGFloat = 4
            let startX = viewportWidth - rightFadeW - inset
            let endX = viewportWidth
            let fadeRect = NSRect(x: startX, y: 0, width: endX - startX, height: tableHeight)

            ctx.saveGState()
            ctx.clip(to: fadeRect)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: [
                bgColor.withAlphaComponent(0).cgColor,
                bgColor.withAlphaComponent(0.18).cgColor,
                bgColor.withAlphaComponent(0.45).cgColor,
                bgColor.withAlphaComponent(0.80).cgColor,
                bgColor.withAlphaComponent(0.96).cgColor,
                bgColor.cgColor
            ] as CFArray, locations: [0.0, 0.18, 0.35, 0.60, 0.82, 1.0]) {
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: startX, y: 0),
                                       end: CGPoint(x: endX, y: 0),
                                       options: [])
            }
            ctx.restoreGState()
        }

        // --- Left fade (when scrolled past the start) ---
        if scrollOffset > 1 {
            let leftFadeW = min(fadeWidth, scrollOffset)
            let inset: CGFloat = 4
            let startX: CGFloat = 0
            let endX = leftFadeW + inset
            let fadeRect = NSRect(x: startX, y: 0, width: endX, height: tableHeight)

            ctx.saveGState()
            ctx.clip(to: fadeRect)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: [
                bgColor.cgColor,
                bgColor.withAlphaComponent(0.96).cgColor,
                bgColor.withAlphaComponent(0.80).cgColor,
                bgColor.withAlphaComponent(0.45).cgColor,
                bgColor.withAlphaComponent(0.18).cgColor,
                bgColor.withAlphaComponent(0).cgColor
            ] as CFArray, locations: [0.0, 0.18, 0.40, 0.65, 0.82, 1.0]) {
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: startX, y: 0),
                                       end: CGPoint(x: endX, y: 0),
                                       options: [])
            }
            ctx.restoreGState()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        clampScrollOffset()

        // --- Table content (clipped for horizontal scroll) ---
        let clipWidth = needsHorizontalScroll ? viewportWidth : contentWidth
        ctx.saveGState()
        ctx.clip(to: NSRect(x: 0, y: 0, width: clipWidth, height: tableHeight))
        ctx.translateBy(x: -scrollOffset, y: 0)

        drawTableBackground()
        drawHeaderBackground()
        drawGridLines()
        drawCellText()
        drawTableBorder()
        drawInsertionIndicator()

        // Draw add-column button inside the scroll-clipped region so it
        // scrolls with content and isn't clipped by the NSClipView boundary.
        if isHoveringAddColumn && needsHorizontalScroll {
            drawAddColumnButton()
        }

        ctx.restoreGState()

        // --- Dragged elements on top (with shadow) ---
        if isDraggingRow { drawDraggedRow(ctx: ctx) }
        if isDraggingColumn { drawDraggedColumn(ctx: ctx) }
        if isDraggingCell { drawDraggedCell(ctx: ctx) }

        // --- Handles and buttons (show for hovered row/column, hide during drag) ---
        if !isDraggingColumn {
            if let col = hoveredColumnHandle {
                drawColumnHandle(at: col, hovered: true)
            } else if let col = hoveredBodyColumn {
                drawColumnHandle(at: col, hovered: false)
            }
        }
        if !isDraggingRow {
            if let row = hoveredRowHandle {
                drawRowHandle(at: row, hovered: true)
            } else if let row = hoveredBodyRow {
                drawRowHandle(at: row, hovered: false)
            }
        }
        if isHoveringAddRow { drawAddRowButton() }
        if isHoveringAddColumn && !needsHorizontalScroll { drawAddColumnButton() }

        // Column divider highlight
        if isHoveringDivider && !isDraggingDivider, hoveredDividerIndex >= 0 {
            drawColumnDividerHighlight(at: hoveredDividerIndex)
        }
        if isDraggingDivider {
            drawColumnDividerIndicator()
        }

        // Gradient fade edges (replaces scroll indicator bar)
        drawScrollFadeEdges()
    }

    private func drawTableBackground() {
        let path = continuousBezierPath(for: tableContentRect, radius: outerCornerRadius)
        cellBackgroundColor.setFill()
        path.fill()
    }

    private func drawHeaderBackground() {
        guard tableData.rows > 0 else { return }
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        let clipPath = continuousBezierPath(for: tableContentRect, radius: outerCornerRadius)
        clipPath.addClip()
        let headerRect = NSRect(x: 0, y: 0, width: contentWidth, height: rowHeight)
        headerBackgroundColor.setFill()
        NSBezierPath(rect: headerRect).fill()
        ctx?.restoreGState()
    }

    private func drawGridLines() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let clipPath = continuousBezierPath(for: tableContentRect, radius: outerCornerRadius)
        ctx.saveGState()
        clipPath.addClip()

        gridColor.setStroke()

        // Horizontal
        for row in 1..<tableData.rows {
            let y = CGFloat(row) * rowHeight
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: y))
            line.line(to: NSPoint(x: contentWidth, y: y))
            // Thicker separator after header row
            line.lineWidth = (row == 1) ? 1.0 : gridLineWidth
            line.stroke()
        }

        // Vertical
        for col in 1..<tableData.columns {
            let x = colX(col)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: 0))
            line.line(to: NSPoint(x: x, y: tableHeight))
            line.lineWidth = gridLineWidth
            line.stroke()
        }

        ctx.restoreGState()
    }

    private func drawCellText() {
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        for row in 0..<tableData.rows {
            let attrs = row == 0 ? headerAttrs : bodyAttrs
            for col in 0..<tableData.columns {
                // Skip cells that are being drawn separately
                if isDraggingRow && row == dragSourceIndex { continue }
                if isDraggingColumn && col == dragSourceIndex { continue }
                if isDraggingCell, let src = dragCellSource, src.row == row, src.column == col { continue }
                if let editing = editingCell, editing.row == row, editing.column == col { continue }

                let text = tableData.cells[row][col]
                guard !text.isEmpty else { continue }
                let rect = cellRect(row: row, column: col)
                    .insetBy(dx: cellPaddingH, dy: cellPaddingV)
                NSAttributedString(string: text, attributes: attrs)
                    .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }
        }
    }

    private func drawTableBorder() {
        borderColor.setStroke()
        let inset = gridLineWidth / 2
        let path = continuousBezierPath(for: tableContentRect.insetBy(dx: inset, dy: inset), radius: outerCornerRadius)
        path.lineWidth = gridLineWidth
        path.stroke()
    }

    // MARK: - Insertion Indicator (during row/col drag)

    private func drawInsertionIndicator() {
        guard isDraggingRow || isDraggingColumn else { return }

        if isDraggingRow {
            let target = dragTargetIndex(isRow: true)
            let lineY = CGFloat(target) * rowHeight
            NSColor.controlAccentColor.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: lineY))
            line.line(to: NSPoint(x: contentWidth, y: lineY))
            line.lineWidth = 2
            line.stroke()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: -3, y: lineY - 3, width: 6, height: 6)).fill()
            NSBezierPath(ovalIn: NSRect(x: contentWidth - 3, y: lineY - 3, width: 6, height: 6)).fill()
        } else if isDraggingColumn {
            let target = dragTargetIndex(isRow: false)
            let lineX = colX(target)
            NSColor.controlAccentColor.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: lineX, y: 0))
            line.line(to: NSPoint(x: lineX, y: tableHeight))
            line.lineWidth = 2
            line.stroke()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: lineX - 3, y: -3, width: 6, height: 6)).fill()
            NSBezierPath(ovalIn: NSRect(x: lineX - 3, y: tableHeight - 3, width: 6, height: 6)).fill()
        }
    }

    // MARK: - Dragged Row (floating with shadow)

    private func drawDraggedRow(ctx: CGContext) {
        let dragOffset = dragCurrentPos - dragStartPos
        let floatingY = CGFloat(dragSourceIndex) * rowHeight + dragOffset
        let visibleWidth = min(contentWidth, viewportWidth)
        let floatingRect = NSRect(x: 0, y: floatingY, width: visibleWidth, height: rowHeight)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8,
                       color: NSColor.black.withAlphaComponent(0.18).cgColor)

        cellBackgroundColor.setFill()
        NSBezierPath(roundedRect: floatingRect, xRadius: 4, yRadius: 4).fill()

        ctx.setShadow(offset: .zero, blur: 0)

        gridColor.setStroke()
        for col in 1..<tableData.columns {
            let x = colX(col) - scrollOffset
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: floatingY))
            line.line(to: NSPoint(x: x, y: floatingY + rowHeight))
            line.lineWidth = gridLineWidth
            line.stroke()
        }

        // Use header attrs for row 0
        let isHeader = dragSourceIndex == 0
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isHeader ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        for col in 0..<tableData.columns {
            let text = tableData.cells[dragSourceIndex][col]
            guard !text.isEmpty else { continue }
            let cellX = colX(col) - scrollOffset
            let w = colW(col)
            let textRect = NSRect(x: cellX + cellPaddingH, y: floatingY + cellPaddingV,
                                   width: w - 2 * cellPaddingH,
                                   height: rowHeight - 2 * cellPaddingV)
            NSAttributedString(string: text, attributes: textAttrs)
                .draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        NSColor.controlAccentColor.withAlphaComponent(0.4).setStroke()
        let borderPath = NSBezierPath(roundedRect: floatingRect.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: 4, yRadius: 4)
        borderPath.lineWidth = 1
        borderPath.stroke()

        ctx.restoreGState()
    }

    // MARK: - Dragged Column (floating with shadow)

    private func drawDraggedColumn(ctx: CGContext) {
        let dragOffset = dragCurrentPos - dragStartPos
        let w = colW(dragSourceIndex)
        let floatingX = colX(dragSourceIndex) + dragOffset - scrollOffset
        let floatingRect = NSRect(x: floatingX, y: 0, width: w, height: tableHeight)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 2, height: 0), blur: 8,
                       color: NSColor.black.withAlphaComponent(0.18).cgColor)

        cellBackgroundColor.setFill()
        NSBezierPath(roundedRect: floatingRect, xRadius: 4, yRadius: 4).fill()

        ctx.setShadow(offset: .zero, blur: 0)

        gridColor.setStroke()
        for row in 1..<tableData.rows {
            let y = CGFloat(row) * rowHeight
            let line = NSBezierPath()
            line.move(to: NSPoint(x: floatingX, y: y))
            line.line(to: NSPoint(x: floatingX + w, y: y))
            line.lineWidth = gridLineWidth
            line.stroke()
        }

        for row in 0..<tableData.rows {
            let text = tableData.cells[row][dragSourceIndex]
            guard !text.isEmpty else { continue }
            let isHeader = row == 0
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: isHeader ? .semibold : .regular),
                .foregroundColor: NSColor.labelColor,
            ]
            let textRect = NSRect(x: floatingX + cellPaddingH,
                                   y: CGFloat(row) * rowHeight + cellPaddingV,
                                   width: w - 2 * cellPaddingH,
                                   height: rowHeight - 2 * cellPaddingV)
            NSAttributedString(string: text, attributes: textAttrs)
                .draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        NSColor.controlAccentColor.withAlphaComponent(0.4).setStroke()
        let borderPath = NSBezierPath(roundedRect: floatingRect.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: 4, yRadius: 4)
        borderPath.lineWidth = 1
        borderPath.stroke()

        ctx.restoreGState()
    }

    // MARK: - Dragged Cell (floating with shadow + target highlight)

    private func drawDraggedCell(ctx: CGContext) {
        guard let src = dragCellSource else { return }
        let text = tableData.cells[src.row][src.column]

        // Highlight target cell
        if let target = cellAt(point: dragCellMousePos),
           !(target.row == src.row && target.column == src.column) {
            let targetRect = cellRect(row: target.row, column: target.column)
                .offsetBy(dx: -scrollOffset, dy: 0)
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: targetRect).fill()
            NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
            let border = NSBezierPath(rect: targetRect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }

        // Floating cell following the mouse
        let cellW = src.column < tableData.columns ? colW(src.column) : 80
        let cellH = rowHeight
        let floatingRect = NSRect(x: dragCellMousePos.x - cellW / 2,
                                   y: dragCellMousePos.y - cellH / 2,
                                   width: cellW, height: cellH)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8,
                       color: NSColor.black.withAlphaComponent(0.2).cgColor)

        cellBackgroundColor.setFill()
        NSBezierPath(roundedRect: floatingRect, xRadius: 4, yRadius: 4).fill()

        ctx.setShadow(offset: .zero, blur: 0)

        if !text.isEmpty {
            let isHeader = src.row == 0
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: isHeader ? .semibold : .regular),
                .foregroundColor: NSColor.labelColor,
            ]
            let textRect = floatingRect.insetBy(dx: cellPaddingH, dy: cellPaddingV)
            NSAttributedString(string: text, attributes: textAttrs)
                .draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
        let borderPath = NSBezierPath(roundedRect: floatingRect.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: 4, yRadius: 4)
        borderPath.lineWidth = 1
        borderPath.stroke()

        ctx.restoreGState()
    }

    // MARK: - Grab Handles

    private func drawColumnHandle(at col: Int, hovered: Bool) {
        let hitRect = columnHandleRect(for: col)
        let pillW = colHandlePillWidth
        let pillH = colHandlePillHeight
        let pill = NSRect(x: hitRect.midX - pillW / 2, y: hitRect.midY - pillH / 2,
                          width: pillW, height: pillH)
        let r = min(pill.width, pill.height) / 2
        let path = NSBezierPath(roundedRect: pill, xRadius: r, yRadius: r)
        (hovered ? handleHoverColor : handleIdleColor).setFill()
        path.fill()

        // Three horizontal dots
        let cx = pill.midX, cy = pill.midY
        (hovered ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setFill()
        for i in -1...1 {
            let dx = CGFloat(i) * handleDotSpacing
            NSBezierPath(ovalIn: NSRect(
                x: cx + dx - handleDotDiameter / 2, y: cy - handleDotDiameter / 2,
                width: handleDotDiameter, height: handleDotDiameter
            )).fill()
        }
    }

    private func drawRowHandle(at row: Int, hovered: Bool) {
        let hitRect = rowHandleRect(for: row)
        let pillW = colHandlePillHeight   // rotated: width = short side
        let pillH = colHandlePillWidth    // rotated: height = long side
        let pill = NSRect(x: hitRect.midX - pillW / 2, y: hitRect.midY - pillH / 2,
                          width: pillW, height: pillH)
        let r = min(pill.width, pill.height) / 2
        let path = NSBezierPath(roundedRect: pill, xRadius: r, yRadius: r)
        (hovered ? handleHoverColor : handleIdleColor).setFill()
        path.fill()

        // Three vertical dots
        let cx = pill.midX, cy = pill.midY
        (hovered ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setFill()
        for i in -1...1 {
            let dy = CGFloat(i) * handleDotSpacing
            NSBezierPath(ovalIn: NSRect(
                x: cx - handleDotDiameter / 2, y: cy + dy - handleDotDiameter / 2,
                width: handleDotDiameter, height: handleDotDiameter
            )).fill()
        }
    }

    // MARK: - Add Buttons

    private func drawAddRowButton() {
        let rect = addRowButtonRect
        let capsuleR = min(rect.width, rect.height) / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: capsuleR, yRadius: capsuleR)

        addButtonFillColor.setFill()
        path.fill()

        addButtonStrokeColor.setStroke()
        path.lineWidth = 1
        path.lineCapStyle = .round
        path.setLineDash(addButtonDashPattern, count: addButtonDashPattern.count, phase: 0)
        path.stroke()

        drawPlusIcon(in: rect)
    }

    private func drawAddColumnButton() {
        let rect = addColumnButtonRect
        let capsuleR = min(rect.width, rect.height) / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: capsuleR, yRadius: capsuleR)

        addButtonFillColor.setFill()
        path.fill()

        addButtonStrokeColor.setStroke()
        path.lineWidth = 1
        path.lineCapStyle = .round
        path.setLineDash(addButtonDashPattern, count: addButtonDashPattern.count, phase: 0)
        path.stroke()

        drawPlusIcon(in: rect)
    }

    private func drawColumnDividerHighlight(at col: Int) {
        let x = colX(col + 1) - scrollOffset
        NSColor.controlAccentColor.withAlphaComponent(0.3).setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: 0))
        line.line(to: NSPoint(x: x, y: tableHeight))
        line.lineWidth = 2
        line.stroke()
    }

    private func drawColumnDividerIndicator() {
        guard draggingDividerIndex >= 0, draggingDividerIndex < tableData.columns - 1 else { return }
        let x = colX(draggingDividerIndex + 1) - scrollOffset
        NSColor.controlAccentColor.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: 0))
        line.line(to: NSPoint(x: x, y: tableHeight))
        line.lineWidth = 2
        line.stroke()
    }

    private func drawPlusIcon(in rect: NSRect) {
        let cx = rect.midX
        let cy = rect.midY
        let half = addIconSize / 2

        addButtonIconColor.setStroke()
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: cx - half, y: cy))
        plus.line(to: NSPoint(x: cx + half, y: cy))
        plus.move(to: NSPoint(x: cx, y: cy - half))
        plus.line(to: NSPoint(x: cx, y: cy + half))
        plus.lineWidth = 1
        plus.lineCapStyle = .round
        plus.stroke()
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: interactiveRect,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    // MARK: - Cursor Rects

    /// Returns the appropriate cursor for a given window point, or nil if the point
    /// isn't over any handle/divider. Called by the Coordinator's `resizeCursorForPoint`
    /// to prevent NSTextView.mouseMoved from resetting to I-beam.
    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)

        // Column dividers -- resize left/right
        for col in 0..<(tableData.columns - 1) {
            if columnDividerRect(at: col).contains(local) {
                return .resizeLeftRight
            }
        }
        // Column handles -- open hand
        for col in 0..<tableData.columns {
            if columnHandleRect(for: col).contains(local) {
                return .openHand
            }
        }
        // Row handles -- open hand (uses rowHandleRect, not the wider hit zone)
        for row in 0..<tableData.rows {
            if rowHandleRect(for: row).contains(local) {
                return .openHand
            }
        }
        // Add buttons -- pointing hand
        if addRowButtonRect.contains(local) || addColumnButtonViewRect.contains(local) {
            return .pointingHand
        }
        return nil
    }

    override func resetCursorRects() {
        for col in 0..<(tableData.columns - 1) {
            addCursorRect(columnDividerRect(at: col), cursor: .resizeLeftRight)
        }
        for col in 0..<tableData.columns {
            addCursorRect(columnHandleRect(for: col), cursor: .openHand)
        }
        for row in 0..<tableData.rows {
            addCursorRect(rowHandleRect(for: row), cursor: .openHand)
        }
        addCursorRect(addRowButtonRect, cursor: .pointingHand)
        addCursorRect(addColumnButtonViewRect, cursor: .pointingHand)
    }

    // MARK: - Mouse Events

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isDraggingDivider {
            NSCursor.resizeLeftRight.set()
        } else if isDraggingRow || isDraggingColumn {
            NSCursor.closedHand.set()
        } else if isHoveringDivider {
            NSCursor.resizeLeftRight.set()
        } else if hoveredColumnHandle != nil || hoveredRowHandle != nil {
            NSCursor.openHand.set()
        } else if isHoveringAddRow || isHoveringAddColumn {
            NSCursor.pointingHand.set()
        } else {
            for col in 0..<tableData.columns {
                if columnHandleRect(for: col).contains(point) {
                    NSCursor.openHand.set(); return
                }
            }
            for row in 0..<tableData.rows {
                if rowHandleHitZone(for: row).contains(point) {
                    NSCursor.openHand.set(); return
                }
            }
            for col in 0..<(tableData.columns - 1) {
                if columnDividerRect(at: col).contains(point) {
                    NSCursor.resizeLeftRight.set(); return
                }
            }
            if addRowButtonRect.contains(point) || addColumnButtonViewRect.contains(point) {
                NSCursor.pointingHand.set(); return
            }
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHoverState(at: point)
        updateCursor()
    }

    override func mouseExited(with event: NSEvent) {
        hoveredColumnHandle = nil
        hoveredRowHandle = nil
        hoveredBodyRow = nil
        hoveredBodyColumn = nil
        isHoveringAddRow = false
        isHoveringAddColumn = false
        isHoveringDivider = false
        hoveredDividerIndex = -1
        NSCursor.arrow.set()
        needsDisplay = true
    }

    private func updateHoverState(at point: NSPoint) {
        var newCol: Int?
        var newRow: Int?
        var newAddRow = false
        var newAddCol = false
        var newDivider = false
        var newDividerIdx = -1

        // Column dividers (between columns, inside the table body)
        for col in 0..<(tableData.columns - 1) {
            if columnDividerRect(at: col).contains(point) {
                newDivider = true
                newDividerIdx = col
                break
            }
        }

        // Column handles (above table)
        if !newDivider {
            for col in 0..<tableData.columns {
                if columnHandleRect(for: col).contains(point) {
                    newCol = col; break
                }
            }
        }

        // Row handles (left of table)
        if !newDivider {
            for row in 0..<tableData.rows {
                if rowHandleHitZone(for: row).contains(point) {
                    newRow = row; break
                }
            }
        }

        // + buttons
        if !newDivider {
            if addRowButtonRect.contains(point) { newAddRow = true }
            if addColumnButtonViewRect.contains(point) { newAddCol = true }
        }

        // Track which row/column the mouse is in (for handle visibility)
        var newBodyRow: Int?
        var newBodyCol: Int?
        if !newDivider && !newAddRow && !newAddCol {
            if let cell = cellAt(point: point) {
                newBodyRow = cell.row
                newBodyCol = cell.column
            }
        }
        if let col = newCol { newBodyCol = col }
        if let row = newRow { newBodyRow = row }

        let changed = newCol != hoveredColumnHandle || newRow != hoveredRowHandle
            || newAddRow != isHoveringAddRow || newAddCol != isHoveringAddColumn
            || newDivider != isHoveringDivider || newDividerIdx != hoveredDividerIndex
            || newBodyRow != hoveredBodyRow || newBodyCol != hoveredBodyColumn

        if changed {
            hoveredColumnHandle = newCol
            hoveredRowHandle = newRow
            isHoveringAddRow = newAddRow
            isHoveringAddColumn = newAddCol
            isHoveringDivider = newDivider
            hoveredDividerIndex = newDividerIdx
            hoveredBodyRow = newBodyRow
            hoveredBodyColumn = newBodyCol
            needsDisplay = true
        }

        updateCursor()
    }

    private func updateCursor() {
        if isDraggingDivider || isHoveringDivider {
            NSCursor.resizeLeftRight.set()
        } else if isDraggingRow || isDraggingColumn {
            NSCursor.closedHand.set()
        } else if hoveredColumnHandle != nil || hoveredRowHandle != nil {
            NSCursor.openHand.set()
        } else if isHoveringAddRow || isHoveringAddColumn {
            NSCursor.pointingHand.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Column divider resize
        var dividerIdx = isHoveringDivider ? hoveredDividerIndex : -1
        if dividerIdx < 0 {
            for col in 0..<(tableData.columns - 1) {
                if columnDividerRect(at: col).contains(point) { dividerIdx = col; break }
            }
        }
        if dividerIdx >= 0 {
            if event.clickCount == 2 {
                // Double-click: reset all columns to default width
                tableData.columnWidths = Array(repeating: NoteTableData.defaultColumnWidth, count: tableData.columns)
                onDataChanged?(tableData)
                needsDisplay = true
                return
            }
            isDraggingDivider = true
            draggingDividerIndex = dividerIdx
            dividerStartX = point.x
            dividerStartWidths = tableData.columnWidths
            NSCursor.resizeLeftRight.set()
            return
        }

        // Column handle -> start drag
        var colToMove: Int?
        if let col = hoveredColumnHandle {
            colToMove = col
        } else {
            for col in 0..<tableData.columns {
                if columnHandleRect(for: col).contains(point) { colToMove = col; break }
            }
        }
        if let col = colToMove {
            isDraggingColumn = true
            dragSourceIndex = col
            dragStartPos = point.x
            dragCurrentPos = point.x
            NSCursor.closedHand.set()
            return
        }

        // Row handle -> start drag
        var rowToMove: Int?
        if let row = hoveredRowHandle {
            rowToMove = row
        } else {
            for row in 0..<tableData.rows {
                if rowHandleHitZone(for: row).contains(point) { rowToMove = row; break }
                }
        }
        if let row = rowToMove {
            isDraggingRow = true
            dragSourceIndex = row
            dragStartPos = point.y
            dragCurrentPos = point.y
            NSCursor.closedHand.set()
            return
        }

        // + buttons
        if addRowButtonRect.contains(point) {
            tableData.addRow()
            onDataChanged?(tableData)
            return
        }
        if addColumnButtonViewRect.contains(point) {
            tableData.addColumn()
            onDataChanged?(tableData)
            return
        }

        // Cell click -> pending edit
        if let cell = cellAt(point: point) {
            pendingEdit = cell
            mouseDownPoint = point
            return
        }

        parentTextView?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isDraggingDivider {
            let delta = point.x - dividerStartX
            let idx = draggingDividerIndex
            guard idx >= 0, idx < dividerStartWidths.count else { return }
            // Only adjust the left column's width
            let newWidth = max(minColumnWidth, dividerStartWidths[idx] + delta)
            tableData.columnWidths[idx] = newWidth
            onDataChanged?(tableData)
            NSCursor.resizeLeftRight.set()
            needsDisplay = true
            return
        }

        if isDraggingRow {
            dragCurrentPos = point.y
            NSCursor.closedHand.set()
            needsDisplay = true
            return
        }
        if isDraggingColumn {
            dragCurrentPos = point.x
            NSCursor.closedHand.set()
            needsDisplay = true
            return
        }

        if isDraggingCell {
            dragCellMousePos = point
            needsDisplay = true
            return
        }

        // Check if pending edit should convert to cell drag
        if let cell = pendingEdit {
            let dx = point.x - mouseDownPoint.x
            let dy = point.y - mouseDownPoint.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist > dragThreshold {
                pendingEdit = nil
                isDraggingCell = true
                dragCellSource = cell
                dragCellMousePos = point
                NSCursor.closedHand.set()
                needsDisplay = true
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingDivider {
            isDraggingDivider = false
            draggingDividerIndex = -1
            dividerStartWidths = []
            NSCursor.arrow.set()
            needsDisplay = true
            return
        }

        if isDraggingRow {
            let target = dragTargetIndex(isRow: true)
            let dest = target > dragSourceIndex ? target - 1 : target
            if dest != dragSourceIndex && dest >= 0 && dest < tableData.rows {
                tableData.moveRow(from: dragSourceIndex, to: dest)
                onDataChanged?(tableData)
            }
            isDraggingRow = false
            dragSourceIndex = -1
            NSCursor.arrow.set()
            needsDisplay = true
            return
        }

        if isDraggingColumn {
            let target = dragTargetIndex(isRow: false)
            let dest = target > dragSourceIndex ? target - 1 : target
            if dest != dragSourceIndex && dest >= 0 && dest < tableData.columns {
                tableData.moveColumn(from: dragSourceIndex, to: dest)
                onDataChanged?(tableData)
            }
            isDraggingColumn = false
            dragSourceIndex = -1
            NSCursor.arrow.set()
            needsDisplay = true
            return
        }

        if isDraggingCell {
            if let src = dragCellSource, let target = cellAt(point: dragCellMousePos),
               !(target.row == src.row && target.column == src.column) {
                let srcText = tableData.cells[src.row][src.column]
                let dstText = tableData.cells[target.row][target.column]
                tableData.updateCell(row: src.row, column: src.column, text: dstText)
                tableData.updateCell(row: target.row, column: target.column, text: srcText)
                onDataChanged?(tableData)
            }
            isDraggingCell = false
            dragCellSource = nil
            NSCursor.arrow.set()
            needsDisplay = true
            return
        }

        // Pending edit -> begin editing
        if let cell = pendingEdit {
            pendingEdit = nil
            beginEditing(row: cell.row, column: cell.column)
            return
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let col = hoveredColumnHandle {
            showColumnMenu(for: col, at: event); return
        } else {
            for col in 0..<tableData.columns {
                if columnHandleRect(for: col).contains(point) {
                    showColumnMenu(for: col, at: event); return
                }
            }
        }
        if let row = hoveredRowHandle {
            showRowMenu(for: row, at: event); return
        } else {
            for row in 0..<tableData.rows {
                if rowHandleHitZone(for: row).contains(point) {
                    showRowMenu(for: row, at: event); return
                }
            }
        }

        if let cell = cellAt(point: point) {
            contextRowIndex = cell.row
            contextColumnIndex = cell.column
            if let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
            return
        }

        super.rightMouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if needsHorizontalScroll && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            scrollOffset -= event.scrollingDeltaX
            clampScrollOffset()
            updateShadowPath()
            needsDisplay = true
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Context Menus

    private func showColumnMenu(for column: Int, at event: NSEvent) {
        contextColumnIndex = column
        let menu = NSMenu()
        let addBefore = menu.addItem(withTitle: "Add Column Before", action: #selector(addColumnBefore(_:)), keyEquivalent: "")
        addBefore.target = self
        let addAfter = menu.addItem(withTitle: "Add Column After", action: #selector(addColumnAfter(_:)), keyEquivalent: "")
        addAfter.target = self
        if tableData.columns > 1 {
            menu.addItem(.separator())
            let del = menu.addItem(withTitle: "Delete Column", action: #selector(deleteColumn(_:)), keyEquivalent: "")
            del.target = self
        }
        menu.addItem(.separator())
        let delTable = menu.addItem(withTitle: "Delete Table", action: #selector(deleteTable(_:)), keyEquivalent: "")
        delTable.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func showRowMenu(for row: Int, at event: NSEvent) {
        contextRowIndex = row
        let menu = NSMenu()
        let addAbove = menu.addItem(withTitle: "Add Row Above", action: #selector(addRowAbove(_:)), keyEquivalent: "")
        addAbove.target = self
        let addBelow = menu.addItem(withTitle: "Add Row Below", action: #selector(addRowBelow(_:)), keyEquivalent: "")
        addBelow.target = self
        if tableData.rows > 1 {
            menu.addItem(.separator())
            let del = menu.addItem(withTitle: "Delete Row", action: #selector(deleteRow(_:)), keyEquivalent: "")
            del.target = self
        }
        menu.addItem(.separator())
        let delTable = menu.addItem(withTitle: "Delete Table", action: #selector(deleteTable(_:)), keyEquivalent: "")
        delTable.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()

        if let cell = cellAt(point: point) {
            contextRowIndex = cell.row
            contextColumnIndex = cell.column
        }

        let addAbove = menu.addItem(withTitle: "Add Row Above", action: #selector(addRowAbove(_:)), keyEquivalent: "")
        addAbove.target = self
        let addBelow = menu.addItem(withTitle: "Add Row Below", action: #selector(addRowBelow(_:)), keyEquivalent: "")
        addBelow.target = self
        menu.addItem(.separator())
        let addColBefore = menu.addItem(withTitle: "Add Column Before", action: #selector(addColumnBefore(_:)), keyEquivalent: "")
        addColBefore.target = self
        let addColAfter = menu.addItem(withTitle: "Add Column After", action: #selector(addColumnAfter(_:)), keyEquivalent: "")
        addColAfter.target = self
        if tableData.rows > 1 {
            menu.addItem(.separator())
            let del = menu.addItem(withTitle: "Delete Row", action: #selector(deleteRow(_:)), keyEquivalent: "")
            del.target = self
        }
        if tableData.columns > 1 {
            let del = menu.addItem(withTitle: "Delete Column", action: #selector(deleteColumn(_:)), keyEquivalent: "")
            del.target = self
        }
        menu.addItem(.separator())
        let delTable = menu.addItem(withTitle: "Delete Table", action: #selector(deleteTable(_:)), keyEquivalent: "")
        delTable.target = self

        return menu
    }

    // MARK: - Menu Actions

    @objc private func addRowAbove(_ sender: Any?) {
        tableData.addRow(at: contextRowIndex)
        onDataChanged?(tableData)
    }

    @objc private func addRowBelow(_ sender: Any?) {
        tableData.addRow(at: contextRowIndex + 1)
        onDataChanged?(tableData)
    }

    @objc private func addColumnBefore(_ sender: Any?) {
        tableData.addColumn(at: contextColumnIndex)
        onDataChanged?(tableData)
    }

    @objc private func addColumnAfter(_ sender: Any?) {
        tableData.addColumn(at: contextColumnIndex + 1)
        onDataChanged?(tableData)
    }

    @objc private func deleteRow(_ sender: Any?) {
        if tableData.rows <= 1 { onDeleteTable?() }
        else { tableData.deleteRow(at: contextRowIndex); onDataChanged?(tableData) }
    }

    @objc private func deleteColumn(_ sender: Any?) {
        if tableData.columns <= 1 { onDeleteTable?() }
        else { tableData.deleteColumn(at: contextColumnIndex); onDataChanged?(tableData) }
    }

    @objc private func deleteTable(_ sender: Any?) {
        onDeleteTable?()
    }

    // MARK: - Cell Editing

    private func beginEditing(row: Int, column: Int) {
        endEditing()
        editingCell = (row, column)

        let rect = visibleCellRect(row: row, column: column).insetBy(dx: cellPaddingH, dy: cellPaddingV)
        let field = NSTextField(frame: rect)
        field.stringValue = tableData.cells[row][column]
        field.font = NSFont.systemFont(ofSize: 13, weight: row == 0 ? .semibold : .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.target = self
        field.action = #selector(cellEditingDone(_:))

        addSubview(field)
        editField = field
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    private func endEditing() {
        guard let field = editField, let cell = editingCell else { return }
        let newValue = field.stringValue
        if tableData.cells[cell.row][cell.column] != newValue {
            tableData.updateCell(row: cell.row, column: cell.column, text: newValue)
            onDataChanged?(tableData)
        }
        field.removeFromSuperview()
        editField = nil
        editingCell = nil
        needsDisplay = true
    }

    @objc private func cellEditingDone(_ sender: NSTextField) {
        endEditing()
        window?.makeFirstResponder(parentTextView)
    }

    private func navigateToCell(row: Int, column: Int) {
        endEditing()
        var targetRow = row
        var targetCol = column

        // Wrap forward
        if targetCol >= tableData.columns {
            targetCol = 0
            targetRow += 1
        }
        // Wrap backward
        if targetCol < 0 {
            targetCol = tableData.columns - 1
            targetRow -= 1
        }

        // Add new row at the BOTTOM if we go past the last row
        if targetRow >= tableData.rows {
            tableData.addRow()
            onDataChanged?(tableData)
            targetRow = tableData.rows - 1
            targetCol = 0
        }

        if targetRow < 0 {
            window?.makeFirstResponder(parentTextView)
            return
        }

        beginEditing(row: targetRow, column: targetCol)
    }
}

// MARK: - NSTextFieldDelegate

extension NoteTableOverlayView: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let cell = editingCell else { return false }

        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            navigateToCell(row: cell.row, column: cell.column + 1)
            return true
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            navigateToCell(row: cell.row, column: cell.column - 1)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            navigateToCell(row: cell.row + 1, column: cell.column)
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            navigateToCell(row: cell.row - 1, column: cell.column)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            navigateToCell(row: cell.row + 1, column: cell.column)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            window?.makeFirstResponder(parentTextView)
            return true
        }

        return false
    }
}
