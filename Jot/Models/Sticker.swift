//
//  Sticker.swift
//  Jot
//
//  Sticky-note sticker that can be placed anywhere on the note canvas.
//  Stores absolute position, size, color, and text properties.
//

import SwiftUI

struct Sticker: Identifiable, Codable, Equatable {
    var id = UUID()
    var color: StickerColor = .green
    var text: String = ""
    var positionX: CGFloat       // absolute X from scroll content leading edge
    var positionY: CGFloat       // absolute Y from scroll content top
    var size: CGFloat = 100      // width = height (square, locked aspect ratio)
    var fontSize: CGFloat = 12   // range: 9–20
    var textColorDark: Bool = true  // true = black text, false = white text
    var zIndex: Int = 0          // for layering — last-interacted gets highest

    static let minSize: CGFloat = 50
    static let maxSize: CGFloat = 300
}

// MARK: - Sticker Color

enum StickerColor: String, Codable, CaseIterable {
    case green, blue, violet, yellow, red, stone

    var baseColor: Color {
        switch self {
        case .green:  return Color(red: 74/255, green: 222/255, blue: 128/255)
        case .blue:   return Color(red: 96/255, green: 165/255, blue: 250/255)
        case .violet: return Color(red: 167/255, green: 139/255, blue: 250/255)
        case .yellow: return Color(red: 250/255, green: 204/255, blue: 21/255)
        case .red:    return Color(red: 248/255, green: 113/255, blue: 113/255)
        case .stone:  return Color(red: 163/255, green: 163/255, blue: 163/255)
        }
    }

    var foldColor: Color {
        switch self {
        case .green:  return Color(red: 21/255, green: 128/255, blue: 61/255)
        case .blue:   return Color(red: 29/255, green: 78/255, blue: 216/255)
        case .violet: return Color(red: 109/255, green: 40/255, blue: 217/255)
        case .yellow: return Color(red: 161/255, green: 98/255, blue: 7/255)
        case .red:    return Color(red: 185/255, green: 28/255, blue: 28/255)
        case .stone:  return Color(red: 68/255, green: 64/255, blue: 60/255)
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
