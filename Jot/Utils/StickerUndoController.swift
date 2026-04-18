//
//  StickerUndoController.swift
//  Jot
//
//  Bridges sticker `[Sticker]` mutations onto the note editor's UndoManager so
//  Cmd+Z interleaves with rich-text undo (note detail pane undo plan).
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class StickerUndoController: ObservableObject {

    /// The rich text editor's undo manager (same stack as Cmd+Z in the note body).
    var noteEditorUndoManager: UndoManager?

    /// Invoked after every sticker mutation (undo, redo, or direct apply) so SwiftData autosave runs.
    var onAfterMutation: () -> Void = {}

    private var stickersBinding: Binding<[Sticker]>?

    func bind(stickers: Binding<[Sticker]>) {
        stickersBinding = stickers
    }

    /// Registers undo from `oldStickers` to `newStickers` and assigns `newStickers` to the binding.
    func record(oldStickers: [Sticker], newStickers: [Sticker], actionName: String) {
        guard oldStickers != newStickers else { return }
        guard let binding = stickersBinding else { return }
        guard let undoManager = noteEditorUndoManager else {
            binding.wrappedValue = newStickers
            onAfterMutation()
            return
        }
        undoManager.registerUndo(withTarget: self) { controller in
            controller.record(oldStickers: newStickers, newStickers: oldStickers, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        binding.wrappedValue = newStickers
        onAfterMutation()
    }
}
