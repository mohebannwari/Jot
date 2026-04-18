//
//  TodoEditorRepresentable+CoordinatorUndo.swift
//  Jot
//
//  Central NSUndoManager registration for attachment payload edits that bypass
//  NSTextStorage.replaceCharacters (see note-detail undo plan).
//

import AppKit

extension TodoEditorRepresentable.Coordinator {

    /// Applies `newValue` to the model and registers an undo step that restores `oldValue`.
    /// Recursive registration pairs undo/redo symmetrically (same pattern as TextFormattingManager).
    func applyMutationWithUndo<Value: Equatable>(
        textView: NSTextView,
        actionName: String,
        oldValue: Value,
        newValue: Value,
        apply: @escaping (Value) -> Void
    ) {
        if readOnly {
            apply(newValue)
            return
        }
        guard oldValue != newValue else {
            apply(newValue)
            return
        }
        guard let undoManager = textView.undoManager else {
            apply(newValue)
            return
        }
        undoManager.registerUndo(withTarget: self) { [weak textView] coordinator in
            guard let textView else { return }
            coordinator.applyMutationWithUndo(
                textView: textView,
                actionName: actionName,
                oldValue: newValue,
                newValue: oldValue,
                apply: apply
            )
        }
        undoManager.setActionName(actionName)
        apply(newValue)
    }

    /// After a column-divider drag, register a single undo from the snapshot taken at drag began.
    func finalizeTableColumnResizeUndoIfNeeded(
        textView: NSTextView,
        attachment: NoteTableAttachment,
        applyTableData: @escaping (NoteTableData) -> Void
    ) {
        if readOnly { return }
        let key = ObjectIdentifier(attachment)
        guard let before = pendingTableColumnResizeSnapshot.removeValue(forKey: key) else { return }
        let after = attachment.tableData
        guard before != after else { return }
        applyMutationWithUndo(
            textView: textView,
            actionName: "Resize Table Column",
            oldValue: before,
            newValue: after,
            apply: applyTableData
        )
    }

    func finalizeCodeBlockWidthResizeUndoIfNeeded(
        textView: NSTextView,
        attachment: NoteCodeBlockAttachment,
        applyCodeBlockData: @escaping (CodeBlockData) -> Void
    ) {
        if readOnly { return }
        let key = ObjectIdentifier(attachment)
        guard let before = pendingCodeBlockWidthResizeSnapshot.removeValue(forKey: key) else { return }
        let after = attachment.codeBlockData
        guard before != after else { return }
        applyMutationWithUndo(
            textView: textView,
            actionName: "Resize Code Block",
            oldValue: before,
            newValue: after,
            apply: applyCodeBlockData
        )
    }

    func finalizeCalloutWidthResizeUndoIfNeeded(
        textView: NSTextView,
        attachment: NoteCalloutAttachment,
        applyCalloutData: @escaping (CalloutData) -> Void
    ) {
        if readOnly { return }
        let key = ObjectIdentifier(attachment)
        guard let before = pendingCalloutWidthResizeSnapshot.removeValue(forKey: key) else { return }
        let after = attachment.calloutData
        guard before != after else { return }
        applyMutationWithUndo(
            textView: textView,
            actionName: "Resize Callout",
            oldValue: before,
            newValue: after,
            apply: applyCalloutData
        )
    }

    func finalizeTabsWidthResizeUndoIfNeeded(
        textView: NSTextView,
        attachment: NoteTabsAttachment,
        applyTabsData: @escaping (TabsContainerData) -> Void
    ) {
        if readOnly { return }
        let key = ObjectIdentifier(attachment)
        guard let before = pendingTabsWidthResizeSnapshot.removeValue(forKey: key) else { return }
        let after = attachment.tabsData
        guard before != after else { return }
        applyMutationWithUndo(
            textView: textView,
            actionName: "Resize Tabs Block",
            oldValue: before,
            newValue: after,
            apply: applyTabsData
        )
    }

    func finalizeTabsHeightResizeUndoIfNeeded(
        textView: NSTextView,
        attachment: NoteTabsAttachment,
        applyTabsData: @escaping (TabsContainerData) -> Void
    ) {
        if readOnly { return }
        let key = ObjectIdentifier(attachment)
        guard let before = pendingTabsHeightResizeSnapshot.removeValue(forKey: key) else { return }
        let after = attachment.tabsData
        guard before != after else { return }
        applyMutationWithUndo(
            textView: textView,
            actionName: "Resize Tabs Height",
            oldValue: before,
            newValue: after,
            apply: applyTabsData
        )
    }
}
