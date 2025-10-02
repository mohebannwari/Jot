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

            // Search pill is provided by FloatingSearch; remove duplicate button

            // Independent: Bottom-center New note
            Button {
                onNewNote()
            } label: {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 16))
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .frame(width: 52, height: 40)
                    .background(Color("ButtonPrimaryBgColor"), in: RoundedRectangle(cornerRadius: 20))
                    .scaleEffect(isHoveringNewNote ? 1.05 : 1.0)
                    .shadow(
                        color: Color.black.opacity(isHoveringNewNote ? 0.12 : 0.08),
                        radius: isHoveringNewNote ? 8 : 4,
                        x: 0,
                        y: isHoveringNewNote ? 4 : 2
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                isHoveringNewNote = hovering
            }
            .animation(.easeInOut, value: isHoveringNewNote)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            // Independent: Bottom-right Theme toggle
            Button {
                themeManager.toggleTheme()
            } label: {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 16))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .frame(width: 40, height: 40)
                    .liquidGlass(in: Circle())
                    .scaleEffect(isHoveringTheme ? 1.1 : 1.0)
                    .shadow(
                        color: Color.black.opacity(isHoveringTheme ? 0.08 : 0.05),
                        radius: isHoveringTheme ? 6 : 3,
                        x: 0,
                        y: isHoveringTheme ? 3 : 1.5
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                isHoveringTheme = hovering
            }
            .animation(.easeInOut, value: isHoveringTheme)
            .padding(.trailing, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}
