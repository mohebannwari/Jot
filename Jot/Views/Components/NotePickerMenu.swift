//
//  NotePickerMenu.swift
//  Jot
//
//  Note picker menu that appears when typing "@" in the text editor.
//  Allows linking to other notes via inline notelinks.
//  Mirrors CommandMenu styling with Liquid Glass.
//

import SwiftUI

enum NotePickerLayout {
    static let itemHeight: CGFloat = 32
    static let itemSpacing: CGFloat = 0
    static let defaultMaxHeight: CGFloat = 240
    static let width: CGFloat = 200
    static let outerPadding: CGFloat = 10

    static func idealHeight(for itemCount: Int, maxHeight: CGFloat = defaultMaxHeight) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let contentHeight = CGFloat(itemCount) * itemHeight + CGFloat(max(0, itemCount - 1)) * itemSpacing
        return min(maxHeight, contentHeight)
    }
}

/// A lightweight struct carrying just enough note info for the picker.
/// Avoids importing the full Note model into the menu layer.
struct NotePickerItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let preview: String
}

/// A lightweight struct for displaying backlink references.
struct BacklinkItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let colorHex: String?
}

/// Note picker menu displaying a filterable list of notes.
/// Appears when user types "@" and supports arrow key navigation.
struct NotePickerMenu: View {
    let notes: [NotePickerItem]
    @Binding var selectedIndex: Int
    @Binding var isRevealed: Bool
    var onSelect: ((NotePickerItem) -> Void)?

    private let glassShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        NotePickerMenuItem(
                            note: note,
                            isSelected: index == selectedIndex
                        )
                        .id(index)
                        .opacity(isRevealed ? 1 : 0)
                        .offset(y: isRevealed ? 0 : 8)
                        .scaleEffect(isRevealed ? 1 : 0.92, anchor: .top)
                        .animation(
                            .bouncy(duration: 0.4).delay(Double(min(index, 5)) * 0.03),
                            value: isRevealed
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect?(note)
                        }
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(width: NotePickerLayout.width)
        .frame(maxHeight: NotePickerLayout.idealHeight(for: notes.count))
        .padding(NotePickerLayout.outerPadding)
        .notePickerGlass(in: glassShape)
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        .scaleEffect(isRevealed ? 1.0 : 0.35, anchor: .top)
        .opacity(isRevealed ? 1 : 0)
    }
}

// MARK: - Glass

private extension View {
    @ViewBuilder
    func notePickerGlass(in shape: some Shape) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(true), in: shape)
                .glassEffectTransition(.materialize)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
    }
}

// MARK: - Menu Item

struct NotePickerMenuItem: View {
    let note: NotePickerItem
    let isSelected: Bool

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isHighlighted: Bool { isSelected || isHovered }

    private var highlightedForegroundColor: Color {
        colorScheme == .dark ? .white : Color("PrimaryTextColor")
    }

    private var highlightedBackgroundColor: Color {
        Color("HoverBackgroundColor").opacity(colorScheme == .dark ? 0.95 : 1.0)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image("IconNoteText")
                .renderingMode(.template)
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(isHighlighted ? highlightedForegroundColor.opacity(0.7) : .secondary)

            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(FontManager.heading(size: 13, weight: .medium))
                .foregroundStyle(isHighlighted ? highlightedForegroundColor : .primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(highlightedBackgroundColor)
                .opacity(isHighlighted ? 1 : 0)
        )
        .animation(.snappy(duration: 0.15), value: isHighlighted)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
