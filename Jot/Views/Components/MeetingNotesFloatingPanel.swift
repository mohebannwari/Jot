//
//  MeetingNotesFloatingPanel.swift
//  Jot
//
//  Accordion panel for AI Meeting Notes — starts as a compact recording pill,
//  expands to show tabs for summary, transcript, and manual notes.
//

import SwiftUI

struct MeetingNotesFloatingPanel: View {
    @ObservedObject var transcriptionService: MeetingTranscriptionService
    let recordingState: MeetingRecordingState
    let duration: TimeInterval
    let summaryResult: MeetingSummaryDisplayResult?
    let isSummaryLoading: Bool
    @Binding var manualNotes: String
    @Binding var selectedTab: MeetingTab

    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private let panelWidth: CGFloat = 400
    private let panelRadius: CGFloat = 22
    private let pillRadius: CGFloat = 100

    private var isComplete: Bool { recordingState == .complete }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded || isComplete {
                tabBar
                tabContent
            }
            if !isComplete {
                recordingBar
            }
            if isExpanded || isComplete {
                footerButtons
            }
        }
        .frame(width: panelWidth)
        .modifier(MeetingPanelBackgroundModifier(
            cornerRadius: (isExpanded || isComplete) ? panelRadius : pillRadius,
            panelBackground: panelBackground,
            borderColor: borderColor
        ))
        .appleIntelligenceGlow(
            cornerRadius: (isExpanded || isComplete) ? panelRadius : pillRadius,
            mode: isSummaryLoading ? .continuous : .oneShot
        )
    }

    // MARK: - Recording Bar (always visible)

    private var recordingBar: some View {
        HStack(spacing: 10) {
            // Recording indicator dot
            if recordingState == .recording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingModifier())
            } else if recordingState == .paused {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
            } else if recordingState == .processing {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingModifier())
            } else if recordingState == .complete {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }

            // Status label
            Text(statusLabel)
                .font(FontManager.heading(size: 12, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))

            // Duration
            Text(formattedDuration)
                .font(FontManager.metadata(size: 12, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .monospacedDigit()

            Spacer()

            // Controls + cancel
            actionButtons

            // Expand/collapse chevron
            Button {
                withAnimation(.jotSpring) {
                    isExpanded.toggle()
                }
            } label: {
                Image(isExpanded ? "IconChevronDownSmall" : "IconChevronTopSmall")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .subtleHoverScale(1.1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            if recordingState == .recording {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.orange, in: Circle())
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.06)
            } else if recordingState == .paused {
                Button(action: onResume) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.blue, in: Circle())
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.06)
            }

            if recordingState == .recording || recordingState == .paused {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.85), in: Circle())
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .subtleHoverScale(1.06)
            }

            Button(action: onDismiss) {
                Image("IconXMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("PrimaryTextColor"))
                    .frame(width: 16, height: 16)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .subtleHoverScale(1.06)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(MeetingTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.label)
                        .font(FontManager.heading(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundColor(selectedTab == tab ? Color("PrimaryTextColor") : Color("SecondaryTextColor"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedTab == tab
                            ? Capsule().fill(tabSelectedBackground)
                            : nil
                        )
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
            }

        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var completeIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text(formattedDuration)
                .font(FontManager.metadata(size: 11, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .monospacedDigit()
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .summary:
                summaryTabContent
            case .transcript:
                transcriptTabContent
            case .notes:
                notesTabContent
            }
        }
        .frame(height: 260)
        .padding(.horizontal, 16)
    }

    // MARK: - Summary Tab

    @ViewBuilder
    private var summaryTabContent: some View {
        if isSummaryLoading {
            summaryShimmer
        } else if let result = summaryResult {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if !result.title.isEmpty {
                        Text(result.title)
                            .font(FontManager.heading(size: 15, weight: .bold))
                            .foregroundColor(Color("PrimaryTextColor"))
                    }

                    if !result.summary.isEmpty {
                        Text(result.summary)
                            .font(FontManager.body(size: 13))
                            .foregroundColor(Color("PrimaryTextColor"))
                            .lineSpacing(3)
                    }

                    if !result.keyPoints.isEmpty {
                        Text("Key Points")
                            .font(FontManager.heading(size: 12, weight: .semibold))
                            .foregroundColor(Color("SecondaryTextColor"))
                            .padding(.top, 4)

                        ForEach(Array(result.keyPoints.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(Color("SecondaryTextColor").opacity(0.4))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(point)
                                    .font(FontManager.body(size: 13))
                                    .foregroundColor(Color("PrimaryTextColor"))
                                    .lineSpacing(2)
                            }
                        }
                    }

                    if !result.actionItems.isEmpty {
                        Text("Action Items")
                            .font(FontManager.heading(size: 12, weight: .semibold))
                            .foregroundColor(Color("SecondaryTextColor"))
                            .padding(.top, 4)

                        ForEach(Array(result.actionItems.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "square")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color("SecondaryTextColor"))
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.description)
                                        .font(FontManager.body(size: 13))
                                        .foregroundColor(Color("PrimaryTextColor"))
                                    if item.assignee != "Unassigned" {
                                        Text(item.assignee)
                                            .font(FontManager.metadata(size: 11, weight: .medium))
                                            .foregroundColor(Color("TertiaryTextColor"))
                                    }
                                }
                            }
                        }
                    }

                    if !result.decisions.isEmpty {
                        Text("Decisions")
                            .font(FontManager.heading(size: 12, weight: .semibold))
                            .foregroundColor(Color("SecondaryTextColor"))
                            .padding(.top, 4)

                        ForEach(Array(result.decisions.enumerated()), id: \.offset) { _, decision in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(Color("SecondaryTextColor").opacity(0.4))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(decision)
                                    .font(FontManager.body(size: 13))
                                    .foregroundColor(Color("PrimaryTextColor"))
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
        } else {
            VStack(spacing: 8) {
                Text("Summary will appear here after you stop recording.")
                    .font(FontManager.body(size: 13))
                    .foregroundColor(Color("TertiaryTextColor"))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var summaryShimmer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<5, id: \.self) { i in
                Color("BorderSubtleColor").opacity(0.4)
                    .frame(width: CGFloat([0.9, 1.0, 0.75, 0.85, 0.6][i]) * (panelWidth - 32), height: 14)
                    .clipShape(Capsule())
                    .shimmering(active: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    // MARK: - Transcript Tab

    private var transcriptTabContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(transcriptionService.segments) { segment in
                        HStack(alignment: .top, spacing: 8) {
                            Text(formatTimestamp(segment.timestamp))
                                .font(FontManager.metadata(size: 10, weight: .medium))
                                .foregroundColor(Color("TertiaryTextColor"))
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)

                            Text(segment.text)
                                .font(FontManager.body(size: 13))
                                .foregroundColor(
                                    segment.isFinal
                                    ? Color("PrimaryTextColor")
                                    : Color("SecondaryTextColor")
                                )
                                .lineSpacing(2)
                                .opacity(segment.isFinal ? 1.0 : 0.7)
                        }
                        .id(segment.id)
                    }

                    if transcriptionService.segments.isEmpty {
                        Text(recordingState == .idle
                             ? "Transcript will appear here once recording starts."
                             : "Listening...")
                            .font(FontManager.body(size: 13))
                            .foregroundColor(Color("TertiaryTextColor"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .onChange(of: transcriptionService.segments.count) { _, _ in
                if let lastID = transcriptionService.segments.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Notes Tab

    private var notesTabContent: some View {
        TextEditor(text: $manualNotes)
            .font(FontManager.body(size: 13))
            .foregroundColor(Color("PrimaryTextColor"))
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(textAreaBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerButtons: some View {
        if recordingState == .complete {
            HStack(spacing: 6) {
                Button("Save to Note", action: onSave)
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color("ButtonPrimaryBgColor"), in: Capsule())
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                    .subtleHoverScale(1.04)

                Button("Dismiss", action: onDismiss)
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color("ButtonSecondaryBgColor"), in: Capsule())
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                    .subtleHoverScale(1.04)

                Spacer()

                completeIndicator
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helpers

    private var statusLabel: String {
        switch recordingState {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .processing: return "Generating Summary"
        case .complete: return "Complete"
        }
    }

    private var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Colors

    private var panelBackground: Color {
        Color("SurfaceElevatedColor")
    }

    private var tabSelectedBackground: Color {
        Color("SurfaceTranslucentColor")
    }

    private var textAreaBackground: Color {
        Color("SurfaceElevatedColor")
    }

    private var borderColor: Color {
        Color("BorderSubtleColor")
    }
}

// MARK: - Panel Background

private struct MeetingPanelBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    let panelBackground: Color
    let borderColor: Color

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(false),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(panelBackground.opacity(0.78))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                .shadow(color: .black.opacity(0.04), radius: 24, y: 8)
        }
    }
}

// MARK: - Pulsing Animation

private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
