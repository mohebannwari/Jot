import SwiftUI

struct FloatingSettings: View {
    @Binding var isPresented: Bool

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var activeTab: SettingsTab = .appearance
    @State private var hoveredTab: SettingsTab?
    @State private var hoveredTheme: AppTheme?
    @State private var hoveredBodyFontStyle: BodyFontStyle?

    private let panelWidth: CGFloat = 612
    private let panelHeight: CGFloat = 512
    private let panelCornerRadius: CGFloat = 16
    private let panelPadding: CGFloat = 24
    private let columnGap: CGFloat = 28

    private let tabColumnWidth: CGFloat = 124
    private let tabColumnHeight: CGFloat = 84
    private let tabHeight: CGFloat = 36
    private let tabVerticalSpacing: CGFloat = 12

    private let contentColumnWidth: CGFloat = 412
    private let contentColumnHeight: CGFloat = 464
    private let contentVerticalPadding: CGFloat = 12

    private let themeCardWidth: CGFloat = 200
    private let themeCardHeight: CGFloat = 224.99998474121094
    private let themeCardRadius: CGFloat = 16

    private let bodyFontCardWidth: CGFloat = 122
    private let bodyFontCardHeight: CGFloat = 91
    private let bodyFontCardRadius: CGFloat = 16
    private let bodyFontCardSpacing: CGFloat = 23

    private enum SettingsTab {
        case account
        case appearance

        var iconAsset: String {
            switch self {
            case .account: return "IconPeopleIdCard"
            case .appearance: return "IconPaintBrush"
            }
        }

        var title: String {
            switch self {
            case .account: return "Account"
            case .appearance: return "Appearance"
            }
        }

        var width: CGFloat {
            switch self {
            case .account: return 102
            case .appearance: return 124
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: columnGap) {
            tabColumn
            contentColumn
        }
        .padding(panelPadding)
        .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .onChange(of: isPresented) { _, presented in
            if presented {
                activeTab = .appearance
            }
        }
        #if os(macOS)
        .onExitCommand {
            if isPresented {
                isPresented = false
            }
        }
        #endif
    }

    private var tabColumn: some View {
        VStack(alignment: .leading, spacing: tabVerticalSpacing) {
            tabButton(.account)
            tabButton(.appearance)
        }
        .frame(width: tabColumnWidth, height: tabColumnHeight, alignment: .topLeading)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = activeTab == tab
        let isHovered = hoveredTab == tab

        return Button {
            activeTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(tab.iconAsset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(isSelected ? Color("ButtonPrimaryTextColor") : Color("SettingsIconSecondaryColor"))
                    .frame(width: 20, height: 20)

                Text(tab.title)
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(isSelected ? Color("ButtonPrimaryTextColor") : Color("SettingsPrimaryTextColor"))
            }
            .padding(.horizontal, 12)
            .frame(width: tab.width, height: tabHeight, alignment: .leading)
            .background {
                Capsule()
                    .fill(isSelected ? Color("ButtonPrimaryBgColor") : Color.clear)
            }
            .clipShape(Capsule())
            .scaleEffect(isHovered ? 1.02 : 1)
            .animation(.jotHover, value: isHovered)
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .onHover { hovering in
            if hovering {
                hoveredTab = tab
            } else if hoveredTab == tab {
                hoveredTab = nil
            }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        if activeTab == .appearance {
            appearancePanel
                .frame(width: contentColumnWidth, height: contentColumnHeight, alignment: .topLeading)
        } else {
            accountPanel
                .frame(width: contentColumnWidth, height: contentColumnHeight, alignment: .topLeading)
        }
    }

    private var accountPanel: some View {
        Color.clear
    }

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 48) {
            themeSection
            bodyFontSection
        }
        .padding(.vertical, contentVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Theme")

            HStack(spacing: 12) {
                themeCard(
                    imageName: "SettingsThemeLight",
                    theme: .light
                )

                themeCard(
                    imageName: "SettingsThemeDark",
                    theme: .dark
                )
            }
        }
        .frame(width: contentColumnWidth, alignment: .leading)
    }

    private func themeCard(imageName: String, theme: AppTheme) -> some View {
        let isHovered = hoveredTheme == theme
        let isSelected = selectedTheme == theme

        return Button {
            themeManager.setTheme(theme)
        } label: {
            Image(imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: themeCardWidth, height: themeCardHeight)
                .clipped()
            .clipShape(RoundedRectangle(cornerRadius: themeCardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: themeCardRadius, style: .continuous)
                        .stroke(
                            isSelected ? Color("SettingsSelectionOrange") : Color.clear,
                            lineWidth: 4
                        )
                }
                .scaleEffect(isHovered ? 1.02 : 1)
                .animation(.jotHover, value: isHovered)
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .onHover { hovering in
            if hovering {
                hoveredTheme = theme
            } else if hoveredTheme == theme {
                hoveredTheme = nil
            }
        }
    }

    private var bodyFontSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Body-font")

            HStack(spacing: bodyFontCardSpacing) {
                bodyFontCard(
                    title: "Default",
                    style: .default,
                    previewFont: Font.custom("Charter", size: 20)
                )

                bodyFontCard(
                    title: "System",
                    style: .system,
                    previewFont: FontManager.heading(size: 20, weight: .medium)
                )

                bodyFontCard(
                    title: "Mono",
                    style: .mono,
                    previewFont: Font.system(size: 20, weight: .medium, design: .monospaced)
                )
            }
            .frame(width: contentColumnWidth, alignment: .leading)
        }
        .frame(width: contentColumnWidth, alignment: .leading)
    }

    private func bodyFontCard(title: String, style: BodyFontStyle, previewFont: Font) -> some View {
        let isHovered = hoveredBodyFontStyle == style
        let isSelected = themeManager.currentBodyFontStyle == style

        return Button {
            themeManager.setBodyFontStyle(style)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: bodyFontCardRadius, style: .continuous)
                        .fill(Color("SettingsOptionCardColor"))

                    Text("Aa")
                        .font(previewFont)
                        .foregroundColor(Color("SettingsPrimaryTextColor"))
                }
                .frame(width: bodyFontCardWidth, height: bodyFontCardHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: bodyFontCardRadius, style: .continuous)
                        .stroke(
                            isSelected ? Color("SettingsSelectionOrange") : Color.clear,
                            lineWidth: 3
                        )
                }

                Text(title)
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(Color("SettingsPrimaryTextColor"))
                    .frame(maxWidth: .infinity)
            }
            .frame(width: bodyFontCardWidth)
            .scaleEffect(isHovered ? 1.02 : 1)
            .animation(.jotHover, value: isHovered)
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .onHover { hovering in
            if hovering {
                hoveredBodyFontStyle = style
            } else if hoveredBodyFontStyle == style {
                hoveredBodyFontStyle = nil
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(FontManager.heading(size: 11, weight: .medium))
            .tracking(-0.2)
            .foregroundColor(Color("SettingsPlaceholderTextColor"))
    }

    private var selectedTheme: AppTheme {
        switch themeManager.currentTheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return colorScheme == .light ? .light : .dark
        }
    }
}
