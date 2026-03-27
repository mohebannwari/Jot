//
//  MeetingNoteDetailPanel.swift
//  Jot
//
//  Collapsible, tabbed panel that displays persisted meeting note data
//  (summary, transcript, manual notes) at the top of the note detail pane.
//  Sits in the same position as AI summary/key points panels.
//

import SwiftUI

struct MeetingNoteDetailPanel: View {
    let meetingSummary: String
    let meetingTranscript: String
    @Binding var meetingManualNotes: String
    let meetingDuration: TimeInterval
    let meetingLanguage: String
    let meetingDate: Date
    var onNotesChanged: ((String) -> Void)? = nil

    @State private var isExpanded = false
    @State private var selectedTab: MeetingTab = .summary
    @Environment(\.colorScheme) private var colorScheme

    private let panelRadius: CGFloat = 22
    private let maxContentHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accordionHeader
            if isExpanded {
                tabBar
                tabContent
            }
        }
        .background(
            RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                .fill(panelBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
    }

    // MARK: - Accordion Header

    private var accordionHeader: some View {
        HStack(spacing: 8) {
            Image("IconMeetingNotes")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(width: 16, height: 16)

            Text("Meeting Notes")
                .font(FontManager.heading(size: 13, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))

            Text(formattedDate)
                .font(FontManager.metadata(size: 11, weight: .medium))
                .foregroundColor(Color("TertiaryTextColor"))

            Circle()
                .fill(Color("TertiaryTextColor").opacity(0.4))
                .frame(width: 3, height: 3)

            Text(formattedDuration)
                .font(FontManager.metadata(size: 11, weight: .medium))
                .foregroundColor(Color("TertiaryTextColor"))
                .monospacedDigit()

            if !meetingLanguage.isEmpty {
                Text(meetingLanguage.uppercased())
                    .font(FontManager.metadata(size: 10, weight: .medium))
                    .foregroundColor(Color("TertiaryTextColor"))
                    .kerning(0.3)
            }

            Spacer()

            Image(isExpanded ? "IconChevronTopSmall" : "IconChevronDownSmall")
                .resizable()
                .renderingMode(.template)
                .frame(width: 16, height: 16)
                .foregroundColor(Color("SecondaryTextColor"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
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
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ThinScrollView(maxHeight: maxContentHeight) {
            Group {
                switch selectedTab {
                case .summary:
                    summaryContent
                case .transcript:
                    transcriptContent
                case .notes:
                    notesContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    // MARK: - Summary Tab

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Parse the meetingSummary -- it's in Jot's rich text format.
            // For MVP, render as plain text with basic structure detection.
            let lines = meetingSummary.components(separatedBy: "\n").filter { !$0.isEmpty }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                meetingSummaryLine(line)
            }
        }
    }

    @ViewBuilder
    private func meetingSummaryLine(_ line: String) -> some View {
        let stripped = line
            .replacingOccurrences(of: "[[h1]]", with: "")
            .replacingOccurrences(of: "[[/h1]]", with: "")
            .replacingOccurrences(of: "[[h2]]", with: "")
            .replacingOccurrences(of: "[[/h2]]", with: "")

        if line.contains("[[h1]]") {
            Text(stripped)
                .font(FontManager.heading(size: 15, weight: .bold))
                .foregroundColor(Color("PrimaryTextColor"))
        } else if line.contains("[[h2]]") {
            Text(stripped)
                .font(FontManager.heading(size: 12, weight: .semibold))
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.top, 4)
        } else if line.hasPrefix("[ ] ") {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "square")
                    .font(.system(size: 11))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .padding(.top, 2)
                Text(String(line.dropFirst(4)))
                    .font(FontManager.body(size: 13))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .lineSpacing(2)
            }
        } else if line.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(Color("SecondaryTextColor").opacity(0.4))
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
                Text(String(line.dropFirst(2)))
                    .font(FontManager.body(size: 13))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .lineSpacing(2)
            }
        } else {
            Text(stripped)
                .font(FontManager.body(size: 13))
                .foregroundColor(Color("PrimaryTextColor"))
                .lineSpacing(3)
        }
    }

    // MARK: - Transcript Tab

    private var transcriptContent: some View {
        let segments = [TranscriptSegment].deserialized(from: meetingTranscript)

        return VStack(alignment: .leading, spacing: 6) {
            if segments.isEmpty {
                Text("No transcript available.")
                    .font(FontManager.body(size: 13))
                    .foregroundColor(Color("TertiaryTextColor"))
            } else {
                ForEach(segments) { segment in
                    HStack(alignment: .top, spacing: 8) {
                        Text(formatTimestamp(segment.timestamp))
                            .font(FontManager.metadata(size: 10, weight: .medium))
                            .foregroundColor(Color("TertiaryTextColor"))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)

                        Text(segment.text)
                            .font(FontManager.body(size: 13))
                            .foregroundColor(Color("PrimaryTextColor"))
                            .lineSpacing(2)
                    }
                }
            }
        }
    }

    // MARK: - Notes Tab

    private var notesContent: some View {
        TextEditor(text: $meetingManualNotes)
            .font(FontManager.body(size: 13))
            .foregroundColor(Color("PrimaryTextColor"))
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(8)
            .frame(minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color("SurfaceElevatedColor"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if meetingManualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add notes...")
                        .font(FontManager.body(size: 13))
                        .foregroundColor(Color("TertiaryTextColor"))
                        .allowsHitTesting(false)
                        .padding(.top, 9)
                        .padding(.leading, 13)
                }
            }
            .onChange(of: meetingManualNotes) { _, newValue in
                onNotesChanged?(newValue)
            }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: meetingDate)
    }

    private var formattedDuration: String {
        let hours = Int(meetingDuration) / 3600
        let minutes = (Int(meetingDuration) % 3600) / 60
        let seconds = Int(meetingDuration) % 60
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
        colorScheme == .dark ? Color("DetailPaneColor") : .white
    }

    private var tabSelectedBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }
}

// MARK: - Thin Scroll View

/// ScrollView with native indicators hidden and a custom thin capsule
/// indicator that only appears while scrolling, then fades out.
private struct ThinScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var isScrolling = false
    @State private var fadeTask: Task<Void, Never>?

    private let indicatorWidth: CGFloat = 3
    private let indicatorInset: CGFloat = 2
    private let minThumbHeight: CGFloat = 24

    var body: some View {
        ScrollView(.vertical) {
            content
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ContentHeightKey.self, value: geo.size.height)
                            .preference(key: ScrollOffsetKey.self, value: -geo.frame(in: .named("thinScroll")).origin.y)
                    }
                )
        }
        .scrollIndicators(.never)
        .coordinateSpace(name: "thinScroll")
        .frame(maxHeight: maxHeight)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ViewportHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .onPreferenceChange(ScrollOffsetKey.self) { newOffset in
            scrollOffset = newOffset
            showIndicator()
        }
        .onPreferenceChange(ViewportHeightKey.self) { viewportHeight = $0 }
        .overlay(alignment: .trailing) {
            if contentHeight > viewportHeight {
                indicator
            }
        }
    }

    private var indicator: some View {
        let ratio = viewportHeight / max(contentHeight, 1)
        let thumbHeight = max(viewportHeight * ratio, minThumbHeight)
        let trackSpace = viewportHeight - thumbHeight
        let maxScroll = contentHeight - viewportHeight
        let progress = maxScroll > 0 ? min(max(scrollOffset / maxScroll, 0), 1) : 0

        return Capsule()
            .fill(Color("SecondaryTextColor").opacity(0.35))
            .frame(width: indicatorWidth, height: thumbHeight)
            .offset(y: trackSpace * progress)
            .padding(.vertical, 3)
            .padding(.trailing, indicatorInset)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(isScrolling ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isScrolling)
    }

    private func showIndicator() {
        isScrolling = true
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            isScrolling = false
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
