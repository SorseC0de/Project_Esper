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
  `Glow.metal` composites it with the glow. The HUD is a second scene, `HudScene`, shown
  by a transparent SpriteKit view (`HudView`) laid over the Metal view, so nothing in it
  glows; it takes the touches and hands them to the game scene. `InputHub` merges touch
  and controllers. `TouchControls` is the on-screen pad. Who drives whom: on a phone touch is player 0,
  a controller plays player 0 with them by default; only VS HUMAN makes a lone controller
  player 1, two controllers then players 0 and 1; on the TV and on a Mac, with no touch,
  the controllers are players 0 and 1. VS CPU, the default, has the computer on player 1
  whatever pads are in; VS HUMAN gives player 1 to the second pad. A keyboard on an iPad or a Mac is player 0 as well: WASD, space to jump, J to shoot,
  K to throw, shift as the left bumper, delete as the start button, Esc quits on a Mac or in the simulator. The HUD is laid out in the phone's points and
  scaled up by `HudScene.scale(forHeight:)` on a bigger screen, the lettering rendered
  at that scale so it stays crisp. `Net/GameCenter` is Game
  Center: signing in, the matchmaker, and the bytes between the two phones. Two
  targets build the same sources and catalog: `ProjectEsper` for iPhone and iPad, and
  `ProjectEsperTV` for Apple TV, same bundle ID so the two play each other. On the TV
  there's no pad on screen, a controller is required, and its menu button is claimed as
  the pause so it doesn't send the app home; the few phone-only calls sit behind
  `#if os(iOS)`. The TV's icon is the empty `App Icon & Top Shelf Image` brand assets,
  waiting for art.
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

Defending, without the ball while the other has it, a body walks, runs, dashes and
drifts a tenth faster (`DefenceRules`). `FighterSpec.baseline` is Melee Fox with a Falco-style dash, 6 frames, half Fox's ground, a 5-frame pivot, the burst always 0.4 over the
3.2 run,
traction 0.35, a shoot stance that brakes sideways drift at 0.15 a frame in the air, and
the air in lockstep with the ground: air speed is the run's, and letting go of the stick
in the air brakes at the ground's traction; moves that don't steer (a wall jump's lockout,
the shot's release, the throw, the Pulsepistol shot, a stance's first frame) coast on
Fox's light air friction instead. Air acceleration 0.02 + 0.24; a jump with the stick held
starts at air speed, and a double jump with the stick held sets the sideways speed, so it
turns around. A walk speeds up gently to walking speed, but past it, or against the
stick, it brakes at traction, so one come into from a run doesn't slide on. Mario, Falcon, Fox and Sheik from the SSBWiki table are kept beside it. Walk acceleration, dash length, pivot, and the wall numbers aren't on the table
and are chosen to sit with the rest.

## Input grammar

Tap is instant, hold is a stance, flick or release resolves it. Same on touch and pad.

- Stick: floating on the left half. A fast push past 0.8 is a dash; a tilt walks. A walk
  with the ball faces the opponent whichever way it goes after its first 3 frames, in
  which the stick still turns the body, so it can back off or dribble between the legs
  while staring them down; only a dash turns the body after that. Without the ball the
  stick turns the body throughout. Down without the ball is the crouch, and with the
  stick across as well the crouch walk at 0.8, facing the stick.
- Crouched or sliding, the body is half as tall, and it stays down while there's no room
  to stand.
- Slide (without ball): down at full run, or shoot while crouched. The dash burst the way
  the body faces, carried for 20 frames bleeding only 0.02 a frame, the leg out: a hitbox
  a tile past the body's front edge and 6 units high that knocks the ball out of a
  grounded holder's hands. It ends in a crouch if down is still held, or stands up into
  the run's skid to stop. A slide can catch a loose ball on the way, which is what it's
  for. Numbers on the body (`slideFrames`, `slideFriction`) and in `SlideRules`.
- Jump: tap. Held through the jumpsquat is a full hop, let go is a short hop. Shoot or
  throw pressed with the jump or during the squat is Smash's rising aerial: out of the
  squat straight into the slash or the snatch on the jump's first frame, still rising. In the air
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
  body rises at least 0.5 a frame and gravity is cut to seven tenths, a little hang
  through the swing. The sheet's six frames at 15 a second, 24 sim frames, and the roll the same. The
  blade is a square round the body, 56 art pixels a side, its centre 4 art pixels in
  front of the body's, live over sheet frames 1 to 3 (`SlashRules.liveSheetFrames`). Touching the holder's body or ball with it knocks the
  ball out of their hands, and it spikes a loose ball down and away at about 45° below
  the horizontal, jittered up to 10° by the frame, at no less than 6. In the air it ends in the roll, the double
  jump's somersault over 18 frames at the same pace with normal gravity and air drift, so
  the whole thing is a commitment; on the ground it's over when the swing is. Not in
  neutral.
- Down lets go of any hang: the wall cling (unless a web line is being aimed), the ledge
  hang, which it drops off rather than climbing, and the rim after a dunk's slam; neither
  the wall nor the ledge can be taken again at once.
- Throw (without ball, in neutral or on defence): the snatch. The sheet's ten frames at
  15 a second, 40 sim frames, the hand out over sheet frames 2 and 3
  (`SnatchRules.activeSheetFrames`), the third sheet frame held twice as long, when the
  whole body plus a tile of reach in front, or the hand's catch ring at the spark's
  spot, takes any ball it touches while the body faces it: a loose one at any speed, or
  the one in the other's hands, where the sheet draws it that frame (down on the floor
  below when it's dribbled over a drop, `Player.ballInHand`), or the holder's
  body itself, whichever way the snatcher faces while their bodies overlap. The last two
  sheet frames are left off. The catch spark shows on the hand on sheet frame 2.
  On the ground it carries the run or dash it came from, bleeding 0.15 a frame; in the
  air it drifts. Web Water keeps the web line on this button instead.
- Ledge (without ball): automatic. Falling past the top corner of a block or the one-way
  ledge, either side, with the corner within a tile of the body's side and within a tile
  either way of hand height, 17.5 above the feet, the hand catches it: the body turns to
  face it and hangs 10 frames, then climbs over 15 in three steps with the sheet, hanging,
  astride the corner, standing a unit in from the edge. No way off it but up. For 20
  frames after walking off an edge no corner is grabbed, so leaving a ledge doesn't grab
  it back. Never a made platform.
- Knocked loose, the ball pops up: straight up off a slide, and off a slash back to the
  slasher, away from its holder, its sideways speed set so it comes down on the slasher
  where their swing's slide will have left them (`Player.slashSlide`, over
  `BallRules.popAloftFrames`): the floater's drift
  for 10 frames, then a normal fall, nobody's, so Flash Fizz can't warp to it. The holder
  can't catch it back for 15 frames.
- Throw: the `player_throw` sheet, `player_throw_air` off the ground, frames 4 to 7
  spread over the recovery. Hold for the stance, stick picks a cardinal, release throws straight with no
  gravity until the first bounce. Sideways or down it's a projectile: the other body it
  meets is stripped and knocked as by the slash, and it bounces back toward the thrower,
  theirs to catch at any speed, so a throw holds off a defender coming in; a snatch with
  the hand out takes it instead. The computer reads a throw charged more than six
  frames and snatches it every time; a quick throw gets by it seven times in ten. Off
  the other it flies straight back at the thrower's chest and is theirs, at any speed and
  facing either way, until it first hits something. A release never starts inside a
  wall: the hand is pushed out of one the body is pressed against. Up is the floater: a soft drift up at 1.5 with gravity
  off for 30 frames, carrying a fifth of the sideways speed the thrower had when the stance
  began, then a normal fall. The rims don't pull a thrown ball, so scoring off a throw
  is the ball going through on its own. In the air the throw stance keeps its run,
  bleeding only 0.03 a frame, so a jump carries it to the rim. In the stance with the
  chest within 25 units of a rim, wider than the basket, it's a dunk: the body turns to
  the backboard and glides to the dunk's place on the rim, `BallRules.dunkOffset` from
  its centre, 16 art pixels back and 24 down, mirrored across for the other rim, over the
  wind-up, there by the slam, so it never jumps into place. The dunk
  sheet plays from the throw stance's frame: the wind-up, the swing, the slam on the
  release frame, when the ball leaves the hand and drops through, then the hang, held
  through the 45 frames, each frame held twice as long as first cut (40 frames to the slam) before the point restarts. Each frame of it is drawn nudged by
  `DunkArt.offsets`, in art pixels, found with `DunkTuning` on: the match held, player 1
  on the right rim on the frame the DUNK FRAME slider picks, DUNK X and DUNK Y nudging
  that frame, the table in the corner readout. As placed: (-6, 10), (-4, 12), (-2, 16),
  (4, 2), (-3, 3), (-2, 2), (-2, 2).
  A tap, or letting go before the 12-frame windup ends, throws when the windup ends where
  the stick pointed. The dunk shows the ledge sheet's first two frames until it has art.
- Wall: hold toward a wall in the air to cling and slide, for as long as it's held. Jump
  leaves it, direction automatic, the double jump restored, and the stick doesn't steer
  for 12 frames so the arc clears the wall. A wall jump comes only out of the cling: no
  jump off a wall merely in reach, none after letting go. A cling can't start for 8
  frames after leaving the ground, and the walls above the court's top row can't be
  clung to or jumped off.
- Catch is automatic, in two rings: the ball within 12.5 of the chest and either in front,
  or in the way of where the body is moving; or within the catch spark's ring where the
  snatch puts it, on the hand at full stretch: 16 art pixels, the spark's full size,
  round a point 18 ahead of and 19 above the feet, whichever way the body moves. Bodies
  never deflect the ball: a ball arriving from behind while standing still goes straight
  through, and to the other so does one faster than 5 a frame (a throw is 7) or a shot in flight
  before its first bounce, unless the body is reaching with a snatch or swinging the
  blade. Whoever last had the ball can take back their own shot or throw at any speed,
  once the release's catch cooldown is up. The snatch is the catch: there is no catch stance.
- Knocked loose by the blade or the slide's leg, or robbed by a snatch, a body can't
  press anything or catch anything for 60 frames, longer than the pop's round trip,
  though the stick still moves it, and its sprite flickers white: the taker has first
  go at the ball.
- Rims steer: a ball falling within reach has its sideways speed blended toward what
  would carry it through the rim, a share a frame, never snapped. Only a shot's or a
  floater's ball, and only until its first bounce off anything; a throw's never. Down
  through a rim scores, whatever the ball did before: a floater that rose up through it
  from under counts once it falls back in. Going up through a rim never scores.

Out of a run or its pivot with the stick slammed the other way, the jump turns the new way
(Mario 64's) with the run's whole speed, as it stood before the pivot.

Pad: A jump, B, R1 or R2 shoot, X throw, Y taunt, right stick aims a stance. L1 steps the POWER
picker, start (menu) pauses, R3 switches the computer, L2 the hitboxes. Down on the stick
with the ball, standing or walking, is the sauce too: the taunt sheet for show, and any
action or the stick cancels it.

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
  is the web line, from the ground, the air or a wall: held, it aims along the stick with
  twelve dots out to its reach, like the shot's; let go, it fires, 120 units, a miss drawn
  going out to its tip over four frames and back over four. It bends to a loose ball or the opponent within
  15° of the aim, and the first thing within 8 units of its tip wins. A miss shows for 8
  frames and is live the whole time: the ball or the opponent crossing it in those frames
  is taken as if it had just been fired. A loose ball is reeled in and caught whatever its speed or facing. The opponent
  holding the ball loses it to the reel. The opponent without it is reeled to 12 units in
  front of the shooter and dropped. A wall or block reels the shooter to it. With the ball
  the throw button is the ordinary throw. Numbers in `WebRules`.
- Super Smoothie (C). A fresh jump press in the air, held, is flight: the stick moves the body
  in any direction with gravity off, slowly with the ball and twice as fast without, for two seconds of budget per airtime, refilled on landing.
  Let go or run out and it falls. The body leans up to thirty degrees into its motion,
  forward or back, and held still it hovers round a three-pixel circle. No double jump. With or without the ball, and flight
  cancels into a shot or a throw with the ball and a slash or a snatch without. Numbers in `LeviRules`.
- Flash Fizz (D). Without the ball, a shoot button warps the body to the ball while the
  ball is still its colour, until its first bounce, and it arrives holding it: throw,
  warp, catch. Otherwise shoot is the slash as ever. The flash is on jump in the air, in
  place of the double jump: five tiles along the stick, or in place, arriving nudged
  clear of anything solid, one a cooldown, two at level two. The flashes are tears in
  space at either level: the exit tear lingers 12 frames and pulls any loose ball
  within 15 units into the hands, and the other holding the ball with their body within
  15 units of either end loses it, popped. With the ball, a dribble hanging past a ledge
  by more than a tile counts as not having it, so shoot warps the body down to it,
  keeping it. One second between flashes. The flash sheet plays where the body left and
  the second flash sheet where it came out. Numbers in `FizzRules`; the dribble's ball
  position per frame comes from `BallLandmarks.swift`, which the importer generates from
  the sheets.
- Platform Protein Shake (E). A fast fall makes a slab under the feet, three tiles wide
  and a tile thick, that stands for a second: solid to everyone, so it blocks the ball and
  the opponent, and a floor to land on, jumps refreshed. With or without the ball.
  Without the ball, in neutral or on defence, a shoot button makes a wall instead, a
  tile thick and three tall just in front of the feet, on the snatch's reach, appearing
  at the hand's full stretch; there's no slash. A wall can come 75 frames after the last wall, on its
  own cooldown and with no arming. A slab can come only 75 frames after the last slab,
  and only after a jump, a double jump, a wall jump or a wall land since it: holding down through a fall makes one, not a stream, and jump, slab, jump,
  slab still works. The stage carries standing slabs as `extras`, which every collision
  query sees. Numbers in `ShakeRules`.
  Super Smoothie's flight is on a cape of energy, and at level two the stick forward
  is the glide: 3.5 forward (2.5 with the ball), sinking 0.8 a frame unless up is held,
  which rises at the flight speed, and diving at 3 on down; the stick backward is the
  drift at the flight speed, and centred it levitates. Level one is the plain flight.
  Numbers in `SmoothieRules`.
- Quake-Up Coffee (G). Its fast fall is 1.6 times anyone's, and the landing shakes the floor: the ball on it hops up
  3 and the other standing on the same floor, within a unit of the same height, is
  stripped; level two makes the whole screen the floor. Numbers in `QuakeRules`.
- Zeus Juice (H). Shoot without the ball throws a bolt straight ahead at 6, tilted by
  the stick up to 30°, for 60 frames, one every 24: a body it meets is stripped and
  knocked as the slash knocks; thrown on the ground it's committed as the slash is, the
  stick not walking and the run bleeding off at the slash's brake, and the ball it meets pops back toward the thrower. There's no slash.
  Level two's throw calls a strike down from the top of the screen, five units wide,
  from the top of the screen onto the ball in hand, where the stance's sheet draws it, as the charge starts or onto the
  snatch's hand at full stretch,
  stopping on the first thing it meets on the way down, a solid, the other body,
  stripped, or the loose ball, popped, once every 40 frames. The bolt throw plays the
  whole throw sheet, ground or air, with the sheet's ball drawn as energy, and the bolt
  leaves on its release frame, sixteen frames in, the way the body faces then.
  Numbers in `ZeusRules`.
- Frost Tea (I). The snatch freezes what it reaches, a body or the loose ball, for 60
  frames: held exactly where it is, nothing running, nothing caught, no hitbox live, though
  a frozen ball can still be picked up or snatched;
  a frozen body is stripped as well. The slide has no friction and no end, until jump,
  throw, shoot, the stick against it, or down let go cancel it. Level two: a double
  jump or a slide leaves an ice clone, the body's box, that freezes whatever touches it
  and shatters, or shatters after 60 frames. Numbers in `FrostRules`.
- Blazing Boba (J). It comes into a round in `explosion_v2`, painted, on the feet, in place of the
  port-in's cluster. A run at full speed or a slide leaves a flame every 4 frames, six
  wide and four tall at the feet, for 45 frames; the other body in one is stripped and
  the flame is spent. Shots and throws set the ball alight until its first bounce, and
  nobody but the thrower can catch or snatch it; the slash still can. Level two: shoot
  and throw together with nothing in hand makes a fireball in hand, fire swirling into
  it; it leaves at one and a half times the ball's speed; shot it arcs under half the ball's gravity with the aiming dots, but a quick shot's takes the quick shot's preset arc, at the ball's speed and gravity, from where the ball leaves; thrown it flies
  dead straight, and it bursts on the first thing it meets and strips and knocks
  whatever's within 15 of the burst. Numbers in `BlazeRules`.
- Pulsepistol Punch (K). Shoot without the ball is the pulse: a pillar ten units tall
  at the hand, the width of the screen the way the body faces, that knocks the ball and
  the other body away without stunning, a held ball popping free; standing it's the
  gun sheet, its ten frames at 15 a second with the pulse on the third, one every 20,
  and nothing to see unless the hitboxes are on: a kinetic pulse, no spark. Level two fires in
  stride on the run, and throw is the pull, the same pulse bringing everything toward
  the body. Numbers in `PulseRules`.

  Level two also snipes: with nothing in hand, down held in a crouch 30 frames (the crouch's
  first frame held meanwhile) goes prone into `player_gun_snipe`, its first frame held. A
  crosshair (`crosshair.svg`, 20 art pixels, out of the glow) starts 60 ahead of the hand and
  the stick moves it anywhere on the stage, 3 a frame, not the body; shoot fires a repulsion and
  throw an attraction at it (the sheet played through, the shot on its third frame, the pulse's
  cooldown): whatever is within 12 of the cursor is sent the shot's way, from the hand to the
  cursor, or back toward the shooter, a body knocked 3 with 1.5 of lift (a held ball popping, no
  stun), the ball at 5. As kinetic and unseen as the pulse. Jump gets up; being hit or stunned
  ends it (`SnipeRules`).
- Surf Soda (K). Running, the body
  rides a board, the skid sheet's first frame still, leaning back 45° in a wheelie on the
  board's tail so the board stands up ahead as a shield, easing there and, stopping, back
  down to upright before the board goes; floating three pixels and bobbing two, leaving a trail of `bubbles`, some flipped. In the air the board is always out,
  off an edge too, floating as off a jump; a jump throws a cloud of bubbles in place of
  the spark, and a landing's bubbles spread wide along the ground at their own sizes. Both jumps are a fixed crescent, a quarter circle 40
  up and 30 forward the way it faces over 30 frames, whatever the stick says; from the
  top the stick spins the body about its middle at 0.25 a frame, toward the way it faces
  a backspin, instead of drifting it
  (level two; at level one it always rights itself),
  and within 30 of the ground it eases toward the nearest upright, landing in a burst of
  bubbles. The board, 20 by 3 under the feet and turning with the body, stops the
  other's bolts and fireballs and turns back their thrown ball: a shield to spin into
  place. The board is a bright grape silhouette the glow takes, its tail's shadow a shade
  darker; it comes and goes in a line of bubbles, and onto the rim the body goes upright
  and the board drops away to the floor. On the board the body is a tenth faster, on top of the defender's tenth, and
  past the crescent's top it floats down at half gravity and six tenths of the fall speed
  unless the fast fall cuts through, shedding bubbles along the board's underside. The
  first jump leans back a quarter turn over
  its crescent, the double jump a whole backflip. Running into a wall with the stick held
  toward it (level two), or meeting one anywhere up it in the air held into it, the board
  (never a car's side: `Stage.unridable`)
  turns back against it and rides up at the run speed; letting go,
  stalling or meeting the ceiling flips it off, pushed away, carrying on round the way
  the ride turned it to the next upright. In the air with the stick let go it rights
  itself. Its head's
  particles are `bubble_particle` at 10, every bubble one of two grape purples by a coin flip, each bubble in the
  trail and the landing on its own frame. Numbers in `SurfRules`, first guesses.
- Titan Tea (L). Twice the size: the body box, its reaches (the blade, the snatch, the
  slide's leg, the catch rings), the ledge hang and the heights the hands hold and let go
  of the ball at, all doubled, and drawn at double size. Heavier: half of any knock, and a
  fifth more gravity falling (not rising, so it jumps as high as ever), fall speed and fast fall. It's stripped, the ball popping free, but
  never stunned. One jump, no double jump unless Jumper Juice gives it back, and no
  crouch. Every landing of its own is Quake-Up's level-one quake on the same floor, whatever
  the level; a landing from a knock isn't, or two Titans would knock each other up forever. Its running steps shake the screen a little (3). At level one the walk and run
  are a tenth slower, the dash still 0.4 over the run, and its actions (the stances, shot,
  throw, dunk, catch, slide, slash, roll, snatch, wall and gun) a tenth slower: through one
  the state's clock holds one frame in ten (`FighterSpec.actionHoldInterval`), and a check
  for reaching a frame (`Player.reached`) ignores a held one so nothing fires twice. Level
  two drops the slowdown, and running or dashing into the other strips them, once a
  contact. It comes into a round on the old lightning entry at the ordinary size, then
  grows to double over 30 frames drawn white.

Hits share the strip: the victim is stunned 60 frames, every button dead (the stick
too, when `StunRules.locksMovement` is on; it's parked off while a harder knockback is
tried), and any ball they hold pops free; the slide's leg stuns a body without the ball
too; the slash, the parry, the bolt, the burst and the pulse knock the body away as
well (`Player.knock`), and the pulse doesn't stun. The slash strips a body with or
without the ball, knocking it 4 along the swing and 2 up. The snatch has no
cooldown, as the slash has none, and meeting a live blade it's the parry: the slasher
is the one stripped and knocked back, the blade spent, resolved before the blades so it
always wins. The throw stance parries too, over its first ten frames (`ThrowParryRules`),
the body flashing white: a slash meeting it strips the slasher and the thrower keeps the
ball. Six is two frames of online input delay and about four of a slash start still on
its way from the other phone, the least that leaves a read online. A snatch still takes
the ball through it.

## Interface

The menus, and in time the HUD and the touch pad, are built from the dobo Vector UI pack
(`~/Downloads/Vector_UI_pack_dobo_UI-2`), the pieces the game uses brought into
`ProjectEsper/UI` at half the pack's size by `Tools/import_ui.py`, which also turns the
pack's purple into `EsperPalette`'s plum, the pack having none. `UIPiece` names each
piece with the corners and rims that mustn't stretch, and stretches it for SpriteKit
(a centre rect, scaled) or SwiftUI (a resizable image), 2.5 of its pixels to the point.
Royal blue is the base, black, gold and plum beside it: the screens' ground is an opaque
royal blue gradient over the world, in place of the old dark material; a dialog is a
black card under a royal blue header ribbon as wide as it; a choice is a royal blue plate, plum for a
way back (RESUME, TITLE, TITLE SCREEN), and the cursor's plate turns gold and grows, in
place of the arrow. A piece drawn bigger has its corners and rims scaled with it, so a big plate
keeps the depth of a small one rather than flattening. The title: the name, BEST OF 7 and 47 on royal blue, VS CPU and VS
HUMAN as small switches, plum when picked and black when not, MULTIPLAYER on plum with
its two mode switches under it, the energy colours on a black plate in the bottom right,
and UI, bottom left, the tuning panel, with over it two placeholder pickers of every
`EsperPalette` swatch (its twelve ramps two to a row, a black plate each; the pick ringed white,
kept, picking it again takes the pack's own tone back; `UIColourPicks`), NON-SELECTED for the
black buttons and BLUE for the light blue ones, each with MAIN, TOP and BOTTOM tabs over it (the
face; the top edge and the oval; the bottom edge), each piece's pixels read as a mix of two of its
shades, or of one and the black line (the pair and share that fit best), and drawn as the same
mix of their tones, so the soft corners between the face and a rim stay blends of the new colours
(`UIPiece.toneMap`; matching a shade alone confused a grey ramp's shades with one another). Swatches
are 7 points on a phone, 12 on an iPad or a Mac, 16 on the TV. Settled (`UIColourPicks`): the
plum pieces' face black's second #262634, top edge and oval blue's third #36A9E0, bottom edge
gold's last #D26614; the screens' ground flat purple's last #4D14A3, the win screen's black's
second #262634; the inside of the pause and win menus the black card on purple's last, its rims
moved as they are from its face; the title lettering's lower half silver's second #D1CED7, and
on a gold plate (the cursor's, on the title, the screens and the stage select) blue's lightest
#6BD0FF. The title has the game's own cursor on every
platform, as the screens do (`FlowState.titleCursor`, `TitleItem.rows`): the stick or the
d-pad moves it row to row, to the nearest item across, or along a row, and A picks; the
item under it sits on the gold plate a little bigger (1.08), a colour gets a gold ring; a tap
picks and moves it there. The TV's focus engine is off on the title (`noSystemFocus`), so its
own cursor never shows. A menu press is one pick: after one nothing more is picked until A is
let go, on that screen or whatever it opens. Circle or square (B or X) is back where a screen has one:
the pause resumes, and the first stage select of an offline series goes back to the title;
the win screen, a later stage pick and the drink pick have none. Each screen's buttons, their text, its titles' lettering and its panels (the header
ribbon and the card under it) scale per platform (`UITuning`: phone, iPad or Mac, TV), set on that panel a step of 0.05 at
a time, − and + (which the TV's remote can reach), Pause and Win shown behind it as
they'd be; the values are kept on the device until they're read off and made the
defaults. It starts the phone's title at buttons 1.1, text 1, titles 0.8 and panels 1, and its
pause and win at buttons 1, text 0.8, titles 0.8 and panels 0.9; the iPad's pause and win at buttons 1,
text 1.5, titles 1.5 and panels 0.9, as tuned on one; and the iPad's and the TV's title
at 2.5 and the TV's text elsewhere at 1.5. Lettering on a plate centres on the plate's
face, above its lip, and is nudged up and left by half its own drop. TEXT Y on the panel
scales that lift, one value a platform: half of it, 0.5, on all of them. The stage select: STAGE SELECT on a ribbon, each stage a royal blue plate
with its name on the face, gold when a cursor or a pick is on it. The Greateraid pick,
on the palette's black rather than the royal blue: its ribbon, the line under it in title
lettering, the raised drink's name under that (and "(Second Sip)" under the name when it
is one), the quote and what the drink does on a blue banner below, and online the
seconds in a blue round button, top right. The bottles carry no names and no arrow: the
raised one grows and wears a thick white outline, white copies of it ringed behind it so
it takes the lean. The wait screen: the same black, the same ribbon, and its seconds in
the same blue round button. The HUD: the
round circles, or 47's score, on a black plate, dark enough that the glow passes it. The
touch pad: THROW and SHOOT side by side, JUMP below and between them, THROW, SHOOT and
JUMP as the pack's round buttons in blue, plum and black,
gold while held, their names in title lettering; the stick a faded black round button
with a blue knob; PAUSE, AI, HITBOX and RESET small black plates along the top, plum when
on. Every one of them is on the tuning panel (STAGE, PICK, HUD, TOUCH), the dialogs
starting from the pause's and the win's sizes on each platform, the HUD and the pad at
1 (the iPad's pad at buttons 0.75 and text 1.5, as tuned); the HUD and the pad are previewed over the court, as in play. The debug pickers and
sliders keep their plain look.

## The game loop

A best of seven, first to four points, in `Series`. The title screen, drawn by the
SwiftUI layer over the Metal view on a dark ultra-thin material with the court showing
through, offers BEST OF 7 and, greyed for now, MULTIPLAYER; jump on the pad starts too.
A round starts with both bodies ported in at their
spawns: a cluster of `flashspark2` over each in its energy, the backboards' 3 by 4 grid
at 0.4 unskewed, held the 12 frames the body is hidden and faded over 0.3 seconds (the
old bolt and crown, `boltEntry`, are Titan Tea's entry); then the three count. With
a screen up or on its way (the drink, the stage select, the win) the port-in and the
count both wait for it to close, BUCKET!! playing out meanwhile; the sim's own count is
set again as play comes back in title lettering
and BALL OUT!!! as it hits zero, when both can act. A point is a round: BUCKET!! goes up
with the strike, and whoever was scored on drinks. The computer drinks at once, one of
its three at random on the series' dice; the human gets the pick screen once the strike
has played, and the round counts again after the drink. Five circles across the top,
dark purple, fill in the round winner's colour as they go, with a sixth and seventh
added if the series gets there, and to either side of them each side's drinks with their
levels, in its colour. What the computer drank goes up as a banner after BUCKET!!. Four points
brings the win screen, the final score large under who won: NEW MATCH, a fresh
best of seven with the drinks gone, or TITLE. RESET starts the round again with the
drinks kept.

The stage select comes before the first round and after each stage's best of three:
the first to two points on a stage (`Series.pointsPerStage`) ends it, and unless the
series is over both go to the select before the drink. Rectangles in a row, The Wreck
Center, Longball Stadium and Slamstill Traffic (`StageChoice`), the one under a cursor
grown, and in its bottom-right corner a circle in the voter's colour, a ring while they
look and filled once they've picked. Two picks the same go there; two different flip a
coin on the series' dice, the light going back and forth for a second and a half before
it lands. Against the computer this phone picks alone; with a second pad in, both vote.
Online the first stage is a vote, and after that whoever lost the stage picks alone
while the other watches. The new stage is a fresh match swapped in for the stopped one,
keeping its frame, and the world is redrawn for it (`showStage`). What the computer
drank at the end of a stage is lettered once play is back.

Start on a pad, delete on a keyboard, or PAUSE beside AI on the phone pauses a match offline: RESTART MATCH, a fresh
best of seven on the stage the match started on; TITLE SCREEN; RESUME, where the cursor
starts. Start again resumes too. A pick timer of twenty seconds for networked play is a number in `Series`,
not enforced yet.

Title lettering is `TitleText`: CardCourt's TwoXMark styling in SF Pro Rounded Black, white
over the palette blue's highlight (#6BD0FF) split at the capitals' middle, a black outline
walked round a ring, a black drop to the south-east, drawn into a texture per string.

## 47

A second mode (`GameMode.fortySeven`), on The Wreck Center only for now, no stage
select, no drinks and no powers. The title has 47 beside BEST OF 7. A basket doesn't
reset anything: the points go up and play goes on, the scorer unable to take the ball,
by hand or by snatch, for 120 frames (`pickupLockout`), flickering black (#242234)
every other four frames while it lasts, so it goes the other way;
through the net the ball is nobody's shot any more, so the other can take it at once. A
basket is three from outside the three-point line, two from inside it or off a dunk,
judged by where the ball last left a hand, or was knocked or swatted from
(`Ball.launchPoint`). The line is a circle round each rim reaching the middle
platform's nearest edge (92 units on the court, `FortySevenRules.threePointRadius`);
the half facing the middle is drawn behind everything, dim and glowing, in the colour
of the side guarding that rim, its two ends run on straight to the screen's edge on the
rim's side, cut off at the walls and the floor; 4 art pixels thick (3PT WIDTH on the
UI tuning panel, under HUD), breathing between gone and a quarter every six seconds. THREE!! goes up for three, BUCKET!! for two. Each side's
points sit either side of a small 47 at the top, in its colour, in place of the round
circles. The first to 47 wins, on the same win screen. RESET, and RESTART MATCH, start
it again from nothing. Online, the host's mode is played: MULTIPLAYER has BEST OF 7 and
47 under it, the pick kept between launches and sent in hello.

## Greateraid

The drinks between rounds, in `Greateraid.swift`. Three bottles an offer, the user's
vector bottle from the catalog, blue for a booster and its three blues swapped for
golds for a biomorph, large with their bottoms off the screen, each leaning five to
thirty degrees, its name across it, the bottle's line in italics and quotes and what
the raised one does lettered in the middle; a tap raises a bottle and a second tap
drinks it, or the stick and jump on the pad. Boosters raise a stat and stack to two
drinks, after which that bottle stops being offered; as a group they're weighted three
to one over Biomorphs, which are the powers, one at a time. With a biomorph in hand only
that one comes round again, lettered "(Second Sip)" under its name, and drinking it
takes the power to level two. Drinks stack through the series and go with it. Every
bottle carries its comment (`Greateraid.comment`), the user's line; "..." is the
placeholder for one not written yet.

- Hasty Horchata: run, dash and air speed up by half a unit a drink. The body a match
  starts on is the baseline with half a unit less of each, the double jump kept, so one
  Hasty Horchata brings it back to the baseline the game was tuned on.
- Jumper Juice: both jumps a tenth higher; then a third jump at half the first's
  height, speed the first's over root two. The double jump itself is 130% of the full
  hop's height, Fox's numbers.
- Lunge Lemonade: four more frames of dash a drink.
- Cannon Cola: a quarter more shot pace a drink. The shot runs the same arc to the same
  spot, only faster, velocity up by the pace and gravity by its square; it's an ordinary
  ball again from its first bounce.
- Slide Cider: eight frames of slide a drink, so further.
- Feather Fresca: falling, a quarter of gravity gone a drink (×0.75, then ×0.5); a fast
  fall is untouched, so it still lands quickly.
- Web Water: the swing; level two adds the web line. The swing's line is drawn on past its anchor off
  the top of the screen, the view's alone.
- Super Smoothie: flight; level two flies faster, with the ball as fast as level one
  without, lasts 180 frames rather than 120, and glides forward. Flight needs no second
  jump.
- Flash Fizz: the flash on jump, five tiles, tearing; level two gives two a cooldown.
- Platform Protein Shake: the slab; level two adds the wall.
- Quake-Up Coffee: the quake on the same floor; level two the whole screen.
- Zeus Juice: the bolt; level two adds the strike on throw.
- Frost Tea: the freezing snatch and the endless slide; level two adds the ice clones.
- Blazing Boba: the flames and the burning ball; level two adds the fireball.
- Pulsepistol Punch: the pulse; level two shoots on the run and adds the pull.
- Titan Tea: the size and weight, slowed; level two at full speed, with the trample.

## Tuning pickers

Segmented pickers in the top-left corner change a stat live on both players. `Tuning.swift`
holds the variants; A is always the baseline as tuned.

- HEAD: how the detached head follows the body. Both close half the gap each frame. B,
  the default, leads sideways instead of trailing, the offset reversed across only.
- POWER, with LEVEL beside it (1 or 2): A none, B Web Water, C Super Smoothie, D Flash Fizz, E Platform Protein
  Shake, F Quake-Up Coffee, G Zeus Juice, H Frost Tea, I Blazing Boba, J Pulsepistol
  Punch, K Surf Soda, L Titan Tea, at the level LEVEL picks, on this phone's player only, the
  other side keeping its drinks, with the body the power brings; A by default. The left bumper always steps POWER; the local side's power
  and level are lettered under the pickers.
- The field's goalposts, settled: the rims 107 high and 66 in from each wall, the posts
  60 in and drawn for a rim at 120, the gold 8 wide; the crossbar sits 20 below that,
  tilted 20° with the end toward the field up, the uprights 100 over it; the back rod
  and the crossbar with its uprights each have their own 1 black outline, as do the
  light panels.
- HITBOX, beside RESET, or a pad's left trigger (L2): draws the sim's boxes over the world. Bodies white (10 × 17.5 units, 16 × 28 art pixels), the loose
  ball purple, the two catch rings faint, the slide's leg and the slash's blade red, the
  snatch's reach green with the hand's ring while it's out, a flash's tear cyan.
- AI, beside that: the computer plays the other side, whatever pads are in. Off, the second
  pad or nothing does. The title's VS CPU / VS HUMAN toggle is the same switch, kept between launches;
  clicking a pad's right stick (R3) switches it too.

## Energy colours

Two palettes, as CardCourt has: `PixelPalette` (`_Graphic Assets/Pixel_Palette.png`,
AAP-64) for the world, `EsperPalette` for the interface. Seven energy colours to pick from
on the title, circles in its corner, the pick kept between launches (`EnergyColour`,
`esper.energyColour`): orange #FA6A0A, the default, teal #20D6C7, red #DF3E23, lime
#9CDB43, pink #BC4A9B, blue #249FDE and gold #F9A31B, all AAP-64's; the body sprite's tone is the
colour lifted two fifths of the way to white. The loose ball's purple is #793A80; Surf
Soda's darker bubbles and its board's tail #403353; outlines drawn in code in the world
(the field's panels and goalposts, the opponent chevron, the round circles) #242234. The
sheets in `_Graphic Assets/Pixel Art` are recoloured to AAP-64's nearest by eye (CIE Lab),
alpha kept, by `Tools/recolour_to_palette.py`, which leaves two kinds alone: all-grey
sheets, the masks the energy colour tints, and the player sheets, which
`Tools/recolour_players.py` puts on twelve AAP-64 colours, one a part, the same in every sheet:
head #20D6C7, ball #FFFFFF, torso #FA6A0A and pelvis #BB7547, front thigh #FFD541 and leg
#FFFC40, back thigh #73172D and leg #B4202A (the thigh the darker, as the arms and front leg
go dark to light), front arm #59C135 and hand #9CDB43, back arm #793A80 and hand #BC4A9B;
the slash's pinks are left alone. Those are the part keys the game reads (`BodyPart`). The
GMS2 sheets are written as strips in Pixel Art, taking over the GMS2 sprites, and each sheet
as it was is kept in `Pixel Art/Player Backup`; the players' outline is `Look`'s, the palette's
#242234. An experiment, on (`HumanLook.enabled`; off puts it all back): the players drawn as
people, skin on the head, the arms and hands and the lower legs, the front in palette 35
#DBA463 and the back in 34 #BB7547, the thighs, torso and pelvis still the energy's; the head
drawn on the body rather than apart (no lag, no bob, no enlarging), outlined with it and not
glowing, its particles still rising off it. The outline is drawn as it is and never glowing, lifted off each frame onto its own white texture and
drawn as a child of the body, coloured each frame, so it can change without recolouring a frame.
In the zone (`ZoneTuning.inTheZone`, a placeholder, off
until something puts a player in it, for now nothing) the outline eases through 7 #F9A31B, 11 #9CDB43, 19 #249FDE, 20 #20D6C7, 27 #BC4A9B a quarter second each, and so do the
ball in hand and the energy on the body (the slash's blade, the skid's puffs, a release's streaks,
drawn in grey and toned by a shader through `Look.energyTone`'s ramp, in the look's colour out
of the zone); each regular energy particle off the head comes out in one of them at random,
the powers' own particles keeping their colours. The fire sheets are recoloured by hand after `fire_dash`: each of its
original colours maps to one of five AAP-64 shades, and the other fire sheets from the same
ramp take that map (the rest to their nearest mapped colour); since moved up one index, to
#FFD541, #F9A31B, #FA6A0A, #DF3E23 and #B4202A (indexes 8 down to 4);
`fire_explosion`, a different sheet, is left as the tool had it. The importer's `NOT_TONED` keeps the strike bolts,
which the recolour took to pure white, drawn as painted. Each has an opposite: orange and teal, red
and lime, pink and blue, and gold gives way to blue. Offline this phone's pick is player one and the other side teal,
or the pick's opposite if the pick is teal. Online the colour rides in the hello: the
host, player one, keeps theirs, and the other takes the opposite if they match. Any two
different colours can meet. Purple is left out, as it's the loose ball's.

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
  the block it walks out underneath it, the block floating clear of the floor. In the
  air within 60 of its rim, and not far below it, it drops whatever it was doing for the
  dunk, and it only takes the stance for one inside the dunk's reach, 25, so the stance
  goes onto the rim rather than letting go as a throw. Once the other has swung twice in
  a second and a half, spam as it reads it, the next swing in reach facing it is met with
  the throw stance's parry, held its ten frames and cancelled with shoot, the ball kept.
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
walls go white, fading back over 20 frames, and the crown erupts off the rim with it. Sparks and bolts play at 24 a second. Stunned, the body and head flicker a dark shade of the energy colour. `ParticleLook.sprites` draws the head's fire and the double jump's platform with `esper_spark` frames at the squares' size, in place of the hard squares. The jump spark and the dash's smoke, near-white on
their sheets, go through the ramp too, in the player's colour. A held throw shows the
charge, the swirl round the ball in hand at 30 a second and half its sheet's size: up to frame 67, then frames 35 to 67 round again for as long as the throw is held,
and when the throw is let go the frames after 67 play out where the ball was. Each player has a look with a team colour: orange for player 1, teal for player 2. The head
and the ball in hand are drawn in it, the ball's outline is in it, and so are the halo on
the ball and the fire off the head. The body a light orange or a light teal toward the team colour, the back limbs a greyed,
darker version of it, a black line one pixel thick round the body following the outside
edge only, and the front arm stroked on its own where it lies over the body. The head is
split out of every frame and drawn as its own sprite with no line, trailing its place on
the body by a quarter of the gap each frame and bobbing a pixel, and its fire is released
into the world so it streams behind a moving head. The loose ball is purple, and from a shot, throw or dunk until its first bounce it's the colour
of whoever let it go, then shifts back over 30. A flying ball leaves a soft additive trail
in its colour. The library finds where the ball and the head sit in each frame so the halo
and the fire follow them. The head is drawn at 1.25 times about its own centre and lifted a pixel off the body. Three dim
yellow chevrons stack over a resting ball and light one after another from the top. A
double jump leaves a short platform of loose digital squares under the feet where it was
taken; they hang a moment, then drop away and cut out. The head bits rise in a tight column that one swinging wind bends as a whole, a scarf.
The ball in hand is its own sprite on the frame's ball, and when a dribble's ball hangs
off a ledge it reaches down to the real floor under it over the same frames; only the
dribble sheets do that, so a stance's ball never sags off the edge of a slab. The feather-fan wing in `Wing.swift` is parked, not in the scene. The ball pointer
is an SF Symbol chevron doing what the pixel one did: three steps down, then off. A slide
leaves the dash's smoke; the snatch's catch spark sits on the hand at full stretch and
rides the body through the rest of the swing, so it's on the hand however far the run
carries it; a ball
knocked loose bursts like a wall jump's spark, away from the hitter.

The powers' effects: Blazing Boba's jump, dash, wall spark, skid, charge, trail and
burst are the painted `fire_*` sheets drawn as they are at a third, standing on the
bottom of their frames; Zeus Juice's bolts are thrown from the throw's release pose; Zeus Juice's jump spark and
charge are grey sheets toned per player; Flash Fizz's flash is `flashspark`, its 256x144 frames boxed down by four, drawn added
so it glows, at both ends, in place of the diamonds; Frost Tea's sparks are snowflakes off the
vector, a sphere of them for the snatch; Quake-Up's quake shakes the camera a pixel or
two for eight frames and throws rock squares up; bolts are the SF bolt in the energy
colour with fading afterimages; the strike reuses a scoring bolt down to the point;
the pulse is a bar from the hand to the edge; ice clones are the body's frame in ice;
flames loop `fire_trail`; fireballs are the ball in fire; frozen bodies and balls go
ice; the cape is seven short rectangles chained along the glide's trail with a wave down
its length.

## Highway Traffic

`Stage.highway`, Slamstill Traffic on the stage select. The court's 34 by 16,
flat: a dark blue night, and a road where the field's grass is, the floor an invisible
strip through its middle. Each player starts where the court has them, the ball loose at
centre.

- The traffic (`Highway.swift`): two lanes, each in four slots: the near lane on the floor,
  which plays, and the far one up over the lane line, drawn behind and darker, only
  scenery. The near lane stands 17.5 down into the road, its boxes with it; the far lane
  7.5 up. Each slot is each wide enough for the longest
  vehicle, a car standing in each; the near lane's are solid and rideable and face right,
  the far lane's face left. Which of the 23 vehicles stands where
  comes off the match's dice, so both phones agree with nothing sent. Each has its own
  length in tiles and its height the drawing's own; it's solid in blocks of eight art
  pixels (`Vehicle.blocks`), each column's unbroken runs one box, mirrored when it faces
  left. The blocks are set by hand in the bounds gallery (the BOUNDS picker, offline): the
  vehicle blown up with see-through blocks over it, a tap going round a block's kinds
  (solid, a slope rising to the right, one falling to the right, open), RESET goes back to the
  measured outline, COPY puts the table on the clipboard as Swift for `Vehicle.set`.
  Edits are kept between launches and stand in live until they're pasted in.
  The slopes (`Stage.slopes`, `SlopeRules`) are 45°, solid under the diagonal and along
  their two straight sides: the feet ride one up and down at walking speed, a block's
  height a frame at most, stepping up over the block a slope climbs to; standing still
  on one, a body stays put; its straight side is a wall and there's no clinging to it;
  the ball bounces off the diagonal, the push into it turned back and a share kept, and
  rolls down it. Anything that would stun a player
  hits one: the slash, a bolt, a strike, a fireball's burst, a thrown ball, a flame; one
  swing counts once. Three hits wreck it, the fuel truck one of fire, in a fire burst, and
  a new one off the dice takes its slot.
- The drawings: `Tools/split_vehicles.py` splits each vector into its body and its wheels
  (a wheel is a tyre's circle through its hub's bolts), and the helicopter into its hull,
  top rotor and tail rotor, each plain and its three reds, as imagesets in the catalog's
  Traffic folder. The racer and both motorcycles have no wheels to split and idle whole.
  A body shivers a pixel under wheels drawn over it that stay put, each on its own beat, dips three
  pixels on its springs when someone lands on it, and flashes black when hit.
- The rim: one at a time, carried under a helicopter flying from one wall to the other at
  1 a frame, 140 up, swaying 6 either way every two seconds, the rim 22 ahead of it and
  18 under, its backboard toward the helicopter; the rim player one guards flies left to
  right, player two's right to left, and the next carries the other side's rim, and the
  one not out waits far over the sky. The helicopter's reds are the rim's guarding side's
  energy in dark tones, so the glow leaves them their colour; its tail rotor spins and its top rotor flips end over end every other frame.

## Football Field

`Stage.footballField`, Longball Stadium on the stage select. 238 by 20 tiles, seven courts long, flat and empty: the floor is an
invisible one-tile strip through the middle of the turf, the end walls solid. The rims sit
at 107, 66 in from each wall, floating between the
goalposts' uprights; by design a standing shot can't reach them, so scoring takes a
jump shot, or a jump off a helmet to dunk or shoot. The computer always takes the jump
shot at a rim that high. Each player starts
under the rim they guard, and the coin flip, off the series' dice so both phones agree,
puts the ball in one pair of hands. A ball that leaves the world comes back at centre.

- Helmets (`FieldRules`): 4 by 4 tiles, solid, in the defender's energy colour, one of the
  three helmet vectors filled in that colour, facing the
  way they go, drawn at 1.1 times the box, tipped back 40°, bobbing round a two-pixel
  circle each on its own phase; a burst of `flashspark2` in their colour
  where one spawns and where one goes, as when two meet. While someone has the
  ball a clock runs, and every two and a half seconds of it a helmet comes from the end the
  defender guards at one of four heights (20, 50, 70, 90; the lowest pushes a standing
  body and clears a crouch or a slide, and the computer crouches or slides under it) and crosses at 2 a frame to
  the far wall, where it goes. They keep going when the ball is loose; only the clock
  stops. A body standing on one rides it; one in its way is pushed ahead of it, and once
  that would put them in a wall it passes through them. It pushes the loose ball the same
  way, and a pushed ball is an ordinary ball again, falling. The computer, meeting one at
  its height, hops and double jumps onto it and rides it. Two going opposite ways that meet take each other out in a burst of `flashspark2`
  in their colours.
- The portal: Gemini's rift from Project Stars (`gemini_rift_v1` and `v2`, boxed down by
  four), drawn as there without the lean: the two drawings as a tall pair and again half
  as wide turned end over end, the pairs trading length every 1.5 seconds, each plate
  jumping 1.5 pixels and to a new opacity twelve times a second, held. At 90, above double-jump height, at a random x kept 200
  from either end; one at a time, five seconds each, the next as soon as it goes. A shot
  or throw still its thrower's through it comes out ten yards, a hundredth of the field
  each, toward the thrower's rim, with a lift of 2 forward and 3.5 up.
- The scenery (`FieldArt`) is flat shapes drawn once: a night sky with floodlight banks,
  the stands with fanning lines and two rails twelve pixels tall, four apart, that wears the possession's
  colour like the court's walls and, with the ball in hand, fills with chevrons drifting
  toward the rim the holder attacks, and with it loose runs "⬩ GET THE BALL! ⬩", one
  rail's lettering one way and the other's the other; the floodlights' blooms take the same colour, purple
  when nobody has it, and so do the panels the lamps sit on, trapezoids wider at the top;
  the yard numbers at one and a half times; the down marker (`football_marker`, 48 tall) stood on the top
  edge of the grass where a loose ball last came to rest, staying there until the next
  rest or the point's restart; the turf's five-yard stripes,
  leaning yard lines, hashes and numbers with their arrows. Goalposts: a padded base in the
  colour of the side that guards it, as the court's blocks are, the pole's width and five more, behind the rim, the gold pole bending forward to the crossbar under it, two uprights.
- The ball cam (`StageFeatures.ballCam`, the view's alone): a close view of the ball,
  128 by 80 art pixels round it, only in play, hanging over the upper screen as a
  trapezoid wider at the top at a third, lined with `flashspark2` in the local player's energy, each on its own
  frame, centred across the screen wherever the local player is, the round circles drawn
  over it (a copy in the HUD while it shows). It has its own scene,
  with its own copy of the scenery built once, and its own renderer, drawn one frame in
  three into a small texture with its own glow, laid down after the screen's; the game
  scene is never drawn twice in a frame. It copies every sprite of the bodies and effects
  layers and the shadows, but only those within its window round the ball and a margin:
  the rest cost one position check each, so a busy field costs it little. Emitters and
  shapes (webs, the pulse) aren't copied; the portal is sprites, so it is.
- On the TV the game renders at 1080p whatever the screen, the pixel art doubled onto a
  4K one unsmoothed (the HUD and menus stay at 4K); the Apple TV 4K's GPU spent about 50 ms
  a frame at 4K, most of it the glow and the composite. The glow there is half size with
  the blur's step halved, so it spreads as far as it did at 4K; side by side with a
  full-size glow it looked the same and cost less. The corner readout shows each render
  stage's CPU and GPU milliseconds a frame, the whole frame's GPU span (the stages are
  separate command buffers and can overlap, so they don't sum), and the render and glow
  sizes.
- Nothing is made mid-match that could have been made before it. At launch every player
  frame and toned effect is built and sent to the GPU; a colour change drops that player's
  and rebuilds all of them (frames, heads, energy, the ball-as-energy sheets, the toned
  effects and particle sheets, the wall-spark silhouettes) on a background queue, then
  keeps them and preloads them. Before this a colour other than the launch defaults rebuilt
  each texture on its first use, a hitch of up to 85 ms the first time each move or spark
  was seen. Also made before play: every page of the sprite atlas; Frost Tea's ice frames
  and snowflake; the art drawn from vectors, each drawn once and kept (the surfboard, the
  helmets in both colours, and on the highway every vehicle and the helicopter in its
  rims' colours, on each stage build and colour change); and one of each way of drawing
  (additive and tinted sprites, shapes, an emitter, a crop, a label) in the launch's
  hidden warm-up, so SpriteKit builds their pipelines then.
- Shadows (`StageFeatures.shadows`, the view's alone): each body's current frame and its
  head, and the goalposts, cast in a dark greyed purple at two thirds, mirrored under the
  feet or the floor line and sheared by the turf's own lean where they stand, so they
  tip away from the field's middle as the yard lines tip toward it.
  A body's shadow stays on the ground under it: rising, it thins out and shrinks, gone at
  160 pixels up, half its size by then. It stays upright whatever the body's lean.
- The backboard: behind each rim a 3 by 4 cluster of `flashspark2` in the guarding side's
  energy, each on its own frame so the board shimmers, on a grid sheared to the
  crossbar's lean, 10 behind the rim and 24 over it at 0.4, sheared 20°, at two thirds;
  solid to the ball, a 20-unit-tall box (`FieldRules.backboardOffset`, `ballBlockers`)
  from the backboard's face all the way back to the end wall, so nothing gets behind it.
  Platform Protein Shake's slabs and walls are the same flash clusters, filling their box
  in the maker's energy.
- The camera is zonal, as Mega Man's and Nidhogg's: the field in seven zones a court wide,
  the camera level on one zone's centre, held inside the field's ends. Within
  a quarter of the screen's width of its edge (`CameraTuning.zoneBufferShare`) the local
  player sends it
  sliding to the next zone over `CameraTuning.slideSeconds` (0.5), eased out, quick away
  and slowing into the new centre, if that zone's centre is
  the nearer, so it never flips back at the line; each round it picks up the zone the
  local player starts in.
  The view takes in the stage's height and the turf below the floor. When the ball is off
  the screen sideways, its chevrons sit at that edge at its height, pointing at it, purple
  outlined in dark purple. The opponent off the screen likewise: one chevron in their
  energy, outlined in black, at that edge, at their chest's height. All of
  it is the view; the sim never sees the camera, so it's safe online.

## Court

The Wreck Center on the stage select, and the default. Its backboard blocks are rows 8 and 9, and
the rims hang off them a tile under their top, lowered 7, at 83 (`Stage.courtRimDrop`);
RIM DEPTH (`Stage.courtRimDepth`) slides each toward its block while `DunkTuning` holds a
body hung on the right rim, the hang and the hoop's art coming with them. Below
the floor's row everything is the outline black, #242234. Its hoops are `hoop`, the rim and a backboard drawn
to the players' scale, placed 5 art pixels out from the backboard and 10 up from the rim's point
(`HoopTuning.offset`), kept out of the glow (the mask marks it, as it does the banner);
the net is `HoopNet`: 5 straight columns of 7 downward chevrons hung from the rim, NET SPREAD
(4) art pixels apart across and NET ROWS (2.75, in quarters) apart down, each strand from the second row down leaning NET WEAVE (0.5) of
the way to the neighbour it's knotted to on that row, toward the right-hand one on one row and
the left-hand one on the next, an edge strand with no one that side hanging straight, so the
chevrons run in diagonals both ways, diamonds with knots; NET TAPER (0.5) narrows it toward the
bottom; NET SKEW (0) raises each column that many art pixels over the one before, toward
the backboard, to match its angle; each chevron smaller than the one
above, from NET TOP (×1) at the rim to NET BOTTOM (×0.25) at the bottom (a chevron is 2.25
across and 1.5 deep at ×1, 1 thick), the whole net moved from the rim's point by NET X and
NET Y (−2, −4; x mirrored on a left backboard, as the hoop's art is); the sliders are on the
UI tuning panel, under HUD. Each chevron is a knot of a Verlet cloth, the top ones pinned to the rim and following it,
each tied to the one below and its neighbours across, and each pulled 0.08 of the way back to
its place every frame, so the net always settles to its shape. The ball, swept from last
frame's point to this one's so a fast shot can't slip between knots, pushes them out and drags
them 0.4 of its travel. A ball dropping in through the rim's opening is a swish: from that
frame the net is pushed by the ball as it came in, carried on at that speed and angle (at
least a pixel a frame down) through the bottom or for 40 frames, not by the ball the sim then
bounces off the back of the rim, so the net flares the way the shot was going. Bodies near the rim push it too. It's in
the guarding side's energy, in the glow; still and with nothing near, it sleeps. The numbers
are `NetTuning`. The football field's and
the highway's backboards are to be fitted to it. The tiles are flat colour, in dark shades: each colour at 0.45 of its brightness. The
floor and walls start purple and shift over 20 frames to the colour of whoever holds the
ball, and back. The backboard blocks wear the colour of the player who scores there's opponent, since you
score on the other side's basket. The ledge is
magenta. Three small faint green chevrons stack over the rim
the holder scores on. The head particles are sprites of their own, not an emitter, so each plays its sheet
through at 24 a second over its life (`esper_particle` by default), rising on one
swinging wind; a single-frame one (a snowflake, or the squares with
`ParticleLook.sprites` off) steps down in size instead. The double jump's platform plays
the particle sheet as its bits drop; Blazing Boba's head burns `fire_particle`, Zeus Juice's sheds its bolts and Surf Soda's its bubbles, each half and half with the regular energy as Frost Tea's snowflakes are; and its burning ball, loose and flying, trails the same fire at twice a head's rate beside its usual trail, streaming back along the ball's path and turned to it, without the head's rise and wind, Frost Tea's sheds snowflakes among the energy,
Zeus Juice's throws the two lightning particles, half each. Sizes per sprite in
`ParticleLook`: energy 10, snowflake 6, fire 12, lightning 8. Hits spark with
`esper_spark` and `esper_spark2`, Zeus Juice's with `lightning_spark` and
`lightning_spark2`, at half size, centred, twice that on a wall; a fireball's burst is
twice its size on a wall. Blazing Boba's hits spark with `fire_spark`, `fire_spark2` or
`fire_spark3`, painted, at half size, centred. The flash sheet is drawn over, not added, so its tone shows,
and with the hitboxes on its tear's reach rings both ends. Head particles each start on
a random frame of their sheet, so a stream never plays in step. The wall jump spark is `fire_wallspark` as a
silhouette in the energy colour; Blazing Boba's is `fire_skid`. The flash is `flashspark2` at 0.66 in the energy colour at both
ends; the jump spark draws at three quarters, the ice one at half. Frost Tea's jump spark is
`ice_jumpspark` toned in the snowflake's two blues.

## Sound

On again. At launch (`SoundBoard.prepare`, from `FlowState`) the engine starts at once, on the
title, and everything is read and mixed on a background thread, each voice then playing a
moment of silence so its first real sound has nothing to set up; nothing loads the first time a
sound plays; a sound asked for before then is skipped. A route change (the TV's HDMI
resetting) or an interruption stops the engine and its voices: they're started again on the
main queue, away from a frame, and a sound that finds the engine or its voice down is
skipped and asks for that restart, never starting the engine itself.

`Tools/sfx.py` makes sounds the bfxr way from recipes in `Tools/sfx.json` (oscillator,
envelope, pitch slide and vibrato, arpeggio, filters, voices mixed) into `_Sound FX`, for
the importer to take in like any other.

The user's effects in `_Sound FX`, any of WAV, MP3 or M4A, brought into `ProjectEsper/Sounds`
as 16-bit 44.1 kHz mono WAV by
`Tools/import_sounds.py` (run it after adding or changing one; the originals are only
read). `SoundBoard` reads each into memory once and plays it on a pool of sixteen voices
through one engine, left running, heard by where they happen: full on the screen,
fading to nothing 32 art pixels past its edge, so nothing off the screen is heard (the
menus and the count are everywhere); each sound to a voice that has finished, or with all busy to the one
nearest its end, the new sound scheduled to interrupt the old (stopping a playing voice waits
on the audio thread, which cost the TV 4 ms a frame of footsteps), ambient, so the silent switch mutes it. Sounds come off the events
shown, once, like the effects.

- jump: the jump, the double jump, the wall jump.
- shoot_v2: the shot, the throw, the fireball's throw and Zeus Juice's bolt (player_shoot
  is unused).
- esper_slash: the slash. slash_wallclank: its blade in a wall on its first live frame,
  clear of the floor the body stands on (`slashClanked`).
- snatch: the snatch at full stretch. catch: a catch.
- parry and parry2, mixed at 0.3 each as they're read: a parry, the snatch's or the
  throw stance's.
- player_hit: struck, popped.
- ball_bounce: every bounce faster than 0.6 across the surface, at full volume from 4;
  and in hand, on the ground, on each frame of a sheet where the landmarks put the ball
  lowest, under five art pixels: the dribbles and the taunt (idle 3 and 8, walk 2 and 6,
  run 4, taunt 2 and 7).
- step: the walk and run sheets' frames 0 and 4, on the ground, at twice its file's level.
- The announcer's 3, 2, 1 (announcer_1..3, or the second set announcer_1-2..3-2 on the COUNT
  picker, A or B): each number of the count as it goes up, in play.
- announcer_ballout and ballout2 together at BALL OUT, each panned halfway to its own side.
- port_in: the port-in at a round's start.
- swish: a point, with the strike on the rim; a dunk has none, the announcer's line instead.
- crowd_cheer, behind the rest, on every basket, and with it the announcer: on the game's last,
  thatlldoit, thatlldoit-2 or thatdecidesit, the finish slowing to 0.35 (offline) and the camera
  easing in on the ball to 0.55 of its view over 40 frames and then staying on it, in a hand or
  loose (where it was last seen while it's drawn nowhere), the HUD keeping its size, until
  the win screen; otherwise a line drawn by weight: the generic score (score, -2, -3,
  whatascore) always in at 4, a dunk's (slamdunk, -2, -3, dunk) at 2 on a dunk, the wrist work
  (watchthewristwork, -2) at 1 on any other shot and 2 on a floater (`Ball.floaterShot`,
  carried by the score event), itsathree at 2 on a three in 47. winner, winner-2 or whatawin
  once as the game goes to the win screen, not again when it's redrawn (a rematch's wait).
- The vocals come in from `_Sound FX/Vocals` by a list in `Tools/import_sounds.py`, the rest of
  the folder left out, each levelled as it's converted: its loudness while sounding (the RMS
  of its 10 ms stretches above -40 dBFS) to -21 dB for the announcer, just under the swish
  (-20.5), and -27 for the crowd, its peak kept under -3.
- lightning_hit1, 2, 3, one at random: with every lightning spark, Zeus Juice's hits.
- fire_hit: with every fire spark, Blazing Boba's hits.
- menu_select: a cursor moving, a colour circle (menu_cursor, louder than the rest, is
  unused). menu_select_v2, played reversed: a choice or a stage picked, BEST OF 7,
  MULTIPLAYER. menu_back: RESUME, start to unpause, TITLE and TITLE SCREEN.

## Glow

`GlowSettings` in `Tuning.swift`: luminance threshold 0.2 for the world and 0.8 for the
bodies, softness of the cut, blur passes at half size, intensity, tint. The passes are in
`Glow.metal`. A second renderer draws a mirror scene holding only the two body sprites
on black (`MaskScene`), and that mask tells the bright pass which threshold applies. The
game scene is never drawn twice in a frame: SpriteKit reuses its per-frame buffers
between two renders, which drew the bodies as white squares. The HUD never goes through
the glow: it's drawn by its own SpriteKit view over the Metal view, transparent, so the
bottles and the two-tone lettering keep their colours. Only the round circles glow, kept
in the game scene under the camera. The pick and win screens sit on the same dark
ultra-thin material as the title, a SwiftUI layer between the two views (`FlowState.veiled`).
The count's banner stays in the world under the material, so it shows through a screen;
the mask marks it in pure green and the bright pass leaves green alone. On a screen the
stick moves the cursor any of the four ways, and CardCourt's selection arrow
(`MenuArrow`, its own greys, drawn pointing down) points at the raised choice: over a
bottle's name, or turned to the right beside a lettered button.
The corner counter shows the frame rate and the worst frame gap of the last second,
which is what a hitch shows up as.

## Multiplayer

Two phones over Game Center, the match run in lockstep with rollback. The sim is the
same `Match` on both; only inputs cross. `RollbackSession` in the sim package runs it:
each frame runs as soon as the local input is known, the other side's predicted as held
where it hasn't arrived, and when it arrives different the sim rolls back to that frame
(`Match` is a value, so a snapshot is a copy) and runs forward again. The local input
is held `NetRules.inputDelay` frames (2) before it's simulated, so the other side's
usually has time to arrive; the sim runs at most `predictionWindow` frames (8) past
the last remote input it holds, then waits; and the side ahead of the other by more
than the other is of it holds back half the gap, checked every 10 frames, the frame
counts and each side's lead going in every packet. A frame's local input is fixed the
first time the frame is reached, since it may already have gone over the wire; a tick
that can't run drops its sample. Every packet carries every input the other side hasn't
acknowledged, and the newest eight regardless, so a lost packet costs nothing: they go
unreliably at 60 a second, five bytes an input (the stick and the aim in 127 steps a
side, the buttons in one byte), which both sides simulate quantized. Hello, picks, stage votes, the
rematch and bye go reliably. Each packet also carries a checksum of the sender's state
before its last confirmed frame; a disagreement lights DESYNC in the corner readout,
which also shows the lead and the rollback counts. Offline runs through the same session
with the other side's input handed in each tick, so there is one path and every frame
confirms at once.

Events come back in two kinds: those of frames run for the first time, or run again
with something new, are the effects, shown at once and never taken back; a point comes
only from a frame both sides' inputs have confirmed, so BUCKET, the strike and the round
never happen on a prediction. After a confirmed point both phones stop the sim on the
same frame, 60 past it, and change screens together: the scored-on side picks, the
other watches WAIT with the same clock, and the pick crosses as an index into the offers
both rolled off the shared dice. The pick is applied once every frame before the stop is
confirmed, as a change outside the inputs (`RollbackSession.mutate`), then both resume.
Twenty seconds to pick, or the raised bottle drinks itself. The seed is the two phones'
randoms together, exchanged in hello; the side whose Game Center player ID sorts first
plays the left. The hello also carries the mode each side wants (`NetMessage.hello`'s `mode`);
the host's is played. A stage vote or pick crosses as the stage's raw value with the count of
stages played, and goes in, like a drink, only once every frame before the stop is
confirmed; a coin flip rolls on the shared dice, so both land the same. Protocol version 4. MULTIPLAYER opens Apple's matchmaker sheet for two, invites or
automatch; it fails at once until the app's record in App Store Connect has Game
Center on. The win screen's REMATCH waits for both; TITLE says bye. A disconnect
or a bye puts the title up with why under MULTIPLAYER. No computer, no reset, no
tuning pickers online; HITBOX stays. The sim calls nothing in the system's maths library: `Trig` is its own sine,
cosine and arctangent in plain arithmetic, so two phones on different iOS versions
get the same bits; the checksum would say otherwise.

Game Center needs the app's App ID to carry the Game Center capability
(`ProjectEsper.entitlements`, automatic signing adds it) and, for the matchmaker to
answer, the app record in App Store Connect with Game Center turned on.

## Queued

- Revisit the football field's helmets now that slopes exist: they may want a shaped
  outline like the cars' rather than a square.

- A "score" mode with three-point lines: a dim glowing arc in the background on each
  side, its peak touching the edge of the middle platform; a shot begun from behind
  the arc counts three. Not built; the note is the whole of it so far.
- Power-ups, including throw-button overrides.
