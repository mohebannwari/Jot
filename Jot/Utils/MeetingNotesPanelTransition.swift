//
//  MeetingNotesPanelTransition.swift
//  Jot
//
//  Animation curves for the meeting recording floating panel. The panel itself uses
//  explicit scale/offset/opacity in `NoteDetailView.meetingNotesFloatingOverlay` because
//  SwiftUI insertion `.transition` was not reliably animating in this overlay stack when
//  `MeetingRecorderManager` published updates in the same frame as `showMeetingPanel`.
//

import SwiftUI

extension Animation {
    /// Large floating surface (meeting notes overlay): smooth settle, minimal overshoot.
    static let jotMeetingPanelPresent = Animation.spring(response: 0.52, dampingFraction: 0.88)

    /// Meeting overlay dismiss: short ease, little bounce — exits softer than they enter.
    static let jotMeetingPanelDismiss = Animation.smooth(duration: 0.26)
}
