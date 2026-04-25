//
//  EditContentFloatingPanel.swift
//  Jot
//
//  Floating panel for Edit Content AI results.
//  Matches TranslateFloatingPanel / TextGenFloatingPanel design:
//  solid bg, full-width header, bottom-fixed position, proper button tokens.
//

import SwiftUI

struct EditContentFloatingPanel: View {
    let state: AIPanelState
    let onReplace: () -> Void
    let onDismiss: () -> Void
    let onRedo: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager

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
                    .darkSurfaceHairlineBorder(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .modifier(AIGlassModifier(cornerRadius: 22, glowMode: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onKeyPress(.return) {
            if case .error = state { return .ignored }
            onReplace()
            return .handled
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    // MARK: - Header

    private var isLoading: Bool {
        if case .loading(.editContent) = state { return true }
        return false
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            if isLoading {
                BrailleLoader(pattern: .scan, size: 11)
                Text("Editing...")
                    .jotMetadataLabelTypography()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .shimmering(active: true)
            } else {
                Image(AITool.editContent.aiIconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("IconSecondaryColor"))
                    .frame(width: 15, height: 15)

                Text(AITool.editContent.aiDisplayName)
                    .jotMetadataLabelTypography()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .kerning(0.5)
            }

            Spacer()

            Button(action: onDismiss) {
                Image("IconXMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("IconSecondaryColor"))
                    .frame(width: 15, height: 15)
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
        case .loading(.editContent):
            shimmerContent

        case .editPreview(let revised, _, _, _):
            previewContent(revised: revised)

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

    private func previewContent(revised: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(revised)
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
                .jotUI(FontManager.uiLabel4(weight: .regular))
                .foregroundColor(Color("ButtonPrimaryTextColor"))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color("ButtonPrimaryBgColor"), in: Capsule())
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.04)

            dismissButton

            Button("Redo", action: onRedo)
                .jotUI(FontManager.uiLabel4(weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(themeManager.tintedSecondaryButtonBackground(for: colorScheme), in: Capsule())
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.04)
        }
    }

    private var dismissButton: some View {
        Button("Dismiss", action: onDismiss)
            .jotUI(FontManager.uiLabel4(weight: .regular))
            .foregroundColor(Color("PrimaryTextColor"))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(themeManager.tintedSecondaryButtonBackground(for: colorScheme), in: Capsule())
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .subtleHoverScale(1.04)
    }
}
