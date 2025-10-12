//
//  ImagePickerControl.swift
//  Noty
//
//  Photo picker button with liquid glass styling for image selection.
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
#if os(macOS)
import AppKit
#else
import UIKit
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
            Image(systemName: "photo.on.rectangle.angled")
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
            ImagePicker(
                onImagesSelected: { urls in
                    // Dismiss the picker first
                    showingPicker = false
                    
                    // Then insert all selected images
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        for url in urls {
                            onImageSelected(url)
                        }
                    }
                },
                onDismiss: {
                    showingPicker = false
                }
            )
            .frame(minWidth: 800, minHeight: 600)
        }
    }
}

// MARK: - Platform-Specific Image Picker

#if os(macOS)

// MARK: - Native macOS Photo Picker with Multiple Selection
struct ImagePicker: View {
    let onImagesSelected: ([URL]) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        // Use the native photo picker with its built-in UI
        // The native picker already provides selection count and Add/Cancel buttons
        PhotoPickerRepresentable(
            onImagesSelected: onImagesSelected,
            onCancel: onDismiss
        )
        .ignoresSafeArea()
    }
}

private struct PhotoPickerRepresentable: NSViewControllerRepresentable {
    let onImagesSelected: ([URL]) -> Void
    let onCancel: () -> Void
    
    func makeNSViewController(context: Context) -> PHPickerViewController {
        // Configure the picker to show only images from the Photos library
        // Allow multiple selection (up to 10 images at once)
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 10 // Allow selecting up to 10 images
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        
        // Set preferred size for the picker
        picker.preferredContentSize = NSSize(width: 800, height: 600)
        
        return picker
    }
    
    func updateNSViewController(_ nsViewController: PHPickerViewController, context: Context) {
        // Update preferred size if needed
        nsViewController.preferredContentSize = NSSize(width: 800, height: 600)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesSelected: onImagesSelected, onCancel: onCancel)
    }
    
    // Coordinator handles the PHPickerViewController delegate callbacks
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagesSelected: ([URL]) -> Void
        let onCancel: () -> Void
        
        init(onImagesSelected: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onImagesSelected = onImagesSelected
            self.onCancel = onCancel
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // User cancelled or finished selecting
            if results.isEmpty {
                NSLog("ImagePicker: No images selected, dismissing")
                onCancel()
                return
            }
            
            NSLog("ImagePicker: User selected \(results.count) image(s)")
            
            // Load all selected images asynchronously
            let dispatchGroup = DispatchGroup()
            var loadedURLs: [URL] = []
            
            for result in results {
                dispatchGroup.enter()
                
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        NSLog("ImagePicker: Error loading image: %@", error.localizedDescription)
                        return
                    }
                    
                    guard let url = url else {
                        NSLog("ImagePicker: No URL returned from picker")
                        return
                    }
                    
                    // Copy the file to a temporary location since the original URL will be cleaned up
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    
                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        NSLog("ImagePicker: Copied image to temporary URL: %@", tempURL.path)
                        loadedURLs.append(tempURL)
                    } catch {
                        NSLog("ImagePicker: Failed to copy image: %@", error.localizedDescription)
                    }
                }
            }
            
            // Wait for all images to load, then notify
            dispatchGroup.notify(queue: .main) {
                NSLog("ImagePicker: Finished loading \(loadedURLs.count) image(s)")
                if !loadedURLs.isEmpty {
                    // Pass the loaded images and let the callback handle dismissal
                    self.onImagesSelected(loadedURLs)
                } else {
                    // No images loaded successfully, just cancel
                    self.onCancel()
                }
            }
        }
    }
}

#else

// MARK: - iOS Photo Picker with Multiple Selection
struct ImagePicker: UIViewControllerRepresentable {
    let onImagesSelected: ([URL]) -> Void
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 10 // Allow multiple selection on iOS too
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesSelected: onImagesSelected, onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagesSelected: ([URL]) -> Void
        let onDismiss: () -> Void
        
        init(onImagesSelected: @escaping ([URL]) -> Void, onDismiss: @escaping () -> Void) {
            self.onImagesSelected = onImagesSelected
            self.onDismiss = onDismiss
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Dismiss first on iOS (works properly)
            picker.dismiss(animated: true)
            onDismiss()
            
            guard !results.isEmpty else {
                NSLog("ImagePicker: No images selected")
                return
            }
            
            NSLog("ImagePicker: User selected \(results.count) image(s)")
            
            // Load all selected images
            let dispatchGroup = DispatchGroup()
            var loadedURLs: [URL] = []
            
            for result in results {
                dispatchGroup.enter()
                
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                    defer { dispatchGroup.leave() }
                    
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
                        loadedURLs.append(tempURL)
                    } catch {
                        NSLog("ImagePicker: Failed to copy image: %@", error.localizedDescription)
                    }
                }
            }
            
            // Wait for all images to load
            dispatchGroup.notify(queue: .main) {
                NSLog("ImagePicker: Finished loading \(loadedURLs.count) image(s)")
                if !loadedURLs.isEmpty {
                    self.onImagesSelected(loadedURLs)
                }
            }
        }
    }
}

#endif

