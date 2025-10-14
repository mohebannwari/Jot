import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = DeveloperToolsSupport.ColorResource(name: "AccentColor", bundle: resourceBundle)

    /// The "BackgroundColor" asset catalog color resource.
    static let background = DeveloperToolsSupport.ColorResource(name: "BackgroundColor", bundle: resourceBundle)

    /// The "ButtonPrimaryBgColor" asset catalog color resource.
    static let buttonPrimaryBg = DeveloperToolsSupport.ColorResource(name: "ButtonPrimaryBgColor", bundle: resourceBundle)

    /// The "ButtonPrimaryTextColor" asset catalog color resource.
    static let buttonPrimaryText = DeveloperToolsSupport.ColorResource(name: "ButtonPrimaryTextColor", bundle: resourceBundle)

    /// The "CardBackgroundColor" asset catalog color resource.
    static let cardBackground = DeveloperToolsSupport.ColorResource(name: "CardBackgroundColor", bundle: resourceBundle)

    /// The "HoverBackgroundColor" asset catalog color resource.
    static let hoverBackground = DeveloperToolsSupport.ColorResource(name: "HoverBackgroundColor", bundle: resourceBundle)

    /// The "MenuButtonColor" asset catalog color resource.
    static let menuButton = DeveloperToolsSupport.ColorResource(name: "MenuButtonColor", bundle: resourceBundle)

    /// The "PrimaryTextColor" asset catalog color resource.
    static let primaryText = DeveloperToolsSupport.ColorResource(name: "PrimaryTextColor", bundle: resourceBundle)

    /// The "SearchInputBackgroundColor" asset catalog color resource.
    static let searchInputBackground = DeveloperToolsSupport.ColorResource(name: "SearchInputBackgroundColor", bundle: resourceBundle)

    /// The "SecondaryTextColor" asset catalog color resource.
    static let secondaryText = DeveloperToolsSupport.ColorResource(name: "SecondaryTextColor", bundle: resourceBundle)

    /// The "SurfaceTranslucentColor" asset catalog color resource.
    static let surfaceTranslucent = DeveloperToolsSupport.ColorResource(name: "SurfaceTranslucentColor", bundle: resourceBundle)

    /// The "TagBackgroundColor" asset catalog color resource.
    static let tagBackground = DeveloperToolsSupport.ColorResource(name: "TagBackgroundColor", bundle: resourceBundle)

    /// The "TagTextColor" asset catalog color resource.
    static let tagText = DeveloperToolsSupport.ColorResource(name: "TagTextColor", bundle: resourceBundle)

    /// The "TertiaryTextColor" asset catalog color resource.
    static let tertiaryText = DeveloperToolsSupport.ColorResource(name: "TertiaryTextColor", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "WebClipLinkIcon" asset catalog image resource.
    static let webClipLinkIcon = DeveloperToolsSupport.ImageResource(name: "WebClipLinkIcon", bundle: resourceBundle)

    /// The "WebClipPlaceholder" asset catalog image resource.
    static let webClipPlaceholder = DeveloperToolsSupport.ImageResource(name: "WebClipPlaceholder", bundle: resourceBundle)

    /// The "checkmark_checked" asset catalog image resource.
    static let checkmarkChecked = DeveloperToolsSupport.ImageResource(name: "checkmark_checked", bundle: resourceBundle)

    /// The "checkmark_unchecked_DM" asset catalog image resource.
    static let checkmarkUncheckedDM = DeveloperToolsSupport.ImageResource(name: "checkmark_unchecked_DM", bundle: resourceBundle)

    /// The "checkmark_unchecked_LM" asset catalog image resource.
    static let checkmarkUncheckedLM = DeveloperToolsSupport.ImageResource(name: "checkmark_unchecked_LM", bundle: resourceBundle)

    /// The "note-card-thumbnail" asset catalog image resource.
    static let noteCardThumbnail = DeveloperToolsSupport.ImageResource(name: "note-card-thumbnail", bundle: resourceBundle)

    /// The "note-card-thumbnail-DM" asset catalog image resource.
    static let noteCardThumbnailDM = DeveloperToolsSupport.ImageResource(name: "note-card-thumbnail-DM", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "AccentColor" asset catalog color.
    static var accent: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .accent)
#else
        .init()
#endif
    }

    /// The "BackgroundColor" asset catalog color.
    static var background: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .background)
#else
        .init()
#endif
    }

    /// The "ButtonPrimaryBgColor" asset catalog color.
    static var buttonPrimaryBg: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .buttonPrimaryBg)
#else
        .init()
#endif
    }

    /// The "ButtonPrimaryTextColor" asset catalog color.
    static var buttonPrimaryText: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .buttonPrimaryText)
#else
        .init()
#endif
    }

    /// The "CardBackgroundColor" asset catalog color.
    static var cardBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .cardBackground)
#else
        .init()
#endif
    }

    /// The "HoverBackgroundColor" asset catalog color.
    static var hoverBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .hoverBackground)
#else
        .init()
#endif
    }

    /// The "MenuButtonColor" asset catalog color.
    static var menuButton: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .menuButton)
#else
        .init()
#endif
    }

    /// The "PrimaryTextColor" asset catalog color.
    static var primaryText: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .primaryText)
#else
        .init()
#endif
    }

    /// The "SearchInputBackgroundColor" asset catalog color.
    static var searchInputBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .searchInputBackground)
#else
        .init()
#endif
    }

    /// The "SecondaryTextColor" asset catalog color.
    static var secondaryText: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .secondaryText)
#else
        .init()
#endif
    }

    /// The "SurfaceTranslucentColor" asset catalog color.
    static var surfaceTranslucent: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .surfaceTranslucent)
#else
        .init()
#endif
    }

    /// The "TagBackgroundColor" asset catalog color.
    static var tagBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .tagBackground)
#else
        .init()
#endif
    }

    /// The "TagTextColor" asset catalog color.
    static var tagText: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .tagText)
#else
        .init()
#endif
    }

    /// The "TertiaryTextColor" asset catalog color.
    static var tertiaryText: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .tertiaryText)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "AccentColor" asset catalog color.
    static var accent: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .accent)
#else
        .init()
#endif
    }

    /// The "BackgroundColor" asset catalog color.
    static var background: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .background)
#else
        .init()
#endif
    }

    /// The "ButtonPrimaryBgColor" asset catalog color.
    static var buttonPrimaryBg: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .buttonPrimaryBg)
#else
        .init()
#endif
    }

    /// The "ButtonPrimaryTextColor" asset catalog color.
    static var buttonPrimaryText: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .buttonPrimaryText)
#else
        .init()
#endif
    }

    /// The "CardBackgroundColor" asset catalog color.
    static var cardBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .cardBackground)
#else
        .init()
#endif
    }

    /// The "HoverBackgroundColor" asset catalog color.
    static var hoverBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .hoverBackground)
#else
        .init()
#endif
    }

    /// The "MenuButtonColor" asset catalog color.
    static var menuButton: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .menuButton)
#else
        .init()
#endif
    }

    /// The "PrimaryTextColor" asset catalog color.
    static var primaryText: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .primaryText)
#else
        .init()
#endif
    }

    /// The "SearchInputBackgroundColor" asset catalog color.
    static var searchInputBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .searchInputBackground)
#else
        .init()
#endif
    }

    /// The "SecondaryTextColor" asset catalog color.
    static var secondaryText: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .secondaryText)
#else
        .init()
#endif
    }

    /// The "SurfaceTranslucentColor" asset catalog color.
    static var surfaceTranslucent: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .surfaceTranslucent)
#else
        .init()
#endif
    }

    /// The "TagBackgroundColor" asset catalog color.
    static var tagBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .tagBackground)
#else
        .init()
#endif
    }

    /// The "TagTextColor" asset catalog color.
    static var tagText: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .tagText)
#else
        .init()
#endif
    }

    /// The "TertiaryTextColor" asset catalog color.
    static var tertiaryText: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .tertiaryText)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "AccentColor" asset catalog color.
    static var accent: SwiftUI.Color { .init(.accent) }

    /// The "BackgroundColor" asset catalog color.
    static var background: SwiftUI.Color { .init(.background) }

    /// The "ButtonPrimaryBgColor" asset catalog color.
    static var buttonPrimaryBg: SwiftUI.Color { .init(.buttonPrimaryBg) }

    /// The "ButtonPrimaryTextColor" asset catalog color.
    static var buttonPrimaryText: SwiftUI.Color { .init(.buttonPrimaryText) }

    /// The "CardBackgroundColor" asset catalog color.
    static var cardBackground: SwiftUI.Color { .init(.cardBackground) }

    /// The "HoverBackgroundColor" asset catalog color.
    static var hoverBackground: SwiftUI.Color { .init(.hoverBackground) }

    /// The "MenuButtonColor" asset catalog color.
    static var menuButton: SwiftUI.Color { .init(.menuButton) }

    /// The "PrimaryTextColor" asset catalog color.
    static var primaryText: SwiftUI.Color { .init(.primaryText) }

    /// The "SearchInputBackgroundColor" asset catalog color.
    static var searchInputBackground: SwiftUI.Color { .init(.searchInputBackground) }

    /// The "SecondaryTextColor" asset catalog color.
    static var secondaryText: SwiftUI.Color { .init(.secondaryText) }

    /// The "SurfaceTranslucentColor" asset catalog color.
    static var surfaceTranslucent: SwiftUI.Color { .init(.surfaceTranslucent) }

    /// The "TagBackgroundColor" asset catalog color.
    static var tagBackground: SwiftUI.Color { .init(.tagBackground) }

    /// The "TagTextColor" asset catalog color.
    static var tagText: SwiftUI.Color { .init(.tagText) }

    /// The "TertiaryTextColor" asset catalog color.
    static var tertiaryText: SwiftUI.Color { .init(.tertiaryText) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "AccentColor" asset catalog color.
    static var accent: SwiftUI.Color { .init(.accent) }

    /// The "BackgroundColor" asset catalog color.
    static var background: SwiftUI.Color { .init(.background) }

    /// The "ButtonPrimaryBgColor" asset catalog color.
    static var buttonPrimaryBg: SwiftUI.Color { .init(.buttonPrimaryBg) }

    /// The "ButtonPrimaryTextColor" asset catalog color.
    static var buttonPrimaryText: SwiftUI.Color { .init(.buttonPrimaryText) }

    /// The "CardBackgroundColor" asset catalog color.
    static var cardBackground: SwiftUI.Color { .init(.cardBackground) }

    /// The "HoverBackgroundColor" asset catalog color.
    static var hoverBackground: SwiftUI.Color { .init(.hoverBackground) }

    /// The "MenuButtonColor" asset catalog color.
    static var menuButton: SwiftUI.Color { .init(.menuButton) }

    /// The "PrimaryTextColor" asset catalog color.
    static var primaryText: SwiftUI.Color { .init(.primaryText) }

    /// The "SearchInputBackgroundColor" asset catalog color.
    static var searchInputBackground: SwiftUI.Color { .init(.searchInputBackground) }

    /// The "SecondaryTextColor" asset catalog color.
    static var secondaryText: SwiftUI.Color { .init(.secondaryText) }

    /// The "SurfaceTranslucentColor" asset catalog color.
    static var surfaceTranslucent: SwiftUI.Color { .init(.surfaceTranslucent) }

    /// The "TagBackgroundColor" asset catalog color.
    static var tagBackground: SwiftUI.Color { .init(.tagBackground) }

    /// The "TagTextColor" asset catalog color.
    static var tagText: SwiftUI.Color { .init(.tagText) }

    /// The "TertiaryTextColor" asset catalog color.
    static var tertiaryText: SwiftUI.Color { .init(.tertiaryText) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "WebClipLinkIcon" asset catalog image.
    static var webClipLinkIcon: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .webClipLinkIcon)
#else
        .init()
#endif
    }

    /// The "WebClipPlaceholder" asset catalog image.
    static var webClipPlaceholder: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .webClipPlaceholder)
#else
        .init()
#endif
    }

    /// The "checkmark_checked" asset catalog image.
    static var checkmarkChecked: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .checkmarkChecked)
#else
        .init()
#endif
    }

    /// The "checkmark_unchecked_DM" asset catalog image.
    static var checkmarkUncheckedDM: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .checkmarkUncheckedDM)
#else
        .init()
#endif
    }

    /// The "checkmark_unchecked_LM" asset catalog image.
    static var checkmarkUncheckedLM: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .checkmarkUncheckedLM)
#else
        .init()
#endif
    }

    /// The "note-card-thumbnail" asset catalog image.
    static var noteCardThumbnail: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .noteCardThumbnail)
#else
        .init()
#endif
    }

    /// The "note-card-thumbnail-DM" asset catalog image.
    static var noteCardThumbnailDM: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .noteCardThumbnailDM)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "WebClipLinkIcon" asset catalog image.
    static var webClipLinkIcon: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .webClipLinkIcon)
#else
        .init()
#endif
    }

    /// The "WebClipPlaceholder" asset catalog image.
    static var webClipPlaceholder: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .webClipPlaceholder)
#else
        .init()
#endif
    }

    /// The "checkmark_checked" asset catalog image.
    static var checkmarkChecked: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .checkmarkChecked)
#else
        .init()
#endif
    }

    /// The "checkmark_unchecked_DM" asset catalog image.
    static var checkmarkUncheckedDM: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .checkmarkUncheckedDM)
#else
        .init()
#endif
    }

    /// The "checkmark_unchecked_LM" asset catalog image.
    static var checkmarkUncheckedLM: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .checkmarkUncheckedLM)
#else
        .init()
#endif
    }

    /// The "note-card-thumbnail" asset catalog image.
    static var noteCardThumbnail: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .noteCardThumbnail)
#else
        .init()
#endif
    }

    /// The "note-card-thumbnail-DM" asset catalog image.
    static var noteCardThumbnailDM: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .noteCardThumbnailDM)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

