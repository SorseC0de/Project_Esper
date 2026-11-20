# Glow, mask, halo and SKShader map (read-only survey)

Project root: `/Users/azurin/My iOS Projects/Games/Project Esper`. All paths below are relative to it.
Files read in full: `ProjectEsper/View/MetalGameView.swift` (1083 lines), `ProjectEsper/View/Glow.metal` (378), `ProjectEsper/View/MaskScene.swift` (170). GameScene, SpriteLibrary, Tuning, MapTiles, BallCamScene read in the parts cited.

**The one fact that matters most for the rework.** The glow pass reads exactly two textures: the finished scene (`sceneTexture`) and the mask (`bodyMask`). If both come out byte-identical, every glow, bloom, EDR and hood-correction pixel comes out identical too. In the default mode (`GlowSettings.playerHalo == true`), every mask layer that comes from a player reads **only the alpha** of the player's textures. The one exception is the halo-off debug path (`bodySnapshots` → `sprites.glowMask(for:)`), which reads RGB from a per-look baked mask.

---

## 1. Render architecture

### 1.1 The view
- `GameMetalView: MTKView` (`MetalGameView.swift:20-98`). Its delegate is `GlowRenderer` (`:57`). It runs at 60 fps (`:37`). It takes no touches (`:56`). The HUD is a separate SpriteKit view laid over it (see `_Design/prototype.md:14-17`).
- **Screen format.** `GlowRenderer.screenFormat` is `.rgba16Float` when `edr`, otherwise `.bgra8Unorm` (`MetalGameView.swift:141`). `edr` is true on iOS (iPhone, iPad and Mac Designed-for-iPad) unless footage is running (`:134-140`). With EDR on, the layer uses `wantsExtendedDynamicRangeContent` and `extendedSRGB` (`:31-35`). The TV is never EDR.
- **tvOS.** It draws at 1080p whatever the TV. `autoResizeDrawable = false` and `layer.magnificationFilter = .nearest` (`:38-42`). `layoutSubviews` sets `drawableSize = bounds.size` (`:65-68`). `framingScale = 1` (`:70`) and `renderScale = 1` (`:91-97`).
- **Mac (Designed for iPad).** `layer.magnificationFilter = .nearest` (`:48`). `applyRenderShare()` sets `contentScaleFactor = framingScale * scene.renderShare` whenever `framingScale >= 2` (`:77-81`). It runs every frame (`:488`) and in `layoutSubviews` (`:82-85`).
  - `renderShare` is 0.5 when the fit is not whole pixels or when screen pixels per game pixel is even, otherwise 1 (`GameScene.swift:5134`).
  - The camera's framing always uses the screen's own scale (`MetalGameView.swift:74`, `GameScene.swift:2336-2347`).
- **iPhone/iPad.** `contentScaleFactor` is the screen's native scale. `renderScale = contentScaleFactor` (`MetalGameView.swift:95`).
- **Footage.** The drawable is fixed at `FootageRun.videoSize`, `framebufferOnly = false`, and the scale is 1 (`:50-55`, `:74`, `:95`).
- **Pixel scale.** `GameScene.layout` picks a whole number of screen pixels per game pixel (`GameScene.swift:5114-5141`). The exceptions are not whole-pixel:
  - `seenWhole` stages (Flight B411 fitted, with camera rotation `cameraRotation`)
  - `wholeStageView` (the map maker)
  - Hoopfish Hideaway's width fill
  - follow-cam footage (`FootageRun.followZoom`)

  Sprites can also carry their own `zRotation`: the body's flight tilt, and hoods.

### 1.2 Textures (all made in `mtkView(_:drawableSizeWillChange:)`, `MetalGameView.swift:393-414`)
`makeTexture` defaults to `.bgra8Unorm`, `.private` storage, with usage `[.renderTarget, .shaderRead]` (`:480-485`).

| Texture | Size | Format |
|---|---|---|
| `sceneTexture` | drawable | bgra8Unorm (8-bit, not sRGB) |
| `sceneDepthStencil` | drawable | depth32Float_stencil8, **shared** by the scene, mask, occluder and cube passes; each one clears it |
| `bodyMask` | drawable | bgra8Unorm |
| `occluderTexture` | drawable | bgra8Unorm |
| `glowA`, `glowB` | `Int(w)/2 × Int(h)/2` (`:416-419`) | bgra8Unorm |
| `shotTexture`, `panelTextures` | manga page and capture | bgra8Unorm |

The scene is therefore always drawn into an 8-bit unorm target, whatever the screen's format. EDR only enters in the composite.

### 1.3 SpriteKit renderers and scenes
There are four `SKRenderer`s, plus a fifth that exists only for footage:

| Renderer | Scene | When drawn | Ref |
|---|---|---|---|
| `skRenderer` | `GameScene` | every frame | `:181`, `:289-290`, `:561`, `:590-591` |
| `occluderRenderer` | `MaskScene(whiteBodies: true)` | only on frames where some cube, diamond, block or hex instance has `flags.x > 0.5` (drawn behind players) | `:239-241`, `:295-296`, `:725-743` |
| `maskRenderer` | `MaskScene()` | every frame | `:183-184`, `:291-292`, `:598-616` |
| `ballCamRenderer` | `BallCamScene` | every 3rd frame (`ballCamEvery = 3`), only while `scene.ballCamEnabled` | `:187-201`, `:293-294`, `:851-903` |
| `hudRenderer` (lazy) | `scene.hudScene` | footage only, `ignoresSiblingOrder = true` | `:423-478` |

`ignoresSiblingOrder` is left at its default (false) on every renderer except the footage HUD's. A grep for `ignoresSiblingOrder` finds only `MetalGameView.swift:428` and `HudScene.swift:79`.

**The render-once rule.** The comment at `MaskScene.swift:14-17` says: "Drawing the game scene a second time in one frame is what put white squares on the bodies: SpriteKit reuses its per-frame buffers between the two renders." So any second image of the world gets its own scene and renderer, and that scene mirrors the game's nodes as snapshots. SKShader objects are, however, shared across scenes and renderers without trouble:
- MaskScene's static flat shaders are used by both the mask scene and the occluder scene.
- `BallCamScene` reuses the game's `sprite.shader` objects (`BallCamScene.swift:86`).

### 1.4 Frame order (`draw(in:)`, `MetalGameView.swift:487-710`)
1. Clock: `now = scene.transformCapture?.tick() ?? scene.footage?.tick() ?? CACurrentMediaTime()` (`:504`).
2. `skRenderer.update(atTime: now)` (`:561`). This runs GameScene's update, so node state is final for the frame.
3. Command buffers: `scene`, `mask`, `glow` and `cam` are separate timed buffers (`:563-564`). `commands` carries the composite and present.
4. **Scene pass** into `sceneTexture` (`:570-591`). It clears to `scene.backgroundColor` alpha 1, or to black or white during a transform capture (`:574-583`).
5. `drawCubes` into the same texture, loading it (`:593`, `:715-838`). It runs the occluder pass first when needed. Then `sceneCommands.commit()`.
6. **Mask pass**:
   - `maskScene.syncStatic(scene.staticFlats, version:)` (`:598`), then `maskScene.mirror(...)` with all the snapshot lists (`:599-600`).
   - `maskRenderer.update(atTime: now)` (`:601`).
   - It renders into `bodyMask`, cleared to **(0,0,0,1)** (`:602-614`), then commits.
7. **Glow** (`:618-648`):
   - `GlowUniforms` is filled (`:618-639`).
   - `bright` pass: `[sceneTexture, bodyMask]` → `glowA` (`:641`).
   - Then `GlowSettings.blurPasses` (2) rounds of a horizontal blur (glowA→glowB) and a vertical blur (glowB→glowA), 4 blur passes in all (`:642-647`).
8. Ball cam (`:650-652`).
9. Wave and aberration uniforms (`:653-661`).
10. **Composite**:
    - Either the manga page path (`:662-683`)
    - Or `compositeScreen` with `[sceneTexture, glowA, bodyMask]` into the drawable, with the ball cam trapezoid in the same encoder (`:684-687`).
    - `uniforms.edr.x = min(GlowSettings.edrBoost, headroom)` (`:685`).
    - Footage HUD and recorder (`:689-692`).
11. Transform capture: the composite again into `shotTexture` with `edr.x = 1`, then read back (`:695-706`).
12. Present and commit (`:707-709`).

**Samplers.** Every glow pass uses `sampler`, which is **linear** with clampToEdge (`:335-340`, bound at `:1041`). The ball cam picture uses `nearest` (`:317-322`, `:929`). The pipelines are plain: no blending on bright, blur or composite (`:299-305`, `:330-333`). The ball cam trapezoid blends with sourceAlpha / oneMinusSourceAlpha (`:306-316`).

**Blur step.** `texelSize = blurStep / glowA size` (`:619`). `blurStep` is 0.5 on tvOS and 1 elsewhere (`:248-252`): "The TV renders at 1080p, half what the 4K screen was drawn at, so its half-size glow steps half a texel".

### 1.5 The mask scene (`MaskScene.swift`)
- `BodySnapshot` (`:4-12`) carries only `texture, position, anchor, xScale, size, zRotation, warp`. It has **no yScale, alpha, colour, colorBlendFactor, blendMode, shader or SKAttribute values.** Positions are the node's own `position`, which works because `world`, `bodies` and each figure sit at the origin with unit scale.
- Init (`:47-56`): `size 640×288`, `scaleMode = .fill`, `backgroundColor = .black`, its own camera, and `staticLayer.zPosition = -1`.
- `mirror` (`:101-134`) copies the scene's size and the camera's position, scale and rotation (`:105-108`), then places each category with a fixed shader and depth.
- `place` (`:136-169`) reuses nodes per category and hides the extra ones. The shader is assigned once, when a node is made (`:139-152`). Every frame it sets `texture, size, anchorPoint, position, xScale, zRotation, warpGeometry` (`:161-167`), with size set before xScale.

**Flat shader** (`MaskScene.swift:61-70`). It outputs premultiplied colour and keeps only the texture's alpha:
```glsl
void main() {
    float alpha = texture2D(u_texture, v_tex_coord).a;
    gl_FragColor = vec4(u_flat.rgb * alpha, alpha);
}
```
- Uniform: `u_flat` (vec4).
- It does **not** multiply by `v_color_mix`. Snapshot alpha is ignored anyway.
- Static instances (`:71-79`):

| Name | `u_flat` |
|---|---|
| `flatWhite` | (1,1,1,1) |
| `flatGreen` | (0,1,0,1) |
| `flatBlue` | (0,0,1,1) |
| `flatBlack` | (0,0,0,1) |
| `flatRed` | (1,0,0,1) |
| `flatMagenta` | (1,0,1,1) |
| `flatYellow` | (1,1,0,1) |
| `flatLine` | (0.3,1,0,1) |

**Mask z-order and contents** (`mirror` arguments wired at `MetalGameView.swift:599-600`; GameScene providers cited):

| z | Category (`mirror` arg) | Shader → mask colour | GameScene source |
|---|---|---|---|
| -1 | static layer (`syncStatic`) | flatGreen | `staticFlats` (`GameScene.swift:3601-3646`), rebuilt only when `staticFlatsVersion` changes (`MaskScene.swift:82-95`) |
| -0.9 | `washFree` | flatYellow | `washFreeSnapshots` (Anozira far lightning) `GameScene.swift:3502-3508` |
| -0.75 | `through` | flatBlue | `glowThroughSnapshots` `:1957-2004` |
| -0.5 | `under` | flatGreen | `tornadoSnapshots + soundWordSnapshots` `:2024-2030`, `:2063+` |
| -0.25 | `throughFront` | flatBlue | `glowThroughFrontSnapshots` `:2007-2014` |
| -0.25 | `throughNets` | SKShapeNode stroke blue, `lineWidth = NetTuning.lineWidth`, square cap, `isAntialiased = false` (`MaskScene.swift:120-133`) | `glowThroughNets` `:2017-2020` |
| 0 | `snapshots` (bodies) | **no shader**: the texture drawn as is | `bodySnapshots` `:1780-1788`, **empty when `playerHalo`** |
| 1 | `flat` | flatGreen | `flatSnapshots + unglowingBodySnapshots` (`MetalGameView.swift:599`; `GameScene.swift:2128-2186`, `:1811-1817`) |
| 1.5 | `lines` | flatLine (0.3,1,0) | `lineSnapshots`: each body's `outlineNode.texture` at the body's transform `:1821-1827` |
| 2.5 | `shield` | flatRed | `shieldedSnapshots` = hood **face** masks `:1765-1775` |
| 3 | `cutOut` | flatBlack | `cutOutSnapshots` `:1738-1764` |
| 3 | `hoods` | flatMagenta | `hoodSnapshots` = hood masks, **empty when `playerHalo`** `:1731-1733` |
| 3.5 | `linesOver` | flatLine | `lineOverSnapshots` (`hoodLineNodes + armLinesOverHood`) `:1828-1834` |

Blending is SpriteKit's default `.alpha` over the black clear. For opaque art pixels the result is the flat colour exactly. A partially transparent texel (linear-filtered art in flats, `softGlow`) gives a fractional mask value. The thresholds below then decide what it counts as.

**What the mask holds for a player, by mode.**
- `playerHalo == true` (the default, `Tuning.swift:557`):
  - The body is drawn **whole** in green, together with the swing arm and the hood mask (`unglowingBodySnapshots`, `GameScene.swift:1811-1817`). Green means it never glows in the screen pass.
  - The line is drawn at (0.3,1,0) and the face in red.
  - Black cut-outs at z 3 cover: hood strings, `headNodes` and `energyNodes` (the energy form's head, the slash blade and puffs), score strikes, Z Tea's charge, kept-charge hands, FloState string, web and chain diamonds, and swing sleeves (`:1738-1764`). These glow at the plain threshold.
  - Then `linesOver`.
  - Greyed-out (FloState lockout) clothes, hoods and strings go green via `flatSnapshots` (`:2128-2136`).
- `playerHalo == false` (a debug slider, `GameScene.swift:5529-5532`):
  - Bodies at z 0 draw `sprites.glowMask(for: node.texture)` (`:1786`). This is a per-look, per-frame baked RGB mask, looked up by the body texture (`SpriteLibrary.swift:1216-1223`).
  - Its colours (`SpriteLibrary.swift:2627-2649`):
    - glowing pixels: **black** (0,0,0,1), so they take the plain threshold
    - non-glowing, non-skin pixels: **white**, so they take the body threshold
    - bare skin: **green**, so it never glows
    - the neck under the hood (skin on the `.head` part): **red**, shielded
  - It is nearest-filtered (`:2646`). When a body has no mask, the lookup returns the body texture itself (`:1223`).
  - Hoods are drawn magenta at z 3.

**The occluder scene** (`MaskScene(whiteBodies: true)`):
- It is mirrored with `scene.occluderSnapshots` as bodies and `scene.rimSnapshots` as flat (`MetalGameView.swift:728`).
- `whiteBodies` makes bodies `flatWhite` at z 2 and flats `flatGreen` at z 1 (`MaskScene.swift:142-146`).
- `occluderSnapshots` (`GameScene.swift:1837-1857`) holds each body texture, each outline texture, Breaker percentages, and hood and head textures. Only alpha is used.
- Read by `cube_fragment` and `block_fragment` (`Glow.metal:288-290`, `:339-340`):
  - `r > 0.5` (white) hides cubes with `behind > 0.5`
  - `g > 0.5` (white or green) hides cubes with `behind > 1.5`

### 1.6 Glow.metal: the mask's channel semantics, exactly
`step(edge, x)` is `x >= edge ? 1 : 0`. All mask reads are `.rgb` and the mask's alpha is never read. The mask is sampled with the **linear** sampler, but at exact texel centres (details below), so in effect it is nearest. The exception is the water sway in the composite.

**`glowOfPixel(color, mask, uv, u, out glows, out boostShare)`** (`Glow.metal:69-103`):
```metal
float body = dot(mask, float3(0.2126, 0.7152, 0.0722));
float hooded = step(0.5, mask.r) * step(mask.g, 0.5);          // r>=0.5 && g<=0.5  (red or magenta)
float hood = hooded * mask.b;                                    // magenta 1, red 0
float flat = step(0.5, mask.g) * step(mask.r, 0.5) * step(mask.b, 0.5); // g>=0.5, r<=0.5, b<=0.5 (green, line)
float through = step(0.1, mask.b) * step(mask.r, 0.05);         // b>=0.1, r<=0.05 (blue)
float threshold = mix(u.threshold, u.bodyThreshold, step(0.05, body) * (1 - through) * (1 - hooded));
if (through > 0 && u.waterTop.a > 0 && u.waterTop.a < 1) { // undo water tint
    float3 water = mix(u.waterTop.rgb, u.waterBottom.rgb, uv.y);
    color = saturate((color - water * u.waterTop.a) / (1 - u.waterTop.a));
}
float brightness = max(color.r, max(color.g, color.b));
float background = u.unglowed.a * step(distance(color, u.unglowed.rgb), 0.01);
float base = smoothstep(threshold - u.softness, threshold + u.softness, brightness) * (1 - flat) * (1 - background);
glows = base * mix(1.0, hood, hooded);
boostShare = base * mix(1.0, hood * u.hood.x, hooded);
float amount = boostShare;
if (brightness > 0.05) { // nearest of 9 energy hues; gain if squared distance < 0.1
    float3 hue = color / brightness; ... if (nearest < 0.1) amount *= gain;
}
return color * amount;
```
The constants (`Tuning.swift:528-536`) are:
- `threshold = 0.2`, `bodyThreshold = 0.8`, `softness = 0.2`. The plain ramp is therefore `smoothstep(0.0, 0.4, max channel)` and the body ramp `smoothstep(0.6, 1.0, ...)`.
- `blurPasses = 2`, `intensity = 1`, `tint = (1,1,1,1)`.
- `hoodShare = 0.6` (K&A 1.0, through `GameScene.hoodGlowShare`, `:3227`).
- `edrBoost` defaults to 1.5 and is kept in UserDefaults.
- Energy gains: orange, green and purple 1.75; blue and red 1.25; teal and lime 0.75 (`Tuning.swift:479`).
- Energy hues are packed as colour / max channel, with the gain in w (`:491-497`), for the 9 `EnergyColour.hued` (`PlayerPalette.swift:321`).

How each mask colour reads in the bright pass:

| Mask colour | Classified as | Threshold | Own glow |
|---|---|---|---|
| black (0,0,0) | nothing set | plain 0.2 | full |
| white (1,1,1) | body | 0.8 | full |
| green (0,1,0) | flat | 0.8 (irrelevant) | **none** (`flat` zeroes base) |
| line (0.3,1,0) | flat | — | none |
| blue (0,0,1) | through | plain | full, from the water-untinted colour |
| red (1,0,0) | hooded, hood = 0 | plain | **none** (glows = 0, boostShare = 0) |
| magenta (1,0,1) | hooded, hood = 1 | plain | `glows = base`; `boostShare = base * hoodShare` |
| yellow (1,1,0) | body (lum 0.93), not hooded (g > 0.5), not flat (r > 0.5) | 0.8 | full |

**`glowBright`** (`:112-130`): four taps at `in.uv ± 0.5/fullSize`. When the drawable's width and height are even, these are exactly the centres of the 2×2 full-size texels under each half-size texel. When a dimension is odd (`glowA` is `Int(w)/2`), the taps fall between texel centres and the linear sampler blends neighbours, in the mask as well. It returns:
`float4(max(total / 4, brightestThrough), 1)`, where `brightestThrough` is the single tap glow with the largest max channel among taps whose mask has `b >= 0.1 && r <= 0.05`.

**`glowBlur`** (`:133-145`): a 9-tap Gaussian with weights `{0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216}` and step `direction * texelSize`. Output alpha is 1.

**`glowComposite`** (`:148-205`):
- **Sway:** `uv.x += wave.x * sin(uv.y*wave.y*2π + wave.z) * smoothstep(wave.w, wave.w+0.04, uv.y)` (`:156`). This is only on Hoopfish and Anozira (`GameScene.swift:1934-1942`), and it makes both the scene and the mask sample off-centre with linear filtering.
- **Own glow:** `ownShare, boostShare` come from `glowOfPixel` on this pixel (`:161-162`).
- **Line:** `line = (0.15 <= r <= 0.45) && g >= 0.5 && b <= 0.05` (`:164`), i.e. the flatLine mask.
- **Aberration:** the clash fringes (`:167-175`).
- **Bloom:** `bloom = glow * tint * intensity * (1 - ownShare) * (1 - line)` (`:176`). The bloom does not land on what glows itself, and never on lines.
- **Wash:** `washFree = r >= 0.9 && g >= 0.9 && b <= 0.05` (yellow); `color = mix(color, wash.rgb, wash.a * (1 - washFree))` (`:178-179`).
- **Shield:** `shielded = r >= 0.9 && g <= 0.05 && b <= 0.05` (red); `lit = color + bloom * (1 - shielded)` (`:181-182`).
- **Hood shadow:** `hood = r >= 0.5 && g <= 0.5 && b >= 0.5` (magenta) runs the hood-shadow correction against 10 `hoodShadow` and `hoodLight` tones (distance <= 0.1) (`:185-198`). With `playerHalo` this never fires, because hoods are green.
- **EDR:** `lit = saturate(lit)`; `boost = mix(1, edr.x, boostShare * (1 - shielded))`; and if `boost > 1`, `lit = encodedSRGB(linearSRGB(lit) * boost)` (`:201-203`). With `playerHalo` on, player bodies are green, so `boostShare` is 0 and **the bodies get no EDR boost**. Only the black cut-outs (energy, heads, strings) and other glowers do.

The **ball cam** has its own glow over an **all-black mask**: everything takes the plain threshold, bodies included (`MetalGameView.swift:883-899`). Its texture is 256×160 (`ballCamResolution = 2` × 128×80). `camGlowUniforms` uses `texelSize = 1/glow` with no `blurStep` (`:905-911`). It is composited at alpha 0.66 (`Glow.metal:235`).

### 1.7 Halos (the player glow in the default mode)
- **Setting.** `GlowSettings.playerHalo` defaults to true, and `haloStrength` defaults to `CustomizeArt.glowStrength` = 0.6 (`Tuning.swift:553-560`; `Customization.swift:1972-1973`). Both are **live debug sliders** that persist in UserDefaults: `ParkedSliders.showing` lists "PLAYER HALO" and "HALO STRENGTH" (`Tuning.swift:465`; `GameScene.swift:5528-5536`).
- **Nodes.** Two per player (`GameScene.swift:2493-2506`):
  - `bodyHalo` is a **child of the body sprite** at `haloZ = 0.006`. That puts it over the line (0.005) and the glow line (0.0055) (`:1790-1793`).
  - `hoodHalo` is a child of the figure, also at 0.006.
  - Both use `blendMode = .add` and start hidden.
- **Per frame.**
  - Body halo (`GameScene.swift:11766-11774`): if `playerHalo`, the body is visible and not greyed out, it takes `sprites.haloTexture(frame, player: drawnAs, ...)` (the cached `"_halo"` key, `SpriteLibrary.swift:1001-1004`) and is placed with `placeHalo`, `position = .zero`.
  - Hood halo (`GameScene.swift:12075-12085`): `sprites.hoodHalo(for: hood.texture)`, placed over `drawn.size().scaled(by: drawScale)`, copying the hood's position, xScale and zRotation.
- **`placeHalo`** (`GameScene.swift:1794-1808`) sizes the trimmed piece back onto the body's frame, padded by `haloPad` art pixels per side. The anchor is recomputed so the piece lands where it would on the whole padded canvas. It sets `alpha = haloStrength`.
- **The halo image** (`SpriteLibrary.haloImage`, `:890-912`):
  1. Start from the frame's glowing-parts image (`images.glowing`: only the glowing pixels in the look's colours, premultiplied RGBA in an sRGB `premultipliedLast` context, `:2614-2621`, `:2314-2320`).
  2. Draw it at `haloResolution = 2` texels per art pixel with interpolation `.none`, padded `haloPad = 8` art pixels.
  3. Apply **three** `vImageBoxConvolve_ARGB8888` passes with box size `round(sqrt(4σ²+1)) | 1`, where σ = `CustomizeArt.glowPixels` (2.5) × 2 = 5, so the box is **11×11**. The edge mode is `kvImageEdgeExtend`. Each pass rounds to 8 bits.
  4. Draw the glowing image again with `.destinationOut`, cutting the glowing pixels themselves out.
- **Trimming and filtering.** `haloTexture` trims the image to its painted bounds plus one clear texel (`trimmedHalo`, `:971-997`) and records the piece's place in the canvas in a weak `NSMapTable` (`:939-967`). The halo texture is filtered **`.linear`** (`:942`, `:1205`).
- **Hood halo** (`SpriteLibrary.swift:1660-1668`): the drawn hood, `destinationIn` the hood mask, then `haloTexture`. It is keyed by the drawn hood texture.
- **Interaction with the screen pass.** The halo is drawn **into `sceneTexture`** (additive, alpha 0.6). It is not in the mask. Wherever a halo pixel lies outside the green body silhouette, the mask there is black (or whatever stage flat lies under it). So the halo's own pixels are themselves bloomed by the screen pass at the plain threshold. This is current behaviour, and it is preserved automatically if the scene texture is byte-identical.
- **Other halos.** These are not per-look bakes: `makeHalo` (`softGlow(diameter: 32)` tinted, `.add`, alpha `ballGlow = 0.5`) for hand balls, the loose ball, fireballs and flights (`GameScene.swift:5002-5010`); beam and blast halos (`:11226-11243`, `:11325-11367`); and blip halos over the cam (`:7589-7596`, `:7629-7636`).

### 1.8 Scene layers that matter to the glow
- `world` holds `ground` (z 0), `bodies` (z 20) and `glowers` (z 21), plus the fronts, rain and so on (`GameScene.swift:331-334`, `:2365-2393`). `glowHud` sits at z 100 on the scene.
- **The figure.** Each player's figure is an `SKEffectNode` with `shouldEnableEffects = false` and a per-figure `phantomShader` (`:2468-2474`). Effects (and so the shader) switch on only in phantom mode (`:9471-9487`).
- **Figure alpha.** `figure.alpha` carries the hit-grace blink (0.5) and phantom alpha (`PhantomLook.alpha` 0.5) (`:9474-9476`). This alpha reaches children's shaders through `v_color_mix.a`.
- **Children of each body sprite:**

| Child | z | Note |
|---|---|---|
| `outline` | 0.005 | `colorBlendFactor = 1`, coloured each frame |
| `glowLine` | 0.0055 | |
| `bodyHalo` | 0.006 | |
| `glowingParts` | 0.001 | K&A |
| `chainHand` | 0.002 | `energyToneShader` |

- **Children of the figure:** `head` 0.04, `energy` 0.03 (`energyRampShader`), `hood` (`hoodUpZ` 0.038), `hoodLine`, and `hoodHalo` (`:2476-2560`, `:1174`, `:369`).
- **Body sprite tints** use SpriteKit's built-in `color` / `colorBlendFactor` (`GameScene.swift:11718-11739`):
  - white at 1 (growing, transform flash)
  - glow colour at 0.9 (`reappearTint`) or at 0.85 (spin flash)
  - K&A wash: `KAndAArt.beyond` at `KAndAArt.washAlpha`
  - Hoods take the tint at 0.9 while reappearing.

---

## 2. Every SKShader in the project

A grep of `ProjectEsper` for `SKShader(`, `.shader =`, `SKUniform` and `SKAttribute` finds nothing in `EsperSim/` or `Tools/`. The hits are below.

### 2.1 MaskScene flat: `MaskScene.swift:61-70` (the source is quoted in 1.5)
- Uniform: `u_flat` vec4. No clock.
- 8 static instances (`:71-79`), shared by the mask and occluder scenes.
- Assigned at `:88`, `:110-119`, `:139`, `:145`, `:150`.

### 2.2 `breakerHoopShader`: `GameScene.swift:684-698`
```glsl
void main() {
    vec4 texel = texture2D(u_texture, v_tex_coord);
    vec3 colour = texel.a > 0.0 ? texel.rgb / texel.a : vec3(0.0);
    float level = dot(colour, vec3(0.299, 0.587, 0.114));
    vec3 toned = level < 0.33 ? a_deep : (level < 0.66 ? a_middle : a_glow);
    gl_FragColor = vec4(toned * texel.a, texel.a) * v_color_mix.a;
}
```
- **Attributes:** `a_glow`, `a_middle`, `a_deep` (vectorFloat3). One shader is shared, and the values are set per node with `setTone` → `node.setValue(SKAttributeValue(vectorFloat3:), forAttribute:)` (`:700-703`).
- **Applied** to the rims, backboards and rim fronts in Breaker Ball, swapped only when the shader changes (`:655-670`). No clock.

### 2.3 `opaqueShader`: `GameScene.swift:9342-9349`
```glsl
void main() {
    vec4 texel = texture2D(u_texture, v_tex_coord);
    float solid = texel.a > 0.02 ? 1.0 : 0.0;
    vec3 colour = texel.a > 0.0 ? texel.rgb / texel.a : vec3(0.0);
    gl_FragColor = vec4(colour * solid, solid) * v_color_mix.a;
}
```
- No uniforms. Used for shields when `shieldLook == .opaque` (`:9350-9353`).

### 2.4 `phantomShader(edgeOutline:)`: `GameScene.swift:9500-9529`
```glsl
float phantomHash(float n) { return fract(sin(n) * 43758.5453); }
void main() {
    vec2 uv = v_tex_coord;
    float row = floor(uv.y * u_size.y / \(PhantomLook.glitchRowHeight));
    // Its own clock, wrapped: the renderer never moves u_time, and a large clock is one the hash
    // can't tell apart; either way every row would sit still.
    float tick = mod(floor(u_clock * \(PhantomLook.glitchRate)), 251.0);
    float jumps = step(\(1 - PhantomLook.glitchRowShare), phantomHash(row * 12.9898 + tick * 78.233));
    float shift = jumps * (floor(phantomHash(row * 3.7 + tick * 1.3) * \(2 * PhantomLook.glitchShift + 1)) - \(PhantomLook.glitchShift));
    uv.x += shift / u_size.x;
    vec4 colour = (uv.x < 0.0 || uv.x > 1.0) ? vec4(0.0) : texture2D(u_texture, uv);
    // No early return: SpriteKit's translation rejects one and drops the whole shader.
    float edge = 0.0;
    if (u_edge > 0.5 && colour.a > 0.0) {
        vec2 pixel = 1.0 / u_size;
        float open = min(min(texture2D(u_texture, uv + vec2(pixel.x, 0.0)).a, texture2D(u_texture, uv - vec2(pixel.x, 0.0)).a),
                         min(texture2D(u_texture, uv + vec2(0.0, pixel.y)).a, texture2D(u_texture, uv - vec2(0.0, pixel.y)).a));
        edge = step(open, 0.4999);
    }
    colour.rgb = mix(mix(colour.rgb, u_glow * colour.a, \(PhantomLook.tint)), u_glow * colour.a, edge);
    gl_FragColor = colour * v_color_mix.a;
}
```
- **Constants** are interpolated from `PhantomLook` (`Tuning.swift:336-344`): `glitchRowHeight 2.0`, `glitchRowShare 0.15`, `glitchShift 3`, `glitchRate 12.0`, `tint 0.33`.
- **Uniforms:** `u_glow` vec3, `u_size` vec2, `u_clock` float, `u_edge` float.
- **One instance per node:** each figure gets its own (`:2472`), as does `ballPhantomLayer` (`:2706`).
- **Fed by `layPhantom`** (`:9489-9495`):
  - `u_glow` from the look
  - `u_size` from `calculateAccumulatedFrame().size`
  - `u_clock = Float(drawingClock.truncatingRemainder(dividingBy: 1000))`
- **Called from** `drawPhantom` (`:9481`) and for the ball (`:12709`). It runs on an `SKEffectNode` with `shouldEnableEffects` toggled.
- **Failure notes** (in its comments, and the memory note `skshader-time-hash-collapses`):
  - `u_time` never advances under `SKRenderer`.
  - A large clock collapses the `fract(sin)` hash.
  - A bare `return;` makes SpriteKit's Metal translation reject the shader, which is then silently dropped. Phantom's glitch shipped invisible because of the first two.

### 2.5 `energyToneShader`: `GameScene.swift:10535-10547`
```glsl
void main() {
    vec4 texel = texture2D(u_texture, v_tex_coord);
    float level = texel.a > 0.0 ? texel.r / texel.a : 0.0;
    vec3 toned = level <= 0.5 ? a_glow * (level * 2.0) : a_glow;
    gl_FragColor = vec4(toned * texel.a, texel.a) * v_color_mix.a;
}
```
- **Attribute:** `a_glow` vec3, set per node with `setGlow` (`:10578-10582`).
- **Used on** the warm-up sprite (`:2422`) and `chainHand` (`:2517`).

### 2.6 `energyRampShader`: `GameScene.swift:10552-10565`
```glsl
void main() {
    vec4 texel = texture2D(u_texture, v_tex_coord);
    float level = texel.a > 0.0 ? texel.r / texel.a : 0.0;
    vec3 toned = level > 0.9 ? a_glow : (level > 0.7 ? a_middle : (level > 0.5 ? a_deep : a_glow * (level * 2.0)));
    gl_FragColor = vec4(toned * texel.a, texel.a) * v_color_mix.a;
}
```
- **Attributes:** `a_glow`, `a_middle`, `a_deep` vec3, set per node with `setEnergyRamp` (`:10568-10577`), which goes through `Look.energyRamp` and `setTone`.
- **Used on** the warm-up sprite (`:2425`) and each player's `energy` node (`:2546`). The zone colour cycles with `drawingClock` (`:11948`).

### 2.7 `shadowShader`: `GameScene.swift:10584-10595`
```glsl
void main() {
    float alpha = texture2D(u_texture, v_tex_coord).a;
    gl_FragColor = vec4(u_shade.rgb * alpha, alpha) * v_color_mix.a;
}
```
- **Uniform:** `u_shade` vec4 = `FieldArt.shadow`.
- **Used on** the shadow body and head sprites, with `alpha = FieldArt.shadowAlpha` and z -6 (`:2529-2536`).

### 2.8 `FlightB411Art.caseMaskShader()`: `MapTiles.swift:383-397`
```glsl
void main() {
    vec2 texel = floor(v_tex_coord * u_size) + 0.5;
    vec2 uv = texel / u_size;
    vec2 p = (uv - u_anchor) * u_size;
    float up = sin(u_swing) * p.x + cos(u_swing) * p.y;
    if (up > 0.0) discard;
    gl_FragColor = texture2D(u_texture, uv);
}
```
- **Uniforms:** `u_swing` float, `u_size` vec2, `u_anchor` vec2.
- **One instance per node** (`GameScene.swift:3757`, `:3765`). The values are set in `layCase` (`MapTiles.swift:416-420`).
- **Notes.** It uses `discard`, which is fine. It snaps samples to the texel centre so the art stays crisp. It works only because each piece is a **standalone cropped texture**: `_Design/prototype.md:2433-2434` says "a shader's texture coordinates run over the whole of a texture, so a cut of a sheet mislays the mask". The comment at `MapTiles.swift:380-382` says it was "Checked in a headless render".

### 2.9 MapTiles edge veil: `MapTiles.swift:708-723`
```glsl
void main() {
    vec4 colour = texture2D(u_texture, v_tex_coord);
    vec2 pixel = v_tex_coord * u_size;
    vec2 low = pixel - u_window_min;
    vec2 high = u_window_max - pixel;
    float inside = min(min(low.x, high.x), min(low.y, high.y));
    float veil = inside < 0.0 ? 0.0 : 1.0 - smoothstep(0.0, max(u_fade, 0.001), inside);
    gl_FragColor = colour * veil * u_alpha;
}
```
- **Uniforms:** `u_size`, `u_window_min`, `u_window_max` (vec2), `u_fade`, `u_alpha` (float).
- **One instance per node**, two nodes. The values are set in `layVeil` (`:733-745`).

### 2.10 Shader pass-through
- `BallCamScene.mirror` sets `node.shader = snapshot.shader` (`BallCamScene.swift:86`). `SpriteSnapshot` carries shader, colour, colorBlendFactor, alpha, blendMode, yScale and warp (`:4-19`), but **not SKAttribute values**.
- `GameScene.ballCamSnapshots` (`GameScene.swift:2257-2287`) is what fills those snapshots.

### 2.11 Shader warm-up
`toned` and `ramped` sprites are added to `warmNode` (`GameScene.swift:2408-2453`, shaders at `:2421-2426`) so the pipelines compile before play. `warmStage` draws 4 frames behind the curtain (`:280-310`, `_Design/prototype.md:960-962`). Only the main renderer is warmed this way. The mask, occluder and ball-cam renderers build their own pipelines the first time they draw.

### 2.12 The clock
- `drawingClock` (`GameScene.swift:77`) is `transformCapture != nil || footage != nil ? (lastTime ?? CACurrentMediaTime()) : CACurrentMediaTime()`.
- Every renderer gets `update(atTime: now)`, with the same `now` (`MetalGameView.swift:561`, `:601`, `:729`, `:867`, `:448`).
- `u_time` is unusable under `SKRenderer` (memory note, and the phantom comment at `GameScene.swift:9506-9507`).

---

## 3. Shader test harnesses

- **None is checked in for SKShader.** The other things in the repo are:
  - `EsperSim/Tests/EsperSimTests/*` are pure sim tests (no SpriteKit or Metal); `EsperSim` itself is "Pure Swift, no SpriteKit" (`_Design/prototype.md:8-12`).
  - `Tools/` has no SpriteKit renderer harness.
- **The closest precedent** is `Tools/export_drawn_art.py` with `Tools/export_drawn_art.swift`. It is a **headless Metal** (not SpriteKit) Mac program. It cuts types out of the app sources, compiles them with `xcrun swiftc -O` (`export_drawn_art.py:112`), and loads `Glow.metal` from source with `device.makeLibrary(source:options:)` (`export_drawn_art.swift:20`). It renders `cube_vertex` / `cube_fragment` with the same pipeline setup as `MetalGameView` into bgra8Unorm and writes PNGs. This proves `Glow.metal` compiles and runs outside Xcode on the Mac.
- **Recipe in memory, not in the repo.** The memory note `skshader-time-hash-collapses` describes it: "an `SKRenderer` drawing into an `MTLTexture`, then read its bytes". It says to verify with `SKRenderer`, not `SKView.texture(from:)`, which does not reproduce the frozen clock. And: "Compile every new shader's exact source in the headless harness before calling it done". A standalone run is the only place "SKShader failed to compile" is printed. `MapTiles.swift:380` mentions a past headless render.
- **A probe in this session's scratchpad** (not part of the project, made today at 23:17, apparently by this workflow): `/private/tmp/claude-501/-Users-azurin-My-iOS-Projects-Games/429224bb-c286-401b-830d-94df88cd06f0/scratchpad/harness/probe.swift`, with a compiled `probe` binary beside it. It builds:
  - a 4×2 index texture with `SKTexture(data:size:flipped:)`, `.nearest`
  - a 4×1 palette texture as `SKUniform(name: "u_palette", texture:)`
  - a palette-lookup SKShader on one sprite

  It draws through `SKRenderer` into a `.shared` bgra8Unorm `MTLTexture`, twice (two `update` and `render` calls), and prints the BGRA bytes. I did not run it.

---

## 4. Constraints for adding custom shaders to player sprites

1. **One render per scene per frame** (`MaskScene.swift:14-17`; memory `skrenderer-first-draw-is-white`). Do not draw `GameScene` twice. Any extra image (a part-ID mask, a palette-resolved copy) needs its own `SKScene` and `SKRenderer`, mirrored through snapshots, as `MaskScene` and `BallCamScene` are. Sharing an `SKShader` object across scenes and renderers is proven fine.
2. **The mask reads alpha only, in halo mode.** Every player-derived mask layer is a flat shader that reads `texture2D(u_texture, v_tex_coord).a`:
   - body (green)
   - line (`outlineNode.texture`)
   - face and hood masks
   - cut-outs: head, energy and strings
   - occluder: body, outline, hood, head

   If player nodes come to show an ID map, the snapshots will copy the ID map, and the mask stays identical **if and only if the ID map's alpha channel is byte-identical** to the baked body texture's premultiplied alpha. The halo-off path is the exception: it needs an RGB glow mask per frame per look (white, black, green, red), looked up by **body texture identity** (`glowMask(for:)`, a weak `NSMapTable`). A shared ID texture would break that lookup, so a shader-generated mask would be needed instead.
3. **The snapshots drop per-node shader state.**
   - `BodySnapshot` has no attributes, colour, alpha or yScale (`MaskScene.swift:4-12`).
   - `SpriteSnapshot` copies `shader` but **not SKAttribute values** (`BallCamScene.swift:4-19`, `:86`). The ball cam would therefore draw an attribute-driven palette shader with zeroed attributes, i.e. black, unless the snapshot is extended or the colours come from a uniform or texture keyed per shader instance.
4. **Per-node values.**
   - `SKUniform` values belong to the shader. The project gets per-node uniforms by **making one `SKShader` instance per node** (phantom, caseMask, edgeVeil), which defeats batching.
   - The batch-friendly pattern already in use is **one shared shader plus per-node `SKAttribute`** values: `energyToneShader`, `energyRampShader` and `breakerHoopShader`, set through `node.setValue(SKAttributeValue(vectorFloat3:), forAttribute:)` (`GameScene.swift:700-703`, `:10578-10582`).
   - Attribute types are float, vec2, vec3 and vec4 only. There are no texture attributes, so a per-look palette texture would be a texture uniform (as the scratch probe does). That means either a shader instance per look, or one shared atlas palette indexed by an attribute.
   - Player figures already draw as many separate textures, each made with `SKTexture(cgImage:)` rather than taken from an atlas. Batching across players is therefore not something present today.
5. **`v_tex_coord` covers the whole parent texture** for sub-rect and atlas textures (`_Design/prototype.md:2433-2434`). Plain lookups through `texture2D(u_texture, v_tex_coord)` are fine. Any texel-space maths (`floor(v_tex_coord * u_size)`, neighbour taps as in phantom's edge test, palette rows derived from position) needs standalone textures or the sub-rect passed in. Whether Xcode's atlas packer rotates frames is unverified; it needs checking if ID maps are atlased.
6. **Colour tint is not automatic under a custom shader.** Body nodes rely on SpriteKit's `color` / `colorBlendFactor`:
   - white flash at 1
   - energy silhouette at 0.9, spin flash at 0.85
   - K&A wash (`GameScene.swift:11718-11739`)
   - head and hood tints
   - outline, glow line and hood line nodes coloured at `colorBlendFactor = 1`

   Every existing custom shader uses only `v_color_mix.a`. For pixel identity, a palette shader must reproduce SpriteKit's built-in colour-blend formula exactly. **That formula is SpriteKit-internal and should be measured headlessly** (ambiguous: not in the code).
7. **Alpha and premultiplication.** SpriteKit textures and shader outputs are premultiplied. All existing shaders write `vec4(rgb * a, a) * v_color_mix.a`, and `v_color_mix.a` carries inherited alpha: figure blink 0.5, phantom 0.5, shadows. The scene target is bgra8Unorm and not sRGB, so values are written raw. A palette colour given as `RGB/255` floats round-trips exactly at alpha 1.
8. **Filtering conventions.**
   - Pixel art is `.nearest`: 78 sites, including every per-frame bake (`SpriteLibrary.swift:1204`), glow masks (`:2646`) and hood heads (`:1657`).
   - `.linear` is reserved for soft things: `_halo` (`:942`, `:1205`), `softGlow` (`:2751`), `ballLayerAura` (`:862`), feather and symbols (`:2795`, `:2824`, `:2839`), and the Breaker percent glyphs (`BreakerArt.swift:194`).
   - An ID or index map **must** be sampled nearest. Linear would blend indices.
   - At non-whole scales or rotations (Flight B411's lean, seen-whole and fill stages, flight tilt, the map maker), nearest sampling of an ID map picks the same texel the baked texture would, **provided the texture size and UVs are identical**. Moving frames into an atlas could change tie-breaks at texel edges at non-integer scales (a possible 1-pixel difference; unverified).
9. **The halo is not linear in palette.** It is built by three 8-bit-rounding 11×11 box blurs (vImage, edge-extend) of the premultiplied glowing pixels at 2× resolution, then cut out with `destinationOut`, then trimmed. Drawn linear-filtered, `.add`, at alpha 0.6. A GPU palette version that blurs per-tone coverage would differ by rounding unless it reproduces vImage's per-pass rounding. If byte-identity is required, the halo needs its own decision: keep it CPU-baked per look, or accept or measure the difference. The exact SpriteKit `.add` blend factors with node alpha are also SpriteKit-internal (ambiguous).
10. **The clock.** `u_time` is frozen under `SKRenderer`. Feed a uniform (`drawingClock`, mod 1000) and wrap ticks (mod 251) before any `fract(sin)` hash.
11. **Shader compilation.**
    - No bare `return;` in `main()`: the whole shader is silently dropped (`GameScene.swift:9515`). `discard` is fine (`MapTiles.swift:389`).
    - Compile every new shader's exact source in a headless SKRenderer harness first.
    - Warm new shaders in `warmNode` (`GameScene.swift:2408-2431`) to avoid first-use pipeline hitches. The ball-cam renderer is not warmed and builds pipelines for copied shaders mid-match on first draw.
12. **Render scale per platform.**
    - tvOS: 1920×1080 drawable at scale 1, layer upscale nearest, `blurStep` 0.5, no EDR.
    - iOS: native scale with EDR rgba16Float.
    - Mac: `framingScale * renderShare` (0.5 or 1), layer nearest.
    - Footage: fixed video size, bgra8Unorm.

    The glow is half-size (`Int(w)/2`), so odd drawable dimensions make the bright taps blend.
13. **Ordering.** `ignoresSiblingOrder` is false for the main and mask renderers. Draw order is the tree order plus `zPosition`, which the figure layout depends on: the halo at 0.006 above the line at 0.005, and so on.
14. **Phantom flattening.** In phantom mode the figure `SKEffectNode` rasterises its children, including any player-sprite custom shader, and then applies `phantomShader`. Child shaders must therefore behave identically inside an effect node's offscreen pass.
