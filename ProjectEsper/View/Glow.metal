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
    // x: the share of its glow a hood takes, marked magenta in the mask (the customize screen's 0.6).
    float4 hood;
    // The nine energy colours, each over its brightest channel, its glow's gain in w.
    float4 energy[9];
    // A clash's colour split: xy its centre in uv, z its reach at the screen's edge, w the
    // fringes' strength; then the two energy colours they take. None at z 0.
    float4 aberration;
    float4 aberrationFirst;
    float4 aberrationSecond;
    // A wash over the whole world: its colour, its strength in w; left off what the mask has in yellow.
    float4 wash;
    // Each energy colour's two hood tones, Diamond's too, its light and its shadow, in the same order.
    float4 hoodLight[10];
    float4 hoodShadow[10];
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

// One full-size pixel's glow, by its own colour and its own mask, never a blend of its neighbours':
// the customize screen's way, the glowing pixels alone, then blurred. Above the brightness threshold
// (its brightest channel), eased in over `softness`; a body's own, higher threshold where the mask is set.
static float3 glowOfPixel(float3 color, float3 mask, float2 uv, constant GlowUniforms &u) {
    float body = dot(mask, float3(0.2126, 0.7152, 0.0722));
    // Red to magenta: a hood (magenta), glowing at its share, and the face in its opening (red), not at all.
    float hooded = step(0.5, mask.r) * step(mask.g, 0.5);
    float hood = hooded * mask.b;
    float flat = step(0.5, mask.g) * step(mask.r, 0.5) * step(mask.b, 0.5);
    // Blue glows through the flats under it, from its colour before the water's tint.
    float through = step(0.1, mask.b) * step(mask.r, 0.05);
    float threshold = mix(u.threshold, u.bodyThreshold, step(0.05, body) * (1 - through) * (1 - hooded));
    if (through > 0 && u.waterTop.a > 0 && u.waterTop.a < 1) {
        float3 water = mix(u.waterTop.rgb, u.waterBottom.rgb, uv.y);
        color = saturate((color - water * u.waterTop.a) / (1 - u.waterTop.a));
    }
    // By its brightest channel, not its luminance: a deep blue, purple, green, orange or red at
    // full strength glows as a light one does.
    float brightness = max(color.r, max(color.g, color.b));
    float background = u.unglowed.a * step(distance(color, u.unglowed.rgb), 0.01);
    float amount = smoothstep(threshold - u.softness, threshold + u.softness, brightness) * (1 - flat) * (1 - background)
        * mix(1.0, hood * u.hood.x, hooded);
    // An energy colour's own gain: the one nearest in hue, the colour over its brightest
    // channel, if near enough; whites and greys are none of them.
    if (brightness > 0.05) {
        float3 hue = color / brightness;
        float nearest = 1e9, gain = 1;
        for (int index = 0; index < 9; index++) {
            float3 apart = hue - u.energy[index].rgb;
            float distance = dot(apart, apart);
            if (distance < nearest) { nearest = distance; gain = u.energy[index].w; }
        }
        if (nearest < 0.1) amount *= gain;
    }
    return color * amount;
}

// What glows, at half size: the four full-size pixels under each, their glows averaged. What glows
// through the flats can be a single art pixel wide, so its brightest is taken whole.
fragment float4 glowBright(FullScreen in [[stage_in]],
                           texture2d<float> scene [[texture(0)]],
                           texture2d<float> bodies [[texture(1)]],
                           sampler linear [[sampler(0)]],
                           constant GlowUniforms &u [[buffer(0)]]) {
    float2 halfTexel = 0.5 / float2(scene.get_width(), scene.get_height());
    float3 total = float3(0);
    float3 brightestThrough = float3(0);
    for (int corner = 0; corner < 4; corner++) {
        float2 at = in.uv + float2(corner % 2 == 0 ? -1 : 1, corner < 2 ? -1 : 1) * halfTexel;
        float3 mask = bodies.sample(linear, at).rgb;
        float3 glow = glowOfPixel(scene.sample(linear, at).rgb, mask, in.uv, u);
        total += glow;
        if (mask.b >= 0.1 && mask.r <= 0.05 && max(glow.r, max(glow.g, glow.b)) > max(brightestThrough.r, max(brightestThrough.g, brightestThrough.b))) {
            brightestThrough = glow;
        }
    }
    return float4(max(total / 4, brightestThrough), 1);
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
                              texture2d<float> bodies [[texture(2)]],
                              sampler linear [[sampler(0)]],
                              constant GlowUniforms &u [[buffer(0)]]) {
    // Under water each row sways a little side to side.
    float2 uv = in.uv;
    uv.x += u.wave.x * sin(uv.y * u.wave.y * 6.2831853 + u.wave.z) * smoothstep(u.wave.w, u.wave.w + 0.04, uv.y);
    float4 color = scene.sample(linear, uv);
    // A clash: the scene's edges fringed out from its centre, one way in one player's energy,
    // the other way in the other's.
    if (u.aberration.z > 0) {
        float2 offset = (uv - u.aberration.xy) * u.aberration.z;
        const float3 weights = float3(0.2126, 0.7152, 0.0722);
        float here = dot(color.rgb, weights);
        float inward = dot(scene.sample(linear, uv - offset).rgb, weights);
        float outward = dot(scene.sample(linear, uv + offset).rgb, weights);
        color.rgb = saturate(color.rgb + (max(inward - here, 0.0) * u.aberrationFirst.rgb
                                          + max(outward - here, 0.0) * u.aberrationSecond.rgb) * u.aberration.w);
    }
    float3 bloom = glow.sample(linear, uv).rgb * u.tint.rgb * u.intensity;
    // None spreads onto what's shielded: the face in a hood's opening.
    float3 mask = bodies.sample(linear, uv).rgb;
    // The world's wash, but over what's marked yellow (the far lightning), under the glow.
    float washFree = step(0.9, mask.r) * step(0.9, mask.g) * step(mask.b, 0.05);
    color.rgb = mix(color.rgb, u.wash.rgb, u.wash.a * (1 - washFree));
    float shielded = step(0.9, mask.r) * step(mask.g, 0.05) * step(mask.b, 0.05);
    float3 lit = color.rgb + bloom * (1 - shielded);
    // A hood's shadow keeps its step down from the hood's light: where the glow would close it
    // (a light already near white in a channel, teal's), the shadow is held that far under the lit light.
    float hood = step(0.5, mask.r) * step(mask.g, 0.5) * step(0.5, mask.b);
    if (hood > 0) {
        const float3 weights = float3(0.2126, 0.7152, 0.0722);
        for (int index = 0; index < 10; index++) {
            float3 shadow = u.hoodShadow[index].rgb;
            if (distance(color.rgb, shadow) > 0.1) continue;
            float3 light = color.rgb + (u.hoodLight[index].rgb - shadow);
            float drop = dot(light - color.rgb, weights);
            float litShadow = dot(saturate(lit), weights);
            float wanted = dot(saturate(light + bloom), weights) - drop;
            if (litShadow > wanted && litShadow > 0) lit = saturate(lit) * (wanted / litShadow);
            break;
        }
    }
    return float4(lit, 1);
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
    return float4(cam.sample(nearest, uv).rgb + bloom, 0.66);
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

// Platform Protein Shake's slabs and walls: a unit cube sized and slanted to a block of energy,
// every face drawn and added on as light, bright along its edges, a slow shimmer up its faces.
struct BlockFragment {
    float4 position [[position]];
    float3 normal;
    float3 local;
    float3 localNormal;
    float3 size;
    float4 color;
    float behind;
    float time;
};

vertex BlockFragment block_vertex(uint vid [[vertex_id]],
                                  uint iid [[instance_id]],
                                  const device CubeVertex *vertices [[buffer(0)]],
                                  const device CubeInstance *instances [[buffer(1)]],
                                  constant CubeUniforms &uniforms [[buffer(2)]]) {
    CubeVertex v = vertices[vid];
    CubeInstance inst = instances[iid];
    BlockFragment out;
    out.position = uniforms.viewProjection * (inst.model * float4(v.position.xyz, 1));
    out.normal = normalize((inst.model * float4(v.normal.xyz, 0)).xyz);
    out.local = v.position.xyz;
    out.localNormal = v.normal.xyz;
    // Width and height off the model's axes; the depth is its third axis's own share, the slant aside.
    out.size = float3(length(inst.model[0].xyz), length(inst.model[1].xyz), abs(inst.model[2].z));
    out.color = inst.color;
    out.behind = inst.flags.x;
    out.time = inst.flags.w;
    return out;
}

fragment float4 block_fragment(BlockFragment in [[stage_in]],
                               constant CubeUniforms &uniforms [[buffer(2)]],
                               texture2d<float, access::read> bodies [[texture(0)]]) {
    float3 cover = bodies.read(uint2(in.position.xy)).rgb;
    if (in.behind > 0.5 && cover.r > 0.5) discard_fragment();
    // How far in from the face's nearest edge, in the scene's pixels: the face's own two axes.
    float3 inside = (0.5 - abs(in.local)) * in.size;
    float3 facing = abs(in.localNormal);
    float edgeDistance = facing.x > 0.5 ? min(inside.y, inside.z) : (facing.y > 0.5 ? min(inside.x, inside.z) : min(inside.x, inside.y));
    float edge = 1.0 - smoothstep(0.0, 1.5, edgeDistance);
    float shimmer = 0.5 + 0.5 * sin((in.local.y * in.size.y + in.local.x * in.size.x * 0.5) * 0.4 - in.time * 4.0);
    float lit = max(dot(normalize(in.normal), normalize(uniforms.light.xyz)), 0.0);
    float3 colour = mix(in.color.rgb, float3(1.0), 0.5 * edge + 0.15 * lit);
    if (uniforms.waterTop.a > 0.0) {
        float down = clamp(in.position.y / max(uniforms.waterBottom.a, 1.0), 0.0, 1.0);
        colour = mix(colour, mix(uniforms.waterTop.rgb, uniforms.waterBottom.rgb, down), uniforms.waterTop.a);
    }
    return float4(colour, in.color.a * (0.2 + 0.1 * shimmer + 0.7 * edge));
}

// The stage preview's page: a panel's cut taken from the frame (a quad over the panel's own
// texture, sampling the frame's middle), and the panels laid on the page (each a fan of
// triangles over its picture). Positions in clip space, uv into the source.
struct MangaVertex {
    float2 position;
    float2 uv;
};

struct MangaOut {
    float4 position [[position]];
    float2 uv;
};

vertex MangaOut mangaVertex(uint id [[vertex_id]], constant MangaVertex *vertices [[buffer(0)]]) {
    MangaOut out;
    out.position = float4(vertices[id].position, 0, 1);
    out.uv = vertices[id].uv;
    return out;
}

fragment float4 mangaFragment(MangaOut in [[stage_in]], texture2d<float> source [[texture(0)]], sampler linear [[sampler(0)]]) {
    return float4(source.sample(linear, in.uv).rgb, 1);
}
