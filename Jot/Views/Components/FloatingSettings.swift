import SwiftUI

struct SettingsPage: View {
    @Binding var isPresented: Bool

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var activeTab: SettingsTab = .general
    @State private var hoveredTab: SettingsTab?
    @State private var hoveredTheme: AppTheme?
    @State private var hoveredBodyFontStyle: BodyFontStyle?
    @State private var hoveredLineSpacing: LineSpacing?
    @State private var hoveredFontSize: CGFloat?
    @State private var isCustomFontSize = false
    @State private var customFontSizeText: String = ""
    @FocusState private var isCustomFontSizeFocused: Bool

    // Contact panel state
    @State private var feedbackType: FeedbackType = .bug
    @State private var feedbackText: String = ""
    @State private var feedbackState: FeedbackState = .idle
    @State private var celebrateRotation: Double = 0
    @State private var celebrateScale: CGFloat = 0
    @State private var hoveredFeedbackType: FeedbackType?
    @State private var hoveredCopyButton = false
    @State private var showCopiedConfirmation = false
    @State private var hoveredMailButton = false
    @State private var hoveredSendButton = false
    @Namespace private var feedbackAnimation

    // Locked notes inline password state
    @State private var customPasswordInput: String = ""
    @State private var isEditingPassword: Bool = false
    @State private var hoveredPasswordConfirm = false
    @State private var hoveredPasswordDismiss = false

    private let columnGap: CGFloat = 42
    private let tabVerticalSpacing: CGFloat = 12
    private let contentVerticalPadding: CGFloat = 8

    private let themeCardHeight: CGFloat = 91

    private let bodyFontCardWidth: CGFloat = 122
    private let bodyFontCardHeight: CGFloat = 91
    private let bodyFontCardRadius: CGFloat = 16

    private let lineSpacingCardWidth: CGFloat = 122
    private let lineSpacingCardHeight: CGFloat = 91
    private let lineSpacingCardRadius: CGFloat = 16

    private let developerEmail = "mhbanwari@gmail.com"

    private enum FeedbackType: String, CaseIterable {
        case bug = "Bug"
        case featureRequest = "Feature request"

        var iconAsset: String {
            switch self {
            case .bug: return "IconBug"
            case .featureRequest: return "IconPullRequest"
            }
        }

        var mailSubject: String {
            switch self {
            case .bug: return "Bug"
            case .featureRequest: return "Feature request"
            }
        }

        func selectedBackground(for scheme: ColorScheme) -> Color {
            switch self {
            case .bug:
                return scheme == .dark
                    ? Color(red: 0x45/255, green: 0x0a/255, blue: 0x0a/255)
                    : Color(red: 0xfe/255, green: 0xca/255, blue: 0xca/255)
            case .featureRequest:
                return scheme == .dark
                    ? Color(red: 0x05/255, green: 0x2e/255, blue: 0x16/255)
                    : Color(red: 0xbb/255, green: 0xf7/255, blue: 0xd0/255)
            }
        }

        func selectedText(for scheme: ColorScheme) -> Color {
            switch self {
            case .bug:
                return scheme == .dark
                    ? Color(red: 0xfe/255, green: 0xca/255, blue: 0xca/255)
                    : Color(red: 0xb9/255, green: 0x1c/255, blue: 0x1c/255)
            case .featureRequest:
                return scheme == .dark
                    ? Color(red: 0xbb/255, green: 0xf7/255, blue: 0xd0/255)
                    : Color(red: 0x15/255, green: 0x80/255, blue: 0x3d/255)
            }
        }
    }

    private enum FeedbackState {
        case idle, sent
    }

    private enum SettingsTab: CaseIterable {
        case general
        case appearance
        case data
        case contact
        case about

        var iconAssetName: String {
            switch self {
            case .general: return "IconSettingsGeneral"
            case .appearance: return "IconSettingsAppearance"
            case .data: return "IconArchive1"
            case .contact: return "IconSettingsSupport"
            case .about: return "IconSettingsAbout"
            }
        }

        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .data: return "Backups"
            case .contact: return "Contact"
            case .about: return "About"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(FontManager.heading(size: 28, weight: .semibold))
                .tracking(-0.4)
                .foregroundColor(Color("SettingsPrimaryTextColor"))

            HStack(alignment: .top, spacing: columnGap) {
                tabColumn
                    .fixedSize(horizontal: true, vertical: false)

                contentColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 80)
        .padding(.bottom, 24)
        .onChange(of: isPresented) { _, presented in
            if presented {
                activeTab = .general
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
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = activeTab == tab
        let isHovered = hoveredTab == tab

        return Button {
            activeTab = tab
        } label: {
            Text(tab.title)
                .font(FontManager.heading(size: 15, weight: .medium))
                .tracking(-0.2)
                .foregroundColor(isSelected
                    ? (colorScheme == .light ? Color.white : Color.black)
                    : Color("SettingsPrimaryTextColor"))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(colorScheme == .light ? Color.black : Color.white)
                } else if isHovered {
                    Capsule()
                        .fill(Color("HoverBackgroundColor"))
                }
            }
            .clipShape(Capsule())
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
        Group {
            switch activeTab {
            case .general:
                generalPanel
            case .appearance:
                appearancePanel
            case .data:
                BackupSettingsPanel()
            case .about:
                aboutPanel
            case .contact:
                contactPanel
            }
        }
        .frame(width: 482, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - General Panel

    private var generalPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 48) {
                // Sort options
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Sort options")

                    settingsSortPicker

                    settingsGroupedCard {
                        settingsCheckbox(
                            "Group notes by date",
                            subtitle: "When sorted by Date Edited or Date Created, group notes by date.",
                            isOn: $themeManager.groupNotesByDate
                        )
                        settingsCheckbox(
                            "Automatically sort checked items",
                            subtitle: "Automatically move checklist items to the bottom of the list as they are checked.",
                            isOn: $themeManager.autoSortCheckedItems
                        )
                    }
                }

                // Writing assistance
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Writing assistance")

                    settingsGroupedCard {
                        settingsCheckbox("Spell check", isOn: $themeManager.spellCheckEnabled)
                        settingsCheckbox("Autocorrect", isOn: $themeManager.autocorrectEnabled)
                        settingsCheckbox(
                            "Smart quotes",
                            subtitle: "\"abc\" to \u{201C}abc\u{201D}",
                            isOn: $themeManager.smartQuotesEnabled
                        )
                        settingsCheckbox(
                            "Smart dashes",
                            subtitle: "-- to \u{2014}",
                            isOn: $themeManager.smartDashesEnabled
                        )
                    }
                }

                // Locked notes
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Locked notes")

                    VStack(alignment: .leading, spacing: 12) {
                        // Password type dropdown
                        Menu {
                            ForEach(LockPasswordType.allCases, id: \.self) { type in
                                Button {
                                    if type == .custom && themeManager.lockPasswordType != .custom {
                                        themeManager.lockPasswordType = .custom
                                        customPasswordInput = ""
                                        isEditingPassword = true
                                    } else {
                                        themeManager.lockPasswordType = type
                                        isEditingPassword = false
                                    }
                                } label: {
                                    if themeManager.lockPasswordType == type {
                                        Label(type.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(type.displayName)
                                    }
                                }
                            }
                        } label: {
                            settingsCapsuleRow {
                                Text(themeManager.lockPasswordType.displayName)
                                    .font(FontManager.heading(size: 15, weight: .medium))
                                    .tracking(-0.5)
                                    .foregroundColor(Color("PrimaryTextColor"))

                                Spacer()

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                            }
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)

                        // Inline password field (only when custom selected)
                        if themeManager.lockPasswordType == .custom {
                            settingsCapsuleRow {
                                if isEditingPassword {
                                    SecureField("Password", text: $customPasswordInput)
                                        .textFieldStyle(.plain)
                                        .font(FontManager.heading(size: 15, weight: .medium))
                                        .tracking(-0.5)
                                        .foregroundColor(Color("PrimaryTextColor"))
                                        .onSubmit {
                                            if !customPasswordInput.isEmpty {
                                                KeychainManager.savePassword(customPasswordInput)
                                                customPasswordInput = ""
                                                isEditingPassword = false
                                            }
                                        }
                                } else {
                                    Text("\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}")
                                        .font(FontManager.heading(size: 15, weight: .medium))
                                        .tracking(-0.5)
                                        .foregroundColor(Color("PrimaryTextColor"))
                                }

                                Spacer()

                                if isEditingPassword {
                                    HStack(spacing: 2) {
                                        Button {
                                            if !customPasswordInput.isEmpty {
                                                KeychainManager.savePassword(customPasswordInput)
                                                customPasswordInput = ""
                                                isEditingPassword = false
                                            }
                                        } label: {
                                            Image("IconCheckmark1")
                                                .renderingMode(.template)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 14, height: 14)
                                                .foregroundColor(Color("PrimaryTextColor"))
                                                .padding(4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(hoveredPasswordConfirm ? Color("HoverBackgroundColor") : Color.clear)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .macPointingHandCursor()
                                        .onHover { hoveredPasswordConfirm = $0 }

                                        Button {
                                            customPasswordInput = ""
                                            isEditingPassword = false
                                            if KeychainManager.loadPassword() == nil {
                                                themeManager.lockPasswordType = .login
                                            }
                                        } label: {
                                            Image("IconCrossMedium")
                                                .renderingMode(.template)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 14, height: 14)
                                                .foregroundColor(Color("PrimaryTextColor"))
                                                .padding(4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(hoveredPasswordDismiss ? Color("HoverBackgroundColor") : Color.clear)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .macPointingHandCursor()
                                        .onHover { hoveredPasswordDismiss = $0 }
                                    }
                                }
                            }

                            // "Change password" link (only when saved and not editing)
                            if !isEditingPassword && KeychainManager.loadPassword() != nil {
                                Button {
                                    customPasswordInput = ""
                                    isEditingPassword = true
                                } label: {
                                    Text("Change password")
                                        .font(FontManager.heading(size: 15, weight: .medium))
                                        .tracking(-0.5)
                                        .foregroundColor(Color(red: 0x25/255, green: 0x63/255, blue: 0xeb/255))
                                }
                                .buttonStyle(.plain)
                                .macPointingHandCursor()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                    }

                    HStack(alignment: .top) {
                        settingsCheckbox(
                            "Use Touch ID",
                            subtitle: "Use your fingerprint to view locked notes.",
                            isOn: $themeManager.useTouchID,
                            standalone: false
                        )

                        Spacer(minLength: 0)

                        Button {
                            showTouchIDHelpAlert()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.88))
                                    .frame(width: 20, height: 20)
                                Text("?")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                            }
                        }
                        .buttonStyle(.plain)
                        .macPointingHandCursor()
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.vertical, contentVerticalPadding)
        }
        .scrollClipDisabled()
    }

    // MARK: - General Panel Helpers

    private var settingsSortPicker: some View {
        Menu {
            ForEach(NoteSortOrder.allCases, id: \.self) { order in
                Button {
                    themeManager.noteSortOrder = order
                } label: {
                    if themeManager.noteSortOrder == order {
                        Label(order.displayName, systemImage: "checkmark")
                    } else {
                        Text(order.displayName)
                    }
                }
            }
        } label: {
            settingsCapsuleRow {
                Text("Sort notes by:")
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))

                Spacer()

                HStack(spacing: 4) {
                    Text(themeManager.noteSortOrder.displayName.uppercased())
                        .font(FontManager.metadata(size: 11, weight: .medium))
                        .foregroundColor(Color("PrimaryTextColor"))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color("SettingsPlaceholderTextColor"))
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func settingsCapsuleRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))
        )
        .overlay(
            Capsule()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func settingsGroupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 18) {
            content()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func settingsCheckbox(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>, standalone: Bool = false) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isOn.wrappedValue ? Color("ButtonPrimaryBgColor") : (colorScheme == .dark ? Color(white: 0.18) : Color.white))
                        .frame(width: 16, height: 16)

                    Circle()
                        .strokeBorder(isOn.wrappedValue ? Color.clear : (colorScheme == .dark ? Color(white: 0.35) : Color(white: 0.72)), lineWidth: 1)
                        .frame(width: 16, height: 16)

                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color("ButtonPrimaryTextColor"))
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FontManager.heading(size: 15, weight: .medium))
                        .tracking(-0.2)
                        .foregroundColor(Color("SettingsPrimaryTextColor"))

                    if let subtitle {
                        Text(subtitle)
                            .font(FontManager.heading(size: 12, weight: .regular))
                            .foregroundColor(Color("SettingsPlaceholderTextColor"))
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 0)
        .if(standalone) { view in
            view
                .padding(.horizontal, 12)
                .padding(.vertical, 0)
        }
    }

    // MARK: - Locked Notes Dialogs

    private func showTouchIDHelpAlert() {
        let alert = NSAlert()
        alert.messageText = "Touch ID"
        alert.informativeText = "When enabled, you can use your fingerprint to quickly unlock locked notes instead of entering your password each time."
        alert.icon = NSImage(systemSymbolName: "touchid", accessibilityDescription: "Touch ID")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Appearance Panel

    private var appearancePanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 48) {
                themeSection
                bodyFontSection
                lineSpacingSection
                fontSizeSection
            }
            .padding(.vertical, contentVerticalPadding)
        }
        .scrollClipDisabled()
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Theme")

            HStack(spacing: 12) {
                themeImageCard(
                    imageName: "SettingsThemeLight",
                    label: "Day",
                    theme: .light
                )

                themeImageCard(
                    imageName: "SettingsThemeDark",
                    label: "Night",
                    theme: .dark
                )

                themeImageCard(
                    imageName: "SettingsThemeAuto",
                    label: "Auto",
                    theme: .system
                )
            }
        }
    }

    private func themeImageCard(imageName: String, label: String, theme: AppTheme) -> some View {
        let isHovered = hoveredTheme == theme
        let isSelected = themeManager.currentTheme == theme

        return Button {
            themeManager.setTheme(theme)
        } label: {
            VStack(spacing: 8) {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: themeCardHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: bodyFontCardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: bodyFontCardRadius, style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0)

                settingsSelectionLabel(label, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
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

    // MARK: - Body Font Section

    private var bodyFontSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Body-font")

            HStack(spacing: 12) {
                bodyFontCard(
                    title: "Default",
                    style: .default,
                    previewFont: Font.custom("Charter", size: 20)
                )

                bodyFontCard(
                    title: "System",
                    style: .system,
                    previewFont: Font.system(size: 20, weight: .medium, design: .default)
                )

                bodyFontCard(
                    title: "Mono",
                    style: .mono,
                    previewFont: Font.system(size: 20, weight: .medium, design: .monospaced)
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
                .frame(maxWidth: .infinity)
                .frame(height: bodyFontCardHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: bodyFontCardRadius, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0)

                settingsSelectionLabel(title, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
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

    private var lineSpacingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Line spacing")

            HStack(spacing: 12) {
                lineSpacingCard(spacing: .compact)
                lineSpacingCard(spacing: .default)
                lineSpacingCard(spacing: .relaxed)
            }
        }
    }

    private func lineSpacingCard(spacing: LineSpacing) -> some View {
        let isHovered = hoveredLineSpacing == spacing
        let isSelected = themeManager.lineSpacing == spacing

        return Button {
            themeManager.lineSpacing = spacing
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: lineSpacingCardRadius, style: .continuous)
                        .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))

                    lineSpacingPreview(for: spacing)
                }
                .frame(maxWidth: .infinity)
                .frame(height: lineSpacingCardHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: lineSpacingCardRadius, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0)

                settingsSelectionLabel(spacing.displayName, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
            .animation(.jotHover, value: isHovered)
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .onHover { hovering in
            if hovering {
                hoveredLineSpacing = spacing
            } else if hoveredLineSpacing == spacing {
                hoveredLineSpacing = nil
            }
        }
    }

    private func lineSpacingPreview(for spacing: LineSpacing) -> some View {
        let lineCount = 4
        let lineGap: CGFloat = {
            switch spacing {
            case .compact: return 4
            case .default: return 7
            case .relaxed: return 10
            }
        }()

        return VStack(spacing: lineGap) {
            ForEach(0..<lineCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color("SettingsPlaceholderTextColor").opacity(0.5))
                    .frame(width: i == lineCount - 1 ? 48 : 80, height: 3)
            }
        }
    }

    // MARK: - Font Size Section

    private let fontSizePresets: [CGFloat] = [14, 15, 16, 18]

    private var isPresetSize: Bool {
        fontSizePresets.contains(themeManager.bodyFontSize)
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Font size")

            HStack(spacing: 8) {
                ForEach(fontSizePresets, id: \.self) { size in
                    fontSizePill(size, isSelected: themeManager.bodyFontSize == size) {
                        isCustomFontSizeFocused = false
                        isCustomFontSize = false
                        themeManager.bodyFontSize = size
                    }
                }

                if isCustomFontSize || !isPresetSize {
                    customFontSizeField
                } else {
                    fontSizePill(nil, label: "Custom", isSelected: false, wide: true) {
                        isCustomFontSize = true
                        customFontSizeText = "\(Int(themeManager.bodyFontSize))"
                        isCustomFontSizeFocused = true
                    }
                }
            }
        }
    }

    private func fontSizePill(_ size: CGFloat?, label: String? = nil, isSelected: Bool, wide: Bool = false, action: @escaping () -> Void) -> some View {
        let isHovered = hoveredFontSize == (size ?? -1)

        return Button(action: action) {
            Text(label ?? "\(Int(size ?? 0))")
                .font(FontManager.metadata(size: 13, weight: .medium))
                .foregroundColor(
                    isSelected
                        ? Color("ButtonPrimaryTextColor")
                        : Color("SettingsPlaceholderTextColor")
                )
                .frame(width: wide ? 64 : 40, height: 32)
                .background(
                    Capsule()
                        .fill(isSelected ? Color("SettingsSelectionOrange") : (colorScheme == .light ? Color.white : Color("SettingsOptionCardColor")))
                )
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0)
                .animation(.jotHover, value: isHovered)
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .onHover { hovering in
            if hovering {
                hoveredFontSize = size ?? -1
            } else if hoveredFontSize == (size ?? -1) {
                hoveredFontSize = nil
            }
        }
    }

    private var customFontSizeField: some View {
        let isActive = !isPresetSize || isCustomFontSize

        let isCustomSelected = isActive && !isPresetSize

        return TextField("", text: $customFontSizeText)
            .font(FontManager.metadata(size: 13, weight: .medium))
            .foregroundColor(isCustomSelected ? Color("ButtonPrimaryTextColor") : Color("SettingsPrimaryTextColor"))
            .multilineTextAlignment(.center)
            .frame(width: 40, height: 32)
            .background(
                Capsule()
                    .fill(isCustomSelected ? Color("SettingsSelectionOrange") : (colorScheme == .light ? Color.white : Color("SettingsOptionCardColor")))
            )
            .overlay(
                Capsule()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
            .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0)
            .textFieldStyle(.plain)
            .focused($isCustomFontSizeFocused)
            .onSubmit {
                if let val = Double(customFontSizeText) {
                    let clamped = min(max(CGFloat(val), 10), 28)
                    themeManager.bodyFontSize = clamped
                    customFontSizeText = "\(Int(clamped))"
                }
                isCustomFontSizeFocused = false
            }
            .onChange(of: isCustomFontSizeFocused) { _, focused in
                if focused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                    }
                }
            }
            .onAppear {
                if !isPresetSize {
                    customFontSizeText = "\(Int(themeManager.bodyFontSize))"
                }
            }
    }

    // MARK: - About Panel

    private var aboutPanel: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)

            VStack(spacing: 6) {
                Text("Jot")
                    .font(FontManager.heading(size: 28, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundColor(Color("SettingsPrimaryTextColor"))

                Text("Version \(appVersion)")
                    .font(FontManager.metadata(size: 12, weight: .medium))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Contact Panel

    private var contactPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 48) {
                emailSection
                feedbackSection
            }
            .padding(.vertical, contentVerticalPadding)
        }
        .scrollClipDisabled()
    }

    // MARK: - Email Section

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Email")

            HStack {
                Text(developerEmail)
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .tracking(-0.2)
                    .foregroundColor(Color("SettingsPrimaryTextColor"))

                Spacer()

                HStack(spacing: 2) {
                    if showCopiedConfirmation {
                        Text("COPIED")
                            .font(FontManager.metadata(size: 9, weight: .medium))
                            .tracking(-0.2)
                            .foregroundColor(Color("SettingsPlaceholderTextColor"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color("HoverBackgroundColor"))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else {
                        contactIconButton(
                            icon: "IconSquareBehindSquare6",
                            isHovered: hoveredCopyButton
                        ) {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(developerEmail, forType: .string)
                            #endif
                            withAnimation(.smooth(duration: 0.2)) {
                                showCopiedConfirmation = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.smooth(duration: 0.2)) {
                                    showCopiedConfirmation = false
                                }
                            }
                        }
                        .onHover { hoveredCopyButton = $0 }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    contactIconButton(
                        icon: "IconEmail2",
                        isHovered: hoveredMailButton
                    ) {
                        if let url = URL(string: "mailto:\(developerEmail)") {
                            #if os(macOS)
                            NSWorkspace.shared.open(url)
                            #endif
                        }
                    }
                    .onHover { hoveredMailButton = $0 }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))
            )
            .overlay(
                Capsule()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func contactIconButton(icon: String, isHovered: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SettingsIconSecondaryColor"))
                .frame(width: 18, height: 18)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? Color("HoverBackgroundColor") : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
    }

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Your feedback is welcomed")
            feedbackTextArea
        }
        .frame(maxHeight: 254)
    }

    private func feedbackTypePill(_ type: FeedbackType) -> some View {
        let isSelected = feedbackType == type
        let isHovered = hoveredFeedbackType == type

        return Button {
            feedbackType = type
        } label: {
            HStack(spacing: 8) {
                Image(type.iconAsset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(isSelected ? type.selectedText(for: colorScheme) : Color("SettingsIconSecondaryColor"))
                    .frame(width: 18, height: 18)

                Text(type.rawValue)
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .tracking(-0.2)
                    .foregroundColor(isSelected ? type.selectedText(for: colorScheme) : Color("SettingsPrimaryTextColor"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? type.selectedBackground(for: colorScheme)
                            : isHovered
                                ? Color("HoverBackgroundColor")
                                : Color("SettingsInnerPillColor")
                    )
            )
        }
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .onHover { hovering in
            if hovering {
                hoveredFeedbackType = type
            } else if hoveredFeedbackType == type {
                hoveredFeedbackType = nil
            }
        }
    }

    private var feedbackTextArea: some View {
        VStack(alignment: .trailing, spacing: 0) {
            FeedbackTextView(
                text: $feedbackText,
                font: .systemFont(ofSize: 14, weight: .regular),
                textColor: NSColor(named: "SettingsPrimaryTextColor") ?? .labelColor
            )
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)

            HStack {
                HStack(spacing: 8) {
                    ForEach(FeedbackType.allCases, id: \.self) { type in
                        feedbackTypePill(type)
                    }
                }
                .opacity(feedbackState == .sent ? 0 : 1)

                Spacer()

                sendButton
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var sendButton: some View {
        if feedbackState == .sent {
            HStack(spacing: 5) {
                Image("IconCelebrate")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .scaleEffect(celebrateScale)
                    .rotationEffect(.degrees(celebrateRotation))

                Text("Feedback received")
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .tracking(-0.2)
                    .foregroundColor(.white)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity
                    ))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 34/255, green: 197/255, blue: 94/255))
                    .matchedGeometryEffect(id: "sendButtonBg", in: feedbackAnimation)
            )
        } else {
            Button {
                sendFeedback()
            } label: {
                Text("Send")
                    .font(FontManager.heading(size: 15, weight: .medium))
                    .tracking(-0.2)
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color("SettingsSelectionOrange"))
                            .matchedGeometryEffect(id: "sendButtonBg", in: feedbackAnimation)
                    )
                    .background(
                        Capsule()
                            .fill(hoveredSendButton ? Color("HoverBackgroundColor") : Color.clear)
                            .padding(-2)
                    )
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
            .onHover { hoveredSendButton = $0 }
            .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)
            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func sendFeedback() {
        let payload: [String: String] = [
            "email": developerEmail,
            "message": feedbackText,
            "_subject": feedbackType.mailSubject
        ]

        var request = URLRequest(url: URL(string: "https://formspree.io/f/xaqpyade")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request).resume()

        celebrateScale = 0
        celebrateRotation = 0

        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            feedbackState = .sent
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.15)) {
            celebrateScale = 1.0
            celebrateRotation = -15
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.45)) {
            celebrateRotation = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                feedbackState = .idle
                feedbackText = ""
                celebrateScale = 0
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(FontManager.heading(size: 12, weight: .medium))
            .tracking(0)
            .foregroundColor(Color("SettingsPlaceholderTextColor"))
    }

    private func settingsSelectionLabel(_ text: String, isSelected: Bool) -> some View {
        Text(text)
            .font(FontManager.heading(size: 13, weight: .medium))
            .tracking(-0.1)
            .foregroundColor(isSelected ? Color("ButtonPrimaryTextColor") : Color("SettingsPrimaryTextColor"))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? Color("SettingsSelectionOrange") : Color.clear)
            )
            .frame(maxWidth: .infinity)
    }
}

private struct AppIconView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSApp.applicationIconImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
}

private struct FeedbackTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 5
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = font
        textView.textColor = textColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }
    }
}
