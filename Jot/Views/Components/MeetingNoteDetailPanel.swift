//
//  MeetingNoteDetailPanel.swift
//  Jot
//
//  Collapsible, tabbed panel that displays persisted meeting note data
//  (summary, transcript, manual notes) at the top of the note detail pane.
//  Supports multiple recording sessions per note, each rendered as its own
//  accordion with independent tabs and state.
//

import SwiftUI

struct MeetingNoteDetailPanel: View {
    @Binding var sessions: [MeetingSession]
    var onNotesChanged: ((UUID, String) -> Void)?
    var onSummaryChanged: ((UUID, String) -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = true

    private let panelRadius: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            if isExpanded {
                let reversed = Array(sessions.reversed())
                ForEach(Array(reversed.enumerated()), id: \.element.id) { index, session in
                    if index > 0 {
                        HandDrawnDividerLine(seed: index)
                            .stroke(Color("PrimaryTextColor").opacity(0.2), lineWidth: 0.9)
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                    }
                    SessionAccordion(
                        session: session,
                        defaultExpanded: index == 0,
                        onNotesChanged: { newNotes in
                            onNotesChanged?(session.id, newNotes)
                        },
                        onSummaryChanged: { newSummary in
                            onSummaryChanged?(session.id, newSummary)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .compositingGroup()
        .background {
            if #available(macOS 26.0, iOS 26.0, *) {
                Color.clear
            } else {
                RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                    .fill(panelBackground)
            }
        }
        .modifier(AIGlassModifier(cornerRadius: panelRadius))
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack(spacing: 6) {
            Image("IconMeetingNotes")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("IconSecondaryColor"))
                .frame(width: 14, height: 14)

            Text("Meeting Notes")
                .jotMetadataLabelTypography()
                .foregroundColor(Color("SecondaryTextColor"))
                .kerning(0.5)

            if sessions.count > 1 {
                // Multi-session badge uses accent so it stays on-token in both appearances (no hardcoded RGB).
                let pillColor = Color("AccentColor")
                Text("\(sessions.count) sessions")
                    .jotMetadataLabelTypography()
                    .foregroundColor(pillColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(pillColor.opacity(0.3))
                    )
            }

            Spacer()

            Image(isExpanded ? "IconChevronTopSmall" : "IconChevronDownSmall")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("IconSecondaryColor"))
                .frame(width: 15, height: 15)

            if let onDismiss {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.jotSpring) { isExpanded.toggle() }
        }
        .macPointingHandCursor()
    }

    // MARK: - Colors

    private var panelBackground: Color {
        colorScheme == .dark ? Color("DetailPaneColor") : .white
    }
}

// MARK: - Session Accordion

/// Renders a single meeting session with its own expand/collapse, tabs, and content.
private struct SessionAccordion: View {
    let session: MeetingSession
    var onNotesChanged: ((String) -> Void)?
    var onSummaryChanged: ((String) -> Void)?

    @State private var isExpanded: Bool
    @State private var selectedTab: MeetingTab = .summary
    @Environment(\.colorScheme) private var colorScheme

    /// Deserialized once at init — avoids re-parsing on every body evaluation.
    private let cachedSegments: [TranscriptSegment]
    /// Summary lines split once — avoids re-splitting on every body evaluation.
    private let cachedSummaryLines: [(offset: Int, element: String)]

    private static let maxContentHeight: CGFloat = 300

    init(session: MeetingSession, defaultExpanded: Bool = false, onNotesChanged: ((String) -> Void)? = nil, onSummaryChanged: ((String) -> Void)? = nil) {
        self.session = session
        self.onNotesChanged = onNotesChanged
        self.onSummaryChanged = onSummaryChanged
        self._isExpanded = State(initialValue: defaultExpanded)
        self.cachedSegments = [TranscriptSegment].deserialized(from: session.transcript)
        self.cachedSummaryLines = Array(
            session.summary.components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .enumerated()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionHeader
            if isExpanded {
                tabBar
                tabContent
            }
        }
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        HStack(spacing: 8) {
            Text(formattedDate)
                .jotMetadataLabelTypography()
                .foregroundColor(Color("SecondaryTextColor"))

            Circle()
                .fill(Color("TertiaryTextColor").opacity(0.4))
                .frame(width: 3, height: 3)

            Text(formattedDuration)
                .jotMetadataLabelTypography()
                .foregroundColor(Color("TertiaryTextColor"))
                .monospacedDigit()

            if !session.language.isEmpty {
                Text(session.language)
                    .jotMetadataLabelTypography()
                    .foregroundColor(Color("TertiaryTextColor"))
                    .kerning(0.3)
            }

            Spacer()

            Image(isExpanded ? "IconChevronTopSmall" : "IconChevronDownSmall")
                .resizable()
                .renderingMode(.template)
                .frame(width: 15, height: 15)
                .foregroundColor(Color("IconSecondaryColor"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.jotSmoothFast) {
                isExpanded.toggle()
            }
        }
        .macPointingHandCursor()
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
                    // Selection signal: capsule background + foregroundColor delta (weight is invariant; chrome never uses weight for state).
                    Text(tab.label)
                        .jotUI(FontManager.uiLabel5(weight: .regular))
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
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .summary:
                ThinScrollView(maxHeight: Self.maxContentHeight) {
                    summaryContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
            case .transcript:
                ThinScrollView(maxHeight: Self.maxContentHeight) {
                    transcriptContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
            case .notes:
                notesContent
                    .frame(maxWidth: .infinity, maxHeight: Self.maxContentHeight, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    // MARK: - Summary Tab

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cachedSummaryLines, id: \.offset) { index, line in
                meetingSummaryLine(line, at: index)
            }
        }
    }

    /// Toggle a `[ ] ` / `[x] ` action item at the given filtered-line index.
    private func toggleActionItem(at filteredIndex: Int) {
        var lines = session.summary.components(separatedBy: "\n")
        let nonEmptyIndices = lines.enumerated().compactMap { $0.element.isEmpty ? nil : $0.offset }
        guard filteredIndex < nonEmptyIndices.count else { return }
        let actualIndex = nonEmptyIndices[filteredIndex]

        if lines[actualIndex].hasPrefix("[ ] ") {
            lines[actualIndex] = "[x] " + String(lines[actualIndex].dropFirst(4))
        } else if lines[actualIndex].hasPrefix("[x] ") {
            lines[actualIndex] = "[ ] " + String(lines[actualIndex].dropFirst(4))
        }
        onSummaryChanged?(lines.joined(separator: "\n"))
    }

    @ViewBuilder
    private func meetingSummaryLine(_ line: String, at index: Int) -> some View {
        let stripped = line
            .replacingOccurrences(of: "[[h1]]", with: "")
            .replacingOccurrences(of: "[[/h1]]", with: "")
            .replacingOccurrences(of: "[[h2]]", with: "")
            .replacingOccurrences(of: "[[/h2]]", with: "")

        if line.contains("[[h1]]") {
            Text(stripped)
                .jotUI(FontManager.uiLabel2(weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
        } else if line.contains("[[h2]]") {
            Text(stripped)
                .jotUI(FontManager.uiLabel3(weight: .regular))
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.top, 4)
        } else if line.hasPrefix("[ ] ") {
            HStack(alignment: .top, spacing: 6) {
                MeetingCheckbox(isChecked: false)
                    .padding(.top, 2)
                Text(String(line.dropFirst(4)))
                    .font(FontManager.body(size: 14))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .lineSpacing(2)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleActionItem(at: index) }
            .macPointingHandCursor()
        } else if line.hasPrefix("[x] ") {
            HStack(alignment: .top, spacing: 6) {
                MeetingCheckbox(isChecked: true)
                    .padding(.top, 2)
                Text(String(line.dropFirst(4)))
                    .font(FontManager.body(size: 14))
                    .foregroundColor(Color("TertiaryTextColor"))
                    .strikethrough(color: Color("TertiaryTextColor").opacity(0.5))
                    .lineSpacing(2)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleActionItem(at: index) }
            .macPointingHandCursor()
        } else if line.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(Color("SecondaryTextColor").opacity(0.4))
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
                Text(String(line.dropFirst(2)))
                    .font(FontManager.body(size: 14))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .lineSpacing(2)
            }
        } else {
            Text(stripped)
                .font(FontManager.body(size: 14))
                .foregroundColor(Color("PrimaryTextColor"))
                .lineSpacing(3)
        }
    }

    // MARK: - Transcript Tab

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if cachedSegments.isEmpty {
                Text("No transcript available.")
                    .jotUI(FontManager.uiPro(size: 14, weight: .regular))
                    .foregroundColor(Color("TertiaryTextColor"))
            } else {
                ForEach(cachedSegments) { segment in
                    HStack(alignment: .top, spacing: 8) {
                        Text(formatTimestamp(segment.timestamp))
                            .jotMetadataLabelTypography()
                            .foregroundColor(Color("TertiaryTextColor"))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)

                        Text(segment.text)
                            .font(FontManager.body(size: 14))
                            .foregroundColor(Color("PrimaryTextColor"))
                            .lineSpacing(2)
                    }
                }
            }
        }
    }

    // MARK: - Notes Tab

    private var notesContent: some View {
        NotesEditor(text: session.manualNotes, onChanged: onNotesChanged)
    }

    // MARK: - Helpers

    private static let sessionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var formattedDate: String {
        Self.sessionDateFormatter.string(from: session.date)
    }

    private var formattedDuration: String {
        let hours = Int(session.duration) / 3600
        let minutes = (Int(session.duration) % 3600) / 60
        let seconds = Int(session.duration) % 60
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

    private var tabSelectedBackground: Color {
        Color("SurfaceTranslucentColor")
    }
}

// MARK: - Notes Editor (callback-based wrapper)

/// Wraps TextEditor for session manual notes, calling back on changes
/// rather than requiring a direct Binding to the session.
private struct NotesEditor: View {
    let text: String
    var onChanged: ((String) -> Void)?

    @State private var editableText: String = ""
    @Environment(\.colorScheme) private var colorScheme

    init(text: String, onChanged: ((String) -> Void)? = nil) {
        self.text = text
        self.onChanged = onChanged
        self._editableText = State(initialValue: text)
    }

    var body: some View {
        TextEditor(text: $editableText)
            .font(FontManager.body(size: 14))
            .foregroundColor(Color("PrimaryTextColor"))
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(8)
            .frame(minHeight: 80, maxHeight: .infinity)
            // Match `MeetingNotesFloatingPanel.contentBlock`: opaque detail well, not glass-through.
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(notesEditorChromeFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add notes...")
                        .jotUI(FontManager.uiPro(size: 14, weight: .regular))
                        .foregroundColor(Color("TertiaryTextColor"))
                        .allowsHitTesting(false)
                        .padding(.top, 9)
                        .padding(.leading, 13)
                }
            }
            .onChange(of: editableText) { _, newValue in
                onChanged?(newValue)
            }
            // Resync from parent when the source text changes (e.g. undo, note switch)
            .onChange(of: text) { _, newValue in
                if newValue != editableText {
                    editableText = newValue
                }
            }
    }

    private var borderColor: Color {
        Color("BorderSubtleColor")
    }

    private var notesEditorChromeFill: Color {
        colorScheme == .dark ? Color("DetailPaneColor") : Color.white
    }
}

// MARK: - Thin Scroll View

/// ScrollView with native indicators hidden and a custom thin capsule indicator.
/// Hugs content height up to `maxHeight`, then scrolls.
private struct ThinScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content
                .background(
                    GeometryReader { contentGeo in
                        Color.clear
                            .preference(
                                key: ScrollMetricsKey.self,
                                value: ScrollMetrics(
                                    contentHeight: contentGeo.size.height,
                                    offset: contentGeo.frame(in: .named("thinScroll")).origin.y
                                )
                            )
                            .onAppear { contentHeight = contentGeo.size.height }
                            .onChange(of: contentGeo.size.height) { _, h in contentHeight = h }
                    }
                )
        }
        .scrollIndicators(.never)
        .coordinateSpace(name: "thinScroll")
        .frame(height: min(contentHeight, maxHeight))
        .overlayPreferenceValue(ScrollMetricsKey.self) { metrics in
            GeometryReader { viewportGeo in
                let vp = viewportGeo.size.height
                let ch = metrics.contentHeight
                let offset = -metrics.offset

                if ch > vp + 1 {
                    let ratio = vp / ch
                    let thumbH = max(vp * ratio, 28)
                    let maxScroll = ch - vp
                    let progress = maxScroll > 0 ? min(max(offset / maxScroll, 0), 1) : 0
                    let track = vp - thumbH - 6

                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.18))
                        .frame(width: 4, height: thumbH)
                        .offset(y: 3 + track * progress)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 2)
                        .allowsHitTesting(false)
                        .animation(.interactiveSpring, value: offset)
                }
            }
        }
    }
}

private struct ScrollMetrics: Equatable {
    var contentHeight: CGFloat = 0
    var offset: CGFloat = 0
}

private struct ScrollMetricsKey: PreferenceKey {
    static var defaultValue = ScrollMetrics()
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        value = nextValue()
    }
}

// MARK: - Meeting Checkbox

/// Custom circular checkbox matching the editor's TodoCheckboxAttachmentCell design,
/// scaled down to 13px for the meeting panel's tighter proportions.
private struct MeetingCheckbox: View {
    let isChecked: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let size: CGFloat = 13
    private let borderWidth: CGFloat = 1.0

    var body: some View {
        ZStack {
            if isChecked {
                Circle()
                    .fill(Color("ButtonPrimaryBgColor"))
                    .frame(width: size, height: size)
                CheckmarkShape()
                    .stroke(Color("ButtonPrimaryTextColor"), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(Color("CheckboxUncheckedFillColor"))
                    .frame(width: size, height: size)
                Circle()
                    .strokeBorder(Color("CheckboxUncheckedStrokeColor"), lineWidth: borderWidth)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Checkmark path matching the editor's TodoCheckboxAttachmentCell control points.
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

        var path = Path()
        path.move(to: CGPoint(x: ox + s * 0.28, y: oy + s * 0.50))
        path.addLine(to: CGPoint(x: ox + s * 0.44, y: oy + s * 0.66))
        path.addLine(to: CGPoint(x: ox + s * 0.72, y: oy + s * 0.34))
        return path
    }
}

// MARK: - Hand-Drawn Divider Line

/// Matches the hand-drawn wavy divider used in the note editor (DividerSizeAttachmentCell).
/// Uses a deterministic pseudo-random hash so the line is stable across redraws.
private struct HandDrawnDividerLine: Shape {
    let seed: Int

    private func hash(_ i: Int) -> CGFloat {
        var h = UInt64(bitPattern: Int64(i))
        h = h &* 6364136223846793005 &+ 1442695040888963407
        h = (h >> 33) ^ h
        return CGFloat(h % 10000) / 10000.0
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseY = rect.midY
        var x = rect.minX
        var y = baseY
        var drift: CGFloat = 0
        var i = seed &* 1000

        path.move(to: CGPoint(x: x, y: y))

        while x < rect.maxX {
            let r1 = hash(i &* 31 &+ 7)
            let r2 = hash(i &* 47 &+ 13)
            let r3 = hash(i &* 73 &+ 29)
            let r4 = hash(i &* 97 &+ 41)

            let segLen = 6.0 + r1 * 12.0
            let nextX = min(x + segLen, rect.maxX)
            let midX = (x + nextX) / 2

            drift += (r2 - 0.5) * 1.2
            drift *= 0.85

            let bumpUp = (r3 - 0.5) * 2.8
            let bumpDown = (r4 - 0.5) * 2.8
            let nextY = baseY + drift

            path.addCurve(
                to: CGPoint(x: nextX, y: nextY),
                control1: CGPoint(x: midX - segLen * 0.15, y: y + bumpUp),
                control2: CGPoint(x: midX + segLen * 0.15, y: nextY + bumpDown)
            )

            x = nextX
            y = nextY
            i += 1
        }

        return path
    }
}
