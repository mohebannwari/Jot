//
//  ImageAttachmentView.swift
//  Jot
//
//  Displays inline images in the rich text editor.
//

import SwiftUI

import AppKit

struct ImageAttachmentView: View {
    let filename: String
    let maxWidth: CGFloat = 400
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?
    @State private var imageSize: CGSize = .zero
    
    var body: some View {
        Group {
            if let image = image {
                imageView(image)
            } else {
                placeholderView
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    @ViewBuilder
    private func imageView(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: maxWidth)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: colorScheme == .light ? 0.5 : 0)
            )
    }
    
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 200, height: 150)
            
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(FontManager.heading(size: 20, weight: .regular))
                    .foregroundColor(.gray)
                
                Text("Loading...")
                    .font(FontManager.heading(size: 12, weight: .regular))
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var borderColor: Color {
        colorScheme == .light
            ? Color.black.opacity(0.1)
            : Color.clear
    }
    
    private func loadImage() {
        guard let imageURL = ImageStorageManager.shared.getImageURL(for: filename) else {
            NSLog("ImageAttachmentView: Failed to get URL for image: %@", filename)
            return
        }

        if let loadedImage = NSImage(contentsOf: imageURL) {
            image = loadedImage
            imageSize = loadedImage.size
            NSLog("ImageAttachmentView: Loaded image %@ with size %@", filename, NSStringFromSize(loadedImage.size))
        } else {
            NSLog("ImageAttachmentView: Failed to load NSImage from %@", imageURL.path)
        }
    }
}
