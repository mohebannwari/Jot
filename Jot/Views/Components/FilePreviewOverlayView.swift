//
//  FilePreviewOverlayView.swift
//  Jot
//
//  NSView overlay for extracted file previews.
//  Follows the CodeBlockOverlayView / CalloutOverlayView pattern:
//  reserves space via CalloutSizeAttachmentCell, renders via NSHostingView.
//

import SwiftUI

final class FilePreviewOverlayView: NSView {

    // MARK: - Data

    var storedFilename: String
    var originalFilename: String
    var typeIdentifier: String
    var displayLabel: String
    var viewMode: FileViewMode
    var currentContainerWidth: CGFloat = 400

    weak var parentTextView: NSTextView?

    // MARK: - Callbacks

    var onViewModeChanged: ((FileViewMode) -> Void)?
    var onDelete: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onDataChanged: (() -> Void)?

    // MARK: - Hosting

    private var hostingView: NSHostingView<AnyView>?

    // MARK: - Init

    init(storedFilename: String, originalFilename: String, typeIdentifier: String,
         displayLabel: String, viewMode: FileViewMode, containerWidth: CGFloat) {
        self.storedFilename = storedFilename
        self.originalFilename = originalFilename
        self.typeIdentifier = typeIdentifier
        self.displayLabel = displayLabel
        self.viewMode = viewMode
        self.currentContainerWidth = containerWidth
        super.init(frame: .zero)
        rebuildHostingView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FilePreviewOverlayView does not support init(coder:)")
    }

    // MARK: - Event Handling

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return super.hitTest(point) }
        let local = convert(point, from: sv)
        guard bounds.contains(local) else { return nil }
        // hitTest expects point in the receiver's superview coordinate system
        // For our subviews, their superview is self, so pass local (our coordinate space)
        for sub in subviews.reversed() {
            if let hit = sub.hitTest(local) { return hit }
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        // Consume to prevent click-through to text view
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        hostingView?.frame = bounds
    }

    // MARK: - Rebuild

    func rebuildHostingView() {
        hostingView?.removeFromSuperview()

        let content = FilePreviewContent(
            storedFilename: storedFilename,
            originalFilename: originalFilename,
            typeIdentifier: typeIdentifier,
            displayLabel: displayLabel,
            viewMode: viewMode,
            containerWidth: currentContainerWidth,
            onViewModeChanged: { [weak self] mode in
                self?.onViewModeChanged?(mode)
            },
            onRename: { [weak self] newName in
                self?.originalFilename = newName
                self?.onRename?(newName)
                self?.rebuildHostingView()
            },
            onCopy: { [weak self] in
                self?.copyFileToPasteboard()
            },
            onDelete: { [weak self] in
                self?.onDelete?()
            },
            onOpenInApp: { [weak self] in
                self?.openInDefaultApp()
            }
        )

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = bounds
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        hostingView = hosting
    }

    // MARK: - Actions

    private func copyFileToPasteboard() {
        guard let fileURL = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([fileURL as NSURL])
    }

    private func openInDefaultApp() {
        guard let fileURL = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else { return }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(fileURL, configuration: config, completionHandler: nil)
    }

    // MARK: - Height Calculation

    struct FileAttachmentInfo {
        let storedFilename: String
        let originalFilename: String
        let typeIdentifier: String
        let displayLabel: String
        let imageAspectRatio: CGFloat?
        let pdfPageAspectRatio: CGFloat?

        init(storedFilename: String, originalFilename: String, typeIdentifier: String,
             displayLabel: String, imageAspectRatio: CGFloat? = nil, pdfPageAspectRatio: CGFloat? = nil) {
            self.storedFilename = storedFilename
            self.originalFilename = originalFilename
            self.typeIdentifier = typeIdentifier
            self.displayLabel = displayLabel
            self.imageAspectRatio = imageAspectRatio
            self.pdfPageAspectRatio = pdfPageAspectRatio
        }
    }

    static func heightForData(_ metadata: Any, viewMode: FileViewMode, width: CGFloat) -> CGFloat {
        // Layout budget matching FilePreviewContent body structure:
        //   VStack(spacing: 8) { header.padding(.top,12) + content.padding(.bottom,12) }
        //   + glass modifier overhead (~6pt)
        let topPad: CGFloat = 12
        let bottomPad: CGFloat = 12
        let gap: CGFloat = 8          // VStack spacing between header and content
        let headerHeight: CGFloat = 20 // Label-5 line height (14pt) + vertical hit area
        let glassOverhead: CGFloat = 6 // thinLiquidGlass internal padding (~3pt each side)

        let typeIdentifier: String
        let imageAspectRatio: CGFloat?
        let pdfPageAspectRatio: CGFloat?
        if let meta = metadata as? FileAttachmentInfo {
            typeIdentifier = meta.typeIdentifier
            imageAspectRatio = meta.imageAspectRatio
            pdfPageAspectRatio = meta.pdfPageAspectRatio
        } else {
            let mirror = Mirror(reflecting: metadata)
            typeIdentifier = mirror.children.first(where: { $0.label == "typeIdentifier" })?.value as? String ?? "public.data"
            imageAspectRatio = nil
            pdfPageAspectRatio = nil
        }
        let category = FileCategory.classify(typeIdentifier)
        let contentHeight: CGFloat
        switch category {
        case .pdf:
            let contentW = width - 24
            let isFull = contentW > 500
            let peekAmount: CGFloat = 24
            let pdfGap: CGFloat = 8
            let pageW: CGFloat = isFull
                ? (contentW - 2 * pdfGap - peekAmount) / 2
                : contentW - pdfGap - peekAmount
            if let ar = pdfPageAspectRatio, ar > 0 {
                contentHeight = pageW / ar
            } else {
                contentHeight = 483
            }
        case .image:
            let contentW = width - 24 // 12pt padding each side (matches FilePreviewContent.contentWidth)
            if let ar = imageAspectRatio, ar > 0 {
                contentHeight = contentW / ar
            } else {
                contentHeight = 400
            }
        case .audio:    contentHeight = 80
        case .video:    contentHeight = 300
        case .text:     contentHeight = 200
        case .office:   contentHeight = 200
        case .other:    contentHeight = 200
        }
        return topPad + headerHeight + gap + contentHeight + bottomPad + glassOverhead
    }
}
