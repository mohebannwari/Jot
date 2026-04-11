//
//  MeetingNotesFloatingPanel.swift
//  Jot
//
//  Floating panel for AI Meeting Notes — tabs on top, content in middle,
//  controls at bottom. Starts as a compact collapsed pill, expands to show
//  Transcript/Notes tabs (and Summary tab after wrap-up).
//

import SwiftUI

struct MeetingNotesFloatingPanel: View {
    @ObservedObject var transcriptionService: MeetingTranscriptionService
    let recordingState: MeetingRecordingState
    let duration: TimeInterval
    let audioLevels: [Float]
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
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var isExpanded = false
    @State private var showStopConfirmation = false
    @State private var showDismissConfirmation = false

    // Figma dimensions
    private let panelWidth: CGFloat = 383
    private let panelRadius: CGFloat = 22
    private let expandedHeight: CGFloat = 299
    private let contentRadius: CGFloat = 14
    private let tabHeight: CGFloat = 34
    private let buttonHeight: CGFloat = 34
    private let squareButtonSize: CGFloat = 34

    private var isComplete: Bool { recordingState == .complete }
    private var isProcessing: Bool { recordingState == .processing }

    /// Tabs + content are visible when expanded or post-recording
    private var showTabs: Bool { isExpanded || isProcessing || isComplete }

    /// Summary tab only available after wrap-up (processing or complete)
    private var visibleTabs: [MeetingTab] {
        if isProcessing || isComplete {
            return MeetingTab.allCases
        }
        return [.transcript, .notes]
    }

    var body: some View {
        VStack(spacing: 8) {
            if showTabs {
                tabBar
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                contentBlock
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
            controlsSection
        }
        .padding(8)
        .frame(width: panelWidth)
        .frame(height: showTabs ? expandedHeight : nil)
        .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .modifier(MeetingPanelBackgroundModifier(
            cornerRadius: panelRadius,
            panelBackground: Color("SurfaceElevatedColor"),
            borderColor: Color("BorderSubtleColor")
        ))
        .appleIntelligenceGlow(
            cornerRadius: panelRadius,
            mode: isSummaryLoading ? .continuous : .oneShot
        )
        .alert("Stop Recording?", isPresented: $showStopConfirmation) {
            Button("Stop", role: .destructive, action: onStop)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end the recording and generate a summary. This action cannot be undone.")
        }
        .alert("Discard Recording?", isPresented: $showDismissConfirmation) {
            Button("Discard", role: .destructive, action: onDismiss)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current recording session and any transcript will be permanently lost.")
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.label)
                        .font(FontManager.heading(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundColor(selectedTab == tab ? Color("PrimaryTextColor") : Color("SecondaryTextColor"))
                        .frame(maxWidth: .infinity)
                        .frame(height: tabHeight)
                        .contentShape(Capsule())
                        .background(
                            selectedTab == tab
                                ? Capsule().fill(themeManager.tintedSecondaryButtonBackground(for: colorScheme))
                                : nil
                        )
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
            }
        }
    }

    // MARK: - Content Block

    private var contentBlock: some View {
        ZStack {
            switch selectedTab {
            case .summary:
                summaryTabContent
            case .transcript:
                transcriptTabContent
            case .notes:
                notesTabContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color("DetailPaneColor") : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: contentRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: contentRadius, style: .continuous)
                .stroke(Color("BorderSubtleColor"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }

    // MARK: - Controls Section

    @ViewBuilder
    private var controlsSection: some View {
        switch recordingState {
        case .idle:
            EmptyView()

        case .recording, .paused:
            recordingControls

        case .processing:
            processingControls

        case .complete:
            completeControls
        }
    }

    // MARK: - Recording / Paused Controls

    private var recordingControls: some View {
        let isPaused = recordingState == .paused

        return VStack(spacing: 8) {
            // Info bar: waveform + status + timer
            HStack(spacing: 8) {
                AudioWaveformIndicator(
                    levels: audioLevels,
                    isPaused: isPaused
                )

                Text(statusLabel)
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .foregroundColor(Color("PrimaryTextColor"))

                Spacer()

                Text(formattedDuration)
                    .font(FontManager.metadata(size: 12, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Action buttons row
            HStack(spacing: 4) {
                // Pause or Resume (flex)
                if isPaused {
                    tintedActionButton(
                        icon: "IconPlayCircle",
                        iconSize: 15,
                        tintColor: Color("MeetingResumeColor"),
                        action: onResume
                    )
                } else {
                    tintedActionButton(
                        icon: "IconPause",
                        iconSize: 15,
                        tintColor: Color("MeetingPausedColor"),
                        action: onPause
                    )
                }

                // Stop (flex) — guarded with confirmation
                tintedActionButton(
                    icon: "StopCircle",
                    iconSize: 15,
                    tintColor: Color("MeetingRecordingColor"),
                    action: { showStopConfirmation = true }
                )

                // Dismiss (square) — guarded with confirmation
                squareButton(
                    icon: "IconCrossMedium",
                    iconSize: 10,
                    action: { showDismissConfirmation = true }
                )

                // Expand / Minimize (square)
                squareButton(
                    icon: isExpanded ? "IconMinimize45" : "IconExpand45",
                    iconSize: 10,
                    action: {
                        withAnimation(.jotSpring) {
                            isExpanded.toggle()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Processing Controls (escape hatch via dismiss)

    private var processingControls: some View {
        HStack(spacing: 8) {
            BrailleLoader(pattern: .checkerboard, size: 10)

            Text(statusLabel)
                .font(FontManager.heading(size: 12, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))
                .shimmering(active: true)

            Spacer()

            Text(formattedDuration)
                .font(FontManager.metadata(size: 12, weight: .medium))
                .foregroundColor(Color("PrimaryTextColor"))
                .monospacedDigit()

            Button(action: { showDismissConfirmation = true }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Complete Controls

    private var completeControls: some View {
        HStack(spacing: 4) {
            Button(action: onSave) {
                Text("Save to note")
                    .font(FontManager.heading(size: 11, weight: .medium))
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(Color("ButtonPrimaryBgColor"), in: Capsule())
            .macPointingHandCursor()
            .subtleHoverScale(1.04)

            Button(action: { showDismissConfirmation = true }) {
                Text("Dismiss")
                    .font(FontManager.heading(size: 11, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(themeManager.tintedSecondaryButtonBackground(for: colorScheme), in: Capsule())
            .macPointingHandCursor()
            .subtleHoverScale(1.04)
        }
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

                        ForEach(Array(result.keyPoints.enumerated()), id: \.offset) { index, point in
                            let score = result.grounding?.keyPointScores[safe: index]
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(Color("SecondaryTextColor").opacity(0.4))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(point)
                                    .font(FontManager.body(size: 13))
                                    .foregroundColor(Color("PrimaryTextColor"))
                                    .lineSpacing(2)
                                if let score, score < 0.3 {
                                    Text("low confidence")
                                        .font(FontManager.metadata(size: 9, weight: .medium))
                                        .foregroundColor(Color.orange.opacity(0.8))
                                        .padding(.top, 2)
                                }
                            }
                        }
                    }

                    if !result.actionItems.isEmpty {
                        Text("Action Items")
                            .font(FontManager.heading(size: 12, weight: .semibold))
                            .foregroundColor(Color("SecondaryTextColor"))
                            .padding(.top, 4)

                        ForEach(Array(result.actionItems.enumerated()), id: \.offset) { index, item in
                            let score = result.grounding?.actionItemScores[safe: index]
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "square")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color("SecondaryTextColor"))
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(item.description)
                                            .font(FontManager.body(size: 13))
                                            .foregroundColor(Color("PrimaryTextColor"))
                                        if let score, score < 0.3 {
                                            Text("low confidence")
                                                .font(FontManager.metadata(size: 9, weight: .medium))
                                                .foregroundColor(Color.orange.opacity(0.8))
                                        }
                                    }
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

                        ForEach(Array(result.decisions.enumerated()), id: \.offset) { index, decision in
                            let score = result.grounding?.decisionScores[safe: index]
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(Color("SecondaryTextColor").opacity(0.4))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(decision)
                                    .font(FontManager.body(size: 13))
                                    .foregroundColor(Color("PrimaryTextColor"))
                                    .lineSpacing(2)
                                if let score, score < 0.3 {
                                    Text("low confidence")
                                        .font(FontManager.metadata(size: 9, weight: .medium))
                                        .foregroundColor(Color.orange.opacity(0.8))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
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
                    .frame(width: CGFloat([0.9, 1.0, 0.75, 0.85, 0.6][i]) * (panelWidth - 48), height: 14)
                    .clipShape(Capsule())
                    .shimmering(active: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
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
                        Text(
                            recordingState == .idle
                                ? "Transcript will appear here once recording starts."
                                : "Listening..."
                        )
                        .font(FontManager.body(size: 13))
                        .foregroundColor(Color("TertiaryTextColor"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
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
            .overlay(alignment: .topLeading) {
                if manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add notes...")
                        .font(FontManager.body(size: 13))
                        .foregroundColor(Color("TertiaryTextColor"))
                        .allowsHitTesting(false)
                        .padding(.top, 9)
                        .padding(.leading, 13)
                }
            }
    }

    // MARK: - Reusable Button Components

    /// Full-width tinted capsule button with icon (pause, play, stop)
    private func tintedActionButton(
        icon: String,
        iconSize: CGFloat,
        tintColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundColor(tintColor)
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(tintColor.opacity(0.25), in: Capsule())
        .macPointingHandCursor()
        .subtleHoverScale(1.1)
    }

    /// Fixed-size secondary capsule button (X, expand/minimize)
    private func squareButton(
        icon: String,
        iconSize: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundColor(Color("PrimaryTextColor"))
                .frame(width: squareButtonSize, height: squareButtonSize)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(themeManager.tintedSecondaryButtonBackground(for: colorScheme), in: Capsule())
        .macPointingHandCursor()
        .subtleHoverScale(1.1)
    }

    // MARK: - Helpers

    private var statusLabel: String {
        switch recordingState {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .processing: return "Generating summary"
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

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
