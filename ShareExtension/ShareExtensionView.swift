//
//  ShareExtensionView.swift
//  ShareExtension
//

import SwiftUI
import Combine

final class ShareViewModel: ObservableObject {
    @Published var isReady = false
    @Published var extractedTitle = ""
}

struct ShareExtensionView: View {
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    @ObservedObject var viewModel: ShareViewModel

    @State private var title: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Save to Jot")
                .font(.headline)

            if viewModel.isReady {
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
                .disabled(!viewModel.isReady)
            }
        }
        .padding(20)
        .frame(width: 360, height: 160)
        .onChange(of: viewModel.extractedTitle) { _, newTitle in
            if title.isEmpty {
                title = newTitle
            }
        }
    }
}
