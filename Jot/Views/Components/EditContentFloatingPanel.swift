//
//  EditContentFloatingPanel.swift
//  Jot
//
//  Floating liquid glass panel for Edit Content AI results.
//  Anchored above the captured text selection, mirroring FloatingEditToolbar placement.
//

import SwiftUI

struct EditContentFloatingPanel: View {
    let state: AIPanelState
    let onReplace: () -> Void
    let onDismiss: () -> Void
    let onRedo: () -> Void

    var body: some View {
        Group {
            switch state {
            case .loading(.editContent):
                shimmerContent
            case .editPreview(let revised, _, _, _):
                previewContent(revised: revised)
            default:
                EmptyView()
            }
        }
        .padding(8)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onKeyPress(.return) { onReplace(); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
    }

    // MARK: - Preview Content

    private func previewContent(revised: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(revised)
                .font(FontManager.metadata(size: 12, weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280, alignment: .leading)

            HStack(spacing: 12) {
                Button("Replace", action: onReplace)
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.accentColor, in: Capsule())
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                    .subtleHoverScale(1.04)

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                    .font(FontManager.heading(size: 12, weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .subtleHoverScale(1.04)

                Button("Redo", action: onRedo)
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                    .font(FontManager.heading(size: 12, weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .subtleHoverScale(1.04)
            }
        }
    }

    // MARK: - Shimmer Placeholder

    private var shimmerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Color("BorderSubtleColor").opacity(0.4)
                    .frame(width: 220, height: 10)
                    .clipShape(Capsule())
                    .shimmering(active: true)
                Color("BorderSubtleColor").opacity(0.4)
                    .frame(width: 160, height: 10)
                    .clipShape(Capsule())
                    .shimmering(active: true)
            }

            HStack(spacing: 12) {
                Color("BorderSubtleColor").opacity(0.4)
                    .frame(width: 72, height: 28)
                    .clipShape(Capsule())
                    .shimmering(active: true)
                Color("BorderSubtleColor").opacity(0.4)
                    .frame(width: 52, height: 14)
                    .clipShape(Capsule())
                    .shimmering(active: true)
                Color("BorderSubtleColor").opacity(0.4)
                    .frame(width: 40, height: 14)
                    .clipShape(Capsule())
                    .shimmering(active: true)
            }
        }
    }
}
