import SwiftUI

struct SettingsPage: View {
    @Binding var isPresented: Bool
    /// Matches note detail sticky header vertical inset (traffic lights vs inset pane).
    let titleTopPadding: CGFloat

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var activeTab: SettingsTab = .general
    @State private var hoveredTab: SettingsTab?
    @State private var hoveredTheme: AppTheme?
    @State private var hoveredBodyFontStyle: BodyFontStyle?
    @State private var hoveredLineSpacing: LineSpacing?

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

    /// Leading inset for the settings tab list from the detail pane edge.
    private let tabLeadingInset: CGFloat = 40
    /// Vertical gap between tab labels only (no per-tab padding).
    private let tabVerticalSpacing: CGFloat = 12
    /// Space between the compact title row and the tab/content body.
    private let titleToBodySpacing: CGFloat = 16
    private let contentVerticalPadding: CGFloat = 8

    /// Pinned "Settings" title strip: title row plus a taller masked fade so scrolled content clears the title.
    private let settingsTitleChromeHeight: CGFloat = 84

    /// Same smootherstep mask as ``NoteDetailView.headerMaskGradient`` (scroll-underlay fade).
    private static let settingsHeaderMaskGradient: LinearGradient = {
        let steps = 40
        let stops: [Gradient.Stop] = (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let eased = 1.0 - (t * t * t * (t * (t * 6 - 15) + 10))
            return .init(color: Color.white.opacity(eased), location: t)
        }
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .top, endPoint: .bottom)
    }()

    /// Scroll (and tab) content starts below the overlaid title chrome; matches title row + gap under it.
    private var settingsContentTopInsetUnderChrome: CGFloat {
        titleTopPadding + settingsTitleChromeHeight + titleToBodySpacing
    }

    private let themeCardHeight: CGFloat = 91

    private let bodyFontCardWidth: CGFloat = 122
    private let bodyFontCardHeight: CGFloat = 91
    private let bodyFontCardRadius: CGFloat = 22

    private let lineSpacingCardWidth: CGFloat = 122
    private let lineSpacingCardHeight: CGFloat = 91
    private let lineSpacingCardRadius: CGFloat = 22

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
        case idle, sent, sendFailed
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
        ZStack(alignment: .top) {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    contentColumn
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .zIndex(0)

                tabColumn
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, tabLeadingInset)
                    .padding(.top, settingsContentTopInsetUnderChrome + contentVerticalPadding)
                    .zIndex(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, 24)

            settingsTitleChrome
                .frame(maxWidth: .infinity, alignment: .top)
                .zIndex(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    // MARK: - Title chrome (matches NoteDetailView sticky header material + mask)

    private var settingsTitleChrome: some View {
        VStack(spacing: 0) {
            // Opaque band flush to the pane top so scrolled content cannot peek above the mask strip.
            Rectangle()
                .fill(themeManager.tintedPaneSurface(for: colorScheme))
                .frame(height: titleTopPadding)
                .allowsHitTesting(false)

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(themeManager.tintedPaneSurface(for: colorScheme))
                    .mask(Self.settingsHeaderMaskGradient)
                    .frame(height: settingsTitleChromeHeight)
                    .allowsHitTesting(false)

                HStack {
                    Spacer()
                    Text("Settings")
                        .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .medium))
                        .foregroundColor(Color("PrimaryTextColor").opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 80)
                    Spacer()
                }
                .frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// Selected tab uses the main text token at full opacity; inactive matches sticky-title opacity parity.
    private func tabForeground(isSelected: Bool, isHovered: Bool) -> Color {
        let base = Color("PrimaryTextColor")
        if isSelected {
            return base
        }
        if isHovered {
            return base.opacity(0.65)
        }
        return base.opacity(0.5)
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
                .font(FontManager.heading(size: 13, weight: .medium))
                .tracking(-0.2)
                .foregroundColor(tabForeground(isSelected: isSelected, isHovered: isHovered))
                .animation(.jotHover, value: isHovered)
                .animation(.jotHover, value: isSelected)
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
                BackupSettingsPanel(scrollContentTopInset: settingsContentTopInsetUnderChrome + contentVerticalPadding)
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

                // Shortcuts (grouped card matches Sort options: 22pt radius via settingsGroupedCard).
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Shortcuts")

                    settingsGroupedCard {
                        // Same title/subtitle spacing as settingsCheckbox (VStack spacing 2). The recorder
                        // sits in a trailing column so its height does not sit between title and subtitle.
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Floating Note")
                                    .font(FontManager.heading(size: 13, weight: .medium))
                                    .tracking(-0.2)
                                    .foregroundColor(Color("SettingsPrimaryTextColor"))

                                Text(
                                    "Open a floating note panel from any app using a global keyboard shortcut."
                                )
                                .font(FontManager.heading(size: 11, weight: .regular))
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HotKeyRecorderView(
                                hotKey: $themeManager.quickNoteHotKey,
                                onChange: { newHotKey in
                                    if let hk = newHotKey {
                                        let other =
                                            themeManager.startMeetingSessionHotKey
                                            ?? QuickNoteHotKey.defaultStartMeetingSession
                                        if hk == other { return false }
                                        return GlobalHotKeyManager.shared.register(hk, slot: .quickNote)
                                    } else {
                                        GlobalHotKeyManager.shared.unregister(slot: .quickNote)
                                        return true
                                    }
                                }
                            )
                        }

                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start Meeting Session")
                                    .font(FontManager.heading(size: 13, weight: .medium))
                                    .tracking(-0.2)
                                    .foregroundColor(Color("SettingsPrimaryTextColor"))

                                Text(
                                    "Open Jot's command palette in pick-a-note-for-meeting mode from any app."
                                )
                                .font(FontManager.heading(size: 11, weight: .regular))
                                .foregroundColor(Color("SettingsPlaceholderTextColor"))
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HotKeyRecorderView(
                                hotKey: $themeManager.startMeetingSessionHotKey,
                                onChange: { newHotKey in
                                    if let hk = newHotKey {
                                        let other = themeManager.quickNoteHotKey ?? QuickNoteHotKey.default
                                        if hk == other { return false }
                                        return GlobalHotKeyManager.shared.register(
                                            hk, slot: .startMeetingSession)
                                    } else {
                                        GlobalHotKeyManager.shared.unregister(slot: .startMeetingSession)
                                        return true
                                    }
                                }
                            )
                        }
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
                                    .font(FontManager.heading(size: 13, weight: .medium))
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
                                        .font(FontManager.heading(size: 13, weight: .medium))
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
                                        .font(FontManager.heading(size: 13, weight: .medium))
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
                                                .scaledToFit()
                                                .frame(width: 15, height: 15)
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
                                                .scaledToFit()
                                                .frame(width: 15, height: 15)
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
                                        .font(FontManager.heading(size: 13, weight: .medium))
                                        .tracking(-0.5)
                                        // Was literally AccentColor light (#2563EB) hardcoded inline;
                                        // use the token so dark-mode + tint-hue adjustments carry.
                                        .foregroundColor(Color("AccentColor"))
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
                                    .fill(themeManager.tintedSettingsInnerPill(for: colorScheme))
                                    .frame(width: 15, height: 15)
                                Text("?")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                            }
                        }
                        .buttonStyle(.plain)
                        .macPointingHandCursor()
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.top, settingsContentTopInsetUnderChrome + contentVerticalPadding)
            .padding(.bottom, contentVerticalPadding)
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
                    .font(FontManager.heading(size: 13, weight: .medium))
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
    }

    private func settingsGroupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 18) {
            content()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))
        )
    }

    private func settingsCheckbox(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>, standalone: Bool = false) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isOn.wrappedValue
                              ? Color("ButtonPrimaryBgColor")
                              : Color("CheckboxUncheckedFillColor"))
                        .frame(width: 15, height: 15)

                    Circle()
                        .strokeBorder(isOn.wrappedValue
                                      ? Color.clear
                                      : Color("CheckboxUncheckedStrokeColor"), lineWidth: 1)
                        .frame(width: 15, height: 15)

                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color("ButtonPrimaryTextColor"))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FontManager.heading(size: 13, weight: .medium))
                        .tracking(-0.2)
                        .foregroundColor(Color("SettingsPrimaryTextColor"))

                    if let subtitle {
                        Text(subtitle)
                            .font(FontManager.heading(size: 11, weight: .regular))
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
                tintSection
                typographySection
                bodyFontSection
                lineSpacingSection
            }
            .padding(.top, settingsContentTopInsetUnderChrome + contentVerticalPadding)
            .padding(.bottom, contentVerticalPadding)
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
                    // `.clipShape` on a `.scaledToFill` image masks overflow to the rounded rect;
                    // no separate `.clipped()` needed. Previously both were stacked, which made
                    // SwiftUI run two rasterization passes on the same frame.
                    .clipShape(RoundedRectangle(cornerRadius: bodyFontCardRadius, style: .continuous))

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

    // MARK: - Tint Section

    private var tintSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Colors")

            VStack(alignment: .leading, spacing: 8) {
                settingsGroupedCard {
                    tintRow(
                        title: "Intensity",
                        caption: "Control how strongly the tint is applied",
                        trailing: "\(Int((themeManager.tintIntensity * 100).rounded()))%"
                    ) {
                        Slider(value: $themeManager.tintIntensity, in: 0...1)
                            .tint(Color("AccentColor"))
                            .frame(width: 140)
                    }

                    tintRow(
                        title: "Hue",
                        caption: "Choose a tint color"
                    ) {
                        HueGradientSlider(value: $themeManager.tintHue)
                            .frame(width: 140)
                    }
                }

                Text("Apply a subtle color wash to the app window and detail pane. The tint adapts to light and dark mode automatically — softer in light, deeper in dark.")
                    .font(FontManager.heading(size: 11, weight: .regular))
                    .foregroundColor(Color("SettingsPlaceholderTextColor"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }
        }
    }

    private func tintRow<Control: View>(
        title: String,
        caption: String,
        trailing: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FontManager.heading(size: 13, weight: .semibold))
                    .foregroundStyle(Color("SettingsPrimaryTextColor"))
                Text(caption)
                    .font(FontManager.heading(size: 11, weight: .regular))
                    .foregroundStyle(Color("SettingsPlaceholderTextColor"))
            }
            Spacer(minLength: 16)
            control()
            if let trailing {
                Text(trailing)
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundStyle(Color("SettingsPlaceholderTextColor"))
                    .frame(width: 32, alignment: .trailing)
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

    // MARK: - Typography (body font size)

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Typography")

            settingsGroupedCard {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body font size")
                            .font(FontManager.heading(size: 13, weight: .semibold))
                            .foregroundStyle(Color("SettingsPrimaryTextColor"))
                        Text("Font size for the Body text")
                            .font(FontManager.heading(size: 11, weight: .regular))
                            .foregroundStyle(Color("SettingsPlaceholderTextColor"))
                    }
                    Spacer(minLength: 16)
                    SettingsNumericCounterPill(
                        value: Binding(
                            get: { Int(round(themeManager.bodyFontSize)) },
                            set: { themeManager.bodyFontSize = CGFloat($0) }
                        ),
                        range: 10...28
                    )
                }
            }
        }
    }

    // MARK: - About Panel

    private var aboutPanel: some View {
        VStack(spacing: 0) {
            // Push the card down so its top aligns with the first sidebar tab (same inset as ``tabColumn``).
            Color.clear
                .frame(height: settingsContentTopInsetUnderChrome + contentVerticalPadding)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)

                    VStack(alignment: .center, spacing: 6) {
                        Text("Jot")
                            .font(FontManager.heading(size: 28, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundColor(Color("SettingsPrimaryTextColor"))
                            .multilineTextAlignment(.center)

                        Text("Version \(appVersion)")
                            .font(FontManager.metadata(size: 11, weight: .medium))
                            .foregroundColor(Color("SettingsPlaceholderTextColor"))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
            .padding(.top, settingsContentTopInsetUnderChrome + contentVerticalPadding)
            .padding(.bottom, contentVerticalPadding)
        }
        .scrollClipDisabled()
    }

    // MARK: - Email Section

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Email")

            HStack {
                Text(developerEmail)
                    .font(FontManager.heading(size: 13, weight: .medium))
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
        }
    }

    private func contactIconButton(icon: String, isHovered: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("SettingsIconSecondaryColor"))
                .frame(width: 15, height: 15)
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
                    .frame(width: 15, height: 15)

                Text(type.rawValue)
                    .font(FontManager.heading(size: 13, weight: .medium))
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
                                : themeManager.tintedSettingsInnerPill(for: colorScheme)
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
                .opacity((feedbackState == .sent || feedbackState == .sendFailed) ? 0 : 1)

                Spacer()

                sendButton
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colorScheme == .light ? Color.white : Color("SettingsOptionCardColor"))
        )
    }

    @ViewBuilder
    private var sendButton: some View {
        if feedbackState == .sendFailed {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    feedbackState = .idle
                }
            } label: {
                Text("Could not send — tap to try again")
                    .font(FontManager.heading(size: 13, weight: .medium))
                    .tracking(-0.2)
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color("SettingsSelectionOrange"))
                    )
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()
        } else if feedbackState == .sent {
            HStack(spacing: 5) {
                Image("IconCelebrate")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(width: 15, height: 15)
                    .scaleEffect(celebrateScale)
                    .rotationEffect(.degrees(celebrateRotation))

                Text("Feedback received")
                    .font(FontManager.heading(size: 13, weight: .medium))
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
                    // Was Tailwind green-500 (#22C55E) hardcoded; SwiftUI `.green` is
                    // theme-aware and close enough for a transient "feedback sent" state.
                    .fill(Color.green)
                    .matchedGeometryEffect(id: "sendButtonBg", in: feedbackAnimation)
            )
        } else {
            Button {
                sendFeedback()
            } label: {
                Text("Send")
                    .font(FontManager.heading(size: 13, weight: .medium))
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

        guard let feedbackURL = URL(string: "https://formspree.io/f/xaqpyade") else { return }
        var request = URLRequest(url: feedbackURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { _, response, error in
            Task { @MainActor in
                let http = response as? HTTPURLResponse
                let ok = error == nil && http.map { (200..<300).contains($0.statusCode) } == true
                guard ok else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        feedbackState = .sendFailed
                    }
                    return
                }

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
        }.resume()
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(FontManager.heading(size: 11, weight: .medium))
            .tracking(0)
            .foregroundColor(Color("SettingsPlaceholderTextColor"))
    }

    private func settingsSelectionLabel(_ text: String, isSelected: Bool) -> some View {
        Text(text)
            .font(FontManager.heading(size: 12, weight: .medium))
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
