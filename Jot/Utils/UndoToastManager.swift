import Combine
import SwiftUI

/// Manages a single undo-toast that appears after destructive operations.
/// Only one toast is active at a time -- a new action replaces the previous toast.
@MainActor
final class UndoToastManager: ObservableObject {

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let undoAction: () -> Void
    }

    @Published var currentToast: Toast?

    private var dismissTask: Task<Void, Never>?

    /// Shows a toast with the given message and an undo closure.
    /// Cancels any previous toast and starts a 5-second auto-dismiss timer.
    func show(_ message: String, undoAction: @escaping () -> Void) {
        dismissTask?.cancel()
        withAnimation(.jotSpring) {
            currentToast = Toast(message: message, undoAction: undoAction)
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Executes the undo closure and dismisses the toast.
    func performUndo() {
        guard let toast = currentToast else { return }
        toast.undoAction()
        dismiss()
    }

    /// Dismisses the current toast without performing undo.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.jotSpring) {
            currentToast = nil
        }
    }
}
