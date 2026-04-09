//
//  HotKeyRecorderView.swift
//  Jot
//
//  SwiftUI control that records a keyboard chord for the Quick Notes feature
//  by installing a local NSEvent monitor only while the user is in recording
//  mode. Rejects modifier-less chords (pure letter keys would block typing
//  system-wide if registered as a global hotkey).
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotKeyRecorderView: View {

    @Binding var hotKey: QuickNoteHotKey?
    let onChange: (QuickNoteHotKey?) -> Void

    @State private var isRecording: Bool = false
    @State private var errorMessage: String?
    @State private var localMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                Text(buttonLabel)
                    .font(FontManager.metadata(size: 11, weight: .semibold))
                    .foregroundColor(labelColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(buttonBackground)
                    )
                    .overlay(
                        Capsule().stroke(
                            isRecording ? Color.accentColor.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                    )
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()

            if hotKey != nil && !isRecording {
                Button(action: clearHotKey) {
                    Text("Clear")
                        .font(FontManager.metadata(size: 11, weight: .medium))
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(FontManager.metadata(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Labels and colors

    private var buttonLabel: String {
        if isRecording { return "Press a chord..." }
        if let hk = hotKey { return hk.displayString }
        return "Click to record"
    }

    private var labelColor: Color {
        if isRecording { return Color("PrimaryTextColor") }
        return hotKey == nil ? Color("SecondaryTextColor") : Color("PrimaryTextColor")
    }

    private var buttonBackground: Color {
        if isRecording {
            return Color.accentColor.opacity(0.15)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    // MARK: - Recording lifecycle

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        errorMessage = nil
        isRecording = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleEvent(event)
            return nil // swallow so the key doesn't reach any other responder
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        // Escape cancels recording without changing anything.
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let carbonMods = QuickNoteHotKey.carbonModifiers(from: event.modifierFlags)
        let candidate = QuickNoteHotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonMods
        )

        guard candidate.hasAnyModifier else {
            errorMessage = "Shortcut requires at least one modifier"
            return
        }

        hotKey = candidate
        errorMessage = nil
        onChange(candidate)
        stopRecording()
    }

    private func clearHotKey() {
        hotKey = nil
        errorMessage = nil
        onChange(nil)
    }
}
