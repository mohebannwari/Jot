#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.mohebanwari.Noty";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "BackgroundColor" asset catalog color resource.
static NSString * const ACColorNameBackgroundColor AC_SWIFT_PRIVATE = @"BackgroundColor";

/// The "ButtonPrimaryBgColor" asset catalog color resource.
static NSString * const ACColorNameButtonPrimaryBgColor AC_SWIFT_PRIVATE = @"ButtonPrimaryBgColor";

/// The "ButtonPrimaryTextColor" asset catalog color resource.
static NSString * const ACColorNameButtonPrimaryTextColor AC_SWIFT_PRIVATE = @"ButtonPrimaryTextColor";

/// The "CardBackgroundColor" asset catalog color resource.
static NSString * const ACColorNameCardBackgroundColor AC_SWIFT_PRIVATE = @"CardBackgroundColor";

/// The "HoverBackgroundColor" asset catalog color resource.
static NSString * const ACColorNameHoverBackgroundColor AC_SWIFT_PRIVATE = @"HoverBackgroundColor";

/// The "MenuButtonColor" asset catalog color resource.
static NSString * const ACColorNameMenuButtonColor AC_SWIFT_PRIVATE = @"MenuButtonColor";

/// The "PrimaryTextColor" asset catalog color resource.
static NSString * const ACColorNamePrimaryTextColor AC_SWIFT_PRIVATE = @"PrimaryTextColor";

/// The "SearchInputBackgroundColor" asset catalog color resource.
static NSString * const ACColorNameSearchInputBackgroundColor AC_SWIFT_PRIVATE = @"SearchInputBackgroundColor";

/// The "SecondaryTextColor" asset catalog color resource.
static NSString * const ACColorNameSecondaryTextColor AC_SWIFT_PRIVATE = @"SecondaryTextColor";

/// The "SurfaceTranslucentColor" asset catalog color resource.
static NSString * const ACColorNameSurfaceTranslucentColor AC_SWIFT_PRIVATE = @"SurfaceTranslucentColor";

/// The "TagBackgroundColor" asset catalog color resource.
static NSString * const ACColorNameTagBackgroundColor AC_SWIFT_PRIVATE = @"TagBackgroundColor";

/// The "TagTextColor" asset catalog color resource.
static NSString * const ACColorNameTagTextColor AC_SWIFT_PRIVATE = @"TagTextColor";

/// The "TertiaryTextColor" asset catalog color resource.
static NSString * const ACColorNameTertiaryTextColor AC_SWIFT_PRIVATE = @"TertiaryTextColor";

/// The "WebClipLinkIcon" asset catalog image resource.
static NSString * const ACImageNameWebClipLinkIcon AC_SWIFT_PRIVATE = @"WebClipLinkIcon";

/// The "WebClipPlaceholder" asset catalog image resource.
static NSString * const ACImageNameWebClipPlaceholder AC_SWIFT_PRIVATE = @"WebClipPlaceholder";

/// The "checkmark_checked" asset catalog image resource.
static NSString * const ACImageNameCheckmarkChecked AC_SWIFT_PRIVATE = @"checkmark_checked";

/// The "checkmark_unchecked_DM" asset catalog image resource.
static NSString * const ACImageNameCheckmarkUncheckedDM AC_SWIFT_PRIVATE = @"checkmark_unchecked_DM";

/// The "checkmark_unchecked_LM" asset catalog image resource.
static NSString * const ACImageNameCheckmarkUncheckedLM AC_SWIFT_PRIVATE = @"checkmark_unchecked_LM";

/// The "note-card-thumbnail" asset catalog image resource.
static NSString * const ACImageNameNoteCardThumbnail AC_SWIFT_PRIVATE = @"note-card-thumbnail";

/// The "note-card-thumbnail-DM" asset catalog image resource.
static NSString * const ACImageNameNoteCardThumbnailDM AC_SWIFT_PRIVATE = @"note-card-thumbnail-DM";

#undef AC_SWIFT_PRIVATE
