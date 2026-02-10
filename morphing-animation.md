# Liquid Glass Morphing Animation Guide

**Last Updated:** September 2, 2025

## Overview

Morphing animations are a key feature of Apple's Liquid Glass design system introduced at WWDC 2025. These animations create fluid transitions where glass elements blend and merge like "droplets of water" - a signature characteristic of the new design language.

## Key Principles

### From Latest Research (2025)
- **Droplet Behavior**: Glass elements blend and merge naturally like liquid droplets
- **No Shape Morphing**: Avoid using `matchedGeometryEffect` for glass container shape changes
- **Materialization**: Use appear/disappear animations with glass effect changes
- **Interactive Layer**: Always maintain floating behavior above content
- **Performance**: 40% less GPU usage, 39% faster render times with new APIs

## Implementation Approach

A morphing animation between Liquid Glass elements in macOS 26/iOS 26 (using SwiftUI) is easily implemented with the new glass effect APIs. The core idea is to place your views inside a `GlassEffectContainer`, assign each morphing element a unique `glassEffectID` within a shared `@Namespace`, and animate state changes.

Here’s a canonical code snippet based on Apple documentation and developer discussion:

```swift
import SwiftUI

struct LiquidGlassMorphingDemo: View {
    @State private var iconCount: Int = 1
    @Namespace private var glassNamespace

    var body: some View {
        VStack(spacing: 24) {
            GlassEffectContainer(spacing: 40) {
                HStack(spacing: 40) {
                    Image(systemName: "sun.max.fill")
                        .frame(width: 80, height: 80)
                        .font(.system(size: 36))
                        .foregroundStyle(.yellow)
                        .glassEffect()
                        .glassEffectID("sun", in: glassNamespace)

                    if iconCount > 1 {
                        Image(systemName: "moon.fill")
                            .frame(width: 80, height: 80)
                            .font(.system(size: 36))
                            .foregroundStyle(.gray)
                            .glassEffect()
                            .glassEffectID("moon", in: glassNamespace)
                    }

                    if iconCount > 2 {
                        Image(systemName: "sparkles")
                            .frame(width: 80, height: 80)
                            .font(.system(size: 36))
                            .foregroundStyle(.purple)
                            .glassEffect()
                            .glassEffectID("sparkles", in: glassNamespace)
                    }
                }
            }

            Button("Morph") {
                withAnimation(.bouncy) {
                    iconCount = (iconCount % 3) + 1
                }
            }
            .buttonStyle(.glass)
        }
    }
}
```

**How it works:**

- Use a `GlassEffectContainer` and assign every glass element a unique `glassEffectID` sharing the same `@Namespace`.
- Changing `iconCount` (e.g., with the button) adds or removes icons, causing SwiftUI to morph the Liquid Glass effect fluidly between the shapes.
- Animation uses `.bouncy` for a fluid transition, but can be changed as needed.[^1][^2]

For more complex morphing (like shape changes, merges, or blends), the same pattern applies—build your effect using the *container* and identify elements with `glassEffectID`. Always wrap with `withAnimation` to let the morph transition occur.[^3][^4]

## Advanced Morphing Techniques

### Button to Overlay Transitions
Buttons can morph into overlays during presentations using the glass container:

```swift
struct ButtonToOverlayMorph: View {
    @State private var showOverlay = false
    @Namespace private var morphNamespace
    
    var body: some View {
        GlassEffectContainer {
            if !showOverlay {
                Button("Show Details") {
                    withAnimation(.bouncy) {
                        showOverlay = true
                    }
                }
                .buttonStyle(.glassProminent)
                .glassEffectID("morph", in: morphNamespace)
            } else {
                VStack {
                    // Overlay content
                    Text("Details")
                        .padding()
                }
                .frame(width: 300, height: 200)
                .glassEffect()
                .glassEffectID("morph", in: morphNamespace)
                .onTapGesture {
                    withAnimation(.bouncy) {
                        showOverlay = false
                    }
                }
            }
        }
    }
}
```

### Adaptive Opacity Based on Size
Glass opacity and appearance can change based on view size:

```swift
struct AdaptiveGlassMorph: View {
    @State private var isExpanded = false
    
    var body: some View {
        GlassEffectContainer {
            RoundedRectangle(cornerRadius: isExpanded ? 24 : 12)
                .frame(
                    width: isExpanded ? 300 : 100,
                    height: isExpanded ? 200 : 100
                )
                .glassEffect(isExpanded ? .regular : .thin)
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.6)) {
                        isExpanded.toggle()
                    }
                }
        }
    }
}
```

## Best Practices for Jot App Implementation

### 1. Note Cards Morphing
- Use `GlassEffectContainer` for the entire grid of note cards
- Assign unique `glassEffectID` to each card based on note.id
- Animate transitions when cards expand/collapse

### 2. Search Bar Transitions
- Morph search bar from toolbar to full-screen search
- Use consistent `@Namespace` across different search states
- Apply `.bouncy` animation for natural feel

### 3. Rich Text Editor Toolbar
- Group formatting buttons in `GlassEffectContainer`
- Morph between compact and expanded toolbar states
- Use `.glassProminent` for primary actions

### 4. Performance Considerations
- Limit glass effects to floating UI elements only
- Never stack glass on glass
- Use `.implicit` display mode when needed
- Test on iOS 26 beta for latest optimizations

### 5. Animation Timing
- `.bouncy`: Default for most glass transitions
- `.smooth(duration: 0.6)`: For deliberate state changes
- `.spring(response: 0.4, dampingFraction: 0.8)`: Custom fluid animations

## Platform-Specific Implementations

### iOS 26 / iPadOS 26
```swift
.glassEffect()  // Default implementation
.glassEffect(.regular.interactive(true))  // Touch-responsive
```

### macOS 26 (Tahoe)
```swift
.glassEffect(in: RoundedRectangle(cornerRadius: 20))
.glassBackgroundEffect()  // For window backgrounds
```

### visionOS 2.4+
```swift
.glassBackgroundEffect()  // Optimized for spatial computing
```

### Fallback for Earlier Versions
```swift
if #available(iOS 26, macOS 26, *) {
    content.glassEffect()
} else {
    content.background(.ultraThinMaterial)
}
```

<div style="text-align: center">⁂</div>

[^1]: https://github.com/onmyway133/blog/issues/997

[^2]: https://www.devtechie.com/blog/exploring-morphing-liquid-glass-effects-in-swiftui-ios-26

[^3]: https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views

[^4]: https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass

[^5]: https://www.reddit.com/r/webdev/comments/1lblqlu/i_made_10_apple_liquid_glass_code_snippets/

[^6]: https://www.youtube.com/watch?v=UiG9dkYqNes

[^7]: https://gist.github.com/samhenrigold/7255ed81aed8c41f0b3a7f3dde9d6022

[^8]: https://github.com/GetStream/awesome-liquid-glass

[^9]: https://www.youtube.com/watch?v=Qutp-v-g2Iw

[^10]: https://developer.apple.com/videos/play/wwdc2025/284/

[^11]: https://swiftuisnippets.wordpress.com/2025/06/14/introducing-liquid-glass-the-new-look-feel-of-apple-platforms/

[^12]: https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/

[^13]: https://www.youtube.com/watch?v=sEi9T5eZO1c

