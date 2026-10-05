# Skin tones

The six two-tone skins of `player_hoodheads` (one per frame of the strip, top to bottom),
sampled from the art. The darker tone is the upper face (rows 16 to 20 of the 48-pixel
canvas) and the lighter the lower (rows 19 to 21). The same two colours will be each skin's
arms: the darker the back arm, the lighter the front, as frame 4 is today
(`HumanLook.skin`: back 34, front 35).

| Frame | Dark (back arm) | Light (front arm) |
|---|---|---|
| 1 | 35 #DBA463 | 36 #F4D29C |
| 2 | 47 #E9B5A3 | 24 #FAD6B8 |
| 3 | 46 #BA756A | 47 #E9B5A3 |
| 4 (the bodies' now) | 34 #BB7547 | 35 #DBA463 |
| 5 | 33 #71413B | 34 #BB7547 |
| 6 | 44 #5B3138 | 33 #71413B |

Indexes are the AAP-64 pixel palette's (`PixelPalette.colours`).

A seventh, the robot's, has no frame of its own: frame 4 drawn with its tones swapped, light 38
#B3B9D1 (front arm) and dark 39 #8B93AF (back arm).
