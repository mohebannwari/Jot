# Liquid Glass Implementation Guide

*This file contains the implementation rules and patterns for Apple's Liquid Glass effects in the Jot app.*

**Last Updated:** September 2, 2025

---

## Latest Updates from WWDC 2025

### What is Liquid Glass?
Apple's Liquid Glass, announced at WWDC 2025 (June 9), represents the biggest visual overhaul since iOS 7 in 2013. It's a dynamic material that combines the optical properties of glass with a sense of fluidity, using real-time rendering with specular highlights that dynamically react to movement.

### Cross-Platform Availability
- **iOS 26, iPadOS 26, macOS 26** (Tahoe), **watchOS 26, tvOS 26**
- First unified design language across all Apple platforms
- Maintains distinct qualities for each platform while establishing harmony

### Performance Improvements (iOS 26+/macOS 26+)
- **40% reduction in GPU usage** with Liquid Glass effects
- **39% faster render times** (10.2ms vs 16.7ms)
- **38% less memory usage** (28MB vs 45MB)
- Improved scroll performance with new instruments

### Beta Updates (August 2025)
- iOS 26 beta 5 shows Apple's commitment to the design
- Expanded to more UI elements
- Adjusted transparency for better legibility after accessibility feedback
- What we see in beta 5 is largely what Apple plans to ship

---

Here is a properly structured documentation summary of the video “Liquid Glass - 5 Things You MUST Know Before Implementing” by Sean Allen, strictly focused on practical and implementation-relevant details for Claude code or internal team adoption. Most marketing content and sponsorships are omitted, and points are structured for clear integration into your engineering documentation or guidelines.

# Documentation: Adopting "Liquid Glass" Design in iOS/macOS Apps

## Purpose
This document summarizes and standardizes the best practices for implementing Apple’s Liquid Glass design in apps, based on Sean Allen's overview. Use this for code reviews, design docs, or feeding into assistants like Claude for consistent and correct application.

## 1. Use Built-in SwiftUI (or UIKit) Components

**Guideline:**  
- Always prefer native SwiftUI or UIKit components (e.g., `TabBar`, `Toolbar`, `Button`, `Slider`) for UI controls.
- Avoid building custom UI components unless necessary.

**Rationale:**  
- Native components receive Liquid Glass updates automatically.  
- You gain out-of-the-box support for accessibility, system-wide animations, morphing, and contextual adaptation.
- Avoids the need for major rewrites when design guidelines change.

**Exception:**  
- For custom controls, use the appropriate "glass effect" modifier with restraint.

## 2. Glass Is a Control Layer, Not a Style

**Guideline:**  
- Treat Liquid Glass as a floating, translucent control layer above the content (e.g., toolbars, tab bars, buttons).
- Avoid layering glass upon glass (“glass on glass” effect) and do not use glass backgrounds excessively.

**Implementation:**  
- Main content should flow underneath the control layers with glass.
- Group toolbar items intelligently; avoid combining icons and text in a way that could confuse users about actionable zones.

## 3. Use Color Sparingly and Thoughtfully

**Guideline:**  
- Minimize use of custom colors on glass surfaces (buttons, toolbars, etc.).
- The system automatically manages contrast and legibility by adjusting symbols/text from light to dark depending on what’s under the glass.

**Best Practice:**  
- Employ color to draw user attention ONLY to primary actions (e.g., a "checkmark" button).
- If you need color, place it in the background/content, not on glass-layer controls.

## 4. Emphasize Concentricity

**Definition:**  
- *Concentricity* refers to the visual alignment of corner radii between UI elements and with device hardware.

**Guideline:**  
- Ensure that corners of controls (e.g., buttons, cards, overlays) match and line up with device and parent container corners.
- Use capsule shapes and new SwiftUI APIs where possible for perfect concentric alignment.
- Avoid mismatched radii which break the design harmony.

**Note:**  
- This is both a hardware and software design principle in current Apple guidelines.

## 5. Update to New Unified Glass App Icons

**Guideline:**  
- All app icons must be redesigned with layers, translucency, and blur per Liquid Glass standards.
- Use the official "Icon Composer" tool to generate new unified icons.

**Process:**  
- Prepare separate icon layers (no effects).
- Use Icon Composer to apply glass effects, control translucency/blur/tint.
- Export the new icon file for all platforms (macOS, iOS, visionOS, watchOS) as a single asset.

## Additional Best Practices

- Always reference current official Apple documentation for Liquid Glass.
- Test all colors, glass effects, and iconography for accessibility and legibility in both light/dark modes.
- Avoid over-customizing; leverage system defaults wherever possible for best cross-platform results.

### Future Implications
- **AR Glasses Connection**: Bloomberg reports Liquid Glass is laying groundwork for Apple's rumored AR glasses (2026)
- **Vision Pro Influence**: Design draws strong inspiration from visionOS visual language
- **20th Anniversary iPhone**: Expected to showcase Liquid Glass prominently

### Developer Resources
- **Xcode 26**: Required for full Liquid Glass implementation
- **Icon Composer**: New tool for creating unified glass app icons
- **Developer APIs**: Available via SwiftUI, UIKit, and AppKit
- **Documentation**: developer.apple.com for latest guidelines

### Disclaimer
Not all APIs shown in demos may be available in production releases. Verify with the current SDK/Xcode version before relying on a given modifier or layout primitive.

This document is fit for prompt injection into Claude or for training engineering teams to implement Apple's latest Liquid Glass UI consistently and correctly[1].

[1] https://www.youtube.com/watch?v=aF2qt5WfprM

---

# Official Apple Documentation - Liquid Glass Animation Guidelines

*From Apple Developer Documentation and WWDC25 Session 284*

## Liquid Glass Animation Principles
- **Interactive Layer**: Designed as an "interactive layer" that floats above content
- **Dynamic Adaptation**: Adapts dynamically to background and user interface style
- **Materialization**: Materializes and dematerializes with special animations (NOT shape morphing)
- **Sparse Usage**: Best used sparingly for most important UI elements only

## Morphing Techniques
- **Button Transitions**: Buttons can morph into overlays during presentations
- **Glass Blending**: Glass views can seamlessly blend and merge like "droplets of water"
- **Container Corners**: Supports container-relative corner configurations
- **Adaptive Opacity**: Opacity and appearance change based on view size

## Search Interface Best Practices
### iPhone Implementation
- Search bar sits in toolbar, adapts to available space

### iPad Implementation
- Can be placed at navigation bar's trailing edge
- Can be a dedicated tab that expands when selected
- Supports automatic search field activation
- Flexible placement options (sidebar, tab bar, navigation bar)

## SwiftUI Implementation Patterns (iOS 26+/macOS 26+)

### Native SwiftUI APIs
- **`.glassEffect()`**: Default glass effect with `.regular` style and `Capsule` shape
- **`.glassEffect(.thin, in: RoundedRectangle(cornerRadius: 20))`**: Custom glass thickness and shape
- **`.glassEffect(.regular.interactive(true))`**: Interactive glass that responds to touch
- **`GlassEffectContainer`**: Combine multiple glass shapes for morphing animations
- **`.glassEffectID()`**: Assign unique IDs for coordinated animations
- **`.glassBackgroundEffect()`**: visionOS 2.4+ specific implementation
- **Button Styles**: `.buttonStyle(.glass)` or `.buttonStyle(.glassProminent)`

### UIKit/AppKit Fallbacks
- **UIVisualEffectView**: Use `UIVisualEffectView` and `UIGlassEffect`
- **Animation**: Animate effect setting for materialize/dematerialize transitions
- **Interactive Support**: Support interactive behaviors with `isInteractive = true`
- **Container Effects**: Use `UIGlassContainerEffect` for advanced multi-view interactions

## Key Design Principle
**"Limit Liquid Glass to the most important elements of your app."**

## Animation Guidelines
- **NO Shape Morphing**: Avoid using `matchedGeometryEffect` for glass container shape changes
- **Materialization**: Use appear/disappear animations with glass effect changes
- **Droplet Behavior**: Glass elements should blend and merge like liquid droplets
- **Interactive Layer**: Always maintain floating behavior above content

--- 

# WWDC25 Summary & Guidelines Document  
**Meet with Apple: Explore the Biggest Updates from WWDC25**  
*Recorded at Apple Developer Center, Cupertino · Coverage of iOS 26, macOS Tahoe, visionOS 26, and more*

## Agenda Overview
- New design system: “Liquid Glass” and unified visual language
- Apple Intelligence & Machine Learning breakthroughs
- Major updates in visionOS (spatial computing and immersive media)
- System features, APIs, and platform-wide best practices

## 1. New Unified Design System: “Liquid Glass”

**Vision**:  
A harmonized, adaptive, and expressive design language for Apple apps and platforms, focused on cohesion, real-time adaptability, and an organic user experience.

### Core Components

- **Liquid Glass Material**:  
  - Dynamic, real-time lighting adapts to content underneath  
  - Two main types:  
    - *Clear*: Fully transparent with a dimming layer for legibility  
    - *Regular*: Adapts brightness/darkness to background; maintains legibility in any mode

- **Tab Bars**
  - Redesigned to “float” above content, translucent on scroll
  - Always visible, enables easier navigation
  - Can now feature a dedicated “search” tab, and persistent accessory views (e.g., mini music player)

- **Toolbars**
  - Float atop content, group simple symbol-based actions
  - Encourage use of symbols over text (with exceptions for clarity)
  - “More” menu (ellipsis) for secondary actions
  - Scroll Edge Effect: Ensures controls stand out as content scrolls beneath

- **Color & Tinting**
  - Use color sparingly for key actions, not over large UI elements
  - Use system tints that adapt to background for accessibility
  - Prioritize brand color in the content area, not in controls

- **Sheets & Modals**
  - Resizable, with “detents” for resting positions
  - Floating glass appearance in compact states; becomes more opaque full-screen
  - Show grabber when resizable; always provide a close button

- **Corner Concentricity**
  - Automatic alignment of corners and shapes in UIs to device hardware for seamless, balanced visual flow
  - Nested elements (e.g., images in cards) auto-adjust inner radius for harmony

#### **App Icons**
- Reimagined: Stacked Liquid Glass layers for dimensionality and adaptation to appearance modes (light/dark, monochromatic, tinted)
- **Icon Composer**: New tool to preview and build icons with these materials

## 2. Implementing the Design: APIs & Guidelines

- **Xcode 26 SDK**:  
  - Recompiling apps brings many updates automatically
- **SwiftUI, UIKit, AppKit**:  
  - Updates apply to all
- **Structural Components**:  
  - Sidebars and tabs now use floating Liquid Glass backgrounds  
  - Use `.backgroundExtensionEffect`, `.tabBarMinimizeBehavior`, and `.tabViewBottomAccessory` for advanced layouts
- **Sheets/Modals**:  
  - Add a Namespace and mark source/target for smooth transition effects
- **Toolbar Enhancements**
  - Use `ToolbarSpacer` and group related actions for clarity
- **Search Placement**  
  - As toolbar or dedicated tab, adaptable to platform conventions
- **Standard Controls**  
  - Bordered/capsule buttons by default, consistent sizes across platforms  
  - Use `.buttonBorderShape()`, `.controlSize()`, `.glassEffect()`, `.glassProminent()`
  - Controls dynamically shrink/expand when scrolling for focus management
- **Custom UI Elements**
  - Use `GlassEffectContainer` for multiple glass elements (better performance, correct visual blending)
  - Use `glassEffectID` for coordinated animations
  - Use `interactive()` modifier for touch responses
  - Glass elements blend and merge like "droplets of water"

## 3. Apple Intelligence & Machine Learning

- **Foundation Models Framework** (on-device Large Language Model)
  - 3-billion-parameter Apple-designed LLM, private, fast, works offline, no API keys or accounts needed
  - Use for generative tasks (summaries, search suggestions, natural language interactions)
  - *Guided Generation*: Use Swift `Generable` macro for structured outputs
  - Tool calling: Fetch live/personal data (like weather, calendar events, etc.)

- **System Features**
  - *Writing Tools*: Rewrite, proofread, or summarize text in-place; expanded toolbar integration
  - *Image Playground*: Genmoji, image generation via API or via system UIs
  
- **APIs**
  - Integration easy for text/image tools, search enhancements, context menus
  - No extra app size or account requirements, ready for macOS, iOS, iPadOS, visionOS

- **ML & Vision Frameworks**  
  - Vision: New document recognition, camera smudge detection  
  - Speech: New, faster SpeechAnalyzer API for on-device STT; supports many languages
  - Core ML: Integrate custom or open LLMs and image models easily, with built-in performance reporting and conversions
  - MLX: Open source, Apple-optimized framework for advanced model experimentation

## 4. visionOS 26: Spatial Computing & Immersive Media

### Immersive UI Features
- **SwiftUI for 3D**:  
  - Layout modifiers for depth/z-order, new *depthAlignment* and *rotation3DLayout* APIs
- **Object Manipulation**:  
  - Built-in gestures for scaling, rotation, hand-to-hand passing; minimal custom code needed
- **RealityKit Improvements**:  
  - Deeper SwiftUI integration, more robust model animation and configuration
  
### Widgets
- Three-dimensional, spatial-aware; anchored to real spaces, adapt to proximity
- Existing iOS/iPadOS widgets carry over automatically for compatibility

### Interactions
- Enhanced hand tracking (90Hz), new “look to scroll” navigation with eyes
- Support for spatial accessories:  
  - PlayStation VR2 Sense controller, Logitech Muse (6DoF tracking, haptics)
  - Game controller APIs for input, anchor entities to hardware

### Media
- *Spatial Scenes*: Convert 2D images to 3D, with real-world parallax
- *Apple Projected Media Profile (APMP)*:  
  - Unified video format for 180°, 360°, fisheye, etc., with built-in projection correction
- *Immersive Video Pipeline*:  
  - Capture, grade, and distribute ultra-high-quality 8K/180°/3D video
  - New frameworks (e.g., *ImmersiveMedia*) for direct integration

### Collaboration & Sharing
- *Spatial Personas*: Out of beta, improved realism
- *SharePlay & Nearby Window Sharing*: Seamless local/remote collaboration
- *Shared World Anchors*: Persist virtual items across users in the same space
- *Privacy*: Restrict sensitive content from being screen-shared

### Enterprise APIs
- *Camera Access*: Dual/stereo feeds, area selection, region view APIs
- *Coordinate Sharing*: APIs for local network spatial alignment
- *Window Follow Mode*: Keep UI visible as user moves
- *Content protection*: `contentCaptureProtected` for sensitive views

## 5. Final Notes & Resources

- All features, APIs, and guidelines found on developer.apple.com and in Xcode sample projects
- *Icon Composer*, *GlassEffectContainer*, and Playgrounds for Foundation models: key new development tools
- Attend Apple’s follow-up sessions, newsletters, and documentation for deep dives

## Best Practices & Next Steps

- Recompile for iOS 26/macOS Tahoe to adopt new look and behaviors immediately
- Use new system components and modify for brand where relevant (using tints, content enhancements)
- Integrate Foundation Models for on-device AI and consider privacy by design
- Explore new visionOS APIs for spatial, collaborative, and media-rich experiences
- Stay updated with documentation and participate in upcoming sessions to clarify and deepen adoption

**For Designers, Developers, Product Managers:**  
Adopt the new visual language and intelligent features to create apps that are cohesive, adaptive, immersive, efficient, privacy-preserving, and future-proof on Apple platforms.[1]

[1] https://www.youtube.com/watch?v=9lO3dsuS3KA&t=3381s