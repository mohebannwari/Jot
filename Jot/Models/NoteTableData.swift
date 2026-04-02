//
//  NoteTableData.swift
//  Jot
//
//  Pure value type representing an inline table's data.
//  Serializes to [[table|...]]...[[/table]] markup for persistence.
//

import Foundation
import CoreGraphics

struct NoteTableData: Equatable {
    var columns: Int
    var cells: [[String]]  // rows x columns, plain text per cell
    var columnWidths: [CGFloat]  // absolute pixel width per column
    var wrapText: Bool = false   // when true, rows expand to fit wrapped text

    var rows: Int { cells.count }

    /// Total content width = sum of all column widths.
    var contentWidth: CGFloat { columnWidths.reduce(0, +) }

    static let defaultColumnWidth: CGFloat = 120

    static func empty(rows: Int = 2, columns: Int = 2) -> NoteTableData {
        let emptyCells = Array(repeating: Array(repeating: "", count: columns), count: rows)
        let widths = Array(repeating: defaultColumnWidth, count: columns)
        return NoteTableData(columns: columns, cells: emptyCells, columnWidths: widths)
    }

    // MARK: - Mutations

    mutating func addRow(at index: Int? = nil) {
        let newRow = Array(repeating: "", count: columns)
        if let idx = index, idx <= cells.count {
            cells.insert(newRow, at: idx)
        } else {
            cells.append(newRow)
        }
    }

    mutating func addColumn(at index: Int? = nil) {
        let insertAt = index ?? columns
        for row in cells.indices {
            if insertAt <= cells[row].count {
                cells[row].insert("", at: insertAt)
            } else {
                cells[row].append("")
            }
        }
        columnWidths.insert(Self.defaultColumnWidth, at: insertAt)
        columns += 1
    }

    mutating func deleteRow(at index: Int) {
        guard index >= 0, index < cells.count, cells.count > 1 else { return }
        cells.remove(at: index)
    }

    mutating func deleteColumn(at index: Int) {
        guard index >= 0, index < columns, columns > 1 else { return }
        for row in cells.indices {
            if index < cells[row].count {
                cells[row].remove(at: index)
            }
        }
        columnWidths.remove(at: index)
        columns -= 1
    }

    mutating func moveRow(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < cells.count,
              destination >= 0, destination < cells.count else { return }
        let row = cells.remove(at: source)
        cells.insert(row, at: destination)
    }

    mutating func moveColumn(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < columns,
              destination >= 0, destination < columns else { return }
        for row in cells.indices {
            let val = cells[row].remove(at: source)
            cells[row].insert(val, at: destination)
        }
        let w = columnWidths.remove(at: source)
        columnWidths.insert(w, at: destination)
    }

    mutating func updateCell(row: Int, column: Int, text: String) {
        guard row >= 0, row < cells.count,
              column >= 0, column < cells[row].count else { return }
        cells[row][column] = text
    }

    // MARK: - Serialization

    /// Serialize to the app's custom markup format:
    /// ```
    /// [[table|2|240.0|120.0,120.0
    /// Header 1\tHeader 2
    /// Cell 1\tCell 2
    /// [[/table]]
    /// ```
    func serialize() -> String {
        var lines: [String] = []
        let widthStr = columnWidths.map { String(format: "%.1f", $0) }.joined(separator: ",")
        var header = "[[table|\(columns)|\(String(format: "%.1f", contentWidth))|\(widthStr)"
        if wrapText { header += "|wrap" }
        lines.append(header)
        for row in cells {
            let escaped = row.map { Self.escape($0) }
            lines.append(escaped.joined(separator: "\t"))
        }
        lines.append("[[/table]]")
        return lines.joined(separator: "\n")
    }

    /// Parse from serialized markup. Backward-compatible with old fraction format.
    static func deserialize(from text: String) -> NoteTableData? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 3 else { return nil }

        let header = lines[0]
        guard header.hasPrefix("[[table|") else { return nil }
        let headerPayload = String(header.dropFirst("[[table|".count))
        let parts = headerPayload.components(separatedBy: "|")
        guard let colCount = Int(parts[0]), colCount > 0 else { return nil }

        // Optional: total width and per-column widths
        var legacyDisplayWidth: CGFloat = 0
        var parsedWidths: [CGFloat]?
        if parts.count >= 2, let w = Double(parts[1]) {
            legacyDisplayWidth = CGFloat(w)
        }
        if parts.count >= 3 {
            let widthParts = parts[2].components(separatedBy: ",")
            let parsed = widthParts.compactMap { Double($0) }.map { CGFloat($0) }
            if parsed.count == colCount {
                parsedWidths = parsed
            }
        }

        // Parse rows until [[/table]]
        var rows: [[String]] = []
        for i in 1..<lines.count {
            let line = lines[i]
            if line == "[[/table]]" { break }
            let rawCells = line.components(separatedBy: "\t")
            let unescaped = rawCells.map { Self.unescape($0) }
            let normalized: [String]
            if unescaped.count < colCount {
                normalized = unescaped + Array(repeating: "", count: colCount - unescaped.count)
            } else if unescaped.count > colCount {
                normalized = Array(unescaped.prefix(colCount))
            } else {
                normalized = unescaped
            }
            rows.append(normalized)
        }

        guard !rows.isEmpty else { return nil }

        // Determine column widths — detect old fraction format vs new absolute
        let widths: [CGFloat]
        if let parsed = parsedWidths {
            let allSmall = parsed.allSatisfy { $0 < 2.0 }
            let sum = parsed.reduce(0, +)
            let isFractionFormat = allSmall && abs(sum - 1.0) < 0.1

            if isFractionFormat {
                // Old format: convert fractions to absolute widths
                let base = legacyDisplayWidth > 0 ? legacyDisplayWidth : CGFloat(colCount) * defaultColumnWidth
                widths = parsed.map { $0 * base }
            } else {
                widths = parsed
            }
        } else {
            widths = Array(repeating: defaultColumnWidth, count: colCount)
        }

        let wrap = parts.count >= 4 && parts[3] == "wrap"
        return NoteTableData(columns: colCount, cells: rows, columnWidths: widths, wrapText: wrap)
    }

    // MARK: - Escape helpers

    private static func escape(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\": result.append("\\\\")
            case "\n": result.append("\\n")
            case "\t": result.append("\\t")
            case "[":  result.append("\\[")
            case "]":  result.append("\\]")
            default:   result.append(ch)
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
                    case "n":  result.append("\n")
                    case "t":  result.append("\t")
                    case "[":  result.append("[")
                    case "]":  result.append("]")
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
