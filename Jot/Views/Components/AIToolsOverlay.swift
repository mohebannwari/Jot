//
//  AIToolsOverlay.swift
//  Jot
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
    var editorInstanceID: UUID?
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
                    .padding(.trailing, 26)
                    .transition(.scale(scale: 0.8, anchor: .trailing).combined(with: .opacity))

                closeButton
                    .padding(.bottom, edgeInset)
                    .padding(.trailing, edgeInset)
                    .transition(.scale.combined(with: .opacity))
            }

            if state == .promptField {
                HStack(alignment: .bottom, spacing: 8) {
                    promptFieldCard
                        .transition(.move(edge: .trailing).combined(with: .opacity))

                    closeButton
                        .transition(.scale.combined(with: .opacity))
                }
                .padding(.bottom, edgeInset)
                .padding(.trailing, edgeInset)
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
            toolIcon("IconAppleIntelligenceIcon", size: 20)
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .hoverContainer(cornerRadius: 8)
    }

    // MARK: - Expanded Tool Bar

    private var expandedToolBar: some View {
        HStack(spacing: 2) {
            toolBarButton(icon: "IconBroomSparkle", tooltip: "Proofread") {
                NotificationCenter.default.post(name: .aiEditRequestSelection, object: nil, userInfo: eidInfo)
                NotificationCenter.default.post(name: .aiToolAction, object: AITool.proofread, userInfo: eidInfo)
                state = .collapsed
            }
            toolBarButton(icon: "IconListSparkle", tooltip: "Key Points") {
                NotificationCenter.default.post(name: .aiToolAction, object: AITool.keyPoints, userInfo: eidInfo)
                state = .collapsed
            }
            toolBarButton(icon: "IconSummary", tooltip: "Summarize") {
                NotificationCenter.default.post(name: .aiToolAction, object: AITool.summary, userInfo: eidInfo)
                state = .collapsed
            }
            toolBarButton(icon: "IconArrowsAllSides2", tooltip: "Edit Content") {
                NotificationCenter.default.post(name: .aiEditRequestSelection, object: nil, userInfo: eidInfo)
                state = .promptField
            }
        }
    }

    private func toolBarButton(
        icon: String,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolIcon(icon)
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .glassTooltip(tooltip)
        .hoverContainer(cornerRadius: 8)
    }

    // MARK: - Close Button

    private var closeButton: some View {
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
            toolIcon("IconChevronRightMedium")
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .hoverContainer(cornerRadius: 8)
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
        .liquidGlass(in: RoundedRectangle(cornerRadius: promptCardRadius, style: .continuous))
    }

    private var promptCardHeader: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image("IconArrowsAllSides2")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 18, height: 18)
                Text("Edit Content")
                    .font(FontManager.heading(size: 11, weight: .semibold))
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
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .onKeyPress(.return) {
                let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return .ignored }
                NotificationCenter.default.post(name: .aiEditSubmit, object: trimmed, userInfo: eidInfo)
                promptText = ""
                state = .collapsed
                return .handled
            }
            .onKeyPress(.escape) {
                state = .expanded
                return .handled
            }
    }

    private var promptEnterButton: some View {
        Button {
            let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            NotificationCenter.default.post(name: .aiEditSubmit, object: trimmed, userInfo: eidInfo)
            promptText = ""
            state = .collapsed
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
        .subtleHoverScale(1.02)
    }

    // MARK: - Shared Helpers

    private func toolIcon(_ assetName: String, size: CGFloat? = nil) -> some View {
        let dim = size ?? iconSize
        return Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(Color("IconSecondaryColor"))
            .frame(width: dim, height: dim)
    }

    // MARK: - Notification Helpers

    private var eidInfo: [String: Any]? {
        editorInstanceID.map { ["editorInstanceID": $0] }
    }

    // MARK: - Theme Colors

    private var cardBackgroundColor: Color {
        Color("SurfaceElevatedColor").opacity(0.85)
    }

    private var textAreaBackgroundColor: Color {
        Color("SurfaceElevatedColor")
    }

    private var enterButtonBackgroundColor: Color {
        Color("ButtonPrimaryBgColor")
    }

    private var enterButtonTextColor: Color {
        Color("ButtonPrimaryTextColor")
    }
}
