//
//  HapticManager.swift
//  Noty
//
//  Manages haptic feedback for user interactions
//

import Foundation
import AppKit

@MainActor
class HapticManager {
    static let shared = HapticManager()

    private let feedbackPerformer = NSHapticFeedbackManager.defaultPerformer

    private init() {}

    // MARK: - Feedback Types

    /// Light tap feedback for subtle interactions (tag selection, hover states)
    func light() {
        feedbackPerformer.perform(.generic, performanceTime: .default)
    }

    /// Medium feedback for standard button taps and interactions
    func medium() {
        feedbackPerformer.perform(.alignment, performanceTime: .default)
    }

    /// Strong feedback for important actions (opening/closing notes, deletion)
    func strong() {
        feedbackPerformer.perform(.levelChange, performanceTime: .default)
    }

    // MARK: - Convenience Methods

    /// Feedback for button taps
    func buttonTap() {
        medium()
    }

    /// Feedback for note interactions (opening, closing)
    func noteInteraction() {
        strong()
    }

    /// Feedback for tag interactions
    func tagInteraction() {
        light()
    }

    /// Feedback for toolbar actions
    func toolbarAction() {
        medium()
    }

    /// Feedback for navigation (back button)
    func navigation() {
        medium()
    }
}
