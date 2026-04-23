import Foundation

enum SidebarSectionFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case today
    case thisMonth
    case thisYear
    case older
    case folders

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .pinned: return "Pinned"
        case .today: return "Today"
        case .thisMonth: return "This Month"
        case .thisYear: return "This Year"
        case .older: return "Older"
        case .folders: return "Folders"
        }
    }
}

func sidebarSectionFilterAllows(_ active: SidebarSectionFilter, section: SidebarSectionFilter) -> Bool {
    active == .all || active == section
}
