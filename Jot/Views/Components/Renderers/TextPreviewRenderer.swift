//
//  TextPreviewRenderer.swift
//  Jot
//
//  Renders a text/code file preview inline in the note editor.
//

import SwiftUI

struct TextPreviewRenderer: View {
    let storedFilename: String
    let containerWidth: CGFloat
    let viewMode: FileViewMode

    @Environment(\.colorScheme) private var colorScheme
    @State private var content: String?
    @State private var loadFailed = false

    private static let codeExtensions: Set<String> = [
        "swift", "py", "js", "json", "xml", "html", "css",
        "ts", "go", "rs", "c", "cpp", "h"
    ]

    // Keep markdown/text previews taller as the preview widens so the reading
    // column does not turn into a very short strip in full-width mode.
    static func preferredHeight(for viewMode: FileViewMode) -> CGFloat {
        switch viewMode {
        case .full:
            return 420
        case .medium:
            return 280
        case .tag:
            return 200
        }
    }

    private var isCodeFile: Bool {
        let ext = (storedFilename as NSString).pathExtension.lowercased()
        return Self.codeExtensions.contains(ext)
    }

    private var contentFont: Font {
        isCodeFile
            ? .system(size: 13, design: .monospaced)
            : .system(size: 13)
    }

    private var previewHeight: CGFloat {
        Self.preferredHeight(for: viewMode)
    }

    var body: some View {
        Group {
            if loadFailed {
                placeholder("Unable to read file")
            } else if let content {
                ScrollView(.vertical) {
                    Text(content)
                        .font(contentFont)
                        .foregroundStyle(Color("PrimaryTextColor"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: containerWidth)
                .frame(height: previewHeight)
                .background(colorScheme == .dark ? Color("DetailPaneColor") : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
            } else {
                placeholder("Loading file...")
            }
        }
        .task {
            await loadContent()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(colorScheme == .dark ? Color("DetailPaneColor") : Color.white)
            .frame(maxWidth: containerWidth)
            .frame(height: previewHeight)
            .overlay {
                Text(message)
                    .jotUI(FontManager.uiLabel5(weight: .regular))
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
    }

    // MARK: - Loading

    private func loadContent() async {
        guard let url = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            loadFailed = true
            return
        }

        // Read only the first 64KB for the preview -- height is mode-dependent (tag/medium/full)
        // but capping bytes avoids memory pressure on large files.
        let maxPreviewBytes = 64 * 1024
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { handle.closeFile() }
            let data = handle.readData(ofLength: maxPreviewBytes)
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                content = fileSize > maxPreviewBytes ? text + "\n\n[truncated]" : text
            } else {
                loadFailed = true
            }
        } catch {
            loadFailed = true
        }
    }
}
