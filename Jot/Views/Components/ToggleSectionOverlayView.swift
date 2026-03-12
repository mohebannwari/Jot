//
//  ToggleSectionOverlayView.swift
//  Jot
//

import AppKit

final class ToggleSectionOverlayView: NSView {

    static let minWidth: CGFloat = 200
    var currentContainerWidth: CGFloat = 0

    var data: ToggleSectionData {
        didSet {
            updateAppearance()
            updateContent()
        }
    }

    weak var parentTextView: NSTextView?
    var onDataChanged: ((ToggleSectionData) -> Void)?
    var onWidthChanged: ((CGFloat) -> Void)?

    // ── Metrics ────────────────────────────────────────────────────────
    private let titleHeight: CGFloat = 34
    private let iconSize: CGFloat = 14
    private let contentIndentWidth: CGFloat = 24

    // ── Subviews ───────────────────────────────────────────────────────
    private let titleContainer = _ToggleTitleContainer()
    private let titleField: NSTextField = {
        let tf = NSTextField()
        tf.isBordered = false
        tf.isEditable = false
        tf.isSelectable = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.lineBreakMode = .byTruncatingTail
        tf.usesSingleLineMode = true
        tf.font = .systemFont(ofSize: 15, weight: .medium)
        return tf
    }()
    private let chevronView = NSImageView()
    
    private let contentContainer = NSView()
    private let contentField: NSTextField = {
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
        return tf
    }()

    override var isFlipped: Bool { true }

    // MARK: - Init

    init(data: ToggleSectionData) {
        self.data = data
        super.init(frame: .zero)
        buildView()
        updateAppearance()
        updateContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildView() {
        titleContainer.onSingleClick = { [weak self] in
            guard let self = self, !self.titleField.isEditable else { return }
            self.data.isExpanded.toggle()
            self.onDataChanged?(self.data)
            self.updateAppearance()
            self.layout()
        }
        titleContainer.onDoubleClick = { [weak self] in
            guard let self = self else { return }
            self.titleField.isEditable = true
            self.titleField.isSelectable = true
            
            self.window?.makeFirstResponder(self.titleField)
            
            if let editor = self.titleField.currentEditor() {
                editor.selectAll(nil)
            }
        }
        
        addSubview(titleContainer)
        
        titleField.delegate = self
        titleContainer.addSubview(titleField)
        
        chevronView.imageScaling = .scaleProportionallyUpOrDown
        if let img = NSImage(named: "IconChevronRightMedium") ?? NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            img.isTemplate = true
            chevronView.image = img
        }
        titleContainer.addSubview(chevronView)
        
        addSubview(contentContainer)
        contentContainer.addSubview(contentField)
        contentField.delegate = self
    }

    // MARK: - Appearance

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        // Chevron rotation
        chevronView.wantsLayer = true
        chevronView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        let angle: CGFloat = data.isExpanded ? 90 : 0
        
        // Use CATransform3D for reliable rotation (Z-axis, negative for clockwise in CoreAnimation)
        let cx = iconSize / 2
        let cy = iconSize / 2
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, cx, cy, 0)
        transform = CATransform3DRotate(transform, angle * .pi / 180, 0, 0, -1)
        transform = CATransform3DTranslate(transform, -cx, -cy, 0)
        chevronView.layer?.transform = transform

        let isPlaceholder = data.title == "Toggle section" || data.title.isEmpty
        let textColor: NSColor = isPlaceholder
            ? (isDark ? .white.withAlphaComponent(0.7) : NSColor(srgbRed: 26/255, green: 26/255, blue: 26/255, alpha: 0.7))
            : .labelColor // Full opacity when typed

        titleField.textColor = textColor
        titleField.placeholderAttributedString = NSAttributedString(
            string: "Toggle section",
            attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: textColor]
        )
        
        chevronView.contentTintColor = textColor
        
        let placeholderColor = isDark ? .white.withAlphaComponent(0.3) : NSColor.black.withAlphaComponent(0.3)
        let bodyFont = FontManager.bodyNS(size: ThemeManager.currentBodyFontSize(), weight: .regular)
        
        contentField.font = bodyFont
        contentField.textColor = .labelColor
        contentField.placeholderAttributedString = NSAttributedString(
            string: "Empty toggle...",
            attributes: [.font: bodyFont, .foregroundColor: placeholderColor]
        )

        contentContainer.isHidden = !data.isExpanded
    }

    private func updateContent() {
        if titleField.stringValue != data.title {
            titleField.stringValue = data.title
        }
        if contentField.stringValue != data.content {
            contentField.stringValue = data.content
        }
        needsLayout = true
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let W = bounds.width
        
        let displayTitle = (data.title.isEmpty ? "Toggle section" : data.title)
        let titleAttrString = NSAttributedString(
            string: displayTitle,
            attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium)]
        )
        let titleRect = titleAttrString.boundingRect(
            with: CGSize(width: W - iconSize - 8, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        
        // Use the exact typographic width for chevron placement
        let exactTypographicWidth = ceil(titleRect.width)
        
        // Give the text field frame a slight buffer (to prevent truncation)
        // without pushing the chevron away.
        let actualTitleW = min(W - iconSize - 8, exactTypographicWidth + 6) 
        
        // 1. Title Block (Text FIRST, then Chevron)
        let chevronX = exactTypographicWidth + 4 // Snap chevron to exact text width, not frame width
        
        let titleTotalW = chevronX + iconSize
        titleContainer.frame = CGRect(x: 0, y: 0, width: titleTotalW, height: titleHeight)
        
        titleField.frame = CGRect(x: 0, y: (titleHeight - 20) / 2, width: actualTitleW, height: 20)
        
        let chevronY = (titleHeight - iconSize) / 2
        chevronView.frame = CGRect(x: chevronX, y: chevronY, width: iconSize, height: iconSize)

        // 2. Content Block
        if data.isExpanded {
            let contentY = titleHeight
            let contentH = max(bounds.height - contentY, 20)
            contentContainer.frame = CGRect(x: 0, y: contentY, width: W, height: contentH)
            
            let cfW = max(W - contentIndentWidth, 40)
            contentField.frame = CGRect(x: contentIndentWidth, y: 0, width: cfW, height: contentH)
        }
    }

    // MARK: - Height Calculation

    static func heightForData(_ data: ToggleSectionData, width: CGFloat) -> CGFloat {
        let tHeight: CGFloat = 34
        if !data.isExpanded {
            return tHeight
        }
        
        let indent: CGFloat = 24
        let tw = max(width - indent, 40)
        
        let text = data.content.isEmpty ? "A" : data.content
        let bodyFont = FontManager.bodyNS(size: ThemeManager.currentBodyFontSize(), weight: .regular)
        
        let rect = NSAttributedString(
            string: text,
            attributes: [.font: bodyFont]
        ).boundingRect(
            with: CGSize(width: tw, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return tHeight + max(ceil(rect.height), 20) + 4
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

// MARK: - Interactive Title Container

private final class _ToggleTitleContainer: NSView {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 1 {
            onSingleClick?()
        }
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - NSTextFieldDelegate

extension ToggleSectionOverlayView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField {
            if tf === titleField {
                data.title = tf.stringValue
                updateAppearance() 
                needsLayout = true 
            } else if tf === contentField {
                data.content = tf.stringValue
            }
            onDataChanged?(data)
        }
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf === titleField {
            tf.isEditable = false
            tf.isSelectable = false
            data.title = tf.stringValue
            
            if data.title.isEmpty {
                data.title = "Toggle section"
                tf.stringValue = "Toggle section"
            }
            
            updateAppearance()
            needsLayout = true
            onDataChanged?(data)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === contentField && commandSelector == #selector(NSResponder.insertNewline(_:)) {
            textView.insertNewlineIgnoringFieldEditor(nil)
            data.content = contentField.stringValue
            onDataChanged?(data)
            return true
        } else if control === titleField && commandSelector == #selector(NSResponder.insertNewline(_:)) {
            self.window?.makeFirstResponder(self.parentTextView)
            return true
        }
        return false
    }
}