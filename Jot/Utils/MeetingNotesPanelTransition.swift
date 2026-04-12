//
//  MeetingNotesPanelTransition.swift
//  Jot
//
//  Asymmetric overlay transition + animation curves for the meeting recording panel.
//

import SwiftUI

extension Animation {
    /// Large floating surface (meeting notes overlay): smooth settle, minimal overshoot.
    static let jotMeetingPanelPresent = Animation.spring(response: 0.52, dampingFraction: 0.88)

    /// Meeting overlay dismiss: short ease, little bounce — exits softer than they enter.
    static let jotMeetingPanelDismiss = Animation.smooth(duration: 0.26)
}

// MARK: - Transition

/// Materialization: rises from below with scale anchored to the bottom. Dismiss: shallow sink + fade.
private struct MeetingNotesFloatingPanelTransitionModifier: ViewModifier {
    fileprivate enum Phase {
        case offscreen
        case onscreen
        case dismissed
    }

    fileprivate let phase: Phase

    func body(content: Content) -> some View {
        let (offsetY, scale, alpha): (CGFloat, CGFloat, Double) = {
            switch phase {
            case .offscreen: return (48, 0.91, 0)
            case .onscreen: return (0, 1, 1)
            case .dismissed: return (16, 0.96, 0)
            }
        }()
        return content
            .scaleEffect(scale, anchor: .bottom)
            .offset(y: offsetY)
            .opacity(alpha)
    }
}

extension AnyTransition {
    /// Keep in sync with `jotMeetingPanelPresent` / `jotMeetingPanelDismiss` at toggle sites.
    static var meetingNotesFloatingPanel: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: MeetingNotesFloatingPanelTransitionModifier(phase: .offscreen),
                identity: MeetingNotesFloatingPanelTransitionModifier(phase: .onscreen)
            ),
            removal: .modifier(
                active: MeetingNotesFloatingPanelTransitionModifier(phase: .dismissed),
                identity: MeetingNotesFloatingPanelTransitionModifier(phase: .onscreen)
            )
        )
    }
}
