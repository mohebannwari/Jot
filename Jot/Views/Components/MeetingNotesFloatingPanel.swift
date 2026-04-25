//
//  MeetingNotesFloatingPanel.swift
//  Jot
//
//  Floating panel for AI Meeting Notes — tabs on top, content in middle,
//  controls at bottom. Starts as a compact collapsed pill, expands to show
//  Transcript/Notes tabs (and Summary tab after wrap-up).
//
//  Micro-pill: while recording/paused, user can shrink to a tight status chip
//  (intrinsic width, no extra horizontal slack). Toggle uses a normal spring +
//  scale/opacity transition — not a single-tree height collapse, which broke
//  layout (content shrinking, phantom padding, wide empty capsule).
//

import SwiftUI

struct MeetingNotesFloatingPanel: View {
    let transcriptionService: MeetingTranscriptionService
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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var isExpanded = false
    @State private var isMicroPillMinimized = false
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

    /// Tabs + content hidden in micro-pill; otherwise same as classic expand rules.
    private var showTabs: Bool {
        !isMicroPillMinimized && (isExpanded || isProcessing || isComplete)
    }

    /// Tight chip: recording/paused only, user chose minimize.
    private var isMicroPillActive: Bool {
        isMicroPillMinimized && (recordingState == .recording || recordingState == .paused)
    }

    private var meetingMorphAnimation: Animation {
        accessibilityReduceMotion ? .easeInOut(duration: 0.16) : .jotMeetingPanelMorph
    }

    private var visibleTabs: [MeetingTab] {
        if isProcessing || isComplete {
            return MeetingTab.allCases
        }
        return [.transcript, .notes]
    }

    /// One-shot glow must not attach separately to micro vs full chrome — switching branches
    /// recreated the modifier and fired `onAppear` again. A single glow on this stable shell
    /// runs once per panel lifetime (i.e. a recording session while the overlay is up).
    private var intelligenceGlowMode: GlowMode {
        isSummaryLoading ? .continuous : .oneShot
    }

    /// Micro / full chrome with morph animation — split out so `body` can branch on glow (pre-26 only).
    private var meetingChromeRoot: some View {
        Group {
            if isMicroPillActive {
                microPillChrome
                    .transition(microPillTransition)
            } else {
                fullPanelChrome
                    .transition(fullPanelTransition)
            }
        }
        .animation(meetingMorphAnimation, value: isMicroPillActive)
    }

    var body: some View {
        // Rotating halo sits in `.background` behind `meetingChromeRoot` (including Liquid Glass on
        // macOS 26+ via `MeetingPanelBackgroundModifier`) so the panel still gets the intro Apple
        // Intelligence treatment without painting over the frosted surface.
        meetingChromeRoot
            .appleIntelligenceGlow(cornerRadius: panelRadius, mode: intelligenceGlowMode)
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
        .onChange(of: recordingState) { _, new in
            if new != .recording && new != .paused {
                isMicroPillMinimized = false
            }
        }
    }

    // MARK: - Micro pill (intrinsic width — no spacers)

    private var microPillChrome: some View {
        HStack(spacing: 8) {
            AudioWaveformIndicator(
                levels: audioLevels,
                isPaused: recordingState == .paused
            )
            .frame(width: 18, height: 18)

            Text(statusLabel)
                .jotUI(FontManager.uiLabel5(weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))

            // Same typography as `recordingControls` / `processingControls` timer (SF Mono + tabular digits).
            Text(formattedDuration)
                .jotMetadataLabelTypography()
                .foregroundColor(Color("PrimaryTextColor"))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: false)
        .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .modifier(MeetingPanelBackgroundModifier(
            cornerRadius: panelRadius,
            panelBackground: Color("SurfaceElevatedColor"),
            borderColor: Color("BorderSubtleColor")
        ))
        .macPointingHandCursor()
        .onTapGesture {
            withAnimation(meetingMorphAnimation) {
                isMicroPillMinimized = false
                isExpanded = true
            }
        }
    }

    // MARK: - Full panel (classic layout from pre-regression build)

    private var fullPanelChrome: some View {
        VStack(spacing: 8) {
            if showTabs {
                tabBar
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        )
                    )
                contentBlock
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
                        )
                    )
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
    }

    private var microPillTransition: AnyTransition {
        let insert = AnyTransition.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity)
        let remove = AnyTransition.opacity
        return .asymmetric(insertion: insert, removal: remove)
    }

    private var fullPanelTransition: AnyTransition {
        let insert = AnyTransition.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity)
        let remove = AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
        return .asymmetric(insertion: insert, removal: remove)
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
                    // Selection signal: tinted capsule fill + foregroundColor delta (weight is invariant; chrome never uses weight for state).
                    Text(tab.label)
                        .jotUI(FontManager.uiLabel5(weight: .regular))
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
        // Opaque well (same token as detail text surfaces) so transcript/notes keep a stable base
        // and do not show the note canvas through—aligned with `TextGenFloatingPanel` content read.
        .background {
            RoundedRectangle(cornerRadius: contentRadius, style: .continuous)
                .fill(colorScheme == .dark ? Color("DetailPaneColor") : Color.white)
                .darkSurfaceHairlineBorder(RoundedRectangle(cornerRadius: contentRadius, style: .continuous))
        }
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
            HStack(spacing: 8) {
                AudioWaveformIndicator(
                    levels: audioLevels,
                    isPaused: isPaused
                )

                Text(statusLabel)
                    .jotUI(FontManager.uiLabel4(weight: .regular))
                    .foregroundColor(Color("PrimaryTextColor"))

                Spacer()

                Text(formattedDuration)
                    .jotMetadataLabelTypography()
                    .foregroundColor(Color("PrimaryTextColor"))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            HStack(spacing: 4) {
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

                tintedActionButton(
                    icon: "StopCircle",
                    iconSize: 15,
                    tintColor: Color("MeetingRecordingColor"),
                    action: { showStopConfirmation = true }
                )

                // Order: dismiss → expand/collapse → micro-pill minimize
                squareButton(
                    icon: "IconCrossMedium",
                    iconSize: 10,
                    action: { showDismissConfirmation = true }
                )

                squareButton(
                    icon: isExpanded ? "IconMinimize45" : "IconExpand45",
                    iconSize: 10,
                    action: {
                        withAnimation(.jotSpring) {
                            isExpanded.toggle()
                        }
                    }
                )

                squareButton(
                    icon: "IconMeetingPillMinimize",
                    iconSize: 10,
                    action: {
                        withAnimation(meetingMorphAnimation) {
                            isMicroPillMinimized = true
                        }
                    }
                )
            }
        }
    }

    // MARK: - Processing Controls

    private var processingControls: some View {
        HStack(spacing: 8) {
            BrailleLoader(pattern: .checkerboard, size: 11)

            Text(statusLabel)
                .jotUI(FontManager.uiLabel4(weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .shimmering(active: true)

            Spacer()

            Text(formattedDuration)
                .jotMetadataLabelTypography()
                .foregroundColor(Color("PrimaryTextColor"))
                .monospacedDigit()

            Button(action: { showDismissConfirmation = true }) {
                Image(systemName: "xmark")
                    .font(FontManager.uiTiny().font)
                    .foregroundColor(Color("IconSecondaryColor"))
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
                    .jotUI(FontManager.uiLabel5(weight: .regular))
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
                    .jotUI(FontManager.uiLabel5(weight: .regular))
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
                            .jotUI(FontManager.uiLabel2(weight: .regular))
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
                            .jotUI(FontManager.uiLabel4(weight: .regular))
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
                                        .jotMetadataLabelTypography()
                                        .foregroundColor(Color.orange.opacity(0.8))
                                        .padding(.top, 2)
                                }
                            }
                        }
                    }

                    if !result.actionItems.isEmpty {
                        Text("Action Items")
                            .jotUI(FontManager.uiLabel4(weight: .regular))
                            .foregroundColor(Color("SecondaryTextColor"))
                            .padding(.top, 4)

                        ForEach(Array(result.actionItems.enumerated()), id: \.offset) { index, item in
                            let score = result.grounding?.actionItemScores[safe: index]
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "square")
                                    .font(FontManager.uiLabel5(weight: .regular).font)
                                    .foregroundColor(Color("IconSecondaryColor"))
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(item.description)
                                            .font(FontManager.body(size: 13))
                                            .foregroundColor(Color("PrimaryTextColor"))
                                        if let score, score < 0.3 {
                                            Text("low confidence")
                                                .jotMetadataLabelTypography()
                                                .foregroundColor(Color.orange.opacity(0.8))
                                        }
                                    }
                                    if item.assignee != "Unassigned" {
                                        // Documented sentence-case mono override (proper noun).
                                        // `jotMetadataLabelTypography()` would uppercase the name — wrong for people.
                                        // See `.claude/rules/design-system.md` → Typography: "do not ship sentence-case
                                        // mono labels except where product explicitly overrides."
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
                            .jotUI(FontManager.uiLabel4(weight: .regular))
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
                                        .jotMetadataLabelTypography()
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

    // MARK: - Transcript Tab (isolated observation — avoids whole-panel invalidation)

    private var transcriptTabContent: some View {
        MeetingFloatingPanelTranscriptTabContent(
            transcriptionService: transcriptionService,
            recordingState: recordingState
        )
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
}

// MARK: - Transcript tab (isolated observation)

private struct MeetingFloatingPanelTranscriptTabContent: View {
    @ObservedObject var transcriptionService: MeetingTranscriptionService
    let recordingState: MeetingRecordingState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(transcriptionService.segments) { segment in
                        HStack(alignment: .top, spacing: 8) {
                            Text(Self.formatTimestamp(segment.timestamp))
                                .jotMetadataLabelTypography()
                                .foregroundColor(Color("TertiaryTextColor"))
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)

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
            // Avoid AppKit scroll view chrome painting an opaque backing over the glass well.
            .scrollContentBackground(.hidden)
        }
    }

    private static func formatTimestamp(_ timestamp: TimeInterval) -> String {
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
            // Match `CreateFolderSheet`: `liquidGlass` uses `.regular` (not `.clear`) plus the same
            // shadow stack so the recording panel reads as frosted glass with depth, not flat tint.
            content
                .glassEffect(
                    .regular.interactive(true),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
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
