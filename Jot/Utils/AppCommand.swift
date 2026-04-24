import Foundation

enum AppCommand: Equatable {
    enum Kind: Equatable {
        case noteSelection
        case openSettings
        case requestSplitViewFromCommandPalette
        case openMeetingSessionCommandPalette
        case floatingSearchSwitchToMeetingPickNote
        case toggleVersionHistory
        case togglePropertiesPanel
        case createNewNote
        case createNewFolder
        case trashFocusedNote
        case navigateNote
        case openNoteFromSpotlight
        case exportSingleNote
        case printCurrentNote
        case forceSaveNote
        case checkForUpdates
        case propertiesPanelToggleTodo

        var name: Notification.Name {
            switch self {
            case .noteSelection:
                return .noteSelectionCommandTriggered
            case .openSettings:
                return .openSettings
            case .requestSplitViewFromCommandPalette:
                return .requestSplitViewFromCommandPalette
            case .openMeetingSessionCommandPalette:
                return .openMeetingSessionCommandPalette
            case .floatingSearchSwitchToMeetingPickNote:
                return .floatingSearchSwitchToMeetingPickNote
            case .toggleVersionHistory:
                return .toggleVersionHistory
            case .togglePropertiesPanel:
                return .togglePropertiesPanel
            case .createNewNote:
                return .createNewNote
            case .createNewFolder:
                return .createNewFolder
            case .trashFocusedNote:
                return .trashFocusedNote
            case .navigateNote:
                return .navigateNote
            case .openNoteFromSpotlight:
                return .openNoteFromSpotlight
            case .exportSingleNote:
                return .exportSingleNote
            case .printCurrentNote:
                return .printCurrentNote
            case .forceSaveNote:
                return .forceSaveNote
            case .checkForUpdates:
                return .checkForUpdates
            case .propertiesPanelToggleTodo:
                return .propertiesPanelToggleTodo
            }
        }
    }

    enum NavigationDirection: String, Equatable {
        case up
        case down
    }

    case noteSelection(NoteSelectionCommandAction)
    case openSettings
    case requestSplitViewFromCommandPalette
    case openMeetingSessionCommandPalette
    case floatingSearchSwitchToMeetingPickNote
    case toggleVersionHistory(editorInstanceID: UUID?)
    case togglePropertiesPanel(editorInstanceID: UUID?)
    case createNewNote
    case createNewFolder
    case trashFocusedNote
    case navigateNote(NavigationDirection)
    case openNoteFromSpotlight(noteID: UUID)
    case exportSingleNote(noteID: UUID)
    case printCurrentNote
    case forceSaveNote
    case checkForUpdates
    case propertiesPanelToggleTodo(editorInstanceID: UUID?, lineIndex: Int)

    var kind: Kind {
        switch self {
        case .noteSelection:
            return .noteSelection
        case .openSettings:
            return .openSettings
        case .requestSplitViewFromCommandPalette:
            return .requestSplitViewFromCommandPalette
        case .openMeetingSessionCommandPalette:
            return .openMeetingSessionCommandPalette
        case .floatingSearchSwitchToMeetingPickNote:
            return .floatingSearchSwitchToMeetingPickNote
        case .toggleVersionHistory:
            return .toggleVersionHistory
        case .togglePropertiesPanel:
            return .togglePropertiesPanel
        case .createNewNote:
            return .createNewNote
        case .createNewFolder:
            return .createNewFolder
        case .trashFocusedNote:
            return .trashFocusedNote
        case .navigateNote:
            return .navigateNote
        case .openNoteFromSpotlight:
            return .openNoteFromSpotlight
        case .exportSingleNote:
            return .exportSingleNote
        case .printCurrentNote:
            return .printCurrentNote
        case .forceSaveNote:
            return .forceSaveNote
        case .checkForUpdates:
            return .checkForUpdates
        case .propertiesPanelToggleTodo:
            return .propertiesPanelToggleTodo
        }
    }

    var name: Notification.Name {
        kind.name
    }

    var object: Any? {
        switch self {
        case .toggleVersionHistory(let editorInstanceID),
             .togglePropertiesPanel(let editorInstanceID),
             .propertiesPanelToggleTodo(let editorInstanceID, _):
            return editorInstanceID
        default:
            return nil
        }
    }

    var userInfo: [AnyHashable: Any]? {
        switch self {
        case .noteSelection(let action):
            return ["action": action.rawValue]
        case .navigateNote(let direction):
            return ["direction": direction.rawValue]
        case .openNoteFromSpotlight(let noteID),
             .exportSingleNote(let noteID):
            return ["noteID": noteID]
        case .propertiesPanelToggleTodo(_, let lineIndex):
            return ["lineIndex": lineIndex]
        default:
            return nil
        }
    }

    init?(notification: Notification) {
        switch notification.name {
        case Kind.noteSelection.name:
            guard let rawAction = notification.userInfo?["action"] as? String,
                  let action = NoteSelectionCommandAction(rawValue: rawAction) else { return nil }
            self = .noteSelection(action)
        case Kind.openSettings.name:
            self = .openSettings
        case Kind.requestSplitViewFromCommandPalette.name:
            self = .requestSplitViewFromCommandPalette
        case Kind.openMeetingSessionCommandPalette.name:
            self = .openMeetingSessionCommandPalette
        case Kind.floatingSearchSwitchToMeetingPickNote.name:
            self = .floatingSearchSwitchToMeetingPickNote
        case Kind.toggleVersionHistory.name:
            self = .toggleVersionHistory(editorInstanceID: notification.object as? UUID)
        case Kind.togglePropertiesPanel.name:
            self = .togglePropertiesPanel(editorInstanceID: notification.object as? UUID)
        case Kind.createNewNote.name:
            self = .createNewNote
        case Kind.createNewFolder.name:
            self = .createNewFolder
        case Kind.trashFocusedNote.name:
            self = .trashFocusedNote
        case Kind.navigateNote.name:
            guard let rawDirection = notification.userInfo?["direction"] as? String else { return nil }
            self = .navigateNote(rawDirection == NavigationDirection.up.rawValue ? .up : .down)
        case Kind.openNoteFromSpotlight.name:
            guard let noteID = notification.userInfo?["noteID"] as? UUID else { return nil }
            self = .openNoteFromSpotlight(noteID: noteID)
        case Kind.exportSingleNote.name:
            guard let noteID = notification.userInfo?["noteID"] as? UUID else { return nil }
            self = .exportSingleNote(noteID: noteID)
        case Kind.printCurrentNote.name:
            self = .printCurrentNote
        case Kind.forceSaveNote.name:
            self = .forceSaveNote
        case Kind.checkForUpdates.name:
            self = .checkForUpdates
        case Kind.propertiesPanelToggleTodo.name:
            guard let lineIndex = notification.userInfo?["lineIndex"] as? Int else { return nil }
            self = .propertiesPanelToggleTodo(
                editorInstanceID: notification.object as? UUID,
                lineIndex: lineIndex
            )
        default:
            return nil
        }
    }
}

extension Notification {
    var appCommand: AppCommand? {
        AppCommand(notification: self)
    }
}

extension NotificationCenter {
    func post(_ command: AppCommand) {
        post(name: command.name, object: command.object, userInfo: command.userInfo)
    }
}
