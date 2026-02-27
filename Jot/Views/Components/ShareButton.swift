//
//  ShareButton.swift
//  Jot
//
//  Share button that presents the system sharing sheet.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ShareButton: View {
    let note: Note

    var body: some View {
        #if os(macOS)
        ShareButtonMac(note: note)
            .frame(width: 18, height: 18)
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)
private struct ShareButtonMac: NSViewRepresentable {
    let note: Note

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(named: "IconShareOs")
        button.image?.isTemplate = true
        button.contentTintColor = NSColor(named: "SecondaryTextColor")
        button.imageScaling = .scaleProportionallyUpOrDown
        button.setFrameSize(NSSize(width: 18, height: 18))
        button.target = context.coordinator
        button.action = #selector(Coordinator.showSharePicker(_:))
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
