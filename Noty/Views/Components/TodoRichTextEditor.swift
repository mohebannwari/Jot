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
#else
    import UIKit
#endif

extension NSAttributedString.Key {
    fileprivate static let webClipTitle = NSAttributedString.Key("WebClipTitle")
    fileprivate static let webClipDescription = NSAttributedString.Key("WebClipDescription")
    fileprivate static let webClipDomain = NSAttributedString.Key("WebClipDomain")
    fileprivate static let imageFilename = NSAttributedString.Key("ImageFilename")
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
            // Command menu overlay (triggered by "/" character)
            if showCommandMenu {
                CommandMenu(
                    tools: commandMenuTools,
                    selectedIndex: $commandMenuSelectedIndex,
                    onSelect: { tool in handleCommandMenuSelection(tool) },
                    maxHeight: 280
                )
                .offset(x: commandMenuPosition.x, y: commandMenuPosition.y)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                    )
                )
                .zIndex(1000)
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
            
            // Image attachment markup patterns
            private static let imageMarkupPrefix = "[[image|"
            private static let imagePattern = #"\[\[image\|\|\|([^\]]+)\]\]"#
            private static let imageRegex: NSRegularExpression? = try? NSRegularExpression(
                pattern: imagePattern,
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

                    // Position at baseline - no negative offset needed
                    attachment.bounds = CGRect(origin: .zero, size: displaySize)
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

                    // Position at baseline - no negative offset needed
                    attachment.bounds = CGRect(origin: .zero, size: displaySize)
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
            
            /// Create an image attachment from a filename
            private func makeImageAttachment(filename: String) -> NSMutableAttributedString {
                NSLog("🖼️ makeImageAttachment: START with filename: %@", filename)
                
                // Get the image URL from storage
                guard let imageURL = ImageStorageManager.shared.getImageURL(for: filename) else {
                    NSLog("🖼️ makeImageAttachment: FAILED to get URL for image: %@", filename)
                    let attributed = NSMutableAttributedString(string: "[Image: \(filename)]")
                    return attributed
                }
                
                NSLog("🖼️ makeImageAttachment: Got imageURL: %@", imageURL.path)
                
        #if os(macOS)
                    // Load the image directly
                    guard let sourceImage = NSImage(contentsOf: imageURL) else {
                        NSLog("makeImageAttachment: Failed to load NSImage from %@", imageURL.path)
                        let attributed = NSMutableAttributedString(string: "[Image: \(filename)]")
                        return attributed
                    }
                    
                    // Calculate aspect-ratio-aware display size with 8px continuous corner radius
                    let imageSize = sourceImage.size
                    let maxDimension: CGFloat = 120
                    let aspectRatio = imageSize.width / imageSize.height
                    let cornerRadius: CGFloat = 8
                    
                    // Determine display size based on aspect ratio
                    let displaySize: CGSize
                    if aspectRatio > 1 {
                        // Horizontal image: constrain height to 120, adjust width proportionally
                        displaySize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
                    } else if aspectRatio < 1 {
                        // Vertical image: constrain width to 120, adjust height proportionally
                        displaySize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
                    } else {
                        // Square image: 120x120
                        displaySize = CGSize(width: maxDimension, height: maxDimension)
                    }
                    
                    // Create resized image with rounded corners
                    let resizedImage = NSImage(size: displaySize)
                    resizedImage.lockFocus()
                    
                    // Enable antialiasing for smooth continuous corners
                    NSGraphicsContext.current?.shouldAntialias = true
                    NSGraphicsContext.current?.imageInterpolation = .high
                    
                    // Create a rounded rect path for clipping with continuous curve
                    let bounds = NSRect(origin: .zero, size: displaySize)
                    let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
                    path.addClip()
                    
                    // Draw the image within the clipped path
                    sourceImage.draw(
                        in: bounds,
                        from: NSRect(origin: .zero, size: imageSize),
                        operation: .copy,
                        fraction: 1.0
                    )
                    resizedImage.unlockFocus()
                    
                    // Create attachment using the image data approach which works reliably on macOS
                    let attachment = NoteImageAttachment(filename: filename)
                    // Store the image as file wrapper data
                    if let tiffData = resizedImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        let fileWrapper = FileWrapper(regularFileWithContents: pngData)
                        fileWrapper.filename = filename
                        fileWrapper.preferredFilename = filename
                        attachment.fileWrapper = fileWrapper
                    }
                    
                    // Also set the image property (for immediate display)
                    attachment.image = resizedImage
                    // Set bounds at origin with full display size
                    // The imageParagraphStyle will handle spacing and prevent clipping
                    attachment.bounds = CGRect(origin: .zero, size: displaySize)
                    
                    let attributed = NSMutableAttributedString(attachment: attachment)
                    
                    NSLog("makeImageAttachment: Created attachment for %@ with aspect ratio %.2f, display size %@", filename, aspectRatio, NSStringFromSize(displaySize))
                    NSLog("makeImageAttachment: Attachment has image: %@, fileWrapper: %@", attachment.image != nil ? "YES" : "NO", attachment.fileWrapper != nil ? "YES" : "NO")
                    NSLog("makeImageAttachment: Attributed string length: %ld", attributed.length)
        #else
                    // Load the image directly
                    guard let uiImage = UIImage(contentsOfFile: imageURL.path) else {
                        NSLog("makeImageAttachment: Failed to load UIImage from %@", imageURL.path)
                        let attributed = NSMutableAttributedString(string: "[Image: \(filename)]")
                        return attributed
                    }
                    
                    // Calculate aspect-ratio-aware display size with 8px continuous corner radius
                    let imageSize = uiImage.size
                    let maxDimension: CGFloat = 120
                    let aspectRatio = imageSize.width / imageSize.height
                    let cornerRadius: CGFloat = 8
                    
                    // Determine display size based on aspect ratio
                    let displaySize: CGSize
                    if aspectRatio > 1 {
                        // Horizontal image: constrain height to 120, adjust width proportionally
                        displaySize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
                    } else if aspectRatio < 1 {
                        // Vertical image: constrain width to 120, adjust height proportionally
                        displaySize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
                    } else {
                        // Square image: 120x120
                        displaySize = CGSize(width: maxDimension, height: maxDimension)
                    }
                    
                    // Create resized image with continuous rounded corners
                    UIGraphicsBeginImageContextWithOptions(displaySize, false, 1.0)
                    
                    // Use continuous corner radius (iOS 13+) for smooth, squircle-like corners
                    let bounds = CGRect(origin: .zero, size: displaySize)
                    let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
                    path.addClip()
                    
                    // Draw the image within the clipped path
                    uiImage.draw(in: bounds)
                    let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? uiImage
                    UIGraphicsEndImageContext()
                    
                    let attachment = NoteImageAttachment(filename: filename)
                    attachment.image = resizedImage
                    // Set bounds at origin with full display size
                    // The imageParagraphStyle will handle spacing and prevent clipping
                    attachment.bounds = CGRect(origin: .zero, size: displaySize)
                    
                    // Store filename in file wrapper for serialization
                    let fileWrapper = FileWrapper(regularFileWithContents: Data())
                    fileWrapper.preferredFilename = filename
                    attachment.fileWrapper = fileWrapper
                    
                    let attributed = NSMutableAttributedString(attachment: attachment)
                    
                    NSLog("makeImageAttachment: Created attachment for %@ with aspect ratio %.2f, display size %@", filename, aspectRatio, NSStringFromCGSize(displaySize))
                #endif
                
                // Store the filename as a custom attribute (like web clips do)
                // This persists even when NSTextAttachment modifies the fileWrapper
                let attachmentRange = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(.imageFilename, value: filename, range: attachmentRange)
                
                // Apply special paragraph style for images with proper spacing
                attributed.addAttribute(
                    .paragraphStyle, value: Self.imageParagraphStyle(), range: attachmentRange)
                
                return attributed
            }

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
                    guard let transcript = notification.object as? String else {
                        NSLog("📝 Coordinator: No transcript in notification object")
                        return
                    }
                    NSLog("📝 Coordinator: Got transcript: %@", transcript)
                    Task { @MainActor [weak self] in
                        self?.insertVoiceTranscript(transcript: transcript)
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
                        self?.insertImage(filename: filename)
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
                guard attributes[.webClipTitle] != nil,
                    let attachment = attributes[.attachment] as? NSTextAttachment
                else { return false }

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

                if let linkValue = attributes[.link] as? String,
                    let url = URL(string: linkValue)
                {
                    NSWorkspace.shared.open(url)
                    return true
                }

                return false
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
                let menuHeight: CGFloat = CommandMenuLayout.idealHeight(for: TodoRichTextEditor.commandMenuActions.count)
                let menuGap: CGFloat = 4
                let safetyMargin: CGFloat = 20

                // Get the visible rect to check against actual viewport, not total text view bounds
                let visibleRect = textView.visibleRect

                // Check if there's enough space below the cursor in the VISIBLE area
                // This is the key: we check against visibleRect.maxY, not bounds.height
                let cursorBottomY = cursorY + cursorHeight
                let spaceBelow = visibleRect.maxY - cursorBottomY
                let shouldShowAbove = spaceBelow < (menuHeight + menuGap + safetyMargin)

                // Position menu above or below cursor depending on available space
                let xPosition = cursorX
                let yPosition: CGFloat
                if shouldShowAbove {
                    // Position above cursor
                    yPosition = max(visibleRect.minY + menuGap, cursorY - menuHeight - menuGap)
                } else {
                    // Position below cursor (default)
                    yPosition = cursorY + cursorHeight + menuGap
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
                
                // Log current state to debug replacement issue
                let currentRange = textView.selectedRange()
                let storageLength = textView.textStorage?.length ?? 0
                NSLog("📝 insertImage: BEFORE - Selected range: %@, storage length: %ld", NSStringFromRange(currentRange), storageLength)
                
                // Ensure cursor is at the end of the document to append, not replace
                if currentRange.location != storageLength || currentRange.length != 0 {
                    NSLog("📝 insertImage: Moving cursor to end of document")
                    let endRange = NSRange(location: storageLength, length: 0)
                    textView.setSelectedRange(endRange)
                }
                
                NSLog("📝 insertImage: Creating image attachment")
                // Create the image attachment directly (like web clips)
                let attachment = makeImageAttachment(filename: filename)
                
                // Check if text storage is empty or contains only whitespace
                // to determine if this is the first element being inserted
                let isEmpty = storageLength == 0 || textView.textStorage?.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
                
                // Create paragraph breaks BEFORE the image block
                // Use base attributes for clean paragraph separation
                let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
                
                let composed = NSMutableAttributedString()
                
                // Add paragraph break before image (double newline if first element)
                if isEmpty {
                    // Extra newline at start to prevent top clipping
                    let spacer = NSAttributedString(string: "\n\n", attributes: baseAttrs)
                    composed.append(spacer)
                } else {
                    // Single newline to create paragraph break
                    let spacer = NSAttributedString(string: "\n", attributes: baseAttrs)
                    composed.append(spacer)
                }
                
                // Append the image attachment (which already has imageParagraphStyle)
                composed.append(attachment)
                
                // Add newline after for paragraph separation
                let newlineAfter = NSAttributedString(string: "\n", attributes: baseAttrs)
                composed.append(newlineAfter)
                
                replaceSelection(with: composed)
                
                // Log what's in the text storage after insertion
                if let textStorage = textView.textStorage {
                    NSLog("📝 insertImage: Text storage length after insert: %ld", textStorage.length)
                    textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
                        if let attachment = value as? NSTextAttachment {
                            NSLog("📝 insertImage: Found attachment in storage at range %@, has image: %@", NSStringFromRange(range), attachment.image != nil ? "YES" : "NO")
                        }
                    }
                }
                
                // Force layout update to ensure attachment displays
                if let layoutManager = textView.layoutManager,
                   let textContainer = textView.textContainer {
                    layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textView.textStorage?.length ?? 0), actualCharacterRange: nil)
                    layoutManager.ensureLayout(for: textContainer)
                }
                
                syncText()
                
                // Log what's in the text storage after syncText
                if let textStorage = textView.textStorage {
                    NSLog("📝 insertImage: Text storage length after syncText: %ld", textStorage.length)
                    textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
                        if let attachment = value as? NSTextAttachment {
                            NSLog("📝 insertImage: Found attachment after syncText at range %@, has image: %@", NSStringFromRange(range), attachment.image != nil ? "YES" : "NO")
                        }
                    }
                }
                
                NSLog("📝 insertImage: Completed")
            }

            private func replaceSelection(with attributed: NSAttributedString) {
                guard let textView = textView else { return }
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
                    var isImageParagraph = false

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
                            // Check if it's an image attachment (has imageFilename attribute)
                            else if textStorage.attribute(
                                .imageFilename, at: substringRange.location, effectiveRange: nil)
                                != nil
                            {
                                isImageParagraph = true
                                stop.pointee = true
                            }
                        }
                    }

                    // Apply appropriate paragraph style based on content type
                    let paragraphStyle: NSParagraphStyle
                    if isImageParagraph {
                        // CRITICAL: Images need special paragraph style with no line height constraints
                        paragraphStyle = Self.imageParagraphStyle()
                    } else if isWebClipParagraph {
                        paragraphStyle = Self.webClipParagraphStyle()
                    } else if isTodoParagraph {
                        paragraphStyle = Self.todoParagraphStyle()
                    } else {
                        paragraphStyle = Self.baseParagraphStyle()
                    }

                    textStorage.addAttribute(
                        .paragraphStyle, value: paragraphStyle, range: substringRange)

                    // Don't adjust baseline for todo, web clip, or image paragraphs
                    if !isTodoParagraph && !isWebClipParagraph && !isImageParagraph {
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
                    } else if text[index...].hasPrefix(Self.imageMarkupPrefix) {
                        // Image attachment deserialization
                        NSLog("📝 deserialize: Found image markup prefix")
                        if let endIndex = text[index...].range(of: "]]")?.upperBound {
                            let imageText = String(text[index..<endIndex])
                            NSLog("📝 deserialize: Markup text: %@", imageText)
                            if let regex = Self.imageRegex,
                                let match = regex.firstMatch(
                                    in: imageText,
                                    options: [],
                                    range: NSRange(location: 0, length: imageText.utf16.count)
                                )
                            {
                                let filename = Self.string(from: match, at: 1, in: imageText)
                                NSLog("📝 deserialize: Extracted filename: %@", filename)
                                
                                // Add newline before image if result is not empty and doesn't end with newline
                // Create image attachment
                let attachment = makeImageAttachment(filename: filename)
                result.append(attachment)
                
                // Add newline after image and a spacer paragraph to guarantee separation
                let newline = NSAttributedString(
                    string: "\n",
                    attributes: Self.baseTypingAttributes(for: currentColorScheme))
                let spacer = NSAttributedString(
                    string: "\u{200B}\n",
                    attributes: Self.baseTypingAttributes(for: currentColorScheme))
                result.append(newline)
                result.append(spacer)
                                
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
            
            static func imageParagraphStyle() -> NSParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.alignment = .left
                // CRITICAL: Set line height multiplier to 1.0 and NO constraints
                // This allows the attachment to determine its own height
                style.lineHeightMultiple = 1.0
                // Set to 0 to remove line height constraints entirely
                style.minimumLineHeight = 0
                style.maximumLineHeight = 0
                // Increase spacing significantly to prevent overlap between images
                style.paragraphSpacing = 16
                style.paragraphSpacingBefore = 16
                // No line spacing - let each image be its own paragraph
                style.lineSpacing = 0
                return style
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
                    guard let transcript = notification.object as? String else {
                        NSLog("📝 Coordinator: No transcript in notification object")
                        return
                    }
                    NSLog("📝 Coordinator: Got transcript: %@", transcript)
                    Task { @MainActor [weak self] in
                        self?.insertVoiceTranscript(transcript: transcript)
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
                let menuHeight: CGFloat = CommandMenuLayout.idealHeight(for: TodoRichTextEditor.commandMenuActions.count)
                let menuGap: CGFloat = 4
                let safetyMargin: CGFloat = 20

                // For UITextView, get the visible rect relative to content offset
                // UITextView doesn't have visibleRect, so we use bounds
                let visibleRect = textView.bounds

                // Check if there's enough space below the cursor in the visible area
                let cursorBottomY = cursorY + cursorHeight
                let spaceBelow = visibleRect.maxY - cursorBottomY
                let shouldShowAbove = spaceBelow < (menuHeight + menuGap + safetyMargin)

                // Position menu above or below cursor depending on available space
                let xPosition = cursorX
                let yPosition: CGFloat
                if shouldShowAbove {
                    // Position above cursor
                    yPosition = max(visibleRect.minY + menuGap, cursorY - menuHeight - menuGap)
                } else {
                    // Position below cursor (default)
                    yPosition = cursorY + cursorHeight + menuGap
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
                
                // Log current state to debug replacement issue
                let currentRange = textView.selectedRange()
                let storageLength = textView.textStorage?.length ?? 0
                NSLog("📝 insertImage: BEFORE - Selected range: %@, storage length: %ld", NSStringFromRange(currentRange), storageLength)
                
                // Ensure cursor is at the end of the document to append, not replace
                if currentRange.location != storageLength || currentRange.length != 0 {
                    NSLog("📝 insertImage: Moving cursor to end of document")
                    let endRange = NSRange(location: storageLength, length: 0)
                    textView.setSelectedRange(endRange)
                }
                
                NSLog("📝 insertImage: Creating image attachment")
                // Create the image attachment directly (like web clips)
                let attachment = makeImageAttachment(filename: filename)
                
                // Add newlines around the attachment for proper spacing
                let newlineBefore = NSAttributedString(
                    string: "\n",
                    attributes: Self.baseTypingAttributes(for: currentColorScheme))
                let newlineAfter = NSAttributedString(
                    string: "\n",
                    attributes: Self.baseTypingAttributes(for: currentColorScheme))
                
                let composed = NSMutableAttributedString()
                composed.append(newlineBefore)
                composed.append(attachment)
                composed.append(newlineAfter)
                
                replaceSelection(with: composed)
                syncText()
                NSLog("📝 insertImage: Completed")
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
                    } else if text[index...].hasPrefix(Self.imageMarkupPrefix) {
                        // Image attachment deserialization
                        NSLog("📝 deserialize: Found image markup prefix")
                        if let endIndex = text[index...].range(of: "]]")?.upperBound {
                            let imageText = String(text[index..<endIndex])
                            NSLog("📝 deserialize: Markup text: %@", imageText)
                            if let regex = Self.imageRegex,
                                let match = regex.firstMatch(
                                    in: imageText,
                                    options: [],
                                    range: NSRange(location: 0, length: imageText.utf16.count)
                                )
                            {
                                let filename = Self.string(from: match, at: 1, in: imageText)
                                NSLog("📝 deserialize: Extracted filename: %@", filename)
                                
                                // Add newline before image if result is not empty and doesn't end with newline
                                if result.length > 0 {
                                    let lastChar = (result.string as NSString).substring(from: result.length - 1)
                                    if lastChar != "\n" {
                                        let newline = NSAttributedString(
                                            string: "\n",
                                            attributes: Self.baseTypingAttributes(for: currentColorScheme))
                                        result.append(newline)
                                    }
                                }
                                
                                // Create image attachment
                                let attachment = makeImageAttachment(filename: filename)
                                result.append(attachment)
                                
                                // Add newline after image
                                let newline = NSAttributedString(
                                    string: "\n",
                                    attributes: Self.baseTypingAttributes(for: currentColorScheme))
                                result.append(newline)
                                
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
            
            private static func imageParagraphStyle() -> NSParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.alignment = .left
                // CRITICAL: Set line height multiplier to 1.0 and NO constraints
                // This allows the attachment to determine its own height
                style.lineHeightMultiple = 1.0
                // Set to 0 to remove line height constraints entirely
                style.minimumLineHeight = 0
                style.maximumLineHeight = 0
                // Increase spacing significantly to prevent overlap between images
                style.paragraphSpacing = 16
                style.paragraphSpacingBefore = 16
                // No line spacing - let each image be its own paragraph
                style.lineSpacing = 0
                return style
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
