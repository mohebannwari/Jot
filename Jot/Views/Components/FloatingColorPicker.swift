//
//  FloatingColorPicker.swift
//  Jot
//
//  Companion color picker pill that appears alongside FloatingEditToolbar
//  when text is selected. Contains 5 preset color circles + custom color button.
//

import SwiftUI
import AppKit

struct FloatingColorPicker: View {
    var onColorSelected: (String) -> Void
    var onRemove: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var circlesVisible = false
    @State private var pressedHex: String? = nil
    @State private var hoveredHex: String? = nil
    @State private var customColor: Color? = nil

    private let colors: [(name: String, hex: String)] = [
        ("red",     "#ef4444"),
        ("yellow",  "#facc15"),
        ("green",   "#22c55e"),
        ("fuchsia", "#d946ef"),
        ("blue",    "#3b82f6"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(colors, id: \.hex) { color in
                colorCircle(hex: color.hex)
            }
            customColorButton
            if let onRemove {
                removeButton(action: onRemove)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .liquidGlass(in: Capsule())
        .animation(.bouncy(duration: 0.4), value: circlesVisible)
        .onDisappear {
            // Tear down stale ColorPanelObserver to prevent ghost color changes
            let panel = NSColorPanel.shared
            panel.setTarget(nil)
            panel.setAction(nil)
            objc_setAssociatedObject(panel, "colorObserver", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.bouncy(duration: 0.3)) {
                    circlesVisible = true
                }
            }
        }
    }

    private func colorCircle(hex: String) -> some View {
        let isHovered = hoveredHex == hex
        let isPressed = pressedHex == hex
        return Button {
            withAnimation(.bouncy(duration: 0.15)) { pressedHex = hex }
            onColorSelected(hex)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.bouncy(duration: 0.15)) { pressedHex = nil }
            }
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.88 : (circlesVisible ? 1.0 : 0.6))
        .opacity(circlesVisible ? 1 : 0)
        .animation(.bouncy(duration: 0.2), value: isHovered)
        .animation(.bouncy(duration: 0.15), value: isPressed)
        .onHover { hovering in
            hoveredHex = hovering ? hex : nil
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var customColorButton: some View {
        let hasCustom = customColor != nil
        return Button {
            openSystemColorPicker()
        } label: {
            ZStack {
                if let custom = customColor {
                    Circle()
                        .fill(custom)
                        .frame(width: 20, height: 20)
                } else {
                    Circle()
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .contentShape(Circle())
        .subtleHoverScale(1.06)
        .scaleEffect(circlesVisible ? 1.0 : 0.6)
        .opacity(circlesVisible ? 1.0 : 0)
        .animation(.bouncy(duration: 0.4), value: circlesVisible)
        .animation(.bouncy(duration: 0.2), value: hasCustom)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 20, height: 20)
                Image("delete")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundColor(.red)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .contentShape(Circle())
        .subtleHoverScale(1.06)
        .scaleEffect(circlesVisible ? 1.0 : 0.6)
        .opacity(circlesVisible ? 1.0 : 0)
        .animation(.bouncy(duration: 0.4), value: circlesVisible)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func openSystemColorPicker() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.setTarget(nil)
        panel.setAction(nil)

        // Use a one-shot observation to catch the user's color choice
        let observer = ColorPanelObserver { nsColor in
            let c = nsColor.usingColorSpace(.sRGB) ?? nsColor.usingColorSpace(.deviceRGB) ?? nsColor
            let hex = String(format: "#%02x%02x%02x",
                             Int(round(c.redComponent * 255)),
                             Int(round(c.greenComponent * 255)),
                             Int(round(c.blueComponent * 255)))
            customColor = Color(nsColor: c)
            onColorSelected(hex)
        }
        panel.setTarget(observer)
        panel.setAction(#selector(ColorPanelObserver.colorChanged(_:)))
        // Keep the observer alive by associating it with the panel
        objc_setAssociatedObject(panel, "colorObserver", observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        panel.orderFront(nil)
    }
}

private class ColorPanelObserver: NSObject {
    let handler: (NSColor) -> Void
    private var debounceTask: DispatchWorkItem?

    init(handler: @escaping (NSColor) -> Void) {
        self.handler = handler
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        // Debounce to avoid flooding undo stack + serialization on every drag frame
        debounceTask?.cancel()
        let color = sender.color
        let task = DispatchWorkItem { [weak self] in
            self?.handler(color)
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }
}

