import Foundation

enum SplitNoteOpeningPane: Equatable {
    case primary
    case secondary
}

struct SplitNoteOpeningContext: Equatable {
    var isSplitVisible: Bool
    var primaryNoteID: UUID?
    var secondaryNoteID: UUID?
    var focusedPane: SplitNoteOpeningPane?
}

struct SplitNoteOpeningResult: Equatable {
    enum Action: Equatable {
        case openSingle
        case replacePrimary
        case replaceSecondary
        case focusExistingPrimary
        case focusExistingSecondary
    }

    var action: Action
    var primaryNoteID: UUID?
    var secondaryNoteID: UUID?
    var selectedNoteID: UUID
    var focusedPane: SplitNoteOpeningPane?
    var keepsSplitVisible: Bool
}

enum SplitNoteOpeningPolicy {
    static func resolve(targetNoteID: UUID, context: SplitNoteOpeningContext) -> SplitNoteOpeningResult {
        guard context.isSplitVisible else {
            return SplitNoteOpeningResult(
                action: .openSingle,
                primaryNoteID: context.primaryNoteID,
                secondaryNoteID: context.secondaryNoteID,
                selectedNoteID: targetNoteID,
                focusedPane: context.focusedPane,
                keepsSplitVisible: false
            )
        }

        if context.primaryNoteID == targetNoteID {
            return SplitNoteOpeningResult(
                action: .focusExistingPrimary,
                primaryNoteID: context.primaryNoteID,
                secondaryNoteID: context.secondaryNoteID,
                selectedNoteID: targetNoteID,
                focusedPane: .primary,
                keepsSplitVisible: true
            )
        }

        if context.secondaryNoteID == targetNoteID {
            return SplitNoteOpeningResult(
                action: .focusExistingSecondary,
                primaryNoteID: context.primaryNoteID,
                secondaryNoteID: context.secondaryNoteID,
                selectedNoteID: targetNoteID,
                focusedPane: .secondary,
                keepsSplitVisible: true
            )
        }

        let focusedPane = context.focusedPane ?? .primary
        switch focusedPane {
        case .primary:
            return SplitNoteOpeningResult(
                action: .replacePrimary,
                primaryNoteID: targetNoteID,
                secondaryNoteID: context.secondaryNoteID,
                selectedNoteID: targetNoteID,
                focusedPane: .primary,
                keepsSplitVisible: true
            )
        case .secondary:
            return SplitNoteOpeningResult(
                action: .replaceSecondary,
                primaryNoteID: context.primaryNoteID,
                secondaryNoteID: targetNoteID,
                selectedNoteID: targetNoteID,
                focusedPane: .secondary,
                keepsSplitVisible: true
            )
        }
    }
}
