//
//  FeatureFlags.swift
//  Jot
//
//  Feature flags for toggling functionality on/off
//

import Foundation

struct FeatureFlags {
    /// Toggle tags functionality
    /// Set to `true` to enable tags throughout the app
    /// Set to `false` to hide tags UI (data is still saved)
    static let tagsEnabled = false

    // Add more feature flags here as needed
    // Example:
    // static let collaborationEnabled = false
    // static let aiAssistantEnabled = false
}
