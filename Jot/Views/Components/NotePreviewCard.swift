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

    private let cardWidth: CGFloat = 300
    private let cardMaxHeight: CGFloat = 250
    private let innerCornerRadius: CGFloat = 22
    private let outerCornerRadius: CGFloat = 24
    private let glassPadding: CGFloat = 2
    private let cardPadding: CGFloat = 16
    private let headerBodyGap: CGFloat = 20
    private let dateToTitleGap: CGFloat = 12
    private let actionIconSize: CGFloat = 18
    private let actionPadding: CGFloat = 8
    private let actionRowGap: CGFloat = 8

    private let borderColor = Color.white.opacity(0.06)

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: note.date)
    }

    /// Strip serialized markup tags from note content for plain-text preview
    private var plainBody: String {
        var text = note.content
        // Remove all [[tag]]...[[/tag]] wrappers, keep inner text
        let tagPattern = #"\[\[/?[^\]]*\]\]"#
        text = text.replacingOccurrences(of: tagPattern, with: "", options: .regularExpression)
        // Remove checkbox markers
        text = text.replacingOccurrences(of: "[x]", with: "")
        text = text.replacingOccurrences(of: "[ ]", with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview content card
            previewContent

            // Options row
            optionsRow
        }
        .frame(width: cardWidth)
        .padding(glassPadding)
        .thinLiquidGlass(in: RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        .onHover { hovering in onHoverChanged?(hovering) }
    }

    // MARK: - Preview Content

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: headerBodyGap) {
            // Header: date + title
            VStack(alignment: .leading, spacing: dateToTitleGap) {
                Text(formattedDate)
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .foregroundColor(Color.white.opacity(0.5))

                Text(note.title)
                    .font(FontManager.heading(size: 32, weight: .medium))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.white)
                    .opacity(isLocked ? 0 : 1)
            }

            // Body text
            if !plainBody.isEmpty {
                Text(plainBody)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.5)
                    .lineSpacing(22 - 16) // line-height 22 with 16pt font
                    .foregroundColor(Color.white.opacity(0.7))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isLocked ? 0 : 1)
            }
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: cardMaxHeight, alignment: .top)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(Color(red: 12/255, green: 10/255, blue: 9/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay {
            if isLocked {
                Image("IconLock")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 40, height: 40)
                    .foregroundColor(.white.opacity(0.3))
            }
        }
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
