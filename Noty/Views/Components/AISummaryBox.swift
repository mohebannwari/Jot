//
//  AISummaryBox.swift
//  Noty
//
//  Created by AI on 21.09.25.
//
//  AI Summary display component for Apple Intelligence writing tools integration

import SwiftUI

struct AISummaryBox: View {
    let summaryText: String
    let onDismiss: () -> Void
    @State private var isVisible = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with AI icon and title
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(FontManager.heading(size: 14, weight: .medium))
                    .foregroundColor(Color("AccentColor"))

                Text("AI Summary")
                    .font(FontManager.heading(size: 13, weight: .semibold))
                    .foregroundColor(Color("PrimaryTextColor"))

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "ellipsis")
                        .font(FontManager.heading(size: 14, weight: .regular))
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .buttonStyle(.plain)
            }

            // Summary content - using Charter for body text
            Text(summaryText)
                .font(FontManager.body(size: 14, weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("CardBackgroundColor"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color("AccentColor").opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08),
            radius: 8,
            x: 0,
            y: 4
        )
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            withAnimation {
                isVisible = true
            }
        }
    }
}

#Preview {
    AISummaryBox(
        summaryText: "I opened my journal as rain tapped the attic window, dust motes dancing in sunlight. I wrote about an old music box from an antique shop, its melody a forgotten dream. Later, I met Elara at a coffee shop; her eyes sparkled with stories. We discussed art and happiness for hours. As the sun set, I felt content. It's the unexpected moments that make life special. I closed my journal, smiling at the day's joys.",
        onDismiss: {}
    )
    .padding()
    .background(Color.gray.opacity(0.1))
}