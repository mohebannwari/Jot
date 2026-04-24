import Foundation
import SwiftData

extension SimpleSwiftDataManager {
    /// Matches sidebar / note-list ordering for smart-folder contents.
    func sidebarSortComparator() -> (Note, Note) -> Bool {
        let sortOrderRaw = UserDefaults.standard.string(forKey: ThemeManager.noteSortOrderKey) ?? "dateEdited"
        let sortOrder = NoteSortOrder(rawValue: sortOrderRaw) ?? .dateEdited
        switch sortOrder {
        case .dateEdited: return { $0.date > $1.date }
        case .dateCreated: return { $0.createdAt > $1.createdAt }
        case .title: return { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    /// Rebuilds virtual membership for every smart folder from the current note list.
    func recomputeSmartFolderMembership(sortedNotes: [Note]) {
        guard !smartFolders.isEmpty else {
            notesBySmartFolderID = [:]
            return
        }
        var dict: [UUID: [Note]] = [:]
        for sf in smartFolders {
            dict[sf.id] = sortedNotes.filter { sf.predicate.matches($0) }
        }
        notesBySmartFolderID = dict
    }

    // Recomputes all derived note collections in a single pass over notes.
    // Called only when notes array changes — not on every UI render.
    func recomputeDerivedNotes() {
        // No manual objectWillChange.send() needed — @Published var notes already
        // fires the publisher before didSet runs, and these derived collections
        // update synchronously within the same didSet, so SwiftUI captures both
        // the notes change and derived property changes in a single render cycle.
        let sortOrderRaw = UserDefaults.standard.string(forKey: ThemeManager.noteSortOrderKey) ?? "dateEdited"
        let sortOrder = NoteSortOrder(rawValue: sortOrderRaw) ?? .dateEdited

        let sortComparator = sidebarSortComparator()

        let groupDate: (Note) -> Date = sortOrder == .dateCreated ? { $0.createdAt } : { $0.date }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        // Sort once, then partition in a single forward pass.
        // Previous implementation sorted each sub-collection independently (9 O(n log n) passes).
        let sorted = notes.sorted(by: sortComparator)

        var folderDict: [UUID: [Note]] = [:]
        var unfiled: [Note] = []
        var pinned: [Note] = []
        var locked: [Note] = []
        var allUnpinned: [Note] = []
        var today: [Note] = []
        var month: [Note] = []
        var year: [Note] = []
        var older: [Note] = []

        for note in sorted {
            if let fid = note.folderID {
                folderDict[fid, default: []].append(note)
                continue
            }

            unfiled.append(note)

            if note.isPinned {
                pinned.append(note)
                continue
            }
            if note.isLocked {
                locked.append(note)
                continue
            }

            allUnpinned.append(note)

            let d = groupDate(note)
            if calendar.isDate(d, inSameDayAs: now) {
                today.append(note)
            } else {
                let noteYear = calendar.component(.year, from: d)
                if noteYear < currentYear {
                    older.append(note)
                } else {
                    let noteMonth = calendar.component(.month, from: d)
                    if noteMonth < currentMonth {
                        year.append(note)
                    } else {
                        let noteDay = calendar.startOfDay(for: d)
                        if noteDay < todayStart {
                            month.append(note)
                        }
                    }
                }
            }
        }

        notesByFolderID = folderDict
        unfiledNotes = unfiled
        pinnedNotes = pinned
        lockedNotes = locked
        allUnpinnedNotes = allUnpinned
        todayNotes = today
        thisMonthNotes = month
        thisYearNotes = year
        olderNotes = older

        recomputeSmartFolderMembership(sortedNotes: sorted)
    }

    /// Updates a single note in-place across all derived sidebar collections
    /// without triggering a full recompute. Used after content-only saves.
    func updateNoteInDerivedCollections(_ note: Note) {
        func patch(_ array: inout [Note]) {
            if let i = array.firstIndex(where: { $0.id == note.id }) {
                array[i] = note
            }
        }
        patch(&pinnedNotes)
        patch(&allUnpinnedNotes)
        patch(&unfiledNotes)
        patch(&lockedNotes)
        patch(&todayNotes)
        patch(&thisMonthNotes)
        patch(&thisYearNotes)
        patch(&olderNotes)
        for (key, var arr) in notesByFolderID {
            if let i = arr.firstIndex(where: { $0.id == note.id }) {
                arr[i] = note
                notesByFolderID[key] = arr
                break
            }
        }

        // Smart folders depend on title/content/tags — refresh without a full derived recompute.
        recomputeSmartFolderMembership(sortedNotes: notes.sorted(by: sidebarSortComparator()))
    }

    /// Re-sorts derived note collections when user changes sort preference.
    func refreshSorting() {
        recomputeDerivedNotes()
    }

}
