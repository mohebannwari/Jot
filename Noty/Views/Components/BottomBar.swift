//
//  BottomBar.swift
//  Noty
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI

struct BottomBar: View {
    var onNewNote: () -> Void
    @State private var isHoveringNewNote = false
    @State private var isHoveringTheme = false
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        ZStack(alignment: .bottom) {
            newNoteButton
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            themeToggleButton
                .padding(.trailing, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    // MARK: - Buttons

    private var newNoteButton: some View {
        Button {
            onNewNote()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.clear)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 20))

                RoundedRectangle(cornerRadius: 20)
                    .fill(Color("ButtonPrimaryBgColor"))
                    .allowsHitTesting(false)

                Text("New Note")
                    .font(FontManager.heading(size: 12, weight: .medium))
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .kerning(0)
                    .padding(.horizontal, 16)
            }
            .frame(height: 40)
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(isHoveringNewNote ? 1.05 : 1.0)
            .shadow(
                color: Color.black.opacity(isHoveringNewNote ? 0.08 : 0.06),
                radius: isHoveringNewNote ? 12 : 8,
                x: 0,
                y: isHoveringNewNote ? 6 : 4
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHoveringNewNote = hovering
        }
        .animation(.easeInOut, value: isHoveringNewNote)
    }

    private var themeToggleButton: some View {
        Button {
            themeManager.toggleTheme()
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .font(FontManager.heading(size: 16, weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .frame(width: 40, height: 40)
                .liquidGlass(in: Circle())
                .scaleEffect(isHoveringTheme ? 1.1 : 1.0)
                .shadow(
                    color: Color.black.opacity(isHoveringTheme ? 0.08 : 0.06),
                    radius: isHoveringTheme ? 12 : 8,
                    x: 0,
                    y: isHoveringTheme ? 6 : 4
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHoveringTheme = hovering
        }
        .animation(.easeInOut, value: isHoveringTheme)
    }
}
