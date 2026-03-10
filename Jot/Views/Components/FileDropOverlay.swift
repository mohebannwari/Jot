//
//  FileDropOverlay.swift
//  Jot
//
//  Fullscreen drag-and-drop overlay with tilted format cards.
//  Shown when external files are dragged onto the app window.
//

import SwiftUI

/// Progress state for multi-file import
struct ImportProgress: Equatable {
    var current: Int
    var total: Int
    var currentFilename: String
}

/// Fullscreen overlay shown during file drag-over
struct FileDropOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    private var cardGradientColors: [Color] {
        colorScheme == .dark
            ? [Color(hex: "#e7e5e4"), Color(hex: "#9c9a99")]
            : [Color(hex: "#0c0a09"), Color(hex: "#1c1c1c")]
    }

    private var cardBorderColor: Color {
        colorScheme == .dark
            ? Color(hex: "#b2b2b2")
            : Color(hex: "#2d2d2d")
    }

    private var iconTint: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(spacing: -8) {
                    fileCard(icon: "IconFilePdf", rotation: -15)
                    fileCard(icon: "IconMarkdown", rotation: 0)
                        .zIndex(1)
                    fileCard(icon: "IconWebsite", rotation: 15)
                }

                Text("Drop files here to import")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
    }

    private func fileCard(icon: String, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: cardGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(cardBorderColor, lineWidth: 2)
            )
            .overlay(
                Image(icon)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(iconTint)
            )
            .frame(width: 48, height: 48)
            .rotationEffect(.degrees(rotation))
    }
}

/// Compact progress indicator during multi-file import
struct ImportProgressOverlay: View {
    let progress: ImportProgress

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(progress.current), total: Double(progress.total))
                .tint(.secondary)
                .frame(width: 200)

            Text("Importing \(progress.current) of \(progress.total)...")
                .font(.system(size: 12, weight: .medium))

            Text(progress.currentFilename)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .thinLiquidGlass(in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - AppKit Drop Target

/// NSView-based drag destination that reliably catches file drops across the entire window,
/// bypassing SwiftUI's .onDrop which conflicts with NSTextView's registered drag types.
struct ImportDropTarget: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> ImportDropNSView {
        let view = ImportDropNSView()
        view.onTargetChanged = { targeted in
            DispatchQueue.main.async { isTargeted = targeted }
        }
        view.onDrop = { urls in
            DispatchQueue.main.async { onDrop(urls) }
        }
        return view
    }

    func updateNSView(_ nsView: ImportDropNSView, context: Context) {}
}

/// Transparent NSView that registers for file URL drags and only accepts importable note formats.
final class ImportDropNSView: NSView {
    var onTargetChanged: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    /// Return nil so clicks, scrolls, and mouse events pass through to views beneath.
    /// Drag events still arrive via NSDraggingDestination (registerForDraggedTypes).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func importableURLs(from info: NSDraggingInfo) -> [URL] {
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let objects = info.draggingPasteboard.readObjects(
            forClasses: classes, options: options
        ) as? [URL] else { return [] }
        return objects.filter { NoteImportFormat.from(url: $0) != nil }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = importableURLs(from: sender)
        guard !urls.isEmpty else { return NSDragOperation() }
        onTargetChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = importableURLs(from: sender)
        return urls.isEmpty ? NSDragOperation() : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !importableURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = importableURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onTargetChanged?(false)
        onDrop?(urls)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargetChanged?(false)
    }
}

#Preview("Drop Overlay") {
    FileDropOverlay()
        .frame(width: 400, height: 300)
}

#Preview("Progress") {
    ImportProgressOverlay(progress: ImportProgress(
        current: 3, total: 7, currentFilename: "meeting-notes.md"
    ))
    .frame(width: 400, height: 200)
}
