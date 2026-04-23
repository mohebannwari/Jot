import SwiftUI

/// Floating undo toast that appears at the bottom of the window
/// after destructive operations. Styled with Liquid Glass capsule.
struct UndoToast: View {
    @EnvironmentObject private var undoToastManager: UndoToastManager

    var body: some View {
        if let toast = undoToastManager.currentToast {
            HStack(spacing: 12) {
                Text(toast.message)
                    .jotUI(FontManager.uiLabel3(weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Button {
                    undoToastManager.performUndo()
                } label: {
                    Text("Undo")
                        .jotUI(FontManager.uiLabel3(weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .thinLiquidGlass(in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
        }
    }
}
