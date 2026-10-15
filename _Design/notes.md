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

## Polish (low priority)

- **No line under the feet:** the outline left off the row of pixels under the feet for bodies
  standing on the ground. Ground-only sheets (idle, walk, run, land, crouch) by a per-sheet list
  when the frame's recoloured; sheets used both standing and in the air (the layup, the slash)
  need a ground line and an air line, picked each frame by whether the body's grounded.

## Next round of revisions (low priority)

- **H.O.O.D lettering on the customize screen:** two tones of the side's energy colour, where
  now it's teal over the energy colour for every side. The current bottom (the energy colour)
  becomes the top, and a darker tone of it the bottom.
- **Customize tick blips too small:** they're 0.4 of ring 8 across (`CustomizeScreen.tickBlipShare`);
  the Rounds lights in the same ring are right at 0.5 (`GameScene.roundLightShare`, of the radius,
  so half the ring across). Match them.
