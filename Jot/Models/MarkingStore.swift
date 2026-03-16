import Foundation
import SwiftUI
import Combine

@MainActor
final class MarkingStore: ObservableObject {
    @Published private(set) var markings: [Marking] = []

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Jot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("markings.json")
    }

    init() {
        load()
    }

    // MARK: - CRUD

    func add(noteID: UUID, noteTitle: String, markedText: String) {
        let marking = Marking(
            noteID: noteID,
            noteTitle: noteTitle,
            markedText: markedText,
            createdAt: Date()
        )
        markings.insert(marking, at: 0)
        save()
    }

    func remove(_ id: UUID) {
        markings.removeAll { $0.id == id }
        save()
    }

    func removeAll(forNote noteID: UUID) {
        markings.removeAll { $0.noteID == noteID }
        save()
    }

    // MARK: - Filtering

    enum TimeFilter: String, CaseIterable, Identifiable {
        case thisWeek = "This week"
        case lastMonth = "Last month"
        case lastYear = "Last year"
        case allTime = "All time"

        var id: String { rawValue }

        /// Exclusive date range for each filter bucket.
        var dateRange: (start: Date?, end: Date?) {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .thisWeek:
                return (cal.date(byAdding: .day, value: -7, to: now), nil)
            case .lastMonth:
                return (cal.date(byAdding: .month, value: -1, to: now),
                        cal.date(byAdding: .day, value: -7, to: now))
            case .lastYear:
                return (cal.date(byAdding: .year, value: -1, to: now),
                        cal.date(byAdding: .month, value: -1, to: now))
            case .allTime:
                return (nil, nil)
            }
        }
    }

    func filtered(by filter: TimeFilter) -> [Marking] {
        let range = filter.dateRange
        return markings.filter { m in
            if let start = range.start, m.createdAt < start { return false }
            if let end = range.end, m.createdAt >= end { return false }
            return true
        }
    }

    /// Groups markings by day label, preserving chronological order.
    func grouped(by filter: TimeFilter) -> [(day: String, items: [Marking])] {
        let items = filtered(by: filter)
        var groups: [(day: String, items: [Marking])] = []
        var seen: [String: Int] = [:]
        for m in items {
            let key = m.dayLabel
            if let idx = seen[key] {
                groups[idx].items.append(m)
            } else {
                seen[key] = groups.count
                groups.append((day: key, items: [m]))
            }
        }
        return groups
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(markings)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("MarkingStore save error: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.fileURL)
            markings = try JSONDecoder().decode([Marking].self, from: data)
        } catch {
            NSLog("MarkingStore load error: \(error)")
        }
    }
}
