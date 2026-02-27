//
//  TodoRichTextEditor.swift
//  Jot
//
//  Rebuilt rich text editor that keeps todo checkboxes aligned,
//  clickable, and in sync with serialized markup.
//

import Combine
import SwiftUI

import AppKit
import QuartzCore
import CoreImage
import QuickLook
import UniformTypeIdentifiers

extension NSAttributedString.Key {
    fileprivate static let webClipTitle = NSAttributedString.Key("WebClipTitle")
    fileprivate static let webClipDescription = NSAttributedString.Key("WebClipDescription")
    fileprivate static let webClipDomain = NSAttributedString.Key("WebClipDomain")
    fileprivate static let plainLinkURL = NSAttributedString.Key("PlainLinkURL")
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

// MARK: - Typing Animation Layout Manager

/// Custom layout manager that animates newly-typed glyphs floating up from below.
/// Each character rises from an initial Y offset with an opacity fade, driven by
/// a high-frequency timer that suspends when no animations are active.
fileprivate final class TypingAnimationLayoutManager: NSLayoutManager {

    // MARK: Animation Parameters

    private let animationDuration: CFTimeInterval = 0.32
    private let initialYOffset: CGFloat = 8.0
    private let staggerDelay: CFTimeInterval = 0.06

    // MARK: State

    /// Maps character index to its animation start time.
    private var activeAnimations: [Int: CFTimeInterval] = [:]

    /// Timer that fires during active animations to drive redraw.
    private var animationTimer: Timer?

    /// The text view whose display we invalidate each frame.
    weak var animatingTextView: NSTextView?

    // MARK: Public API

    /// Register characters in a range for animation.
    /// - Parameters:
    ///   - range: The character range to animate.
    ///   - stagger: If true, each character gets an incremental delay (paste wave).
    func animateCharacters(in range: NSRange, stagger: Bool) {
        let now = CACurrentMediaTime()
        for i in 0..<range.length {
            let charIndex = range.location + i
            let delay = stagger ? Double(i) * staggerDelay : 0.0
            activeAnimations[charIndex] = now + delay
        }
        startTimerIfNeeded()
    }

    /// Immediately cancel all running animations.
    func clearAllAnimations() {
        activeAnimations.removeAll()
        animationTimer?.invalidate()
        animationTimer = nil
    }

    // MARK: Easing

    /// Cubic ease-out: fast arrival, gentle settle. No overshoot.
    private func easeOut(_ t: Double) -> Double {
        let p = 1.0 - t
        return 1.0 - p * p * p
    }

    // MARK: Timer

    private func startTimerIfNeeded() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            self.animatingTextView?.needsDisplay = true

            // Prune completed animations (keep if end time is still in the future)
            let now = CACurrentMediaTime()
            self.activeAnimations = self.activeAnimations.filter {
                now < $0.value + self.animationDuration
            }

            if self.activeAnimations.isEmpty {
                self.animationTimer?.invalidate()
                self.animationTimer = nil
            }
        }
    }

    // MARK: Drawing Override

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard !activeAnimations.isEmpty,
            let context = NSGraphicsContext.current?.cgContext
        else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        let now = CACurrentMediaTime()
        var currentIndex = glyphsToShow.location
        let endIndex = NSMaxRange(glyphsToShow)

        while currentIndex < endIndex {
            let charIndex = characterIndexForGlyph(at: currentIndex)

            if let startTime = activeAnimations[charIndex], now >= startTime {
                let elapsed = now - startTime
                let progress = min(elapsed / animationDuration, 1.0)

                if progress < 1.0 {
                    let easedProgress = easeOut(progress)
                    let yOffset = initialYOffset * CGFloat(1.0 - easedProgress)
                    let alpha = CGFloat(easedProgress)

                    context.saveGState()
                    context.translateBy(x: 0, y: yOffset)
                    context.setAlpha(alpha)
                    super.drawGlyphs(
                        forGlyphRange: NSRange(location: currentIndex, length: 1), at: origin)
                    context.restoreGState()
                } else {
                    activeAnimations.removeValue(forKey: charIndex)
                    super.drawGlyphs(
                        forGlyphRange: NSRange(location: currentIndex, length: 1), at: origin)
                }
                currentIndex += 1
            } else if activeAnimations[charIndex] != nil {
                // Start time is in the future (staggered), draw invisible
                context.saveGState()
                context.setAlpha(0)
                super.drawGlyphs(
                    forGlyphRange: NSRange(location: currentIndex, length: 1), at: origin)
                context.restoreGState()
                currentIndex += 1
            } else {
                // Batch consecutive non-animating glyphs for performance
                var runEnd = currentIndex + 1
                while runEnd < endIndex {
                    let nextCharIndex = characterIndexForGlyph(at: runEnd)
                    if activeAnimations[nextCharIndex] != nil { break }
                    runEnd += 1
                }
                super.drawGlyphs(
                    forGlyphRange: NSRange(location: currentIndex, length: runEnd - currentIndex),
                    at: origin)
                currentIndex = runEnd
            }
        }
    }
}

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


struct TodoRichTextEditor: View {
    @Binding var text: String
    var focusRequestID: UUID? = nil
    var onToolbarAction: ((EditTool) -> Void)?
    var onCommandMenuSelection: ((EditTool) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    private let baseBottomInset: CGFloat = 0


    // Command menu state (triggered by "/" character)
    @State private var showCommandMenu = false
    @State private var commandMenuPosition: CGPoint = .zero
    @State private var commandMenuSelectedIndex = 0
    @State private var commandSlashLocation: Int = -1

    // URL paste option menu state
    @State private var showURLPasteMenu = false
    @State private var urlPasteMenuPosition: CGPoint = .zero
    @State private var urlPasteURL: String = ""
    @State private var urlPasteRange: NSRange = NSRange(location: 0, length: 0)
    fileprivate static let commandMenuActions: [EditTool] = [.imageUpload, .voiceRecord, .link, .todo]
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
    static var isCommandMenuShowing: Bool {
        get { InlineNSTextView.isCommandMenuShowing }
        set { InlineNSTextView.isCommandMenuShowing = newValue }
    }


    init(
        text: Binding<String>,
        focusRequestID: UUID? = nil,
        onToolbarAction: ((EditTool) -> Void)? = nil,
        onCommandMenuSelection: ((EditTool) -> Void)? = nil
    ) {
        self._text = text
        self.focusRequestID = focusRequestID
        self.onToolbarAction = onToolbarAction
        self.onCommandMenuSelection = onCommandMenuSelection
    }

    private var bottomInset: CGFloat {
            return baseBottomInset
    }

    var body: some View {
        Group {
                TodoEditorRepresentable(
                    text: $text,
                    colorScheme: colorScheme,
                    bottomInset: bottomInset,
                    focusRequestID: focusRequestID
                )
        }
        .frame(maxWidth: .infinity)  // Natural height based on content
        .background(Color.clear)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showCommandMenu {
                    CommandMenu(
                        tools: commandMenuTools,
                        selectedIndex: $commandMenuSelectedIndex,
                        onSelect: { tool in handleCommandMenuSelection(tool) }
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
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showURLPasteMenu {
                    URLPasteOptionMenu(
                        onMention: {
                            withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
                            NotificationCenter.default.post(
                                name: .urlPasteSelectMention,
                                object: [
                                    "url": urlPasteURL,
                                    "range": NSValue(range: urlPasteRange),
                                ] as [String: Any]
                            )
                        },
                        onPasteAsURL: {
                            withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
                            NotificationCenter.default.post(
                                name: .urlPasteSelectPlainLink,
                                object: [
                                    "url": urlPasteURL,
                                    "range": NSValue(range: urlPasteRange),
                                ] as [String: Any]
                            )
                        }
                    )
                    .offset(
                        x: clampedURLPasteMenuPosition(for: geometry.size).x,
                        y: clampedURLPasteMenuPosition(for: geometry.size).y
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                        )
                    )
                    .zIndex(999)
                }
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

                    InlineNSTextView.isCommandMenuShowing = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HideCommandMenu")))
        { _ in
            withAnimation(.smooth(duration: 0.15)) {
                showCommandMenu = false
            }
            commandSlashLocation = -1

                InlineNSTextView.isCommandMenuShowing = false
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
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteDetected)) { notification in
            guard let info = notification.object as? [String: Any],
                  let url = info["url"] as? String,
                  let rangeValue = info["range"] as? NSValue,
                  let rectValue = info["rect"] as? NSValue else { return }

            let range = rangeValue.rangeValue
            let rect = rectValue.rectValue

            urlPasteURL = url
            urlPasteRange = range

            // Center the menu 8px below the URL text
            let menuWidth: CGFloat = 160
            let menuX = rect.midX - menuWidth / 2
            let menuY = rect.maxY + 8

            urlPasteMenuPosition = CGPoint(x: max(0, menuX), y: menuY)

            withAnimation(.smooth(duration: 0.2)) {
                showURLPasteMenu = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteDismiss)) { _ in
            if showURLPasteMenu {
                withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
            }
        }
    }

    // MARK: - Command Menu Handlers

    private func handleCommandMenuSelection(_ tool: EditTool) {
        withAnimation(.smooth(duration: 0.15)) {
            showCommandMenu = false
        }

            InlineNSTextView.isCommandMenuShowing = false

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

    private func clampedURLPasteMenuPosition(for containerSize: CGSize) -> CGPoint {
        let menuWidth: CGFloat = 160
        let menuHeight: CGFloat = 68
        let maxX = max(0, containerSize.width - menuWidth)
        let maxY = max(0, containerSize.height - menuHeight)
        let clampedX = min(max(urlPasteMenuPosition.x, 0), maxX)
        let clampedY = min(max(urlPasteMenuPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

}

// MARK: - URL Paste Option Menu

struct URLPasteOptionMenu: View {
    let onMention: () -> Void
    let onPasteAsURL: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredOption: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            optionRow(
                iconName: "insert link",
                label: "Mention",
                index: 0,
                action: onMention
            )
            optionRow(
                iconName: "IconGlobe",
                label: "Paste as URL",
                index: 1,
                action: onPasteAsURL
            )
        }
        .padding(CommandMenuLayout.outerPadding)
        .frame(width: 160)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }

    private func optionRow(
        iconName: String,
        label: String,
        index: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(iconColor(for: index))

                Text(label)
                    .font(FontManager.heading(size: 13, weight: .regular))
                    .foregroundStyle(textColor(for: index))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                hoveredOption == index
                    ? Capsule().fill(Color("HoverBackgroundColor"))
                    : nil
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.12)) {
                hoveredOption = isHovered ? index : (hoveredOption == index ? nil : hoveredOption)
            }
        }
    }

    private func iconColor(for index: Int) -> Color {
        hoveredOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("IconSecondaryColor")
    }

    private func textColor(for index: Int) -> Color {
        hoveredOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("PrimaryTextColor")
    }
}

// MARK: - Representable Implementations


    struct TodoEditorRepresentable: NSViewRepresentable {
        @Binding var text: String
        let colorScheme: ColorScheme
        let bottomInset: CGFloat
        let focusRequestID: UUID?
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

                // Install custom layout manager for typing animation
                let typingLayoutManager = TypingAnimationLayoutManager()
                container.replaceLayoutManager(typingLayoutManager)
                typingLayoutManager.animatingTextView = textView
                context.coordinator.typingAnimationManager = typingLayoutManager
            }

            let initialScheme = colorScheme
            if let resolvedAppearance = appearance(for: initialScheme) {
                textView.appearance = resolvedAppearance
            }

            let resolvedColor = resolvedTextColor(
                for: initialScheme, appearance: textView.appearance)
            textView.textColor = resolvedColor
            textView.typingAttributes = Coordinator.baseTypingAttributes(for: initialScheme)
            textView.defaultParagraphStyle = Coordinator.baseParagraphStyle()

            context.coordinator.updateColorScheme(initialScheme)
            context.coordinator.configure(with: textView)

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
            let resolvedScheme = colorScheme

            // Only update appearance/colors when the color scheme has actually changed
            if context.coordinator.currentColorScheme != resolvedScheme {
                if let resolvedAppearance = appearance(for: resolvedScheme) {
                    textView.appearance = resolvedAppearance
                    let resolvedColor = resolvedTextColor(
                        for: resolvedScheme, appearance: textView.appearance)
                    textView.textColor = resolvedColor
                    textView.typingAttributes = Coordinator.baseTypingAttributes(for: resolvedScheme)
                    textView.linkTextAttributes = [
                        .underlineStyle: 0,
                        .underlineColor: NSColor.clear,
                    ]
                    context.coordinator.updateColorScheme(resolvedScheme)

                    // Re-color non-custom text ranges for the new theme
                    if let textStorage = textView.textStorage {
                        let themeColor = resolvedTextColor(for: resolvedScheme, appearance: textView.appearance)
                        let fullRange = NSRange(location: 0, length: textStorage.length)
                        textStorage.beginEditing()
                        textStorage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                            guard attributes[.attachment] == nil else { return }
                            if attributes[TextFormattingManager.customTextColorKey] as? Bool != true {
                                textStorage.addAttribute(.foregroundColor, value: themeColor, range: range)
                            }
                        }
                        textStorage.endEditing()
                        textView.needsDisplay = true
                    }
                }
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
            context.coordinator.requestFocusIfNeeded(focusRequestID)
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
            return Coordinator(
                text: $text,
                colorScheme: colorScheme,
                focusRequestID: focusRequestID
            )
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
            private var lastHandledFocusRequestID: UUID?

            // Typing animation state
            fileprivate weak var typingAnimationManager: TypingAnimationLayoutManager?
            private var pendingAnimationLocation: Int?
            private var pendingAnimationLength: Int?
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
                case webClip(attachment: NSTextAttachment)
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
            private var hoveredWebClipAttachment: NSTextAttachment?
            // Allow slight tolerance so hover stays active when the cursor is near the tag edges
            private let hoverHitTolerance: CGFloat = 4
            private static let previewImageCache: NSCache<NSString, NSImage> = {
                let cache = NSCache<NSString, NSImage>()
                cache.countLimit = 32
                return cache
            }()

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

                        // Convert to window coordinates for proper positioning
                        let selectionRectInWindow = textView.convert(selectionRect, to: nil)

                        // Cache selection so Edit Content can use it even after focus shifts
                        lastKnownSelectionRange = selectedRange
                        lastKnownSelectionText = (textView.string as NSString).substring(with: selectedRange)
                        lastKnownSelectionWindowRect = selectionRectInWindow

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
                    // Clear cache only if user deliberately placed cursor (view still has focus).
                    // When focus is lost (e.g. clicking AI tools button), preserve cache so the
                    // selection is still available for the tool that caused the focus shift.
                    if textView.window?.firstResponder == textView {
                        lastKnownSelectionRange = NSRange(location: NSNotFound, length: 0)
                        lastKnownSelectionText = ""
                        lastKnownSelectionWindowRect = .zero
                    }
                    let info: [String: Any] = ["hasSelection": false]
                    NotificationCenter.default.post(
                        name: .textSelectionChanged,
                        object: nil,
                        userInfo: info
                    )
                }
            }
            private var textBeforeWritingTools = ""
            var currentColorScheme: ColorScheme

            // Proofread inline overlay tracking: (pill view, highlighted NSRange, original text color attributes)
            private var proofreadPillViews: [(view: NSView, range: NSRange)] = []
            private var proofreadHighlightedRanges: [NSRange] = []

            // Last known non-empty selection — cached here so clicking the AI tools button
            // (which clears the NSTextView selection) doesn't lose context for Edit Content.
            private var lastKnownSelectionRange: NSRange = NSRange(location: NSNotFound, length: 0)
            private var lastKnownSelectionText: String = ""
            private var lastKnownSelectionWindowRect: CGRect = .zero

            // Use Charter for body text as per design requirements
            private static var textFont: NSFont { FontManager.bodyNS(size: 16, weight: .regular) }
            private static let baseLineHeight: CGFloat = 24
            private static let todoLineHeight: CGFloat = 24
            private static let checkboxIconSize: CGFloat = 18
            private static let baseBaselineOffset: CGFloat = 0.0
            private static let todoBaselineOffset: CGFloat = {
                return 0.0
            }()
            private static var checkboxAttachmentYOffset: CGFloat { 0.0 }
            private static let checkboxBaselineOffset: CGFloat = {
                return 0.0
            }()
            private static let webClipMarkupPrefix = "[[webclip|"
            private static let webClipPattern = #"\[\[webclip\|([^|]*)\|([^|]*)\|([^\]]*)\]\]"#
            private static let webClipRegex: NSRegularExpression? = try? NSRegularExpression(
                pattern: webClipPattern,
                options: []
            )
            private static let plainLinkMarkupPrefix = "[[link|"
            private static let plainLinkPattern = #"\[\[link\|([^\]]*)\]\]"#
            private static let plainLinkRegex: NSRegularExpression? = try? NSRegularExpression(
                pattern: plainLinkPattern,
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

            /// Create a plain blue text link attachment -- looks like text, behaves like a button.
            private func makePlainLinkAttachment(url rawURL: String) -> NSMutableAttributedString {
                let normalizedURL = Self.normalizedURL(from: rawURL)
                let linkValue = normalizedURL.isEmpty ? rawURL : normalizedURL

                let linkView = Text(linkValue)
                    .font(FontManager.heading(size: Self.textFont.pointSize, weight: .regular))
                    .foregroundColor(.accentColor)
                    .fixedSize()
                    .environment(\.colorScheme, currentColorScheme)

                let renderer = ImageRenderer(content: linkView)
                let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
                renderer.scale = displayScale
                renderer.isOpaque = false

                let attachment = NSTextAttachment()

                guard let cgImage = renderer.cgImage else {
                    return NSMutableAttributedString(string: linkValue)
                }

                let pixelWidth = CGFloat(cgImage.width)
                let pixelHeight = CGFloat(cgImage.height)
                let displaySize = CGSize(
                    width: pixelWidth / displayScale,
                    height: pixelHeight / displayScale)

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
                let attachmentRange = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(.link, value: linkValue, range: attachmentRange)
                attributed.addAttribute(.underlineStyle, value: 0, range: attachmentRange)
                attributed.addAttribute(.plainLinkURL, value: linkValue, range: attachmentRange)
                attributed.addAttribute(
                    .paragraphStyle, value: Self.webClipParagraphStyle(), range: attachmentRange)

                return attributed
            }

            /// Create an inline image attachment tag from a filename
            private func makeImageAttachment(filename: String, imageNumber: Int) -> NSMutableAttributedString {
                func fallbackAttributedString() -> NSMutableAttributedString {
                    return NSMutableAttributedString(string: "[Image: \(filename)]")
                }

                let tagLabel = "image\(max(imageNumber, 1))"

                if ImageStorageManager.shared.getImageURL(for: filename) == nil {
                    NSLog("🖼️ makeImageAttachment: WARNING - no stored file found for %@", filename)
                }

                let attachment: NoteImageAttachment
                let displaySize: CGSize

                let tagView = ImageAttachmentTagView(label: tagLabel)
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
                sizeDescription = NSStringFromSize(
                    NSSize(width: displaySize.width, height: displaySize.height))

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
                resetWebClipHover()
            }

            private func showWebClipHover(
                attachment: NSTextAttachment,
                characterIndex: Int,
                at rectInTextView: CGRect,
                in textView: NSTextView
            ) {
                if hoveredWebClipAttachment === attachment { return }
                hoveredWebClipAttachment = attachment

                // attachment.image is nil once the layout system moves it to a cell
                let image = attachmentImage(attachment, in: textView, characterIndex: characterIndex)
                    ?? attachment.image
                guard let image else { return }

                let scaleAmount: CGFloat = 1.06
                let scaledSize = CGSize(
                    width: rectInTextView.width * scaleAmount,
                    height: rectInTextView.height * scaleAmount
                )
                let scaledOrigin = CGPoint(
                    x: rectInTextView.midX - scaledSize.width / 2,
                    y: rectInTextView.midY - scaledSize.height / 2
                )
                let scaledRect = CGRect(origin: scaledOrigin, size: scaledSize)

                let host = previewHostView ?? textView.superview
                guard let host else { return }

                let rectInHost = textView.convert(scaledRect, to: host)
                let overlay = ensureHoverTagOverlay(in: host, relativeTo: textView)
                overlay.image = image
                overlay.imageScaling = .scaleProportionallyUpOrDown
                overlay.frame = rectInHost.integral
                overlay.layer?.cornerRadius = rectInHost.height / 2
                overlay.layer?.cornerCurve = .continuous
                overlay.layer?.masksToBounds = true
            }

            private func resetWebClipHover() {
                hoveredWebClipAttachment = nil
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
                } else if attributes[.webClipDomain] != nil {
                    previewTarget = .webClip(attachment: attachment)
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
                case .webClip:
                    break
                }
                return true
            }

            init(text: Binding<String>, colorScheme: ColorScheme, focusRequestID: UUID?) {
                self.textBinding = text
                self.currentColorScheme = colorScheme
                self.lastHandledFocusRequestID = focusRequestID
            }

            deinit {
                typingAnimationManager?.clearAllAnimations()
                observers.forEach { NotificationCenter.default.removeObserver($0) }
                observers.removeAll()
            }

            func configure(with textView: NSTextView) {
                self.textView = textView
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
                    guard let raw = notification.userInfo?["tool"] as? String else { return }
                    guard let tool = EditTool(rawValue: raw) else { return }
                    Task { @MainActor [weak self] in
                        guard let self = self, let textView = self.textView else { return }
                        self.formatter.applyFormatting(to: textView, tool: tool)
                        self.styleTodoParagraphs()
                        self.syncText()
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
                        // Special handling for todo checkbox to use proper attachment instead of text
                        if tool == .todo {
                            self.insertTodo()
                        } else {
                            self.formatter.applyFormatting(to: textView, tool: tool)
                        }

                        // Sync the text back
                        self.syncText()
                    }
                }

                let highlightSearch = NotificationCenter.default.addObserver(
                    forName: .highlightSearchMatches, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let userInfo = notification.userInfo,
                          let ranges = userInfo["ranges"] as? [NSRange],
                          let activeIndex = userInfo["activeIndex"] as? Int else { return }
                    Task { @MainActor [weak self] in
                        self?.applySearchHighlighting(ranges: ranges, activeIndex: activeIndex)
                    }
                }

                let clearSearch = NotificationCenter.default.addObserver(
                    forName: .clearSearchHighlights, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.clearSearchHighlighting()
                    }
                }

                // MARK: Proofread show annotations
                let proofreadShow = NotificationCenter.default.addObserver(
                    forName: .aiProofreadShowAnnotations, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let annotations = notification.object as? [ProofreadAnnotation] else { return }
                    let activeIndex = notification.userInfo?["activeIndex"] as? Int ?? 0
                    Task { @MainActor [weak self] in
                        self?.applyProofreadAnnotations(annotations, activeIndex: activeIndex)
                    }
                }

                // MARK: Proofread clear overlays
                let proofreadClear = NotificationCenter.default.addObserver(
                    forName: .aiProofreadClearOverlays, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.clearProofreadOverlays()
                    }
                }

                // MARK: Proofread apply suggestion
                let proofreadApply = NotificationCenter.default.addObserver(
                    forName: .aiProofreadApplySuggestion, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let userInfo = notification.userInfo,
                          let original = userInfo["original"] as? String,
                          let replacement = userInfo["replacement"] as? String else { return }
                    Task { @MainActor [weak self] in
                        self?.applyProofreadSuggestion(original: original, replacement: replacement)
                    }
                }

                // MARK: Edit Content — capture selection
                let captureSelection = NotificationCenter.default.addObserver(
                    forName: .aiEditRequestSelection, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.captureSelectionForEditContent()
                    }
                }

                let urlPasteMention = NotificationCenter.default.addObserver(
                    forName: .urlPasteSelectMention, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let info = notification.object as? [String: Any],
                          let url = info["url"] as? String,
                          let rangeValue = info["range"] as? NSValue else { return }
                    Task { @MainActor [weak self] in
                        self?.replaceURLPasteWithWebClip(url: url, range: rangeValue.rangeValue)
                    }
                }

                let urlPasteSelectPlainLink = NotificationCenter.default.addObserver(
                    forName: .urlPasteSelectPlainLink, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let info = notification.object as? [String: Any],
                          let url = info["url"] as? String,
                          let rangeValue = info["range"] as? NSValue else { return }
                    Task { @MainActor [weak self] in
                        self?.replaceURLPasteWithPlainLink(url: url, range: rangeValue.rangeValue)
                    }
                }

                let urlPasteDismiss = NotificationCenter.default.addObserver(
                    forName: .urlPasteDismiss, object: nil, queue: .main
                ) { [weak self] notification in
                    let range = (notification.object as? NSValue)?.rangeValue
                    Task { @MainActor [weak self] in
                        if let range { self?.clearURLPasteHighlight(range: range) }
                    }
                }

                let applyColor = NotificationCenter.default.addObserver(
                    forName: Notification.Name("applyTextColor"), object: nil, queue: .main
                ) { [weak self] notification in
                    TextFormattingManager.colorLog("RECEIVED notification applyTextColor")
                    guard let hex = notification.userInfo?["hex"] as? String else {
                        TextFormattingManager.colorLog("FAIL: hex not found in userInfo")
                        return
                    }
                    TextFormattingManager.colorLog("hex=\(hex), self is nil=\(self == nil)")
                    Task { @MainActor [weak self] in
                        guard let self = self, let textView = self.textView else {
                            TextFormattingManager.colorLog("FAIL: self or textView nil inside Task")
                            return
                        }
                        TextFormattingManager.colorLog("Inside Task: calling applyTextColor")
                        self.formatter.applyTextColor(hex: hex, to: textView)
                        self.syncText()
                        TextFormattingManager.colorLog("syncText done, lastSerialized contains color=\(self.lastSerialized.contains("[[color|"))")
                    }
                }

                observers = [
                    insertTodo, insertLink, insertVoiceTranscript, insertImage, applyTool, applyCommandMenuTool,
                    highlightSearch, clearSearch,
                    proofreadShow, proofreadClear, proofreadApply, captureSelection,
                    urlPasteMention, urlPasteSelectPlainLink, urlPasteDismiss,
                    applyColor,
                ]
            }

            // MARK: - Proofread Overlay Helpers

            private func applyProofreadAnnotations(_ annotations: [ProofreadAnnotation], activeIndex: Int = 0) {
                guard let textView = self.textView,
                      let storage = textView.textStorage,
                      let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer else { return }

                clearProofreadOverlays()

                let fullString = storage.string as NSString

                // First pass: resolve all annotation ranges
                var resolved: [(annotation: ProofreadAnnotation, range: NSRange)] = []
                for annotation in annotations {
                    let found = fullString.range(
                        of: annotation.original,
                        options: .literal,
                        range: NSRange(location: 0, length: fullString.length)
                    )
                    guard found.location != NSNotFound else { continue }
                    resolved.append((annotation, found))
                }

                // Use the same explicit text colors the editor uses (from baseTypingAttributes)
                let isDark = currentColorScheme == .dark
                let baseColor: NSColor = isDark
                    ? NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                    : NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)
                let dimAlpha: CGFloat = isDark ? 0.4 : 0.25
                let dimColor = baseColor.withAlphaComponent(dimAlpha)

                let fullRange = NSRange(location: 0, length: storage.length)
                let clampedIndex = resolved.isEmpty ? 0 : min(activeIndex, resolved.count - 1)
                storage.beginEditing()
                storage.addAttribute(.foregroundColor, value: dimColor, range: fullRange)
                if !resolved.isEmpty {
                    storage.addAttribute(.foregroundColor, value: baseColor, range: resolved[clampedIndex].range)
                }
                storage.endEditing()

                // Track all resolved ranges
                for item in resolved {
                    proofreadHighlightedRanges.append(item.range)
                }

                // Scroll the active annotation into view
                if !resolved.isEmpty {
                    textView.scrollRangeToVisible(resolved[clampedIndex].range)
                }
            }

            private func clearProofreadOverlays() {
                guard let textView = self.textView,
                      let storage = textView.textStorage else {
                    proofreadPillViews.forEach { $0.view.removeFromSuperview() }
                    proofreadPillViews.removeAll()
                    proofreadHighlightedRanges.removeAll()
                    return
                }

                // Remove pill views
                proofreadPillViews.forEach { $0.view.removeFromSuperview() }
                proofreadPillViews.removeAll()

                // Restore full text opacity
                if storage.length > 0 {
                    storage.beginEditing()
                    storage.addAttribute(
                        .foregroundColor,
                        value: NSColor.labelColor,
                        range: NSRange(location: 0, length: storage.length)
                    )
                    storage.endEditing()
                }
                proofreadHighlightedRanges.removeAll()
            }

            private func applyProofreadSuggestion(original: String, replacement: String) {
                guard let textView = self.textView,
                      let storage = textView.textStorage else { return }

                let fullString = storage.string as NSString
                let found = fullString.range(of: original, options: .literal, range: NSRange(location: 0, length: fullString.length))
                guard found.location != NSNotFound else {
                    clearProofreadOverlays()
                    return
                }

                if textView.shouldChangeText(in: found, replacementString: replacement) {
                    storage.replaceCharacters(in: found, with: replacement)
                    textView.didChangeText()
                }
                syncText()
                NotificationCenter.default.post(name: .aiProofreadClearOverlays, object: nil)
            }

            // MARK: - Edit Content Selection Capture

            private func captureSelectionForEditContent() {
                // Clicking the AI tools button clears the text view selection before this fires,
                // so we use the last cached non-empty selection rather than reading the live selection.
                guard lastKnownSelectionRange.length > 0 else {
                    NotificationCenter.default.post(
                        name: .aiEditCaptureSelection,
                        object: nil,
                        userInfo: [
                            "nsRange": NSRange(location: NSNotFound, length: 0),
                            "selectedText": "",
                            "windowRect": CGRect.zero
                        ]
                    )
                    return
                }

                NotificationCenter.default.post(
                    name: .aiEditCaptureSelection,
                    object: nil,
                    userInfo: [
                        "nsRange": lastKnownSelectionRange,
                        "selectedText": lastKnownSelectionText,
                        "windowRect": lastKnownSelectionWindowRect
                    ]
                )
            }

            // MARK: - Search Highlighting

            private var searchImpulseView: NSView?

            func applySearchHighlighting(ranges: [NSRange], activeIndex: Int) {
                guard let textView = self.textView,
                      let storage = textView.textStorage else { return }
                let fullRange = NSRange(location: 0, length: storage.length)
                guard fullRange.length > 0 else { return }

                storage.beginEditing()

                // Dim all text to 30% opacity
                storage.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                    if let color = value as? NSColor {
                        storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.3), range: range)
                    }
                }

                // Restore matched ranges to full opacity
                for matchRange in ranges {
                    guard matchRange.location + matchRange.length <= storage.length else { continue }
                    storage.enumerateAttribute(.foregroundColor, in: matchRange, options: []) { value, range, _ in
                        if let color = value as? NSColor {
                            storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(1.0), range: range)
                        }
                    }
                }

                storage.endEditing()

                // Scroll active match into view and play impulse
                if activeIndex >= 0 && activeIndex < ranges.count {
                    textView.scrollRangeToVisible(ranges[activeIndex])
                    playMatchGlow(for: ranges[activeIndex])
                }
            }

            func clearSearchHighlighting() {
                guard let textView = self.textView,
                      let storage = textView.textStorage else { return }
                let fullRange = NSRange(location: 0, length: storage.length)
                guard fullRange.length > 0 else { return }

                // Remove any lingering impulse view
                searchImpulseView?.removeFromSuperview()
                searchImpulseView = nil

                storage.beginEditing()

                // Restore all text to full opacity
                storage.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                    if let color = value as? NSColor {
                        storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(1.0), range: range)
                    }
                }

                storage.endEditing()
            }

            private func playMatchGlow(for range: NSRange) {
                guard let textView = self.textView,
                      let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer else { return }

                // Remove previous glow
                searchImpulseView?.removeFromSuperview()
                searchImpulseView = nil

                // Get the glyph rect for the matched range
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var matchRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                // Offset for text container inset
                let origin = textView.textContainerOrigin
                matchRect.origin.x += origin.x
                matchRect.origin.y += origin.y

                // Pad for diffuse glow breathing room
                let padding: CGFloat = 10
                matchRect = matchRect.insetBy(dx: -padding, dy: -padding)

                // Determine glow color based on appearance
                let isDark: Bool = {
                    let appearance = textView.window?.effectiveAppearance ?? textView.effectiveAppearance
                    if let match = appearance.bestMatch(from: [.darkAqua, .aqua]) {
                        return match == .darkAqua
                    }
                    return true
                }()
                let glowColor = isDark
                    ? NSColor(white: 1.0, alpha: 0.45)
                    : NSColor(white: 0.0, alpha: 0.50)

                // -- Outer Glow View (no visible background) --
                let glowView = NSView(frame: matchRect)
                glowView.wantsLayer = true
                guard let glowLayer = glowView.layer else { return }

                // No background -- the glow is purely the shadow cast from shadowPath
                glowLayer.backgroundColor = NSColor.clear.cgColor
                glowLayer.shadowPath = CGPath(
                    roundedRect: CGRect(origin: .zero, size: matchRect.size),
                    cornerWidth: 3, cornerHeight: 3, transform: nil
                )
                glowLayer.shadowColor = glowColor.cgColor
                glowLayer.shadowOffset = .zero
                glowLayer.shadowRadius = 0
                glowLayer.shadowOpacity = 0

                textView.addSubview(glowView)
                searchImpulseView = glowView

                // -- Layer 2: Sparkle Emitter --
                let emitter = CAEmitterLayer()
                emitter.emitterPosition = CGPoint(x: matchRect.width / 2, y: matchRect.height / 2)
                emitter.emitterSize = CGSize(width: matchRect.width, height: 1)
                emitter.emitterShape = .line
                emitter.renderMode = .additive

                let sparkleCell = CAEmitterCell()
                sparkleCell.contents = {
                    let size: CGFloat = 4
                    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                        let path = NSBezierPath(ovalIn: rect)
                        NSColor.white.setFill()
                        path.fill()
                        return true
                    }
                    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }()
                sparkleCell.birthRate = 40
                sparkleCell.lifetime = 0.5
                sparkleCell.lifetimeRange = 0.15
                sparkleCell.velocity = 20
                sparkleCell.velocityRange = 10
                sparkleCell.emissionRange = .pi * 2
                sparkleCell.scale = 0.4
                sparkleCell.scaleRange = 0.2
                sparkleCell.scaleSpeed = -0.3
                sparkleCell.alphaSpeed = -1.5
                sparkleCell.color = glowColor.withAlphaComponent(0.8).cgColor

                emitter.emitterCells = [sparkleCell]
                glowLayer.addSublayer(emitter)

                // -- Animations --
                // Shadow radius: 0 -> 20 -> 0 (wide feathered bloom, no hard edge)
                let radiusAnim = CAKeyframeAnimation(keyPath: "shadowRadius")
                radiusAnim.values = [0, 20, 0]
                radiusAnim.keyTimes = [0, 0.33, 1.0]
                radiusAnim.timingFunctions = [
                    CAMediaTimingFunction(name: .easeOut),
                    CAMediaTimingFunction(name: .easeIn)
                ]
                radiusAnim.duration = 0.6

                // Shadow opacity: 0 -> 0.45 -> 0
                let opacityAnim = CAKeyframeAnimation(keyPath: "shadowOpacity")
                opacityAnim.values = [0, 0.45, 0]
                opacityAnim.keyTimes = [0, 0.33, 1.0]
                opacityAnim.timingFunctions = [
                    CAMediaTimingFunction(name: .easeOut),
                    CAMediaTimingFunction(name: .easeIn)
                ]
                opacityAnim.duration = 0.6

                // Stop emitting after brief burst, let existing particles fade
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    emitter.birthRate = 0
                }

                CATransaction.begin()
                CATransaction.setCompletionBlock { [weak self] in
                    // Allow sparkle particles to finish their lifetime before removal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        Task { @MainActor [weak self] in
                            // Only remove if this is still the current glow view
                            if self?.searchImpulseView === glowView {
                                glowView.removeFromSuperview()
                                self?.searchImpulseView = nil
                            }
                        }
                    }
                }
                glowLayer.add(radiusAnim, forKey: "glowRadius")
                glowLayer.add(opacityAnim, forKey: "glowOpacity")
                CATransaction.commit()
            }

            func requestFocusIfNeeded(_ focusRequestID: UUID?) {
                guard let focusRequestID else { return }
                guard lastHandledFocusRequestID != focusRequestID else { return }
                lastHandledFocusRequestID = focusRequestID
                guard let textView else { return }

                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                }
            }

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
                } else if attributes[.plainLinkURL] != nil,
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

                typingAnimationManager?.clearAllAnimations()
                isUpdating = true

                let targetTextColor: NSColor = currentColorScheme == .dark
                    ? NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                    : NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)
                textView.textColor = targetTextColor

                let attributedText = deserialize(text)
                textStorage.setAttributedString(attributedText)

                textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                styleTodoParagraphs()

                // Cache the input directly — deserialize+serialize is a stable round-trip,
                // so we avoid a redundant O(n) enumeration pass here.
                lastSerialized = text

                if let container = textView.textContainer,
                    let layoutManager = textView.layoutManager
                {
                    layoutManager.ensureLayout(for: container)
                }
                textView.invalidateIntrinsicContentSize()
                textView.needsDisplay = true
                textView.needsLayout = true

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

                textStorage.beginEditing()
                textStorage.enumerateAttributes(in: fullRange, options: []) {
                    attributes, range, _ in
                    guard attributes[.attachment] == nil else { return }
                    if attributes[TextFormattingManager.customTextColorKey] as? Bool != true {
                        textStorage.addAttribute(.foregroundColor, value: textColor, range: range)
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
                else { return }

                guard text != lastSerialized else { return }

                let selectedRange = textView.selectedRange()

                typingAnimationManager?.clearAllAnimations()
                isUpdating = true

                textView.textColor = currentColorScheme == .dark
                    ? NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                    : NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)

                let attributedText = deserialize(text)
                textStorage.setAttributedString(attributedText)

                textView.typingAttributes = Self.baseTypingAttributes(for: currentColorScheme)
                styleTodoParagraphs()

                lastSerialized = text
                textView.setSelectedRange(selectedRange)

                isUpdating = false
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView, textView == self.textView,
                    !isUpdating
                else { return }

                // Trigger typing animation for newly inserted characters
                if let location = pendingAnimationLocation,
                    let length = pendingAnimationLength,
                    length > 0
                {
                    let stagger = length > 1
                    typingAnimationManager?.animateCharacters(
                        in: NSRange(location: location, length: length),
                        stagger: stagger
                    )
                    pendingAnimationLocation = nil
                    pendingAnimationLength = nil
                }

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

                // Dismiss URL paste menu on any text change
                NotificationCenter.default.post(name: .urlPasteDismiss, object: nil)

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

                // Record pending animation for newly inserted text.
                // Skip animation entirely for paste operations — instant insertion feels right.
                let isPasting = (textView as? InlineNSTextView)?.isPasting ?? false
                if !isUpdating, !isPasting, let replacement = replacementString, !replacement.isEmpty {
                    pendingAnimationLocation = affectedCharRange.location
                    pendingAnimationLength = replacement.count
                } else {
                    pendingAnimationLocation = nil
                    pendingAnimationLength = nil
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
                        // Position cursor at the location where "/" was removed
                        textView.setSelectedRange(NSRange(location: slashLocation, length: 0))
                    }
                }

                // Apply the selected tool
                // Special handling for todo checkbox to use proper attachment instead of text
                if tool == .todo {
                    insertTodo()
                } else {
                    formatter.applyFormatting(to: textView, tool: tool)
                }

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

            private func replaceURLPasteWithWebClip(url: String, range: NSRange) {
                guard let textView = textView, let textStorage = textView.textStorage else { return }

                // Clear the blue highlight
                if range.location + range.length <= textStorage.length {
                    textStorage.removeAttribute(.foregroundColor, range: range)
                }

                // Select the pasted URL text range and replace with web clip
                textView.setSelectedRange(range)
                insertWebClip(url: url)
            }

            private func replaceURLPasteWithPlainLink(url: String, range: NSRange) {
                guard let textView = textView, let textStorage = textView.textStorage else { return }

                if range.location + range.length <= textStorage.length {
                    textStorage.removeAttribute(.foregroundColor, range: range)
                }

                textView.setSelectedRange(range)

                let attachment = makePlainLinkAttachment(url: url)
                let composed = NSMutableAttributedString()
                composed.append(attachment)
                let space = NSAttributedString(
                    string: " ",
                    attributes: Self.baseTypingAttributes(for: currentColorScheme))
                composed.append(space)

                replaceSelection(with: composed)
                syncText()
            }

            private func clearURLPasteHighlight(range: NSRange) {
                guard let textStorage = textView?.textStorage else { return }
                guard range.location + range.length <= textStorage.length else { return }
                // Restore base text attributes (keep the URL text as-is but remove special styling)
                let base = Self.baseTypingAttributes(for: currentColorScheme)
                textStorage.addAttributes(base, range: range)
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
                let nextNumber = nextImageNumber(in: textView.textStorage)
                let attachment = makeImageAttachment(filename: filename, imageNumber: nextNumber)
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

            private func nextImageNumber(in textStorage: NSTextStorage?) -> Int {
                guard let textStorage else { return 1 }
                return max(1, imageAttachmentCount(in: textStorage) + 1)
            }

            private func imageAttachmentCount(in attributedString: NSAttributedString) -> Int {
                let fullRange = NSRange(location: 0, length: attributedString.length)
                guard fullRange.length > 0 else { return 0 }

                var count = 0
                attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, _, _ in
                    if attributes[.imageFilename] != nil
                        || attributes[.attachment] is NoteImageAttachment
                    {
                        count += 1
                    }
                }
                return count
            }

            private func renumberImageAttachments() {
                guard let textView = textView,
                    let textStorage = textView.textStorage
                else { return }

                let fullRange = NSRange(location: 0, length: textStorage.length)
                guard fullRange.length > 0 else { return }

                var replacements: [(range: NSRange, filename: String, number: Int)] = []
                var counter = 0

                textStorage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                    if let filename = attributes[.imageFilename] as? String {
                        counter += 1
                        replacements.append((range: range, filename: filename, number: counter))
                    } else if let attachment = attributes[.attachment] as? NoteImageAttachment {
                        counter += 1
                        replacements.append(
                            (range: range, filename: attachment.storedFilename, number: counter)
                        )
                    }
                }

                guard !replacements.isEmpty else { return }

                let originalSelection = textView.selectedRange()
                textStorage.beginEditing()
                for replacement in replacements.reversed() {
                    let updatedAttachment = makeImageAttachment(
                        filename: replacement.filename,
                        imageNumber: replacement.number
                    )
                    textStorage.replaceCharacters(in: replacement.range, with: updatedAttachment)
                }
                textStorage.endEditing()

                let maxLocation = textStorage.length
                let clampedLocation = min(originalSelection.location, maxLocation)
                let clampedLength = min(
                    originalSelection.length,
                    max(0, maxLocation - clampedLocation)
                )
                textView.setSelectedRange(
                    NSRange(location: clampedLocation, length: clampedLength)
                )
            }

            private func replaceSelection(with attributed: NSAttributedString) {
                guard let textView = textView else { return }
                hideImagePreview()
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
                renumberImageAttachments()
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

                    // Check text color — skip ranges with a user-intentional custom color
                    let hasCustomColor = attributes[TextFormattingManager.customTextColorKey] as? Bool == true
                    if hasCustomColor {
                        NSLog("[ColorDebug] fixInconsistentFonts: PRESERVING custom color at range (%d,%d)", range.location, range.length)
                    }
                    if !hasCustomColor {
                        if let currentColor = attributes[.foregroundColor] as? NSColor {
                            if !currentColor.isEqual(expectedColor) {
                                fixedAttributes[.foregroundColor] = expectedColor
                                needsFixing = true
                            }
                        } else {
                            fixedAttributes[.foregroundColor] = expectedColor
                            needsFixing = true
                        }
                    }

                    if needsFixing {
                        textStorage.setAttributes(fixedAttributes, range: range)
                    }
                }
            }

            private func styleTodoParagraphs() {
                guard let textStorage = textView?.textStorage else { return }
                let fullRange = NSRange(location: 0, length: textStorage.length)
                textStorage.beginEditing()
                textStorage.removeAttribute(.paragraphStyle, range: fullRange)
                textStorage.removeAttribute(.baselineOffset, range: fullRange)

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
                textStorage.endEditing()
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
                storage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                    if let attachment = attributes[.attachment] as? NSTextAttachment,
                        let cell = attachment.attachmentCell as? TodoCheckboxAttachmentCell
                    {
                        output.append(cell.isChecked ? "[x]" : "[ ]")
                    } else if attributes[.plainLinkURL] is String,
                        let urlString = attributes[.link] as? String
                    {
                        let sanitizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                        output.append("[[link|\(sanitizedURL)]]")
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
                        if let filename = attributes[.imageFilename] as? String {
                            output.append("[[image|||\(filename)]]")
                        } else if let noteAttachment = attachment as? NoteImageAttachment {
                            output.append("[[image|||\(noteAttachment.storedFilename)]]")
                        } else if let fileWrapper = attachment.fileWrapper,
                                let filename = fileWrapper.preferredFilename ?? fileWrapper.filename,
                                !filename.isEmpty,
                                filename.hasSuffix(".jpg")
                        {
                            output.append("[[image|||\(filename)]]")
                        } else {
                            output.append((storage.string as NSString).substring(with: range))
                            NSLog("⚠️ Serialization CRITICAL: Could not find filename for image attachment. Data may be lost.")
                        }
                    } else {
                        let rangeText = (storage.string as NSString).substring(with: range)
                        if attributes[TextFormattingManager.customTextColorKey] as? Bool == true,
                           let nsColor = attributes[.foregroundColor] as? NSColor
                        {
                            let hex = Self.nsColorToHex(nsColor)
                            NSLog("[ColorDebug] SERIALIZE: emitting color markup hex=%@ text='%@'", hex, rangeText)
                            output.append("[[color|\(hex)]]")
                            output.append(rangeText)
                            output.append("[[/color]]")
                        } else {
                            output.append(rangeText)
                        }
                    }
                }
                return output
            }

            private func deserialize(_ text: String) -> NSAttributedString {
                // Handle empty text case
                if text.isEmpty {
                    return NSAttributedString(
                        string: "", attributes: Self.baseTypingAttributes(for: currentColorScheme))
                }

                let result = NSMutableAttributedString()
                var index = text.startIndex
                var lastWasWebClip = false
                var imageCounter = 0

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
                    } else if text[index...].hasPrefix(Self.plainLinkMarkupPrefix) {
                        if let endIndex = text[index...].range(of: "]]")?.upperBound {
                            let linkText = String(text[index..<endIndex])
                            if let regex = Self.plainLinkRegex,
                               let match = regex.firstMatch(
                                   in: linkText, options: [],
                                   range: NSRange(location: 0, length: linkText.utf16.count))
                            {
                                let rawURL = Self.string(from: match, at: 1, in: linkText)
                                let attachment = makePlainLinkAttachment(url: rawURL)
                                result.append(attachment)

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
                        if let endIndex = text[index...].range(of: "]]")?.upperBound {
                            let imageText = String(text[index..<endIndex])
                            if let regex = AttachmentMarkup.imageRegex,
                                let match = regex.firstMatch(
                                    in: imageText,
                                    options: [],
                                    range: NSRange(location: 0, length: imageText.utf16.count)
                                )
                            {
                                let filename = Self.string(from: match, at: 1, in: imageText)
                                
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

                                imageCounter += 1
                                let attachment = makeImageAttachment(
                                    filename: filename,
                                    imageNumber: imageCounter
                                )
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
                    } else if text[index...].hasPrefix("[[color|") {
                        let prefixLen = "[[color|".count
                        let afterPrefix = text.index(index, offsetBy: prefixLen)
                        if text.distance(from: afterPrefix, to: text.endIndex) >= 8 {
                            let hexEnd = text.index(afterPrefix, offsetBy: 6)
                            let hex = String(text[afterPrefix..<hexEnd])
                            if text[hexEnd...].hasPrefix("]]") {
                                let contentStart = text.index(hexEnd, offsetBy: 2)
                                if let closingRange = text[contentStart...].range(of: "[[/color]]") {
                                    let coloredText = String(text[contentStart..<closingRange.lowerBound])
                                    var attrs = Self.baseTypingAttributes(for: currentColorScheme)
                                    attrs[.foregroundColor] = TextFormattingManager.nsColorFromHex(hex)
                                    attrs[TextFormattingManager.customTextColorKey] = true
                                    result.append(NSAttributedString(string: coloredText, attributes: attrs))
                                    index = closingRange.upperBound
                                    lastWasWebClip = false
                                    continue
                                }
                            }
                        }
                        // Malformed -- fall through to single-char handler
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

            // Paragraph style for web clip attachments — matches base style so line
            // heights stay consistent whether the clip is inline or on its own line.
            static func webClipParagraphStyle() -> NSParagraphStyle {
                return baseParagraphStyle()
            }
            
            static func imageTagVerticalOffset(for height: CGFloat) -> CGFloat {
                let offset = (textFont.capHeight - height) / 2
                return offset
            }

            private static func nsColorToHex(_ color: NSColor) -> String {
                let c = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? color
                return String(format: "%02x%02x%02x",
                              Int(round(c.redComponent * 255)),
                              Int(round(c.greenComponent * 255)),
                              Int(round(c.blueComponent * 255)))
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

        /// Set during paste operations so the coordinator can skip the typing animation.
        var isPasting = false

        override func paste(_ sender: Any?) {
            isPasting = true

            let pastedText = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isURL = Self.isLikelyURL(pastedText)
            let beforeLocation = selectedRange().location

            super.paste(sender)
            isPasting = false

            if isURL && !pastedText.isEmpty {
                let afterLocation = selectedRange().location
                let pastedLength = afterLocation - beforeLocation
                if pastedLength > 0 {
                    let pastedRange = NSRange(location: beforeLocation, length: pastedLength)

                    // Style the pasted URL with blue text
                    textStorage?.addAttribute(
                        .foregroundColor, value: NSColor.controlAccentColor, range: pastedRange)

                    // Calculate position for the option menu
                    if let layoutManager = layoutManager, let textContainer = textContainer {
                        let glyphRange = layoutManager.glyphRange(
                            forCharacterRange: pastedRange, actualCharacterRange: nil)
                        let rect = layoutManager.boundingRect(
                            forGlyphRange: glyphRange, in: textContainer)
                        let adjustedRect = CGRect(
                            x: rect.origin.x + textContainerOrigin.x,
                            y: rect.origin.y + textContainerOrigin.y,
                            width: rect.width,
                            height: rect.height
                        )

                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .urlPasteDetected,
                                object: [
                                    "url": pastedText,
                                    "range": NSValue(range: pastedRange),
                                    "rect": NSValue(rect: adjustedRect),
                                ] as [String: Any]
                            )
                        }
                    }
                }
            }
        }

        private static func isLikelyURL(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else {
                return false
            }
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return true }
            let domainPattern = #"^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+(/.*)?$"#
            return trimmed.range(of: domainPattern, options: .regularExpression) != nil
        }

        override func pasteAsPlainText(_ sender: Any?) {
            isPasting = true
            super.pasteAsPlainText(sender)
            isPasting = false
        }

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

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "z" {
                undoManager?.undo()
                return true
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
               event.charactersIgnoringModifiers == "z" {
                undoManager?.redo()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func insertNewline(_ sender: Any?) {
            if actionDelegate?.handleReturn(in: self) == true { return }
            super.insertNewline(sender)
        }

        override func keyDown(with event: NSEvent) {
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
        private let size = NSSize(width: 18, height: 18)

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
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)

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

    // URL paste option menu notifications
    static let urlPasteDetected = Notification.Name("URLPasteDetected")
    static let urlPasteSelectMention = Notification.Name("URLPasteSelectMention")
    static let urlPasteSelectPlainLink = Notification.Name("URLPasteSelectPlainLink")
    static let urlPasteDismiss = Notification.Name("URLPasteDismiss")

    // In-note search notifications
    static let showInNoteSearch = Notification.Name("ShowInNoteSearch")
    static let highlightSearchMatches = Notification.Name("HighlightSearchMatches")
    static let clearSearchHighlights = Notification.Name("ClearSearchHighlights")

    // Settings
    static let openSettings = Notification.Name("openSettings")
}
