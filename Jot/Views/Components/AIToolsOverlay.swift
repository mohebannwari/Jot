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
    case translateField
    case textGenPromptField
}

struct AIToolsOverlay: View {
    @Binding var state: AIToolsState
    var editorInstanceID: UUID?
    @State private var textGenPromptText = ""
    @Environment(\.colorScheme) private var colorScheme

    private let pillPadding: CGFloat = 8
    private let edgeInset: CGFloat = 0
    private let iconSize: CGFloat = 15
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

            if state == .textGenPromptField {
                HStack(alignment: .bottom, spacing: 8) {
                    textGenPromptFieldCard
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
            toolIcon("IconAppleIntelligenceIcon", size: 15)
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .glassTooltip("Apple Intelligence Tools", edge: .trailing)
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
            toolBarButton(icon: "TextGen", tooltip: "Generate Text") {
                NotificationCenter.default.post(name: .aiEditRequestSelection, object: nil, userInfo: eidInfo)
                state = .textGenPromptField
            }
            toolBarButton(icon: "IconMeetingNotes", tooltip: "Meeting Notes") {
                NotificationCenter.default.post(name: .aiMeetingNotesStart, object: nil, userInfo: eidInfo)
                state = .collapsed
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
            case .promptField, .translateField, .textGenPromptField:  // legacy states kept for enum compat
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



    // MARK: - Text Gen Prompt Field Card

    private var textGenPromptFieldCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image("TextGen")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 15, height: 15)
                    Text("Generate Text")
                        .font(FontManager.heading(size: 11, weight: .semibold))
                        .foregroundColor(Color("PrimaryTextColor"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            TextEditor(text: $textGenPromptText)
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
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
                .onKeyPress(.return) {
                    submitTextGen()
                    return .handled
                }
                .onKeyPress(.escape) {
                    state = .expanded
                    return .handled
                }

            Button {
                submitTextGen()
            } label: {
                Text("Generate")
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
        .padding(promptCardPadding)
        .frame(width: promptCardWidth)
        .liquidGlass(in: RoundedRectangle(cornerRadius: promptCardRadius, style: .continuous))
    }

    private func submitTextGen() {
        let trimmed = textGenPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NotificationCenter.default.post(name: .aiTextGenSubmit, object: trimmed, userInfo: eidInfo)
        textGenPromptText = ""
        state = .collapsed
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
