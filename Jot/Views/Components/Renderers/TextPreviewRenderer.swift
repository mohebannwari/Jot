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

    @State private var content: String?
    @State private var loadFailed = false

    private let maxHeight: CGFloat = 200

    private static let codeExtensions: Set<String> = [
        "swift", "py", "js", "json", "xml", "html", "css",
        "ts", "go", "rs", "c", "cpp", "h"
    ]

    private var isCodeFile: Bool {
        let ext = (storedFilename as NSString).pathExtension.lowercased()
        return Self.codeExtensions.contains(ext)
    }

    private var contentFont: Font {
        isCodeFile
            ? .system(size: 13, design: .monospaced)
            : .system(size: 13)
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
                .frame(maxHeight: maxHeight)
                .background(Color("SurfaceElevatedColor"))
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
            .fill(Color("SurfaceElevatedColor"))
            .frame(maxWidth: containerWidth)
            .frame(height: maxHeight)
            .overlay {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
    }

    // MARK: - Loading

    private func loadContent() async {
        guard let url = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            loadFailed = true
            return
        }

        // Read only the first 64KB for the preview -- full file load is unnecessary
        // for a 200pt scroll view and avoids memory pressure on large files.
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
