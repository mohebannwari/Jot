//
//  ImagePickerControl.swift
//  Jot
//
//  Image picker button with liquid glass styling.
//  Uses NSOpenPanel for filesystem-wide image selection.
//

import SwiftUI
import UniformTypeIdentifiers

public struct ImagePickerControl: View {
    let onImageSelected: (URL) -> Void

    @Namespace private var glassNamespace

    public init(onImageSelected: @escaping (URL) -> Void) {
        self.onImageSelected = onImageSelected
    }

    public var body: some View {
        Button {
            HapticManager.shared.buttonTap()
            openImagePanel()
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(FontManager.icon(size: 16, weight: .medium))
                .foregroundStyle(Color("PrimaryTextColor"))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .background(Circle().fill(.clear))
        .liquidGlass(in: Circle())
        .accessibilityLabel(Text("Add image"))
    }

    private func openImagePanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Images"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                onImageSelected(url)
            }
        }
    }
}
