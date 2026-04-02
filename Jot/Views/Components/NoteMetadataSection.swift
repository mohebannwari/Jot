//
//  NoteMetadataSection.swift
//  Jot
//
//  Collapsible Notion-style metadata panel shown below the note title.
//

import SwiftUI

struct NoteMetadataSection: View {
    let note: Note
    var onUpdateTags: (([String]) -> Void)?
    var onToggleTodo: ((Int) -> Void)?

    @State private var isExpanded = false
    @State private var isTodoExpanded = false
    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var tagFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Content-Derived Metadata

    private struct ParsedTodo: Identifiable {
        let id: Int // line index in content
        let text: String
        let isCompleted: Bool
    }

    private var parsedTodos: [ParsedTodo] {
        var results: [ParsedTodo] = []
        let lines = note.content.components(separatedBy: "\n")
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
        var id: String { url }
        let url: String
        let domain: String
        let isWebClip: Bool
    }

    private var parsedLinks: [ParsedLink] {
        var results: [ParsedLink] = []

        if note.content.contains("[[webclip|") {
            let parts = note.content.components(separatedBy: "[[webclip|")
            for i in 1..<parts.count {
                let inner = parts[i].components(separatedBy: "]]").first ?? ""
                let fields = inner.components(separatedBy: "|")
                if fields.count >= 3 {
                    results.append(ParsedLink(url: fields[2], domain: cleanDomain(fields[2]), isWebClip: true))
                }
            }
        }

        if note.content.contains("[[link|") {
            let parts = note.content.components(separatedBy: "[[link|")
            for i in 1..<parts.count {
                let url = parts[i].components(separatedBy: "]]").first ?? ""
                if !url.isEmpty {
                    results.append(ParsedLink(url: url, domain: cleanDomain(url), isWebClip: false))
                }
            }
        }

        return results
    }

    private struct ParsedAttachment: Identifiable {
        var id: String { originalName }
        let originalName: String
        let displayLabel: String
    }

    private var parsedAttachments: [ParsedAttachment] {
        var results: [ParsedAttachment] = []

        if note.content.contains("[[file|") {
            let parts = note.content.components(separatedBy: "[[file|")
            for i in 1..<parts.count {
                let inner = parts[i].components(separatedBy: "]]").first ?? ""
                let fields = inner.components(separatedBy: "|")
                if fields.count >= 3 {
                    results.append(ParsedAttachment(originalName: fields[2], displayLabel: fields[2]))
                }
            }
        }

        if note.content.contains("[[image|||") {
            let parts = note.content.components(separatedBy: "[[image|||")
            for i in 1..<parts.count {
                let filename = parts[i].components(separatedBy: "]]").first ?? "image"
                results.append(ParsedAttachment(originalName: filename, displayLabel: filename))
            }
        }

        return results
    }

    // MARK: - Helpers

    private func cleanDomain(_ urlString: String) -> String {
        urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .components(separatedBy: "/").first ?? urlString
    }

    // MARK: - Date Formatting

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd. MMM yyyy 'at' HH:mm"
        return f
    }()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            propertiesToggleButton

            if isExpanded {
                expandedSection
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    // MARK: - Toggle Button

    private var propertiesToggleButton: some View {
        HStack {
            Button {
                withAnimation(.jotSpring) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image("IconNoteProperties")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)

                    Text("Properties")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.2)

                    Image("IconChevronRightMedium")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay {
                    Capsule()
                        .stroke(
                            style: StrokeStyle(lineWidth: 1.6, dash: [4, 3])
                        )
                        .foregroundColor(Color(nsColor: .separatorColor))
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()

            Spacer()
        }
    }

    // MARK: - Expanded Section

    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Created
            propertyRow(label: "Created") {
                Text(Self.absoluteFormatter.string(from: note.createdAt))
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.3)
                    .foregroundColor(Color("PrimaryTextColor"))
            }

            // Tags
            propertyRow(label: "Tags") {
                tagsValue
            }

            // Todos
            propertyRow(label: "Todos") {
                VStack(alignment: .leading, spacing: 8) {
                    todosCounterPill

                    if isTodoExpanded {
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
        }
        .padding(2)
        .compositingGroup()
        .thinLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                .padding(.leading, 12)
                .padding(.vertical, 8)
                .frame(width: 120, alignment: .leading)

            // Value column — flex
            value()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 2)
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
                .background(Color("BlockContainerColor"), in: Capsule())
            }

            // Add tag: inline field or plus button
            if isAddingTag {
                TextField("tag name", text: $newTagText)
                    .font(.system(size: 11, weight: .medium))
                    .textFieldStyle(.plain)
                    .frame(width: 80)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color("BlockContainerColor"), in: Capsule())
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
        let todos = parsedTodos
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
                .background(Color("BlockContainerColor"), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
        }
    }

    @ViewBuilder
    private var expandedTodoList: some View {
        let todos = parsedTodos
        VStack(alignment: .leading, spacing: 8) {
            ForEach(todos) { todo in
                Button {
                    onToggleTodo?(todo.id)
                } label: {
                    HStack(spacing: 4) {
                        todoCheckbox(isCompleted: todo.isCompleted)
                            .frame(width: 18, height: 18)

                        Text(todo.text)
                            .font(.system(size: 11, weight: .medium))
                            .tracking(-0.2)
                            .foregroundColor(Color("PrimaryTextColor"))
                            .strikethrough(todo.isCompleted, color: Color("PrimaryTextColor").opacity(0.5))
                            .opacity(todo.isCompleted ? 0.5 : 1)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("BlockContainerColor"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .stroke(Color.black.opacity(0.4), lineWidth: 3.5)

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
        let links = parsedLinks
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
                                .padding(.horizontal, 4)

                            Image("IconArrowRightUpCircle")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                        .foregroundColor(.white)
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
        let attachments = parsedAttachments
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

                        Image("IconArrowRightUpCircle")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    }
                    .foregroundColor(Color("PrimaryTextColor"))
                    .padding(4)
                    .background(Color("BlockContainerColor"), in: Capsule())
                    .environment(\.colorScheme, colorScheme == .dark ? .light : .dark)
                }
            }
        }
    }

    // MARK: - Shared

    private var noneText: some View {
        Text("None")
            .font(.system(size: 12, weight: .medium))
            .tracking(-0.3)
            .foregroundColor(Color("TertiaryTextColor"))
    }
}
