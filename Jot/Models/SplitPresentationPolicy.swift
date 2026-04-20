import Foundation

struct PlainGlobalSearchSelectionResult: Equatable {
    var selectedNoteID: UUID
    var closesSplit: Bool
}

enum SplitSessionActivationPane: Equatable {
    case primary
    case secondary
}

struct SplitSessionActivationResult: Equatable {
    var selectedNoteID: UUID
    var focusedPane: SplitSessionActivationPane
}

enum SplitPresentationPolicy {
    static func resolvePlainGlobalSearchSelection(
        targetNoteID: UUID,
        isSplitVisible: Bool
    ) -> PlainGlobalSearchSelectionResult {
        PlainGlobalSearchSelectionResult(
            selectedNoteID: targetNoteID,
            closesSplit: isSplitVisible
        )
    }

    static func resolveSplitSessionActivation(
        primaryNoteID: UUID,
        secondaryNoteID: UUID,
        targetNoteID: UUID?
    ) -> SplitSessionActivationResult {
        if targetNoteID == secondaryNoteID {
            return SplitSessionActivationResult(
                selectedNoteID: secondaryNoteID,
                focusedPane: .secondary
            )
        }

        return SplitSessionActivationResult(
            selectedNoteID: primaryNoteID,
            focusedPane: .primary
        )
    }
}
