# EDG64 conversion

Progress of the whole game's move from AAP-64 to EDG64. The tables (energy tones, skins, the
reference player) are in `notes.md`. ✅ done, ⏳ to do.

## Palette code
- ✅ `PixelPalette.colours` is EDG64, in Aseprite's order; AAP-64 kept as `PixelPalette.aap64` for what isn't converted yet
- ✅ `PixelPalette.fire`: 35, 33, 31, 43, 42
- ⏳ `EsperPalette`: still has about 30 users (Onomatopoeia, customize grounds and hood line, UIColourPicks, title swatches, the gold lit colour); to circle back to
- ⏳ Every remaining `PixelPalette.aap64` use, stage by stage, as each is repainted

## Players
- ✅ Body-part keys on the sheets (`BodyPart.sourceColours`)
- ✅ Outline #1A1932
- ✅ Bodysuit #3D3D3D / #272727
- ✅ Skins: the first five, the second the default
- ⏳ Skins: Silver, Gold, Onyx (locked; to be unlocked or bought)
- ✅ Energy colours: three tones each from `Energy_Palette.png`
- ✅ Emerald on the wheel; teal is now Larimar's light blue
- ✅ The blade, drink and drink choice sheets
- ⏳ `player_hoodheads_v2`: still painted in AAP-64 skin and greys (swapped in code)
- ⏳ The ice look (frozen bodies, Frost Tea clones): still AAP-64 57 / 49 / 22

## Ball
- ✅ Basketball and the ice ball (`_e64` versions)
- ✅ Blazing Boba's fireball, on the fire ramp

## Effects (`_Graphic Assets/Pixel Art/Effects_e64`, imported over the originals)
- ✅ beam, bubble_particle, bubbles, burst, charge, dust_run, dust_walk, esper_charge
- ✅ The fire set: fire_charge, fire_charge2, fire_dash, fire_jump, fire_particle, fire_skid,
  fire_spark, fire_spark2, fire_spark3, fire_trail, fire_wallspark, fireball_summon
- ⏳ fire_explosion: its smoke and ash colours go past the fire ramp
- ⏳ dust_dash, dust_run2, dust_run3, dust_skid
- ⏳ esper_particle, esper_spark, esper_spark2, esper_spark3
- ⏳ explosion, explosion_v2
- ⏳ flashspark, flashspark2, flashspark3, shine, slashclash, score_strike, shield, flo_absorb
- ⏳ gemini_rift_v1, gemini_rift_v2
- ⏳ ice_jumpspark, jumpspark
- ⏳ The lightning set: lightning1 to 4, lightning_charge, lightning_jump, lightning_particle,
  lightning_particle2, lightning_spark, lightning_spark2

## Stages
- ✅ The Wreck Center (map, possession pixels, its animated pieces)
- ✅ Hoop, Hoop_straight, Backboard, Backboard_straight, Hoop_support (and the dark and half-length supports made from it)
- ✅ Flight B411's hoopcase
- ⏳ Hoopfish Hideaway's own backboards and hoops
- ⏳ The Elements (with its lava, tornados, fireballs and icicles)
- ⏳ Hoopfish Hideaway
- ✅ K&A (map, clouds, broken car, red car; its edge and wash #1A1932, its cones #FFA214)
- ✅ Flight B411 (hoopcase, cloud, cart; its other sprites kept as they are, by choice)
- ⏳ Longball Stadium
- ⏳ Slamstill Traffic

## Interface
- ⏳ The UI art and the colours drawn in code (`EsperPalette`, Onomatopoeia, Zones' colours)
