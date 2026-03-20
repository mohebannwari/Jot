//
//  ShareExtensionView.swift
//  ShareExtension
//

import SwiftUI

struct ShareExtensionView: View {
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    @Binding var extractedTitle: String
    @Binding var isReady: Bool

    @State private var title: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Save to Jot")
                .font(.headline)

            if isReady {
                TextField("Title (optional)", text: $title)
                    .textFieldStyle(.roundedBorder)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Extracting content...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(title.isEmpty ? nil : title)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isReady)
            }
        }
        .padding(20)
        .frame(width: 360, height: 160)
        .onChange(of: extractedTitle) { _, newTitle in
            if title.isEmpty {
                title = newTitle
            }
        }
    }
}
