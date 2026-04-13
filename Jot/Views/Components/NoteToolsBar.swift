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

/// Horizontal edge fade for the expanded, scrollable strip only. When collapsed, no mask is applied so
/// `glassTooltip` overlays can draw above the bar (a mask clips to layout bounds even if it is solid white).
private struct NoteToolsBarExpandedFadeMask: ViewModifier {
    let isExpanded: Bool

    func body(content: Content) -> some View {
        Group {
            if isExpanded {
                content.mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 10)
                        Rectangle().fill(.white)
                        LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 10)
                    }
                }
            } else {
                content
            }
        }
    }
}

struct NoteToolsBar: View {
    let note: Note
    var editorInstanceID: UUID? = nil
    var paneWidth: CGFloat = .infinity
    var aiToolsExpanded: Bool = false

    @State private var isExpanded = false

    private let iconSize: CGFloat = 15

    var body: some View {
        toolbarScrollArea
            .modifier(NoteToolsBarExpandedFadeMask(isExpanded: isExpanded))
            .padding(.horizontal, isExpanded ? -10 : 0)
            .padding(.top, -40)
            .preference(key: ToolbarExpandedPreferenceKey.self, value: isExpanded)
            .animation(.jotSpring, value: isExpanded)
    }

    private var toolbarScrollArea: some View {
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

// MARK: - macOS Share Button

#if os(macOS)
private struct ShareToolButton: View {
    let note: Note
    let iconSize: CGFloat

    var body: some View {
        Button {
            showSharePicker()
        } label: {
            Image("IconArrowRounded")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("IconSecondaryColor"))
                .frame(width: iconSize, height: iconSize)
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background(ShareAnchorView())
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .glassTooltip("Share")
        .hoverContainer(cornerRadius: 8)
    }

    private func showSharePicker() {
        guard let anchorView = ShareAnchorView.lastView else { return }
        var shareText = note.title
        if !note.content.isEmpty {
            shareText += "\n\n" + note.content.strippingColorMarkup
        }
        let picker = NSSharingServicePicker(items: [shareText])
        picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    }
}

/// Invisible NSView anchor for NSSharingServicePicker popover positioning.
private struct ShareAnchorView: NSViewRepresentable {
    static weak var lastView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Self.lastView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.lastView = nsView
    }
}
#endif
