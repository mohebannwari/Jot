//
//  NoteMetadataSection.swift
//  Jot
//
//  Side-panel properties view showing note metadata (created date, tags,
//  todos, links, attachments, mentioned notes, backlinks). Rendered as its own split-sibling pane
//  in ContentView: it inherits its glass chrome and corner radius from
//  `propertiesPanelSlot` (which uses `DetailPaneChromeBackgroundView`), so this
//  view paints no background of its own — that would create glass-on-glass.
//  Scroll content fades to transparent at the bottom via `.mask(...)`, letting
//  the pane chrome show through cleanly with no extra translucent layer.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

struct NoteMetadataSection: View {
    let note: Note
    var folder: Folder?
    var backlinks: [BacklinkItem] = []
    /// When set, replaces serialized `[[notelink|…|title]]` titles with the current note title from the library (or falls back to the serialized title if the note is missing).
    var resolveMentionTitle: ((UUID, String) -> String)? = nil
    var onUpdateTags: (([String]) -> Void)?
    /// When set, user can remove individual AI tag chips; empty list hides the row.
    var onUpdateAIGeneratedTags: (([String]) -> Void)?
    var onToggleTodo: ((Int) -> Void)?
    var onNavigateToNote: ((UUID) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var isTodoExpanded = false
    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var tagFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager

    // MARK: - Content-Derived Metadata (cached, updated on content change)

    private struct ParsedTodo: Identifiable {
        let id: Int // line index in content
        let text: String
        let isCompleted: Bool
    }

    @State private var cachedTodos: [ParsedTodo] = []
    @State private var cachedLinks: [ParsedLink] = []
    @State private var cachedAttachments: [ParsedAttachment] = []
    /// Outgoing `[[notelink|targetUUID|title]]` targets (deduped), refreshed from `note.content`.
    @State private var cachedMentions: [(UUID, String)] = []

    private static func parseTodos(from content: String) -> [ParsedTodo] {
        var results: [ParsedTodo] = []
        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[x] ") {
                results.append(ParsedTodo(id: index, text: String(trimmed.dropFirst(4)), isCompleted: true))
            } else if trimmed.hasPrefix("[ ] ") {
                results.append(ParsedTodo(id: index, text: String(trimmed.dropFirst(4)), isCompleted: false))
            } else if trimmed == "[x]" {
                results.append(ParsedTodo(id: index, text: "", isCompleted: true))
            } else if trimmed == "[ ]" {
                results.append(ParsedTodo(id: index, text: "", isCompleted: false))
            }
        }
        return results
    }

    private struct ParsedLink: Identifiable {
        let id: Int
        let url: String
        let domain: String
        let isWebClip: Bool
    }

    private static func parseLinks(from content: String, cleanDomain: (String) -> String) -> [ParsedLink] {
        var results: [ParsedLink] = []

        if content.contains("[[webclip|") {
            let parts = content.components(separatedBy: "[[webclip|")
            for i in 1..<parts.count {
                let inner = parts[i].components(separatedBy: "]]").first ?? ""
                let fields = inner.components(separatedBy: "|")
                if fields.count >= 3 {
                    results.append(ParsedLink(id: results.count, url: fields[2], domain: cleanDomain(fields[2]), isWebClip: true))
                }
            }
        }

        if content.contains("[[link|") {
            let parts = content.components(separatedBy: "[[link|")
            for i in 1..<parts.count {
                let url = parts[i].components(separatedBy: "]]").first ?? ""
                if !url.isEmpty {
                    results.append(ParsedLink(id: results.count, url: url, domain: cleanDomain(url), isWebClip: false))
                }
            }
        }

        return results
    }

    private struct ParsedAttachment: Identifiable {
        let id: Int
        /// Filename on disk under `ImageStorageManager` or `FileAttachmentStorageManager`.
        let storedFilename: String
        let displayLabel: String
        let isImage: Bool
    }

    private static func parseAttachments(from content: String) -> [ParsedAttachment] {
        var results: [ParsedAttachment] = []

        if content.contains("[[file|") {
            let parts = content.components(separatedBy: "[[file|")
            for i in 1..<parts.count {
                let inner = parts[i].components(separatedBy: "]]").first ?? ""
                let fields = inner.components(separatedBy: "|")
                // [[file|typeId|storedFilename|originalName(|viewMode)]]
                if fields.count >= 3 {
                    let stored = fields[1]
                    let label = fields[2]
                    results.append(
                        ParsedAttachment(id: results.count, storedFilename: stored, displayLabel: label, isImage: false)
                    )
                }
            }
        }

        if content.contains("[[image|||") {
            let parts = content.components(separatedBy: "[[image|||")
            for i in 1..<parts.count {
                let raw = parts[i].components(separatedBy: "]]").first ?? "image"
                // [[image|||foo.jpg|||0.3300]] — only the first segment is the stored filename.
                let stored = raw.components(separatedBy: "|||").first ?? raw
                results.append(
                    ParsedAttachment(id: results.count, storedFilename: stored, displayLabel: stored, isImage: true)
                )
            }
        }

        return results
    }

    private func reparseContent() {
        cachedTodos = Self.parseTodos(from: note.content)
        cachedLinks = Self.parseLinks(from: note.content, cleanDomain: cleanDomain)
        cachedAttachments = Self.parseAttachments(from: note.content)
        cachedMentions = OutgoingNotelinkScanner.outgoingNotelinks(
            in: note.content,
            excludingNoteID: note.id
        )
    }

    // MARK: - Helpers

    private func cleanDomain(_ urlString: String) -> String {
        urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .components(separatedBy: "/").first ?? urlString
    }

    /// Opens the stored image or file attachment in the user’s default app (same intent as the pill affordance).
    private func openAttachmentInWorkspace(_ attachment: ParsedAttachment) {
        #if os(macOS)
        let url: URL? =
            attachment.isImage
            ? ImageStorageManager.shared.getImageURL(for: attachment.storedFilename)
            : FileAttachmentStorageManager.shared.fileURL(for: attachment.storedFilename)
        if let url {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// Pill/panel surface shared by tags, AI tags, and todos so all properties-panel
    /// translucent surfaces read identically against the glass properties pane.
    /// `SurfaceTranslucentColor` = 6% black (light) / 6% white (dark).
    private var tagPillContainerColor: Color {
        Color("SurfaceTranslucentColor")
    }

    private var todoContainerColor: Color {
        tagPillContainerColor
    }

    // MARK: - Date Formatting

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd. MMM yyyy 'at' HH:mm"
        return f
    }()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Close button row (left-aligned)
            HStack {
                Button { onDismiss?() } label: {
                    Image(systemName: "xmark")
                        .font(FontManager.uiMicro(weight: .regular).font)
                        .foregroundColor(Color("IconSecondaryColor"))
                        .frame(width: 22, height: 22)
                        .background(Color("SurfaceTranslucentColor"), in: Circle())
                }
                .buttonStyle(.plain)
                .propertiesPanelPointingHandCursor()

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 18)

            // Title
            Text("Properties")
                .jotUI(FontManager.uiPro(size: 14, weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: -4) {
                    // Created
                    propertyRow(label: "Created") {
                        Text(Self.absoluteFormatter.string(from: note.createdAt))
                            .jotUI(FontManager.uiLabel4())
                            .foregroundColor(Color("PrimaryTextColor"))
                    }

                    // Folder
                    propertyRow(label: "Folder") {
                        if let folder {
                            let pillFg: Color = (colorScheme == .dark && folder.folderColorNeedsDarkForeground)
                                ? .black : .white

                            HStack(spacing: 4) {
                                Image("IconFolder1")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(pillFg)
                                    .frame(width: 15, height: 15)

                                Text(folder.name)
                                    .jotUI(FontManager.uiLabel5(weight: .regular))
                                    .foregroundColor(pillFg)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(folder.folderDisplayColor(for: colorScheme), in: Capsule())
                        } else {
                            noneText
                        }
                    }

                    // Tags
                    propertyRow(label: "Tags") {
                        tagsValue
                    }

                    if !note.aiGeneratedTags.isEmpty {
                        aiGeneratedTagsPropertyRow
                    }

                    // Todos
                    propertyRow(label: "Todos") {
                        VStack(alignment: .leading, spacing: 8) {
                            todosCounterPill

                            if isTodoExpanded && !cachedTodos.isEmpty {
                                expandedTodoList
                            }
                        }
                    }

                    // Links
                    propertyRow(label: "Links") {
                        linksValue
                    }

                    // Attachments
                    propertyRow(label: "Attachments") {
                        attachmentsValue
                    }

                    // Mentioned notes (outgoing notelinks in this note’s body)
                    propertyRow(label: "Mentioned Notes") {
                        mentionedNotesValue
                    }

                    // Referenced By (backlinks; always shown — None when empty)
                    propertyRow(label: "Referenced By") {
                        referencedByValue
                    }
                }
                .padding(.bottom, 180)
            }
            // Mask the scroll content so it fades to transparent over the bottom 180pt.
            // The pane chrome (provided by `propertiesPanelSlot`) shows through cleanly
            // with no extra glass or tint layer painted on top.
            .mask(scrollContentFadeMask)
        }
        // No self-applied glass or tint: the panel inherits its surface from
        // `DetailPaneChromeBackgroundView` in `propertiesPanelSlot`, exactly like the detail pane.
        .onAppear { reparseContent() }
        .onChange(of: note.id) { reparseContent() }
        .onChange(of: note.content) { reparseContent() }
    }

    /// Vertical mask: fully opaque above the bottom strip, easing to transparent over the last 180pt.
    private var scrollContentFadeMask: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white)
            LinearGradient(
                gradient: Gradient(stops: (0...40).map { i in
                    let t = Double(i) / 40.0
                    let eased = t * t * t * (t * (t * 6 - 15) + 10)
                    return .init(color: Color.white.opacity(1 - eased), location: t)
                }),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
        }
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func propertyRow<Value: View>(
        label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        // Gutter between label and value columns (`sm` on the canonical spacing scale).
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Label column — fixed width, aligned with header
            Text(label)
                .jotUI(FontManager.uiLabel4())
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.vertical, 8)
                .frame(width: 100, alignment: .leading)

            // Value column — flex
            value()
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    // MARK: - Tags (Interactive)

    /// Same translucent capsule treatment as AI-generated tag chips (see `tagPillContainerColor`).
    @ViewBuilder
    private var tagsValue: some View {
        FlowLayout(spacing: 6) {
            ForEach(note.tags, id: \.self) { tag in
                // One tappable pill (matches link/attachment affordance; shows hand cursor on the whole chip).
                Button {
                    onUpdateTags?(note.tags.filter { $0 != tag })
                } label: {
                    HStack(spacing: 4) {
                        Text(tag)
                            .jotUI(FontManager.uiLabel5(weight: .regular))
                            .foregroundColor(Color("SecondaryTextColor"))

                        Image("IconCrossMedium")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundColor(Color("SecondaryTextColor").opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tagPillContainerColor, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .propertiesPanelPointingHandCursor()
            }

            // Add tag: inline field or plus button
            if isAddingTag {
                TextField("tag name", text: $newTagText)
                    .jotUI(FontManager.uiLabel5(weight: .regular))
                    .textFieldStyle(.plain)
                    .frame(width: 80)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tagPillContainerColor, in: Capsule())
                    .foregroundColor(Color("PrimaryTextColor"))
                    .focused($tagFieldFocused)
                    .onSubmit { commitTag() }
                    .onKeyPress(.escape) {
                        cancelTagInput()
                        return .handled
                    }
            } else {
                Button {
                    withAnimation(.jotSpring) {
                        isAddingTag = true
                        tagFieldFocused = true
                    }
                } label: {
                    Image("IconPlusSmall")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundColor(Color("IconSecondaryColor"))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 2)
                        .alignmentGuide(.firstTextBaseline) { d in
                            d[VerticalAlignment.center] + 3
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .propertiesPanelPointingHandCursor()
            }
        }
    }

    private func commitTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !note.tags.contains(trimmed) {
            var updated = note.tags
            updated.append(trimmed)
            onUpdateTags?(updated)
        }
        newTagText = ""
        isAddingTag = false
    }

    private func cancelTagInput() {
        newTagText = ""
        isAddingTag = false
    }

    /// "AI generated" on one line, "tags" on the next — same column width as other property labels.
    private var aiGeneratedTagsPropertyRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI generated")
                    .jotUI(FontManager.uiLabel4())
                    .foregroundColor(Color("SecondaryTextColor"))
                Text("tags")
                    .jotUI(FontManager.uiLabel4())
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            .padding(.vertical, 8)
            .frame(width: 100, alignment: .leading)

            aiGeneratedTagsChips
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    /// Dismissable chips: same surface as manual tags (`tagPillContainerColor`).
    @ViewBuilder
    private var aiGeneratedTagsChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(note.aiGeneratedTags, id: \.self) { tag in
                Button {
                    let next = note.aiGeneratedTags.filter { $0 != tag }
                    onUpdateAIGeneratedTags?(next)
                } label: {
                    HStack(spacing: 4) {
                        Text(tag)
                            .jotUI(FontManager.uiLabel5(weight: .regular))
                            .foregroundColor(Color("SecondaryTextColor"))

                        Image("IconCrossMedium")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundColor(Color("SecondaryTextColor").opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tagPillContainerColor, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .propertiesPanelPointingHandCursor()
            }
        }
    }

  // MARK: - Todos

    @ViewBuilder
    private var todosCounterPill: some View {
        let todos = cachedTodos
        let completed = todos.filter(\.isCompleted).count
        let total = todos.count

        if total == 0 {
            noneText
        } else {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { isTodoExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    todoProgressCircle(completed: completed, total: total)
                        .frame(width: 14, height: 14)
                        .padding(.trailing, 4)

                    Text("\(completed)/\(total)")
                        .jotUI(FontManager.uiLabel5(weight: .regular))
                        .foregroundColor(Color("PrimaryTextColor"))

                    Image("IconChevronRightMedium")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundColor(Color("IconSecondaryColor"))
                        .rotationEffect(.degrees(isTodoExpanded ? 90 : 0))
                }
                .padding(.leading, 4)
                .padding(.trailing, 2)
                .padding(.vertical, 4)
                .background(todoContainerColor, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .propertiesPanelPointingHandCursor()
        }
    }

    @ViewBuilder
    private var expandedTodoList: some View {
        let todos = cachedTodos
        VStack(alignment: .leading, spacing: 8) {
            ForEach(todos) { todo in
                Button {
                    onToggleTodo?(todo.id)
                } label: {
                    HStack(alignment: .center, spacing: 6) {
                        todoCheckbox(isCompleted: todo.isCompleted)
                            .frame(width: 16, height: 16)

                        Text(todo.text)
                            .jotUI(FontManager.uiLabel5(weight: .regular))
                            .foregroundColor(Color("PrimaryTextColor"))
                            .strikethrough(todo.isCompleted, color: Color("PrimaryTextColor").opacity(0.5))
                            .opacity(todo.isCompleted ? 0.5 : 1)
                    }
                }
                .buttonStyle(.plain)
                .propertiesPanelPointingHandCursor()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(todoContainerColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .compositingGroup()
        .transition(
            .asymmetric(
                insertion: .opacity
                    .combined(with: .scale(scale: 0.92, anchor: .top))
                    .combined(with: .offset(y: -12)),
                removal: .opacity
                    .combined(with: .scale(scale: 0.85, anchor: .top))
                    .combined(with: .offset(y: -20))
            )
        )
    }

    private func todoProgressCircle(completed: Int, total: Int) -> some View {
        let fraction = total > 0 ? CGFloat(completed) / CGFloat(total) : 0

        return ZStack {
            Circle()
                .stroke(Color("TodoProgressColor").opacity(colorScheme == .dark ? 0.2 : 0.35), lineWidth: 3.5)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color("TodoProgressColor"), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    @ViewBuilder
    private func todoCheckbox(isCompleted: Bool) -> some View {
        if isCompleted {
            ZStack {
                Circle()
                    .fill(Color("ButtonPrimaryBgColor"))

                Image("IconCheckmark1")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
            }
        } else {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(0.06)
                        : Color.white)

                Circle()
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.18)
                            : Color.black.opacity(0.28),
                        lineWidth: 1.5
                    )
            }
        }
    }

    // MARK: - Links (Inline Pills)

    @ViewBuilder
    private var linksValue: some View {
        let links = cachedLinks
        if links.isEmpty {
            noneText
        } else {
            FlowLayout(spacing: 4) {
                ForEach(links) { link in
                    Button {
                        if let url = URL(string: link.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 0) {
                            Image("IconChainLink")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)

                            Text(link.domain)
                                .jotUI(FontManager.uiLabel4())
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 4)

                            Image("IconArrowRightUpCircle")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                        .foregroundColor(.white) // LinkPillColor is always dark blue -- white text is forced-appearance by design
                        .padding(4)
                        .background(Color("LinkPillColor"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .propertiesPanelPointingHandCursor()
                }
            }
        }
    }

    // MARK: - Attachments (Inline Pills)

    @ViewBuilder
    private var attachmentsValue: some View {
        let attachments = cachedAttachments
        if attachments.isEmpty {
            noneText
        } else {
            FlowLayout(spacing: 4) {
                ForEach(attachments) { attachment in
                    Button {
                        openAttachmentInWorkspace(attachment)
                    } label: {
                        HStack(spacing: 4) {
                            Image("IconFileLink")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)

                            Text(attachment.displayLabel)
                                .jotUI(FontManager.uiLabel5(weight: .regular))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 160)

                            Image("IconArrowRightUpCircle")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                        .foregroundColor(Color("ButtonPrimaryTextColor"))
                        .padding(4)
                        .background(Color("ButtonPrimaryBgColor"), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .propertiesPanelPointingHandCursor()
                }
            }
        }
    }

    // MARK: - Mentioned Notes (outgoing notelinks)

    private func displayTitleForMention(noteID: UUID, serializedTitle: String) -> String {
        let resolved = resolveMentionTitle?(noteID, serializedTitle) ?? serializedTitle
        let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    @ViewBuilder
    private var mentionedNotesValue: some View {
        let mentions = cachedMentions
        if mentions.isEmpty {
            noneText
        } else {
            FlowLayout(spacing: 4) {
                ForEach(mentions, id: \.0) { noteID, serializedTitle in
                    Button {
                        onNavigateToNote?(noteID)
                    } label: {
                        HStack(spacing: 4) {
                            Text(displayTitleForMention(noteID: noteID, serializedTitle: serializedTitle))
                                .jotUI(FontManager.uiLabel5(weight: .regular))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 180)

                            Image("IconArrowRightUpCircle")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                        .foregroundColor(.black)
                        .padding(.leading, 8)
                        .padding(.trailing, 4)
                        .padding(.vertical, 4)
                        .background(Color("NotelinkPillBgColor"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .propertiesPanelPointingHandCursor()
                }
            }
        }
    }

    // MARK: - Referenced By (Backlinks)

    @ViewBuilder
    private var referencedByValue: some View {
        if backlinks.isEmpty {
            noneText
        } else {
            FlowLayout(spacing: 4) {
                ForEach(backlinks) { backlink in
                    Button {
                        onNavigateToNote?(backlink.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image("IconArrowLeftUpCircle")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)

                            Text(backlink.title)
                                .jotUI(FontManager.uiLabel5(weight: .regular))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 180)
                        }
                        .foregroundColor(.black)
                        .padding(.leading, 4)
                        .padding(.trailing, 8)
                        .padding(.vertical, 4)
                        .background(Color("NotelinkPillBgColor"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .propertiesPanelPointingHandCursor()
                }
            }
        }
    }

    // MARK: - Shared

    private var noneText: some View {
        Text("None")
            .jotUI(FontManager.uiLabel4())
            .foregroundColor(Color("SecondaryTextColor"))
    }
}

#if os(macOS)
private extension View {
    /// `NSCursor` push/pop — cursor rects from `macPointingHandCursor()` are unreliable inside nested
    /// `ScrollView`/`NSScrollView`, so Properties uses this for every clickable control in the panel.
    func propertiesPanelPointingHandCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
#else
private extension View {
    func propertiesPanelPointingHandCursor() -> some View { self }
}
#endif
