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

    private let tabVerticalSpacing: CGFloat = 12

    private let contentVerticalPadding: CGFloat = 12

    private let themeCardRadius: CGFloat = 16
    private let themeCardAspectRatio: CGFloat = 584.0 / 658.0

    private let bodyFontCardWidth: CGFloat = 122
    private let bodyFontCardHeight: CGFloat = 91
    private let bodyFontCardRadius: CGFloat = 16

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
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .contentShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { })
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

    // MARK: - Tab Bar

    private var tabColumn: some View {
        VStack(alignment: .leading, spacing: tabVerticalSpacing) {
            tabButton(.account)
            tabButton(.appearance)
        }
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
                    .foregroundColor(Color("SettingsIconSecondaryColor"))
                    .frame(width: 18, height: 18)

                Text(tab.title)
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(Color("SettingsPrimaryTextColor"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(colorScheme == .light ? Color.white : Color("SettingsActiveTabColor"))
                }
            }
            .clipShape(Capsule())
            .shadow(color: isSelected ? .black.opacity(0.06) : .clear, radius: 3, x: 0, y: 1)
            .shadow(color: isSelected ? .black.opacity(0.03) : .clear, radius: 1, x: 0, y: 0)
            .scaleEffect(isHovered ? 1.01 : 1)
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

    // MARK: - Content

    @ViewBuilder
    private var contentColumn: some View {
        if activeTab == .appearance {
            appearancePanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            accountPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Theme")

            HStack(spacing: 12) {
                themeCard(
                    imageName: "SettingsThemeLight",
                    label: "Light",
                    theme: .light
                )

                themeCard(
                    imageName: "SettingsThemeDark",
                    label: "Dark",
                    theme: .dark
                )

                systemThemeCard()
            }
        }
    }

    private func themeCard(imageName: String, label: String, theme: AppTheme) -> some View {
        let isHovered = hoveredTheme == theme
        let isSelected = themeManager.currentTheme == theme

        return Button {
            themeManager.setTheme(theme)
        } label: {
            VStack(spacing: 12) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(themeCardAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: themeCardRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.09), radius: 4, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 0)
                    .overlay {
                        RoundedRectangle(cornerRadius: themeCardRadius, style: .continuous)
                            .stroke(
                                isSelected ? Color("SettingsSelectionOrange") : Color.clear,
                                lineWidth: 4
                            )
                    }

                Text(label)
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(Color("SettingsPrimaryTextColor"))
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(isHovered ? 1.01 : 1)
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

    private func systemThemeCard() -> some View {
        let isHovered = hoveredTheme == .system
        let isSelected = themeManager.currentTheme == .system

        return Button {
            themeManager.setTheme(.system)
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Image("SettingsThemeLight")
                        .resizable()
                        .aspectRatio(themeCardAspectRatio, contentMode: .fit)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle()
                                Color.clear
                            }
                        )

                    Image("SettingsThemeDark")
                        .resizable()
                        .aspectRatio(themeCardAspectRatio, contentMode: .fit)
                        .mask(
                            HStack(spacing: 0) {
                                Color.clear
                                Rectangle()
                            }
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: themeCardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.09), radius: 4, x: 0, y: 1)
                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 0)
                .overlay {
                    RoundedRectangle(cornerRadius: themeCardRadius, style: .continuous)
                        .stroke(
                            isSelected ? Color("SettingsSelectionOrange") : Color.clear,
                            lineWidth: 4
                        )
                }

                Text("System")
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(Color("SettingsPrimaryTextColor"))
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(isHovered ? 1.01 : 1)
            .animation(.jotHover, value: isHovered)
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .onHover { hovering in
            if hovering {
                hoveredTheme = .system
            } else if hoveredTheme == .system {
                hoveredTheme = nil
            }
        }
    }

    // MARK: - Body Font Section

    private var bodyFontSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Body-font")

            HStack {
                bodyFontCard(
                    title: "Default",
                    style: .default,
                    previewFont: Font.custom("Charter", size: 20)
                )

                Spacer()

                bodyFontCard(
                    title: "System",
                    style: .system,
                    previewFont: Font.system(size: 20 * FontManager.opticalSizeCompensation, weight: .medium, design: .default)
                )

                Spacer()

                bodyFontCard(
                    title: "Mono",
                    style: .mono,
                    previewFont: Font.system(size: 20 * FontManager.opticalSizeCompensation, weight: .medium, design: .monospaced)
                )
            }
        }
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
                        .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))

                    Text("Aa")
                        .font(previewFont)
                        .foregroundColor(Color("SettingsPlaceholderTextColor"))
                }
                .frame(width: bodyFontCardWidth, height: bodyFontCardHeight)
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0)
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
            .scaleEffect(isHovered ? 1.01 : 1)
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

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(FontManager.heading(size: 12, weight: .medium))
            .tracking(-0.3)
            .foregroundColor(Color("SettingsPlaceholderTextColor"))
    }
}
