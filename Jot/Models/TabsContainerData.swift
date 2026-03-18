//
//  TabsContainerData.swift
//  Jot
//
//  Data model for tabs containers embedded in the rich text editor.
//

import Foundation

struct TabPane {
    var name: String
    var content: String
}

struct TabsContainerData {
    var panes: [TabPane]
    var activeIndex: Int
    var containerHeight: CGFloat

    static let defaultHeight: CGFloat = 222
    static let minHeight: CGFloat = 100
    static let maxHeight: CGFloat = 600

    static func empty() -> TabsContainerData {
        TabsContainerData(
            panes: [TabPane(name: "Tab 1", content: "")],
            activeIndex: 0,
            containerHeight: defaultHeight
        )
    }

    mutating func addTab() {
        let name = "Tab \(panes.count + 1)"
        panes.append(TabPane(name: name, content: ""))
        activeIndex = panes.count - 1
    }

    mutating func removeTab(at index: Int) {
        guard panes.count > 1, panes.indices.contains(index) else { return }
        panes.remove(at: index)
        if activeIndex >= panes.count {
            activeIndex = panes.count - 1
        } else if activeIndex > index {
            activeIndex -= 1
        }
    }

    mutating func renameTab(at index: Int, to newName: String) {
        guard panes.indices.contains(index) else { return }
        panes[index].name = newName.isEmpty ? "Untitled" : newName
    }

    // MARK: - Serialization

    // Format: [[tabs|activeIndex|height|Name1\tName2]]content1\t\tcontent2[[/tabs]]

    func serialize() -> String {
        let names = panes.map { Self.escape($0.name) }.joined(separator: "\t")
        let contents = panes.map { Self.escape($0.content) }.joined(separator: "\t\t")
        return "[[tabs|\(activeIndex)|\(Int(containerHeight))|\(names)]]\(contents)[[/tabs]]"
    }

    static func deserialize(from text: String) -> TabsContainerData? {
        guard text.hasPrefix("[[tabs|") else { return nil }
        let afterPrefix = text.dropFirst("[[tabs|".count)
        guard let closeBracket = afterPrefix.range(of: "]]") else { return nil }

        let header = String(afterPrefix[afterPrefix.startIndex..<closeBracket.lowerBound])
        let parts = header.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        guard let activeIdx = Int(parts[0]) else { return nil }
        let height = CGFloat(Int(parts[1]) ?? Int(defaultHeight))

        let names = String(parts[2]).components(separatedBy: "\t").map { unescape($0) }

        let contentStart = closeBracket.upperBound
        let remaining = afterPrefix[contentStart...]
        guard let closingRange = remaining.range(of: "[[/tabs]]") else { return nil }
        let rawContent = String(remaining[remaining.startIndex..<closingRange.lowerBound])

        let contents: [String]
        if rawContent.isEmpty {
            contents = names.map { _ in "" }
        } else {
            contents = rawContent.components(separatedBy: "\t\t").map { unescape($0) }
        }

        var panes: [TabPane] = []
        for i in 0..<names.count {
            let content = i < contents.count ? contents[i] : ""
            panes.append(TabPane(name: names[i], content: content))
        }
        guard !panes.isEmpty else { return nil }

        let clampedIndex = min(activeIdx, panes.count - 1)
        let clampedHeight = max(minHeight, min(maxHeight, height))
        return TabsContainerData(panes: panes, activeIndex: clampedIndex, containerHeight: clampedHeight)
    }

    // MARK: - Escape helpers

    private static func escape(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "[": result += "\\["
            case "]": result += "\\]"
            default: result.append(ch)
            }
        }
        return result
    }

    private static func unescape(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\\" {
                let next = s.index(after: i)
                if next < s.endIndex {
                    switch s[next] {
                    case "\\": result.append("\\")
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "[": result.append("[")
                    case "]": result.append("]")
                    default:
                        result.append(s[i])
                        result.append(s[next])
                    }
                    i = s.index(after: next)
                } else {
                    result.append(s[i])
                    i = next
                }
            } else {
                result.append(s[i])
                i = s.index(after: i)
            }
        }
        return result
    }
}
