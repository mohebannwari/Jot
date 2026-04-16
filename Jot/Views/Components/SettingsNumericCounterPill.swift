import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Minus / value / plus capsule used in settings (Backups "Keep last", Appearance body font size).
/// Double-click the value to type a number directly; +/- still adjust by one.
struct SettingsNumericCounterPill: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    @Binding var value: Int
    let range: ClosedRange<Int>

    @State private var isEditingValue = false
    @State private var editText = ""
    @FocusState private var valueFieldFocused: Bool

    /// Fixed width so the macOS text field does not expand the capsule (it ignores loose min/max frames).
    private var valueSlotWidth: CGFloat {
        let digits = max("\(range.lowerBound)".count, "\(range.upperBound)".count)
        return CGFloat(8 * digits + 8)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                commitIfEditing()
                value = max(range.lowerBound, value - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Group {
                if isEditingValue {
                    TextField("", text: $editText)
                        .font(FontManager.heading(size: 12, weight: .medium))
                        .tracking(-0.3)
                        .foregroundColor(Color("PrimaryTextColor"))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .controlSize(.small)
                        .focused($valueFieldFocused)
                        .frame(width: valueSlotWidth, height: 28)
                        .clipped()
                        .onSubmit { commitIfEditing() }
                } else {
                    Text("\(value)")
                        .font(FontManager.heading(size: 12, weight: .medium))
                        .tracking(-0.3)
                        .foregroundColor(Color("PrimaryTextColor"))
                        .frame(width: valueSlotWidth, height: 28, alignment: .center)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            beginEditing()
                        }
                }
            }

            Button {
                commitIfEditing()
                value = min(range.upperBound, value + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .background(
            Capsule()
                .fill(themeManager.tintedSettingsInnerPill(for: colorScheme))
        )
        // Only commit on focus *loss* (true → false), not while the field is waiting for async focus after double-click.
        .onChange(of: valueFieldFocused) { wasFocused, nowFocused in
            if wasFocused && !nowFocused {
                commitIfEditing()
            }
        }
    }

    private func beginEditing() {
        editText = "\(value)"
        isEditingValue = true
        DispatchQueue.main.async {
            valueFieldFocused = true
            #if os(macOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
            }
            #endif
        }
    }

    /// Applies typed digits clamped to `range`, or keeps the previous value if input is not a valid integer.
    private func commitIfEditing() {
        guard isEditingValue else { return }
        if let parsed = Int(editText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value = min(max(parsed, range.lowerBound), range.upperBound)
        }
        isEditingValue = false
        valueFieldFocused = false
        editText = ""
    }
}
