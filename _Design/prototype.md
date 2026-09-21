# Project Esper prototype

SpriteKit rebuild of the GMS2 basketball platformer. Nidhogg/Rounds family: footsies and
neutral to get a shot off; catch it and the roles reverse.

## Layout

- `EsperSim/` — the whole game as one value, `Match`, advanced one frame at a time by
  `advance(inputs:)`. Pure Swift, no SpriteKit. `swift test` runs its tests on the Mac.
  This is the rollback boundary: nothing gameplay-relevant lives outside it.
- `ProjectEsper/` — the app. `GameScene` steps the sim at 60 and draws the last state.
  `InputHub` merges touch and controllers. `TouchControls` is the on-screen pad.
- `Tools/import_sprites.py` — copies the GMS2 frames into the atlas. Run after art changes.

## Units

Melee units. 1 unit = 1.6 game pixels, so a 16px tile is 10 units and the 24px body is 15
units tall, which is Melee Mario's height. The court is 30 by 14 tiles, not quite two Final Destinations wide, and the camera fits
all of it at a whole number of screen pixels per game pixel: 5 on an iPhone.


## Movement

`FighterSpec.baseline` is Melee Fox with Falcon's run speed and the air turned up: air
speed 1.0, air acceleration 0.02 + 0.12, a jump with the stick held starts at air speed,
and a double jump with the stick held sets the sideways speed, so it turns around. Mario,
Falcon, Fox and Sheik from the SSBWiki table are kept beside it. Walk acceleration, dash length, pivot, and the wall numbers aren't on the table
and are chosen to sit with the rest.

## Input grammar

Tap is instant, hold is a stance, flick or release resolves it. Same on touch and pad.

- Stick: floating on the left half. A fast push past 0.8 is a dash; a tilt walks. Walking
  keeps the body facing where it was, so it can back up or dribble between the legs while
  staring the other way. Only a dash turns it.
- Jump: tap. Held through the 4-frame squat is a full hop, let go is a short hop.
- Shoot (with ball): hold for the stance, flick for the angle, release to fire. A tap, or
  letting go before the 20-frame windup ends, is the quickshot: it fires on the preset 53°
  arc when the windup ends. Holding past the windup and releasing without a flick is the
  pump fake. On the ground, jump during the stance is a jump shot.
- Shoot (without ball, in the air): swat. Reverses the ball if it's in front.
- Throw: hold for the stance, stick picks a cardinal, release throws straight with no
  gravity until the first bounce. The rims don't pull a thrown ball, so scoring off a throw
  is the ball going through on its own. In the stance within 12 units of a rim it's a dunk.
- Wall: hold toward a wall in the air to cling, jump to leave. Direction is automatic.
- Catch is automatic: facing the ball within reach.

Pad: A jump, B or R1 shoot, X throw, Y taunt, right stick aims a stance. L1 steps the top
tuning picker, menu resets.

## Tuning pickers

Segmented pickers in the top-left corner change a stat live on both players. `Tuning.swift`
holds the variants; A is always the baseline as tuned.

- AIR: A baseline. B faster and snappier. C near-instant turn, letting go stops the drift.
  D momentum, Fox's own acceleration with a long carry. E direct, the stick is the air speed.

## Queued

- Metal layer: SKRenderer into an offscreen texture, bloom pass to match GameMaker's Glow
  filter (threshold, radius, intensity, colour).
- Rollback netcode over GameKit, then an AI for solo play.
- Power-ups, including throw-button overrides.
