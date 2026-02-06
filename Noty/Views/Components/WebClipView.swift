//
//  WebClipView.swift
//  Noty
//
//  Proper implementation that fills space correctly
//

import SwiftUI

struct WebClipView: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let domain: String
    let url: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(FontManager.metadata(size: 10, weight: .medium))
                .foregroundStyle(foregroundColor)

            Text(cleanedDomain)
                .font(FontManager.metadata(size: 10, weight: .medium))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .textCase(.lowercase)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(minWidth: 54, minHeight: 20)
        .background(backgroundColor, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 0.5)
        )
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? .white : Color("PrimaryTextColor")
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color("SurfaceTranslucentColor")
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.black.opacity(0.06)
    }

    private var cleanedDomain: String {
        domain
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
    }

    private var accessibilityLabel: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmedTitle.isEmpty ? cleanedDomain : trimmedTitle
        return "Open \(label)"
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
