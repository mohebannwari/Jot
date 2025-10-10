//
//  WebClipView.swift
//  Noty
//
//  Proper implementation that fills space correctly
//

import SwiftUI

struct WebClipView: View {
    let title: String
    let domain: String
    let url: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(FontManager.heading(size: 11, weight: .medium))
                .foregroundColor(linkColor)

            Text(cleanedDomain)
                .font(FontManager.heading(size: 12, weight: .medium))
                .foregroundColor(linkColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(capsuleBackground, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            if let urlString = url ?? URL(string: "https://\(domain)")?.absoluteString,
                let url = URL(string: urlString)
            {
                #if os(macOS)
                    NSWorkspace.shared.open(url)
                #else
                    UIApplication.shared.open(url)
                #endif
            }
        }
    }

    private var linkColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var capsuleBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.06)
    }

    private var cleanedDomain: String {
        domain
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            .sRGB,
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }
}
