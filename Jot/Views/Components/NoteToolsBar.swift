//
//  NoteToolsBar.swift
//  Jot
//
//  Horizontal icon bar at the bottom-left of the detail pane.
//  Mirrors the "/" command menu functionality: image upload, voice record,
//  to-do, insert link, and share.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NoteToolsBar: View {
    let note: Note
    var editorInstanceID: UUID? = nil

    private let iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 2) {
            toolButton(icon: "gallery", tooltip: "Image Upload") {
                postToolAction(.imageUpload)
            }
            toolButton(icon: "mic-recording", tooltip: "Voice Record") {
                postToolAction(.voiceRecord)
            }
            toolButton(icon: "todo-list", tooltip: "To-Do") {
                postToolAction(.todo)
            }
            toolButton(icon: "insert link", tooltip: "Insert Link") {
                postToolAction(.link)
            }
            toolButton(icon: "IconPageTextSearch", tooltip: "Search on Page") {
                postToolAction(.searchOnPage)
            }
            #if os(macOS)
            ShareToolButton(note: note, iconSize: iconSize)
                .frame(width: iconSize, height: iconSize)
                .padding(4)
                .hoverContainer(cornerRadius: 8)
            #endif
        }
    }

    private func toolButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("IconSecondaryColor"))
                .frame(width: iconSize, height: iconSize)
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .help(tooltip)
        .hoverContainer(cornerRadius: 8)
    }

    private func postToolAction(_ tool: EditTool) {
        var userInfo: [String: Any] = [:]
        if let eid = editorInstanceID { userInfo["editorInstanceID"] = eid }
        NotificationCenter.default.post(
            name: .noteToolsBarAction,
            object: tool.rawValue,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }
}

// MARK: - macOS Share Button

#if os(macOS)
private struct ShareToolButton: NSViewRepresentable {
    let note: Note
    let iconSize: CGFloat

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(named: "IconShareOs")
        button.image?.isTemplate = true
        button.contentTintColor = NSColor(named: "IconSecondaryColor")
        button.imageScaling = .scaleProportionallyUpOrDown
        button.setFrameSize(NSSize(width: iconSize, height: iconSize))
        button.target = context.coordinator
        button.action = #selector(Coordinator.showSharePicker(_:))
        button.toolTip = "Share"
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.note = note
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(note: note)
    }

    class Coordinator: NSObject {
        var note: Note

        init(note: Note) {
            self.note = note
        }

        @objc func showSharePicker(_ sender: NSButton) {
            var shareText = note.title
            if !note.content.isEmpty {
                shareText += "\n\n" + note.content.strippingColorMarkup
            }
            let picker = NSSharingServicePicker(items: [shareText])
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
#endif
