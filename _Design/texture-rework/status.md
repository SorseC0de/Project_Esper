# Texture rework — status (2026-11-19, morning)

Goal: player art drawn from GPU maps instead of a dozen CPU-painted pictures per frame per look slot
(~43k textures, ~1.6–1.9 GB on the TV). Look must stay pixel-identical.

## Where things are
- Brought into the main checkout on 2026-11-19 (uncommitted there, with the rest of build 15's work).
- Branch `texture-rework`, worktree `../Project Esper texture-rework`: where it was built, kept as a record.
- Branch `pre-texture-rework`: snapshot of the main working tree when the rework began (restore point).

## What a frame is now
One set per frame per body shape (`PlayerMap.ShapeKey`: covered limbs, energy form, line width,
stroked groups, line style), shared by every slot whose look has that shape. In a default match the
two sides, their turned slots and the ice look are one shape; the two energy forms are another.
- **map** (RGBA8): palette slot, glow-mask kind, layer flags (body, glow line, bare glow line, glowing,
  clothes), body alpha. Read pixel-sharp: SpriteKit samples a custom shader's texture linearly
  whatever its filtering mode, so every map shader snaps to the texel centre.
- **coverage** (RGBA8): energy grey, energy alpha, bare line, line. Read linearly where the old
  pictures were (the energy ramp, the glow mask's flats), so those come out exactly as before.
- **thin line** (2x, white): FloState's outline, energy-form shapes only, unchanged picture.
- **palette** (32 × 64): every slot's look, 4 rows each (plain, arms swapped, skin swapped, hands lit).
  A colour change is a palette change; the maps stay.

Still per look: halos, and the pieces cut from the body (hands, arms over hood, over-ball, blast arms,
back hand). Their readers sample them linearly (the glow mask's cut-outs, the chain hand's tone), so a
map can't stand in for them exactly yet.

## Verified
- `Tools/PlayerArtCheck/run.sh maps`: all 438 sheet frames × 15 looks (8,535 maps) made with no
  pixel left out; every look of a shape makes byte-identical maps (skin tone included, hence not in
  the key).
- `Tools/PlayerArtCheck/run.sh gpu 3`: each layer drawn through its map shader against the old picture
  as SpriteKit drew it, at scales 1–5, turned, flipped, at sub-pixel offsets, under four tints, and
  the glow mask's flat shaders over each: 144,878 renders, 0 pixels different.
- iOS and tvOS Debug builds succeed.

## Not verified
- On a device: nothing run yet. The TV's `[MEM]` line and `memoryBreakdown` (now listing `_map`,
  `_coverage`, `_thinline`) are the measure.
- Phantom (the figure flattened by its effect node) and the ball cam weren't drawn headlessly.

## Findings, unchanged on purpose
- The ball cam never carried the energy's ramp colours (`a_glow` etc.), so a player's energy shows
  black in it. Kept as it was.
