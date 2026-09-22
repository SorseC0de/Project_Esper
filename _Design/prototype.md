# Project Esper prototype

SpriteKit rebuild of the GMS2 basketball platformer. Nidhogg/Rounds family: footsies and
neutral to get a shot off; catch it and the roles reverse.

## Layout

- `EsperSim/` — the whole game as one value, `Match`, advanced one frame at a time by
  `advance(inputs:)`. Pure Swift, no SpriteKit. `swift test` runs its tests on the Mac.
  This is the rollback boundary: nothing gameplay-relevant lives outside it. `Opponent`
  is the computer's player, beside the sim rather than in it: it reads the match and
  gives one frame of input like a pad, deterministic with its own random stream.
- `ProjectEsper/` — the app. `GameScene` steps the sim at 60 and draws the last state.
  `MetalGameView` is the Metal layer: `SKRenderer` draws the scene into a texture and
  `Glow.metal` composites it with the glow. `InputHub` merges touch and controllers.
  `TouchControls` is the on-screen pad.
- `Tools/import_sprites.py` — copies the GMS2 frames and slices the strips in
  `_Graphic Assets` (square frames stacked one under another; a strip overrides the GMS2
  sprite of the same name) into the atlas. Run after art changes. The ball's imageset
  lives at the catalog's root, outside the atlas, and the importer leaves it alone. The
  sheets' white is the ball only on a sheet that holds it (`Animation.holdsBall`, the
  importer's `BALL_SHEETS`), and there only where it's the biggest blob of white in the
  frame and at least 12 pixels; every other white pixel is energy, the skid's puffs, a
  release's streaks, the slide's speed lines. The importer and the sprite library apply
  the same rule. The effect sheets there (`esper_spark`, `esper_spark2`, `esper_spark3`,
  `lightning1` to `4`, `esper_charge`) are grayscale strips toned per player in the app;
  the charge is a 512-pixel soft render with the swirl in its middle 150, boxed down by 4
  on import. Palette PNGs are read too.

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
  with the ball faces the opponent whichever way it goes after its first 3 frames, in
  which the stick still turns the body, so it can back off or dribble between the legs
  while staring them down; only a dash turns the body after that. Without the ball the
  stick turns the body throughout. Down without the ball is the crouch, and with the
  stick across as well the crouch walk at 0.8, facing the stick.
- Slide (without ball): down at full run, or shoot while crouched. The dash burst the way
  the body faces, bleeding off 0.15 a frame over 20 frames, the leg out: a hitbox a tile
  past the body's front edge and 6 units high that knocks the ball out of a grounded
  holder's hands. It ends in a crouch if down is still held. A slide can catch a loose
  ball on the way, which is what it's for.
- Jump: tap. Held through the jumpsquat is a full hop, let go is a short hop. In the air
  a stick against the way you're going turns you at once, body and all, Silksong's rule. For 3 frames
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
- Shoot (without ball, in neutral or on defence): the Esper Slash, the swat. On the
  ground it carries the run or dash it came from, bleeding 0.15 a frame; in the air the
  body rises at least 1 a frame and gravity is cut to a fifth, so it hangs through the
  swing. 18 frames at 20 a second. The blade is a square round the body, 56 art pixels a
  side, live over frames 3 to 11. Touching the holder's body or ball with it knocks the
  ball out of their hands, and it spikes a loose ball down and away at about 45° below
  the horizontal, jittered up to 10° by the frame, at no less than 6. In the air it ends in the roll, the double
  jump's somersault over 18 frames at the same pace with normal gravity and air drift, so
  the whole thing is a commitment; on the ground it's over when the swing is. Not in
  neutral.
- Throw (without ball, in neutral or on defence): the snatch. 40 frames, the hand out over
  frames 4 to 15, when the whole body plus a tile of reach in front takes any ball it
  overlaps while the body faces it: a loose one at any speed, or the one in the other's
  hands. The catch spark shows on the hand on frame 8. Then half a second before another.
  On the ground it carries the run or dash it came from, bleeding 0.15 a frame; in the
  air it drifts. Web Water keeps the web line on this button instead.
- Ledge (without ball): automatic. Falling past the top corner of a block or the one-way
  ledge, either side, with the corner within a tile of the body's side and within a tile
  either way of hand height, 17.5 above the feet, the hand catches it: the body turns to
  face it and hangs 10 frames, then climbs over 15 in three steps with the sheet, hanging,
  astride the corner, standing a unit in from the edge. No way off it but up. For 20
  frames after walking off an edge no corner is grabbed, so leaving a ledge doesn't grab
  it back. Never a made platform.
- Knocked loose (by a slide or a slash), the ball pops straight up: the floater's drift
  for 10 frames, then a normal fall, nobody's, so Flash Fizz can't warp to it. The holder
  can't catch it back for 15 frames.
- Throw: hold for the stance, stick picks a cardinal, release throws straight with no
  gravity until the first bounce. Up is the floater: a soft drift up at 1.5 with gravity
  off for 30 frames, carrying a fifth of the sideways speed the thrower had when the stance
  began, then a normal fall. The rims don't pull a thrown ball, so scoring off a throw
  is the ball going through on its own. In the air the throw stance keeps its run,
  bleeding only 0.03 a frame, so a jump carries it to the rim. In the stance with the
  chest within 25 units of a rim, wider than the basket, it's a dunk: the feet snap to
  the dunk's place on the rim, `BallRules.dunkOffset` from its centre, mirrored across
  for the other rim, facing the backboard; the ball goes in at once, and the dunker
  hangs there 45 frames before the point restarts. `DunkTuning` in `Tuning.swift`, when
  on, holds the match with player 1 in that hang at the right rim and puts DUNK X and
  DUNK Y sliders up, in art pixels, to find the place; it found 16 back and 24 down.
  A tap, or letting go before the 12-frame windup ends, throws when the windup ends where
  the stick pointed. The dunk shows the ledge sheet's first two frames until it has art.
- Wall: hold toward a wall in the air to cling and slide, for as long as it's held. Jump
  leaves it, direction automatic, the double jump restored, and the stick doesn't steer
  for 6 frames so the arc clears the wall. A jump press with a wall within 2 units of either side
  is a wall jump with no cling at all, and for 6 frames after letting go of a wall a press
  still jumps off it. A cling can't start for 8 frames after leaving the ground, and the
  walls above the court's top row can't be clung to or jumped off.
- Catch is automatic, in two rings: the ball within 12.5 of the chest and either in front,
  or in the way of where the body is moving; or within the catch spark's ring where the
  snatch puts it, on the hand at full stretch: 16 art pixels, the spark's full size,
  round a point 18 ahead of and 19 above the feet, whichever way the body moves. A
  ball arriving from behind while standing still bounces off, and so does one faster
  than 5 a frame (a throw is 7) unless the body is reaching with a snatch, and for 10
  frames after bouncing off a body the rings don't take it, so it isn't caught on the
  rebound. A shot in
  flight, before its first bounce, is different: it goes straight through a body,
  neither caught nor deflected, unless that body is reaching with a snatch; after its
  first bounce it's a loose ball again. The snatch is the catch: there is no catch
  stance.
- Hit by the blade, a body can't press anything for 15 frames, though the stick still
  moves it, and its sprite flickers white.
- Rims steer: a ball falling within reach has its sideways speed blended toward what
  would carry it through the rim, a share a frame, never snapped. Only a shot's or a
  floater's ball, and only until its first bounce off anything; a throw's never. Down
  through a rim scores unless the ball rose up through that rim first.

Pad: A jump, B, R1 or R2 shoot, X throw, Y taunt, right stick aims a stance. L1 steps the top
tuning picker, menu resets.

The touch buttons say what they'd do right now: SHOOT, SLASH, CATCH, SLIDE, FLASH or
WALL; THROW, SNATCH or WEB; JUMP, FLY or SWING.

A match, and every point, starts with a three count in which nobody moves or acts. A
point puts both back at their spawns as they began, the ball in the hands of whoever
didn't score, and counts again.

## Powers

Each power takes over parts of the controls, and less of it is available with the ball
in hand: that's where tricking lives, throwing the ball away to use the power while it's
in the air, catching it, carrying on. On the POWER picker, A is none.

- Web Water (B). Double jump is the web swing: air movement halts, a web goes to a point
  45 units ahead and 130 up, wherever the body is, so the swing is the same at any
  height, and the body swings under it on a pendulum arc to the
  mirrored angle, so it dips, then lets go higher than it stopped. That least arc always
  happens; holding jump keeps swinging, up to 1.6 times the arc and never over the anchor.
  The exit keeps the arc's direction but is
  capped to air speed across and a full hop up, so the stick can turn it. The swing is on
  a cooldown of a full swing's frames, 28, from the moment one ends, however it ends,
  cleared on landing; it neither spends nor needs the double jump, so a swing let go early
  doesn't lock the next one out until landing, and no swing chains straight into another.
  It works with the ball. The wall cling never slides. The throw button without the ball
  is the web line, from the ground, the air or a wall: held, it aims along the stick with a
  faint line; let go, it fires, 120 units. It bends to a loose ball or the opponent within
  15° of the aim, and the first thing within 8 units of its tip wins. A miss shows for 8
  frames and is live the whole time: the ball or the opponent crossing it in those frames
  is taken as if it had just been fired. A loose ball is reeled in and caught whatever its speed or facing. The opponent
  holding the ball loses it to the reel. The opponent without it is reeled to 12 units in
  front of the shooter and dropped. A wall or block reels the shooter to it. With the ball
  the throw button is the ordinary throw. Numbers in `WebRules`.
- Super Soda (C). A fresh jump press in the air, held, is flight: the stick moves the body
  in any direction with gravity off, slowly with the ball and twice as fast without, for two seconds of budget per airtime, refilled on landing.
  Let go or run out and it falls. The body leans up to thirty degrees into its motion,
  forward or back, and held still it hovers round a three-pixel circle. No double jump. With or without the ball, and flight
  cancels into a shot or a throw with the ball and a slash or a snatch without. Numbers in `SodaRules`.
- Flash Fizz (D). Without the ball, in neutral or on defence, a shoot button is the
  flash: 30 units along the stick, or in place with the stick centred, in addition to the
  double jump, arriving nudged clear of anything solid. The flashes are tears in space,
  and the exit tear lingers 12 frames and pulls any loose ball within 12 units into the
  hands, the ball going through space the way the body did: throw, flash after it, and
  it's yours again; or flash in place to take one that's near. There's no slash. With the
  ball, a dribble hanging past a ledge by more than a tile counts as not having it, so
  shoot warps the body down to it, keeping it, standing still on the block. One second
  between flashes. A bright wide diamond blinks where it left, quick, and where it came
  out, hanging on for the tear's frames. Numbers in `FizzRules`; the dribble's ball
  position per frame comes from `BallLandmarks.swift`, which the importer generates from
  the sheets.
- Platform Protein Shake (E). A fast fall makes a slab under the feet, three tiles wide
  and a tile thick, that stands for a second: solid to everyone, so it blocks the ball and
  the opponent, and a floor to land on, jumps refreshed. With or without the ball.
  Without the ball, in neutral or on defence, a shoot button makes a wall instead, a
  tile thick and three tall just in front of the feet, on the snatch's reach, appearing
  at the hand's full stretch; there's no slash. Slab or wall, the next can come only 75
  frames after the last, and only after a jump, a double jump, a wall jump or a wall land
  since it: holding down through a fall makes one, not a stream, and jump, slab, jump,
  slab still works. The stage carries standing slabs as `extras`, which every collision
  query sees. Numbers in `ShakeRules`.

## Tuning pickers

Segmented pickers in the top-left corner change a stat live on both players. `Tuning.swift`
holds the variants; A is always the baseline as tuned.

- HEAD: how the detached head follows the body. Both close half the gap each frame. B,
  the default, leads sideways instead of trailing, the offset reversed across only.
- POWER: A none, B Web Water, C Super Soda, D Flash Fizz, E Platform Protein Shake. The
  left bumper steps this one.
- HITBOX, beside RESET: draws the sim's boxes over the world. Bodies white, the loose
  ball purple, the two catch rings faint, the slide's leg and the slash's blade red, the
  snatch's reach green, a flash's tear cyan.
- AI, beside that: the computer plays the other side. Off, the second pad or nothing does.

## Opponent

`Opponent.swift`. Powerless for now: it runs, walks, jumps, slides, slashes, snatches,
throws and catches. It reads which of the three states the match is in and plays each
differently, and it holds its jumps through the squat so its hops are full.

- With the ball it works toward one of three shot spots, picked afresh each possession:
  two on the floor in front of its rim, 45 and 70 out, and the end of the ledge nearest
  the rim, which it climbs with a full hop and the double jump. At a floor spot it
  shoots standing or, half the time, off a jump: the stance, a hop after the windup, let
  go on the rise with the flick solved for the lift; the flick is the one that lands
  nearest the rim, tried in five-degree steps. When the other is within 50 and in the
  way and hasn't committed it picks, by chance, to stand, to walk back and forth
  dribbling with the odd hop, to pump fake, to lob the ball straight up and run under
  it, or to go over them on two jumps; after three such waits it stops waiting and goes
  over, lobs, or switches spot. While the other's swing or reach is live it steps back
  out of reach and waits; the moment it's spent, the recovery of a slash or a snatch,
  the roll, a landing, a catch, it darts past, a dash with a full hop and the double
  jump over them if they're in the way. Crowded within 16 it darts or backs off. Behind
  the block it climbs out: to the wall, a hop, the wall jump, the double jump inward.
- Without the ball and the other holding it, it guards the rim they score on: it walks
  to a spot 25 in front of that rim on their side and stands facing them. It strikes,
  a dash in and the swing when the blade will reach, a hop first if they're above, when
  they wind up a shot within reach, when they're spent within 45, or by chance when
  they stand about within 45; up close the swing is sometimes the snatch. After a swing
  it rests 40 frames. When they stand still for a second far from the rim it walks up
  to them and strikes.
- With the ball loose it goes to where the ball will come down, running if it's far,
  slides for it when it's a race, times a snatch or a slash for one in flight, leaves its
  own shot alone while it's on its way and waits under the rim for the miss, and goes up
  for one over its head, both jumps if it's high.

## Look

`Art/PlayerPalette.swift` names the figure's eleven parts and the flat colour each is
painted on the sheets, plus the Esper Slash's blade in pinks and the energy, the sheets'
white that isn't the ball. A `Look` maps parts to colours and the sprite library
recolours each frame once as it's used. The blade and the energy are split out of every
frame like the head and drawn on their own sprite over the body, among the glowers, so
they bloom at the world threshold, toned by their own brightness through the look's
ramp: black up to the team colour over the dark half, the colour up to a quarter of the
way to white over the light half, so mid grey is the colour itself and white a light tint
that still reads as it. The grayscale effect sheets go through the same ramp in a player's colour. A ball
knocked loose or swatted throws one of two sparks, either each time, centred on the ball
in the hitter's colour. A score brings lightning down on the rim in the scorer's colour,
one of four bolts each time, favouring vertical: it leans half as far as the ball came
in off vertical and never past 45°, so it never lies flat, at the sheet's own width and
stretched tall enough to run past the top of the screen at that lean. On the sheet's two
full-frame flash frames the whole screen flashes in the same tone and the floor and
walls go white, fading back over 20 frames, and the crown erupts off the rim with it. Sparks and bolts play at 24 a second. The jump spark and the dash's smoke, near-white on
their sheets, go through the ramp too, in the player's colour. A held throw shows the
charge, the swirl round the ball in hand at 30 a second and half its sheet's size: up to frame 67, then frames 35 to 67 round again for as long as the throw is held,
and when the throw is let go the frames after 67 play out where the ball was. Each player has a look with a team colour: orange for player 1, teal for player 2. The head
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
is an SF Symbol chevron doing what the pixel one did: three steps down, then off. A slide
leaves the dash's smoke; the snatch's catch spark sits on the hand at full stretch; a ball
knocked loose bursts like a wall jump's spark, away from the hitter.

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
