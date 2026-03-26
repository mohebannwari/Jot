//
//  CardSectionData.swift
//  Jot
//
//  Data model for card section blocks embedded in the rich text editor.
//  Cards flow horizontally with per-card Tailwind colors, rich text content,
//  and individually resizable dimensions.
//

import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - CardColor

enum CardColor: String, CaseIterable, Equatable {
    case red, orange, amber, yellow, lime, green, emerald
    case teal, cyan, sky, blue, indigo, violet, purple
    case fuchsia, pink, rose

    // Light mode: 100 (fill), 400 (border)
    // Dark mode:  900 (fill), 700 (border)

    var lightFillHex: String {
        switch self {
        case .red:     return "#FEE2E2"
        case .orange:  return "#FFEDD5"
        case .amber:   return "#FEF3C7"
        case .yellow:  return "#FEF9C3"
        case .lime:    return "#ECFCCB"
        case .green:   return "#DCFCE7"
        case .emerald: return "#D1FAE5"
        case .teal:    return "#CCFBF1"
        case .cyan:    return "#CFFAFE"
        case .sky:     return "#E0F2FE"
        case .blue:    return "#DBEAFE"
        case .indigo:  return "#E0E7FF"
        case .violet:  return "#EDE9FE"
        case .purple:  return "#F3E8FF"
        case .fuchsia: return "#FAE8FF"
        case .pink:    return "#FCE7F3"
        case .rose:    return "#FFE4E6"
        }
    }

    var lightBorderHex: String {
        switch self {
        case .red:     return "#F87171"
        case .orange:  return "#FB923C"
        case .amber:   return "#FBBF24"
        case .yellow:  return "#FACC15"
        case .lime:    return "#A3E635"
        case .green:   return "#4ADE80"
        case .emerald: return "#34D399"
        case .teal:    return "#2DD4BF"
        case .cyan:    return "#22D3EE"
        case .sky:     return "#38BDF8"
        case .blue:    return "#60A5FA"
        case .indigo:  return "#818CF8"
        case .violet:  return "#A78BFA"
        case .purple:  return "#C084FC"
        case .fuchsia: return "#E879F9"
        case .pink:    return "#F472B6"
        case .rose:    return "#FB7185"
        }
    }

    var darkFillHex: String {
        switch self {
        case .red:     return "#7F1D1D"
        case .orange:  return "#7C2D12"
        case .amber:   return "#78350F"
        case .yellow:  return "#713F12"
        case .lime:    return "#365314"
        case .green:   return "#14532D"
        case .emerald: return "#064E3B"
        case .teal:    return "#134E4A"
        case .cyan:    return "#164E63"
        case .sky:     return "#0C4A6E"
        case .blue:    return "#1E3A8A"
        case .indigo:  return "#312E81"
        case .violet:  return "#4C1D95"
        case .purple:  return "#581C87"
        case .fuchsia: return "#701A75"
        case .pink:    return "#831843"
        case .rose:    return "#881337"
        }
    }

    var darkBorderHex: String {
        switch self {
        case .red:     return "#B91C1C"
        case .orange:  return "#C2410C"
        case .amber:   return "#B45309"
        case .yellow:  return "#A16207"
        case .lime:    return "#4D7C0F"
        case .green:   return "#15803D"
        case .emerald: return "#047857"
        case .teal:    return "#0F766E"
        case .cyan:    return "#0E7490"
        case .sky:     return "#0369A1"
        case .blue:    return "#1D4ED8"
        case .indigo:  return "#4338CA"
        case .violet:  return "#6D28D9"
        case .purple:  return "#7E22CE"
        case .fuchsia: return "#A21CAF"
        case .pink:    return "#BE185D"
        case .rose:    return "#BE123C"
        }
    }

    /// Display name for context menus
    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    #if os(macOS)
    func fillColor(isDark: Bool) -> NSColor {
        NSColor(hex: isDark ? darkFillHex : lightFillHex)
    }

    func borderColor(isDark: Bool) -> NSColor {
        NSColor(hex: isDark ? darkBorderHex : lightBorderHex)
    }
    #endif

    static func random() -> CardColor {
        allCases.randomElement() ?? .blue
    }
}

// MARK: - CardData

struct CardData: Equatable {
    var content: String
    var color: CardColor
    var width: CGFloat
    var height: CGFloat

    static func empty(color: CardColor = .random()) -> CardData {
        CardData(
            content: "",
            color: color,
            width: CardSectionData.defaultCardWidth,
            height: CardSectionData.defaultCardHeight
        )
    }
}

// MARK: - CardPosition

struct CardPosition: Equatable {
    let column: Int
    let row: Int
}

// MARK: - CardSectionData

struct CardSectionData: Equatable {
    var columns: [[CardData]]

    // Default dimensions for new cards
    static let defaultCardWidth: CGFloat = 450
    static let defaultCardHeight: CGFloat = 350

    // Layout constants
    static let cardCornerRadius: CGFloat = 22
    static let cardPadding: CGFloat = 16
    static let cardBorderWidth: CGFloat = 2
    static let cardGap: CGFloat = 12
    static let containerCornerRadius: CGFloat = 16
    static let plusButtonWidth: CGFloat = 28

    // Resize bounds
    static let minCardWidth: CGFloat = 200
    static let minCardHeight: CGFloat = 150
    static let maxCardWidth: CGFloat = 800
    static let maxCardHeight: CGFloat = 800

    // MARK: - Flat-index bridge

    var flatCards: [CardData] { columns.flatMap { $0 } }

    var flatCardCount: Int { columns.reduce(0) { $0 + $1.count } }

    func position(forFlatIndex idx: Int) -> CardPosition? {
        var remaining = idx
        for (col, column) in columns.enumerated() {
            if remaining < column.count { return CardPosition(column: col, row: remaining) }
            remaining -= column.count
        }
        return nil
    }

    func flatIndex(for pos: CardPosition) -> Int? {
        guard columns.indices.contains(pos.column),
              columns[pos.column].indices.contains(pos.row) else { return nil }
        var idx = 0
        for c in 0..<pos.column { idx += columns[c].count }
        return idx + pos.row
    }

    // MARK: - Column geometry

    func columnWidth(at col: Int) -> CGFloat {
        guard columns.indices.contains(col) else { return Self.defaultCardWidth }
        return columns[col].map(\.width).max() ?? Self.defaultCardWidth
    }

    func columnHeight(at col: Int) -> CGFloat {
        guard columns.indices.contains(col) else { return Self.defaultCardHeight }
        let heights = columns[col].map(\.height)
        return heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * Self.cardGap
    }

    var maxColumnHeight: CGFloat {
        guard !columns.isEmpty else { return Self.defaultCardHeight }
        return (0..<columns.count).map { columnHeight(at: $0) }.max() ?? Self.defaultCardHeight
    }

    var contentWidth: CGFloat {
        let colWidths = (0..<columns.count).reduce(CGFloat(0)) { $0 + columnWidth(at: $1) }
        return colWidths + CGFloat(max(0, columns.count - 1)) * Self.cardGap + Self.cardGap + Self.plusButtonWidth
    }

    // MARK: - Factories

    static func empty() -> CardSectionData {
        CardSectionData(columns: [[CardData.empty()]])
    }

    // MARK: - Flat-index mutation helpers (backward compat with overlay subview indexing)

    mutating func addCard() {
        columns.append([CardData.empty()])
    }

    mutating func removeCard(at flatIndex: Int) {
        guard flatCardCount > 1, let pos = position(forFlatIndex: flatIndex) else { return }
        columns[pos.column].remove(at: pos.row)
        if columns[pos.column].isEmpty { columns.remove(at: pos.column) }
    }

    mutating func updateCardContent(at flatIndex: Int, content: String) {
        guard let pos = position(forFlatIndex: flatIndex) else { return }
        columns[pos.column][pos.row].content = content
    }

    mutating func setCardColor(at flatIndex: Int, color: CardColor) {
        guard let pos = position(forFlatIndex: flatIndex) else { return }
        columns[pos.column][pos.row].color = color
    }

    mutating func resizeCard(at flatIndex: Int, width: CGFloat? = nil, height: CGFloat? = nil) {
        guard let pos = position(forFlatIndex: flatIndex) else { return }
        if let w = width {
            columns[pos.column][pos.row].width = min(max(Self.minCardWidth, w), Self.maxCardWidth)
        }
        if let h = height {
            columns[pos.column][pos.row].height = min(max(Self.minCardHeight, h), Self.maxCardHeight)
        }
    }

    // MARK: - Column-aware mutation helpers

    @discardableResult
    mutating func removeCardAt(position pos: CardPosition) -> CardData? {
        guard columns.indices.contains(pos.column),
              columns[pos.column].indices.contains(pos.row) else { return nil }
        let card = columns[pos.column].remove(at: pos.row)
        if columns[pos.column].isEmpty { columns.remove(at: pos.column) }
        return card
    }

    mutating func insertAsNewColumn(_ card: CardData, at columnIndex: Int) {
        let clamped = min(max(0, columnIndex), columns.count)
        columns.insert([card], at: clamped)
    }

    mutating func stackCard(_ card: CardData, inColumn col: Int, atRow row: Int) {
        guard columns.indices.contains(col) else { return }
        let clampedRow = min(max(0, row), columns[col].count)
        columns[col].insert(card, at: clampedRow)
    }

    mutating func moveColumn(from: Int, to: Int) {
        guard columns.indices.contains(from) else { return }
        let clamped = min(max(0, to), columns.count - 1)
        guard from != clamped else { return }
        let col = columns.remove(at: from)
        columns.insert(col, at: clamped)
    }

    // MARK: - Serialization

    // New format: [[cards|col1spec;col2spec]]col1content;;col2content[[/cards]]
    // Column spec: card+card (+ separates stacked cards within a column)
    // Column content: card\t\tcard (\t\t separates stacked card contents within a column)
    // Legacy format: [[cards|card,card]]content\t\tcontent[[/cards]] (each card = own column)

    func serialize() -> String {
        let header = columns.map { col in
            col.map { "\($0.color.rawValue):\(Int($0.width)):\(Int($0.height))" }
               .joined(separator: "+")
        }.joined(separator: ";")
        let contents = columns.map { col in
            col.map { Self.escape($0.content) }.joined(separator: "\t\t")
        }.joined(separator: ";;")
        return "[[cards|\(header)]]\(contents)[[/cards]]"
    }

    static func deserialize(from text: String) -> CardSectionData? {
        guard text.hasPrefix("[[cards|") else { return nil }
        let afterPrefix = text.dropFirst("[[cards|".count)
        guard let closeBracket = afterPrefix.range(of: "]]") else { return nil }

        let header = String(afterPrefix[afterPrefix.startIndex..<closeBracket.lowerBound])
        guard !header.isEmpty else { return nil }

        // Parse body content
        let contentStart = closeBracket.upperBound
        let remaining = afterPrefix[contentStart...]
        guard let closingRange = remaining.range(of: "[[/cards]]") else { return nil }
        let rawContent = String(remaining[remaining.startIndex..<closingRange.lowerBound])

        // Detect format: ";" in header means new column format, otherwise legacy flat
        let parsedColumns: [[CardData]]
        if header.contains(";") || header.contains("+") {
            parsedColumns = parseColumnsFormat(header: header, rawContent: rawContent)
        } else {
            parsedColumns = parseLegacyFormat(header: header, rawContent: rawContent)
        }

        guard !parsedColumns.isEmpty else { return nil }
        return CardSectionData(columns: parsedColumns)
    }

    // New column format: ";" separates columns in header, ";;" separates columns in content
    private static func parseColumnsFormat(header: String, rawContent: String) -> [[CardData]] {
        let columnSpecs = header.components(separatedBy: ";")
        let columnContents = rawContent.isEmpty ? [] : rawContent.components(separatedBy: ";;")

        var result: [[CardData]] = []
        for (colIdx, colSpec) in columnSpecs.enumerated() {
            let cardSpecs = colSpec.components(separatedBy: "+")
            let colContent = colIdx < columnContents.count ? columnContents[colIdx] : ""
            let cardContents = colContent.isEmpty ? [] : colContent.components(separatedBy: "\t\t").map { unescape($0) }

            var column: [CardData] = []
            for (cardIdx, spec) in cardSpecs.enumerated() {
                guard let card = parseCardSpec(spec, content: cardIdx < cardContents.count ? cardContents[cardIdx] : "") else { continue }
                column.append(card)
            }
            if !column.isEmpty { result.append(column) }
        }
        return result
    }

    // Legacy flat format: "," separates cards, each becomes its own single-card column
    private static func parseLegacyFormat(header: String, rawContent: String) -> [[CardData]] {
        let cardSpecs = header.components(separatedBy: ",")
        let contents: [String]
        if rawContent.isEmpty {
            contents = cardSpecs.map { _ in "" }
        } else {
            contents = rawContent.components(separatedBy: "\t\t").map { unescape($0) }
        }

        var result: [[CardData]] = []
        for (i, spec) in cardSpecs.enumerated() {
            let content = i < contents.count ? contents[i] : ""
            if let card = parseCardSpec(spec, content: content) {
                result.append([card])
            }
        }
        return result
    }

    private static func parseCardSpec(_ spec: String, content: String) -> CardData? {
        let parts = spec.components(separatedBy: ":")
        guard !parts.isEmpty, let color = CardColor(rawValue: parts[0]) else { return nil }
        var w = defaultCardWidth
        var h = defaultCardHeight
        if parts.count >= 2, let parsed = Double(parts[1]) { w = CGFloat(parsed) }
        if parts.count >= 3, let parsed = Double(parts[2]) { h = CGFloat(parsed) }
        let clampedW = min(max(minCardWidth, w), maxCardWidth)
        let clampedH = min(max(minCardHeight, h), maxCardHeight)
        return CardData(content: content, color: color, width: clampedW, height: clampedH)
    }

    // MARK: - Escape helpers (same convention as TabsContainerData)

    static func escape(_ s: String) -> String {
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

    static func unescape(_ s: String) -> String {
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

// MARK: - NSColor hex initializer

#if os(macOS)
private extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green:   CGFloat((rgb >> 8)  & 0xFF) / 255,
            blue:    CGFloat( rgb        & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
