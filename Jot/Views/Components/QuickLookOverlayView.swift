//
//  QuickLookOverlayView.swift
//  Jot
//
//  Custom Quick Look preview — window-relative sizing, PDFKit rendering,
//  multi-page counter, and scrolling only when content exceeds one page.
//

import AppKit
import PDFKit
import SwiftUI

struct QuickLookOverlayView: View {
    let notes: [Note]
    let format: NoteExportFormat
    let onDismiss: () -> Void

    @State private var pdfDocument: PDFDocument?
    @State private var rawContent: String?
    @State private var isLoading = true
    @State private var currentPage: Int = 1
    @State private var pageCount: Int = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()

                panelView(in: geometry.size)

                Button("") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .frame(width: 0, height: 0)
                    .hidden()
            }
            // Dismiss lives on the ZStack (parent). The panel child's onTapGesture {}
            // wins via SwiftUI child-over-parent priority, blocking dismiss inside the panel.
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
        }
        .task { await loadContent() }
    }

    // MARK: - Panel

    private func panelView(in containerSize: CGSize) -> some View {
        let sizes = computeSizes(containerSize)
        return VStack(spacing: 8) {
            headerView
            previewContent(previewWidth: sizes.previewWidth, previewHeight: sizes.previewHeight)
        }
        .padding(12)
        .frame(width: sizes.panelWidth, height: sizes.panelHeight)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 50, x: 0, y: 20)
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
        // Consume taps inside the panel so they don't fall through to the backdrop dismiss
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onTapGesture {}
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 0) {
            Text("Quick look")
                .font(FontManager.heading(size: 11, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(Color("PrimaryTextColor"))

            if pageCount > 1 {
                Spacer().frame(width: 8)
                Circle()
                    .fill(Color("TertiaryTextColor"))
                    .frame(width: 2, height: 2)
                Spacer().frame(width: 8)
                Text("\(currentPage) of \(pageCount) pages")
                    .font(FontManager.heading(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color("SecondaryTextColor"))
                    .animation(.jotSpring, value: currentPage)
                    .contentTransition(.numericText())
            }

            Spacer()

            Button { onDismiss() } label: {
                Image("IconCircleX")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color("SecondaryTextColor"))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .subtleHoverScale(1.1)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Preview Content

    @ViewBuilder
    private func previewContent(previewWidth: CGFloat, previewHeight: CGFloat) -> some View {
        if isLoading {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color("SurfaceElevatedColor"))
                .frame(width: previewWidth, height: previewHeight)
                .shimmering(active: true)
        } else if format == .pdf, let doc = pdfDocument {
            PDFViewRepresentable(document: doc, currentPage: $currentPage)
                .frame(width: previewWidth, height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        } else if let raw = rawContent {
            RawTextRepresentable(text: raw)
                .frame(width: previewWidth, height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color("SurfaceElevatedColor"))
                .frame(width: previewWidth, height: previewHeight)
        }
    }

    // MARK: - Sizing

    private struct PanelSizes {
        let panelWidth: CGFloat
        let panelHeight: CGFloat
        let previewWidth: CGFloat
        let previewHeight: CGFloat
    }

    /// Sizes the panel so exactly one US Letter page is fully visible without scrolling.
    /// Multi-page PDFs scroll within the same frame.
    private func computeSizes(_ containerSize: CGSize) -> PanelSizes {
        // US Letter: 612 × 792 pts
        let letterAspect: CGFloat = 612.0 / 792.0

        // Real VStack overhead: top padding (12) + header height (~18) + VStack gap (8) + bottom padding (12) = 50
        let fixedVerticalOverhead: CGFloat = 50

        // PDFView adds ~8px internal margin on top and bottom around each page.
        // Compute previewWidth so the rendered page (margins included) exactly fills previewHeight.
        // Formula: renderedHeight = (previewWidth / 612) * 792 + pdfMargins = previewHeight
        // → previewWidth = (previewHeight - pdfMargins) * letterAspect
        let pdfViewVerticalMargins: CGFloat = 16

        let maxPanelHeight = containerSize.height * 0.92
        let maxPanelWidth = containerSize.width * 0.88

        let previewHeight = maxPanelHeight - fixedVerticalOverhead

        // Width sized to make the PDF page exactly fit previewHeight (accounting for PDFView margins)
        var previewWidth = (previewHeight - pdfViewVerticalMargins) * letterAspect

        // Clamp to max panel width
        let maxPreviewWidth = maxPanelWidth - 24 // 12px padding × 2
        if previewWidth > maxPreviewWidth {
            previewWidth = maxPreviewWidth
        }

        let panelWidth = previewWidth + 24
        let panelHeight = previewHeight + fixedVerticalOverhead

        return PanelSizes(
            panelWidth: panelWidth,
            panelHeight: panelHeight,
            previewWidth: previewWidth,
            previewHeight: previewHeight
        )
    }

    // MARK: - Content Loading

    private func loadContent() async {
        guard let note = notes.first else {
            isLoading = false
            return
        }

        switch format {
        case .pdf:
            if let data = await NoteExportService.shared.buildPDFData(notes: notes),
               let doc = PDFDocument(data: data) {
                pdfDocument = doc
                pageCount = doc.pageCount
            }
        case .markdown:
            rawContent = NoteExportService.shared.buildMarkdownString(notes: notes)
        case .html:
            rawContent = NoteExportService.shared.buildHTMLString(notes: notes, title: note.title)
        }

        isLoading = false
    }
}

// MARK: - Raw Text Representable

/// Scrollable read-only NSTextView — shows raw file output (Markdown/HTML source).
private struct RawTextRepresentable: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        // NSTextView.scrollableTextView() is unreliable in SwiftUI — the text container
        // gets zero-width layout before bounds are known, so text never renders.
        // Manual construction gives full control over sizing and background.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .white
        scrollView.drawsBackground = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        textView.isEditable = false
        textView.isSelectable = true
        // White paper background regardless of mode — matches PDF preview appearance.
        // labelColor is near-white in dark mode, so pin text to black on white.
        textView.backgroundColor = .white
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textColor = .black
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Keep container width locked to scroll view width so lines wrap correctly
        let width = max(nsView.contentSize.width - 40, 1)
        textView.textContainer?.containerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
    }
}

// MARK: - PDF View Representable

private struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = FillWidthPDFView()
        pdfView.document = document
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = false
        pdfView.minScaleFactor = 0.1
        pdfView.maxScaleFactor = 10.0
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = false
        pdfView.backgroundColor = .white

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}

    final class Coordinator: NSObject {
        var parent: PDFViewRepresentable

        init(_ parent: PDFViewRepresentable) { self.parent = parent }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let index = pdfView.document?.index(for: page) else { return }
            DispatchQueue.main.async {
                self.parent.currentPage = index + 1
            }
        }
    }
}

// MARK: - Fill-Width PDFView

/// PDFView subclass that recalculates scaleFactor on every layout pass so the
/// page always fills the available width — no horizontal gutters.
private final class FillWidthPDFView: PDFView {
    override func layout() {
        super.layout()
        guard let page = document?.page(at: 0), bounds.width > 0 else { return }
        let pageWidth = page.bounds(for: .mediaBox).width
        guard pageWidth > 0 else { return }
        scaleFactor = bounds.width / pageWidth
    }
}
