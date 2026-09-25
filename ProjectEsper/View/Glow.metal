#include <metal_stdlib>
using namespace metal;

// The glow, GameMaker's Glow filter by another route: the bright parts of the scene,
// blurred at half size, added back on top.

struct GlowUniforms {
    float2 texelSize;
    float2 direction;
    float threshold;
    float bodyThreshold;
    float softness;
    float intensity;
    float4 tint;
};

struct FullScreen {
    float4 position [[position]];
    float2 uv;
};

// One triangle that covers the screen; uv has y down like the textures.
vertex FullScreen glowVertex(uint id [[vertex_id]]) {
    float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    FullScreen out;
    out.position = float4(corners[id], 0, 1);
    out.uv = float2((corners[id].x + 1) / 2, 1 - (corners[id].y + 1) / 2);
    return out;
}

// What glows: everything above the luminance threshold, eased in over `softness`. Where
// the body mask is set the body's own, higher threshold applies instead.
fragment float4 glowBright(FullScreen in [[stage_in]],
                           texture2d<float> scene [[texture(0)]],
                           texture2d<float> bodies [[texture(1)]],
                           sampler linear [[sampler(0)]],
                           constant GlowUniforms &u [[buffer(0)]]) {
    float4 color = scene.sample(linear, in.uv);
    // The mask is the bodies on black, so anything with light in it is body; pure green
    // marks what must not glow at all.
    float3 mask = bodies.sample(linear, in.uv).rgb;
    float body = dot(mask, float3(0.2126, 0.7152, 0.0722));
    float flat = step(0.5, mask.g) * step(mask.r, 0.05) * step(mask.b, 0.05);
    float threshold = mix(u.threshold, u.bodyThreshold, step(0.05, body));
    float luminance = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float amount = smoothstep(threshold - u.softness, threshold + u.softness, luminance) * (1 - flat);
    return float4(color.rgb * amount, 1);
}

// A nine-tap Gaussian along `direction`; run once across and once down.
fragment float4 glowBlur(FullScreen in [[stage_in]],
                         texture2d<float> source [[texture(0)]],
                         sampler linear [[sampler(0)]],
                         constant GlowUniforms &u [[buffer(0)]]) {
    const float weights[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };
    float2 step = u.direction * u.texelSize;
    float3 sum = source.sample(linear, in.uv).rgb * weights[0];
    for (int i = 1; i < 5; i++) {
        sum += source.sample(linear, in.uv + step * i).rgb * weights[i];
        sum += source.sample(linear, in.uv - step * i).rgb * weights[i];
    }
    return float4(sum, 1);
}

// The scene with the glow added on top.
fragment float4 glowComposite(FullScreen in [[stage_in]],
                              texture2d<float> scene [[texture(0)]],
                              texture2d<float> glow [[texture(1)]],
                              sampler linear [[sampler(0)]],
                              constant GlowUniforms &u [[buffer(0)]]) {
    float4 color = scene.sample(linear, in.uv);
    float3 bloom = glow.sample(linear, in.uv).rgb * u.tint.rgb * u.intensity;
    return float4(color.rgb + bloom, 1);
}

// The ball cam: its texture on a trapezoid over the screen, wider at the top. Each corner
// carries its uv times the row's width, so the divide after interpolation keeps the
// picture straight across the slant. A thin black edge frames it.
struct BallCamCorner {
    float2 position;
    float3 uvq;
};

struct BallCamOut {
    float4 position [[position]];
    float3 uvq;
};

vertex BallCamOut ballCamVertex(uint id [[vertex_id]], constant BallCamCorner *corners [[buffer(0)]]) {
    BallCamOut out;
    out.position = float4(corners[id].position, 0, 1);
    out.uvq = corners[id].uvq;
    return out;
}

fragment float4 ballCamFragment(BallCamOut in [[stage_in]],
                                texture2d<float> cam [[texture(0)]],
                                texture2d<float> glow [[texture(1)]],
                                sampler nearest [[sampler(0)]],
                                sampler linear [[sampler(1)]],
                                constant GlowUniforms &u [[buffer(0)]]) {
    float2 uv = in.uvq.xy / in.uvq.z;
    float2 size = float2(cam.get_width(), cam.get_height());
    float2 edge = min(uv, 1 - uv) * size;
    if (min(edge.x, edge.y) < 2) { return float4(0, 0, 0, 1); }
    float3 bloom = glow.sample(linear, uv).rgb * u.tint.rgb * u.intensity;
    return float4(cam.sample(nearest, uv).rgb + bloom, 1);
}
