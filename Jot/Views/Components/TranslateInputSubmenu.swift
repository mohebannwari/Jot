//
//  TranslateInputSubmenu.swift
//  Jot
//
//  Compact input submenu for the floating toolbar's translate action.
//

import SwiftUI

struct TranslateInputSubmenu: View {
    @State private var language = ""
    @FocusState private var isFocused: Bool
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("TARGET LANGUAGE...", text: $language)
                .font(FontManager.metadata(size: 11, weight: .medium))
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
                Text("Translate")
                    .jotUI(FontManager.uiLabel4(weight: .regular))
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color("ButtonPrimaryBgColor"), in: Capsule())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
        }
        .padding(10)
        .frame(width: 200)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { isFocused = true }
    }

    private func submit() {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        language = ""
    }
}
