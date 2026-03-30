//
//  EditContentInputSubmenu.swift
//  Jot
//
//  Compact input submenu for the floating toolbar's edit content action.
//

import SwiftUI

struct EditContentInputSubmenu: View {
    @State private var instruction = ""
    @FocusState private var isFocused: Bool
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("EDIT INSTRUCTION...", text: $instruction)
                .font(FontManager.metadata(size: 11, weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .textFieldStyle(.plain)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color("SurfaceTranslucentColor"))
                )
                .focused($isFocused)
                .onSubmit { submit() }
                .onKeyPress(.escape) { onDismiss(); return .handled }

            Button(action: submit) {
                Text("Edit")
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color("ButtonPrimaryBgColor"), in: Capsule())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
        }
        .padding(10)
        .frame(width: 220)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { isFocused = true }
    }

    private func submit() {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        instruction = ""
    }
}
