#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// Progressive edge blur: blurs content pixels near the top and bottom edges
/// of the view with increasing gaussian radius. Center content stays sharp.
///
/// Parameters:
///   - position: current pixel coordinate
///   - layer: rasterized SwiftUI layer to sample from
///   - viewSize: (width, height) of the view in points
///   - blurZone: height of the blur transition zone at each edge (points)
///   - maxRadius: maximum blur radius at the very edge (points)
[[stitchable]] half4 progressiveEdgeBlur(
    float2 position,
    SwiftUI::Layer layer,
    float2 viewSize,
    float blurZone,
    float maxRadius
) {
    // Distance from nearest vertical edge
    float distFromTop = position.y;
    float distFromBottom = viewSize.y - position.y;
    float nearestEdge = min(distFromTop, distFromBottom);

    // Outside blur zone -> return original pixel
    if (nearestEdge >= blurZone) {
        return layer.sample(position);
    }

    // Blur radius ramps from 0 (at blurZone boundary) to maxRadius (at edge)
    float t = 1.0 - (nearestEdge / blurZone);
    float radius = maxRadius * t * t; // quadratic ramp for smoother falloff

    if (radius < 0.5) {
        return layer.sample(position);
    }

    // Gaussian-weighted box sampling
    half4 color = half4(0.0);
    float totalWeight = 0.0;
    int kernelSize = int(ceil(radius));

    for (int dy = -kernelSize; dy <= kernelSize; dy++) {
        for (int dx = -kernelSize; dx <= kernelSize; dx++) {
            float dist = sqrt(float(dx * dx + dy * dy));
            if (dist > radius) continue;

            float weight = exp(-(dist * dist) / (2.0 * radius * radius));
            color += layer.sample(position + float2(float(dx), float(dy))) * half(weight);
            totalWeight += weight;
        }
    }

    return color / half(max(totalWeight, 0.001));
}
