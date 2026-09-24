#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A sync ring: pixels in a band around `radius` are pushed outward by up to
// `amp` points and snapped to a 2pt grid, so the ring reads as a pixel
// shockwave crossing the sheets. Outside the band the layer is untouched.
[[ stitchable ]] half4 syncRipple(float2 pos, SwiftUI::Layer layer, float2 origin, float radius, float width, float amp) {
    float d = distance(pos, origin);
    float x = (d - radius) / max(width, 1.0);
    float band = exp(-x * x);
    if (band < 0.05) { return layer.sample(pos); }
    float2 dir = d > 0.0 ? (pos - origin) / d : float2(0.0);
    float2 p = pos - dir * amp * band;
    p = (floor(p / 2.0) + 0.5) * 2.0;
    return layer.sample(p);
}
