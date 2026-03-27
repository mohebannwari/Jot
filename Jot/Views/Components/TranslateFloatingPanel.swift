//
//  TranslateFloatingPanel.swift
//  Jot
//
//  Floating panel for AI Translation results.
//  Matches TextGenFloatingPanel's design: solid bg, header row, bottom-fixed position.
//

import SwiftUI

struct TranslateFloatingPanel: View {
    let state: AIPanelState
    let onReplace: () -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void
    let onRetranslate: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            contentArea
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colorScheme == .dark ? Color("DetailPaneColor") : .white)
        )
        .appleIntelligenceGlow(cornerRadius: 22, mode: .continuous)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onKeyPress(.return) { onReplace(); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(AITool.translate.aiIconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(width: 18, height: 18)

            Text(AITool.translate.aiDisplayName.uppercased())
                .font(FontManager.metadata(size: 11, weight: .semibold))
                .foregroundColor(Color("SecondaryTextColor"))
                .kerning(0.5)

            Spacer()

            Button(action: onDismiss) {
                Image("IconXMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 18, height: 18)
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
        case .loading(.translate):
            shimmerContent

        case .translatePreview(let translated, _, _, _):
            previewContent(translated: translated)

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

    private func previewContent(translated: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(translated)
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
            Button("Replace", action: onReplace)
                .font(FontManager.heading(size: 12, weight: .semibold))
                .foregroundColor(Color("ButtonPrimaryTextColor"))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color("ButtonPrimaryBgColor"), in: Capsule())
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.04)

            Button("Copy", action: onCopy)
                .font(FontManager.heading(size: 12, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color("ButtonSecondaryBgColor"), in: Capsule())
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.04)

            Button("Retranslate", action: onRetranslate)
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
