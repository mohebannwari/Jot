//
//  SmartFolderEditorSheet.swift
//  Jot
//
//  MVP editor for smart-folder predicates — functional layout; polish later.
//  Smart Folder sheet: metadata labels use mono 11 all caps (`jotMetadataLabelTypography`);
//  the first three field titles are slightly inset; text fields use capsule clips for parity.
//

import SwiftUI

struct SmartFolderEditorSheet: View {
    let notes: [Note]
    var editingSmartFolder: SmartFolder?
    let onSave: (String, SmartFolderPredicate) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var tagsText: String
    @State private var keyword: String
    @State private var dateFilterEnabled: Bool
    @State private var dateFieldChoice: SmartFolderDateField
    @State private var dateStartEnabled: Bool
    @State private var dateEndEnabled: Bool
    @State private var dateStart: Date
    @State private var dateEnd: Date
    @State private var requirePinned: Bool
    @State private var requireLocked: Bool
    @State private var requireHasAttachments: Bool
    @State private var requireHasChecklist: Bool

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, tags, keyword
    }

    init(
        notes: [Note],
        editingSmartFolder: SmartFolder? = nil,
        onSave: @escaping (String, SmartFolderPredicate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.notes = notes
        self.editingSmartFolder = editingSmartFolder
        self.onSave = onSave
        self.onCancel = onCancel

        if let sf = editingSmartFolder {
            _name = State(initialValue: sf.name)
            _tagsText = State(initialValue: sf.predicate.requiredTags?.joined(separator: ", ") ?? "")
            _keyword = State(initialValue: sf.predicate.keyword ?? "")
            let df = sf.predicate.dateField
            let hasDate = df != nil && (sf.predicate.dateStart != nil || sf.predicate.dateEnd != nil)
            _dateFilterEnabled = State(initialValue: hasDate)
            _dateFieldChoice = State(initialValue: df ?? .modified)
            _dateStartEnabled = State(initialValue: sf.predicate.dateStart != nil)
            _dateEndEnabled = State(initialValue: sf.predicate.dateEnd != nil)
            _dateStart = State(initialValue: sf.predicate.dateStart ?? Date())
            _dateEnd = State(initialValue: sf.predicate.dateEnd ?? Date())
            _requirePinned = State(initialValue: sf.predicate.requirePinned == true)
            _requireLocked = State(initialValue: sf.predicate.requireLocked == true)
            _requireHasAttachments = State(initialValue: sf.predicate.requireHasAttachments == true)
            _requireHasChecklist = State(initialValue: sf.predicate.requireHasChecklist == true)
        } else {
            _name = State(initialValue: "Smart Folder")
            _tagsText = State(initialValue: "")
            _keyword = State(initialValue: "")
            _dateFilterEnabled = State(initialValue: false)
            _dateFieldChoice = State(initialValue: .modified)
            _dateStartEnabled = State(initialValue: false)
            _dateEndEnabled = State(initialValue: false)
            _dateStart = State(initialValue: Date())
            _dateEnd = State(initialValue: Date())
            _requirePinned = State(initialValue: false)
            _requireLocked = State(initialValue: false)
            _requireHasAttachments = State(initialValue: false)
            _requireHasChecklist = State(initialValue: false)
        }
    }

    private var draftPredicate: SmartFolderPredicate {
        buildPredicateFromState()
    }

    private var matchCount: Int {
        draftPredicate.matchCount(in: notes)
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && draftPredicate.hasAnyActiveCriterion
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nameField
                    tagsField
                    keywordField
                    dateSection
                    togglesSection
                    matchCountLabel
                }
                .padding(.horizontal, 4)
                // Extra space below the sheet chrome so the first label does not sit tight under the top edge.
                .padding(.top, 8)
            }
            .frame(maxHeight: 420)

            buttonSection
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .frame(width: 400)
        .onAppear { focusedField = .name }
    }

    /// Leading inset for the first three field titles only (Name / Tags / Keyword), per layout spec.
    private static let insetFieldTitleLeading: CGFloat = 10

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .jotMetadataLabelTypography()
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.leading, Self.insetFieldTitleLeading)
            TextField("Smart folder name", text: $name)
                .jotUI(FontManager.uiLabel2(weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .name)
                .padding(12)
                .background(themeManager.tintedDetailPane(for: colorScheme))
                .clipShape(Capsule())
        }
    }

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags (comma-separated)")
                .jotMetadataLabelTypography()
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.leading, Self.insetFieldTitleLeading)
            TextField("work, ideas", text: $tagsText)
                .jotUI(FontManager.uiLabel4(weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .tags)
                .padding(12)
                .background(themeManager.tintedDetailPane(for: colorScheme))
                .clipShape(Capsule())
        }
    }

    private var keywordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyword")
                .jotMetadataLabelTypography()
                .foregroundColor(Color("SecondaryTextColor"))
                .padding(.leading, Self.insetFieldTitleLeading)
            TextField("Search in title and body", text: $keyword)
                .jotUI(FontManager.uiLabel4(weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .keyword)
                .padding(12)
                .background(themeManager.tintedDetailPane(for: colorScheme))
                .clipShape(Capsule())
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Filter by date", isOn: $dateFilterEnabled)
                .jotUI(FontManager.uiLabel3(weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))

            if dateFilterEnabled {
                Picker("Date field", selection: $dateFieldChoice) {
                    Text("Date modified").tag(SmartFolderDateField.modified)
                    Text("Date created").tag(SmartFolderDateField.created)
                }
                .pickerStyle(.segmented)

                Toggle("On or after", isOn: $dateStartEnabled)
                    .jotUI(FontManager.uiLabel3(weight: .regular))
                if dateStartEnabled {
                    DatePicker("Start", selection: $dateStart, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }

                Toggle("On or before", isOn: $dateEndEnabled)
                    .jotUI(FontManager.uiLabel3(weight: .regular))
                if dateEndEnabled {
                    DatePicker("End", selection: $dateEnd, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
        }
    }

    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Include only")
                .jotMetadataLabelTypography()
                .foregroundColor(Color("SecondaryTextColor"))

            Toggle("Pinned notes", isOn: $requirePinned)
                .jotUI(FontManager.uiLabel3(weight: .regular))
            Toggle("Locked notes", isOn: $requireLocked)
                .jotUI(FontManager.uiLabel3(weight: .regular))
            Toggle("Has attachments", isOn: $requireHasAttachments)
                .jotUI(FontManager.uiLabel3(weight: .regular))
            Toggle("Has checklist items", isOn: $requireHasChecklist)
                .jotUI(FontManager.uiLabel3(weight: .regular))
        }
    }

    private var matchCountLabel: some View {
        Text("Matches \(matchCount) notes")
            .jotMetadataLabelTypography()
            .foregroundColor(Color("SecondaryTextColor"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var buttonSection: some View {
        VStack(spacing: 8) {
            Button {
                submit()
            } label: {
                Text(editingSmartFolder != nil ? "Save" : "Create")
                    .jotUI(FontManager.uiLabel4(weight: .regular))
                    .foregroundColor(Color("ButtonPrimaryTextColor"))
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(Color("ButtonPrimaryBgColor"))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1.0 : 0.4)
            .subtleHoverScale(1.02)

            Button {
                HapticManager.shared.buttonTap()
                onCancel()
            } label: {
                Text("Cancel")
                    .jotUI(FontManager.uiLabel4(weight: .regular))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .subtleHoverScale(1.02)
        }
        .padding(.top, 8)
    }

    private func buildPredicateFromState() -> SmartFolderPredicate {
        var p = SmartFolderPredicate()
        let parsedTags = Self.parseTags(tagsText)
        if !parsedTags.isEmpty {
            p.requiredTags = parsedTags
        }
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kw.isEmpty {
            p.keyword = kw
        }
        if dateFilterEnabled && (dateStartEnabled || dateEndEnabled) {
            p.dateField = dateFieldChoice
            if dateStartEnabled {
                p.dateStart = dateStart
            }
            if dateEndEnabled {
                p.dateEnd = dateEnd
            }
        }
        if requirePinned { p.requirePinned = true }
        if requireLocked { p.requireLocked = true }
        if requireHasAttachments { p.requireHasAttachments = true }
        if requireHasChecklist { p.requireHasChecklist = true }
        return p
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pred = buildPredicateFromState()
        guard pred.hasAnyActiveCriterion else { return }
        HapticManager.shared.buttonTap()
        onSave(trimmed, pred)
    }

    private static func parseTags(_ text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
