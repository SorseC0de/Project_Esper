# Notes for later

## Names kept for later

- **Hoopfish Hideaway**: the underwater stage's first name, before it became Hoopfish Hideaway.
- **Hoopfish Harbor**: another name for an underwater stage.

## Palette: AAP-64 to EDG64 (low priority, ahead of polish)

The whole game's pixel palette moves again, from AAP-64 to EDG64: more vibrant, a better
choice of several colours, and above all the blues AAP-64 lacks.

- **Characters:** a straight swap Claude can make, the sheets and `PixelPalette` both.
- **Maps:** by eye, by hand. EDG64 hasn't AAP-64's muted browns, so they don't swap cleanly.
- **Teal:** EDG64 has none; teal becomes light blue wherever it's used.

### Energy colours (the user's, tested on a no-glow player)

Three tones each, all from EDG64: the **base** (the energy colour itself), the **hood's shadow**
(the hood's darker pixels), and the **back limbs' accessories** (sleeves and boots on the back
arm and leg). Three tones stay on purpose; today the last two come from two different
calculations (`energyTone` for the hood, `Look.scaled(glow, backLegShare)` for the limbs), and
the migration sets them to these exactly.

| Colour | Base | Hood shadow | Back limbs |
|---|---|---|---|
| Red | #EA323C | #C42430 | #891E2B |
| Orange | #FF5000 | #C64524 | #8E251D |
| Gold | #FFC825 | #FFA214 | #E07438 |
| Lime | #99E65F | #5AC54F | #33984B |
| Green, Emerald (new) | #33984B | #1E6F50 | #134C4C |
| Light blue, Larimar (was teal) | #0CF1FF | #00CDF9 | #0098DC |
| Blue | #0098DC | #0069AA | #00396D |
| Pink | #F389F5 | #CA52C9 | #93388F |
| Purple | #93388F | #622461 | #3B1443 |

### A converted player (the user's reference: default skin, Sapphire)

| Role | Colour | Pixels |
|---|---|---|
| Outline | #1A1932 | 148 |
| Energy base (Sapphire) | #0098DC | 74 |
| Energy, hood's shadow | #0069AA | 16 |
| Energy, back limbs | #00396D | 16 |
| Skin, front (the new default) | #E69C69 | 42 |
| Skin, back | #BF6F4A | 32 |
| Bodysuit, front | #3D3D3D | 60 |
| Bodysuit, back | #272727 | 20 |

### Skin tones (the user's, EDG64)

Eight, each a front and a back tone, the back the next skin's front down the ramp. The second is
the default. The last three are unlocked or bought, not open from the start: there's no
unlocking yet, so the customize screen will need a locked state for them.

| # | Skin | Front | Back |
|---|---|---|---|
| 1 | | #F6CA9F | #E69C69 |
| 2 | Default | #E69C69 | #BF6F4A |
| 3 | | #BF6F4A | #8A4836 |
| 4 | | #8A4836 | #5D2C28 |
| 5 | | #5D2C28 | #391F21 |
| 6 | Silver (locked) | #B4B4B4 | #858585 |
| 7 | Gold (locked) | #EDAB50 | #E07438 |
| 8 | Onyx (locked) | #657392 | #424C6E |

Today there are seven (`HumanLook.skinTones`, the hooded heads' six and the robot's); the hooded
heads' sheet (`player_hoodheads`) has a frame a skin, so it needs the new eight, or the faces
recoloured to these from one.

Green is a ninth hood colour, Emerald (`EnergyColour.name`): it needs a place in the wheel and
on the customize picker. Light blue takes teal's place; its name, Larimar, is in already.

## Polish (low priority)

- **No line under the feet:** the outline left off the row of pixels under the feet for bodies
  standing on the ground. Ground-only sheets (idle, walk, run, land, crouch) by a per-sheet list
  when the frame's recoloured; sheets used both standing and in the air (the layup, the slash)
  need a ground line and an air line, picked each frame by whether the body's grounded.
