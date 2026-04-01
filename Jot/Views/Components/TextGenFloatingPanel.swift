//
//  TextGenFloatingPanel.swift
//  Jot
//
//  Floating panel for AI text generation results.
//  Mirrors AIResultPanel's visual style with integrated Accept/Dismiss buttons.
//  Replaces the old TextGenAcceptPanel + shimmer overlay machinery.
//

import SwiftUI

struct TextGenFloatingPanel: View {
    let state: AIPanelState
    let onAccept: () -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            contentArea
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if #available(macOS 26.0, iOS 26.0, *) {
                Color.clear
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(colorScheme == .dark ? Color("DetailPaneColor") : .white)
            }
        }
        .modifier(AIGlassModifier(cornerRadius: 22, glowMode: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onKeyPress(.return) {
            if case .error = state { return .ignored }
            onAccept()
            return .handled
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    // MARK: - Header

    private var isLoading: Bool {
        if case .loading(.textGenerate) = state { return true }
        return false
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            if isLoading {
                BrailleLoader(pattern: .waverows, size: 11)
                Text("Generating...")
                    .font(FontManager.metadata(size: 11, weight: .semibold))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .shimmering(active: true)
            } else {
                Image(AITool.textGenerate.aiIconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 16, height: 16)

                Text(AITool.textGenerate.aiDisplayName.uppercased())
                    .font(FontManager.metadata(size: 11, weight: .semibold))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .kerning(0.5)
            }

            Spacer()

            Button(action: onDismiss) {
                Image("IconXMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .subtleHoverScale(1.1)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch state {
        case .loading(.textGenerate):
            shimmerContent

        case .textGenPreview(let generated, _):
            previewContent(generated: generated)

        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(FontManager.body(size: 13))
                    .foregroundColor(Color.red.opacity(0.8))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                dismissButton
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Shimmer

    private var shimmerContent: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 8) {
                Color("BorderSubtleColor").opacity(0.4)
                    .frame(width: geo.size.width * 0.82, height: 14)
                    .clipShape(Capsule())
                    .shimmering(active: true)
                Color("BorderSubtleColor").opacity(0.4)
                    .frame(width: geo.size.width * 0.95, height: 14)
                    .clipShape(Capsule())
                    .shimmering(active: true)
                Color("BorderSubtleColor").opacity(0.4)
                    .frame(width: geo.size.width * 0.67, height: 14)
                    .clipShape(Capsule())
                    .shimmering(active: true)
            }
        }
        .frame(height: 54)
    }

    // MARK: - Preview

    private func previewContent(generated: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(generated)
                .font(FontManager.body(size: 14))
                .foregroundColor(Color("PrimaryTextColor"))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)

            buttonRow
        }
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        HStack(spacing: 6) {
            Button("Accept", action: onAccept)
                .font(FontManager.heading(size: 12, weight: .semibold))
                .foregroundColor(Color("ButtonPrimaryTextColor"))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color("ButtonPrimaryBgColor"), in: Capsule())
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.04)

            dismissButton
        }
    }

    private var dismissButton: some View {
        Button("Dismiss", action: onDismiss)
            .font(FontManager.heading(size: 12, weight: .semibold))
            .foregroundColor(Color("PrimaryTextColor"))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color("ButtonSecondaryBgColor"), in: Capsule())
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .subtleHoverScale(1.04)
    }
}
