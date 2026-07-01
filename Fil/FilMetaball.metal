#include <metal_stdlib>
using namespace metal;

// Metaball field for the "liquid" screensaver mode. Each fil is one blob center
// with a color; where blobs overlap, their fields sum past a threshold and merge
// into a single gooey mass, and their colors blend by field contribution.
//
// Applied via SwiftUI `.colorEffect`, so the signature is
// `(float2 position, half4 color, args...)`. `centers` is a flat [x0,y0,x1,y1,...]
// array (count = 2 * blobCount); `cols` holds one premultiplied color per blob.
[[ stitchable ]] half4 filMetaball(float2 position,
                                   half4 color,
                                   device const float *centers,
                                   int centerCount,
                                   device const half4 *cols,
                                   int colCount,
                                   float radius,
                                   float threshold,
                                   float edge) {
    int count = centerCount / 2;
    float field = 0.0;
    float3 weightedColor = 0.0;
    float weightSum = 0.0;
    float r2 = radius * radius;

    for (int i = 0; i < count; i++) {
        float2 center = float2(centers[2 * i], centers[2 * i + 1]);
        float2 delta = position - center;
        float dist2 = dot(delta, delta);
        // Compact-support "blobby" kernel: a fil's field is exactly zero beyond its
        // radius, so distant fils contribute nothing and each stays a distinct droplet
        // — they only merge where their neighborhoods actually overlap.
        float q2 = dist2 / r2;
        if (q2 < 1.0) {
            float t = 1.0 - q2;
            float w = t * t * t;
            field += w;
            weightedColor += float3(cols[i].rgb) * w;
            weightSum += w;
        }
    }

    // Screen-space antialiased edge: the transition band tracks the field's per-pixel
    // rate of change (fwidth), so the outline is ~`edge` pixels wide — as crisp as a
    // vector shape, with no aliasing. Small `edge` = razor sharp; larger = softer goo.
    float aa = max(fwidth(field), 1e-4) * edge;
    float alpha = smoothstep(threshold - aa, threshold + aa, field);
    if (weightSum <= 0.0 || alpha <= 0.0) {
        return half4(0.0);
    }

    float3 rgb = weightedColor / weightSum;
    // Return premultiplied color so the transparent exterior lets the black show.
    return half4(half3(rgb) * half(alpha), half(alpha));
}
