import SwiftUI

struct MarkingsView: View {
    @EnvironmentObject private var markingStore: MarkingStore
    @EnvironmentObject private var notesManager: SimpleSwiftDataManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedFilter: MarkingStore.TimeFilter = .thisWeek
    @State private var hoveredDeleteID: UUID?
    @State private var hoveredShowID: UUID?

    var onShowInNote: ((UUID, String) -> Void)?
    var onDeleteMarking: ((Marking) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Title
                Text("Your markings")
                    .font(FontManager.heading(size: 26, weight: .medium))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .tracking(-1)

                // Filter tabs + content
                VStack(alignment: .leading, spacing: 28) {
                    filterTabs

                    let groups = markingStore.grouped(by: selectedFilter)
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups, id: \.day) { group in
                            daySection(day: group.day, items: group.items)
                        }
                    }
                }
            }
            .frame(maxWidth: 482, alignment: .leading)
            .padding(.bottom, 8)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 80)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        HStack(spacing: 8) {
            ForEach(MarkingStore.TimeFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(FontManager.heading(size: 13, weight: .medium))
                        .tracking(-0.4)
                        .foregroundColor(
                            selectedFilter == filter
                                ? Color("ButtonPrimaryTextColor")
                                : Color("PrimaryTextColor")
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if selectedFilter == filter {
                                Capsule().fill(Color("ButtonPrimaryBgColor"))
                            } else {
                                Capsule()
                                    .fill(Color("BackgroundColor"))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color("BorderSubtleColor"), lineWidth: 1)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Day Section

    private func daySection(day: String, items: [Marking]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.uppercased())
                .font(FontManager.metadata(size: 11, weight: .medium))
                .tracking(-0.2)
                .foregroundColor(Color("SecondaryTextColor"))

            ForEach(items) { marking in
                markingCard(marking)
            }
        }
    }

    // MARK: - Marking Card

    private func markingCard(_ marking: Marking) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(marking.noteTitle)
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(Color("PrimaryTextColor"))
                    .lineLimit(1)

                Text(marking.markedText)
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(Color("SecondaryTextColor"))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button {
                    onShowInNote?(marking.noteID, marking.markedText)
                } label: {
                    let isHovered = hoveredShowID == marking.id
                    HStack(spacing: 4) {
                        Image("IconShowInNote")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .rotationEffect(.degrees(180))
                            .scaleEffect(y: -1)
                            .offset(x: isHovered ? -2 : 0, y: isHovered ? -2 : 0)
                            .animation(.easeInOut(duration: 0.2), value: isHovered)

                        Text("Show in note")
                            .font(FontManager.heading(size: 13, weight: .medium))
                            .tracking(-0.4)
                    }
                    .foregroundColor(Color("PrimaryTextColor"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color("SurfaceElevatedColor"))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color("BorderSubtleColor"), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredShowID = hovering ? marking.id : nil
                }

                Spacer()

                Button {
                    onDeleteMarking?(marking)
                } label: {
                    Image("IconTrashRounded")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundColor(hoveredDeleteID == marking.id ? .red : Color("IconSecondaryColor"))
                        .animation(.easeInOut(duration: 0.15), value: hoveredDeleteID)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredDeleteID = hovering ? marking.id : nil
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color("MarkingCardBgColor"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("IconHighlight")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundColor(Color("SecondaryTextColor"))

            Text("No markings yet")
                .font(FontManager.heading(size: 15, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))

            Text("Select text and tap the marker tool to save markings.")
                .font(FontManager.heading(size: 13, weight: .medium))
                .foregroundColor(Color("TertiaryTextColor"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
