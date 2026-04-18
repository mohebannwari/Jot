//
//  StickerCanvasOverlay.swift
//  Jot
//
//  Transparent overlay inside the scroll view that renders all stickers.
//  Individual StickerView instances capture their own hits.
//  Clicks on empty space pass through to the text editor below.
//

import SwiftUI

struct StickerCanvasOverlay: View {
    @Binding var stickers: [Sticker]
    @Binding var isPlacingSticker: Bool
    @Binding var selectedStickerID: UUID?
    let onChanged: () -> Void
    /// When set, sticker mutations register on the note editor's `NSUndoManager` (see `StickerUndoController`).
    var recordStickerUndo: ((_ before: [Sticker], _ after: [Sticker], _ actionName: String) -> Void)? = nil

    @State private var editingStickerID: UUID? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Invisible spacer — forces ZStack to fill the overlay's proposed size
            // without capturing any hit events
            Color.clear.allowsHitTesting(false)

            // Placement click-capture overlay (temporary — dismissed after one click)
            if isPlacingSticker {
                placementOverlay
            }

            // Render each sticker at its stored position
            ForEach($stickers) { $sticker in
                stickerNode(sticker: $sticker)
            }
        }
        .onExitCommand {
            if isPlacingSticker {
                isPlacingSticker = false
            }
        }
        .onChange(of: selectedStickerID) { _, newValue in
            if newValue == nil {
                editingStickerID = nil
            }
        }
    }

    // MARK: - Individual Sticker Node

    @ViewBuilder
    private func stickerNode(sticker: Binding<Sticker>) -> some View {
        let s = sticker.wrappedValue
        let isSelected = selectedStickerID == s.id

        StickerView(
            sticker: sticker,
            isSelected: isSelected,
            isEditing: editingBinding(for: s.id),
            onSelect: { selectSticker(s.id) },
            onDelete: { deleteSticker(s.id) },
            onChanged: onChanged,
            getAllStickers: { stickers },
            recordStickerUndo: recordStickerUndo
        )
        .position(x: s.positionX + s.size / 2, y: s.positionY + s.size / 2)
        .zIndex(Double(s.zIndex))
    }

    // MARK: - Placement Overlay

    private var placementOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.crosshair.push() }
                else { NSCursor.pop() }
            }
            .onTapGesture { location in
                placeSticker(at: location)
            }
            .zIndex(1000)
    }

    // MARK: - Actions

    private func placeSticker(at location: CGPoint) {
        let newSticker = Sticker(
            color: .green,
            text: "",
            positionX: max(0, location.x - 100), // center the 200x200 sticker on click, clamped
            positionY: max(0, location.y - 100),
            size: 200,
            fontSize: 12,
            textColorDark: true,
            zIndex: (stickers.map(\.zIndex).max() ?? 0) + 1
        )
        let previous = stickers
        let next = previous + [newSticker]
        if let rec = recordStickerUndo {
            rec(previous, next, "Add Sticker")
        } else {
            stickers = next
            onChanged()
        }
        selectedStickerID = newSticker.id
        editingStickerID = newSticker.id  // immediate text editing
        isPlacingSticker = false
    }

    private func selectSticker(_ id: UUID) {
        selectedStickerID = id
        // Bring to front and normalize z-ordering to keep values small
        if let idx = stickers.firstIndex(where: { $0.id == id }) {
            let maxZ = stickers.map(\.zIndex).max() ?? 0
            if stickers[idx].zIndex < maxZ {
                let previous = stickers
                // Normalize: sort by current zIndex, reassign 0...n, selected gets top
                var next = stickers
                let sorted = next.sorted { $0.zIndex < $1.zIndex }
                for (i, s) in sorted.enumerated() {
                    if let j = next.firstIndex(where: { $0.id == s.id }) {
                        next[j].zIndex = (s.id == id) ? next.count : i
                    }
                }
                if let rec = recordStickerUndo {
                    rec(previous, next, "Reorder Stickers")
                } else {
                    stickers = next
                    onChanged()
                }
            }
        }
    }

    private func deleteSticker(_ id: UUID) {
        let previous = stickers
        let next = stickers.filter { $0.id != id }
        if let rec = recordStickerUndo {
            rec(previous, next, "Remove Sticker")
        } else {
            stickers = next
            onChanged()
        }
        if selectedStickerID == id { selectedStickerID = nil }
        if editingStickerID == id { editingStickerID = nil }
    }

    private func editingBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { editingStickerID == id },
            set: { newValue in
                if newValue {
                    editingStickerID = id
                } else if editingStickerID == id {
                    editingStickerID = nil
                }
            }
        )
    }
}
