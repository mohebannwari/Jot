//
//  CreateFolderSheet.swift
//  Noty
//
//  Custom folder creation sheet with color picker
//

import SwiftUI

struct CreateFolderSheet: View {
    let onCreate: (String, String?) -> Void
    let onCancel: () -> Void
    let editingFolder: Folder?

    @State private var folderName: String
    @State private var selectedColorHex: String?
    @State private var isCustomColorPickerPresented = false
    @State private var customColor: Color = .gray
    @FocusState private var isNameFieldFocused: Bool

    private var isEditing: Bool { editingFolder != nil }

    init(onCreate: @escaping (String, String?) -> Void,
         onCancel: @escaping () -> Void,
         editingFolder: Folder? = nil) {
        self.onCreate = onCreate
        self.onCancel = onCancel
        self.editingFolder = editingFolder
        _folderName = State(initialValue: editingFolder?.name ?? "New Folder")
        _selectedColorHex = State(initialValue: editingFolder?.colorHex)
    }

    private static let presetColors: [(name: String, hex: String)] = [
        ("zinc", "#71717a"),
        ("red", "#ef4444"),
        ("yellow", "#facc15"),
        ("green", "#22c55e"),
        ("fuchsia", "#d946ef"),
        ("blue", "#2563eb"),
    ]

    private let circleSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 16) {
            nameInputRow

            colorSection

            buttonSection
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .frame(width: 357)
        .onAppear {
            isNameFieldFocused = true
        }
    }

    // MARK: - Name Input

    private var nameInputRow: some View {
        HStack(spacing: 8) {
            TextField("Folder name", text: $folderName)
                .font(FontManager.heading(size: 15, weight: .medium))
                .tracking(-0.5)
                .foregroundColor(Color("PrimaryTextColor"))
                .textFieldStyle(.plain)
                .focused($isNameFieldFocused)
                .onSubmit { submitCreate() }

            if !folderName.isEmpty {
                Button {
                    folderName = ""
                } label: {
                    Image("IconCircleX")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color("SurfaceDefaultColor"))
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
        .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 0)
    }

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image("IconColorSwatch")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 18, height: 18)

                Text("Choose folder color")
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .tracking(-0.4)
            }
            .padding(.horizontal, 4)

            HStack {
                ForEach(Self.presetColors, id: \.hex) { preset in
                    colorCircle(hex: preset.hex)
                }

                customColorButton
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func colorCircle(hex: String) -> some View {
        let isSelected = selectedColorHex == hex
        return Button {
            HapticManager.shared.buttonTap()
            withAnimation(.notyBounce) {
                selectedColorHex = hex
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: circleSize, height: circleSize)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.08 : 1.0)
        .animation(.notyBounce, value: isSelected)
    }

    private var customColorButton: some View {
        ZStack {
            if let hex = selectedColorHex, !Self.presetColors.contains(where: { $0.hex == hex }) {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: circleSize, height: circleSize)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
            } else {
                Circle()
                    .fill(Color("SurfaceTranslucentColor"))
                    .frame(width: circleSize, height: circleSize)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                Color("BorderSubtleColor"),
                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                            )
                    )
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color("SecondaryTextColor"))
                    )
            }
        }
        .overlay {
            ColorPicker("", selection: $customColor, supportsOpacity: false)
                .labelsHidden()
                .opacity(0.015)
        }
        .onChange(of: customColor) { _, newColor in
            selectedColorHex = newColor.toHexString()
        }
    }

    // MARK: - Buttons

    private var buttonSection: some View {
        VStack(spacing: 8) {
            Button {
                submitCreate()
            } label: {
                Text(isEditing ? "Save" : "Create")
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(Color("ButtonPrimaryBgColor"))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)

            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(FontManager.heading(size: 12, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(Color("PrimaryTextColor"))
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func submitCreate() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticManager.shared.buttonTap()
        onCreate(trimmed, selectedColorHex)
    }
}

// MARK: - Color to Hex

private extension Color {
    func toHexString() -> String {
        #if os(macOS)
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = nsColor.redComponent
        let g = nsColor.greenComponent
        let b = nsColor.blueComponent
        #else
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil)
        #endif
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
