import Foundation

struct Marking: Identifiable, Codable, Equatable {
    var id = UUID()
    var noteID: UUID
    var noteTitle: String
    var markedText: String
    var createdAt: Date

    /// Compact date label for grouping (e.g. "Thursday 13.02")
    var dayLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE dd.MM"
        return fmt.string(from: createdAt)
    }
}
