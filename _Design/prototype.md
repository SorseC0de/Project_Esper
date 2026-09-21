# Project Esper prototype

SpriteKit rebuild of the GMS2 basketball platformer. Nidhogg/Rounds family: footsies and
neutral to get a shot off; catch it and the roles reverse.

## Layout

- `EsperSim/` — the whole game as one value, `Match`, advanced one frame at a time by
  `advance(inputs:)`. Pure Swift, no SpriteKit. `swift test` runs its tests on the Mac.
  This is the rollback boundary: nothing gameplay-relevant lives outside it.
- `ProjectEsper/` — the app. `GameScene` steps the sim at 60 and draws the last state.
  `MetalGameView` is the Metal layer: `SKRenderer` draws the scene into a texture and
  `Glow.metal` composites it with the glow. `InputHub` merges touch and controllers.
  `TouchControls` is the on-screen pad.
- `Tools/import_sprites.py` — copies the GMS2 frames into the atlas. Run after art changes.

## Units

Melee units. 1 unit = 1.6 game pixels, so a 16px tile is 10 units and the 24px body is 15
units tall, which is Melee Mario's height. The court is 30 by 14 tiles, not quite two Final Destinations wide, and the camera fits
all of it at a whole number of screen pixels per game pixel: 5 on an iPhone.


## Movement

`FighterSpec.baseline` is Melee Fox with a Falco-style dash, a 2.8 burst into a 2.5 run,
traction 0.15, a shoot stance that brakes sideways drift at 0.15 a frame in the air, and
the air turned up: air speed 1.6, air acceleration 0.02 + 0.24, a jump with the stick held
starts at air speed, and a double jump with the stick held sets the sideways speed, so it
turns around. Mario, Falcon, Fox and Sheik from the SSBWiki table are kept beside it. Walk acceleration, dash length, pivot, and the wall numbers aren't on the table
and are chosen to sit with the rest.

## Input grammar

Tap is instant, hold is a stance, flick or release resolves it. Same on touch and pad.

- Stick: floating on the left half. A fast push past 0.8 is a dash; a tilt walks. A walk
  always faces the opponent whichever way it goes, so it can back off or dribble between
  the legs while staring them down. Only a dash turns the body.
- Jump: tap. Held through the jumpsquat is a full hop, let go is a short hop. Down while
  falling is a fast fall, except while holding throw with the ball, where down is the aim.
- Shoot (with ball): hold for the stance, flick for the angle, release to fire. A tap, or
  letting go before the 20-frame windup ends, is the quickshot: it fires on the preset 53°
  arc when the windup ends. Holding past the windup and releasing without a flick is the
  pump fake. On the ground, jump during the stance is a jump shot: released on the way up
  it fires on the preset arc if nothing was flicked and the ball leaves with the body's
  lift. On the way down it's an ordinary air shot.
- Shoot (without ball, in the air): swat. Reverses the ball if it's in front.
- Throw: hold for the stance, stick picks a cardinal, release throws straight with no
  gravity until the first bounce. The rims don't pull a thrown ball, so scoring off a throw
  is the ball going through on its own. In the stance within 12 units of a rim it's a dunk.
- Wall: hold toward a wall in the air to cling, jump to leave. Direction is automatic. A
  cling can't start for 8 frames after leaving the ground, so a jump beside a wall isn't
  caught by it on the way up.
- Catch is automatic: facing the ball within reach.

Pad: A jump, B or R1 shoot, X throw, Y taunt, right stick aims a stance. L1 steps the top
tuning picker, menu resets.

## Tuning pickers

Segmented pickers in the top-left corner change a stat live on both players. `Tuning.swift`
holds the variants; A is always the baseline as tuned.

- AIR: A baseline. B the stance brakes harder, 0.3 a frame. C direct, the stick is the air
  speed. D the stance barely brakes. E a 1.8 cap.

## Glow

`GlowSettings` in `Tuning.swift`: luminance threshold, softness of the cut, blur passes at
half size, intensity, tint. The passes are in `Glow.metal`.

## Queued

- Rollback netcode over GameKit, then an AI for solo play.
- Power-ups, including throw-button overrides.
