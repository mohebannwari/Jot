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
            onChanged: onChanged
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
        stickers.append(newSticker)
        selectedStickerID = newSticker.id
        editingStickerID = newSticker.id  // immediate text editing
        isPlacingSticker = false
        onChanged()
    }

    private func selectSticker(_ id: UUID) {
        selectedStickerID = id
        // Bring to front and normalize z-ordering to keep values small
        if let idx = stickers.firstIndex(where: { $0.id == id }) {
            let maxZ = stickers.map(\.zIndex).max() ?? 0
            if stickers[idx].zIndex < maxZ {
                // Normalize: sort by current zIndex, reassign 0...n, selected gets top
                let sorted = stickers.sorted { $0.zIndex < $1.zIndex }
                for (i, s) in sorted.enumerated() {
                    if let j = stickers.firstIndex(where: { $0.id == s.id }) {
                        stickers[j].zIndex = (s.id == id) ? stickers.count : i
                    }
                }
                onChanged()
            }
        }
    }

    private func deleteSticker(_ id: UUID) {
        stickers.removeAll { $0.id == id }
        if selectedStickerID == id { selectedStickerID = nil }
        if editingStickerID == id { editingStickerID = nil }
        onChanged()
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
