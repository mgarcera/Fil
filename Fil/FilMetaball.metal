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

// MARK: - Aurora ("curtains of light")

static float filHash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

// Smooth value noise in 0...1.
static float filValueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = filHash21(i);
    float b = filHash21(i + float2(1.0, 0.0));
    float c = filHash21(i + float2(0.0, 1.0));
    float d = filHash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal (layered) value noise for organic, aurora-like flow.
static float filFbm(float2 p) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        sum += amp * filValueNoise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

// Curtains of light: each fil color becomes a softly wavering horizontal band that
// bends and shimmers via fractal noise, layered additively over black.
[[ stitchable ]] half4 filAurora(float2 position,
                                 half4 color,
                                 float2 resolution,
                                 device const half4 *cols,
                                 int colCount,
                                 float time) {
    float2 uv = position / resolution;
    int bands = min(colCount, 6);
    if (bands <= 0) { return half4(0.0); }

    float3 accum = 0.0;
    float alpha = 0.0;

    for (int b = 0; b < bands; b++) {
        float fb = float(b);
        // Band's resting height, wavering horizontally over time.
        float base = 0.18 + 0.64 * (fb + 0.5) / float(bands);
        float waver = filFbm(float2(uv.x * 2.0 + fb * 3.1, time * 0.05 + fb * 1.7)) - 0.5;
        float center = base + 0.14 * waver;
        float width = 0.05 + 0.035 * filFbm(float2(uv.x * 3.0 + fb, time * 0.06));
        float d = (uv.y - center) / width;
        float band = exp(-d * d);
        // Vertical shimmer streaks within the curtain.
        float streak = 0.55 + 0.45 * filFbm(float2(uv.x * 9.0 + time * 0.12, fb * 2.3));
        float intensity = band * streak;
        accum += float3(cols[b].rgb) * intensity;
        alpha += intensity;
    }

    alpha = clamp(alpha, 0.0, 1.0);
    // Premultiplied: intensity-weighted color, transparent where dim so black shows.
    return half4(half3(min(accum, 1.0)), half(alpha));
}
