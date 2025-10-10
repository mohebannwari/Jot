//
//  ImagePickerControl.swift
//  Noty
//
//  Photo picker button with liquid glass styling for image selection.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
import PhotosUI
#endif

public struct ImagePickerControl: View {
    let onImageSelected: (URL) -> Void
    
    @State private var showingPicker = false
    @Namespace private var glassNamespace
    
    public init(onImageSelected: @escaping (URL) -> Void) {
        self.onImageSelected = onImageSelected
    }
    
    public var body: some View {
        Button {
            HapticManager.shared.buttonTap()
            showingPicker = true
        } label: {
            Image(systemName: "photo")
                .font(FontManager.heading(size: 20, weight: .medium))
                .foregroundStyle(Color("PrimaryTextColor"))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .background(Circle().fill(.clear))
        .liquidGlass(in: Circle())
        .accessibilityLabel(Text("Add image"))
        .sheet(isPresented: $showingPicker) {
            ImagePicker(onImageSelected: onImageSelected)
        }
    }
}

// MARK: - Platform-Specific Image Picker

#if os(macOS)

struct ImagePicker: View {
    let onImageSelected: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Select an Image")
                .font(.headline)
            
            Button("Choose from Files") {
                selectImage()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 300, height: 150)
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .bmp, .tiff]
        panel.message = "Select an image to add to your note"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                NSLog("ImagePicker: Selected image at %@", url.path)
                onImageSelected(url)
                dismiss()
            }
        }
    }
}

#else

struct ImagePicker: UIViewControllerRepresentable {
    let onImageSelected: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else {
                NSLog("ImagePicker: No image selected")
                return
            }
            
            // Load the image data
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                if let error = error {
                    NSLog("ImagePicker: Error loading image: %@", error.localizedDescription)
                    return
                }
                
                guard let url = url else {
                    NSLog("ImagePicker: No URL returned from picker")
                    return
                }
                
                // Copy to temporary location since the original URL may be cleaned up
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    NSLog("ImagePicker: Copied image to temporary URL: %@", tempURL.path)
                    
                    DispatchQueue.main.async {
                        self.parent.onImageSelected(tempURL)
                    }
                } catch {
                    NSLog("ImagePicker: Failed to copy image: %@", error.localizedDescription)
                }
            }
        }
    }
}

#endif

