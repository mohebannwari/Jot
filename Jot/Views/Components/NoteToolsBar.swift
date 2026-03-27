//
//  NoteToolsBar.swift
//  Jot
//
//  Horizontal icon bar at the bottom-left of the detail pane.
//  Collapsed: 4 primary actions + ellipsis to expand.
//  Expanded: primary actions + divider + additional tools from the slash command menu.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NoteToolsBar: View {
    let note: Note
    var editorInstanceID: UUID? = nil
    var paneWidth: CGFloat = .infinity
    var aiToolsExpanded: Bool = false

    @State private var isExpanded = false

    private let iconSize: CGFloat = 18

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
            // MARK: - Primary actions (always visible)

            toolButton(icon: "gallery", tooltip: "Image Upload", tooltipEdge: .leading) {
                postToolAction(.imageUpload)
            }
            toolButton(icon: "IconFileLink", tooltip: "Attach File") {
                postToolAction(.fileLink)
            }
            toolButton(icon: "IconPageTextSearch", tooltip: "Search on Page") {
                postToolAction(.searchOnPage)
            }
            toolButton(icon: "mic-recording", tooltip: "Voice Record") {
                postToolAction(.voiceRecord)
            }
            #if os(macOS)
            ShareToolButton(note: note, iconSize: iconSize)
                .frame(width: iconSize, height: iconSize)
                .padding(4)
                .glassTooltip("Share")
                .hoverContainer(cornerRadius: 8)
            #endif

            // MARK: - Ellipsis toggle / divider

            if isExpanded {
                // Single dot divider (non-interactive)
                Circle()
                    .fill(Color("IconSecondaryColor"))
                    .frame(width: 4, height: 4)
                    .padding(.horizontal, 6)
                    .transition(.scale.combined(with: .opacity))
            } else {
                // Horizontal ellipsis button to expand
                Button {
                    withAnimation(.jotSpring) { isExpanded = true }
                } label: {
                    Image("IconDotGrid1x3HorizontalTight")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("IconSecondaryColor"))
                        .frame(width: iconSize, height: iconSize)
                        .padding(4)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
                .glassTooltip("More actions", edge: .trailing)
                .hoverContainer(cornerRadius: 8)
                .transition(.scale.combined(with: .opacity))
            }

            // MARK: - Expanded actions

            if isExpanded {
                Group {
                    // Lists & Tasks
                    toolButton(icon: "todo-list", tooltip: "Bullet List") {
                        postToolAction(.bulletList)
                    }
                    toolButton(icon: "IconNumberedList", tooltip: "Numbered List") {
                        postToolAction(.numberedList)
                    }
                    toolButton(icon: "IconTodos", tooltip: "To-Do") {
                        postToolAction(.todo)
                    }
                    // Rich Blocks
                    toolButton(icon: "IconCode", tooltip: "Code Block") {
                        postToolAction(.codeBlock)
                    }
                    toolButton(icon: "IconTextBlock", tooltip: "Block Quote") {
                        postToolAction(.blockQuote)
                    }
                    toolButton(icon: "IconLightBulbSimple", tooltip: "Callout") {
                        postToolAction(.callout)
                    }
                    toolButton(icon: "IconDossier", tooltip: "Tabs") {
                        postToolAction(.tabs)
                    }
                    toolButton(icon: "IconCarussel", tooltip: "Cards") {
                        postToolAction(.cards)
                    }
                    // Insertable Objects
                    toolButton(icon: "IconTable", tooltip: "Table") {
                        postToolAction(.table)
                    }
                    toolButton(icon: "insert link", tooltip: "Insert Link") {
                        postToolAction(.link)
                    }
                    toolButton(icon: "IconDivider", tooltip: "Insert Divider") {
                        postToolAction(.divider)
                    }
                    toolButton(icon: "IconSticker", tooltip: "Post-it") {
                        postToolAction(.sticker)
                    }
                    // Version history
                    Button {
                        NotificationCenter.default.post(name: .toggleVersionHistory, object: editorInstanceID)
                    } label: {
                        Image("IconBranchSimple")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color("IconSecondaryColor"))
                            .frame(width: iconSize, height: iconSize)
                            .padding(4)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                    .glassTooltip("Version History")
                    .hoverContainer(cornerRadius: 8)
                    // Collapse chevron
                    Button {
                        withAnimation(.jotSpring) { isExpanded = false }
                    } label: {
                        Image("IconChevronRightMedium")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color("IconSecondaryColor"))
                            .frame(width: iconSize, height: iconSize)
                            .scaleEffect(x: -1, y: 1)
                            .padding(4)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .macPointingHandCursor()
                    .glassTooltip("Collapse", edge: .trailing)
                    .hoverContainer(cornerRadius: 8)
                }
                .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
        }
        .padding(.top, 40)
        }
        .scrollClipDisabled(true)
        .scrollDisabled(!isExpanded)
        .frame(maxWidth: isExpanded ? max(paneWidth - (aiToolsExpanded ? 260 : 80), 200) : .infinity)
        .fixedSize(horizontal: !isExpanded, vertical: true)
        .padding(.horizontal, isExpanded ? 10 : 0)
        .mask(
            Group {
                if isExpanded {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 10)
                        Rectangle().fill(.white)
                        LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 10)
                    }
                } else {
                    Rectangle().fill(.white)
                }
            }
        )
        .padding(.horizontal, isExpanded ? -10 : 0)
        .padding(.top, -40)
        .preference(key: ToolbarExpandedPreferenceKey.self, value: isExpanded)
        .animation(.jotSpring, value: isExpanded)
    }

    // MARK: - Helpers

    private func toolButton(icon: String, tooltip: String, tooltipEdge: HorizontalAlignment = .center, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("IconSecondaryColor"))
                .frame(width: iconSize, height: iconSize)
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .glassTooltip(tooltip, edge: tooltipEdge)
        .hoverContainer(cornerRadius: 8)
    }

    private func postToolAction(_ tool: EditTool) {
        var userInfo: [String: Any] = [:]
        if let eid = editorInstanceID { userInfo["editorInstanceID"] = eid }
        NotificationCenter.default.post(
            name: .noteToolsBarAction,
            object: tool.rawValue,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }
}

// MARK: - Preference Key

struct ToolbarExpandedPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Side-Only Clip

/// Clips left and right edges but allows vertical overflow (tooltips above, shadows below).
private struct SideClipShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - 200, width: rect.width, height: rect.height + 400))
    }
}

// MARK: - macOS Share Button

#if os(macOS)
private struct ShareToolButton: NSViewRepresentable {
    let note: Note
    let iconSize: CGFloat

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(named: "IconShareOs")
        button.image?.isTemplate = true
        button.contentTintColor = NSColor(named: "IconSecondaryColor")
        button.imageScaling = .scaleProportionallyUpOrDown
        button.setFrameSize(NSSize(width: iconSize, height: iconSize))
        button.target = context.coordinator
        button.action = #selector(Coordinator.showSharePicker(_:))
        button.toolTip = "Share"
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.note = note
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(note: note)
    }

    class Coordinator: NSObject {
        var note: Note

        init(note: Note) {
            self.note = note
        }

        @objc func showSharePicker(_ sender: NSButton) {
            var shareText = note.title
            if !note.content.isEmpty {
                shareText += "\n\n" + note.content.strippingColorMarkup
            }
            let picker = NSSharingServicePicker(items: [shareText])
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
#endif
