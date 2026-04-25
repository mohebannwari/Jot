//
//  NotePreviewCard.swift
//  Jot
//
//  Created by Moheb Anwari on 22.03.26.
//

import SwiftUI
import AppKit

struct NotePreviewCard: View {
    let note: Note
    let isPinned: Bool
    let isLocked: Bool
    let onTogglePin: () -> Void
    let onToggleLock: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    var onHoverChanged: ((Bool) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    @State private var cachedSnapshot: NSImage?

    private let cardWidth: CGFloat = 300
    private let cardMaxHeight: CGFloat = 250
    private let innerCornerRadius: CGFloat = 22
    private let outerCornerRadius: CGFloat = 24
    private let glassPadding: CGFloat = 2
    private let actionIconSize: CGFloat = 18
    private let actionPadding: CGFloat = 8
    private let actionRowGap: CGFloat = 8

    private let borderColor = Color.white.opacity(0.06)
    private let cardBackgroundColor = Color("DetailPaneColor")

    /// Whether the preview area has visual content (snapshot or locked icon).
    private var hasPreviewContent: Bool {
        isLocked || cachedSnapshot != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasPreviewContent {
                previewContent
            }
            optionsRow
        }
        .frame(width: cardWidth)
        .padding(glassPadding)
        .thinLiquidGlass(in: RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        .onHover { hovering in onHoverChanged?(hovering) }
        .task(id: note.content) {
            guard !isLocked else { cachedSnapshot = nil; return }
            cachedSnapshot = NoteSnapshotRenderer.render(
                content: note.content,
                width: cardWidth,
                height: cardMaxHeight
            )
        }
    }

    // MARK: - Preview Content

    private var previewContent: some View {
        Group {
            if isLocked {
                Image("IconLock")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 40, height: 40)
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = cachedSnapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: cardWidth, height: cardMaxHeight)
            }
        }
        .frame(width: cardWidth, height: cardMaxHeight)
        .clipShape(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(alignment: .bottom) {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: cardBackgroundColor.opacity(0), location: 0.0),
                    .init(color: cardBackgroundColor.opacity(0.5), location: 0.3),
                    .init(color: cardBackgroundColor.opacity(0.85), location: 0.6),
                    .init(color: cardBackgroundColor, location: 1.0),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: innerCornerRadius,
                    bottomTrailingRadius: innerCornerRadius,
                    style: .continuous
                )
            )
            .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Options Row

    private var optionsRow: some View {
        HStack(spacing: actionRowGap) {
            PreviewActionButton(
                icon: isPinned ? "IconUnpin" : "IconThumbtack",
                iconSize: actionIconSize,
                padding: actionPadding,
                action: onTogglePin
            )
            PreviewActionButton(
                icon: isLocked ? "IconUnlocked" : "IconLock",
                iconSize: actionIconSize,
                padding: actionPadding,
                action: onToggleLock
            )
            PreviewActionButton(
                icon: "IconArchive1",
                iconSize: actionIconSize,
                padding: actionPadding,
                action: onArchive
            )
            PreviewActionButton(
                icon: "delete",
                iconSize: actionIconSize,
                padding: actionPadding,
                action: onDelete
            )
        }
        .padding(actionPadding)
        .macBlockingArrowCursor()
    }
}

// MARK: - Offscreen Snapshot Renderer

/// Renders note content to a bitmap using the same deserialization pipeline
/// as the main editor, then captures the top portion as an NSImage.
/// Caseless enum used as namespace -- avoids NSTextView-in-SwiftUI layout issues.
enum NoteSnapshotRenderer {

    static func render(
        content: String,
        width: CGFloat,
        height: CGFloat
    ) -> NSImage? {
        guard !content.isEmpty else { return nil }

        let binding = Binding.constant(content)
        let rep = TodoEditorRepresentable(
            text: binding,
            colorScheme: .dark,
            focusRequestID: nil,
            editorInstanceID: nil,
            readOnly: true
        )
        let coordinator = rep.makeCoordinator()

        // Build an offscreen NSTextView matching the editor's configuration
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10000))
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: width - 32, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)

        // Force dark appearance to match the preview card background
        textView.appearance = NSAppearance(named: .darkAqua)

        // Deserialize content -- skip overlay creation since the view has no window
        coordinator.configure(with: textView)
        coordinator.applyInitialText(content)

        // Ensure layout is complete
        if let lm = textView.layoutManager, let tc = textView.textContainer {
            lm.ensureLayout(for: tc)
        }

        // Clean up overlays that were created for the detached view
        coordinator.removeAllOverlays()

        // Render only the top `height` pixels to a bitmap
        let captureRect = NSRect(x: 0, y: 0, width: width, height: height)
        guard let bitmapRep = textView.bitmapImageRepForCachingDisplay(in: captureRect) else {
            return nil
        }
        textView.cacheDisplay(in: captureRect, to: bitmapRep)

        let image = NSImage(size: captureRect.size)
        image.addRepresentation(bitmapRep)
        return image
    }
}

// MARK: - Action Button

private struct PreviewActionButton: View {
    let icon: String
    let iconSize: CGFloat
    let padding: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .frame(width: iconSize, height: iconSize)
                .foregroundColor(.primary.opacity(isHovered ? 1.0 : 0.6))
                .padding(padding)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered { NSCursor.pop(); isHovered = false }
        }
    }
}
