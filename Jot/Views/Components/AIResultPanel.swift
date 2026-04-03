//
//  AIResultPanel.swift
//  Jot
//
//  Liquid glass card for Summary and Key Points AI results.
//  Proofread and Edit Content states are handled elsewhere.
//

import SwiftUI

struct AIResultPanel: View {
    let state: AIPanelState
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = true

    private var isCollapsible: Bool {
        switch state {
        case .summary, .keyPoints: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if isExpanded {
                contentArea
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
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
        .modifier(AIGlassModifier(cornerRadius: 22))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            if isLoading {
                BrailleLoader(pattern: loadingPattern, size: 11)
                Text(loadingLabel)
                    .font(FontManager.metadata(size: 11, weight: .semibold))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .shimmering(active: true)
            } else {
                Image(toolIconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 14, height: 14)

                Text(toolLabel.uppercased())
                    .font(FontManager.metadata(size: 11, weight: .semibold))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .kerning(0.5)
            }

            Spacer()

            if isCollapsible {
                Image(isExpanded ? "IconChevronTopSmall" : "IconChevronDownSmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 15, height: 15)
            }

            Button(action: onDismiss) {
                Image("IconXMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 15, height: 15)
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .subtleHoverScale(1.1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isCollapsible else { return }
            withAnimation(.jotSmoothFast) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch state {
        case .loading:
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

        case .summary(let text):
            Text(text)
                .font(FontManager.body(size: 14))
                .foregroundColor(Color("PrimaryTextColor"))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)

        case .keyPoints(let points):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(FontManager.body(size: 14))
                            .foregroundColor(Color("SecondaryTextColor"))
                        Text(point)
                            .font(FontManager.body(size: 14))
                            .foregroundColor(Color("PrimaryTextColor"))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .animation(
                        .spring(response: 0.38, dampingFraction: 0.82)
                            .delay(Double(index) * 0.05),
                        value: points.count
                    )
                }
            }

        case .error(let message):
            Text(message)
                .font(FontManager.body(size: 13))
                .foregroundColor(Color.red.opacity(0.8))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var loadingPattern: BraillePattern {
        switch state {
        case .loading(.summary):      return .breathe
        case .loading(.keyPoints):    return .breathe
        case .loading(.proofread):    return .snake
        case .loading(.meetingNotes): return .checkerboard
        case .loading:                return .breathe
        default:                      return .breathe
        }
    }

    private var loadingLabel: String {
        switch state {
        case .loading(.summary):      return "Summarizing..."
        case .loading(.keyPoints):    return "Extracting..."
        case .loading(.proofread):    return "Proofreading..."
        case .loading(.meetingNotes): return "Processing..."
        case .loading:                return "Thinking..."
        default:                      return ""
        }
    }

    private var toolLabel: String {
        switch state {
        case .loading(let tool): return tool.aiDisplayName
        case .summary:          return AITool.summary.aiDisplayName
        case .keyPoints:        return AITool.keyPoints.aiDisplayName
        case .error:            return "Apple Intelligence"
        default:                return ""
        }
    }

    private var toolIconName: String {
        switch state {
        case .loading(let tool): return tool.aiIconName
        case .summary:           return AITool.summary.aiIconName
        case .keyPoints:         return AITool.keyPoints.aiIconName
        default:                 return "IconAppleIntelligenceIcon"
        }
    }
}

// MARK: - AITool Helpers

extension AITool {
    var aiDisplayName: String {
        switch self {
        case .summary:      return "Summary"
        case .keyPoints:    return "Key Points"
        case .proofread:    return "Proofread"
        case .editContent:  return "Edit Content"
        case .translate:    return "Translate"
        case .textGenerate: return "Generate Text"
        case .meetingNotes: return "Meeting Notes"
        }
    }

    var aiIconName: String {
        switch self {
        case .summary:      return "IconSummary"
        case .keyPoints:    return "IconListSparkle"
        case .proofread:    return "IconBroomSparkle"
        case .editContent:  return "IconArrowsAllSides2"
        case .translate:    return "IconAiTranslate"
        case .textGenerate: return "TextGen"
        case .meetingNotes: return "IconMeetingNotes"
        }
    }
}
