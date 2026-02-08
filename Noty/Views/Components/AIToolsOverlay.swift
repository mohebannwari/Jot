//
//  AIToolsOverlay.swift
//  Noty
//
//  Multi-state AI tools overlay for the detail pane.
//  States: collapsed (single icon), expanded (tool bar + close),
//  promptField (edit content card + close).
//

import SwiftUI

enum AIToolsState: Equatable {
    case collapsed
    case expanded
    case promptField
}

struct AIToolsOverlay: View {
    @Binding var state: AIToolsState
    @State private var promptText = ""
    @Environment(\.colorScheme) private var colorScheme

    private let pillPadding: CGFloat = 8
    private let edgeInset: CGFloat = 0
    private let iconSize: CGFloat = 18
    private let toolBarHPadding: CGFloat = 12
    private let toolBarVPadding: CGFloat = 8
    private let toolBarGap: CGFloat = 18
    private let promptCardWidth: CGFloat = 257
    private let promptCardRadius: CGFloat = 24
    private let promptCardPadding: CGFloat = 12
    private let springAnimation = Animation.spring(response: 0.35, dampingFraction: 0.82)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if state == .collapsed {
                collapsedButton
                    .padding(.bottom, edgeInset)
                    .padding(.trailing, edgeInset)
                    .transition(.scale.combined(with: .opacity))
            }

            if state == .expanded {
                expandedToolBar
                    .padding(.bottom, edgeInset)
                    .padding(.trailing, 40)
                    .transition(.scale(scale: 0.8, anchor: .trailing).combined(with: .opacity))

                closePill
                    .padding(.bottom, edgeInset)
                    .padding(.trailing, edgeInset)
                    .transition(.scale.combined(with: .opacity))
            }

            if state == .promptField {
                promptFieldCard
                    .padding(.bottom, 40)
                    .padding(.trailing, edgeInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                closePill
                    .padding(.bottom, edgeInset)
                    .padding(.trailing, edgeInset)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(springAnimation, value: state)
    }

    // MARK: - Collapsed

    private var collapsedButton: some View {
        Button {
            state = .expanded
        } label: {
            toolIcon("IconAppleIntelligenceIcon")
                .padding(pillPadding)
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        #if os(macOS)
        .glassEffect(.regular.interactive(true), in: Capsule())
        #else
        .background(.ultraThinMaterial, in: Capsule())
        #endif
    }

    // MARK: - Expanded Tool Bar

    private var expandedToolBar: some View {
        HStack(spacing: toolBarGap) {
            toolBarButton(icon: "IconBroomSparkle", tooltip: "Proofread") {
                // Tool action placeholder
            }
            toolBarButton(icon: "IconListSparkle", tooltip: "Key Points") {
                // Tool action placeholder
            }
            toolBarButton(icon: "IconSummary", tooltip: "Summarize") {
                // Tool action placeholder
            }
            toolBarButton(icon: "IconArrowsAllSides2", tooltip: "Edit Content") {
                state = .promptField
            }
        }
        .padding(.horizontal, toolBarHPadding)
        .padding(.vertical, toolBarVPadding)
        #if os(macOS)
        .glassEffect(.regular.interactive(true), in: Capsule())
        #else
        .background(.ultraThinMaterial, in: Capsule())
        #endif
    }

    private func toolBarButton(
        icon: String,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolIcon(icon)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .help(tooltip)
    }

    // MARK: - Close Pill

    private var closePill: some View {
        Button {
            switch state {
            case .expanded:
                state = .collapsed
            case .promptField:
                state = .expanded
            case .collapsed:
                break
            }
        } label: {
            toolIcon("IconCircleX")
                .padding(pillPadding)
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        #if os(macOS)
        .glassEffect(.regular.interactive(true), in: Capsule())
        #else
        .background(.ultraThinMaterial, in: Capsule())
        #endif
    }

    // MARK: - Prompt Field Card

    private var promptFieldCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            promptCardHeader
            promptTextArea
            promptEnterButton
        }
        .padding(promptCardPadding)
        .frame(width: promptCardWidth)
        #if os(macOS)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: promptCardRadius, style: .continuous))
        #else
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: promptCardRadius, style: .continuous))
        #endif
    }

    private var promptCardHeader: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                toolIcon("IconArrowsAllSides2")
                    .frame(width: 12, height: 12)
                Text("Edit Content")
                    .font(FontManager.heading(size: 10, weight: .semibold))
                    .foregroundColor(Color("PrimaryTextColor"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var promptTextArea: some View {
        TextEditor(text: $promptText)
            .font(FontManager.metadata(size: 12, weight: .regular))
            .foregroundColor(Color("PrimaryTextColor"))
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(8)
            .frame(height: 158)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(textAreaBackgroundColor)
            )
    }

    private var promptEnterButton: some View {
        Button {
            // Submit action placeholder
        } label: {
            Text("Enter")
                .font(FontManager.heading(size: 12, weight: .semibold))
                .foregroundColor(enterButtonTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(enterButtonBackgroundColor)
                )
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
    }

    // MARK: - Shared Helpers

    private func toolIcon(_ assetName: String) -> some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(Color("SecondaryTextColor"))
            .frame(width: iconSize, height: iconSize)
    }

    // MARK: - Theme Colors

    private var cardBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.14, blue: 0.14, opacity: 0.85)
            : Color.white.opacity(0.85)
    }

    private var textAreaBackgroundColor: Color {
        colorScheme == .dark
            ? Color.black
            : Color.white
    }

    private var enterButtonBackgroundColor: Color {
        colorScheme == .dark
            ? Color.white
            : Color(red: 0.102, green: 0.102, blue: 0.102)
    }

    private var enterButtonTextColor: Color {
        colorScheme == .dark
            ? Color.black
            : Color.white
    }
}
