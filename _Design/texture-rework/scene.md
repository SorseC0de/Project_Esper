# GameScene player drawing: a map for the GPU palette-swap rework

Scope: how `ProjectEsper/View/GameScene.swift` (GS) draws each in-match player from SpriteLibrary (SL) layer textures. All GS line numbers are `GameScene.swift:N` unless another file is named. I only read files; nothing was edited, built or run.

Conventions:
- Sheet frame numbers in code are 0-based. The user counts frames from 1, so code frame 4 is the user's frame 5.
- An art pixel is 1 scene point × `drawScale`. `node.size = texture.size().scaled(by: drawScale)` (11553), where `drawScale = bodyScale(index) * riderScales[index]` (11551). `bodyScale` is Titan Tea's eased growth (9162-9167). Body textures are 1 texel per art pixel. The thin outline has 2 texels per art pixel, and halos have 2 texels per art pixel with padding (see §6).
- `SpriteLibrary.point()` turns sim units into whole points (`SL:2233-2235`, `pixelsPerUnit = 1.6`, `SL:11`).
- Player slots ("player:" in every accessor) are listed at `SL:78-86`:
  - sides 0 and 1
  - `icePlayer` = 2
  - `transformedPlayer(i)` = 3 + i
  - `turnedPlayer(i)` = 5 + i
  - `customizePlayer(i)` = 7 + i
- Every body layer in a frame is baked under the key `p{slot}_{anim}_{frame}[_whole][_balllifted]{suffix}` (`SL:1065-1067`).

---

## 1. Layers and parents

| Container | Parent | z | Line |
|---|---|---|---|
| `world` | scene | 0 | 2365 |
| `ground` (stage, **player shadows**) | world | — | 2366 |
| `bodies` (**all player figures**) | world | 20 | 2367-2368 |
| `glowers` (effects, snipe cursor, head emitters, webs, ice clones) | world | 21 | 2369-2370 |
| figure `SKEffectNode`, one per player | `bodies` | 0, or 0.5 for the front figure (ball holder / last touch) | 2470-2474, 11504-11505 |
| `warmNode` (every texture drawn tiny at α 0.02) | `glowHud` z 100 | 90 | 2401-2453 |

- **No player-body art is parented to `glowers`.** The comment at 358-360 says the energy node is "among the glowers". That comment is stale: the energy node is added to the figure (2547).
- `MaskScene` (`MaskScene.swift`, its own scene and its own `SKRenderer`) never holds the scene's nodes. It is fed `BodySnapshot` copies each frame (`MetalGameView.swift:599-600`). See §7.
- Ice clones go into `glowers` (11293). Afterimages go into `bodies` (9310). Shadows go into `ground` (2536).
- Draw order: the main `SKRenderer` (`MetalGameView.swift:289`) leaves `ignoresSiblingOrder` at its default `false`. Effective z is therefore the accumulated `zPosition`, and ties fall back to tree order.

Each figure is created at 2470-2473 like this:
```swift
let figure = SKEffectNode()
figure.shouldEnableEffects = false
figure.shader = GameScene.phantomShader(edgeOutline: false)
bodies.addChild(figure)
```
Effects are enabled only in Phantom mode (9473). Figure alpha is set every frame (9476): `(phantomMode ? PhantomLook.alpha(0.5) : 1) * graceBlink`, where `graceBlink` is 0.5 for 4 frames on and 4 off during `hitGrace` (9475). Alpha propagates to every node in the figure.

---

## 2. Node stack per player

Columns below:
- **z** is local. For a child of the body, the effective value is body z (0) plus the local z.
- **CBF** is `colorBlendFactor`.
- **Blend** is `.alpha` unless stated otherwise.
- **α** is 1 unless stated otherwise.
- **Filtering** for every SL player-layer texture is `.nearest` (`SL:1204`). Halo textures are `.linear` (`SL:942`, `SL:1205`), and so is the ball aura (`SL:862`).

All nodes are created in `build()` at 2467-2697 unless a lazy creator is cited. Every one is updated **every rendered frame** in `render()` (11472-~13124), inside the per-player loop that runs from 11507 to 12606.

### 2a. Children of the body node (they inherit its position, xScale flip and zRotation)

| Node (array) | Created | z | Texture accessor (per-frame line) | Colour / CBF | Blend, α, shader | Anchor / size |
|---|---|---|---|---|---|---|
| **body** `playerNodes` | 2478-2480, figure child | 0 | `sprites.texture(frame, player: drawnAs, ballAsEnergy: wholeSheet, ballLifted:)` (11531) | `tint` / `tintShare` (11727-11728). K&A: `beyond` / `washAlpha` (11735-11739). See §4 | alpha | `anchor(for: anim)` = `(0.5, feetFromBottom/pixelSize)` (11554, `SL:2228-2230`); size tex×drawScale (11553) |
| outline `outlineNodes` | 2481-2485 | 0.005 | FloState: `thinOutlineTexture(...)`; otherwise `outlineTexture(...)` (11890-11891). Swapped for `bareOutlineTexture` when the hood is tipped (12053) | CBF 1 (2482). Colour logic at 11898-11904 | alpha | node.anchorPoint / node.size (11894-11895) |
| glow line `glowLineNodes` | 2487-2492 | 0.0055 | `glowLineTexture` (11913). Becomes `bareGlowLineTexture` when tipped (12056-12057) | CBF 1. Colour `EnergyColour.withGlow(look.glow).glowLine` (11912, 11918) | alpha | same as body |
| body halo `bodyHalos` | 2495-2500 | `haloZ` 0.006 (1793) | `haloTexture(...)` (11769), placed by `placeHalo` (1794-1808) | none | **`.add`** (2497). α = `GlowSettings.haloStrength` (1807). Default `CustomizeArt.glowStrength` = 0.6 (`Tuning.swift:535-536`, `Customization.swift:1972`) | computed (§6). position .zero (11771) |
| K&A glowing parts `glowingPartNodes` | 2508-2512 | 0.001 | `glowingPartsTexture(...)` (11757), only when `washed` | none (stays unwashed) | alpha | node size/anchor (11760-11761) |
| Breaker chain hand `chainHandNodes` | 2514-2519 | 0.002 | `backHandTexture(...)` (11745) | attribute `a_glow` = look.glow, or look.bright while flashing (11750-11751) | **shader `energyToneShader`** (2517) | node size/anchor (11748-11749) |
| lockout sizzles | 4340-4352, transient | 0.095 | effect sheets `sizzle1/2` | — | α 0.66, scale 0.1 | — |
| FloState exit burst | 12527-12530, transient | 0.096 | `EnergyEffect.burst.node` (per-player toned effect) | — | — | — |

### 2b. Siblings of the body inside the figure (they copy the body's transform, or compute their own)

| Node | Created | z | Texture (per-frame line) | Colour / CBF | Blend / α / shader | Transform source |
|---|---|---|---|---|---|---|
| padding | 2475-2477 | 0 | none (clear) | — | — | Phantom only: sized to body frame + 2×`glitchShift` (9479-9480) |
| hood `hoodNodes` | 2549-2553 | `hoodUpZ` 0.038 (1174, 11983) | `hoodHead(skin:, player: index, energy: energyForm, view:)` `.drawn`, or `player: icePlayer` when frozen (11979-11981) | `tint` / CBF = reappearing ? 0.9 : 0 (11729-11732). **Only Flash Fizz's reappear tints the hood. Growing, spin flash and the white transform frame do not.** | alpha | xScale reset to 1, then size tex×drawScale (11985-11986). Anchor `anchor(for: .idle)` (11987). Position = body + `leaned(moved)` (11989-11991). xScale = body's, negated if `HoodView.isFlipped` (11992-11994). zRotation = body's (11995). `turn(...)` changes anchor, position and rotation (1199-1207, 12015-12041) |
| hood line `hoodLineNodes` | 2554-2559 | `hoodLineZ` **−0.001** (369), under the body | `hoodLine(skin:, view:, energy:, style:)` (12051) | CBF 1. Colour = glowLine colour if that node is visible, otherwise the outline colour (12065) | alpha | copies the hood (12066-12071) |
| hood halo `hoodHalos` | 2501-2506 | 0.006 | `hoodHalo(for: hood.texture)`, an `NSMapTable` lookup (12076, `SL:1007-1008`) | none | **`.add`**, α haloStrength | placeHalo over hood size; copies hood pos/xScale/rot (12077-12081) |
| hood flash `hoodFlashes` | 2560-2565 | set to `hoodFlashZ` 0.091 every frame (1190, 12264) | `hood.texture` (12257) | CBF 1. `flashColour` (12256) | α 0.85 (2562) | copies the hood (12258-12263) |
| lockout hood grey `lockoutHoods` | 2600-2609 | `hoodUpZ+0.0002` = 0.0382 | `hoodMasks[index].hood`, the hood-only mask from `hoodHead` (12089-12090) | CBF 1, colour `lockoutGrey` = `aap64[39]` #8B93AF (1253, 2603) | alpha | copies the hood (12091-12096) |
| K&A face wash `hoodFaceWashes` | 2666-2670 | `hoodUpZ+0.0001` | `hoodFace(skin:, player: index, view:)` (12237) | colour `KAndAArt.beyond` (`aap64[30]` #242234, `MapTiles.swift:294`), CBF `washAlpha` (12241-12242) | alpha | copies the hood (12243-12248) |
| energy `energyNodes` | 2543-2548 | 0.03 | `energyTexture(...)` (11944). Hidden while `.rolling` | attributes `a_glow`, `a_middle` and `a_deep` via `setEnergyRamp`. Source colour is the zone colour or `look(for: drawnAs).glow` (11948) | **shader `energyRampShader`** (2546) | copies the body's size, anchor, position, xScale and zRotation, **but not yScale** (11949-11953) |
| head `headNodes` | 2539-2542 | 0.04 | `headTexture(frame, player: drawnAs)` (12461) | tint/tintShare (11765-11766) | alpha | size tex × `headScale` 1.25 × drawScale (12479) |
| eyes `eyesNodes` | 2570-2575 | 0.035 | `sprites.texture("transform_eyes", frame.frame)`, an effect sheet that is not per-look (12564) | CBF 1, colour look.glow (12570) | alpha | copies the body (12565-12569) |
| stun body / stun head `stunBodies` / `stunHeads` | 2588-2599 | 0.09 | `source.texture`: the **body's** texture and the head's (11833) | CBF 1, `flashColour` (11832) | blend explicitly `.alpha`, α 0.85 (2593-2594) | copies size, anchor, position, xScale, yScale and rot (11834-11839) |
| lockout clothes `lockoutClothes` | 2600-2609 | 0.037 | `clothesTexture(...)` (11847). Cache suffix **`_skin`** (`SL:1402-1405`) | CBF 1, `lockoutGrey` | alpha | copies the body (11850-11856) |
| ball cover `ballCovers` | 2632-2639 | 0.031 | `overBallTexture(...)` when `player.holding` (11924) | **none set: never tinted or washed** | alpha | copies the body (11930-11936) |
| ball cover line `ballCoverLines` | same | 0.0311 | `overBallLineTexture(...)` when holding and the outline is visible (11925-11926) | CBF 1 (2636). Colour = outline colour (11938) | alpha | copies the body |
| kept-charge hands `keptChargeHands` | 2643-2647 | per frame: `hoodUpZ+0.0011` on arms-over-hood frames when the hood shows, otherwise `keptChargeZ` 0.032 (12178, 1185) | `handsTexture(...)` (12168) | Shield flash: colour `look.bright`, CBF `flash/12`. Otherwise colour `keptChargeWhite` (0.95 grey), CBF `0.85 * (0.5-0.5cos(2πt/1s))` (12179-12186) | alpha | copies the body (12171-12177) |
| arms over hood `armsOverHood` | 2648-2652 | `hoodUpZ+0.001` | `armsOverHoodTexture(...)`. Only when the hood is visible and `armPartsOverHood(frame)` is non-empty (12192-12193, 9065-9069) | **copies body.color and body.colorBlendFactor** (12195-12196), so K&A wash and flashes reach it | alpha | copies the body (12198-12204) |
| arm line `armLinesOverHood` | 2654-2659 | `hoodUpZ+0.0009` | `armsOverHoodLineTexture(frame, player: drawnAs)` (12207) | CBF 1, outline colour (12211) | alpha | copies armOver |
| K&A arm glow `armGlowsOverHood` | 2660-2664 | `hoodUpZ+0.0011` | `armsOverHoodGlowingTexture(...)`, only when `washed` (12220-12221) | none (unwashed) | alpha | copies armOver |
| hand ball `handBalls` | 2617-2621 | 0.03, or −0.002 when behind the body (12348) | basketball textures, ball layer / painted ball (12300-12370). Not player-look art | — | — | its own placement |
| ball aura `ballAuras` | 2622-2629, child of handBall | −0.001 | `ballLayerAura` (12320), `.linear` | CBF 1, team colour (12325) | **`.add`**, α `ballAuraStrength` 0.8 | padded (12321-12329) |
| hand halo `handHalos` | 2671-2674 (`makeHalo` 5002-5010) | 0.02, or −0.003 behind | softGlow | CBF 1 | **`.add`**, α 0.5 | 18×18 |
| beam arms `blastArmNodes` | lazy, 1345-1362 | `hoodUpZ+0.002`; line child −0.0005 | `texture(AnimationFrame(.beamArms,0), drawnAs)` and line `outlineTexture` (11587-11590) | arm: none. Line: CBF 1, outline colour, or `look.outline` if the outline is hidden (11593) | alpha | anchor `blastArmsAnchor` (31.5/64, 33.5/64). zRot `beamAim*facing` (11602) |
| blast pose arms `blastPoseArmNodes` (front, back) | lazy, 1366-1405 (`shoulderArms`) | front `hoodUpZ+0.002`. Back set every frame to `node.zPosition-0.001` = −0.001 (11668). Lines −0.0005 | `frontArmTexture` / `backArmTexture(AnimationFrame(.blastArms, f))` and `blastArmOutlineTexture(front:)` (11646-11656) | arm: none. Line as for the beam arms | alpha | anchor at the shoulder (1392). zRot `blastAngle*facing` (11667). Up-nudge on the front arm (11662-11664) |
| web-shot arms `webShotArmNodes` | lazy, 1377-1383 (`shoulderArms`) | same as the blast arms | `texture(AnimationFrame(.webshootBackArm/FrontArm/WallArm, f))` and `outlineTexture` (11699-11704) | same as the blast arms | alpha | rot `shotTurn*facing` (11710) |
| swing arm `swingArmNodes` | lazy, 1422-1440 | `hoodUpZ+0.002`; line −0.0005 | `texture(AnimationFrame(.swingArm,0))` and `outlineTexture`. Also `glowingPartsTexture` kept for the mask (11610-11614) | as for the blast arms | alpha | anchor = shoulder (19.5, 21)/canvas (1426). Rot toward the sky point (11630-11631) |
| charge, charge overlay | 2576-2586 | 0.05, 0.06 | per-player toned effect sheets: `effectTexture(...)` (12402, 12408, 12416), `texture(fireCharge...)` | — | — | — |
| hood strings `hoodStrings` (`HoodStrings.swift`) | 2566 | `hoodUpZ+0.0005`. `floatingStringZ` 0.045 is unreachable, see §9 | `flatSquare` pixels, no player art | plain/accent colours from `look.hoodTones` (12151-12157) | — | — |

FloState strings are not SpriteKit nodes. They are `CubeInstance` diamonds drawn by the Metal layer (12102-12141, 378-382).

### 2c. Outside the figure

| Node | Parent | Texture | Notes |
|---|---|---|---|
| shadow body / shadow head | `ground`, z −6 (2530-2538) | body/head `.texture` (10608) | `shadowShader` reads alpha only (10584-10595). α `FieldArt.shadowAlpha × (1-share)`. Warp-sheared (10621-10624). yScale −scale |
| afterimages | `bodies`, z −1 (+0.01 for the hood) | `body.texture` / `hood.texture` / `energyNodes.texture` (9297-9318) | CBF 1, colour `look.bright` or the FloState rainbow. α 0.9, held 0.1 s then faded over 0.3 s. Size uses **`abs(body.size.width)`** (9300) |
| Zones phantoms | `bodies` (`ZonesPlay.swift:447-477`) | copies of `playerNodes[0]` and `hoodNodes[0]` `.texture` (6250-6253) | CBF 1, α 0.55, `abs(size)` |
| ice clones | `glowers`, z 6 (11253-11302) | `texture(frame, player: icePlayer)`, `outlineTexture` (line child z 0.1, CBF 1, `Look.ice.outline`), and `hoodHead(skin:, player: icePlayer).drawn` (hood child z 1) | node α 0.3 + 0.5 × life. Made once per clone |

### 2d. Effective z order inside one figure (ascending)

1. Hand halo when the ball is behind (−0.003), hand ball behind (−0.002).
2. Back blast/web arm line (−0.0015), back blast/web arm and **hood line** (both −0.001, tie decided by tree order).
3. Padding and body (0).
4. The body's own children:
   - glowing parts 0.001
   - chain hand 0.002
   - outline 0.005
   - glow line 0.0055
   - body halo and hood halo (both 0.006, both additive, so their order doesn't matter)
5. Hand halo (0.02).
6. Ball aura (0.029). Energy and hand ball (both 0.03; tree order puts energy first, since it is created at 2547 and the hand ball at 2620).
7. Ball cover and its line (0.031, 0.0311). Kept-charge hands (0.032). Eyes (0.035). Lockout clothes (0.037).
8. The hood group:
   - hood 0.038
   - face wash 0.0381
   - lockout hood 0.0382
   - hanging strings 0.0385
   - arm line 0.0389
   - arms over hood 0.039
   - arm glow and over-hood kept-charge hands (both 0.0391, a tie)
9. Head, front blast/web/beam/swing arms (0.040), with their lines at 0.0395.
10. Charge (0.05) and charge overlay (0.06).
11. Stun flashes (0.09), hood flash (0.091), sizzles (0.095), exit burst (0.096).

---

## 3. Per-frame update order (render loop 11507-12606)

1. `shownFrame` (11509, 8482-8496) picks the frame: the slash contact frame during a clash hit-stop, the clash play-out, the Shieldflip frame, or `player.animationFrame`.
2. `drawnAs` is chosen (11529-11530):
   ```swift
   let drawnAs = player.frozen > 0 ? SpriteLibrary.icePlayer
       : (energyForm ? SpriteLibrary.transformedPlayer(index) : sprites.bodyPlayer(index, facingLeft: player.facing == .left))
   ```
   - Frozen takes priority over FloState.
   - `energyForm = player.inFloState || (changing && frame.frame >= 5)` (11527; `transformEnergyFrame = 5`, 9600).
   - `bodyPlayer` returns the turned slot only when that slot's look differs (`SL:90-93`).
   - The energy form and the ice look have no turned variant; they flip with xScale alone.
3. Body texture, size, anchor and position. Position adds: drift (whole points), the K&A car sag, the Anozira ride, the transform lift +7 (9598), and the dunk nudge and grip (11531-11581).
4. `node.xScale = facing.sign` (11582). **Size is assigned at 11553, before xScale at 11582.** The hood code instead resets xScale to 1 before sizing (11984-11986, comment: "a sprite's size is taken against its scale"). Afterimages and Zones phantoms take `abs(body.size.width)`, which suggests the body's `size` can read back negative. A rework must reproduce the net quad exactly.
5. Arms: beam (11584-11603), swing (11606-11639), blast pose (11642-11669), web shot (11673-11717).
6. Tints (11720-11766), then the halo (11767-11775).
7. Tilt: `bodyTilt` eased 0.2 a frame, or set outright from `fadeawayLean×facing`, the spin tilt (10°) or the spin-dunk tilt (11779-11797). Then the Shieldflip middle turn (11799-11805), then the rim turn and Anozira nod (11807-11816). All are applied to `node.position` and `node.zRotation`. **The body's quad is rotated, and every texture is sampled with nearest filtering under that rotation.**
8. Stun/absorb flashes (11821-11840), lockout clothes (11844-11866), snipe cursor, `drawPhantom` (11883).
9. Outline and glow line (11887-11921), ball covers (11923-11939), energy (11942-11956).
10. Hood (11966-12045), hood line / bare outline (12047-12074), hood halo (12075-12085), lockout hood (12087-12097), strings (12102-12159), kept-charge hands (12162-12188), arms over hood (12190-12232), face wash (12234-12250), hood flash (12253-12265).
11. Hand ball, halo, aura and charge (12272-12454). Head (12458-12497). Cube emitters (12501-12558). Eyes (12561-12571).
12. `placeSurf` (12573, 9950-10010) turns the body and head about the board, along with this list of riders:
    `[handBalls, handHalos, energyNodes, chargeNodes, hoodNodes, hoodFlashes, lockoutHoods, lockoutClothes, stunBodies, stunHeads, eyesNodes]` (9994-9998).
    That happens **after** the siblings above copied `node.position`.
13. Shadows (12574-12580) and afterimages (12585-12592).

Later in `render()`, during `roundIntro`, the body, head, energy and ball are hidden (13084-13094). Earlier per-frame reads of `node.isHidden` therefore see last frame's value.

---

## 4. Colours and tints at runtime (body node)

From 11720-11739:
```swift
let spinFlash = player.spinPhasing && match.frame / GameScene.spinFlashFrames % 2 == 0      // 4 on / 4 off (9358)
let reappearing = match.frame < reappearUntil[index, default: 0]                              // Flash Fizz
let tint: SKColor = spinFlash || reappearing ? SKColor(rgb: sprites.look(for: index).glow) : .white
let flashWhite = changing && frame.frame == GameScene.transformWhiteFrame                     // frame 4 (9599)
let tintShare: CGFloat = growing || flashWhite ? 1 : (reappearing ? GameScene.reappearTint : (spinFlash ? 0.85 : 0))
node.color = tint; node.colorBlendFactor = tintShare
...
let washed = kAndAArt != nil && tintShare == 0
if washed { node.color = SKColor(rgb: KAndAArt.beyond); node.colorBlendFactor = KAndAArt.washAlpha }
```
- `reappearTint` = 0.9 (92).
- `growing` is Titan's growth (11552).
- `KAndAArt.washAlpha` is read from UserDefaults `esper.kAndA.washAlpha` and **defaults to 0.5** (`MapTiles.swift:192-194`). The comment there still says "a tenth".
- The head copies `tint` / `tintShare` (11765-11766).
- Arms over hood copy the body's final colour and CBF, including the wash (12195-12196).
- **Nothing else** takes these tints: not the outline, energy, ball covers, blast/web/beam/swing arms, glowing parts or chain hand.

Outline colour (11896-11904):
```swift
let cycling = ZoneTuning.inTheZone || floStateLine
let lineColour = cycling ? ZoneTuning.outline(at: drawingClock) : SKColor(rgb: sprites.look(for: index).outline)
let tumbleFlash = player.spinPhasing || player.phantomMode ? SKColor(rgb: sprites.look(for: index).glow) : nil
outlineNode.color = growing ? .white : tumbleFlash ?? (player.frozen > 0 ? SKColor(rgb: Look.ice.outline) : lineColour)
```
- `ZoneTuning.outline` eases linearly through `aap64[7, 11, 19, 20, 27]` at 0.25 s each (`Tuning.swift:253-272`). It runs on the **wall clock** (`drawingClock`, 77).

Glow line: visible only while `lineInLook` (11910-11911). That means none of these apply: growing, in the zone, FloState line, frozen, spin phasing, phantom. The look's glow must also be a stock `EnergyColour` (11912; `withGlow`, `PlayerPalette.swift:290`). Its colour is `EnergyColour.glowLine`, a VARIA64 index per colour (`PlayerPalette.swift:255-`).

Flashes (11821-11840):
- **parried**: `parryLocked && (attackLockout/2)%2==0`, colour `PixelPalette.colours[8]` = #1C121C.
- **stunned**: hitStun>0, every other pair of frames, colour `look.energyTone(luminance: 0.15)`.
- **tumbling lockout**: `(stateTimer/4)%2==0`, colour[8].
- **absorbing a FLO orb**: colour look.glow.

Each draws a CBF-1, α-0.85 silhouette of the body (and head) at z 0.09, plus the hood flash at 0.091. The design doc `_Design/prototype.md:726` says the parry flashes "palette 2". **The code uses EDG64/VARIA64 index 8**, and the comment at 11819-11820 says "EDG64 8". The code is the source of truth.

FloState lockout (the "skin layer" flash), 11844-11858:
- `lockoutOn = floStateLockout > 0 && !inFloState && (floStateLockout/4)%2==0`.
- When on, the clothes layer (`clothesTexture`, cache key `_skin`) and the hood mask are drawn flat in `aap64[39]`.
- `greyedOut` gains the player. That suppresses both halos, removes the hood from the glow mask, and makes the strings and clothes/hood flats unglowing (1771, 2130-2136, 11768, 12076).
- Strings and FloState diamonds take `lockoutGrey` (12120, 12156-12157).
- The comment at 1247 ("flashing palette 17") is stale.

Kept charge, chain hand, eyes and arm lines: see §2.

---

## 5. Look-driven visuals, one by one

- **FloState body**: slot `transformedPlayer(index)`.
  - Line: `thinOutlineTexture`, a white line at half thickness on a canvas with 2 texels per art pixel (`SL:1394-1398`), drawn at body size, so each texel is half a point. Coloured with the zone rainbow (11889-11904).
  - No glow line. No hood line or bare outline (`!floStateLine`, 12049).
  - Hood: `hoodHead(energy: true)`. Strings: Metal diamonds instead of `HoodStrings`.
  - Energy ramp colour: `look(for: transformedPlayer).glow` (11948).
- **Transform** (`changing`):
  - Lift +7.
  - Frame 4: all white (CBF 1), body and head only.
  - Frames ≥5 use the energy form.
  - `transform_eyes` over the body.
  - Cube spiral up to frame 4 (12537).
- **Frozen**: slot `icePlayer` for every body-canvas layer.
  - Hood: `hoodHead(skin:, player: icePlayer)`.
  - Outline colour `Look.ice.outline`.
  - No glow line, no strings.
  - Hood line `energy:` forced false (12051). Ball look `.ice`, and no ball halo.
- **Phantom**: the figure's SKEffectNode is flattened (`shouldEnableEffects = true`) and run through `phantomShader(edgeOutline:false)` (9500-9529, uniforms set in `layPhantom` 9489-9495).
  - Tint: one third toward the glow (`PhantomLook.tint 0.33`).
  - Rows 2 points tall jump up to ±3 points, 15% of rows, re-picked 12 times a second.
  - Figure α 0.5. Outline colour = glow. No glow line.
  - Shader source (quoted at 9501-9524):
    ```glsl
    float row = floor(uv.y * u_size.y / 2.0);
    float tick = mod(floor(u_clock * 12.0), 251.0);
    float jumps = step(0.85, phantomHash(row * 12.9898 + tick * 78.233));
    float shift = jumps * (floor(phantomHash(row * 3.7 + tick * 1.3) * 7.0) - 3.0);
    uv.x += shift / u_size.x;
    vec4 colour = (uv.x < 0.0 || uv.x > 1.0) ? vec4(0.0) : texture2D(u_texture, uv);
    ... colour.rgb = mix(mix(colour.rgb, u_glow * colour.a, 0.33), u_glow * colour.a, edge);
    gl_FragColor = colour * v_color_mix.a;
    ```
    - The interpolated constants come from `PhantomLook` (`Tuning.swift:336-344`).
    - `u_size` is the figure's accumulated frame in points.
  - Because the figure is flattened first, any per-sprite palette shader runs **before** this shader.
- **K&A**:
  - Body washed (`beyond` #242234 at `washAlpha`).
  - The glowing parts are redrawn unwashed over it (child, z 0.001).
  - Arms over hood are washed, with their glowing sleeve redrawn unwashed (`armsOverHoodGlowingTexture`).
  - The hood itself is unwashed (it glows). Its face (`hoodFace`) is drawn washed over the hood.
  - The head, energy and outline are not washed. **Ball covers are not washed** (11924-11937 set no colour).
  - The glow mask's hood share is 1.0 on K&A (`Tuning.swift:521-528`, `hoodGlowShare` 3227).
- **Hood and face**:
  - One hooded-head texture per (skin, slot, energy, view) (`SL:1621-1650`). The view comes from `HoodView.of(frame)` (`SL:2938-2970`), on a 48-pixel canvas.
  - Placed by the head landmark's delta from `hoodDrawnFor = AnimationFrame(.idle, 2)` (`SL:2069`). Whole-pixel rounded, plus `headNudge` (11989-11991, 9108-9114).
  - Tipped by flight, aim or a sheet turn (12001-12041). When tipped (12048), the body line swaps to `bareOutlineTexture` / `bareGlowLineTexture`. The hood carries `hoodLine` at z −0.001 and recoloured.
  - `hoodMasks[index] = (hoodHead.hood, hoodHead.face)` (11982) feeds the glow mask and the lockout grey.
- **Arms over hood**: the frames are `frontArmOverHood` and `bothArmsOverHood` (9039-9069). Body texture, line, and K&A glow are covered in §2b.
- **Back hand (Breaker Ball)**: `backHandTexture` on the chain hand, run through `energyToneShader` (11740-11755). It shows while the hand holds the chain and FloState strings don't pull it, or during `chainHandFlash`.
- **Ball in hand**:
  - The ball sprites are ball art, not player looks.
  - Player art involved: `overBallTexture` / `overBallLineTexture` (z 0.031 / 0.0311) over the hand ball (z 0.03).
  - The `_whole` bake key is the Volta bolt throw with nothing in hand (11521). `_balllifted` is a snatch that took nothing (11523).
- **Blast / beam / web / swing arms**: see §2b.
  - They are never tinted, washed or flashed.
  - Only the swing arm reaches the glow mask (1759-1762, 1783).

---

## 6. Shaders already attached (exact source)

The energy ramp shader is on the energy node (2546). It is shared, with values set per node through attributes (10552-10564):
```glsl
vec4 texel = texture2D(u_texture, v_tex_coord);
float level = texel.a > 0.0 ? texel.r / texel.a : 0.0;
vec3 toned = level > 0.9 ? a_glow : (level > 0.7 ? a_middle : (level > 0.5 ? a_deep : a_glow * (level * 2.0)));
gl_FragColor = vec4(toned * texel.a, texel.a) * v_color_mix.a;
```
- Attributes `a_glow`, `a_middle` and `a_deep` are `vectorFloat3`.
- They are set by `setEnergyRamp` (10568-10576) from `Look.energyRamp` (`PlayerPalette.swift:190-193`). Stock colours give (glow, hoodShadow, backLimbs). Other colours give (glow, glow × (1+backLegShare)/2, glow × backLegShare).
- **This is the existing model of GPU palette toning for the rework to follow.** It is grey-level thresholding on the red channel, un-premultiplied.

The energy tone shader is on the chain hand (2517) (10535-10546):
```glsl
float level = texel.a > 0.0 ? texel.r / texel.a : 0.0;
vec3 toned = level <= 0.5 ? a_glow * (level * 2.0) : a_glow;
gl_FragColor = vec4(toned * texel.a, texel.a) * v_color_mix.a;
```

- The shadow shader (10584-10595) is alpha only, `vec4(u_shade.rgb*alpha, alpha) * v_color_mix.a`.
- The phantom shader is covered in §5.
- `MaskScene.flat*` (`MaskScene.swift:61-79`) is alpha only: `vec4(u_flat.rgb * alpha, alpha)`.
- All of these are warmed at build on a sample texture (2420-2431).
- **SpriteKit ignores `color` and `colorBlendFactor` on a node with a custom shader.** These shaders only use `v_color_mix.a`. A palette shader that replaces a tinted node must apply the partial tint itself:
  - body tints 0.85 and 0.9, and the wash at 0.5
  - hood 0.9
  - arms over hood, face wash and kept-charge hands
  - The exact SpriteKit colorize math under premultiplied alpha must be measured (§10).
- The halo is a placed, pre-blurred texture with `.linear` filtering, 2 texels per art pixel, padded `haloPad` = 8 art pixels, and trimmed. Its placement data is a `HaloPiece` looked up by texture (`SL:886-975`, GS 1794-1808).
  - `artWidth = canvas.width/2 - 16`
  - `pad = 8 × size.width/artWidth`
  - the anchor is recomputed so it lands on the body's anchor
  - **An index map cannot reproduce this without a GPU blur, or without keeping these halo bakes.**

---

## 7. Copies of layer textures and what they read

| Consumer | What it reads | Lines |
|---|---|---|
| Stun body/head, hood flash, lockout clothes/hood, outlines and all `*Line` nodes | alpha only (CBF 1 silhouettes) | §2 |
| Afterimages, Zones phantoms | alpha only (CBF 1) | 9297-9318, `ZonesPlay.swift:447-466` |
| Shadows | alpha only (shader) | 10584-10628 |
| MaskScene, `playerHalo` **on** (default, `Tuning.swift:533`) | `unglowingBodySnapshots`: body textures, swing arms and hood masks drawn flat green (1811-1817). `lineSnapshots`: outline textures flat line colour, depth 1.5 (1821-1827). `lineOverSnapshots`: hood line and arm lines at depth 3.5 (1828-1834). `cutOutSnapshots`: head, energy, kept-charge hands, Z Tea charge, hood strings, FloState diamonds, swing-arm glowing parts, all flat black (1738-1764). `shieldedSnapshots`: face masks flat red (1765). `flatSnapshots`: greyed-out clothes, hood and strings (2128-2136). **All read alpha only** | `MaskScene.swift:101-169` |
| MaskScene, `playerHalo` **off** | `bodySnapshots` draws `sprites.glowMask(for: body.texture)` **in colour**, with no shader (1780-1788, `MaskScene.swift:109`). `hoodSnapshots` are magenta. The glow-mask texture is found through an `NSMapTable` keyed by the body texture object (`SL:1216-1223`) | — |
| Occluder scene | body, outline, hood and head, flat white, alpha only (1837-1855, `MetalGameView.swift:728`) | — |

So in the default configuration, every consumer outside the main draw needs only **coverage alpha** for each layer.

That has two consequences:
- If several layers collapse into one index/part map, every snapshot list above must either pass a per-layer coverage texture or be given a part-aware mask shader.
- The halo-off path needs the glow-mask colours.

The blast, web and beam arms are not in any snapshot list. Their pixels outside the body therefore bloom at the plain threshold. This is existing behaviour.

---

## 8. Runtime look changes, rebuilds and stutters

- `applyColours(_:looks:)` (8089-8116) calls `sprites.setLook` for each side. Then it recolours:
  - stun colours, webs, block tiles, arcs, end zones, labels and nets
  - the hoopcase art
  - `headStreamsCache = [:]`
  
  Then it runs `warmDrawnArt()`, `warmWinPoses()` (which waits on `afterRebuilds`, 8032-8042) and `drawSeries()`.
- `SL.setLook` (`SL:101-115`):
  - Returns early if the look is unchanged.
  - Otherwise it drops the side's slot, its transformed slot and its turned slot.
  - The drop clears every `p{slot}_` key: body layers, toned effects, silhouettes, hood heads and portraits (`SL:247-253`).
  - It then `rewarm`s them off the main thread (`SL:310-`). That covers every animation frame, plus the `_whole` and `_balllifted` variants, toned effects, silhouettes, hood heads and portraits.
  - **Until the rebuild lands, any frame the render loop asks for is made synchronously on the main thread** (`SL:1073-1086`, logged by `reportMiss` when `reportsMisses`, set at 5701). That is the main stutter.
- Callers:
  - build (2359-2361)
  - `startSeries` / `startTutorial` / transform capture (6096-6142)
  - leaving Zones (6420)
  - the debug COLOUR picker (5216-5222)
  - the online launch (7742) and online drop (8171)
  - the live customize screen (`Customization.swift:280`, through `applyCustomizations`)
  - Footage (`Footage.swift:293, 335`)
  - **Zones `zonesLooks()`** (6391-6399), called on every fresh match or turn (6171, 6378, 6696). It swaps both sides' looks between slots 0 and 1, so **both** slots rebuild in full each time the shown side changes.
- PLAYER VISIBILITY calls `reloadPlayerVisibility` (7834-7836, from `TitleOverlay.swift:429`), which calls `SL.reloadMatchLines`. That drops the hood lines and every match slot, then runs `warmUp` again (`SL:192-197`). `SL.redrawPlayers` (`SL:199-204`) has **no caller** in GameScene.
- Pieces made lazily on the main thread mid-match when absent:
  - `bareOutlineTexture` (`SL:1335-1355`; "on the spot elsewhere")
  - `armsOverHoodGlowingTexture` (`SL:1267-1283`), K&A only
  - `backHandTexture` (`SL:1286-1299`), with no miss report
  - `hoodFace`, `hoodLine` and `hoodHead`
  - `partsTexture`-based arms
  - `ballLayerAura`
  
  I did not check whether `warmUp` / `rewarm` covers each of these. That belongs to the SpriteLibrary map.
- GPU first use:
  - At build, `warmNode` draws `sprites.allTextures` as cached **at that instant**. The async `warmUp` has only just started (2397-2406).
  - `warmStage` preloads every texture then in the scene (280-310). The count waits for `afterRebuilds` (322).
- Steady per-frame CPU work: about 10-20 String-keyed dictionary lookups per player per frame. Each accessor first calls `texture(...)`, which builds `frameKey` by string interpolation. There are also `NSMapTable` lookups (`hoodHalo`, `haloPiece`, `glowMask`) and several `landmark` lookups.

---

## 9. Quirks a pixel-identical rework must reproduce, or decide on deliberately

1. **Partial tints**:
   - spin flash 0.85, reappear 0.9, grow/transform-white 1.0, K&A wash `washAlpha` (default 0.5)
   - hood: reappear only
   - head: same as body
   - arms over hood: copy the body
   - face wash, and kept-charge hands (breath × 0.85, or flash/12)
2. Untinted layers that sit over a tinted body: ball covers, blast/web/beam/swing arms, glowing parts (on purpose on K&A), chain hand, energy.
3. `placeSurf` turns a fixed rider list (9994-9998). These are **not** turned, because they copied `node.position` before the turn:
   - ball covers and their lines
   - arms over hood, arm lines and arm glows
   - hood line and hood halo
   - face wash and kept-charge hands
   - blast/web/beam/swing arms
   
   Whether these can co-occur with surfing in play is unverified.
4. Body `size` is set before `xScale` (11553 vs 11582). The hood resets xScale to 1 before sizing. `abs()` in the copies suggests a negative `size` can read back.
5. `headNodes` never show in practice. `Look.energyFormHeadApart = false` (`PlayerPalette.swift:89-90`), so the `_head` texture is never made (`SL:2416`), `headTexture` returns nil, and 12460-12485 is a dead path. The `HoodStrings.floState` style and `floatingStringZ` are also unreachable (12142-12149).
6. The energy colour comes from `look(for: drawnAs)` (11948): the ice glow when frozen, the transformed look's glow in FloState. Every other colour lookup uses `look(for: index)`.
7. The glow line needs a stock `EnergyColour` glow, otherwise it is hidden.
8. The thin outline (2 texels per art pixel) and the halos (2 texels per art pixel, linear, padded, trimmed) are the only layers not on the 1-texel-per-art-pixel body canvas.
9. Landmarks come out of the CPU bake (`SL:1084` `landmarks[key] = made.landmarks`, keyed per slot). The scene depends on them for:
   - the hood placement (11968-11969, 12016)
   - the ball in hand (12345)
   - sizzles (11865)
   - cubes (12492-12555)
   - Z Tea's charge (2906)
   
   A rework that removes the bake must still supply them.
10. Per-player toned effects are cached per slot and rebuilt with the look, so they share the rebuild cost. They would suit the same GPU toning as `energyRampShader`:
    - `effectTexture` (`SL:1600-1606`)
    - `silhouetteTexture` (`SL:1569-1575`)
    - Their call sites: shields 9387, Z blast 11239, beam pieces 11346, charges 12402-12416, clash slide 8504, wall spark 8781, and `sheetFrames` 9648.
    - `iceTexture` (8664) is not per player.

## 10. Ambiguities and things to verify

- SpriteKit's built-in colorize formula for `colorBlendFactor` between 0 and 1 with premultiplied textures is undocumented. Measure it headlessly before writing a palette shader that must match 0.85, 0.9 and 0.5 exactly.
- The resolution of the SKEffectNode's offscreen flatten in Phantom (points vs pixels) affects the shader's `u_size` row height. Measure it if Phantom must match.
- Whether all lazily-made pieces (§8) are pre-warmed is covered by the SpriteLibrary map.
- The design doc's "palette 2" for the parry flash differs from the code's `colours[8]` (11828).
- Non-match users of the same bakes, outside the in-match stack but sharing the cache:
  - `portrait` (win 7867-7893, updates 7927-8014, customize 7811)
  - `standalone` / `standalonePicture` (pick screen 7320-7349, customize seated 7823-7826)
  - `zTeaArms` (1303-1343)
  - `overBallImages` (7888)
  - `customizeHood` / `hoodHeadPicture` (8078-8085)
  
  They render to CGImages and SwiftUI, so they need the colours on the CPU or a matching path.
