//
//  TodoRichTextEditor.swift
//  Noty
//
//  Rebuilt rich text editor that keeps todo checkboxes aligned,
//  clickable, and in sync with serialized markup.
//

import Combine
import SwiftUI

#if os(macOS)
    import AppKit
    import QuartzCore
    import CoreImage
    import UniformTypeIdentifiers
    import QuickLook
#else
    import UIKit
    import UniformTypeIdentifiers
#endif

extension NSAttributedString.Key {
    fileprivate static let webClipTitle = NSAttributedString.Key("WebClipTitle")
    fileprivate static let webClipDescription = NSAttributedString.Key("WebClipDescription")
    fileprivate static let webClipDomain = NSAttributedString.Key("WebClipDomain")
    fileprivate static let imageFilename = NSAttributedString.Key("ImageFilename")
    fileprivate static let fileStoredFilename = NSAttributedString.Key("FileStoredFilename")
    fileprivate static let fileOriginalFilename = NSAttributedString.Key("FileOriginalFilename")
    fileprivate static let fileTypeIdentifier = NSAttributedString.Key("FileTypeIdentifier")
    fileprivate static let fileDisplayLabel = NSAttributedString.Key("FileDisplayLabel")
}

private enum AttachmentMarkup {
    static let imageMarkupPrefix = "[[image|"
    static let imagePattern = #"\[\[image\|\|\|([^\]]+)\]\]"#
    static let imageRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: imagePattern,
        options: []
    )
    static let fileMarkupPrefix = "[[file|"
    static let filePattern = #"\[\[file\|([^|]+)\|([^|]+)\|([^\]]*)\]\]"#
    static let fileRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: filePattern,
        options: []
    )

    static func displayLabel(for storedFile: FileAttachmentStorageManager.StoredFile) -> String {
        #if canImport(UniformTypeIdentifiers)
        if #available(macOS 11.0, iOS 14.0, *) {
            if let type = UTType(storedFile.typeIdentifier) {
                if type.conforms(to: .pdf) { return "PDF" }
                if type.conforms(to: .image) { return "Image" }
                if type.conforms(to: .audio) { return "Audio" }
                if type.conforms(to: .movie) { return "Video" }
            }
        }
        #endif

        let ext = (storedFile.originalFilename as NSString).pathExtension
        if !ext.isEmpty {
            return ext.uppercased()
        }

        return "File"
    }

    static func sanitizedComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "]]", with: " ")
    }
}

// Notification names for floating toolbar coordination
extension Notification.Name {
    static let textSelectionChanged = Notification.Name("TextSelectionChanged")
}

#if os(macOS)
/// Dedicated attachment type so that we never lose the stored filename during round-trips.
private final class NoteImageAttachment: NSTextAttachment {
    let storedFilename: String

    init(filename: String) {
        self.storedFilename = filename
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteImageAttachment does not support init(coder:)")
    }
}

/// Attachment type that captures metadata for non-image files.
private final class NoteFileAttachment: NSTextAttachment {
    let storedFilename: String
    let originalFilename: String
    let typeIdentifier: String
    let displayLabel: String

    init(storedFilename: String, originalFilename: String, typeIdentifier: String, displayLabel: String) {
        self.storedFilename = storedFilename
        self.originalFilename = originalFilename
        self.typeIdentifier = typeIdentifier
        self.displayLabel = displayLabel
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteFileAttachment does not support init(coder:)")
    }
}

/// Preview image view that renders the attachment thumbnail with rounded corners and stroke.
private final class ImagePreviewView: NSImageView {
    var colorScheme: ColorScheme = .dark {
        didSet { updateAppearance() }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: 4)
        imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        imageView.layer?.cornerRadius = 8
        // Enable smoother corner radius rendering
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.allowsEdgeAntialiasing = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ImagePreviewView does not support init(coder:)")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(image: NSImage, displaySize: CGSize) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        imageView.layer?.contentsScale = scale
        frame.size = displaySize
        imageView.frame = bounds
        imageView.image = image
        let path = CGPath(
            roundedRect: CGRect(origin: .zero, size: displaySize),
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil)
        layer?.shadowPath = path
    }

    func animateEntrance() {
        guard let layer = layer else { return }
        layer.removeAnimation(forKey: "entranceTransform")
        layer.removeAnimation(forKey: "entranceOpacity")

        let initialTransform = CATransform3DMakeTranslation(0, 14, 0)
        layer.transform = initialTransform
        layer.opacity = 0

        let timing = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.24, 0.98)
        let duration: CFTimeInterval = 0.26

        let transformAnimation = CABasicAnimation(keyPath: "transform")
        transformAnimation.fromValue = initialTransform
        transformAnimation.toValue = CATransform3DIdentity
        transformAnimation.duration = duration
        transformAnimation.timingFunction = timing

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0
        opacityAnimation.toValue = 1
        opacityAnimation.duration = duration
        opacityAnimation.timingFunction = timing

        layer.add(transformAnimation, forKey: "entranceTransform")
        layer.add(opacityAnimation, forKey: "entranceOpacity")
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
    }

    private func updateAppearance() {
        layer?.shadowColor = (colorScheme == .dark
            ? NSColor.black.withAlphaComponent(0.6)
            : NSColor.black.withAlphaComponent(0.3)).cgColor
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    private let imageView = NSImageView()
}

#else
/// Dedicated attachment type so that we never lose the stored filename during round-trips.
private final class NoteImageAttachment: NSTextAttachment {
    let storedFilename: String

    init(filename: String) {
        self.storedFilename = filename
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteImageAttachment does not support init(coder:)")
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = NoteImageAttachment(filename: storedFilename)
        copy.image = self.image
        copy.bounds = self.bounds
        copy.fileWrapper = self.fileWrapper
        copy.contents = self.contents
        copy.attachmentCell = self.attachmentCell
        return copy
    }
}

/// Attachment type that captures metadata for non-image files.
private final class NoteFileAttachment: NSTextAttachment {
    let storedFilename: String
    let originalFilename: String
    let typeIdentifier: String
    let displayLabel: String

    init(storedFilename: String, originalFilename: String, typeIdentifier: String, displayLabel: String) {
        self.storedFilename = storedFilename
        self.originalFilename = originalFilename
        self.typeIdentifier = typeIdentifier
        self.displayLabel = displayLabel
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteFileAttachment does not support init(coder:)")
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = NoteFileAttachment(
            storedFilename: storedFilename,
            originalFilename: originalFilename,
            typeIdentifier: typeIdentifier,
            displayLabel: displayLabel
        )
        copy.image = self.image
        copy.bounds = self.bounds
        copy.fileWrapper = self.fileWrapper
        copy.contents = self.contents
        copy.attachmentCell = self.attachmentCell
        return copy
    }
}
#endif

struct TodoRichTextEditor: View {
    @Binding var text: String
    var onToolbarAction: ((EditTool) -> Void)?
    var onCommandMenuSelection: ((EditTool) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    private let baseBottomInset: CGFloat = 0

    @State private var showAISummary = false
    @State private var aiSummaryText = ""

    // Command menu state (triggered by "/" character)
    @State private var showCommandMenu = false
    @State private var commandMenuPosition: CGPoint = .zero
    @State private var commandMenuSelectedIndex = 0
    @State private var commandSlashLocation: Int = -1
    fileprivate static let commandMenuActions: [EditTool] = [.imageUpload, .voiceRecord, .link]
    fileprivate static let commandMenuBaseWidth: CGFloat = CommandMenuLayout.width
    fileprivate static let commandMenuOuterPadding: CGFloat = CommandMenuLayout.outerPadding
    fileprivate static let commandMenuHorizontalPadding = commandMenuOuterPadding * 2
    fileprivate static let commandMenuVerticalPadding = commandMenuOuterPadding * 2
    fileprivate static let commandMenuContentHeight: CGFloat = CommandMenuLayout.idealHeight(
        for: TodoRichTextEditor.commandMenuActions.count)
    fileprivate static let commandMenuTotalWidth: CGFloat =
        commandMenuBaseWidth + commandMenuHorizontalPadding
    fileprivate static let commandMenuTotalHeight: CGFloat =
        commandMenuContentHeight + commandMenuVerticalPadding
    private let commandMenuTools = TodoRichTextEditor.commandMenuActions

    // Static accessor for command menu showing flag (used by keyboard handlers)
    #if os(macOS)
    static var isCommandMenuShowing: Bool {
        get { InlineNSTextView.isCommandMenuShowing }
        set { InlineNSTextView.isCommandMenuShowing = newValue }
    }
    #else
    static var isCommandMenuShowing: Bool {
        get { DynamicHeightTextView.isCommandMenuShowing }
        set { DynamicHeightTextView.isCommandMenuShowing = newValue }
    }
    #endif

    #if os(iOS)
        @State private var keyboardInset: CGFloat = 0
    #endif

    init(
        text: Binding<String>,
        onToolbarAction: ((EditTool) -> Void)? = nil,
        onCommandMenuSelection: ((EditTool) -> Void)? = nil
    ) {
        print(
            "DEBUG: TodoRichTextEditor init called with text: '\(text.wrappedValue.prefix(100))...'"
        )
        self._text = text
        self.onToolbarAction = onToolbarAction
        self.onCommandMenuSelection = onCommandMenuSelection
    }

    private var bottomInset: CGFloat {
        #if os(iOS)
            return baseBottomInset + keyboardInset
        #else
            return baseBottomInset
        #endif
    }

    var body: some View {
        let _ = print(
            "DEBUG: TodoRichTextEditor body computed - text value: '\(text.prefix(100))...'")
        return Group {
            #if os(macOS)
                TodoEditorRepresentable(
                    text: $text, colorScheme: colorScheme, bottomInset: bottomInset)
            #else
                TodoEditorRepresentable(
                    text: $text, colorScheme: colorScheme, bottomInset: bottomInset)
            #endif
        }
        .frame(maxWidth: .infinity)  // Natural height based on content
        .background(Color.clear)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showCommandMenu {
                    CommandMenu(
                        tools: commandMenuTools,
                        selectedIndex: $commandMenuSelectedIndex,
                        onSelect: { tool in handleCommandMenuSelection(tool) },
                        maxHeight: 280
                    )
                    .offset(
                        x: clampedCommandMenuPosition(for: geometry.size).x,
                        y: clampedCommandMenuPosition(for: geometry.size).y
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                        )
                    )
                    .zIndex(1000)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showAISummary {
                AISummaryBox(
                    summaryText: aiSummaryText,
                    onDismiss: {
                        withAnimation(.bouncy(duration: 0.3)) {
                            showAISummary = false
                        }
                    }
                )
                .padding(.trailing, 16)
                .padding(.top, 16)
                .frame(maxWidth: 300)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(
                            with: .scale(scale: 0.9, anchor: .topTrailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing))
                    ))
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("TodoToolbarAction"))
        ) { _ in
            NotificationCenter.default.post(name: .insertTodoInEditor, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InsertWebLink"))) {
            notification in
            if let url = notification.object as? String {
                NotificationCenter.default.post(name: .insertWebClipInEditor, object: url)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("ShowAISummary"))
        ) { notification in
            if let summary = notification.object as? String {
                aiSummaryText = summary
                withAnimation(.bouncy(duration: 0.4)) {
                    showAISummary = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowCommandMenu")))
        { notification in
            if let info = notification.object as? [String: Any],
                let position = info["position"] as? CGPoint,
                let slashLocation = info["slashLocation"] as? Int
            {
                commandMenuPosition = position
                commandSlashLocation = slashLocation
                commandMenuSelectedIndex = 0

                withAnimation(.smooth(duration: 0.2)) {
                    showCommandMenu = true
                }

                #if os(macOS)
                    InlineNSTextView.isCommandMenuShowing = true
                #else
                    DynamicHeightTextView.isCommandMenuShowing = true
                #endif
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HideCommandMenu")))
        { _ in
            withAnimation(.smooth(duration: 0.15)) {
                showCommandMenu = false
            }
            commandSlashLocation = -1

            #if os(macOS)
                InlineNSTextView.isCommandMenuShowing = false
            #else
                DynamicHeightTextView.isCommandMenuShowing = false
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuNavigateUp")))
        { _ in
            if showCommandMenu && commandMenuSelectedIndex > 0 {
                commandMenuSelectedIndex -= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuNavigateDown")))
        { _ in
            let maxIndex = max(0, commandMenuTools.count - 1)
            if showCommandMenu && commandMenuSelectedIndex < maxIndex {
                commandMenuSelectedIndex += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuSelect")))
        { _ in
            if showCommandMenu {
                if commandMenuSelectedIndex < commandMenuTools.count {
                    handleCommandMenuSelection(commandMenuTools[commandMenuSelectedIndex])
                }
            }
        }
        #if os(iOS)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification)
            ) { notification in
                handleKeyboardChange(notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardInset = 0
                }
            }
        #endif
    }

    // MARK: - Command Menu Handlers

    private func handleCommandMenuSelection(_ tool: EditTool) {
        withAnimation(.smooth(duration: 0.15)) {
            showCommandMenu = false
        }

        #if os(macOS)
            InlineNSTextView.isCommandMenuShowing = false
        #else
            DynamicHeightTextView.isCommandMenuShowing = false
        #endif

        NotificationCenter.default.post(
            name: .applyCommandMenuTool,
            object: ["tool": tool, "slashLocation": commandSlashLocation]
        )

        if let onCommandMenuSelection {
            onCommandMenuSelection(tool)
        }

        commandSlashLocation = -1
    }

    private func clampedCommandMenuPosition(for containerSize: CGSize) -> CGPoint {
        let maxX = max(0, containerSize.width - TodoRichTextEditor.commandMenuTotalWidth)
        let maxY = max(0, containerSize.height - TodoRichTextEditor.commandMenuTotalHeight)
        let clampedX = min(max(commandMenuPosition.x, 0), maxX)
        let clampedY = min(max(commandMenuPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

    #if os(iOS)
        private func handleKeyboardChange(_ notification: Notification) {
            guard
                let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect,
                let window = keyWindow
            else { return }

            let keyboardHeight = max(0, window.frame.maxY - endFrame.minY)
            let safeArea = window.safeAreaInsets.bottom
            let effectiveInset = max(0, keyboardHeight - safeArea)

            let duration =
                notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
                ?? 0.25
            let curveRaw =
                notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
                ?? UIView.AnimationCurve.easeOut.rawValue
            let curve = UIView.AnimationCurve(rawValue: Int(curveRaw)) ?? .easeOut

            let animation: Animation
            switch curve {
            case .easeInOut:
                animation = .easeInOut(duration: duration)
            case .easeIn:
                animation = .easeIn(duration: duration)
            case .easeOut:
                animation = .easeOut(duration: duration)
            case .linear:
                animation = .linear(duration: duration)
            @unknown default:
                animation = .easeOut(duration: duration)
            }

            withAnimation(animation) {
                keyboardInset = effectiveInset
            }
        }

        private var keyWindow: UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })
        }
    #endif
}

// MARK: - Representable Implementations

#if os(macOS)

    struct TodoEditorRepresentable: NSViewRepresentable {
        @Binding var text: String
        let colorScheme: ColorScheme
        let bottomInset: CGFloat
        private let unlimitedDimension = CGFloat.greatestFiniteMagnitude

        func makeNSView(context: Context) -> InlineNSTextView {
            let textView = InlineNSTextView()
            textView.delegate = context.coordinator
            textView.actionDelegate = context.coordinator
            textView.isEditable = true
            textView.isSelectable = true
            textView.isRichText = true
            textView.importsGraphics = false
            textView.allowsUndo = true
            textView.backgroundColor = .clear
            textView.drawsBackground = false
            // Use Charter for body text as per design requirements
            textView.font = FontManager.bodyNS(size: 16, weight: .regular)
            textView.textColor = NSColor.labelColor
            textView.textContainerInset = NSSize(width: 0, height: 16)
            textView.linkTextAttributes = [
                .underlineStyle: 0,
                .underlineColor: NSColor.clear,
            ]
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: unlimitedDimension, height: unlimitedDimension)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]

            // Ensure text view can receive focus and input
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false

            // Critical: Ensure text view accepts text input
            textView.insertionPointColor = NSColor.controlAccentColor

            // Enable Writing Tools when text is selected (without standalone button)
            if #available(macOS 15.0, *) {
                textView.writingToolsBehavior = .complete
            }
            if let container = textView.textContainer {
                container.widthTracksTextView = true
                container.heightTracksTextView = false
                container.lineFragmentPadding = 0
                container.containerSize = NSSize(width: 600, height: unlimitedDimension)
            }

            // CRITICAL FIX: Use the passed colorScheme directly, not resolved from view
            // The view's appearance might not be set correctly yet at init time
            let initialScheme = colorScheme
            print("DEBUG: makeNSView - using passed colorScheme: \(initialScheme)")

            if let resolvedAppearance = appearance(for: initialScheme) {
                textView.appearance = resolvedAppearance
            }

            let resolvedColor = resolvedTextColor(
                for: initialScheme, appearance: textView.appearance)
            print("DEBUG: makeNSView - resolved text color: \(resolvedColor)")
            textView.textColor = resolvedColor
            textView.typingAttributes = Coordinator.baseTypingAttributes(for: initialScheme)
            textView.defaultParagraphStyle = Coordinator.baseParagraphStyle()

            context.coordinator.updateColorScheme(initialScheme)
            context.coordinator.configure(with: textView)

            // Apply initial text synchronously to ensure proper sizing calculation
            print("DEBUG: makeNSView - about to apply initial text: '\(text)'")
            context.coordinator.applyInitialText(text)

            // Ensure layout is complete before returning
            if let container = textView.textContainer, let layoutManager = textView.layoutManager {
                layoutManager.ensureLayout(for: container)
            }

            // Defer first responder setup to avoid focus issues
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }

            return textView
        }

        func updateNSView(_ nsView: InlineNSTextView, context: Context) {
            let textView = nsView
            // CRITICAL FIX: Use the passed colorScheme directly
            let resolvedScheme = colorScheme

            // Update appearance and colors
            if let resolvedAppearance = appearance(for: resolvedScheme) {
                textView.appearance = resolvedAppearance

                // Update text color with proper color scheme
                let resolvedColor = resolvedTextColor(
                    for: resolvedScheme, appearance: textView.appearance)
                textView.textColor = resolvedColor
                textView.typingAttributes = Coordinator.baseTypingAttributes(for: resolvedScheme)
                textView.linkTextAttributes = [
                    .underlineStyle: 0,
                    .underlineColor: NSColor.clear,
                ]
                context.coordinator.updateColorScheme(resolvedScheme)
            }

            // Update container size only if needed
            if let container = textView.textContainer, let layoutManager = textView.layoutManager {
                let width = textView.bounds.width
                if width > 0 && abs(container.containerSize.width - width) > 0.5 {
                    container.containerSize = NSSize(width: width, height: unlimitedDimension)
                    layoutManager.ensureLayout(for: container)
                }
            }

            // Only update text if it has actually changed
            context.coordinator.updateIfNeeded(with: text)
        }

        // Report dynamic size to SwiftUI so the editor grows with its content naturally
        func sizeThatFits(_ proposal: ProposedViewSize, nsView: InlineNSTextView, context: Context)
            -> CGSize
        {
            guard let container = nsView.textContainer,
                let layoutManager = nsView.layoutManager
            else {
                let fallbackWidth = proposal.width ?? 600
                return CGSize(width: fallbackWidth, height: 24)
            }

            let proposedWidth = proposal.width ?? nsView.bounds.width
            let targetWidth = max(proposedWidth, 100)

            // Update container size for layout calculation
            if abs(container.containerSize.width - targetWidth) > 0.5 {
                container.containerSize = NSSize(width: targetWidth, height: unlimitedDimension)
            }

            // Ensure layout is up to date
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)

            let lineHeight =
                nsView.font?.boundingRectForFont.size.height
                ?? nsView.defaultParagraphStyle?.minimumLineHeight
                ?? 24
            let minHeight = lineHeight + nsView.textContainerInset.height * 2
            let contentHeight = used.height + nsView.textContainerInset.height * 2
            let height = max(contentHeight, minHeight)
            return CGSize(width: targetWidth, height: height)
        }

        func makeCoordinator() -> Coordinator {
            return Coordinator(text: $text, colorScheme: colorScheme)
        }

        private func resolvedColorScheme(for view: NSView?) -> ColorScheme? {
            if let appearance = view?.window?.effectiveAppearance ?? view?.effectiveAppearance,
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            {
                return match == .darkAqua ? .dark : .light
            }
            let appAppearance = NSApplication.shared.effectiveAppearance
            if let match = appAppearance.bestMatch(from: [.darkAqua, .aqua]) {
                return match == .darkAqua ? .dark : .light
            }
            return nil
        }

        private func appearance(for scheme: ColorScheme) -> NSAppearance? {
            switch scheme {
            case .dark:
                return NSAppearance(named: .darkAqua)
            case .light:
                return NSAppearance(named: .aqua)
            @unknown default:
                return nil
            }
        }

        private func resolvedTextColor(for scheme: ColorScheme, appearance: NSAppearance?)
            -> NSColor
        {
            // Use the actual PrimaryTextColor values from the asset catalog
            if scheme == .dark {
                return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)  // White for dark mode
            } else {
                return NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)  // Dark gray for light mode
            }
        }

        @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
            private weak var textView: NSTextView?
            private var observers: [NSObjectProtocol] = []
            private var lastSerialized = ""
            private let formatter = TextFormattingManager()
            private var isUpdating = false
            private var textBinding: Binding<String>
#if os(macOS)
            private struct HiddenAttachmentState {
                let attachment: NSTextAttachment
                weak var textView: NSTextView?
                let originalImage: NSImage?
                let originalCell: (any NSTextAttachmentCellProtocol)?
                let characterIndex: Int
            }

            private struct FileAttachmentMetadata {
                let storedFilename: String
                let originalFilename: String
                let typeIdentifier: String
                let displayLabel: String
            }

            private enum AttachmentPreviewTarget {
                case image(filename: String)
                case file(metadata: FileAttachmentMetadata)
            }

            private weak var previewHostView: NSView?
            private var imagePreviewView: ImagePreviewView?
            private var currentPreviewIdentifier: String?
            // Cache the attachment rect to prevent jitter during horizontal cursor movement
            private var cachedAttachmentRect: CGRect?
            private var hoverTagOverlayView: NSImageView?
            private var originalTextViewFilters: [Any]?
            private var isHoverEffectApplied = false
            private var hiddenAttachmentState: HiddenAttachmentState?
            // Allow slight tolerance so hover stays active when the cursor is near the tag edges
            private let hoverHitTolerance: CGFloat = 4
            private static let previewImageCache: NSCache<NSString, NSImage> = {
                let cache = NSCache<NSString, NSImage>()
                cache.countLimit = 32
                return cache
            }()
#endif

            // NSTextViewDelegate method to handle selection changes
            func textViewDidChangeSelection(_ notification: Notification) {
                // Ensure layout stability when selection changes to prevent attachment shifting
                if let textView = self.textView, let textContainer = textView.textContainer {
                    textView.layoutManager?.ensureLayout(for: textContainer)
                }
                
                // Post notification about selection change for floating toolbar
                guard let textView = self.textView else { return }
                let selectedRange = textView.selectedRange()
                
                // Only show floating toolbar if there's actual text selected (not just cursor)
                if selectedRange.length > 0 {
                    // Calculate selection rectangle in text view's local coordinate space (same as CommandMenu)
                    if let layoutManager = textView.layoutManager,
                       let textContainer = textView.textContainer {
                        
                        // Get the glyph range for the selection
                        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
                        
                        // Get the bounding rect for the selection in the text container
                        let selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                        
                        // Get visible rect to understand scroll position
                        let visibleRect = textView.visibleRect
                        
                        // Convert selection rect to visible coordinates
                        // selectionRect is in text container space, we need to adjust for scroll
                        let selectionX = selectionRect.origin.x + textView.textContainerOrigin.x
                        let selectionYInContainer = selectionRect.origin.y + textView.textContainerOrigin.y
                        
                        // Adjust Y position relative to visible rect (accounts for scroll)
                        let selectionY = selectionYInContainer - visibleRect.origin.y
                        let selectionWidth = selectionRect.width
                        let selectionHeight = selectionRect.height

                        // DEBUG LOGGING
                        print("📍 [macOS] Selection Debug:")
                        print("  - selectionRect: \(selectionRect)")
                        print("  - textContainerOrigin: \(textView.textContainerOrigin)")
                        print("  - visibleRect: \(visibleRect)")
                        print("  - selectionYInContainer: \(selectionYInContainer)")
                        print("  - selectionY (relative to visible): \(selectionY)")
                        print("  - selectionHeight: \(selectionHeight)")

                        // Convert to window coordinates for proper positioning
                        let selectionRectInWindow = textView.convert(selectionRect, to: nil)
                        print("  - selectionRectInWindow: \(selectionRectInWindow)")

                        // Post notification with selection info - let the view calculate toolbar position
                        let info: [String: Any] = [
                            "hasSelection": true,
                            "selectionX": selectionX,
                            "selectionY": selectionY,
                            "selectionWidth": selectionWidth,
                            "selectionHeight": selectionHeight,
                            "selectionWindowY": selectionRectInWindow.origin.y,
                            "selectionWindowX": selectionRectInWindow.origin.x,
                            "visibleWidth": visibleRect.width,
                            "visibleHeight": visibleRect.height
                        ]
                        NotificationCenter.default.post(
                            name: .textSelectionChanged,
                            object: nil,
                            userInfo: info
                        )
                    }
                } else {
                    // No selection - hide floating toolbar
                    let info: [String: Any] = ["hasSelection": false]
                    NotificationCenter.default.post(
                        name: .textSelectionChanged,
                        object: nil,
                        userInfo: info
                    )
                }
            }
            private var textBeforeWritingTools = ""
            private var currentColorScheme: ColorScheme

            // Use Charter for body text as per design requirements
            private static let textFont = FontManager.bodyNS(size: 16, weight: .regular)
            private static let baseLineHeight: CGFloat = 24
            private static let todoLineHeight: CGFloat = 24
            private static let checkboxIconSize: CGFloat = 24  // 24x24 pixels for better visibility
            private static let baseBaselineOffset: CGFloat = 0.0
            private static let todoBaselineOffset: CGFloat = {
                // Don't offset the text baseline
                return 0.0
            }()
            private static let checkboxAttachmentYOffset: CGFloat = {
                // With cellBaselineOffset override, we use 0 for bounds.origin.y
                // The cell's baseline offset method handles all positioning
                return 0.0
            }()
            private static let checkboxBaselineOffset: CGFloat = {
                // No additional baseline adjustment needed
                return 0.0
            }()
            private static let webClipMarkupPrefix = "[[webclip|"
            private static let webClipPattern = #"\[\[webclip\|([^|]*)\|([^|]*)\|([^\]]*)\]\]"#
            private static let webClipRegex: NSRegularExpression? = try? NSRegularExpression(
                pattern: webClipPattern,
                options: []
            )
            private static func cleanedWebClipComponent(_ value: Any?) -> String {
                guard let raw = value as? String else { return "" }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                return
                    trimmed
                    .replacingOccurrences(of: "|", with: " ")
                    .replacingOccurrences(of: "]]", with: " ]")
            }

            private static func sanitizedWebClipComponent(_ value: String) -> String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                return
                    trimmed
                    .replacingOccurrences(of: "|", with: " ")
                    .replacingOccurrences(of: "]]", with: " ")
            }

            private static func normalizedURL(from raw: String) -> String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                    return trimmed
                }
                return "https://\(trimmed)"
            }

            private static func resolvedDomain(from urlString: String) -> String {
                let normalized = normalizedURL(from: urlString)
                if let host = URL(string: normalized)?.host, !host.isEmpty {
                    return host
                }
                return
                    normalized
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
            }

            private static func string(
                from match: NSTextCheckingResult, at index: Int, in text: String
            ) -> String {
                guard index < match.numberOfRanges else { return "" }
                let range = match.range(at: index)
                guard let swiftRange = Range(range, in: text) else { return "" }
                return String(text[swiftRange])
            }

            private func makeWebClipAttachment(
                url rawURL: String,
                title: String?,
                description: String?,
                domain: String?
            ) -> NSMutableAttributedString {
                let normalizedURL = Self.normalizedURL(from: rawURL)
                let linkValue = normalizedURL.isEmpty ? rawURL : normalizedURL
                let resolvedDomain =
                    (domain?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? domain!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : Self.resolvedDomain(from: linkValue))

                let fallbackTitle =
                    (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    ? resolvedDomain
                    : title!.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackExcerpt =
                    (description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    ? "Open link to view the full preview."
                    : description!.trimmingCharacters(in: .whitespacesAndNewlines)

                #if os(macOS)
                    // Create the view without artificial width constraints - let it size to content
                    let cardView = WebClipView(
                        title: fallbackTitle,
                        domain: resolvedDomain,
                        url: linkValue
                    )
                    .fixedSize()  // Size to fit content naturally
                    .environment(\.colorScheme, currentColorScheme)

                    let renderer = ImageRenderer(content: cardView)
                    // Use display's native backing scale for pixel-perfect rendering
                    let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
                    renderer.scale = displayScale
                    renderer.isOpaque = false

                    let attachment = NSTextAttachment()

                    guard let cgImage = renderer.cgImage else {
                        let attributed = NSMutableAttributedString(
                            string: "[WebClip: \(fallbackTitle)]")
                        return attributed
                    }

                    // Create NSImage from CGImage with proper pixel dimensions
                    let pixelWidth = CGFloat(cgImage.width)
                    let pixelHeight = CGFloat(cgImage.height)

                    // Calculate display size (points) from pixel size
                    let displaySize = CGSize(
                        width: pixelWidth / displayScale,
                        height: pixelHeight / displayScale)

                    // Create NSImage with correct size to prevent blurriness
                    let nsImage = NSImage(size: displaySize)
                    nsImage.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

                    attachment.image = nsImage

                    attachment.bounds = CGRect(
                        x: 0,
                        y: Self.imageTagVerticalOffset(for: displaySize.height),
                        width: displaySize.width,
                        height: displaySize.height
                    )
                    let attributed = NSMutableAttributedString(attachment: attachment)
                #else
                    // Create the view without artificial width constraints - let it size to content
                    let cardView = WebClipView(
                        title: fallbackTitle,
                        domain: resolvedDomain,
                        url: linkValue
                    )
                    .fixedSize()  // Size to fit content naturally
                    .environment(\.colorScheme, currentColorScheme)

                    let renderer = ImageRenderer(content: cardView)
                    // Use device scale for sharp rendering (2x or 3x depending on device)
                    let displayScale = UIScreen.main.scale
                    renderer.scale = displayScale
                    renderer.isOpaque = false

                    let attachment = NSTextAttachment()

                    guard let uiImage = renderer.uiImage else {
                        let attributed = NSMutableAttributedString(
                            string: "[WebClip: \(fallbackTitle)]")
                        return attributed
                    }

                    // CRITICAL: UIImage already handles scale internally via its scale property
                    // We just need to ensure the attachment bounds match the visual size
                    let displaySize = uiImage.size

                    attachment.image = uiImage

                    attachment.bounds = CGRect(
                        x: 0,
                        y: Self.imageTagVerticalOffset(for: displaySize.height),
                        width: displaySize.width,
                        height: displaySize.height
                    )
                    let attributed = NSMutableAttributedString(attachment: attachment)
                #endif

                let attachmentRange = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(.link, value: linkValue, range: attachmentRange)
                attributed.addAttribute(.underlineStyle, value: 0, range: attachmentRange)
                attributed.addAttribute(.webClipTitle, value: fallbackTitle, range: attachmentRange)
                attributed.addAttribute(
                    .webClipDescription, value: fallbackExcerpt, range: attachmentRange)
                attributed.addAttribute(
                    .webClipDomain, value: resolvedDomain, range: attachmentRange)

                // Apply special paragraph style for web clips to prevent overlap
                attributed.addAttribute(
                    .paragraphStyle, value: Self.webClipParagraphStyle(), range: attachmentRange)

                return attributed
            }
            
            /// Create an inline image attachment tag from a filename
            private func makeImageAttachment(filename: String) -> NSMutableAttributedString {
                NSLog("🖼️ makeImageAttachment: START with filename: %@", filename)

                func fallbackAttributedString() -> NSMutableAttributedString {
                    NSLog("🖼️ makeImageAttachment: Falling back to text placeholder for %@", filename)
                    return NSMutableAttributedString(string: "[Image: \(filename)]")
                }

                if ImageStorageManager.shared.getImageURL(for: filename) == nil {
                    NSLog("🖼️ makeImageAttachment: WARNING - no stored file found for %@", filename)
                }

                let attachment: NoteImageAttachment
                let displaySize: CGSize

#if os(macOS)
                let tagView = ImageAttachmentTagView()
                    .environment(\.colorScheme, currentColorScheme)
                let renderer = ImageRenderer(content: tagView)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                renderer.scale = scale
                renderer.isOpaque = false

                guard let cgImage = renderer.cgImage else {
                    NSLog("🖼️ makeImageAttachment: FAILED to render tag CGImage")
                    return fallbackAttributedString()
                }

                displaySize = CGSize(
                    width: CGFloat(cgImage.width) / scale,
                    height: CGFloat(cgImage.height) / scale
                )

                let renderedImage = NSImage(size: displaySize)
                renderedImage.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

                attachment = NoteImageAttachment(filename: filename)
                attachment.image = renderedImage
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: renderedImage)

#else
                let tagView = ImageAttachmentTagView()
                    .environment(\.colorScheme, currentColorScheme)
                let renderer = ImageRenderer(content: tagView)
                let scale = UIScreen.main.scale
                renderer.scale = scale
                renderer.isOpaque = false

                guard let uiImage = renderer.uiImage else {
                    NSLog("🖼️ makeImageAttachment: FAILED to render tag UIImage")
                    return fallbackAttributedString()
                }

                displaySize = uiImage.size
                attachment = NoteImageAttachment(filename: filename)
                attachment.image = uiImage

#endif

                attachment.bounds = CGRect(
                    x: 0,
                    y: Self.imageTagVerticalOffset(for: displaySize.height),
                    width: displaySize.width,
                    height: displaySize.height
                )

                let attributed = NSMutableAttributedString(attachment: attachment)
                let attachmentRange = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(.imageFilename, value: filename, range: attachmentRange)

                let sizeDescription: String
#if os(macOS)
                sizeDescription = NSStringFromSize(
                    NSSize(width: displaySize.width, height: displaySize.height))
#else
                sizeDescription = NSStringFromCGSize(displaySize)
#endif

                NSLog(
                    "🖼️ makeImageAttachment: Created inline tag for %@ with size %@",
                    filename,
                    sizeDescription
                )

                return attributed
            }

            /// Create an inline file attachment tag with metadata
            private func makeFileAttachment(metadata: FileAttachmentMetadata)
                -> NSMutableAttributedString
            {
                func fallbackAttributedString() -> NSMutableAttributedString {
                    return NSMutableAttributedString(
                        string: "[File: \(metadata.displayLabel)]"
                    )
                }

                let tagView = FileAttachmentTagView(label: metadata.displayLabel)
                    .environment(\.colorScheme, currentColorScheme)
                let renderer = ImageRenderer(content: tagView)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                renderer.scale = scale
                renderer.isOpaque = false

                guard let cgImage = renderer.cgImage else {
                    NSLog("📄 makeFileAttachment: FAILED to render tag image")
                    return fallbackAttributedString()
                }

                let displaySize = CGSize(
                    width: CGFloat(cgImage.width) / scale,
                    height: CGFloat(cgImage.height) / scale
                )

                let renderedImage = NSImage(size: displaySize)
                renderedImage.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

                let attachment = NoteFileAttachment(
                    storedFilename: metadata.storedFilename,
                    originalFilename: metadata.originalFilename,
                    typeIdentifier: metadata.typeIdentifier,
                    displayLabel: metadata.displayLabel
                )
                attachment.image = renderedImage
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: renderedImage)
                attachment.bounds = CGRect(
                    x: 0,
                    y: Self.imageTagVerticalOffset(for: displaySize.height),
                    width: displaySize.width,
                    height: displaySize.height
                )

                let attributed = NSMutableAttributedString(attachment: attachment)
                let attachmentRange = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(
                    .fileStoredFilename,
                    value: metadata.storedFilename,
                    range: attachmentRange
                )
                attributed.addAttribute(
                    .fileOriginalFilename,
                    value: metadata.originalFilename,
                    range: attachmentRange
                )
                attributed.addAttribute(
                    .fileTypeIdentifier,
                    value: metadata.typeIdentifier,
                    range: attachmentRange
                )
                attributed.addAttribute(
                    .fileDisplayLabel,
                    value: metadata.displayLabel,
                    range: attachmentRange
                )

                return attributed
            }

#if os(macOS)
            private func ensurePreviewInfrastructure(for textView: NSTextView) {
                if previewHostView == nil {
                    previewHostView = textView.enclosingScrollView?.contentView
                }

                guard let host = previewHostView else { return }

                if imagePreviewView == nil {
                    let preview = ImagePreviewView(frame: .zero)
                    preview.isHidden = true
                    preview.colorScheme = currentColorScheme
                    host.addSubview(preview)
                    imagePreviewView = preview
                }
            }

            private func previewDisplaySize(for image: NSImage) -> CGSize {
                let maxDimension: CGFloat = 62
                let imageSize = image.size
                guard imageSize.width > 0, imageSize.height > 0 else {
                    return CGSize(width: maxDimension, height: maxDimension)
                }

                if imageSize.width >= imageSize.height {
                    let height = maxDimension
                    let width = maxDimension * (imageSize.width / imageSize.height)
                    return CGSize(width: width, height: height)
                } else {
                    let width = maxDimension
                    let height = maxDimension * (imageSize.height / imageSize.width)
                    return CGSize(width: width, height: height)
                }
            }

            private func showImagePreview(
                for filename: String,
                attachment: NSTextAttachment,
                characterIndex: Int,
                at rectInView: CGRect,
                in textView: NSTextView
            ) {
                showAttachmentPreview(
                    identifier: filename,
                    attachment: attachment,
                    characterIndex: characterIndex,
                    at: rectInView,
                    in: textView
                ) {
                    guard let imageURL = ImageStorageManager.shared.getImageURL(for: filename) else {
                        return nil
                    }
                    return NSImage(contentsOf: imageURL)
                }
            }

            private func showFilePreview(
                metadata: FileAttachmentMetadata,
                attachment: NSTextAttachment,
                characterIndex: Int,
                at rectInView: CGRect,
                in textView: NSTextView
            ) {
                showAttachmentPreview(
                    identifier: metadata.storedFilename,
                    attachment: attachment,
                    characterIndex: characterIndex,
                    at: rectInView,
                    in: textView
                ) {
                    guard let fileURL = FileAttachmentStorageManager.shared.fileURL(
                        for: metadata.storedFilename
                    ) else {
                        return nil
                    }
                    return generateFilePreviewImage(for: fileURL, displayLabel: metadata.displayLabel)
                }
            }

            private func showAttachmentPreview(
                identifier: String,
                attachment: NSTextAttachment,
                characterIndex: Int,
                at rectInView: CGRect,
                in textView: NSTextView,
                imageProvider: () -> NSImage?
            ) {
                ensurePreviewInfrastructure(for: textView)

                guard let preview = imagePreviewView else { return }

                preview.colorScheme = currentColorScheme

                let cacheKey = identifier as NSString
                var resolvedImage = Self.previewImageCache.object(forKey: cacheKey)
                if resolvedImage == nil {
                    resolvedImage = imageProvider()
                    if let resolvedImage {
                        Self.previewImageCache.setObject(resolvedImage, forKey: cacheKey)
                    }
                }

                guard let image = resolvedImage else {
                    hideImagePreview()
                    return
                }

                let isNewAttachment = currentPreviewIdentifier != identifier

                if isNewAttachment {
                    let displaySize = previewDisplaySize(for: image)
                    preview.configure(image: image, displaySize: displaySize)
                    currentPreviewIdentifier = identifier
                    cachedAttachmentRect = rectInView
                } else if cachedAttachmentRect == nil {
                    cachedAttachmentRect = rectInView
                }

                if let cached = cachedAttachmentRect {
                    let deltaX = abs(cached.midX - rectInView.midX)
                    let deltaY = abs(cached.midY - rectInView.midY)
                    if deltaX > 0.75 || deltaY > 0.75 {
                        cachedAttachmentRect = rectInView
                    }
                }

                let positioningRect = cachedAttachmentRect ?? rectInView

                let previewSize = preview.frame.size
                let verticalSpacing: CGFloat = 8
                let minPadding: CGFloat = 12

                func clampedFrame(
                    anchorRect: CGRect,
                    containerBounds: CGRect,
                    containerIsFlipped: Bool
                ) -> CGRect {
                    var frame = CGRect(origin: .zero, size: previewSize)
                    let minX = containerBounds.minX + minPadding
                    let maxX = containerBounds.maxX - frame.width - minPadding
                    let desiredCenterX = anchorRect.midX
                    frame.origin.x = desiredCenterX - frame.width / 2
                    frame.origin.x = min(maxX, max(minX, frame.origin.x))

                    let boundsMinY = containerBounds.minY + minPadding
                    let boundsMaxY = containerBounds.maxY - minPadding

                    if containerIsFlipped {
                        let aboveOrigin = anchorRect.minY - verticalSpacing - frame.height
                        let aboveFits = aboveOrigin >= boundsMinY
                        let belowOrigin = anchorRect.maxY + verticalSpacing
                        let belowFits = belowOrigin + frame.height <= boundsMaxY

                        if aboveFits {
                            frame.origin.y = min(aboveOrigin, boundsMaxY - frame.height)
                        } else if belowFits {
                            frame.origin.y = max(belowOrigin, boundsMinY)
                        } else {
                            let clamped = max(boundsMinY, min(aboveOrigin, boundsMaxY - frame.height))
                            frame.origin.y = clamped
                        }
                    } else {
                        let aboveOrigin = anchorRect.maxY + verticalSpacing
                        let aboveFits = aboveOrigin + frame.height <= boundsMaxY
                        let belowOrigin = anchorRect.minY - verticalSpacing - frame.height
                        let belowFits = belowOrigin >= boundsMinY

                        if aboveFits {
                            frame.origin.y = aboveOrigin
                        } else if belowFits {
                            frame.origin.y = belowOrigin
                        } else {
                            let clamped = max(boundsMinY, min(aboveOrigin, boundsMaxY - frame.height))
                            frame.origin.y = clamped
                        }
                    }

                    frame.origin.x = round(frame.origin.x)
                    frame.origin.y = round(frame.origin.y)
                    return frame
                }

                applyHoverEffectIfNeeded(to: textView)

                let overlayImage = attachmentImage(
                    attachment,
                    in: textView,
                    characterIndex: characterIndex
                )

                hideUnderlyingAttachment(attachment, characterIndex: characterIndex, in: textView)

                if let host = previewHostView ?? textView.superview {
                    var anchorInHost = textView.convert(positioningRect, to: host)
                    anchorInHost.origin.x = round(anchorInHost.origin.x)
                    anchorInHost.origin.y = round(anchorInHost.origin.y)

                    if let image = overlayImage {
                        let overlay = ensureHoverTagOverlay(in: host, relativeTo: textView)
                        overlay.image = image
                        overlay.frame = anchorInHost.integral
                        overlay.layer?.cornerRadius = overlay.frame.height / 2
                        overlay.layer?.cornerCurve = .continuous
                        overlay.layer?.masksToBounds = true
                    } else {
                        clearHoverTagOverlay()
                    }

                    let referenceView = hoverTagOverlayView ?? textView

                    if preview.superview !== host {
                        host.addSubview(preview, positioned: .above, relativeTo: referenceView)
                    } else {
                        host.addSubview(preview, positioned: .above, relativeTo: referenceView)
                    }

                    let framed = clampedFrame(
                        anchorRect: anchorInHost,
                        containerBounds: host.bounds,
                        containerIsFlipped: host.isFlipped
                    )
                    preview.frame = framed
                } else {
                    clearHoverTagOverlay()

                    var anchorInTextView = positioningRect
                    anchorInTextView.origin.x = round(anchorInTextView.origin.x)
                    anchorInTextView.origin.y = round(anchorInTextView.origin.y)

                    let framed = clampedFrame(
                        anchorRect: anchorInTextView,
                        containerBounds: textView.bounds,
                        containerIsFlipped: textView.isFlipped
                    )
                    preview.frame = framed
                }

                if isNewAttachment || preview.isHidden {
                    preview.animateEntrance()
                }

                preview.isHidden = false
            }

            private func generateFilePreviewImage(for url: URL, displayLabel: String) -> NSImage? {
                let maxDimension: CGFloat = 62
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let targetSize = CGSize(width: maxDimension * scale, height: maxDimension * scale)

                if let cgImage = QLThumbnailImageCreate(
                    kCFAllocatorDefault,
                    url as CFURL,
                    targetSize,
                    nil
                )?.takeRetainedValue() {
                    let displaySize = CGSize(
                        width: CGFloat(cgImage.width) / scale,
                        height: CGFloat(cgImage.height) / scale
                    )
                    let image = NSImage(size: NSSize(width: displaySize.width, height: displaySize.height))
                    image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
                    return image
                }

                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: maxDimension, height: maxDimension)
                return icon
            }

            private func hideImagePreview() {
                currentPreviewIdentifier = nil
                // Clear cached rect when hiding preview to start fresh on next hover
                cachedAttachmentRect = nil
                imagePreviewView?.layer?.removeAllAnimations()
                imagePreviewView?.isHidden = true
                clearHoverTagOverlay()
                if let textView {
                    removeHoverEffect(from: textView)
                }
                restoreHiddenAttachment()
            }

            private func ensureHoverTagOverlay(in container: NSView, relativeTo referenceView: NSView) -> NSImageView {
                if let existing = hoverTagOverlayView, existing.superview === container {
                    container.addSubview(existing, positioned: .above, relativeTo: referenceView)
                    return existing
                }

                hoverTagOverlayView?.removeFromSuperview()

                let overlay = NSImageView(frame: .zero)
                overlay.imageScaling = .scaleProportionallyUpOrDown
                overlay.wantsLayer = true
                overlay.layer?.masksToBounds = true
                overlay.layer?.cornerCurve = .continuous
                container.addSubview(overlay, positioned: .above, relativeTo: referenceView)
                hoverTagOverlayView = overlay
                return overlay
            }

            private func clearHoverTagOverlay() {
                hoverTagOverlayView?.removeFromSuperview()
                hoverTagOverlayView = nil
            }

            private func applyHoverEffectIfNeeded(to textView: NSTextView) {
                guard !isHoverEffectApplied else { return }

                textView.wantsLayer = true
                textView.layerUsesCoreImageFilters = true
                originalTextViewFilters = textView.layer?.filters

                if let blur = CIFilter(name: "CIGaussianBlur") {
                    blur.setDefaults()
                    blur.setValue(2.0, forKey: kCIInputRadiusKey as String)
                    textView.layer?.filters = [blur]
                } else {
                    textView.layer?.filters = nil
                }

                textView.alphaValue = 0.5
                isHoverEffectApplied = true
            }

            private func removeHoverEffect(from textView: NSTextView) {
                guard isHoverEffectApplied else { return }
                textView.alphaValue = 1.0
                textView.layer?.filters = originalTextViewFilters
                textView.layerUsesCoreImageFilters = false
                originalTextViewFilters = nil
                isHoverEffectApplied = false
            }

            private func attachmentImage(
                _ attachment: NSTextAttachment,
                in textView: NSTextView,
                characterIndex: Int
            ) -> NSImage? {
                if let cell = attachment.attachmentCell as? NSTextAttachmentCell {
                    return cell.image
                }
                return attachment.image(
                    forBounds: attachment.bounds,
                    textContainer: textView.textContainer,
                    characterIndex: characterIndex
                )
            }

            private func hideUnderlyingAttachment(
                _ attachment: NSTextAttachment,
                characterIndex: Int,
                in textView: NSTextView
            ) {
                restoreHiddenAttachment(except: attachment)

                guard hiddenAttachmentState?.attachment !== attachment else { return }

                let originalImage = attachment.image
                let originalCell = attachment.attachmentCell

                guard attachment.bounds.width > 0, attachment.bounds.height > 0 else { return }

                if let transparent = makeTransparentImage(of: attachment.bounds.size) {
                    attachment.image = transparent
                    attachment.attachmentCell = NSTextAttachmentCell(imageCell: transparent)
                } else {
                    attachment.image = nil
                    attachment.attachmentCell = nil
                }

                textView.layoutManager?.invalidateDisplay(
                    forCharacterRange: NSRange(location: characterIndex, length: 1))

                hiddenAttachmentState = HiddenAttachmentState(
                    attachment: attachment,
                    textView: textView,
                    originalImage: originalImage,
                    originalCell: originalCell,
                    characterIndex: characterIndex
                )
            }

            private func restoreHiddenAttachment(except attachmentToKeepHidden: NSTextAttachment? = nil) {
                guard let state = hiddenAttachmentState else { return }
                if let keepHidden = attachmentToKeepHidden, state.attachment === keepHidden {
                    return
                }

                let attachment = state.attachment

                attachment.image = state.originalImage
                if let originalCell = state.originalCell {
                    attachment.attachmentCell = originalCell
                } else {
                    attachment.attachmentCell = nil
                }

                state.textView?.layoutManager?.invalidateDisplay(
                    forCharacterRange: NSRange(location: state.characterIndex, length: 1))

                hiddenAttachmentState = nil
            }

            private func makeTransparentImage(of size: CGSize) -> NSImage? {
                guard size.width > 0, size.height > 0 else { return nil }
                let image = NSImage(size: size)
                image.lockFocus()
                NSColor.clear.setFill()
                NSRect(origin: .zero, size: size).fill()
                image.unlockFocus()
                return image
            }

            func endAttachmentHover() {
                hideImagePreview()
            }

            func handleAttachmentHover(at point: CGPoint, in textView: NSTextView) -> Bool {
                // Fast path: if we're already showing a preview and the cursor is still within
                // the cached rect (with tolerance), keep the preview stable without recalculating
                if currentPreviewIdentifier != nil,
                    let cachedRect = cachedAttachmentRect
                {
                    let toleranceRect = cachedRect.insetBy(dx: -hoverHitTolerance, dy: -hoverHitTolerance)
                    if toleranceRect.contains(point) {
                        // Still hovering over the same attachment - preview is already shown, no need to update
                        return true
                    }
                }

                guard let layoutManager = textView.layoutManager,
                    let textStorage = textView.textStorage,
                    let textContainer = textView.textContainer
                else {
                    hideImagePreview()
                    return false
                }

                let containerPoint = CGPoint(
                    x: point.x - textView.textContainerOrigin.x,
                    y: point.y - textView.textContainerOrigin.y)

                let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
                if glyphIndex >= layoutManager.numberOfGlyphs {
                    hideImagePreview()
                    return false
                }

                let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                guard characterIndex < textStorage.length else {
                    hideImagePreview()
                    return false
                }

                let attributes = textStorage.attributes(at: characterIndex, effectiveRange: nil)
                guard let attachment = attributes[.attachment] as? NSTextAttachment else {
                    hideImagePreview()
                    return false
                }

                let previewTarget: AttachmentPreviewTarget
                if let filename = attributes[.imageFilename] as? String {
                    previewTarget = .image(filename: filename)
                } else if let storedFilename = attributes[.fileStoredFilename] as? String,
                          let originalFilename = attributes[.fileOriginalFilename] as? String,
                          let typeIdentifier = attributes[.fileTypeIdentifier] as? String
                {
                    let displayLabel = (attributes[.fileDisplayLabel] as? String) ?? "File"
                    let metadata = FileAttachmentMetadata(
                        storedFilename: storedFilename,
                        originalFilename: originalFilename,
                        typeIdentifier: typeIdentifier,
                        displayLabel: displayLabel
                    )
                    previewTarget = .file(metadata: metadata)
                } else {
                    hideImagePreview()
                    return false
                }

                let characterRange = NSRange(location: characterIndex, length: 1)
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: characterRange,
                    actualCharacterRange: nil)

                guard glyphRange.length > 0 else {
                    hideImagePreview()
                    return false
                }

                // Get the bounding rect for the glyph - this is where it's visually rendered
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: glyphRange,
                    in: textContainer)
                
                // For attachments, glyphRect.origin.y is at the BASELINE
                // The attachment's visual TOP is at baseline + attachment.bounds.origin.y
                // (origin.y is negative for images taller than the line height)
                let visualTop = glyphRect.origin.y + attachment.bounds.origin.y
                
                // Build the visual rect for the attachment
                let drawingRect = CGRect(
                    x: glyphRect.origin.x,
                    y: visualTop,
                    width: attachment.bounds.size.width,
                    height: attachment.bounds.size.height
                )

                let rectInTextView = drawingRect.offsetBy(
                    dx: textView.textContainerOrigin.x,
                    dy: textView.textContainerOrigin.y)
                
                // Debug logging
                NSLog("🔍 glyphRect: \(glyphRect)")
                NSLog("🔍 attachment.bounds: \(attachment.bounds)")
                NSLog("🔍 visualTop (baseline + offset): \(visualTop)")
                NSLog("🔍 drawingRect (final attachment rect): \(drawingRect)")
                NSLog("🔍 rectInTextView (after container origin): \(rectInTextView)")

                let detectionRect = rectInTextView.insetBy(
                    dx: -hoverHitTolerance,
                    dy: -hoverHitTolerance)

                guard detectionRect.contains(point) else {
                    hideImagePreview()
                    return false
                }

                switch previewTarget {
                case let .image(filename):
                    showImagePreview(
                        for: filename,
                        attachment: attachment,
                        characterIndex: characterIndex,
                        at: rectInTextView,
                        in: textView
                    )
                case let .file(metadata):
                    showFilePreview(
                        metadata: metadata,
                        attachment: attachment,
                        characterIndex: characterIndex,
                        at: rectInTextView,
                        in: textView
                    )
                }
                return true
            }
#endif

            init(text: Binding<String>, colorScheme: ColorScheme) {
                self.textBinding = text
                self.currentColorScheme = colorScheme
            }

            deinit {
                observers.forEach { NotificationCenter.default.removeObserver($0) }
                observers.removeAll()
            }

            func configure(with textView: NSTextView) {
                self.textView = textView
#if os(macOS)
                let newHost = textView.enclosingScrollView?.contentView
                if previewHostView !== newHost {
                    imagePreviewView?.removeFromSuperview()
                    imagePreviewView = nil
                    clearHoverTagOverlay()
                    removeHoverEffect(from: textView)
                    restoreHiddenAttachment()
                    previewHostView = newHost
                }
                ensurePreviewInfrastructure(for: textView)
                if let clipView = newHost {
                    clipView.postsBoundsChangedNotifications = true
                    let observer = NotificationCenter.default.addObserver(
                        forName: NSView.boundsDidChangeNotification,
                        object: clipView,
                        queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.hideImagePreview()
                        }
                    }
                    observers.append(observer)
                }
#endif

                // Prevent layout shifts when gaining focus
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification, object: textView.window,
                    queue: .main
                ) { [weak self] _ in
                    // Ensure layout is stable when window becomes key
                    Task { @MainActor [weak self] in
                        if let textView = self?.textView, let textContainer = textView.textContainer {
                            textView.layoutManager?.ensureLayout(for: textContainer)
                        }
                    }
                }

                let insertTodo = NotificationCenter.default.addObserver(
                    forName: .insertTodoInEditor, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.insertTodo()
                    }
                }

                let insertLink = NotificationCenter.default.addObserver(
                    forName: .insertWebClipInEditor, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let url = notification.object as? String else { return }
                    Task { @MainActor [weak self] in
                        self?.insertWebClip(url: url)
                    }
                }

                let insertVoiceTranscript = NotificationCenter.default.addObserver(
                    forName: .insertVoiceTranscriptInEditor, object: nil, queue: .main
                ) { [weak self] notification in
                    NSLog("📝 Coordinator: Received insertVoiceTranscriptInEditor notification")
                    // We're on main queue (specified in observer), use assumeIsolated for synchronous execution
                    // This prevents race condition with view dismissal that occurred with Task wrapper
                    MainActor.assumeIsolated {
                        guard let self = self else {
                            NSLog("⚠️ Coordinator deallocated before transcript insertion")
                            return
                        }
                        guard let transcript = notification.object as? String else {
                            NSLog("📝 Coordinator: No transcript in notification object")
                            return
                        }
                        NSLog("📝 Coordinator: Got transcript: %@", transcript)
                        self.insertVoiceTranscript(transcript: transcript)
                        NSLog("📝 Coordinator: Transcript insertion completed")
                    }
                }
                
                let insertImage = NotificationCenter.default.addObserver(
                    forName: .insertImageInEditor, object: nil, queue: .main
                ) { [weak self] notification in
                    NSLog("📝 Coordinator: Received insertImageInEditor notification")
                    guard let filename = notification.object as? String else {
                        NSLog("📝 Coordinator: No filename in notification object")
                        return
                    }
                    NSLog("📝 Coordinator: Got image filename: %@", filename)
                    Task { @MainActor [weak self] in
                        guard let self = self else {
                            NSLog("⚠️ Coordinator deallocated before image insertion")
                            return
                        }
                        self.insertImage(filename: filename)
                    }
                }

                let applyTool = NotificationCenter.default.addObserver(
                    forName: .applyEditTool, object: nil, queue: .main
                ) { [weak self] notification in
                    print("📝 DEBUG: Received applyEditTool notification")
                    print("📝 DEBUG: UserInfo: \(String(describing: notification.userInfo))")
                    guard let raw = notification.userInfo?["tool"] as? String else {
                        print("📝 DEBUG: Failed to get tool string from userInfo")
                        return
                    }
                    print("📝 DEBUG: Tool string: \(raw)")
                    guard let tool = EditTool(rawValue: raw) else {
                        print("📝 DEBUG: Failed to convert '\(raw)' to EditTool")
                        return
                    }
                    print("📝 DEBUG: Successfully converted to tool: \(tool)")
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        guard let textView = self.textView else {
                            print("📝 DEBUG: textView is nil")
                            return
                        }
                        print("📝 DEBUG: Applying formatting for tool: \(tool)")
                        self.formatter.applyFormatting(to: textView, tool: tool)
                        self.styleTodoParagraphs()
                        self.syncText()
                        print("📝 DEBUG: Formatting applied successfully")
                    }
                }

                let applyCommandMenuTool = NotificationCenter.default.addObserver(
                    forName: .applyCommandMenuTool, object: nil, queue: .main
                ) { [weak self] notification in
                    // Extract notification data before passing to MainActor context
                    guard let info = notification.object as? [String: Any],
                          let tool = info["tool"] as? EditTool,
                          let slashLocation = info["slashLocation"] as? Int else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        guard let self = self,
                              let textView = self.textView,
                              let textStorage = textView.textStorage else {
                            return
                        }
                        
                        // Remove the "/" character that triggered the menu
                        if slashLocation >= 0 && slashLocation < textStorage.length {
                            let slashRange = NSRange(location: slashLocation, length: 1)
                            if textView.shouldChangeText(in: slashRange, replacementString: "") {
                                textStorage.replaceCharacters(in: slashRange, with: "")
                                textView.didChangeText()
                            }
                        }
                        
                        // Apply the selected tool
                        self.formatter.applyFormatting(to: textView, tool: tool)
                        
                        // Sync the text back
                        self.syncText()
                    }
                }

                observers = [
                    insertTodo, insertLink, insertVoiceTranscript, insertImage, applyTool, applyCommandMenuTool,
                ]
            }

#if os(macOS)
            func canHandleFileDrop(_ info: NSDraggingInfo, in textView: NSTextView) -> Bool {
                guard let urls = fileURLs(from: info) else {
                    return false
                }
                return !urls.isEmpty
            }

            func handleFileDrop(_ info: NSDraggingInfo, in textView: NSTextView) -> Bool {
                guard let urls = fileURLs(from: info), !urls.isEmpty else {
                    return false
                }
                processDroppedURLs(urls)
                return true
            }

            private func fileURLs(from info: NSDraggingInfo) -> [URL]? {
                let classes: [AnyClass] = [NSURL.self]
                let options: [NSPasteboard.ReadingOptionKey: Any] = [
                    .urlReadingFileURLsOnly: true
                ]
                guard let objects = info.draggingPasteboard.readObjects(
                    forClasses: classes,
                    options: options
                ) as? [URL] else {
                    return nil
                }
                return objects
            }

            private func processDroppedURLs(_ urls: [URL]) {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    for url in urls {
                        await self.ingestDroppedURL(url)
                    }
                }
            }

            private func ingestDroppedURL(_ url: URL) async {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                if isImageURL(url) {
                    if let filename = await ImageStorageManager.shared.saveImage(from: url) {
                        insertImage(filename: filename)
                        return
                    } else {
                        NSLog("📄 ingestDroppedURL: Failed to persist image at %@", url.path)
                    }
                }

                if let storedFile = await FileAttachmentStorageManager.shared.saveFile(from: url) {
                    insertFileAttachment(using: storedFile)
                    return
                }

                NSLog("📄 ingestDroppedURL: Unhandled file type for %@", url.path)
            }

            private func isImageURL(_ url: URL) -> Bool {
                if let values = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
                   let identifier = values.typeIdentifier {
                    if #available(macOS 11.0, *) {
                        if let type = UTType(identifier) {
                            return type.conforms(to: .image)
                        }
                    }
                }

                let ext = url.pathExtension.lowercased()
                return ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif"].contains(
                    ext
                )
            }
#endif

            func handleAttachmentClick(at point: CGPoint, in textView: NSTextView) -> Bool {
                guard let layoutManager = textView.layoutManager,
                    let textStorage = textView.textStorage,
                    let textContainer = textView.textContainer
                else { return false }

                // Use text container coordinates directly to avoid textContainerOrigin issues
                let pointInContainer = CGPoint(
                    x: point.x - textView.textContainerOrigin.x,
                    y: point.y - textView.textContainerOrigin.y)

                let glyphIndex = layoutManager.glyphIndex(for: pointInContainer, in: textContainer)
                if glyphIndex >= layoutManager.numberOfGlyphs { return false }

                let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                guard charIndex < textStorage.length else { return false }

                let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
                guard let attachment = attributes[.attachment] as? NSTextAttachment else {
                    return false
                }

                enum AttachmentAction {
                    case webClip(url: URL)
                    case file(url: URL)
                }

                let action: AttachmentAction?
                if let storedFilename = attributes[.fileStoredFilename] as? String,
                   let fileURL = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) {
                    action = .file(url: fileURL)
                } else if attributes[.webClipTitle] != nil,
                          let linkValue = attributes[.link] as? String,
                          let url = URL(string: linkValue) {
                    action = .webClip(url: url)
                } else {
                    action = nil
                }

                guard let action else { return false }

                // Get the actual glyph bounding rect for the attachment character
                // This gives us the EXACT position where the attachment is drawn
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

                // The attachment's actual visual rect is the glyph rect (which respects bounds.origin)
                // plus the attachment's size
                let attachmentRect = CGRect(
                    origin: glyphRect.origin,
                    size: attachment.bounds.size
                ).integral

                // Only handle clicks within the actual visible attachment area
                guard attachmentRect.contains(pointInContainer) else { return false }

                switch action {
                case let .webClip(url):
                    NSWorkspace.shared.open(url)
                    return true
                case let .file(url):
                    NSWorkspace.shared.open(url)
                    return true
                }

            }

            func updateColorScheme(_ scheme: ColorScheme) {
                currentColorScheme = scheme
            }

            func applyInitialText(_ text: String) {
                guard let textView = textView, let textStorage = textView.textStorage else {
                    return
                }

                print("DEBUG: ApplyInitialText called with text: '\(text.prefix(100))...'")
                print("DEBUG: Current color scheme: \(currentColorScheme)")

                isUpdating = true

                // Set the textView's base text color first
                let targetTextColor: NSColor
                if currentColorScheme == .dark {
                    targetTextColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                } else {
                    targetTextColor = NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)
                }
                textView.textColor = targetTextColor
                print("DEBUG: Set textView.textColor to: \(targetTextColor)")

                // Ensure we deserialize the text properly
                let attributedText = deserialize(text)
                print("DEBUG: Deserialized text length: \(attributedText.length)")

                // Check what color the deserialized text has
                if attributedText.length > 0 {
                    let attrs = attributedText.attributes(at: 0, effectiveRange: nil)
                    print(
                        "DEBUG: First char attributes - foregroundColor: \(attrs[.foregroundColor] ?? "nil")"
                    )
                }

                // Set the attributed string
                textStorage.setAttributedString(attributedText)

                // Ensure proper typing attributes are set
                textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)

                // Apply paragraph styling
                styleTodoParagraphs()

                // Ensure all text has proper color - critical for existing notes
                ensureTextColor()

                // Check color again after ensureTextColor
                if textStorage.length > 0 {
                    let attrs = textStorage.attributes(at: 0, effectiveRange: nil)
                    print(
                        "DEBUG: After ensureTextColor - foregroundColor: \(attrs[.foregroundColor] ?? "nil")"
                    )
                }

                // Update serialized state
                lastSerialized = serialize()

                // Force layout and size recalculation
                if let container = textView.textContainer,
                    let layoutManager = textView.layoutManager
                {
                    layoutManager.ensureLayout(for: container)
                }
                textView.invalidateIntrinsicContentSize()
                textView.needsDisplay = true
                textView.needsLayout = true

                print("DEBUG: Text view content after setup: '\(textView.string.prefix(100))...'")
                print("DEBUG: Text view final textColor: \(textView.textColor ?? NSColor.clear)")

                isUpdating = false
            }

            // Ensures all text has the correct foreground color attribute
            private func ensureTextColor() {
                guard let textView = textView, let textStorage = textView.textStorage else {
                    return
                }
                let fullRange = NSRange(location: 0, length: textStorage.length)

                // Get the correct text color for current scheme
                let textColor: NSColor
                if currentColorScheme == .dark {
                    textColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                } else {
                    textColor = NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)
                }

                print(
                    "DEBUG: ensureTextColor - applying color: \(textColor) for scheme: \(currentColorScheme)"
                )

                // Batch the text storage edits
                textStorage.beginEditing()

                // Remove any existing foreground color first, then apply new one
                textStorage.removeAttribute(.foregroundColor, range: fullRange)

                // Now apply the correct color to all non-attachment text
                textStorage.enumerateAttributes(in: fullRange, options: []) {
                    attributes, range, _ in
                    // Skip attachments - they don't need text color
                    if attributes[.attachment] == nil {
                        textStorage.addAttribute(.foregroundColor, value: textColor, range: range)
                        print("DEBUG: Applied color to range: \(range)")
                    }
                }

                textStorage.endEditing()

                // Force the text view to redisplay with new colors
                textView.needsDisplay = true
                if let layoutManager = textView.layoutManager,
                    let textContainer = textView.textContainer
                {
                    layoutManager.invalidateDisplay(forCharacterRange: fullRange)
                    layoutManager.ensureLayout(for: textContainer)
                }
            }

            func updateIfNeeded(with text: String) {
                guard !isUpdating, let textView = textView, let textStorage = textView.textStorage
                else {
                    print(
                        "DEBUG: UpdateIfNeeded - guard failed. isUpdating: \(isUpdating), textView: \(textView != nil), textStorage: \(textView?.textStorage != nil)"
                    )
                    return
                }

                guard text != lastSerialized else {
                    print("DEBUG: UpdateIfNeeded - text hasn't changed")
                    return
                }

                print("DEBUG: UpdateIfNeeded called with text: '\(text.prefix(100))...'")
                print("DEBUG: Last serialized was: '\(lastSerialized.prefix(100))...'")

                // Store current selection before updating
                let selectedRange = textView.selectedRange()

                isUpdating = true

                // Set the textView's base text color
                if currentColorScheme == .dark {
                    textView.textColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                } else {
                    textView.textColor = NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)
                }

                // Deserialize and set the new text
                let attributedText = deserialize(text)
                textStorage.setAttributedString(attributedText)

                // Force typing attributes immediately and again after a brief delay
                // to ensure Writing Tools respects our formatting
                textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                DispatchQueue.main.async {
                    textView.typingAttributes = Self.baseTypingAttributes(
                        for: self.currentColorScheme)
                }

                styleTodoParagraphs()

                // Ensure text color is correct after updating
                ensureTextColor()

                lastSerialized = serialize()

                // Restore selection after updating
                textView.setSelectedRange(selectedRange)

                print(
                    "DEBUG: UpdateIfNeeded complete. Text view now shows: '\(textView.string.prefix(100))...'"
                )

                isUpdating = false
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView, textView == self.textView,
                    !isUpdating
                else {
                    print(
                        "DEBUG: textDidChange - guard failed. Same textView: \(notification.object as? NSTextView == self.textView), isUpdating: \(isUpdating)"
                    )
                    return
                }

                print("DEBUG: textDidChange - text changed to: '\(textView.string.prefix(100))...'")

                // Ensure typing attributes are preserved after Writing Tools operations
                DispatchQueue.main.async {
                    // Skip processing if we're in the middle of an update
                    guard !self.isUpdating else { return }

                    // Fix any inconsistent fonts first
                    self.fixInconsistentFonts()
                    textView.typingAttributes = Self.baseTypingAttributes(
                        for: self.currentColorScheme)

                    // Apply consistent formatting to any new text that might have been inserted
                    // without proper attributes (e.g., from Writing Tools)
                    let selectedRange = textView.selectedRange()
                    if selectedRange.length == 0 && selectedRange.location > 0 {
                        // Check if the character before cursor has proper font attributes
                        let beforeRange = NSRange(location: selectedRange.location - 1, length: 1)
                        if beforeRange.location >= 0,
                            let textStorage = textView.textStorage,
                            beforeRange.location + beforeRange.length <= textStorage.length
                        {
                            let attributes = textStorage.attributes(
                                at: beforeRange.location, effectiveRange: nil)
                            let currentFont = attributes[.font] as? NSFont
                            let expectedFont =
                                Self.baseTypingAttributes(for: self.currentColorScheme)[.font]
                                as? NSFont

                            // If font doesn't match, apply correct attributes to recent text
                            if currentFont?.fontName != expectedFont?.fontName
                                || currentFont?.pointSize != expectedFont?.pointSize
                            {
                                textStorage.addAttributes(
                                    Self.baseTypingAttributes(for: self.currentColorScheme),
                                    range: beforeRange
                                )
                            }
                        }
                    }
                }

                syncText()
            }

            func textView(
                _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                replacementString: String?
            ) -> Bool {
                // Check for "/" to trigger command menu
                if replacementString == "/" {
                    // Show command menu at cursor position
                    showCommandMenuAtCursor(
                        textView: textView, insertLocation: affectedCharRange.location)
                    return true  // Allow the "/" to be typed
                }

                // Check for Enter key in todo paragraph
                if replacementString == "\n", isInTodoParagraph(range: affectedCharRange) {
                    insertTodo()
                    return false
                }
                return true
            }

            func handleReturn(in textView: NSTextView) -> Bool {
                if isInTodoParagraph(range: textView.selectedRange()) {
                    insertTodo()
                    return true
                }
                return false
            }

            // MARK: - Command Menu Handling

            /// Shows the command menu at the current cursor position
            /// Positions menu close to cursor with viewport bounds awareness
            private func showCommandMenuAtCursor(textView: NSTextView, insertLocation: Int) {
                // Get the rect for the cursor position to place the menu
                guard let layoutManager = textView.layoutManager,
                    let textContainer = textView.textContainer
                else {
                    return
                }

                // Calculate the glyph range for the insertion point
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: insertLocation)
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

                // Convert to text view's coordinate space
                // This accounts for text container origin (insets/padding)
                let cursorX = glyphRect.origin.x + textView.textContainerOrigin.x
                let cursorY = glyphRect.origin.y + textView.textContainerOrigin.y
                let cursorHeight = glyphRect.height

                // Menu dimensions
                let menuGap: CGFloat = 4
                let safetyMargin: CGFloat = 20
                let menuHeight = TodoRichTextEditor.commandMenuTotalHeight
                let menuWidth = TodoRichTextEditor.commandMenuTotalWidth

                // Get the visible rect to check against actual viewport, not total text view bounds
                let visibleRect = textView.visibleRect

                // Check if there's enough space below the cursor in the VISIBLE area
                // This is the key: we check against visibleRect.maxY, not bounds.height
                let cursorBottomY = cursorY + cursorHeight
                let spaceBelow = visibleRect.maxY - cursorBottomY
                let shouldShowAbove = spaceBelow < (menuHeight + menuGap + safetyMargin)

                // Position menu above or below cursor depending on available space
                var xPosition = cursorX
                var yPosition: CGFloat
                if shouldShowAbove {
                    // Position above cursor
                    yPosition = cursorY - menuHeight - menuGap
                } else {
                    // Position below cursor (default)
                    yPosition = cursorY + cursorHeight + menuGap
                }

                // Clamp X within visible bounds to avoid clipping
                let minX = visibleRect.minX + safetyMargin
                let maxX = visibleRect.maxX - menuWidth - safetyMargin
                if minX <= maxX {
                    xPosition = min(max(xPosition, minX), maxX)
                } else {
                    xPosition = max(
                        visibleRect.minX + menuGap,
                        visibleRect.maxX - menuWidth - menuGap
                    )
                }

                // Clamp Y to keep menu fully visible
                let minY = visibleRect.minY + safetyMargin
                let maxY = visibleRect.maxY - menuHeight - safetyMargin
                if minY <= maxY {
                    yPosition = min(max(yPosition, minY), maxY)
                } else {
                    yPosition = max(
                        visibleRect.minY + menuGap,
                        visibleRect.maxY - menuHeight - menuGap
                    )
                }

                let menuPosition = CGPoint(x: xPosition, y: yPosition)

                // Only need extra space when menu shows below cursor AND there's not enough space
                let needsExtraSpace = !shouldShowAbove && spaceBelow < (menuHeight + menuGap + safetyMargin)

                print("🔴 POSTING ShowCommandMenu notification - position: \(menuPosition), slashLocation: \(insertLocation), needsSpace: \(needsExtraSpace)")

                // Post notification to show menu
                NotificationCenter.default.post(
                    name: .showCommandMenu,
                    object: [
                        "position": menuPosition,
                        "slashLocation": insertLocation,
                        "needsSpace": needsExtraSpace
                    ]
                )
            }

            /// Handles command menu tool application
            private func handleCommandMenuToolApplication(_ notification: Notification) {
                guard let info = notification.object as? [String: Any],
                    let tool = info["tool"] as? EditTool,
                    let slashLocation = info["slashLocation"] as? Int,
                    let textView = textView,
                    let textStorage = textView.textStorage
                else { return }

                // Remove the "/" character that triggered the menu
                if slashLocation >= 0 && slashLocation < textStorage.length {
                    let slashRange = NSRange(location: slashLocation, length: 1)
                    if textView.shouldChangeText(in: slashRange, replacementString: "") {
                        textStorage.replaceCharacters(in: slashRange, with: "")
                        textView.didChangeText()
                    }
                }

                // Apply the selected tool
                formatter.applyFormatting(to: textView, tool: tool)

                // Sync the text back
                syncText()
            }

            // MARK: - Todo Handling

            private func insertTodo() {
                guard let textView = textView else { return }
                let attachment = NSTextAttachment()
                let cell = TodoCheckboxAttachmentCell(isChecked: false)
                attachment.attachmentCell = cell
                attachment.bounds = CGRect(
                    x: 0, y: Self.checkboxAttachmentYOffset, width: Self.checkboxIconSize,
                    height: Self.checkboxIconSize)

                let todoAttachment = NSMutableAttributedString(attachment: attachment)
                todoAttachment.addAttribute(
                    .baselineOffset, value: Self.checkboxBaselineOffset,
                    range: NSRange(location: 0, length: todoAttachment.length))
                // Add comfortable spacing between checkbox and text (2 spaces)
                let space = NSAttributedString(
                    string: "  ", attributes: Self.baseTypingAttributes(for: currentColorScheme))
                let paragraphBreak = NSAttributedString(
                    string: "\n", attributes: Self.baseTypingAttributes(for: currentColorScheme))

                let composed = NSMutableAttributedString()
                if textView.selectedRange().location != 0 {
                    composed.append(paragraphBreak)
                }
                composed.append(todoAttachment)
                composed.append(space)

                replaceSelection(with: composed)
                styleTodoParagraphs()
                syncText()
            }

            private func insertWebClip(url: String) {
                guard let textView = textView else { return }
                let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedURL = Self.normalizedURL(from: cleanURL)
                let linkValue = normalizedURL.isEmpty ? cleanURL : normalizedURL
                let attachment = makeWebClipAttachment(
                    url: linkValue,
                    title: nil,
                    description: nil,
                    domain: nil
                )

                let composed = NSMutableAttributedString()
                let selectedRange = textView.selectedRange()

                // Check if we need a newline before (only if not at start and previous char is not whitespace)
                if selectedRange.location > 0 {
                    if let textStorage = textView.textStorage,
                       selectedRange.location <= textStorage.length {
                        let prevChar = (textStorage.string as NSString).substring(
                            with: NSRange(location: selectedRange.location - 1, length: 1)
                        )
                        // Add newline only if previous character is not already whitespace or newline
                        if prevChar != " " && prevChar != "\n" && prevChar != "\t" {
                            let paragraphBreak = NSAttributedString(
                                string: "\n",
                                attributes: Self.baseTypingAttributes(for: currentColorScheme)
                            )
                            composed.append(paragraphBreak)
                        }
                    }
                }

                composed.append(attachment)

                // Always add a space after the web clip for horizontal spacing
                let space = NSAttributedString(
                    string: " ",
                    attributes: Self.baseTypingAttributes(for: currentColorScheme)
                )
                composed.append(space)

                replaceSelection(with: composed)
                syncText()
            }

            private func deleteWebClipAttachment(url: String) {
                guard let textStorage = textView?.textStorage else { return }

                textStorage.enumerateAttribute(
                    .attachment, in: NSRange(location: 0, length: textStorage.length)
                ) { value, range, stop in
                    if value as? NSTextAttachment != nil,
                        let linkValue = textStorage.attribute(
                            .link, at: range.location, effectiveRange: nil) as? String,
                        Self.normalizedURL(from: linkValue) == Self.normalizedURL(from: url)
                    {
                        textStorage.deleteCharacters(in: range)
                        stop.pointee = true
                    }
                }
                syncText()
            }

            private func insertVoiceTranscript(transcript: String) {
                NSLog("📝 insertVoiceTranscript: Called with transcript: %@", transcript)
                guard textView != nil else {
                    NSLog("📝 insertVoiceTranscript: textView is nil")
                    return
                }
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    NSLog("📝 insertVoiceTranscript: trimmed transcript is empty")
                    return
                }

                NSLog("📝 insertVoiceTranscript: Inserting trimmed text: %@", trimmed)
                // Add proper spacing and formatting
                let formatted = trimmed + " "
                replaceSelection(
                    with: NSAttributedString(
                        string: formatted,
                        attributes: Self.baseTypingAttributes(for: currentColorScheme)))
                syncText()
                NSLog("📝 insertVoiceTranscript: Completed")
            }
            
            private func insertImage(filename: String) {
                NSLog("📝 insertImage: Called with filename: %@", filename)
                guard let textView = textView else {
                    NSLog("📝 insertImage: textView is nil")
                    return
                }

                let selectionRange = textView.selectedRange()
                let storageString = textView.textStorage?.string ?? ""
                let nsString = storageString as NSString
                let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)

                let composed = NSMutableAttributedString()

                if needsLeadingSpace(before: selectionRange, in: nsString) {
                    let leadingSpace = NSAttributedString(string: " ", attributes: baseAttributes)
                    composed.append(leadingSpace)
                }

                NSLog("📝 insertImage: Creating inline image tag attachment")
                let attachment = makeImageAttachment(filename: filename)
                composed.append(attachment)

                if needsTrailingSpace(after: selectionRange, in: nsString) {
                    let trailingSpace = NSAttributedString(string: " ", attributes: baseAttributes)
                    composed.append(trailingSpace)
                }

                replaceSelection(with: composed)

                syncText()
                NSLog("📝 insertImage: Completed")
            }

            private func insertFileAttachment(
                using storedFile: FileAttachmentStorageManager.StoredFile
            ) {
                NSLog("📄 insertFileAttachment: Called with stored filename: %@",
                      storedFile.storedFilename)
                guard let textView = textView else {
                    NSLog("📄 insertFileAttachment: textView is nil")
                    return
                }

                let selectionRange = textView.selectedRange()
                let storageString = textView.textStorage?.string ?? ""
                let nsString = storageString as NSString
                let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)

                let displayLabel = AttachmentMarkup.displayLabel(for: storedFile)
                let metadata = FileAttachmentMetadata(
                    storedFilename: storedFile.storedFilename,
                    originalFilename: storedFile.originalFilename,
                    typeIdentifier: storedFile.typeIdentifier,
                    displayLabel: displayLabel
                )

                let composed = NSMutableAttributedString()

                if needsLeadingSpace(before: selectionRange, in: nsString) {
                    let leadingSpace = NSAttributedString(string: " ", attributes: baseAttributes)
                    composed.append(leadingSpace)
                }

                let attachment = makeFileAttachment(metadata: metadata)
                composed.append(attachment)

                if needsTrailingSpace(after: selectionRange, in: nsString) {
                    let trailingSpace = NSAttributedString(string: " ", attributes: baseAttributes)
                    composed.append(trailingSpace)
                }

                replaceSelection(with: composed)
                syncText()
                NSLog("📄 insertFileAttachment: Completed")
            }

            private func needsLeadingSpace(before range: NSRange, in text: NSString) -> Bool {
                guard range.location > 0 else { return false }
                let previousIndex = range.location - 1
                let previousCharacter = text.character(at: previousIndex)
                guard let scalar = UnicodeScalar(previousCharacter) else { return false }
                return !CharacterSet.whitespacesAndNewlines.contains(scalar)
            }

            private func needsTrailingSpace(after range: NSRange, in text: NSString) -> Bool {
                let endIndex = range.location + range.length
                if endIndex >= text.length {
                    return true
                }
                let nextCharacter = text.character(at: endIndex)
                guard let scalar = UnicodeScalar(nextCharacter) else { return false }
                return !CharacterSet.whitespacesAndNewlines.contains(scalar)
            }

            private func replaceSelection(with attributed: NSAttributedString) {
                guard let textView = textView else { return }
#if os(macOS)
                hideImagePreview()
#endif
                var range = textView.selectedRange()
                let storageLength = textView.textStorage?.length ?? 0

                if range.location == NSNotFound {
                    range = NSRange(location: storageLength, length: 0)
                    textView.setSelectedRange(range)
                } else {
                    if range.location > storageLength {
                        range.location = storageLength
                        range.length = 0
                        textView.setSelectedRange(range)
                    } else if range.location + range.length > storageLength {
                        range.length = max(0, storageLength - range.location)
                        textView.setSelectedRange(range)
                    }
                }

                if textView.shouldChangeText(in: range, replacementString: attributed.string) {
                    isUpdating = true
                    
                    // Check if we're inserting an attachment
                    attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
                        if let attachment = value as? NSTextAttachment {
                            NSLog("📝 replaceSelection: Inserting attachment at range %@, has image: %@", NSStringFromRange(range), attachment.image != nil ? "YES" : "NO")
                        }
                    }
                    
                    textView.textStorage?.beginEditing()
                    textView.textStorage?.replaceCharacters(in: range, with: attributed)
                    textView.textStorage?.endEditing()
                    textView.setSelectedRange(
                        NSRange(location: range.location + attributed.length, length: 0))
                    textView.didChangeText()
                    isUpdating = false
                }
            }

            private func syncText() {
                guard let textView = textView else { return }
                isUpdating = true
                styleTodoParagraphs()
                lastSerialized = serialize()
                textBinding.wrappedValue = lastSerialized

                // Always ensure typing attributes are correct after sync
                textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                isUpdating = false
            }

            /// Fixes any text that has inconsistent font formatting (e.g., from Writing Tools)
            private func fixInconsistentFonts() {
                guard let textView = textView,
                    let textStorage = textView.textStorage
                else { return }

                let expectedAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                guard let expectedFont = expectedAttributes[.font] as? NSFont,
                    let expectedColor = expectedAttributes[.foregroundColor] as? NSColor
                else { return }

                textStorage.enumerateAttributes(
                    in: NSRange(location: 0, length: textStorage.length)
                ) { attributes, range, _ in
                    var needsFixing = false
                    var fixedAttributes: [NSAttributedString.Key: Any] = attributes

                    // Check font
                    if let currentFont = attributes[.font] as? NSFont {
                        if currentFont.fontName != expectedFont.fontName
                            || currentFont.pointSize != expectedFont.pointSize
                        {
                            fixedAttributes[.font] = expectedFont
                            needsFixing = true
                        }
                    } else {
                        fixedAttributes[.font] = expectedFont
                        needsFixing = true
                    }

                    // Check text color
                    if let currentColor = attributes[.foregroundColor] as? NSColor {
                        if !currentColor.isEqual(expectedColor) {
                            fixedAttributes[.foregroundColor] = expectedColor
                            needsFixing = true
                        }
                    } else {
                        fixedAttributes[.foregroundColor] = expectedColor
                        needsFixing = true
                    }

                    if needsFixing {
                        textStorage.setAttributes(fixedAttributes, range: range)
                    }
                }
            }

            private func styleTodoParagraphs() {
                guard let textStorage = textView?.textStorage else { return }
                let fullRange = NSRange(location: 0, length: textStorage.length)
                textStorage.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) {
                    _, range, _ in
                    textStorage.removeAttribute(.paragraphStyle, range: range)
                }
                textStorage.enumerateAttribute(.baselineOffset, in: fullRange, options: []) {
                    _, range, _ in
                    textStorage.removeAttribute(.baselineOffset, range: range)
                }

                var paragraphRange = NSRange(location: 0, length: 0)
                while paragraphRange.location < textStorage.length {
                    let substringRange = (textStorage.string as NSString).paragraphRange(
                        for: NSRange(location: paragraphRange.location, length: 0))
                    if substringRange.length == 0 { break }
                    defer { paragraphRange.location = NSMaxRange(substringRange) }

                    var isTodoParagraph = false
                    var isWebClipParagraph = false

                    textStorage.enumerateAttribute(
                        .attachment,
                        in: NSRange(
                            location: substringRange.location, length: min(1, substringRange.length)
                        ), options: []
                    ) { value, _, stop in
                        if let attachment = value as? NSTextAttachment {
                            // Check if it's a todo checkbox
                            if let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell {
                                isTodoParagraph = true
                                cell.invalidateAppearance()
                                stop.pointee = true
                            }
                            // Check if it's a web clip attachment (has webClipTitle attribute)
                            else if textStorage.attribute(
                                .webClipTitle, at: substringRange.location, effectiveRange: nil)
                                != nil
                            {
                                isWebClipParagraph = true
                                stop.pointee = true
                            }
                        }
                    }

                    // Apply appropriate paragraph style based on content type
                    let paragraphStyle: NSParagraphStyle
                    if isWebClipParagraph {
                        paragraphStyle = Self.webClipParagraphStyle()
                    } else if isTodoParagraph {
                        paragraphStyle = Self.todoParagraphStyle()
                    } else {
                        paragraphStyle = Self.baseParagraphStyle()
                    }

                    textStorage.addAttribute(
                        .paragraphStyle, value: paragraphStyle, range: substringRange)

                    // Don't adjust baseline for todo or web clip paragraphs
                    if !isTodoParagraph && !isWebClipParagraph {
                        textStorage.addAttribute(
                            .baselineOffset, value: Self.baseBaselineOffset, range: substringRange)
                    }

                    if isTodoParagraph {
                        textStorage.enumerateAttribute(.attachment, in: substringRange, options: [])
                        { value, attachmentRange, _ in
                            guard let attachment = value as? NSTextAttachment,
                                let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell
                            else { return }
                            attachment.bounds = CGRect(
                                x: 0, y: Self.checkboxAttachmentYOffset,
                                width: Self.checkboxIconSize, height: Self.checkboxIconSize)
                            textStorage.addAttribute(
                                .baselineOffset, value: Self.checkboxBaselineOffset,
                                range: attachmentRange)
                            cell.invalidateAppearance()
                        }
                    }
                }
            }

            private func isInTodoParagraph(range: NSRange) -> Bool {
                guard let storage = textView?.textStorage else { return false }
                let location = max(0, min(storage.length, range.location))
                let paragraphRange = (storage.string as NSString).paragraphRange(
                    for: NSRange(location: location, length: 0))
                var isTodo = false
                storage.enumerateAttribute(
                    .attachment,
                    in: NSRange(
                        location: paragraphRange.location, length: min(1, paragraphRange.length)),
                    options: []
                ) { value, _, _ in
                    if (value as? NSTextAttachment)?.attachmentCell is TodoCheckboxAttachmentCell {
                        isTodo = true
                    }
                }
                return isTodo
            }

            private func serialize() -> String {
                guard let storage = textView?.textStorage else { return "" }
                let fullRange = NSRange(location: 0, length: storage.length)
                var output = ""
                NSLog("📝 serialize: START - storage length: %ld", storage.length)
                storage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                    if let attachment = attributes[.attachment] as? NSTextAttachment,
                        let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell
                    {
                        output.append(cell.isChecked ? "[x]" : "[ ]")
                    } else if let attachment = attributes[.attachment] as? NSTextAttachment,
                        !(attachment.attachmentCell is TodoCheckboxAttachmentCell),
                        let urlString = attributes[.link] as? String
                    {
                        var title = Self.cleanedWebClipComponent(attributes[.webClipTitle])
                        let description = Self.cleanedWebClipComponent(
                            attributes[.webClipDescription])
                        let domain = Self.cleanedWebClipComponent(attributes[.webClipDomain])
                        if title.isEmpty {
                            title = domain
                        }
                        let sanitizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                        output.append("[[webclip|\(title)|\(description)|\(sanitizedURL)]]")
                    } else if let storedFilename = attributes[.fileStoredFilename] as? String {
                        let typeIdentifierRaw = (attributes[.fileTypeIdentifier] as? String) ?? "public.data"
                        let originalNameRaw = (attributes[.fileOriginalFilename] as? String) ?? storedFilename
                        let typeIdentifier = Self.sanitizedWebClipComponent(typeIdentifierRaw)
                        let originalName = Self.sanitizedWebClipComponent(originalNameRaw)
                        output.append("[[file|\(typeIdentifier)|\(storedFilename)|\(originalName)]]")
                    } else if let attachment = attributes[.attachment] as? NSTextAttachment,
                        !(attachment.attachmentCell is TodoCheckboxAttachmentCell)
                    {
                        // Image attachment serialization with fallback
                        NSLog("📝 serialize: Found image attachment at range %@", NSStringFromRange(range))
                        // Primary: Use the robust custom attribute
                        if let filename = attributes[.imageFilename] as? String {
                            NSLog("📝 serialize: Using custom attribute filename: %@", filename)
                            output.append("[[image|||\(filename)]]")
                        }
                        // Secondary: Try NoteImageAttachment which stores filename directly
                        else if let noteAttachment = attachment as? NoteImageAttachment {
                            output.append("[[image|||\(noteAttachment.storedFilename)]]")
                            NSLog("Serialization: Recovered filename %@ from NoteImageAttachment", noteAttachment.storedFilename)
                        }
                        // Tertiary: Fallback to fileWrapper
                        else if let fileWrapper = attachment.fileWrapper,
                                let filename = fileWrapper.preferredFilename ?? fileWrapper.filename,
                                !filename.isEmpty,
                                filename.hasSuffix(".jpg")
                        {
                            output.append("[[image|||\(filename)]]")
                            NSLog("Serialization: Recovered filename %@ from fileWrapper", filename)
                        }
                        // If all fail, data is lost - log this critical error
                        else {
                            output.append((storage.string as NSString).substring(with: range))
                            NSLog("⚠️ Serialization CRITICAL: Could not find filename for image attachment. Data may be lost.")
                        }
                    } else {
                        output.append((storage.string as NSString).substring(with: range))
                    }
                }
                NSLog("📝 serialize: END - output length: %ld, contains image markup: %@", output.count, output.contains("[[image|||") ? "YES" : "NO")
                if output.contains("[[image|||") {
                    NSLog("📝 serialize: Output preview: %@", String(output.prefix(500)))
                }
                return output
            }

            private func deserialize(_ text: String) -> NSAttributedString {
                print("DEBUG: Deserializing text: '\(text)'")
                NSLog("📝 deserialize: START - text length: %ld, contains image markup: %@", text.count, text.contains("[[image|||") ? "YES" : "NO")

                // Handle empty text case
                if text.isEmpty {
                    return NSAttributedString(
                        string: "", attributes: Self.baseTypingAttributes(for: currentColorScheme))
                }

                let result = NSMutableAttributedString()
                var index = text.startIndex
                var lastWasWebClip = false

                while index < text.endIndex {
                    if text[index...].hasPrefix("[x]") || text[index...].hasPrefix("[ ]") {
                        let isChecked = text[index...].hasPrefix("[x]")
                        let attachment = NSTextAttachment()
                        attachment.attachmentCell = TodoCheckboxAttachmentCell(isChecked: isChecked)
                        attachment.bounds = CGRect(
                            x: 0, y: Self.checkboxAttachmentYOffset, width: Self.checkboxIconSize,
                            height: Self.checkboxIconSize)
                        let attString = NSMutableAttributedString(attachment: attachment)
                        attString.addAttribute(
                            .baselineOffset, value: Self.checkboxBaselineOffset,
                            range: NSRange(location: 0, length: attString.length))
                        result.append(attString)
                        index = text.index(index, offsetBy: 3)
                        lastWasWebClip = false
                        continue
                    } else if text[index...].hasPrefix(Self.webClipMarkupPrefix) {
                        if let endIndex = text[index...].range(of: "]]")?.upperBound {
                            let webclipText = String(text[index..<endIndex])
                            if let regex = Self.webClipRegex,
                                let match = regex.firstMatch(
                                    in: webclipText,
                                    options: [],
                                    range: NSRange(location: 0, length: webclipText.utf16.count)
                                )
                            {
                                let rawTitle = Self.string(from: match, at: 1, in: webclipText)
                                let rawDescription = Self.string(
                                    from: match, at: 2, in: webclipText)
                                let rawURL = Self.string(from: match, at: 3, in: webclipText)

                                let cleanedTitle = Self.sanitizedWebClipComponent(rawTitle)
                                let cleanedDescription = Self.sanitizedWebClipComponent(
                                    rawDescription)
                                let normalizedURL = Self.normalizedURL(from: rawURL)
                                let linkForAttachment =
                                    normalizedURL.isEmpty ? rawURL : normalizedURL
                                let domain = Self.sanitizedWebClipComponent(
                                    Self.resolvedDomain(from: linkForAttachment)
                                )

                                let attachment = makeWebClipAttachment(
                                    url: linkForAttachment,
                                    title: cleanedTitle.isEmpty ? nil : cleanedTitle,
                                    description: cleanedDescription.isEmpty
                                        ? nil : cleanedDescription,
                                    domain: domain.isEmpty ? nil : domain
                                )
                                result.append(attachment)

                                // Add space after webclip for horizontal spacing
                                let space = NSAttributedString(
                                    string: " ",
                                    attributes: Self.baseTypingAttributes(for: currentColorScheme))
                                result.append(space)

                                index = endIndex
                                lastWasWebClip = true
                                continue
                            }
                        }
                    } else if text[index...].hasPrefix(AttachmentMarkup.fileMarkupPrefix) {
                        if let endIndex = text[index...].range(of: "]]")?.upperBound {
                            let fileText = String(text[index..<endIndex])
                            if let regex = AttachmentMarkup.fileRegex,
                               let match = regex.firstMatch(
                                   in: fileText,
                                   options: [],
                                   range: NSRange(location: 0, length: fileText.utf16.count)
                               )
                            {
                                let rawType = Self.string(from: match, at: 1, in: fileText)
                                let storedFilename = Self.string(from: match, at: 2, in: fileText)
                                let rawOriginal = Self.string(from: match, at: 3, in: fileText)

                                let typeIdentifier = rawType.isEmpty ? "public.data" : rawType
                                let originalName = rawOriginal.isEmpty ? storedFilename : rawOriginal

                                let storedFile = FileAttachmentStorageManager.StoredFile(
                                    storedFilename: storedFilename,
                                    originalFilename: originalName,
                                    typeIdentifier: typeIdentifier
                                )

                                let metadata = FileAttachmentMetadata(
                                    storedFilename: storedFile.storedFilename,
                                    originalFilename: storedFile.originalFilename,
                                    typeIdentifier: storedFile.typeIdentifier,
                                    displayLabel: AttachmentMarkup.displayLabel(for: storedFile)
                                )

                                let baseAttributes = Self.baseTypingAttributes(
                                    for: currentColorScheme)
                                if result.length > 0,
                                   let lastScalar = result.string.unicodeScalars.last,
                                   !CharacterSet.whitespacesAndNewlines.contains(lastScalar)
                                {
                                    let leadingSpace = NSAttributedString(
                                        string: " ", attributes: baseAttributes)
                                    result.append(leadingSpace)
                                }

                                let attachment = makeFileAttachment(metadata: metadata)
                                result.append(attachment)

                                let shouldAddTrailingSpace: Bool
                                if endIndex < text.endIndex {
                                    let nextCharacter = text[endIndex]
                                    shouldAddTrailingSpace = !nextCharacter.isWhitespace
                                } else {
                                    shouldAddTrailingSpace = true
                                }

                                if shouldAddTrailingSpace {
                                    let trailingSpace = NSAttributedString(
                                        string: " ", attributes: baseAttributes)
                                    result.append(trailingSpace)
                                }

                                index = endIndex
                                lastWasWebClip = false
                                continue
                            }
                        }
                    } else if text[index...].hasPrefix(AttachmentMarkup.imageMarkupPrefix) {
                        // Image attachment deserialization
                        NSLog("📝 deserialize: Found image markup prefix")
                        if let endIndex = text[index...].range(of: "]]")?.upperBound {
                            let imageText = String(text[index..<endIndex])
                            NSLog("📝 deserialize: Markup text: %@", imageText)
                            if let regex = AttachmentMarkup.imageRegex,
                                let match = regex.firstMatch(
                                    in: imageText,
                                    options: [],
                                    range: NSRange(location: 0, length: imageText.utf16.count)
                                )
                            {
                                let filename = Self.string(from: match, at: 1, in: imageText)
                                NSLog("📝 deserialize: Extracted filename: %@", filename)
                                
                                // Ensure spacing around inline attachment
                                let baseAttributes = Self.baseTypingAttributes(
                                    for: currentColorScheme)
                                if result.length > 0,
                                    let lastScalar = result.string.unicodeScalars.last,
                                    !CharacterSet.whitespacesAndNewlines.contains(lastScalar)
                                {
                                    let leadingSpace = NSAttributedString(
                                        string: " ", attributes: baseAttributes)
                                    result.append(leadingSpace)
                                }

                                let attachment = makeImageAttachment(filename: filename)
                                result.append(attachment)

                                let shouldAddTrailingSpace: Bool
                                if endIndex < text.endIndex {
                                    let nextCharacter = text[endIndex]
                                    shouldAddTrailingSpace = !nextCharacter.isWhitespace
                                } else {
                                    shouldAddTrailingSpace = true
                                }

                                if shouldAddTrailingSpace {
                                    let trailingSpace = NSAttributedString(
                                        string: " ", attributes: baseAttributes)
                                    result.append(trailingSpace)
                                }
                                
                                index = endIndex
                                lastWasWebClip = false
                                continue
                            }
                        }
                    }

                    // Add single character with proper attributes
                    let char = String(text[index])

                    // Convert newline to space if between webclips
                    let finalChar: String
                    if char == "\n" && lastWasWebClip {
                        // Check if next non-whitespace char is a webclip
                        var nextIndex = text.index(after: index)
                        while nextIndex < text.endIndex && text[nextIndex].isWhitespace && text[nextIndex] != "\n" {
                            nextIndex = text.index(after: nextIndex)
                        }
                        if nextIndex < text.endIndex && text[nextIndex...].hasPrefix(Self.webClipMarkupPrefix) {
                            finalChar = " "  // Convert newline to space between webclips
                        } else {
                            finalChar = char
                        }
                    } else {
                        finalChar = char
                    }

                    let attributedChar = NSAttributedString(
                        string: finalChar,
                        attributes: Self.baseTypingAttributes(for: currentColorScheme))
                    result.append(attributedChar)
                    index = text.index(after: index)
                    lastWasWebClip = false
                }

                print("DEBUG: Deserialized attributed string length: \(result.length)")
                print("DEBUG: Deserialized plain text: '\(result.string)'")

                return result
            }

            // MARK: - Helpers

            static func baseParagraphStyle() -> NSParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.2
                style.minimumLineHeight = baseLineHeight
                style.maximumLineHeight = baseLineHeight + 4
                style.paragraphSpacing = 8
                return style
            }

            static func todoParagraphStyle() -> NSParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.2
                style.minimumLineHeight = todoLineHeight
                style.maximumLineHeight = todoLineHeight + 4
                style.paragraphSpacing = 10
                style.firstLineHeadIndent = 0
                style.headIndent = 30
                return style
            }

            // Paragraph style for web clip attachments with extra spacing to prevent overlap
            static func webClipParagraphStyle() -> NSParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.0
                // NO minimum/maximum line height - let attachment determine its own space
                // This prevents empty clickable space above/below
                style.minimumLineHeight = 0
                style.maximumLineHeight = 0
                // No paragraph spacing - web clips are now inline with horizontal spacing
                style.paragraphSpacing = 0
                style.paragraphSpacingBefore = 0
                return style
            }
            
            static func imageTagVerticalOffset(for height: CGFloat) -> CGFloat {
                let offset = (textFont.capHeight - height) / 2
                return offset
            }

            static func baseTypingAttributes(for colorScheme: ColorScheme? = nil)
                -> [NSAttributedString.Key: Any]
            {
                let textColor: NSColor
                if let scheme = colorScheme {
                    // Use the actual PrimaryTextColor values from the asset catalog
                    if scheme == .dark {
                        textColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)  // White for dark mode
                    } else {
                        textColor = NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)  // Dark gray for light mode
                    }
                } else {
                    textColor = NSColor.labelColor
                }

                return [
                    .font: textFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: baseParagraphStyle(),
                    .underlineStyle: 0,
                        // .baselineOffset: baseBaselineOffset,
                ]
            }

            private static func baselineOffset(forLineHeight lineHeight: CGFloat, font: NSFont)
                -> CGFloat
            {
                let metrics = font.ascender - font.descender + font.leading
                let delta = max(0, lineHeight - metrics)
                return delta / 2
            }

            // MARK: - Writing Tools Support (macOS 15+)
            @available(macOS 15.0, *)
            func textViewWritingToolsWillBegin(_ textView: NSTextView) {
                // Store text before Writing Tools starts
                textBeforeWritingTools = textView.string
            }

            @available(macOS 15.0, *)
            func textViewWritingToolsDidEnd(_ textView: NSTextView) {
                // Writing Tools finished - textDidChange will handle summary detection
            }
        }
    }

    final class InlineNSTextView: NSTextView {
        // Static flag to track command menu visibility for keyboard event handling
        static var isCommandMenuShowing = false

        weak var actionDelegate: TodoEditorRepresentable.Coordinator?
        private var hoverTrackingArea: NSTrackingArea?

        override var intrinsicContentSize: NSSize {
            guard let layoutManager = layoutManager,
                let textContainer = textContainer
            else {
                return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = usedRect.height + textContainerInset.height * 2

            return NSSize(width: NSView.noIntrinsicMetric, height: height)
        }

        override func didChangeText() {
            super.didChangeText()
            invalidateIntrinsicContentSize()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            registerForDraggedTypes([.fileURL])
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area = hoverTrackingArea {
                removeTrackingArea(area)
            }
            let options: NSTrackingArea.Options = [
                .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect
            ]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverTrackingArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let point = convert(event.locationInWindow, from: nil)
            if actionDelegate?.handleAttachmentHover(at: point, in: self) != true {
                actionDelegate?.endAttachmentHover()
            }
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            actionDelegate?.endAttachmentHover()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result {
                // Ensure the text view is properly focused and can receive input
                // Fix timing issue by ensuring window focus happens on next run loop
                DispatchQueue.main.async {
                    self.window?.makeFirstResponder(self)
                    // Additional check to ensure we can actually receive text input
                    self.insertionPointColor = NSColor.controlAccentColor
                    self.needsDisplay = true
                }
            }
            return result
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if actionDelegate?.handleAttachmentClick(at: point, in: self) == true {
                return
            }
            actionDelegate?.endAttachmentHover()
            // Ensure the text view becomes first responder on click
            if window?.makeFirstResponder(self) == true {
                // Additional verification that we're ready for text input
                DispatchQueue.main.async {
                    if self.window?.firstResponder == self {
                        self.insertionPointColor = NSColor.controlAccentColor
                        self.needsDisplay = true
                    }
                }
            }
            super.mouseDown(with: event)
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            if actionDelegate?.canHandleFileDrop(sender, in: self) == true {
                return .copy
            }
            return super.draggingEntered(sender)
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            if actionDelegate?.canHandleFileDrop(sender, in: self) == true {
                return true
            }
            return super.prepareForDragOperation(sender)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            if actionDelegate?.handleFileDrop(sender, in: self) == true {
                return true
            }
            return super.performDragOperation(sender)
        }

        override func insertNewline(_ sender: Any?) {
            print("DEBUG: insertNewline called")
            if actionDelegate?.handleReturn(in: self) == true { return }
            super.insertNewline(sender)
        }

        override func keyDown(with event: NSEvent) {
            print("DEBUG: keyDown called with key: \(event.characters ?? "nil")")

            // Only intercept keys if command menu is showing
            guard InlineNSTextView.isCommandMenuShowing else {
                super.keyDown(with: event)
                return
            }

            // Handle special keys for command menu navigation
            // keyCode 126 = Up Arrow, 125 = Down Arrow, 36 = Return, 53 = Escape
            switch event.keyCode {
            case 126:  // Up Arrow
                // Post notification to navigate up in command menu
                NotificationCenter.default.post(name: .commandMenuNavigateUp, object: nil)
                return  // Don't pass to super to prevent cursor movement

            case 125:  // Down Arrow
                // Post notification to navigate down in command menu
                NotificationCenter.default.post(name: .commandMenuNavigateDown, object: nil)
                return  // Don't pass to super to prevent cursor movement

            case 36, 76:  // Return or Enter key
                // Post notification to select current command menu item
                NotificationCenter.default.post(name: .commandMenuSelect, object: nil)
                // If command menu handles it, don't pass to super
                // The notification handler will determine if it was consumed
                return

            case 53:  // Escape key
                // Post notification to hide command menu
                NotificationCenter.default.post(name: .hideCommandMenu, object: nil)
                return

            default:
                // For all other keys, check if we should hide the command menu
                // Any character input (other than arrow keys) should hide the menu
                if event.characters != nil && event.characters != "" {
                    NotificationCenter.default.post(name: .hideCommandMenu, object: nil)
                }
                super.keyDown(with: event)
            }
        }

        @available(macOS 10.11, *)
        override func insertText(_ string: Any, replacementRange: NSRange) {
            // Check if we're inserting "/" to trigger command menu
            if let str = string as? String, str == "/" {
                // Get the cursor position before insertion
                let location = selectedRange().location

                // Allow the "/" to be inserted first
                super.insertText(string, replacementRange: replacementRange)

                // Then show the command menu at that position
                if actionDelegate != nil {
                    // Post notification to show command menu
                    // We need to get the rect for the inserted "/" character
                    if let layoutManager = self.layoutManager,
                        let textContainer = self.textContainer
                    {
                        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
                        let glyphRect = layoutManager.boundingRect(
                            forGlyphRange: NSRange(location: glyphIndex, length: 1),
                            in: textContainer)

                        let cursorX = glyphRect.origin.x + self.textContainerOrigin.x
                        let cursorY = glyphRect.origin.y + self.textContainerOrigin.y
                        let cursorHeight = glyphRect.height

                        let xPosition = cursorX
                        let yPosition = cursorY + cursorHeight + 4

                        let menuPosition = CGPoint(x: xPosition, y: yPosition)

                        NotificationCenter.default.post(
                            name: .showCommandMenu,
                            object: ["position": menuPosition, "slashLocation": location]
                        )
                    }
                }
                return
            }

            super.insertText(string, replacementRange: replacementRange)
        }
        
        // MARK: - Context Menu Implementation
        
        override func menu(for event: NSEvent) -> NSMenu? {
            // Create a custom context menu for the text editor
            let menu = NSMenu()
            
            // Standard text editing actions
            menu.addItem(NSMenuItem(title: "Cut", action: #selector(cut(_:)), keyEquivalent: "x"))
            menu.addItem(NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c"))
            menu.addItem(NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "v"))
            
            menu.addItem(NSMenuItem.separator())
            
            // Text formatting actions
            menu.addItem(NSMenuItem(title: "Bold", action: #selector(toggleBold(_:)), keyEquivalent: "b"))
            menu.addItem(NSMenuItem(title: "Italic", action: #selector(toggleItalic(_:)), keyEquivalent: "i"))
            menu.addItem(NSMenuItem(title: "Underline", action: #selector(toggleUnderline(_:)), keyEquivalent: "u"))
            
            menu.addItem(NSMenuItem.separator())
            
            // Special formatting actions
            menu.addItem(NSMenuItem(title: "Insert Todo", action: #selector(insertTodo(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Insert Bullet List", action: #selector(insertBulletList(_:)), keyEquivalent: ""))
            
            menu.addItem(NSMenuItem.separator())
            
            // Select all
            menu.addItem(NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a"))
            
            return menu
        }
        
        // MARK: - Context Menu Actions
        
        @objc private func toggleBold(_ sender: Any?) {
            NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "bold"])
        }
        
        @objc private func toggleItalic(_ sender: Any?) {
            NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "italic"])
        }
        
        @objc private func toggleUnderline(_ sender: Any?) {
            NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "underline"])
        }
        
        @objc private func insertTodo(_ sender: Any?) {
            NotificationCenter.default.post(name: Notification.Name("TodoToolbarAction"), object: nil)
        }
        
        @objc private func insertBulletList(_ sender: Any?) {
            NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "bulletList"])
        }
    }

    private final class TodoCheckboxAttachmentCell: NSTextAttachmentCell {
        var isChecked: Bool
        private let size = NSSize(width: 24, height: 24)  // 24x24 pixels

        init(isChecked: Bool = false) {
            self.isChecked = isChecked
            super.init(imageCell: nil)
        }

        required init(coder: NSCoder) {
            self.isChecked = false
            super.init(coder: coder)
        }

        override var cellSize: NSSize { size }

        // CRITICAL: Override cellBaselineOffset to control vertical positioning
        // This is what actually determines where the attachment sits relative to the baseline
        override nonisolated func cellBaselineOffset() -> NSPoint {
            // Use the actual font metrics for perfect alignment
            // Use Charter for body text alignment calculations
            // Using inline font creation to avoid actor isolation issues in nonisolated context
            let font = NSFont(name: "Charter", size: 16) ?? NSFont.systemFont(ofSize: 16)

            // Center the checkbox with the cap height (height of capital letters)
            // This provides the best optical alignment with mixed-case text
            // Formula from Apple docs: (capHeight - imageHeight) / 2
            let offset = (font.capHeight - size.height) / 2

            return NSPoint(x: 0, y: offset)
        }

        override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
            guard let image = image(for: controlView) else { return }
            // Draw the image directly at the cellFrame position
            // The attachment.bounds.origin.y already handles vertical positioning
            // Don't add extra centering here - it causes misalignment
            let target = NSRect(
                x: cellFrame.minX,
                y: cellFrame.minY,
                width: size.width,
                height: size.height)
            image.draw(in: target)
        }

        override func wantsToTrackMouse() -> Bool {
            true
        }

        override func trackMouse(
            with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?,
            atCharacterIndex charIndex: Int, untilMouseUp flag: Bool
        ) -> Bool {
            isChecked.toggle()
            if let textView = controlView as? NSTextView {
                let range = NSRange(location: charIndex, length: 1)
                textView.layoutManager?.invalidateDisplay(forGlyphRange: range)
                textView.didChangeText()
                NotificationCenter.default.post(
                    name: NSText.didChangeNotification, object: textView)
            }
            return true
        }

        func invalidateAppearance() {
            // no-op placeholder to keep API symmetrical with iOS implementation
        }

        private func image(for controlView: NSView?) -> NSImage? {
            // Detect dark mode
            let isDark: Bool
            if let appearance = controlView?.effectiveAppearance {
                isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            } else {
                isDark = false
            }

            // Use SF Symbols for perfect alignment and consistency
            let symbolName = isChecked ? "checkmark.circle.fill" : "circle"
            let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)

            // Create the image with proper configuration
            guard
                let baseImage = NSImage(
                    systemSymbolName: symbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
            else { return nil }

            // Create tinted version
            let tinted = NSImage(size: baseImage.size)
            tinted.lockFocus()

            let rect = NSRect(origin: .zero, size: baseImage.size)

            if isChecked {
                // Checked state: black in light mode, white in dark mode
                if isDark {
                    NSColor.white.set()
                } else {
                    NSColor.black.set()
                }
            } else {
                // Unchecked state: adapt to color scheme
                if isDark {
                    // White/light gray circle in dark mode for visibility
                    NSColor(white: 0.85, alpha: 1.0).set()
                } else {
                    // Dark gray circle in light mode
                    NSColor(white: 0.3, alpha: 1.0).set()
                }
            }

            // Draw the symbol with the color
            baseImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            rect.fill(using: .sourceAtop)

            tinted.unlockFocus()
            return tinted
        }
    }

#else

    struct TodoEditorRepresentable: UIViewRepresentable {
        @Binding var text: String
        let colorScheme: ColorScheme
        let bottomInset: CGFloat

        // A custom text view that correctly reports its intrinsic content size
        // for proper dynamic height sizing in SwiftUI.
        final class DynamicHeightTextView: UITextView {
            // Static flag to track command menu visibility for keyboard event handling
            static var isCommandMenuShowing = false

            override var intrinsicContentSize: CGSize {
                // Return a size that fits the content. fall back to a reasonable width if undefined.
                let fixedWidth = frame.size.width > 0 ? frame.size.width : 600
                let size = sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
                let lineHeight = font?.lineHeight ?? 24
                let minimumHeight = lineHeight + textContainerInset.top + textContainerInset.bottom
                let result = CGSize(width: fixedWidth, height: max(size.height, minimumHeight))
                return result
            }
            
            // MARK: - Context Menu Implementation for iOS
            
            override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
                // Allow standard text editing actions
                if action == #selector(cut(_:)) || action == #selector(copy(_:)) || action == #selector(paste(_:)) || action == #selector(selectAll(_:)) {
                    return super.canPerformAction(action, withSender: sender)
                }
                
                // Allow our custom actions
                if action == #selector(toggleBold(_:)) || action == #selector(toggleItalic(_:)) || action == #selector(toggleUnderline(_:)) || action == #selector(insertTodo(_:)) || action == #selector(insertBulletList(_:)) {
                    return true
                }
                
                return false
            }
            
            override func menuItems(for menu: UIMenu) -> [UIMenuElement] {
                var items: [UIMenuElement] = []
                
                // Standard text editing actions
                if canPerformAction(#selector(cut(_:)), withSender: nil) {
                    items.append(UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { _ in
                        self.cut(self)
                    })
                }
                
                if canPerformAction(#selector(copy(_:)), withSender: nil) {
                    items.append(UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                        self.copy(self)
                    })
                }
                
                if canPerformAction(#selector(paste(_:)), withSender: nil) {
                    items.append(UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { _ in
                        self.paste(self)
                    })
                }
                
                if !items.isEmpty {
                    items.append(UIMenuElement.separator())
                }
                
                // Text formatting actions
                items.append(UIAction(title: "Bold", image: UIImage(systemName: "bold")) { _ in
                    self.toggleBold(self)
                })
                
                items.append(UIAction(title: "Italic", image: UIImage(systemName: "italic")) { _ in
                    self.toggleItalic(self)
                })
                
                items.append(UIAction(title: "Underline", image: UIImage(systemName: "underline")) { _ in
                    self.toggleUnderline(self)
                })
                
                items.append(UIMenuElement.separator())
                
                // Special formatting actions
                items.append(UIAction(title: "Insert Todo", image: UIImage(systemName: "checkmark.circle")) { _ in
                    self.insertTodo(self)
                })
                
                items.append(UIAction(title: "Insert Bullet List", image: UIImage(systemName: "list.bullet")) { _ in
                    self.insertBulletList(self)
                })
                
                items.append(UIMenuElement.separator())
                
                // Select all
                if canPerformAction(#selector(selectAll(_:)), withSender: nil) {
                    items.append(UIAction(title: "Select All", image: UIImage(systemName: "textformat.abc")) { _ in
                        self.selectAll(self)
                    })
                }
                
                return items
            }
            
            // MARK: - Context Menu Actions
            
            @objc private func toggleBold(_ sender: Any?) {
                NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "bold"])
            }
            
            @objc private func toggleItalic(_ sender: Any?) {
                NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "italic"])
            }
            
            @objc private func toggleUnderline(_ sender: Any?) {
                NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "underline"])
            }
            
            @objc private func insertTodo(_ sender: Any?) {
                NotificationCenter.default.post(name: Notification.Name("TodoToolbarAction"), object: nil)
            }
            
            @objc private func insertBulletList(_ sender: Any?) {
                NotificationCenter.default.post(name: .applyEditTool, object: nil, userInfo: ["tool": "bulletList"])
            }
        }

        func makeUIView(context: Context) -> UITextView {
            let textView = DynamicHeightTextView()
            textView.delegate = context.coordinator
            textView.isEditable = true
            textView.isSelectable = true
            textView.isScrollEnabled = false  // Disable internal scrolling - let parent scroll view handle it
            textView.alwaysBounceVertical = false
            textView.backgroundColor = .clear
            // Use Charter for body text as per design requirements
            textView.font = FontManager.bodyUI(size: 16, weight: .regular)
            // Don't set textColor here - it will be set properly based on color scheme below
            textView.tintColor = UIColor(named: "AccentColor") ?? .systemBlue
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
            textView.textContainer.lineFragmentPadding = 0
            // Remove all insets since text editor is now part of unified scroll view
            textView.contentInset = UIEdgeInsets.zero
            textView.scrollIndicatorInsets = UIEdgeInsets.zero
            textView.linkTextAttributes = [
                .underlineStyle: 0
            ]
            // Allow the text view to size naturally based on content - handled by DynamicHeightTextView now
            //            textView.setContentHuggingPriority(.required, for: .vertical)
            //            textView.setContentCompressionResistancePriority(.required, for: .vertical)
            let initialScheme = resolvedColorScheme(for: textView)

            // Set initial text color based on color scheme
            let initialTextColor: UIColor
            if initialScheme == .dark {
                initialTextColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)  // White for dark mode
            } else {
                initialTextColor = UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)  // Dark gray for light mode
            }
            textView.textColor = initialTextColor
            textView.typingAttributes = Coordinator.baseTypingAttributes(for: initialScheme)

            // Enable Writing Tools when text is selected (without standalone button)
            if #available(iOS 18.0, *) {
                textView.writingToolsBehavior = .complete
            }

            context.coordinator.updateColorScheme(initialScheme)
            context.coordinator.configure(with: textView)
            context.coordinator.applyInitialText(text)
            return textView
        }

        func updateUIView(_ uiView: UITextView, context: Context) {
            // Only update color scheme if it has changed to reduce glitching
            let resolvedScheme = resolvedColorScheme(for: uiView)
            // Note: We'll update colors every time for now to ensure consistency
            let currentTextColor: UIColor
            if resolvedScheme == .dark {
                currentTextColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)  // White for dark mode
            } else {
                currentTextColor = UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)  // Dark gray for light mode
            }
            uiView.textColor = currentTextColor
            uiView.typingAttributes = Coordinator.baseTypingAttributes(for: resolvedScheme)
            uiView.linkTextAttributes = [
                .underlineStyle: 0
            ]
            context.coordinator.updateColorScheme(resolvedScheme)

            // Only update text if it has actually changed
            context.coordinator.updateIfNeeded(with: text)
        }

        // Report dynamic size to SwiftUI so the editor grows with its content (no minHeight)
        func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context)
            -> CGSize
        {
            let paddingAdjustment: CGFloat = 0  // outer SwiftUI padding handles margins
            let targetWidth = (proposal.width ?? UIScreen.main.bounds.width) - paddingAdjustment
            let fitting = uiView.sizeThatFits(
                CGSize(width: max(0, targetWidth), height: .greatestFiniteMagnitude))
            let lineHeight = uiView.font?.lineHeight ?? 24
            let minHeight =
                lineHeight + uiView.textContainerInset.top + uiView.textContainerInset.bottom
            let result = CGSize(width: targetWidth, height: max(fitting.height, minHeight))
            return result
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text, colorScheme: colorScheme)
        }

        private func resolvedColorScheme(for view: UIView) -> ColorScheme {
            if view.traitCollection.userInterfaceStyle == .dark {
                return .dark
            }
            if view.traitCollection.userInterfaceStyle == .light {
                return .light
            }
            return colorScheme
        }

        @MainActor final class Coordinator: NSObject, UITextViewDelegate {
            private weak var textView: UITextView?
            private var observers: [NSObjectProtocol] = []
            private var lastSerialized = ""
            private var isUpdating = false
            private var textBinding: Binding<String>
            private var currentColorScheme: ColorScheme
            private struct FileAttachmentMetadata {
                let storedFilename: String
                let originalFilename: String
                let typeIdentifier: String
                let displayLabel: String
            }

            // Use Charter for body text as per design requirements
            private static let textFont = FontManager.bodyUI(size: 16, weight: .regular)
            private static let baseLineHeight: CGFloat = 24
            private static let todoLineHeight: CGFloat = 24
            private static let checkboxIconSize: CGFloat = 24  // 24x24 pixels for better visibility
            private static let baseBaselineOffset: CGFloat = 0.0
            private static let todoBaselineOffset: CGFloat = {
                // Don't offset the text baseline
                return 0.0
            }()
            private static let checkboxAttachmentYOffset: CGFloat = {
                // Use font metrics for perfect alignment
                // Center the checkbox with the cap height (height of capital letters)
                // Formula from Apple docs: (capHeight - imageHeight) / 2
                // Use Charter for body text alignment calculations
                let font = FontManager.bodyUI(size: 16, weight: .regular)
                let checkboxHeight: CGFloat = 24
                let offset = (font.capHeight - checkboxHeight) / 2
                return offset
            }()
            private static let checkboxBaselineOffset: CGFloat = {
                // No additional baseline adjustment needed
                return 0.0
            }()

            init(text: Binding<String>, colorScheme: ColorScheme) {
                self.textBinding = text
                self.currentColorScheme = colorScheme
            }

            deinit {
                observers.forEach { NotificationCenter.default.removeObserver($0) }
                observers.removeAll()
            }

            func configure(with textView: UITextView) {
                self.textView = textView

                let insertTodo = NotificationCenter.default.addObserver(
                    forName: .insertTodoInEditor, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.insertTodo()
                    }
                }

                let insertLink = NotificationCenter.default.addObserver(
                    forName: .insertWebClipInEditor, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let url = notification.object as? String else { return }
                    Task { @MainActor [weak self] in
                        self?.insertWebClip(url: url)
                    }
                }

                let insertVoiceTranscript = NotificationCenter.default.addObserver(
                    forName: .insertVoiceTranscriptInEditor, object: nil, queue: .main
                ) { [weak self] notification in
                    NSLog("📝 Coordinator: Received insertVoiceTranscriptInEditor notification")
                    // We're on main queue (specified in observer), use assumeIsolated for synchronous execution
                    // This prevents race condition with view dismissal that occurred with Task wrapper
                    MainActor.assumeIsolated {
                        guard let self = self else {
                            NSLog("⚠️ Coordinator deallocated before transcript insertion")
                            return
                        }
                        guard let transcript = notification.object as? String else {
                            NSLog("📝 Coordinator: No transcript in notification object")
                            return
                        }
                        NSLog("📝 Coordinator: Got transcript: %@", transcript)
                        self.insertVoiceTranscript(transcript: transcript)
                        NSLog("📝 Coordinator: Transcript insertion completed")
                    }
                }

                let applyCommandMenuTool = NotificationCenter.default.addObserver(
                    forName: .applyCommandMenuTool, object: nil, queue: .main
                ) { [weak self] notification in
                    Task { @MainActor [weak self] in
                        self?.handleCommandMenuToolApplication(notification)
                    }
                }

                observers = [insertTodo, insertLink, insertVoiceTranscript, insertImage, applyCommandMenuTool]

                let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
                tap.cancelsTouchesInView = false
                textView.addGestureRecognizer(tap)
            }

            func updateColorScheme(_ scheme: ColorScheme) {
                currentColorScheme = scheme
            }

            func applyInitialText(_ text: String) {
                guard let textView = textView else { return }
                isUpdating = true
                textView.attributedText = deserialize(text)
                textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)

                // Ensure all text has proper color - critical for existing notes
                ensureTextColor()

                lastSerialized = serialize()
                isUpdating = false
            }

            // Ensures all text has the correct foreground color attribute
            private func ensureTextColor() {
                guard let textView = textView else { return }
                let mutableText = NSMutableAttributedString(
                    attributedString: textView.attributedText ?? NSAttributedString())
                let fullRange = NSRange(location: 0, length: mutableText.length)

                // Get the correct text color for current scheme
                let textColor: UIColor
                if currentColorScheme == .dark {
                    textColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                } else {
                    textColor = UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)
                }

                // Unconditionally apply text color to all text ranges
                // This ensures existing content always has the correct color for the current scheme
                mutableText.enumerateAttributes(in: fullRange, options: []) {
                    attributes, range, _ in
                    // Skip attachments - they don't need text color
                    if attributes[.attachment] == nil {
                        mutableText.addAttribute(.foregroundColor, value: textColor, range: range)
                    }
                }

                textView.attributedText = mutableText
            }

            func updateIfNeeded(with text: String) {
                guard !isUpdating, text != lastSerialized, let textView else { return }
                isUpdating = true
                textView.attributedText = deserialize(text)

                // Force typing attributes immediately and again after a brief delay
                // to ensure Writing Tools respects our formatting
                textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                DispatchQueue.main.async {
                    textView.typingAttributes = Self.baseTypingAttributes(
                        for: self.currentColorScheme)
                }

                lastSerialized = serialize()
                isUpdating = false
            }

            func textViewDidChange(_ textView: UITextView) {
                // Ensure typing attributes are preserved after Writing Tools operations
                DispatchQueue.main.async {
                    // Fix any inconsistent fonts first
                    self.fixInconsistentFonts()
                    textView.typingAttributes = Self.baseTypingAttributes(
                        for: self.currentColorScheme)

                    // Apply consistent formatting to any new text that might have been inserted
                    // without proper attributes (e.g., from Writing Tools)
                    let selectedRange = textView.selectedRange
                    if selectedRange.length == 0 && selectedRange.location > 0 {
                        // Check if the character before cursor has proper font attributes
                        let beforeRange = NSRange(location: selectedRange.location - 1, length: 1)
                        if beforeRange.location >= 0,
                            beforeRange.location + beforeRange.length
                                <= textView.attributedText.length
                        {
                            let attributes = textView.attributedText.attributes(
                                at: beforeRange.location, effectiveRange: nil)
                            let currentFont = attributes[.font] as? UIFont
                            let expectedFont =
                                Self.baseTypingAttributes(for: self.currentColorScheme)[.font]
                                as? UIFont

                            // If font doesn't match, apply correct attributes to recent text
                            if currentFont?.fontName != expectedFont?.fontName
                                || currentFont?.pointSize != expectedFont?.pointSize
                            {
                                let mutableText = NSMutableAttributedString(
                                    attributedString: textView.attributedText)
                                mutableText.addAttributes(
                                    Self.baseTypingAttributes(for: self.currentColorScheme),
                                    range: beforeRange
                                )
                                textView.attributedText = mutableText
                            }
                        }
                    }
                }

                syncText()

                // Tell the layout system that the size has changed
                textView.invalidateIntrinsicContentSize()
            }

            // Selection change handling
            func textViewDidChangeSelection(_ textView: UITextView) {
                // Ensure layout stability when selection changes to prevent attachment shifting
                if let textView = self.textView, let textContainer = textView.textContainer {
                    textView.layoutManager?.ensureLayout(for: textContainer)
                }
                
                // Post notification about selection change for floating toolbar
                let selectedRange = textView.selectedRange
                
                // Only show floating toolbar if there's actual text selected (not just cursor)
                if selectedRange.length > 0 {
                    // Calculate selection rectangle in text view's local coordinate space (same as CommandMenu)
                    if let layoutManager = textView.layoutManager,
                       let textContainer = textView.textContainer {
                        
                        // Get the glyph range for the selection
                        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
                        
                        // Get the bounding rect for the selection in the text container
                        let selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                        
                        // Get scroll view's content offset to adjust for scroll position
                        let contentOffset = textView.contentOffset
                        
                        // Convert selection rect to visible coordinates
                        // selectionRect is in text container space, adjust for inset and scroll
                        let selectionX = selectionRect.origin.x + textView.textContainerInset.left
                        let selectionYInContainer = selectionRect.origin.y + textView.textContainerInset.top
                        
                        // Adjust Y position relative to content offset (accounts for scroll)
                        let selectionY = selectionYInContainer - contentOffset.y
                        let selectionWidth = selectionRect.width
                        let selectionHeight = selectionRect.height

                        // Post notification with selection info - let the view calculate toolbar position
                        let info: [String: Any] = [
                            "hasSelection": true,
                            "selectionX": selectionX,
                            "selectionY": selectionY,
                            "selectionWidth": selectionWidth,
                            "selectionHeight": selectionHeight,
                            "visibleWidth": visibleRect.width,
                            "visibleHeight": visibleRect.height
                        ]
                        NotificationCenter.default.post(
                            name: .textSelectionChanged,
                            object: nil,
                            userInfo: info
                        )
                    }
                } else {
                    // No selection - hide floating toolbar
                    let info: [String: Any] = ["hasSelection": false]
                    NotificationCenter.default.post(
                        name: .textSelectionChanged,
                        object: nil,
                        userInfo: info
                    )
                }
            }

            func textView(
                _ textView: UITextView, shouldChangeTextIn range: NSRange,
                replacementText text: String
            ) -> Bool {
                // Check for "/" to trigger command menu
                if text == "/" {
                    // Show command menu at cursor position
                    showCommandMenuAtCursor(textView: textView, insertLocation: range.location)
                    return true  // Allow the "/" to be typed
                }

                // Check for Enter key in todo paragraph
                if text == "\n", isInTodoParagraph(range: range) {
                    insertTodo()
                    return false
                }
                return true
            }

            // MARK: - Command Menu Handling

            /// Shows the command menu at the current cursor position
            /// Positions menu close to cursor with viewport bounds awareness
            private func showCommandMenuAtCursor(textView: UITextView, insertLocation: Int) {
                // Get the rect for the cursor position to place the menu
                guard let layoutManager = textView.layoutManager,
                    let textContainer = textView.textContainer
                else { return }

                // Calculate the glyph range for the insertion point
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: insertLocation)
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

                // Convert to text view's coordinate space
                let cursorX = glyphRect.origin.x + textView.textContainerInset.left
                let cursorY = glyphRect.origin.y + textView.textContainerInset.top
                let cursorHeight = glyphRect.height

                // Menu dimensions
                let menuGap: CGFloat = 4
                let safetyMargin: CGFloat = 20
                let menuHeight = TodoRichTextEditor.commandMenuTotalHeight
                let menuWidth = TodoRichTextEditor.commandMenuTotalWidth

                // For UITextView, get the visible rect relative to content offset
                // UITextView doesn't have visibleRect, so we use bounds
                let visibleRect = textView.bounds

                // Check if there's enough space below the cursor in the visible area
                let cursorBottomY = cursorY + cursorHeight
                let spaceBelow = visibleRect.maxY - cursorBottomY
                let shouldShowAbove = spaceBelow < (menuHeight + menuGap + safetyMargin)

                // Position menu above or below cursor depending on available space
                var xPosition = cursorX
                var yPosition: CGFloat
                if shouldShowAbove {
                    // Position above cursor
                    yPosition = cursorY - menuHeight - menuGap
                } else {
                    // Position below cursor (default)
                    yPosition = cursorY + cursorHeight + menuGap
                }

                // Clamp X within visible bounds to avoid clipping
                let minX = visibleRect.minX + safetyMargin
                let maxX = visibleRect.maxX - menuWidth - safetyMargin
                if minX <= maxX {
                    xPosition = min(max(xPosition, minX), maxX)
                } else {
                    xPosition = max(
                        visibleRect.minX + menuGap,
                        visibleRect.maxX - menuWidth - menuGap
                    )
                }

                // Clamp Y to keep menu fully visible
                let minY = visibleRect.minY + safetyMargin
                let maxY = visibleRect.maxY - menuHeight - safetyMargin
                if minY <= maxY {
                    yPosition = min(max(yPosition, minY), maxY)
                } else {
                    yPosition = max(
                        visibleRect.minY + menuGap,
                        visibleRect.maxY - menuHeight - menuGap
                    )
                }

                let menuPosition = CGPoint(x: xPosition, y: yPosition)

                // Only need extra space when menu shows below cursor AND there's not enough space
                let needsExtraSpace = !shouldShowAbove && spaceBelow < (menuHeight + menuGap + safetyMargin)

                print("🔴 POSTING ShowCommandMenu notification - position: \(menuPosition), slashLocation: \(insertLocation), needsSpace: \(needsExtraSpace)")

                // Post notification to show menu
                NotificationCenter.default.post(
                    name: .showCommandMenu,
                    object: [
                        "position": menuPosition,
                        "slashLocation": insertLocation,
                        "needsSpace": needsExtraSpace
                    ]
                )
            }

            /// Handles command menu tool application
            private func handleCommandMenuToolApplication(_ notification: Notification) {
                guard let info = notification.object as? [String: Any],
                    let tool = info["tool"] as? EditTool,
                    let slashLocation = info["slashLocation"] as? Int,
                    let textView = textView,
                    let textStorage = textView.textStorage
                else { return }

                // Remove the "/" character that triggered the menu
                if slashLocation >= 0 && slashLocation < textStorage.length {
                    let slashRange = NSRange(location: slashLocation, length: 1)
                    textStorage.replaceCharacters(in: slashRange, with: "")
                }

                // Apply the selected tool
                formatter.applyFormatting(to: textView, tool: tool)

                // Sync the text back
                syncText()
            }

            // MARK: - Todo Handling

            private func insertTodo() {
                guard let textView = textView else { return }
                let attachment = TodoCheckboxAttachment(isChecked: false)
                attachment.bounds = CGRect(
                    x: 0, y: Self.checkboxAttachmentYOffset, width: Self.checkboxIconSize,
                    height: Self.checkboxIconSize)
                attachment.image = image(isChecked: false)

                let attributed = NSMutableAttributedString(attachment: attachment)
                attributed.addAttribute(
                    .baselineOffset, value: Self.checkboxBaselineOffset,
                    range: NSRange(location: 0, length: attributed.length))
                // Add comfortable spacing between checkbox and text (2 spaces)
                let space = NSAttributedString(
                    string: "  ", attributes: Self.baseTypingAttributes(for: currentColorScheme))
                let newline = NSAttributedString(
                    string: "\n", attributes: Self.baseTypingAttributes(for: currentColorScheme))

                let composed = NSMutableAttributedString()
                if textView.selectedRange.location != 0 {
                    composed.append(newline)
                }
                composed.append(attributed)
                composed.append(space)

                replaceSelection(with: composed)
                syncText()
            }

            private func insertWebClip(url: String) {
                guard let textView = textView else { return }
                // Add extra line break after web clip to prevent overlapping with content below
                let formatted = NSAttributedString(
                    string:
                        "\n[[webclip|||\(url.trimmingCharacters(in: .whitespacesAndNewlines))]]\n\n",
                    attributes: Self.baseTypingAttributes(for: currentColorScheme))
                replaceSelection(with: formatted)
                syncText()
            }

            private func insertVoiceTranscript(transcript: String) {
                guard let textView = textView else { return }
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                // Add proper spacing and formatting
                let formatted = NSAttributedString(
                    string: trimmed + " ",
                    attributes: Self.baseTypingAttributes(for: currentColorScheme))
                replaceSelection(with: formatted)
                syncText()
            }
            
            private func insertImage(filename: String) {
                NSLog("📝 insertImage: Called with filename: %@", filename)
                guard let textView = textView else {
                    NSLog("📝 insertImage: textView is nil")
                    return
                }

                let currentRange = textView.selectedRange
                let storageString = textView.attributedText?.string ?? ""
                let nsString = storageString as NSString
                let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)

                let composed = NSMutableAttributedString()

                if needsLeadingSpace(before: currentRange, in: nsString) {
                    let leadingSpace = NSAttributedString(string: " ", attributes: baseAttributes)
                    composed.append(leadingSpace)
                }

                NSLog("📝 insertImage: Creating inline image tag attachment")
                let attachment = makeImageAttachment(filename: filename)
                composed.append(attachment)

                if needsTrailingSpace(after: currentRange, in: nsString) {
                    let trailingSpace = NSAttributedString(string: " ", attributes: baseAttributes)
                    composed.append(trailingSpace)
                }

                replaceSelection(with: composed)
                syncText()
                NSLog("📝 insertImage: Completed")
            }

            private func makeFileAttachment(metadata: FileAttachmentMetadata)
                -> NSMutableAttributedString
            {
                func fallbackAttributedString() -> NSMutableAttributedString {
                    return NSMutableAttributedString(
                        string: "[File: \(metadata.displayLabel)]"
                    )
                }

                let tagView = FileAttachmentTagView(label: metadata.displayLabel)
                    .environment(\.colorScheme, currentColorScheme)
                let renderer = ImageRenderer(content: tagView)
                renderer.scale = UIScreen.main.scale
                renderer.isOpaque = false

                guard let uiImage = renderer.uiImage else {
                    NSLog("📄 makeFileAttachment: FAILED to render tag UIImage")
                    return fallbackAttributedString()
                }

                let attachment = NoteFileAttachment(
                    storedFilename: metadata.storedFilename,
                    originalFilename: metadata.originalFilename,
                    typeIdentifier: metadata.typeIdentifier,
                    displayLabel: metadata.displayLabel
                )
                attachment.image = uiImage
                attachment.bounds = CGRect(
                    x: 0,
                    y: Self.imageTagVerticalOffset(for: uiImage.size.height),
                    width: uiImage.size.width,
                    height: uiImage.size.height
                )

                let attributed = NSMutableAttributedString(attachment: attachment)
                let attachmentRange = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(
                    .fileStoredFilename,
                    value: metadata.storedFilename,
                    range: attachmentRange
                )
                attributed.addAttribute(
                    .fileOriginalFilename,
                    value: metadata.originalFilename,
                    range: attachmentRange
                )
                attributed.addAttribute(
                    .fileTypeIdentifier,
                    value: metadata.typeIdentifier,
                    range: attachmentRange
                )
                attributed.addAttribute(
                    .fileDisplayLabel,
                    value: metadata.displayLabel,
                    range: attachmentRange
                )

                return attributed
            }

            private func needsLeadingSpace(before range: NSRange, in text: NSString) -> Bool {
                guard range.location > 0 else { return false }
                let previousCharacter = text.character(at: range.location - 1)
                guard let scalar = UnicodeScalar(previousCharacter) else { return false }
                return !CharacterSet.whitespacesAndNewlines.contains(scalar)
            }

            private func needsTrailingSpace(after range: NSRange, in text: NSString) -> Bool {
                let endIndex = range.location + range.length
                if endIndex >= text.length {
                    return true
                }
                let nextCharacter = text.character(at: endIndex)
                guard let scalar = UnicodeScalar(nextCharacter) else { return false }
                return !CharacterSet.whitespacesAndNewlines.contains(scalar)
            }

            private func replaceSelection(with attributed: NSAttributedString) {
                guard let textView = textView else { return }
                let storageLength = textView.textStorage?.length ?? textView.attributedText?.length ?? 0
                var range = textView.selectedRange

                if range.location == NSNotFound {
                    range = NSRange(location: storageLength, length: 0)
                    textView.selectedRange = range
                } else {
                    if range.location > storageLength {
                        range.location = storageLength
                        range.length = 0
                        textView.selectedRange = range
                    } else if range.location + range.length > storageLength {
                        range.length = max(0, storageLength - range.location)
                        textView.selectedRange = range
                    }
                }

                isUpdating = true
                let mutable = NSMutableAttributedString(
                    attributedString: textView.attributedText ?? NSAttributedString())
                mutable.replaceCharacters(in: range, with: attributed)
                textView.attributedText = mutable
                let cursor = NSRange(location: range.location + attributed.length, length: 0)
                textView.selectedRange = cursor
                isUpdating = false
            }

            private func syncText() {
                guard let textView = textView else { return }
                isUpdating = true
                applyParagraphStyling()
                lastSerialized = serialize()
                textBinding.wrappedValue = lastSerialized

                // Always ensure typing attributes are correct after sync
                textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                isUpdating = false
            }

            /// Fixes any text that has inconsistent font formatting (e.g., from Writing Tools)
            private func fixInconsistentFonts() {
                guard let textView = textView else { return }

                let expectedAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                guard let expectedFont = expectedAttributes[.font] as? UIFont,
                    let expectedColor = expectedAttributes[.foregroundColor] as? UIColor
                else { return }

                let mutableText = NSMutableAttributedString(
                    attributedString: textView.attributedText)
                mutableText.enumerateAttributes(
                    in: NSRange(location: 0, length: mutableText.length)
                ) { attributes, range, _ in
                    var needsFixing = false
                    var fixedAttributes: [NSAttributedString.Key: Any] = attributes

                    // Check font
                    if let currentFont = attributes[.font] as? UIFont {
                        if currentFont.fontName != expectedFont.fontName
                            || currentFont.pointSize != expectedFont.pointSize
                        {
                            fixedAttributes[.font] = expectedFont
                            needsFixing = true
                        }
                    } else {
                        fixedAttributes[.font] = expectedFont
                        needsFixing = true
                    }

                    // Check text color
                    if let currentColor = attributes[.foregroundColor] as? UIColor {
                        if !currentColor.isEqual(expectedColor) {
                            fixedAttributes[.foregroundColor] = expectedColor
                            needsFixing = true
                        }
                    } else {
                        fixedAttributes[.foregroundColor] = expectedColor
                        needsFixing = true
                    }

                    if needsFixing {
                        mutableText.setAttributes(fixedAttributes, range: range)
                    }
                }

                textView.attributedText = mutableText
            }

            private func applyParagraphStyling() {
                guard let textView = textView else { return }
                let mutable = NSMutableAttributedString(
                    attributedString: textView.attributedText ?? NSAttributedString())
                let fullRange = NSRange(location: 0, length: mutable.length)
                mutable.removeAttribute(.paragraphStyle, range: fullRange)
                mutable.removeAttribute(.baselineOffset, range: fullRange)

                (mutable.string as NSString).enumerateSubstrings(
                    in: fullRange, options: .byParagraphs
                ) { _, range, _, _ in
                    let attributes = self.paragraphAttributes(for: mutable, at: range)
                    mutable.addAttribute(.paragraphStyle, value: attributes.style, range: range)
                    mutable.addAttribute(.baselineOffset, value: attributes.baseline, range: range)

                    if attributes.isTodo {
                        mutable.enumerateAttribute(.attachment, in: range, options: []) {
                            value, attachmentRange, _ in
                            guard let attachment = value as? TodoCheckboxAttachment else { return }
                            attachment.bounds = CGRect(
                                x: 0, y: Self.checkboxAttachmentYOffset,
                                width: Self.checkboxIconSize, height: Self.checkboxIconSize)
                            mutable.addAttribute(
                                .baselineOffset, value: Self.checkboxBaselineOffset,
                                range: attachmentRange)
                        }
                    }
                }

                let selection = textView.selectedRange
                textView.attributedText = mutable
                textView.selectedRange = selection
            }

            private func paragraphAttributes(for attributed: NSAttributedString, at range: NSRange)
                -> (style: NSParagraphStyle, baseline: CGFloat, isTodo: Bool)
            {
                var isTodo = false
                var isWebClip = false

                attributed.enumerateAttribute(
                    .attachment,
                    in: NSRange(location: range.location, length: min(1, range.length)), options: []
                ) { value, _, _ in
                    if let attachment = value as? TodoCheckboxAttachment {
                        isTodo = true
                        attachment.image = image(isChecked: attachment.isChecked)
                    }
                    // Check if it's a web clip attachment
                    else if value is NSTextAttachment {
                        if attributed.attribute(
                            .webClipTitle, at: range.location, effectiveRange: nil) != nil
                        {
                            isWebClip = true
                        }
                    }
                }

                // Apply appropriate style based on content type
                let style: NSParagraphStyle
                if isWebClip {
                    style = Self.webClipParagraphStyle()
                } else {
                    style = Self.paragraphStyle(isTodo: isTodo)
                }

                let baseline =
                    (isTodo || isWebClip) ? Self.todoBaselineOffset : Self.baseBaselineOffset
                return (style, baseline, isTodo)
            }

            private func isInTodoParagraph(range: NSRange) -> Bool {
                guard let textView = textView else { return false }
                let location = max(0, min(range.location, textView.attributedText.length))
                let paragraphRange = (textView.text as NSString).paragraphRange(
                    for: NSRange(location: location, length: 0))
                var result = false
                textView.attributedText.enumerateAttribute(
                    .attachment,
                    in: NSRange(
                        location: paragraphRange.location, length: min(1, paragraphRange.length)),
                    options: []
                ) { value, _, _ in
                    if let attachment = value as? TodoCheckboxAttachment {
                        result = true
                        attachment.image = image(isChecked: attachment.isChecked)
                    }
                }
                return result
            }

            private func serialize() -> String {
                guard let textView = textView else { return "" }
                let result = NSMutableString()
                let fullRange = NSRange(location: 0, length: textView.attributedText.length)
                textView.attributedText.enumerateAttributes(in: fullRange, options: []) {
                    attributes, range, _ in
                    if let attachment = attributes[.attachment] as? TodoCheckboxAttachment {
                        result.append(attachment.isChecked ? "[x]" : "[ ]")
                    } else if let storedFilename = attributes[.fileStoredFilename] as? String {
                        let typeIdentifierRaw = (attributes[.fileTypeIdentifier] as? String) ?? "public.data"
                        let originalNameRaw = (attributes[.fileOriginalFilename] as? String) ?? storedFilename
                        let typeIdentifier = AttachmentMarkup.sanitizedComponent(typeIdentifierRaw)
                        let originalName = AttachmentMarkup.sanitizedComponent(originalNameRaw)
                        result.append("[[file|\(typeIdentifier)|\(storedFilename)|\(originalName)]]")
                    } else if let attachment = attributes[.attachment] as? NSTextAttachment {
                        // Image attachment serialization with fallback
                        // Primary: Use the robust custom attribute
                        if let filename = attributes[.imageFilename] as? String {
                            result.append("[[image|||\(filename)]]")
                        }
                        // Secondary: Try NoteImageAttachment which stores filename directly
                        else if let noteAttachment = attachment as? NoteImageAttachment {
                            result.append("[[image|||\(noteAttachment.storedFilename)]]")
                            NSLog("Serialization: Recovered filename %@ from NoteImageAttachment", noteAttachment.storedFilename)
                        }
                        // Tertiary: Fallback to fileWrapper
                        else if let fileWrapper = attachment.fileWrapper,
                                let filename = fileWrapper.preferredFilename ?? fileWrapper.filename,
                                !filename.isEmpty,
                                filename.hasSuffix(".jpg")
                        {
                            result.append("[[image|||\(filename)]]")
                            NSLog("Serialization: Recovered filename %@ from fileWrapper", filename)
                        }
                        // If all fail, data is lost - log this critical error
                        else {
                            result.append(
                                (textView.attributedText.string as NSString).substring(with: range))
                            NSLog("⚠️ Serialization CRITICAL: Could not find filename for image attachment. Data may be lost.")
                        }
                    } else {
                        result.append(
                            (textView.attributedText.string as NSString).substring(with: range))
                    }
                }
                return result as String
            }

            private func deserialize(_ text: String) -> NSAttributedString {
                let result = NSMutableAttributedString()
                var index = text.startIndex
                while index < text.endIndex {
                    if text[index...].hasPrefix("[x]") || text[index...].hasPrefix("[ ]") {
                        let isChecked = text[index...].hasPrefix("[x]")
                        let attachment = TodoCheckboxAttachment(isChecked: isChecked)
                        attachment.bounds = CGRect(
                            x: 0, y: Self.checkboxAttachmentYOffset, width: Self.checkboxIconSize,
                            height: Self.checkboxIconSize)
                        attachment.image = image(isChecked: isChecked)
                        let att = NSMutableAttributedString(attachment: attachment)
                        att.addAttribute(
                            .baselineOffset, value: Self.checkboxBaselineOffset,
                            range: NSRange(location: 0, length: att.length))
                        result.append(att)
                        index = text.index(index, offsetBy: 3)
                        continue
                    } else if text[index...].hasPrefix(AttachmentMarkup.fileMarkupPrefix) {
                        if let endIndex = text[index...].range(of: "]]" )?.upperBound {
                            let fileText = String(text[index..<endIndex])
                            if let regex = AttachmentMarkup.fileRegex,
                               let match = regex.firstMatch(
                                   in: fileText,
                                   options: [],
                                   range: NSRange(location: 0, length: fileText.utf16.count)
                               )
                            {
                                let rawType = Self.string(from: match, at: 1, in: fileText)
                                let storedFilename = Self.string(from: match, at: 2, in: fileText)
                                let rawOriginal = Self.string(from: match, at: 3, in: fileText)

                                let typeIdentifier = rawType.isEmpty ? "public.data" : rawType
                                let originalName = rawOriginal.isEmpty ? storedFilename : rawOriginal

                                let storedFile = FileAttachmentStorageManager.StoredFile(
                                    storedFilename: storedFilename,
                                    originalFilename: originalName,
                                    typeIdentifier: typeIdentifier
                                )

                                let metadata = FileAttachmentMetadata(
                                    storedFilename: storedFile.storedFilename,
                                    originalFilename: storedFile.originalFilename,
                                    typeIdentifier: storedFile.typeIdentifier,
                                    displayLabel: AttachmentMarkup.displayLabel(for: storedFile)
                                )

                                let baseAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                                if result.length > 0,
                                   let lastScalar = result.string.unicodeScalars.last,
                                   !CharacterSet.whitespacesAndNewlines.contains(lastScalar)
                                {
                                    let leadingSpace = NSAttributedString(
                                        string: " ", attributes: baseAttributes)
                                    result.append(leadingSpace)
                                }

                                let attachment = makeFileAttachment(metadata: metadata)
                                result.append(attachment)

                                let shouldAddTrailingSpace: Bool
                                if endIndex < text.endIndex {
                                    let nextCharacter = text[endIndex]
                                    shouldAddTrailingSpace = !nextCharacter.isWhitespace
                                } else {
                                    shouldAddTrailingSpace = true
                                }

                                if shouldAddTrailingSpace {
                                    let trailingSpace = NSAttributedString(
                                        string: " ", attributes: baseAttributes)
                                    result.append(trailingSpace)
                                }

                                index = endIndex
                                continue
                            }
                        }
                    } else if text[index...].hasPrefix(AttachmentMarkup.imageMarkupPrefix) {
                        // Image attachment deserialization
                        NSLog("📝 deserialize: Found image markup prefix")
                        if let endIndex = text[index...].range(of: "]]")?.upperBound {
                            let imageText = String(text[index..<endIndex])
                            NSLog("📝 deserialize: Markup text: %@", imageText)
                            if let regex = AttachmentMarkup.imageRegex,
                                let match = regex.firstMatch(
                                    in: imageText,
                                    options: [],
                                    range: NSRange(location: 0, length: imageText.utf16.count)
                                )
                            {
                                let filename = Self.string(from: match, at: 1, in: imageText)
                                NSLog("📝 deserialize: Extracted filename: %@", filename)
                                
                                let baseAttributes = Self.baseTypingAttributes(
                                    for: currentColorScheme)
                                if result.length > 0,
                                    let lastScalar = result.string.unicodeScalars.last,
                                    !CharacterSet.whitespacesAndNewlines.contains(lastScalar)
                                {
                                    let leadingSpace = NSAttributedString(
                                        string: " ", attributes: baseAttributes)
                                    result.append(leadingSpace)
                                }

                                let attachment = makeImageAttachment(filename: filename)
                                result.append(attachment)

                                let shouldAddTrailingSpace: Bool
                                if endIndex < text.endIndex {
                                    let nextCharacter = text[endIndex]
                                    shouldAddTrailingSpace = !nextCharacter.isWhitespace
                                } else {
                                    shouldAddTrailingSpace = true
                                }

                                if shouldAddTrailingSpace {
                                    let trailingSpace = NSAttributedString(
                                        string: " ", attributes: baseAttributes)
                                    result.append(trailingSpace)
                                }

                                index = endIndex
                                continue
                            }
                        }
                    }
                    result.append(
                        NSAttributedString(
                            string: String(text[index]),
                            attributes: Self.baseTypingAttributes(for: currentColorScheme)))
                    index = text.index(after: index)
                }
                return result
            }

            private func image(isChecked: Bool) -> UIImage? {
                // Detect dark mode
                let isDark = textView?.traitCollection.userInterfaceStyle == .dark

                // Use SF Symbols for perfect alignment and consistency
                let symbolName = isChecked ? "checkmark.circle.fill" : "circle"
                let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
                let image = UIImage(systemName: symbolName, withConfiguration: config)

                // Apply appropriate color based on state and color scheme
                if isChecked {
                    // Checked state: vibrant blue background with white checkmark
                    // Using bright saturated blue (0, 122, 255) - iOS system blue at 100% vibrance
                    return image?.withTintColor(
                        UIColor(red: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1.0),
                        renderingMode: .alwaysOriginal
                    )
                } else {
                    // Unchecked state: adapt to color scheme
                    let uncheckedColor: UIColor
                    if isDark {
                        // White/light gray circle in dark mode for visibility
                        uncheckedColor = UIColor(white: 0.85, alpha: 1.0)
                    } else {
                        // Dark gray circle in light mode
                        uncheckedColor = UIColor(white: 0.3, alpha: 1.0)
                    }
                    return image?.withTintColor(uncheckedColor, renderingMode: .alwaysOriginal)
                }
            }

            @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
                guard let textView = textView else { return }
                let location = gesture.location(in: textView)
                let manager = textView.layoutManager
                var point = location
                point.x -= textView.textContainerInset.left
                point.y -= textView.textContainerInset.top

                let index = manager.characterIndex(
                    for: point, in: textView.textContainer,
                    fractionOfDistanceBetweenInsertionPoints: nil)
                if index >= textView.attributedText.length { return }

                let glyphRange = NSRange(location: index, length: 1)
                let glyphRect = manager.boundingRect(
                    forGlyphRange: glyphRange, in: textView.textContainer)
                var tapRect = glyphRect
                tapRect.origin.x += textView.textContainerInset.left
                tapRect.origin.y += textView.textContainerInset.top
                tapRect.size.width = max(24, tapRect.size.width)
                tapRect.size.height = max(24, tapRect.size.height)

                if !tapRect.contains(location) { return }

                let attributes = textView.attributedText.attributes(at: index, effectiveRange: nil)
                if attributes[.webClipTitle] != nil {
                    // Fixed dimensions for web clip tap detection
                    let attachmentRect = CGRect(
                        x: tapRect.origin.x,
                        y: tapRect.maxY - 60,
                        width: 250,
                        height: 60
                    )
                    let closeRect = CGRect(
                        x: attachmentRect.maxX - 26,
                        y: attachmentRect.maxY - 26,
                        width: 20,
                        height: 20
                    )

                    if closeRect.contains(location), let linkValue = attributes[.link] as? String {
                        deleteWebClipAttachment(url: linkValue)
                        return
                    }

                    if let linkValue = attributes[.link] as? String,
                        let url = URL(string: linkValue)
                    {
                        UIApplication.shared.open(url)
                        return
                    }
                }

                if let attachment = attributes[.attachment] as? TodoCheckboxAttachment {
                    attachment.isChecked.toggle()
                    attachment.image = image(isChecked: attachment.isChecked)
                    textView.setNeedsDisplay()
                    syncText()
                }
            }

            static func baseTypingAttributes(for colorScheme: ColorScheme? = nil)
                -> [NSAttributedString.Key: Any]
            {
                let textColor: UIColor
                if let scheme = colorScheme {
                    // Use the actual PrimaryTextColor values from the asset catalog
                    if scheme == .dark {
                        textColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)  // White for dark mode
                    } else {
                        textColor = UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)  // Dark gray for light mode
                    }
                } else {
                    textColor = UIColor.label
                }

                return [
                    .font: textFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle(isTodo: false),
                    .underlineStyle: 0,
                        // .baselineOffset: baseBaselineOffset,
                ]
            }

            private static func paragraphStyle(isTodo: Bool) -> NSParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.2
                let minimum = isTodo ? todoLineHeight : baseLineHeight
                style.minimumLineHeight = minimum
                style.maximumLineHeight = minimum + 4
                style.paragraphSpacing = isTodo ? 10 : 8
                style.firstLineHeadIndent = 0
                style.headIndent = isTodo ? 28 : 0
                return style
            }

            // Paragraph style for web clip attachments with extra spacing to prevent overlap
            private static func webClipParagraphStyle() -> NSParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.0
                // NO minimum/maximum line height - let attachment determine its own space
                // This prevents empty clickable space above/below
                style.minimumLineHeight = 0
                style.maximumLineHeight = 0
                // No paragraph spacing - web clips are now inline with horizontal spacing
                style.paragraphSpacing = 0
                style.paragraphSpacingBefore = 0
                return style
            }
            
            private static func imageTagVerticalOffset(for height: CGFloat) -> CGFloat {
                let offset = (textFont.capHeight - height) / 2
                return offset
            }

            private static func baselineOffset(forLineHeight lineHeight: CGFloat, font: UIFont)
                -> CGFloat
            {
                let metrics = font.lineHeight
                let delta = max(0, lineHeight - metrics)
                return delta / 2
            }

            // MARK: - Writing Tools Support (iOS 18+)
            @available(iOS 18.0, *)
            func textViewWritingToolsWillBegin(_ textView: UITextView) {
                // Store text before Writing Tools starts
                textBeforeWritingTools = textView.text ?? ""
            }

            @available(iOS 18.0, *)
            func textViewWritingToolsDidEnd(_ textView: UITextView) {
                // Writing Tools finished - textViewDidChange will handle summary detection
            }
        }
    }

    private final class TodoCheckboxAttachment: NSTextAttachment {
        var isChecked: Bool

        init(isChecked: Bool) {
            self.isChecked = isChecked
            super.init(data: nil, ofType: nil)
        }

        required init?(coder: NSCoder) {
            self.isChecked = false
            super.init(coder: coder)
        }
    }
#endif

// MARK: - Notifications

extension Notification.Name {
    static let insertTodoInEditor = Notification.Name("insertTodoInEditor")
    static let insertWebClipInEditor = Notification.Name("insertWebClipInEditor")
    static let insertVoiceTranscriptInEditor = Notification.Name("insertVoiceTranscriptInEditor")
    static let insertImageInEditor = Notification.Name("insertImageInEditor")
    static let deleteWebClipAttachment = Notification.Name("deleteWebClipAttachment")
    static let applyEditTool = Notification.Name("applyEditTool")

    // Command menu notifications
    static let showCommandMenu = Notification.Name("ShowCommandMenu")
    static let hideCommandMenu = Notification.Name("HideCommandMenu")
    static let commandMenuNavigateUp = Notification.Name("CommandMenuNavigateUp")
    static let commandMenuNavigateDown = Notification.Name("CommandMenuNavigateDown")
    static let commandMenuSelect = Notification.Name("CommandMenuSelect")
    static let applyCommandMenuTool = Notification.Name("ApplyCommandMenuTool")
}
