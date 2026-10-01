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
    // A colour that never glows, the stage's flat background, where its alpha is 1.
    float4 unglowed;
    // The screen's sway: x its reach across in uv, y waves down the screen, z its phase, none at 0;
    // w how far down the screen the HUD's top band reaches, which doesn't sway.
    float4 wave;
    // The water's tint over the scene, top and bottom of the screen, its alpha in waterTop.a;
    // none at 0.
    float4 waterTop;
    float4 waterBottom;
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
    // Blue glows through the flats under it, from its colour before the water's tint. It can be
    // a single art pixel wide, so any blue at all counts, and the brightest of the full-size
    // pixels under this half-size one is taken rather than their blend with the flats.
    float through = step(0.1, mask.b) * step(mask.r, 0.05);
    float threshold = mix(u.threshold, u.bodyThreshold, step(0.05, body) * (1 - through));
    if (through > 0) {
        float2 halfTexel = 0.5 / float2(scene.get_width(), scene.get_height());
        float brightest = -1;
        for (int corner = 0; corner < 4; corner++) {
            float2 offset = float2(corner % 2 == 0 ? -1 : 1, corner < 2 ? -1 : 1) * halfTexel;
            float3 sampled = scene.sample(linear, in.uv + offset).rgb;
            if (u.waterTop.a > 0 && u.waterTop.a < 1) {
                float3 water = mix(u.waterTop.rgb, u.waterBottom.rgb, in.uv.y);
                sampled = saturate((sampled - water * u.waterTop.a) / (1 - u.waterTop.a));
            }
            float sampledLuminance = dot(sampled, float3(0.2126, 0.7152, 0.0722));
            if (sampledLuminance > brightest) { brightest = sampledLuminance; color.rgb = sampled; }
        }
    }
    float luminance = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float background = u.unglowed.a * step(distance(color.rgb, u.unglowed.rgb), 0.01);
    float amount = smoothstep(threshold - u.softness, threshold + u.softness, luminance) * (1 - flat) * (1 - background);
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
    // Under water each row sways a little side to side.
    float2 uv = in.uv;
    uv.x += u.wave.x * sin(uv.y * u.wave.y * 6.2831853 + u.wave.z) * smoothstep(u.wave.w, u.wave.w + 0.04, uv.y);
    float4 color = scene.sample(linear, uv);
    float3 bloom = glow.sample(linear, uv).rgb * u.tint.rgb * u.intensity;
    return float4(color.rgb + bloom, 1);
}

// The ball cam: its texture on a trapezoid over the screen, wider at the top. Each corner
// carries its uv times the row's width, so the divide after interpolation keeps the
// picture straight across the slant. It's laid down at a third; flashes line its edges.
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
    float3 bloom = glow.sample(linear, uv).rgb * u.tint.rgb * u.intensity;
    return float4(cam.sample(nearest, uv).rgb + bloom, 0.33);
}

// The head's energy as small cubes turning in 3D, borrowed from Project RingOut: one unit
// cube drawn once an instance in the instance's colour and alpha, shaded as energy.
struct CubeVertex {
    float4 position;
    float4 normal;
};

struct CubeInstance {
    float4x4 model;
    float4 color;
    // x: 1 for a cube drawn behind the players, hidden wherever a body is; 2 behind the
    // rims as well.
    float4 flags;
};

struct CubeUniforms {
    float4x4 viewProjection;
    float4 light;
    // The water's tint: top and bottom colours, its strength in top's a, the height in bottom's a.
    float4 waterTop;
    float4 waterBottom;
};

struct CubeFragment {
    float4 position [[position]];
    float3 normal;
    float4 color;
    float behind;
};

vertex CubeFragment cube_vertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device CubeVertex *vertices [[buffer(0)]],
                                const device CubeInstance *instances [[buffer(1)]],
                                constant CubeUniforms &uniforms [[buffer(2)]]) {
    CubeVertex v = vertices[vid];
    CubeInstance inst = instances[iid];
    CubeFragment out;
    out.position = uniforms.viewProjection * (inst.model * float4(v.position.xyz, 1));
    out.normal = normalize((inst.model * float4(v.normal.xyz, 0)).xyz);
    out.color = inst.color;
    out.behind = inst.flags.x;
    return out;
}

fragment float4 cube_fragment(CubeFragment in [[stage_in]],
                              constant CubeUniforms &uniforms [[buffer(2)]],
                              texture2d<float, access::read> bodies [[texture(0)]]) {
    // Behind the players: nothing where a body or its line is drawn (white), and behind
    // the rims too, nothing where one is (green).
    float3 cover = bodies.read(uint2(in.position.xy)).rgb;
    if (in.behind > 0.5 && cover.r > 0.5) discard_fragment();
    if (in.behind > 1.5 && cover.g > 0.5) discard_fragment();
    // Energy, not a solid: no face goes dark, and the one facing the light runs toward
    // white, so the turn reads while the whole cube glows in its colour.
    float lit = max(dot(normalize(in.normal), normalize(uniforms.light.xyz)), 0.0);
    float3 colour = mix(in.color.rgb * (0.85 + 0.15 * lit), float3(1.0), 0.35 * lit * lit);
    // Under water, tinted as the rest of the scene is.
    if (uniforms.waterTop.a > 0.0) {
        float down = clamp(in.position.y / max(uniforms.waterBottom.a, 1.0), 0.0, 1.0);
        colour = mix(colour, mix(uniforms.waterTop.rgb, uniforms.waterBottom.rgb, down), uniforms.waterTop.a);
    }
    return float4(colour, in.color.a);
}
