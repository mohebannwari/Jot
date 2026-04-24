//
//  MapInsertPrompt.swift
//  Jot
//

import SwiftUI

struct MapInsertPrompt: View {
    @ObservedObject var service: MapSearchService
    let onSelect: (MapSearchService.Result) -> Void
    let onCancel: () -> Void

    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image("IconMap")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundColor(Color("SecondaryTextColor"))

                TextField("Search for a place", text: $service.query)
                    .textFieldStyle(.plain)
                    .jotUI(FontManager.uiLabel4(weight: .regular))
                    .foregroundColor(Color("PrimaryTextColor"))
                    .focused($isQueryFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        guard let firstResult = service.results.first else { return }
                        onSelect(firstResult)
                    }

                if service.isResolvingSelection {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(FontManager.uiPro(size: 14, weight: .semibold).font)
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
            }

            if !service.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(service.results.prefix(5))) { result in
                        Button {
                            onSelect(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .jotUI(FontManager.uiLabel3(weight: .regular))
                                    .foregroundColor(Color("PrimaryTextColor"))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(FontManager.heading(size: 11, weight: .regular))
                                        .foregroundColor(Color("SecondaryTextColor"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .macPointingHandCursor()
                        .hoverContainer(cornerRadius: 14)
                    }
                }
            } else if !service.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text((service.errorMessage ?? "No places found").uppercased())
                    .jotUI(FontManager.uiLabel5(weight: .regular))
                    .foregroundColor(Color("SecondaryTextColor"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: 340)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isQueryFocused = true
            }
        }
        .onExitCommand {
            onCancel()
        }
    }
}
