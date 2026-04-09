//
//  QuickNotePanel.swift
//  Jot
//
//  Floating panel for Quick Notes capture. Three tightly-coupled types live
//  together in this file because they're small and reading them together is
//  clearer than splitting them across three files:
//    1. QuickNotePanelWindow      — borderless NSPanel subclass
//    2. QuickNoteWindowController — singleton owning the panel lifecycle
//    3. QuickNotePanelView        — SwiftUI plain-text editor inside the panel
//

import AppKit
import SwiftUI
import os

// MARK: - NSPanel subclass

/// Borderless NSPanel that can become key (so its text fields accept input)
/// but never becomes main (so it never steals the main-window role from
/// ContentView). The borderless style is required to drop Apple's window
/// chrome (rounded rect, traffic lights, titlebar) — without it, our custom
/// liquid-glass surface would render *inside* a second outer rectangle.
final class QuickNotePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Window controller

@MainActor
final class QuickNoteWindowController {

    static let shared = QuickNoteWindowController()

    private var panel: QuickNotePanelWindow?
    private weak var previousApp: NSRunningApplication?
    private let logger = Logger(subsystem: "com.jot", category: "QuickNoteWindowController")

    private init() {}

    // MARK: - Public

    /// Show the panel. Captures the currently frontmost app so focus can be
    /// restored on dismiss. If the panel is already visible, brings it forward
    /// without resetting content.
    func showPanel() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if panel == nil {
            panel = makePanel()
        }

        guard let panel = panel else { return }

        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        // Reset to empty content by rebuilding the hosting view. Cheap and
        // guarantees @State goes back to defaults without any indirection.
        installContent(into: panel)

        // Do NOT call center() here — the frame autosave restores the user's
        // last position. Centering on every show would defeat that.
        panel.alphaValue = 1.0
        panel.makeKeyAndOrderFront(nil)
        logger.info("Showed Quick Note panel")
    }

    /// Dismiss the panel with a brief fade-out, then return focus to whichever
    /// app was frontmost before the panel appeared.
    func dismissPanel(saved: Bool) {
        guard let panel = panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            // The completion handler is typed as a plain closure, not
            // @MainActor, but NSAnimationContext always delivers it on the
            // main queue. Hop explicitly to satisfy strict concurrency.
            DispatchQueue.main.async {
                panel.orderOut(nil)
                panel.alphaValue = 1.0
                self?.previousApp?.activate()
                self?.previousApp = nil
            }
        })
    }

    // MARK: - Panel construction

    private func makePanel() -> QuickNotePanelWindow {
        let initialSize = NSSize(width: 600, height: 400)
        let rect = NSRect(origin: .zero, size: initialSize)

        // Borderless + nonactivating + resizable. No .titled, no .closable —
        // the SwiftUI surface is the entire chrome.
        let panel = QuickNotePanelWindow(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // Make the window itself transparent so only the SwiftUI rounded glass
        // is visible. hasShadow still works because the glass content is opaque.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Reasonable lower bound so the user can't shrink past usability.
        panel.minSize = NSSize(width: 360, height: 240)

        // Try to restore the user's last position; only center if there is none.
        let autosaveKey = "NSWindow Frame QuickNotePanel"
        let hasSavedFrame = UserDefaults.standard.string(forKey: autosaveKey) != nil
        panel.setFrameAutosaveName("QuickNotePanel")
        if !hasSavedFrame {
            panel.center()
        }

        installContent(into: panel)
        return panel
    }

    private func installContent(into panel: QuickNotePanelWindow) {
        let rootView = QuickNotePanelView(
            onSave: { [weak self] title, body in
                QuickNoteService.shared.save(title: title, body: body)
                self?.dismissPanel(saved: true)
            },
            onCancel: { [weak self] in
                self?.dismissPanel(saved: false)
            }
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }
}

// MARK: - SwiftUI content

struct QuickNotePanelView: View {

    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var showSavedCheckmark: Bool = false
    @FocusState private var focus: Field?
    @Environment(\.colorScheme) private var colorScheme

    private enum Field { case title, body }

    private var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(FontManager.heading(size: 22, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 12)
                .focused($focus, equals: .title)
                .onSubmit {
                    focus = .body
                }

            Divider()
                .padding(.horizontal, 24)

            TextEditor(text: $bodyText)
                .scrollContentBackground(.hidden)
                .font(FontManager.body(size: 15))
                .foregroundColor(Color("PrimaryTextColor"))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .focused($focus, equals: .body)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            // Tiny delay so the window is actually key before focus tries to land.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                focus = .title
            }
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if showSavedCheckmark {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved")
                        .font(FontManager.metadata(size: 11, weight: .semibold))
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .transition(.opacity)
            } else {
                Text("\u{2318}\u{21A9} save \u{00B7} esc cancel")
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
            }

            Spacer()

            saveButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// The Save button is also the Cmd+Return accelerator — one button serves
    /// both the visible and keyboard paths.
    private var saveButton: some View {
        Button(action: performSave) {
            Text("Save")
                .font(FontManager.heading(size: 13, weight: .semibold))
                .foregroundColor(Color("ButtonPrimaryTextColor"))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        hasContent
                            ? Color("ButtonPrimaryBgColor")
                            : Color("ButtonPrimaryBgColor").opacity(0.35)
                    )
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!hasContent)
        .macPointingHandCursor()
    }

    // MARK: - Save action

    private func performSave() {
        guard hasContent else { return }

        withAnimation(.easeIn(duration: 0.15)) {
            showSavedCheckmark = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onSave(title, bodyText)
        }
    }
}
