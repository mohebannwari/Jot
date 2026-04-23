//
//  FontSizeSubmenu.swift
//  Jot
//
//  Vertical dropdown for the font size pill. Range 9-18 + custom input.
//

import SwiftUI

struct FontSizeSubmenu: View {
    var currentSize: CGFloat
    var onSizeSelected: ((CGFloat) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var isRevealed = false
    @State private var customSizeText = ""
    @FocusState private var isCustomFieldFocused: Bool

    private let sizes: [CGFloat] = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(sizes.enumerated()), id: \.element) { index, size in
                        sizeRow(size)
                            .opacity(isRevealed ? 1 : 0)
                            .offset(y: isRevealed ? 0 : 8)
                            .scaleEffect(isRevealed ? 1 : 0.92, anchor: .top)
                            .animation(
                                .bouncy(duration: 0.4).delay(Double(index) * 0.03),
                                value: isRevealed
                            )
                    }
                }
            }
            .frame(maxHeight: 240)

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            // Custom size input
            HStack(spacing: 6) {
                TextField("Custom", text: $customSizeText)
                    .jotUI(FontManager.uiLabel3(weight: .medium))
                    .textFieldStyle(.plain)
                    .frame(width: 52)
                    .focused($isCustomFieldFocused)
                    .onSubmit {
                        if let val = Double(customSizeText), val >= 1, val <= 200 {
                            onSizeSelected?(CGFloat(val))
                            onDismiss?()
                        }
                    }
                Text("pt")
                    .jotUI(FontManager.uiLabel5(weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .padding(4)
        .frame(width: 120)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isRevealed = true
            }
        }
    }

    private func sizeRow(_ size: CGFloat) -> some View {
        let isSelected = abs(currentSize - size) < 0.5
        return SubmenuRowButton(icon: nil, label: "\(Int(size))", isActive: isSelected) {
            HapticManager.shared.toolbarAction()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onSizeSelected?(size)
            }
            onDismiss?()
        }
    }
}
