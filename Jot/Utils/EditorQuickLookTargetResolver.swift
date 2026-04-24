import Foundation

struct EditorQuickLookPreviewTarget {
    let url: URL
    let requiresSecurityScope: Bool
}

enum EditorQuickLookTargetResolver {
    static func resolveFileLinkPreviewTarget(path: String, bookmark: String) -> EditorQuickLookPreviewTarget? {
        if !bookmark.isEmpty, let resolvedURL = resolveFileLinkURL(path: path, bookmark: bookmark) {
            return EditorQuickLookPreviewTarget(url: resolvedURL, requiresSecurityScope: true)
        }

        guard let resolvedURL = resolveFileLinkURL(path: path, bookmark: "") else { return nil }
        return EditorQuickLookPreviewTarget(url: resolvedURL, requiresSecurityScope: false)
    }

    static func resolveFileLinkURL(path: String, bookmark: String) -> URL? {
        if !bookmark.isEmpty, let data = Data(base64Encoded: bookmark) {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved
            }
        }

        let fileURL = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: path) ? fileURL : nil
    }
}
