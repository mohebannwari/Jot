//
//  WebClipView.swift
//  Jot
//
//  Proper implementation that fills space correctly
//

import SwiftUI

struct WebClipView: View {
    let title: String
    let domain: String
    let url: String?

    @Environment(\.colorScheme) private var colorScheme

    /// Light mode: system accent blue. Dark mode: darker Apple-style blue.
    private var pillBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.149, green: 0.353, blue: 0.776)  // #2658C6
            : Color.accentColor
    }

    var body: some View {
        Button {
            if let urlString = url ?? URL(string: "https://\(domain)")?.absoluteString,
                let url = URL(string: urlString)
            {
                #if os(macOS)
                    NSWorkspace.shared.open(url)
                #else
                    UIApplication.shared.open(url)
                #endif
            }
        } label: {
            HStack(spacing: 4) {
                Image("insert link")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.white)

                Text(cleanedDomain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .textCase(.lowercase)

                Image("arrow-up-right")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.white)
            }
            .padding(4)
            .frame(minWidth: 54)
            .background(pillBackground, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
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

