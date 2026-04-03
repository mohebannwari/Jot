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
            HStack(spacing: 0) {
                Image("IconChainLink")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)

                Text(cleanedDomain)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .textCase(.lowercase)
                    .padding(.horizontal, 4)

                Image("IconArrowRightUpCircle")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            }
            .foregroundColor(.white) // LinkPillColor is always dark blue -- white text is forced-appearance by design
            .padding(4)
            .background(Color("LinkPillColor"), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
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

