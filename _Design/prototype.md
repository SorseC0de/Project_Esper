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

`FighterSpec.baseline` is Melee Fox with a Falco-style dash, the burst always 0.4 over the
3.2 run,
traction 0.35, a shoot stance that brakes sideways drift at 0.15 a frame in the air, and
the air turned up: air speed 1.6, air acceleration 0.02 + 0.24, a jump with the stick held
starts at air speed, and a double jump with the stick held sets the sideways speed, so it
turns around. Mario, Falcon, Fox and Sheik from the SSBWiki table are kept beside it. Walk acceleration, dash length, pivot, and the wall numbers aren't on the table
and are chosen to sit with the rest.

## Input grammar

Tap is instant, hold is a stance, flick or release resolves it. Same on touch and pad.

- Stick: floating on the left half. A fast push past 0.8 is a dash; a tilt walks. A walk
  always faces the opponent whichever way it goes, so it can back off or dribble between
  the legs while staring them down. Only a dash turns the body.
- Jump: tap. Held through the jumpsquat is a full hop, let go is a short hop. For 3 frames
  after walking off an edge a press is still that jump. Down while falling is a fast fall,
  except while holding throw with the ball, where down is the aim.
- Shoot (with ball): hold for the stance, flick for the angle, release to fire. A tap,
  let go within 6 frames, is the quickshot: it fires on the preset 53° arc when the
  20-frame windup ends. Let go after that but before the windup ends and it's a cancel.
  Holding past the windup and releasing without a flick is the pump fake, and so is a second shoot button or the throw button pressed during the
  stance; after a cancel the buttons involved have to come up before another stance.
  Shoot pressed during a throw stance cancels the throw the same way. On the ground, jump during the stance
  is a jump shot: released on the way up
  it fires on the preset arc if nothing was flicked and the ball leaves with the body's
  lift. On the way down it's an ordinary air shot.
- Shoot (without ball, in the air): swat. Reverses the ball if it's in front.
- Throw: hold for the stance, stick picks a cardinal, release throws straight with no
  gravity until the first bounce. Up is the floater: a soft drift up at 1.5 with gravity
  off for 30 frames, carrying a fifth of the sideways speed the thrower had when the stance
  began, then a normal fall. The rims don't pull a thrown ball, so scoring off a throw
  is the ball going through on its own. In the stance within 12 units of a rim it's a dunk.
  A tap, or letting go before the 12-frame windup ends, throws when the windup ends where
  the stick pointed.
- Wall: hold toward a wall in the air to cling and slide, for as long as it's held. Jump
  leaves it, direction automatic, the double jump restored, and the stick doesn't steer
  for 6 frames so the arc clears the wall. A jump press with a wall within 2 units of either side
  is a wall jump with no cling at all, and for 6 frames after letting go of a wall a press
  still jumps off it. A cling can't start for 8 frames after leaving the ground, and the
  walls above the court's top row can't be clung to or jumped off.
- Catch is automatic: the ball within reach and either in front, or in the way of where
  the body is moving. A ball arriving from behind while standing still bounces off, and so
  does one faster than 5 a frame (a throw is 7, a shot 4.5) unless the body is in the catch
  stance: a shoot button held with no ball.
- Rims steer: a ball falling within reach has its sideways speed blended toward what
  would carry it through the rim, a share a frame, never snapped.

Pad: A jump, B, R1 or R2 shoot, X throw, Y taunt, right stick aims a stance. L1 steps the top
tuning picker, menu resets.

## Powers

Each power takes over parts of the controls, and less of it is available with the ball
in hand: that's where tricking lives, throwing the ball away to use the power while it's
in the air, catching it, carrying on. On the POWER picker, A is none.

- Web Water (B). Double jump is the web swing: air movement halts, a web goes to the top
  of the court 45 units ahead, and the body swings under it on a pendulum arc to the
  mirrored angle, so it dips, then lets go higher than it stopped. That least arc always
  happens; holding jump keeps swinging, up to 1.6 times the arc and never over the anchor,
  and a full swing gives the double jump back. The exit keeps the arc's direction but is
  capped to air speed across and a full hop up, so the stick can turn it. It spends the double jump
  and works with the ball. The wall cling never slides. The throw button without the ball
  is the web line, from the ground, the air or a wall: held, it aims along the stick with a
  faint line; let go, it fires, 120 units. It bends to a loose ball or the opponent within
  15° of the aim, and the first thing within 8 units of its tip wins. A loose ball is reeled in and caught whatever its speed or facing. The opponent
  holding the ball loses it to the reel. The opponent without it is reeled to 12 units in
  front of the shooter and dropped. A wall or block reels the shooter to it. With the ball
  the throw button is the ordinary throw. Numbers in `WebRules`.
- Super Soda (C). A fresh jump press in the air, held, is flight: the stick moves the body
  in any direction with gravity off, slowly with the ball and twice as fast without, for two seconds of budget per airtime, refilled on landing.
  Let go or run out and it falls. No double jump. With or without the ball, and a shot or
  throw can be taken from flight. Numbers in `SodaRules`.
- Flash Fizz (D). A shoot button with no ball warps the body to the ball and it arrives
  holding it, but only while the ball is still its colour, the 60 frames after it let the
  ball go: throw, warp, catch. One second between warps. A bright wide diamond blinks at
  where it left and where it landed. Otherwise shoot does what it does without the ball.
  Numbers in `FizzRules`.

## Tuning pickers

Segmented pickers in the top-left corner change a stat live on both players. `Tuning.swift`
holds the variants; A is always the baseline as tuned.

- HEAD: how the detached head follows the body. Both close half the gap each frame. B,
  the default, leads sideways instead of trailing, the offset reversed across only.
- POWER: A none, B Web Water, C Super Soda, D Flash Fizz. The left bumper steps this one.

## Look

`Art/PlayerPalette.swift` names the figure's eleven parts and the flat colour each is
painted on the sheets. A `Look` maps parts to colours and the sprite library recolours
each frame once as it's used. Each player has a look with a team colour: orange for player 1, teal for player 2. The head
and the ball in hand are drawn in it, the ball's outline is in it, and so are the halo on
the ball and the fire off the head. The body a light orange or a light teal toward the team colour, the back limbs a greyed,
darker version of it, a black line one pixel thick round the body following the outside
edge only, and the front arm stroked on its own where it lies over the body. The head is
split out of every frame and drawn as its own sprite with no line, trailing its place on
the body by a quarter of the gap each frame and bobbing a pixel, and its fire is released
into the world so it streams behind a moving head. The loose ball is purple, and for 60 frames after a shot, throw or dunk it's the colour
of whoever let it go, then shifts back over 30. A flying ball leaves a soft additive trail
in its colour. The library finds where the ball and the head sit in each frame so the halo
and the fire follow them. The head is drawn at 1.25 times about its own centre and lifted a pixel off the body. Three dim
yellow chevrons stack over a resting ball and light one after another from the top. A
double jump leaves a short platform of loose digital squares under the feet where it was
taken; they hang a moment, then drop away and cut out. The head bits rise in a tight column that one swinging wind bends as a whole, a scarf.
The ball in hand is its own sprite on the frame's ball, and when that hangs off a ledge the
dribble reaches down to the real floor under it over the same frames. The feather-fan wing in `Wing.swift` is parked, not in the scene. The ball pointer
is an SF Symbol chevron doing what the pixel one did: three steps down, then off.

## Court

The tiles are flat colour, in dark shades: each colour at 0.45 of its brightness. The
floor and walls start purple and shift over 20 frames to the colour of whoever holds the
ball, and back. The backboard blocks wear the colour of the player who scores there's opponent, since you
score on the other side's basket. The ledge is
magenta. Three small faint green chevrons stack over the rim
the holder scores on. The head particles are hard squares that step down in size, a
digital dissolve rather than a flame.

## Glow

`GlowSettings` in `Tuning.swift`: luminance threshold 0.2 for the world and 0.8 for the
bodies, softness of the cut, blur passes at half size, intensity, tint. The passes are in
`Glow.metal`. A second renderer draws a mirror scene holding only the two body sprites
on black (`MaskScene`), and that mask tells the bright pass which threshold applies. The
game scene is never drawn twice in a frame: SpriteKit reuses its per-frame buffers
between two renders, which drew the bodies as white squares. The world threshold
is on a slider across the top of the screen. The corner counter shows the frame rate and
the worst frame gap of the last second, which is what a hitch shows up as.

## Queued

- Rollback netcode over GameKit, then an AI for solo play.
- Power-ups, including throw-button overrides.
