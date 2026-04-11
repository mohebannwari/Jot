//
//  FilePreviewContent.swift
//  Jot
//
//  SwiftUI view for the inline file preview container.
//  Rendered inside FilePreviewOverlayView via NSHostingView.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - File Category

enum FileCategory {
    case pdf
    case image
    case audio
    case video
    case text
    case office
    case other

    static func classify(_ typeIdentifier: String) -> FileCategory {
        guard let utType = UTType(typeIdentifier) else { return .other }
        if utType.conforms(to: .pdf) { return .pdf }
        if utType.conforms(to: .image) { return .image }
        if utType.conforms(to: .audio) { return .audio }
        if utType.conforms(to: .movie) || utType.conforms(to: .video) { return .video }
        if utType.conforms(to: .plainText) || utType.conforms(to: .sourceCode)
            || utType.conforms(to: .html) || utType.conforms(to: .xml)
            || typeIdentifier == "net.daringfireball.markdown"
            || typeIdentifier == "public.markdown"
        { return .text }
        if typeIdentifier == "org.openxmlformats.wordprocessingml.document"
            || typeIdentifier == "org.openxmlformats.spreadsheetml.sheet"
            || typeIdentifier == "org.openxmlformats.presentationml.presentation"
            || utType.conforms(to: UTType("com.microsoft.word.doc") ?? .data)
            || utType.conforms(to: UTType("com.microsoft.excel.xls") ?? .data)
        { return .office }
        return .other
    }
}

// MARK: - File Preview Content

struct FilePreviewContent: View {
    let storedFilename: String
    let originalFilename: String
    let typeIdentifier: String
    let displayLabel: String
    var viewMode: FileViewMode
    let containerWidth: CGFloat

    var onViewModeChanged: ((FileViewMode) -> Void)?
    var onRename: ((String) -> Void)?
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    var onOpenInApp: (() -> Void)?

    @State private var appIcon: NSImage?
    @State private var appName: String = ""

    private var category: FileCategory {
        FileCategory.classify(typeIdentifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar
                .padding(.leading, 24)
                .padding(.trailing, 12)
                .padding(.top, 12)
            contentArea
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .thinLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task { detectDefaultApp() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 0) {
            fileNameButton
            Spacer()
            openInAppButton
        }
    }

    private var fileNameButton: some View {
        Button {
            showContextMenu()
        } label: {
            HStack(spacing: 2) {
                Text(originalFilename)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color("PrimaryTextColor"))
                    .lineLimit(1)
                Image("IconChevronDownSmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color("PrimaryTextColor"))
            }
        }
        .buttonStyle(.plain)
    }

    private var openInAppButton: some View {
        Button {
            onOpenInApp?()
        } label: {
            HStack(spacing: 4) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 15, height: 15)
                }
                Text("Open in \(appName)")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color("PrimaryTextColor"))
                    .lineLimit(1)
                Image("IconArrowRightUpCircle")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // NSHostingView in FilePreviewOverlayView is not in the app SwiftUI tree, so we cannot use
            // @EnvironmentObject(ThemeManager). Static NS tint matches FileAttachmentTagView / editor overlays.
            .background(
                Color(nsColor: ThemeManager.tintedSecondaryButtonBackgroundNS(isDark: colorScheme == .dark)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch category {
        case .pdf:
            PDFPreviewRenderer(storedFilename: storedFilename, containerWidth: contentWidth)
        case .image:
            ImagePreviewRenderer(storedFilename: storedFilename, containerWidth: contentWidth)
        case .audio:
            AudioPreviewRenderer(storedFilename: storedFilename, containerWidth: contentWidth)
        case .video:
            VideoPreviewRenderer(storedFilename: storedFilename, containerWidth: contentWidth)
        case .text:
            TextPreviewRenderer(
                storedFilename: storedFilename,
                containerWidth: contentWidth,
                viewMode: viewMode
            )
        case .office, .other:
            ThumbnailPreviewRenderer(storedFilename: storedFilename, containerWidth: contentWidth)
        }
    }

    private var contentWidth: CGFloat {
        containerWidth - 24 // 12pt padding each side
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()

        // View As submenu
        let viewAsItem = NSMenuItem(title: "View As", action: nil, keyEquivalent: "")
        let viewAsMenu = NSMenu()

        let mediumItem = NSMenuItem(title: "Medium", action: nil, keyEquivalent: "")
        mediumItem.state = viewMode == .medium ? .on : .off
        mediumItem.target = FilePreviewMenuTarget.shared
        mediumItem.action = #selector(FilePreviewMenuTarget.menuAction(_:))
        mediumItem.representedObject = FilePreviewMenuAction.viewMode(.medium, onViewModeChanged)
        viewAsMenu.addItem(mediumItem)

        let fullItem = NSMenuItem(title: "Full Width", action: nil, keyEquivalent: "")
        fullItem.state = viewMode == .full ? .on : .off
        fullItem.target = FilePreviewMenuTarget.shared
        fullItem.action = #selector(FilePreviewMenuTarget.menuAction(_:))
        fullItem.representedObject = FilePreviewMenuAction.viewMode(.full, onViewModeChanged)
        viewAsMenu.addItem(fullItem)

        let tagItem = NSMenuItem(title: "Display as Tag", action: nil, keyEquivalent: "")
        tagItem.state = viewMode == .tag ? .on : .off
        tagItem.target = FilePreviewMenuTarget.shared
        tagItem.action = #selector(FilePreviewMenuTarget.menuAction(_:))
        tagItem.representedObject = FilePreviewMenuAction.viewMode(.tag, onViewModeChanged)
        viewAsMenu.addItem(tagItem)

        viewAsItem.submenu = viewAsMenu
        menu.addItem(viewAsItem)

        menu.addItem(.separator())

        // Rename
        let renameItem = NSMenuItem(title: "Rename Attachment...", action: nil, keyEquivalent: "")
        renameItem.target = FilePreviewMenuTarget.shared
        renameItem.action = #selector(FilePreviewMenuTarget.menuAction(_:))
        renameItem.representedObject = FilePreviewMenuAction.rename(originalFilename, onRename)
        menu.addItem(renameItem)

        // Copy
        let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
        copyItem.target = FilePreviewMenuTarget.shared
        copyItem.action = #selector(FilePreviewMenuTarget.menuAction(_:))
        copyItem.representedObject = FilePreviewMenuAction.copy(onCopy)
        menu.addItem(copyItem)

        menu.addItem(.separator())

        // Delete
        let deleteItem = NSMenuItem(title: "Delete", action: nil, keyEquivalent: "")
        deleteItem.target = FilePreviewMenuTarget.shared
        deleteItem.action = #selector(FilePreviewMenuTarget.menuAction(_:))
        deleteItem.representedObject = FilePreviewMenuAction.delete(onDelete)
        menu.addItem(deleteItem)

        // Anchor menu to the window's content view at the current mouse position
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let windowPoint = window.mouseLocationOutsideOfEventStream
            let viewPoint = contentView.convert(windowPoint, from: nil)
            menu.popUp(positioning: nil, at: viewPoint, in: contentView)
        }
    }

    // MARK: - Default App Detection

    private func detectDefaultApp() {
        guard let fileURL = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            appName = "Finder"
            appIcon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: fileURL) {
            appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            let name = FileManager.default.displayName(atPath: appURL.path)
            appName = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        } else {
            appName = "Finder"
            appIcon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        }
    }
}

// MARK: - Menu Action Bridge

/// Bridges NSMenu actions to SwiftUI callbacks since NSMenuItem targets must be @objc.
enum FilePreviewMenuAction {
    case viewMode(FileViewMode, ((FileViewMode) -> Void)?)
    case rename(String, ((String) -> Void)?)
    case copy((() -> Void)?)
    case delete((() -> Void)?)
}

final class FilePreviewMenuTarget: NSObject {
    static let shared = FilePreviewMenuTarget()

    @objc func menuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? FilePreviewMenuAction else { return }
        switch action {
        case .viewMode(let mode, let callback):
            callback?(mode)
        case .rename(let currentName, let callback):
            showRenameDialog(currentName: currentName, callback: callback)
        case .copy(let callback):
            callback?()
        case .delete(let callback):
            callback?()
        }
    }

    private func showRenameDialog(currentName: String, callback: ((String) -> Void)?) {
        let alert = NSAlert()
        alert.messageText = "Rename Attachment"
        alert.informativeText = "Enter a new name for this attachment."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = currentName
        textField.isEditable = true
        textField.isSelectable = true
        alert.accessoryView = textField

        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty && newName != currentName {
                callback?(newName)
            }
        }
    }
}
