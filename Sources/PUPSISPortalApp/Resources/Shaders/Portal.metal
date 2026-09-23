#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float h(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
static float n(float2 p) {
    float2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h(i), h(i + float2(1, 0)), f.x), mix(h(i + float2(0, 1)), h(i + float2(1, 1)), f.x), f.y);
}
static float fbm(float2 p) { float v = 0, a = 0.5; for (int k = 0; k < 4; k++) { v += a * n(p); p *= 2.03; a *= 0.5; } return v; }
static float b2(float2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
static float bayer(float2 a) { return b2(0.5 * a) * 0.25 + b2(a); }

// size: view size in points; cell: pixel size in points (3 at rest, up to 12 in warp)
[[ stitchable ]] half4 portalSwirl(float2 pos, half4 color, float2 size, float time, float speed,
                                   float lit, float cell,
                                   half4 c0, half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 q0 = floor(pos / cell);
    float2 uv = ((q0 + 0.5) * cell - 0.5 * size) / size.y;
    uv.y = -uv.y;
    float d = length(uv * float2(1.25, 0.8));
    float a = atan2(uv.y, uv.x) + time * 0.28 * speed + d * 3.2;
    float2 q = float2(cos(a), sin(a)) * d * 2.4;
    float v = fbm(q * 2.2 + float2(0, -time * 0.5 * speed));
    v += 0.22 * sin(uv.x * 16.0 + fbm(uv * 3.0 + time * 0.25 * speed) * 7.0 + time * 1.6 * speed);
    v = clamp(v * 0.95 + (0.55 - d) * 0.55, 0.0, 1.0) * lit;
    float k = clamp(floor(v * 4.0 + bayer(q0) - 0.5), 0.0, 4.0);
    return k < 0.5 ? c0 : k < 1.5 ? c1 : k < 2.5 ? c2 : k < 3.5 ? c3 : c4;
}

[[ stitchable ]] half4 pixelate(float2 pos, SwiftUI::Layer layer, float cell) {
    return layer.sample((floor(pos / cell) + 0.5) * cell);
}
