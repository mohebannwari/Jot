//
//  NoteMetadataSection.swift
//  Jot
//
//  Side-panel properties view showing note metadata (created date, tags,
//  todos, links, attachments, backlinks). Displayed as a slide-in panel
//  in the detail pane, separated by a vertical divider.
//

import SwiftUI

struct NoteMetadataSection: View {
    let note: Note
    var folder: Folder?
    var backlinks: [BacklinkItem] = []
    var onUpdateTags: (([String]) -> Void)?
    var onToggleTodo: ((Int) -> Void)?
    var onNavigateToNote: ((UUID) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var isTodoExpanded = false
    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var tagFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Content-Derived Metadata (cached, updated on content change)

    private struct ParsedTodo: Identifiable {
        let id: Int // line index in content
        let text: String
        let isCompleted: Bool
    }

    @State private var cachedTodos: [ParsedTodo] = []
    @State private var cachedLinks: [ParsedLink] = []
    @State private var cachedAttachments: [ParsedAttachment] = []

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
        let originalName: String
        let displayLabel: String
    }

    private static func parseAttachments(from content: String) -> [ParsedAttachment] {
        var results: [ParsedAttachment] = []

        if content.contains("[[file|") {
            let parts = content.components(separatedBy: "[[file|")
            for i in 1..<parts.count {
                let inner = parts[i].components(separatedBy: "]]").first ?? ""
                let fields = inner.components(separatedBy: "|")
                if fields.count >= 3 {
                    results.append(ParsedAttachment(id: results.count, originalName: fields[2], displayLabel: fields[2]))
                }
            }
        }

        if content.contains("[[image|||") {
            let parts = content.components(separatedBy: "[[image|||")
            for i in 1..<parts.count {
                let filename = parts[i].components(separatedBy: "]]").first ?? "image"
                results.append(ParsedAttachment(id: results.count, originalName: filename, displayLabel: filename))
            }
        }

        return results
    }

    private func reparseContent() {
        cachedTodos = Self.parseTodos(from: note.content)
        cachedLinks = Self.parseLinks(from: note.content, cleanDomain: cleanDomain)
        cachedAttachments = Self.parseAttachments(from: note.content)
    }

    // MARK: - Helpers

    private func cleanDomain(_ urlString: String) -> String {
        urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .components(separatedBy: "/").first ?? urlString
    }

    /// Matches tabs container fill in dark mode; boosted in dark mode to compensate for blur material behind panel
    private var todoContainerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color("TodoContainerColor")
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
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .frame(width: 22, height: 22)
                        .background(Color("SurfaceTranslucentColor"), in: Circle())
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 18)

            // Title
            Text("Properties")
                .font(FontManager.heading(size: 14, weight: .semibold))
                .tracking(-0.3)
                .foregroundColor(Color("PrimaryTextColor"))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: -4) {
                        // Created
                        propertyRow(label: "Created") {
                            Text(Self.absoluteFormatter.string(from: note.createdAt))
                                .font(.system(size: 12, weight: .medium))
                                .tracking(-0.3)
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
                                        .font(FontManager.heading(size: 11, weight: .medium))
                                        .tracking(-0.2)
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

                        // Referenced By (backlinks)
                        if !backlinks.isEmpty {
                            propertyRow(label: "Referenced By") {
                                referencedByValue
                            }
                        }
                    }
                    .padding(.bottom, 180)
                }

                // Bottom content fade -- identical to NoteDetailView footer
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 180)
                    .background(
                        Rectangle().fill(Color("DetailPaneSurfaceColor"))
                            .mask(Self.bottomFadeGradient)
                    )
                    .allowsHitTesting(false)
            }
        }
        .background(.ultraThinMaterial)
        .background(Color("DetailPaneSurfaceColor").opacity(0.5))
        .onAppear { reparseContent() }
        .onChange(of: note.content) { reparseContent() }
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func propertyRow<Value: View>(
        label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // Label column — 120pt wide, aligned with header
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .tracking(-0.3)
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

    @ViewBuilder
    private var tagsValue: some View {
        FlowLayout(spacing: 6) {
            ForEach(note.tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.2)
                        .foregroundColor(Color("PrimaryTextColor"))

                    Button {
                        onUpdateTags?(note.tags.filter { $0 != tag })
                    } label: {
                        Image("IconCrossMedium")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundColor(Color("PrimaryTextColor").opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(todoContainerColor, in: Capsule())
            }

            // Add tag: inline field or plus button
            if isAddingTag {
                TextField("tag name", text: $newTagText)
                    .font(.system(size: 11, weight: .medium))
                    .textFieldStyle(.plain)
                    .frame(width: 80)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(todoContainerColor, in: Capsule())
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
                        .foregroundColor(Color("SecondaryTextColor"))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 2)
                        .alignmentGuide(.firstTextBaseline) { d in
                            d[VerticalAlignment.center] + 3
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
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
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.2)
                        .foregroundColor(Color("PrimaryTextColor"))

                    Image("IconChevronRightMedium")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundColor(Color("SecondaryTextColor"))
                        .rotationEffect(.degrees(isTodoExpanded ? 90 : 0))
                }
                .padding(.leading, 4)
                .padding(.trailing, 2)
                .padding(.vertical, 4)
                .background(todoContainerColor, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color("PrimaryTextColor"))
                            .strikethrough(todo.isCompleted, color: Color("PrimaryTextColor").opacity(0.5))
                            .opacity(todo.isCompleted ? 0.5 : 1)
                    }
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
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
                                .font(.system(size: 12, weight: .medium))
                                .tracking(-0.3)
                                .textCase(.lowercase)
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
                    .macPointingHandCursor()
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
                    HStack(spacing: 4) {
                        Image("IconFileLink")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)

                        Text(attachment.displayLabel)
                            .font(.system(size: 11, weight: .medium))
                            .tracking(-0.2)
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
                }
            }
        }
    }

    // MARK: - Referenced By (Backlinks)

    @ViewBuilder
    private var referencedByValue: some View {
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
                            .font(.system(size: 11, weight: .medium))
                            .tracking(-0.2)
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
                .macPointingHandCursor()
            }
        }
    }

    // MARK: - Shared

    private static let bottomFadeGradient: LinearGradient = {
        // Perlin smootherstep (6t^5 - 15t^4 + 10t^3) -- matches NoteDetailView footer exactly.
        let steps = 40
        let stops: [Gradient.Stop] = (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let eased = t * t * t * (t * (t * 6 - 15) + 10)
            return .init(color: Color.white.opacity(eased), location: t)
        }
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .top, endPoint: .bottom)
    }()

    private var noneText: some View {
        Text("None")
            .font(.system(size: 12, weight: .medium))
            .tracking(-0.3)
            .foregroundColor(Color("TertiaryTextColor"))
    }
}
