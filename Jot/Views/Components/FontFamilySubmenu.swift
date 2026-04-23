//
//  FontFamilySubmenu.swift
//  Jot
//
//  Dropdown for per-selection font family: SF Pro (system), Mono, Charter (serif).
//

import SwiftUI

struct FontFamilySubmenu: View {
    var currentFamily: String  // "default", "system", "mono"
    var onFamilySelected: ((BodyFontStyle) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var isRevealed = false

    private let families: [(style: BodyFontStyle, label: String)] = [
        (.system, "SF Pro"),
        (.mono, "Mono"),
        (.default, "Charter"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(families.enumerated()), id: \.element.style.rawValue) { index, item in
                familyRow(item.style, label: item.label)
                    .opacity(isRevealed ? 1 : 0)
                    .offset(y: isRevealed ? 0 : 8)
                    .scaleEffect(isRevealed ? 1 : 0.92, anchor: .top)
                    .animation(
                        .bouncy(duration: 0.4).delay(Double(index) * 0.03),
                        value: isRevealed
                    )
            }
        }
        .padding(4)
        .frame(width: 140)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isRevealed = true
            }
        }
    }

    private func familyRow(_ style: BodyFontStyle, label: String) -> some View {
        FontFamilyRow(style: style, label: label, isSelected: currentFamily == style.rawValue, font: fontFor(style, size: 13)) {
            HapticManager.shared.toolbarAction()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onFamilySelected?(style)
            }
            onDismiss?()
        }
    }

    private func fontFor(_ style: BodyFontStyle, size: CGFloat) -> Font {
        switch style {
        case .default:
            return Font.custom("Charter", size: size).weight(.medium)
        case .system:
            return Font.system(size: size, weight: .medium)
        case .mono:
            return Font.system(size: size, weight: .medium, design: .monospaced)
        }
    }
}

private struct FontFamilyRow: View {
    let style: BodyFontStyle
    let label: String
    let isSelected: Bool
    let font: Font
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(font)
                    .foregroundColor(isSelected ? Color("AccentColor") : Color("PrimaryTextColor"))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(FontManager.uiTiny(weight: .bold).font)
                        .foregroundColor(Color("AccentColor"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isHovered ? Color("PrimaryTextColor").opacity(0.08) : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered { NSCursor.pop() }
        }
    }
}
