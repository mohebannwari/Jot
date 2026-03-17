//
//  TodoRichTextEditor.swift
//  Jot
//
//  Rebuilt rich text editor that keeps todo checkboxes aligned,
//  clickable, and in sync with serialized markup.
//

import SwiftUI
import AppKit


struct TodoRichTextEditor: View {
    @Binding var text: String
    var focusRequestID: UUID?
    var editorInstanceID: UUID?
    var onToolbarAction: ((EditTool) -> Void)?
    var onCommandMenuSelection: ((EditTool) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    private let baseBottomInset: CGFloat = 0

    var availableNotes: [NotePickerItem] = []
    var onNavigateToNote: ((UUID) -> Void)?

    init(
        text: Binding<String>,
        focusRequestID: UUID? = nil,
        editorInstanceID: UUID? = nil,
        onToolbarAction: ((EditTool) -> Void)? = nil,
        onCommandMenuSelection: ((EditTool) -> Void)? = nil,
        availableNotes: [NotePickerItem] = [],
        onNavigateToNote: ((UUID) -> Void)? = nil
    ) {
        self._text = text
        self.focusRequestID = focusRequestID
        self.editorInstanceID = editorInstanceID
        self.onToolbarAction = onToolbarAction
        self.onCommandMenuSelection = onCommandMenuSelection
        self.availableNotes = availableNotes
        self.onNavigateToNote = onNavigateToNote
    }


    // Command menu state (triggered by "/" character)
    @State private var showCommandMenu = false
    @State private var commandMenuRevealed = false
    @State private var commandMenuPosition: CGPoint = .zero
    @State private var commandMenuSelectedIndex = 0
    @State private var commandSlashLocation: Int = -1
    @State private var commandMenuFilterText = ""

    // Note picker state (triggered by "@" character)
    @State private var showNotePicker = false
    @State private var notePickerRevealed = false
    @State private var notePickerPosition: CGPoint = .zero
    @State private var notePickerSelectedIndex = 0
    @State private var notePickerAtLocation: Int = -1
    @State private var notePickerFilterText = ""
    @State private var notePickerItems: [NotePickerItem] = []

    private var filteredNotePickerItems: [NotePickerItem] {
        if notePickerFilterText.isEmpty {
            return notePickerItems
        }
        return notePickerItems.filter {
            $0.title.localizedCaseInsensitiveContains(notePickerFilterText)
        }
    }

    // URL paste option menu state
    @State private var showURLPasteMenu = false
    @State private var urlPasteMenuPosition: CGPoint = .zero
    @State private var urlPasteURL: String = ""
    @State private var urlPasteRange: NSRange = NSRange(location: 0, length: 0)

    // Code paste option menu state
    @State private var showCodePasteMenu = false
    @State private var codePasteMenuPosition: CGPoint = .zero
    @State private var codePasteTextRect: CGRect = .zero
    @State private var codePasteCode: String = ""
    @State private var codePasteRange: NSRange = NSRange(location: 0, length: 0)
    @State private var codePasteLanguage: String = "plaintext"

    static let commandMenuActions: [EditTool] = [.imageUpload, .fileLink, .voiceRecord, .link, .todo, .bulletList, .numberedList, .blockQuote, .codeBlock, .callout, .divider, .table]
    static let commandMenuOuterPadding: CGFloat = CommandMenuLayout.outerPadding
    static let commandMenuHorizontalPadding = commandMenuOuterPadding * 2
    static let commandMenuVerticalPadding = commandMenuOuterPadding * 2
    static let commandMenuTotalWidth: CGFloat =
        CommandMenuLayout.width + commandMenuHorizontalPadding

    private var filteredCommandMenuTools: [EditTool] {
        if commandMenuFilterText.isEmpty {
            return Self.commandMenuActions
        }
        return Self.commandMenuActions.filter {
            $0.name.localizedCaseInsensitiveContains(commandMenuFilterText)
        }
    }

    /// When true, the text view shows arrow cursor instead of I-beam.
    /// Set by ContentView when a full-screen panel overlay is open.
    static var isPanelOverlayActive: Bool {
        get { InlineNSTextView.isPanelOverlayActive }
        set { InlineNSTextView.isPanelOverlayActive = newValue }
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

    private var editorWithOverlays: some View {
        Group {
                TodoEditorRepresentable(
                    text: $text,
                    colorScheme: colorScheme,
                    bottomInset: bottomInset,
                    focusRequestID: focusRequestID,
                    editorInstanceID: editorInstanceID,
                    onNavigateToNote: onNavigateToNote
                )
        }
        .frame(maxWidth: .infinity)  // Natural height based on content
        .background(Color.clear)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showCommandMenu && !filteredCommandMenuTools.isEmpty {
                    // Tap-outside scrim to dismiss
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissCommandMenu() }
                        .zIndex(999)

                    CommandMenu(
                        tools: filteredCommandMenuTools,
                        selectedIndex: $commandMenuSelectedIndex,
                        isRevealed: $commandMenuRevealed,
                        onSelect: { tool in handleCommandMenuSelection(tool) }
                    )
                    .offset(
                        x: clampedCommandMenuPosition(for: geometry.size).x,
                        y: clampedCommandMenuPosition(for: geometry.size).y
                    )
                    .allowsHitTesting(commandMenuRevealed)
                    .transition(.identity)
                    .zIndex(1000)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showNotePicker && !filteredNotePickerItems.isEmpty {
                    NotePickerMenu(
                        notes: filteredNotePickerItems,
                        selectedIndex: $notePickerSelectedIndex,
                        isRevealed: $notePickerRevealed,
                        onSelect: { note in handleNotePickerSelection(note) }
                    )
                    .offset(
                        x: clampedNotePickerPosition(for: geometry.size).x,
                        y: clampedNotePickerPosition(for: geometry.size).y
                    )
                    .allowsHitTesting(notePickerRevealed)
                    .transition(.identity)
                    .zIndex(1001)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showURLPasteMenu {
                    URLPasteOptionMenu(
                        onMention: {
                            withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
                            InlineNSTextView.isURLPasteMenuShowing = false
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
                            InlineNSTextView.isURLPasteMenuShowing = false
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
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showCodePasteMenu {
                    CodePasteOptionMenu(
                        language: codePasteLanguage,
                        onCodeBlock: {
                            withAnimation(.smooth(duration: 0.15)) { showCodePasteMenu = false }
                            InlineNSTextView.isCodePasteMenuShowing = false
                            NotificationCenter.default.post(
                                name: .codePasteSelectCodeBlock,
                                object: [
                                    "code": codePasteCode,
                                    "range": NSValue(range: codePasteRange),
                                    "language": codePasteLanguage,
                                ] as [String: Any]
                            )
                        },
                        onPlainText: {
                            withAnimation(.smooth(duration: 0.15)) { showCodePasteMenu = false }
                            InlineNSTextView.isCodePasteMenuShowing = false
                            NotificationCenter.default.post(
                                name: .codePasteSelectPlainText,
                                object: [
                                    "range": NSValue(range: codePasteRange),
                                ] as [String: Any]
                            )
                        }
                    )
                    .offset(
                        x: clampedCodePasteMenuPosition(for: geometry.size).x,
                        y: clampedCodePasteMenuPosition(for: geometry.size).y
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
    }

    private var editorWithToolbarNotifications: some View {
        editorWithOverlays
        .onReceive(
            NotificationCenter.default.publisher(for: .todoToolbarAction)
        ) { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            NotificationCenter.default.post(name: .insertTodoInEditor, object: nil, userInfo: editorInstanceID.map { ["editorInstanceID": $0] })
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InsertWebLink"))) {
            notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if let url = notification.object as? String {
                NotificationCenter.default.post(name: .insertWebClipInEditor, object: url, userInfo: editorInstanceID.map { ["editorInstanceID": $0] })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowCommandMenu")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if let info = notification.object as? [String: Any],
                let position = info["position"] as? CGPoint,
                let slashLocation = info["slashLocation"] as? Int
            {
                commandMenuPosition = position
                commandSlashLocation = slashLocation
                commandMenuSelectedIndex = 0
                commandMenuFilterText = ""

                // Show the view in the hierarchy
                showCommandMenu = true
                // Animate the reveal (scale up from cursor + item cascade)
                withAnimation(.bouncy(duration: 0.45)) {
                    commandMenuRevealed = true
                }

                InlineNSTextView.isCommandMenuShowing = true
                InlineNSTextView.commandSlashLocation = slashLocation
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HideCommandMenu")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            dismissCommandMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuFilterUpdate")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            guard showCommandMenu else { return }
            let filter = (notification.object as? String) ?? ""
            commandMenuFilterText = filter
            commandMenuSelectedIndex = 0

            // Auto-hide if no matches
            let matches = Self.commandMenuActions.filter {
                $0.name.localizedCaseInsensitiveContains(filter)
            }
            if !filter.isEmpty && matches.isEmpty {
                dismissCommandMenu()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuNavigateUp")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if showCommandMenu && commandMenuSelectedIndex > 0 {
                commandMenuSelectedIndex -= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuNavigateDown")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            let maxIndex = max(0, filteredCommandMenuTools.count - 1)
            if showCommandMenu && commandMenuSelectedIndex < maxIndex {
                commandMenuSelectedIndex += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandMenuSelect")))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if showCommandMenu {
                let tools = filteredCommandMenuTools
                if commandMenuSelectedIndex < tools.count {
                    handleCommandMenuSelection(tools[commandMenuSelectedIndex])
                }
            }
        }
    }

    private var editorWithPickerNotifications: some View {
        editorWithToolbarNotifications
        // Note picker notifications (triggered by "@")
        .onReceive(NotificationCenter.default.publisher(for: .showNotePicker))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if let info = notification.object as? [String: Any],
                let position = info["position"] as? CGPoint,
                let atLocation = info["atLocation"] as? Int
            {
                // Filter out the current note from the picker list
                let notes = availableNotes
                guard !notes.isEmpty else { return }

                notePickerPosition = position
                notePickerAtLocation = atLocation
                notePickerSelectedIndex = 0
                notePickerFilterText = ""
                notePickerItems = notes

                showNotePicker = true
                withAnimation(.bouncy(duration: 0.45)) {
                    notePickerRevealed = true
                }

                InlineNSTextView.isNotePickerShowing = true
                InlineNSTextView.notePickerAtLocation = atLocation
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hideNotePicker))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            dismissNotePicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notePickerFilterUpdate))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            guard showNotePicker else { return }
            let filter = (notification.object as? String) ?? ""
            notePickerFilterText = filter
            notePickerSelectedIndex = 0

            let matches = notePickerItems.filter {
                $0.title.localizedCaseInsensitiveContains(filter)
            }
            if !filter.isEmpty && matches.isEmpty {
                dismissNotePicker()
                // Notify NoteDetailView to re-enable scroll (.scrollDisabled)
                NotificationCenter.default.post(
                    name: .hideNotePicker,
                    object: nil,
                    userInfo: editorInstanceID.map { ["editorInstanceID": $0] }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notePickerNavigateUp))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if showNotePicker && notePickerSelectedIndex > 0 {
                notePickerSelectedIndex -= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notePickerNavigateDown))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            let maxIndex = max(0, filteredNotePickerItems.count - 1)
            if showNotePicker && notePickerSelectedIndex < maxIndex {
                notePickerSelectedIndex += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notePickerSelect))
        { notification in
            if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID { return }
            if showNotePicker {
                let notes = filteredNotePickerItems
                if notePickerSelectedIndex < notes.count {
                    handleNotePickerSelection(notes[notePickerSelectedIndex])
                }
            }
        }
    }

    private var editorWithURLPasteNotifications: some View {
        editorWithPickerNotifications
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
            // Total width = inner frame (160) + outer padding (12 * 2)
            let menuTotalWidth: CGFloat = 160 + CommandMenuLayout.outerPadding * 2
            let menuX = rect.midX - menuTotalWidth / 2
            let menuY = rect.maxY + 8

            urlPasteMenuPosition = CGPoint(x: max(0, menuX), y: menuY)

            withAnimation(.smooth(duration: 0.2)) {
                showURLPasteMenu = true
            }
            InlineNSTextView.isURLPasteMenuShowing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteDismiss)) { _ in
            if showURLPasteMenu {
                withAnimation(.smooth(duration: 0.15)) { showURLPasteMenu = false }
                InlineNSTextView.isURLPasteMenuShowing = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .codePasteDetected)) { notification in
            guard let info = notification.object as? [String: Any],
                  let code = info["code"] as? String,
                  let rangeValue = info["range"] as? NSValue,
                  let rectValue = info["rect"] as? NSValue,
                  let language = info["language"] as? String else { return }

            let range = rangeValue.rangeValue
            let rect = rectValue.rectValue

            codePasteCode = code
            codePasteRange = range
            codePasteLanguage = language
            codePasteTextRect = rect

            let menuTotalWidth: CGFloat = 220 + CommandMenuLayout.outerPadding * 2
            let menuX = rect.midX - menuTotalWidth / 2
            let menuY = rect.maxY + 8

            codePasteMenuPosition = CGPoint(x: max(0, menuX), y: menuY)

            withAnimation(.smooth(duration: 0.2)) {
                showCodePasteMenu = true
            }
            InlineNSTextView.isCodePasteMenuShowing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .codePasteDismiss)) { _ in
            if showCodePasteMenu {
                withAnimation(.smooth(duration: 0.15)) { showCodePasteMenu = false }
                InlineNSTextView.isCodePasteMenuShowing = false
            }
        }
    }

    var body: some View {
        editorWithURLPasteNotifications
    }

    // MARK: - Command Menu Handlers

    /// Two-phase dismiss: reverse entrance animation, then remove from hierarchy
    private func dismissCommandMenu() {
        // Guard against re-entry: the .hideCommandMenu notification handler
        // at line 1028 also calls this function, so bail if already dismissed.
        guard showCommandMenu || InlineNSTextView.isCommandMenuShowing else { return }

        // Immediately stop keyboard interception
        InlineNSTextView.isCommandMenuShowing = false
        InlineNSTextView.commandSlashLocation = -1

        // Notify NoteDetailView to re-enable scroll (deferred to avoid
        // re-entrant SwiftUI state updates during the current transaction)
        let eidInfo: [String: Any]? = editorInstanceID.map { ["editorInstanceID": $0] }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .hideCommandMenu,
                object: nil,
                userInfo: eidInfo
            )
        }

        // Phase 1: animate reverse entrance (scale down to cursor, items cascade out)
        withAnimation(.smooth(duration: 0.25)) {
            commandMenuRevealed = false
        }

        // Phase 2: remove from hierarchy after exit animation settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !self.commandMenuRevealed else { return }
            self.showCommandMenu = false
            self.commandSlashLocation = -1
            self.commandMenuFilterText = ""
        }
    }

    private func handleCommandMenuSelection(_ tool: EditTool) {
        let filterLength = commandMenuFilterText.count
        let slashLoc = commandSlashLocation

        dismissCommandMenu()

        NotificationCenter.default.post(
            name: .applyCommandMenuTool,
            object: ["tool": tool, "slashLocation": slashLoc, "filterLength": filterLength],
            userInfo: editorInstanceID.map { ["editorInstanceID": $0] }
        )

        if let onCommandMenuSelection {
            onCommandMenuSelection(tool)
        }
    }

    private func clampedCommandMenuPosition(for containerSize: CGSize) -> CGPoint {
        let contentHeight = CommandMenuLayout.idealHeight(for: filteredCommandMenuTools.count)
        let totalHeight = contentHeight + Self.commandMenuVerticalPadding
        let maxX = max(0, containerSize.width - Self.commandMenuTotalWidth)
        let maxY = max(0, containerSize.height - totalHeight)
        let clampedX = min(max(commandMenuPosition.x, 0), maxX)
        let clampedY = min(max(commandMenuPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

    private func clampedURLPasteMenuPosition(for containerSize: CGSize) -> CGPoint {
        let menuWidth: CGFloat = 160 + CommandMenuLayout.outerPadding * 2
        let menuHeight: CGFloat = 68 + CommandMenuLayout.outerPadding * 2
        let maxX = max(0, containerSize.width - menuWidth)
        let maxY = max(0, containerSize.height - menuHeight)
        let clampedX = min(max(urlPasteMenuPosition.x, 0), maxX)
        let clampedY = min(max(urlPasteMenuPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

    private func clampedCodePasteMenuPosition(for containerSize: CGSize) -> CGPoint {
        let menuWidth: CGFloat = 220 + CommandMenuLayout.outerPadding * 2
        let menuHeight: CGFloat = 68 + CommandMenuLayout.outerPadding * 2
        let maxX = max(0, containerSize.width - menuWidth)
        let clampedX = min(max(codePasteMenuPosition.x, 0), maxX)

        // If the popup would overflow below the viewport, flip it above the pasted text
        var y = codePasteMenuPosition.y
        if y + menuHeight > containerSize.height {
            y = codePasteTextRect.minY - menuHeight - 8
        }
        let clampedY = min(max(y, 0), max(0, containerSize.height - menuHeight))
        return CGPoint(x: clampedX, y: clampedY)
    }

    // MARK: - Note Picker Helpers

    private func dismissNotePicker() {
        InlineNSTextView.isNotePickerShowing = false
        InlineNSTextView.notePickerAtLocation = -1

        withAnimation(.smooth(duration: 0.25)) {
            notePickerRevealed = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !self.notePickerRevealed else { return }
            self.showNotePicker = false
            self.notePickerAtLocation = -1
            self.notePickerFilterText = ""
            self.notePickerItems = []
        }
    }

    private func handleNotePickerSelection(_ note: NotePickerItem) {
        let filterLength = notePickerFilterText.count
        let atLoc = notePickerAtLocation

        dismissNotePicker()

        // Notify NoteDetailView to re-enable scroll (.scrollDisabled)
        NotificationCenter.default.post(
            name: .hideNotePicker,
            object: nil,
            userInfo: editorInstanceID.map { ["editorInstanceID": $0] }
        )

        NotificationCenter.default.post(
            name: .applyNotePickerSelection,
            object: [
                "noteID": note.id.uuidString,
                "noteTitle": note.title,
                "atLocation": atLoc,
                "filterLength": filterLength,
            ] as [String: Any],
            userInfo: editorInstanceID.map { ["editorInstanceID": $0] }
        )
    }

    private func clampedNotePickerPosition(for containerSize: CGSize) -> CGPoint {
        let outerPadding = NotePickerLayout.outerPadding * 2
        let contentHeight = NotePickerLayout.idealHeight(for: filteredNotePickerItems.count)
        let totalHeight = contentHeight + outerPadding
        let totalWidth = NotePickerLayout.width + outerPadding
        let maxX = max(0, containerSize.width - totalWidth)
        let maxY = max(0, containerSize.height - totalHeight)
        let clampedX = min(max(notePickerPosition.x, 0), maxX)
        let clampedY = min(max(notePickerPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

}

// MARK: - URL Paste Option Menu

struct URLPasteOptionMenu: View {
    let onMention: () -> Void
    let onPasteAsURL: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var focusedOption: Int = 0
    @State private var hoveredOption: Int?

    private let optionCount = 2

    private var activeOption: Int {
        hoveredOption ?? focusedOption
    }

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
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteNavigateUp)) { _ in
            withAnimation(.smooth(duration: 0.1)) {
                hoveredOption = nil
                focusedOption = max(focusedOption - 1, 0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteNavigateDown)) { _ in
            withAnimation(.smooth(duration: 0.1)) {
                hoveredOption = nil
                focusedOption = min(focusedOption + 1, optionCount - 1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .urlPasteSelectFocused)) { _ in
            let selected = activeOption
            if selected == 0 {
                onMention()
            } else {
                onPasteAsURL()
            }
        }
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
                activeOption == index
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
        activeOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("IconSecondaryColor")
    }

    private func textColor(for index: Int) -> Color {
        activeOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("PrimaryTextColor")
    }
}

struct CodePasteOptionMenu: View {
    let language: String
    let onCodeBlock: () -> Void
    let onPlainText: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var focusedOption: Int = 0
    @State private var hoveredOption: Int?

    private let optionCount = 2

    private var activeOption: Int {
        hoveredOption ?? focusedOption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            optionRow(
                iconName: "IconCode",
                label: "Code Block (\(CodeBlockData.displayName(for: language)))",
                index: 0,
                action: onCodeBlock
            )
            optionRow(
                iconName: "IconFileText",
                label: "Plain Text",
                index: 1,
                action: onPlainText
            )
        }
        .padding(CommandMenuLayout.outerPadding)
        .frame(width: 220)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .onReceive(NotificationCenter.default.publisher(for: .codePasteNavigateUp)) { _ in
            withAnimation(.smooth(duration: 0.1)) {
                hoveredOption = nil
                focusedOption = max(focusedOption - 1, 0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .codePasteNavigateDown)) { _ in
            withAnimation(.smooth(duration: 0.1)) {
                hoveredOption = nil
                focusedOption = min(focusedOption + 1, optionCount - 1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .codePasteSelectFocused)) { _ in
            if activeOption == 0 {
                onCodeBlock()
            } else {
                onPlainText()
            }
        }
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
                activeOption == index
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
        activeOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("IconSecondaryColor")
    }

    private func textColor(for index: Int) -> Color {
        activeOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("PrimaryTextColor")
    }
}

