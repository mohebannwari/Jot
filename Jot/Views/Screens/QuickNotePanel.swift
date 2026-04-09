//
//  QuickNotePanel.swift
//  Jot
//
//  Floating panel for Quick Notes capture. Three tightly-coupled types live
//  together in this file because they're small and reading them together is
//  clearer than splitting them across three files:
//    1. QuickNotePanelWindow     — NSPanel subclass (can become key, not main)
//    2. QuickNoteWindowController — singleton owning the panel lifecycle
//    3. QuickNotePanelView        — SwiftUI plain-text editor inside the panel
//

import AppKit
import SwiftUI
import os

// MARK: - NSPanel subclass

/// NSPanel that can become key (so its text fields accept input) but never
/// becomes main (so it never steals the main-window role from ContentView).
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

        panel.center()
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
        let size = NSSize(width: 480, height: 320)
        let rect = NSRect(origin: .zero, size: size)

        let panel = QuickNotePanelWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("QuickNotePanel")
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear

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
        panel.contentView = NSHostingView(rootView: rootView)
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

    var body: some View {
        ZStack {
            // Hidden save accelerator: captures Cmd+Return without rendering.
            Button("", action: performSave)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.plain)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(FontManager.heading(size: 20, weight: .semibold))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 10)
                    .focused($focus, equals: .title)
                    .onSubmit {
                        focus = .body
                    }

                Divider()
                    .padding(.horizontal, 20)

                TextEditor(text: $bodyText)
                    .scrollContentBackground(.hidden)
                    .font(FontManager.body(size: 14))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .focused($focus, equals: .body)

                footer
            }
        }
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        HStack {
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
                Text("\u{2318}\u{21A9} to save \u{00B7} esc to cancel")
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Save action

    private func performSave() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else {
            // Nothing to save — cancel silently.
            onCancel()
            return
        }

        withAnimation(.easeIn(duration: 0.15)) {
            showSavedCheckmark = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onSave(title, bodyText)
        }
    }
}
