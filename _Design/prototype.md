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
  K to throw, shift as the left bumper, delete as the start button, M as the left trigger (the
  hitboxes), Esc quits on a Mac or in the simulator; the arrow keys move player 1 when the
  computer's off. The HUD is laid out in the phone's points and
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
  grounded holder's hands. It ends in a crouch if down is still held, into the run with the
  stick still held forward (as out of a dash; Frost Tea's ice slide too), or stands up into
  the run's skid to stop. A slide can catch a loose ball on the way, which is what it's
  for. Numbers on the body (`slideFrames`, `slideFriction`) and in `SlideRules`.
  A slide on a slope going down the way the body faces is forced (`Player.forcedSlide`, protocol
  31): the body speeds up to the burst (`SlopeRules.slideGain`) and rides the surface with no
  friction and no timer, and nothing gets out of it but a jump, which cancels it: no stick,
  shoot, throw, slash or snatch, Frost Tea's cancels included. It ends on flat ground, when the
  slide's own timer then finishes it, or in open air, off the slope's end. Up a slope it's the
  ordinary slide.
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
  Shoot pressed during a throw stance cancels the throw the same way, and jump cancels it into
  a jump (on the ground the jump squat; in the air the air's jump, if one is left), the throw
  button up before another stance. Protocol 16. On the ground, jump during the stance
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
- The change (`PlayerState.transforming`, `TransformRules`, protocol 44): throw and shoot together,
  from anything free, or within four frames of the stance, slash or snatch the first of them
  started (so the two a frame apart still do it), change the human form
  into the energy form; the same again in it changes straight back. Blazing Boba's level-two
  fireball keeps the two together where it's asked for. The change holds the body still where it
  is, gravity off, while `player_transform` (nine 48 pixel frames at ten a second, read straight
  from `Player_Transform.aseprite` by the importer, its `Layer 1` as `transform_eyes`) plays; then
  it's `transformed`. Parked: nobody has the change there to make (`transformReady` off, protocol 49); given it, it's shown by
  the zone's cycling colours round the line, and the head's and legs' cubes in the zone's colours,
  until it's made. As drawn: seven pixels up off the
  ground the whole change, the eyes over the body in the energy's colour, all white and glowing on
  frame 4 and the energy form from frame 5 (0-based); up to frame 4 cubes spiral up round the
  body (30 a second, 10 pixels out, at the head's cube size) and the head's and legs' cubes rise in a helix. The energy form
  is the look from before the human one (`Look.transformed`, `human: false`), but all of it in the
  energy's colour as the head is, no shoes, the back parts down its ramp as a human's back leg
  (0.66), glowing all over as the head does; the head apart, and cubes off the hands as off the legs; drawn as a player of its own
  (`SpriteLibrary.transformedPlayer`), warmed with the rest.
- Stepback: down on the ground in a shot's or a throw's stance, once a stance, pressed any time in
  it and coming once it has reached its hold (`shotWindupFrames`, `throwWindupFrames`): the throw sheet's third frame, sliding
  straight back 48 art pixels over 12 frames (`StepbackRules`), the facing kept, trailing
  afterimages in the colour's bright version, at 0.9, held a tenth of a second and fading over
  three, as Zeus Juice's bolt does (a jump out of the shooting stance and the throw leave the same; the slash leaves its blade's, not the body's), with the jump's sound; the whole way
  a counter, as the throw stance's parry frames are (out of a shot the air-with-ball sheet's last
  frame shows, out of a throw the throw sheet's third), and its ball can't be snatched, by Frost Tea's
  either. Then back in the stance at its hold, buttons kept, the aim cleared: the stick still down from the stepback aims nothing until it's let go and pressed again, so a quick shot or throw out of it goes off the preset, not down (`stepbackAimLocked`, protocol 33). Down never cancels a stance: the
  shot and the throw cancel each other (protocol 24); off an edge, it's the air, the stance gone.
- The rim's top is a thin platform that can't be stood on (`RimRules`): a body coming down on it
  from above is sent back up at 3.5 a frame, and a ball that isn't scoring bounces off it; nothing
  climbs it or drops through it, and a dunk hangs on it. A ball scores only if it was let go as a
  shot, a floater or a dunk (`Ball.scoring`), kept through its bounces off the board and walls,
  so a bank still drops; one thrown or knocked loose bounces off the top (protocol 25). The rim's
  art gives, the view's alone (`RimLook`): it turns about its back edge on the backboard as a damped
  spring, loose so it rings (stiffness 0.2, damping 0.08), kicked down 4° for every unit a frame
whatever lands on it came at, held down 12° while someone
  dunks on it with the dunker turning with it, and the net's top hanging from it and turning too.
  After Tiny Toon Adventures: ACME All-Stars (1994).
- Hit-stop: the whole match held, nothing moving or counting down, 4 frames when a hit lands
  (a strip, a pop, a snatch off a holder), 6 when a shot goes in, 10 on a counter
  (`HitStopRules`); a made point restarts after it, so the ball's held in the net. Protocol 22.
- Throw (without ball, in neutral or on defence): the snatch. The sheet's ten frames at
  15 a second, 40 sim frames, the hand out over sheet frames 2 and 3
  (`SnatchRules.activeSheetFrames`), the third sheet frame held twice as long, when its
  reach, the snatcher's body and the hand's catch ring at the spark's spot, takes any ball
  it touches while the body faces it, or the ball of a holder whose body it touches
  (`Player.snatchReaches`; every drink's snatch, the upgrades only adding what they do on a
  touch; protocol 21): a loose one at any speed, or
  the one in the other's hands, where the sheet draws it that frame (down on the floor
  below when it's dribbled over a drop, `Player.ballInHand`), or the holder's
  body itself, whichever way the snatcher faces while their bodies overlap. The last two
  sheet frames are left off. The catch spark shows on the hand on sheet frame 2.
  On the ground it carries the run or dash it came from, bleeding 0.15 a frame; in the
  air it drifts. Web Water keeps the web line on this button instead.
- Drop through: down held on the ground for 10 frames (`DropRules.holdFrames`), standing only
  on one-ways, falls through them; for 12 frames (`DropRules.passFrames`) one-ways don't hold
  the body. Solid ground never lets go. Protocol 15.
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
  at 15 a second, as the windup plays. Hold for the stance, stick picks a cardinal, release throws straight with no
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
  bleeding only 0.03 a frame, so a jump carries it to the rim. In the stance, from its
  fourth frame (`BallRules.dunkStanceFrames`, 3; protocol 17), with the chest within 25 units
  of a rim, wider than the basket, it's a dunk: the body turns to
  the backboard and glides to the dunk's place on the rim, `BallRules.dunkOffset` from
  its centre, 16 art pixels back and 24 down, mirrored across for the other rim, over the
  wind-up, there by the slam, so it never jumps into place. The dunk
  sheet plays from the throw stance's frame: the wind-up, the swing, the slam on the
  release frame, when the ball leaves the hand and drops through, then the hang, held
  through the 45 frames, each frame held twice as long as first cut (40 frames to the slam) before the point restarts. Each frame of it is drawn nudged by
  `DunkArt.offsets`, in art pixels, found with `DunkTuning` on: the match held, player 1
  on the right rim on the frame the DUNK FRAME slider picks, DUNK X and DUNK Y nudging
  that frame, the table in the corner readout. Kept per stage, each stage's hoop art its own (`DunkArt.courtOffsets`,
  `stadiumOffsets`); Longball Stadium's as placed: (-6, 10), (-4, 12), (-2, 16), (2, 1), (-3, 3),
  (-1, -1), (-1, -1); Wreck Center's start there, to be placed for the straight hoop, the tuning
  starting on it (`DunkTuning.stage`).
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
  from under counts once it falls back in. Going up through a rim never scores. It's the
  ball's bottom that has to come down through, so all of it was above the rim first: one thrown
  flat at the rim's height, off the backboard, drops out under it (protocol 18). The dunk lets
  go of it with its bottom just over the rim.

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
- Titan Tea (L). Jumps leave 1.25 times as fast (`Drinks.titanJumpShare`), and the dunk puts the
  feet off the rim at twice the offset and reaches twice as far, so the hands meet it. Twice the size: the body box, its reaches (the blade, the snatch, the
  slide's leg, the catch rings), the ledge hang and the heights the hands hold and let go
  of the ball at, all doubled, and drawn at double size. Heavier: half of any knock, and a
  fifth more gravity falling (not rising), fall speed and fast fall. It's stripped, the ball popping free, but
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
  Everything drawn off the body goes at its size too: the jump, dash, slide, wall and skid
  sparks, the double jump's rings, the head's and legs' cubes (`GameScene.bodyScale`). Its dunk
  is moved as a whole by `DunkArt.titanOffset`, (−5, −11), on top of each frame's, on TITAN DUNK X and Y with
  `DunkTuning` on.
- Gale Ale (M, a biomorph; protocol 63). Its tornados (`Gale`, `GaleRules`, `Match.gales`) are two
  thirds the Elements' tornado's height and a third wider, 40 by 20, drawn as its sheet squeezed
  the same way, and burst on its burst sheet at twice that; they don't glow. A double jump leaves
  a still one under the feet it jumped from, for two seconds (`stillFrames`, 120), that holds whoever
  comes into it out of the air and the loose ball as the Elements' do (the jumper let rise clear
  of it first, the tornado's jump-out cooldown); it never burns. Level two: the snatch, on its spark
  frame, sends one off from the spark the way it faces at 3 a frame, for four seconds at most; it
  strips the first other body it meets, takes the ball, theirs or loose, and carries it inside,
  and bursts on anything solid, the stage's invisible walls and the ball's own blockers included,
  or the world's edge, letting the ball go where it is.
- Z Tea (N, a biomorph; protocol 64). Its slash, with nothing in hand: on the ground, the beam's
  charge, a second (`ZRules.chargeFrames`, 60), committed: nothing but the jump calls it off
  (into the jump) and a hit stops it; then the beam fires half a second (30) from the hand, 400
  units along, 5 either side, and strips and knocks along it (5, lifted 1.5) the first other body
  it meets, sending the ball along it at 7, theirs or loose. Firing, it can't be stunned or knocked
  (`Player.knock`, `hitStun`). At level two up and down on the stick turn it, 2 degrees a frame at full
  tilt (`aimRate`), any angle up to 45 off level, through the charge and while it fires, the beam
  turning with it. The throw's charge swirl (`esper_charge`) plays at the hand through the
  charge, its tail as the beam fires. Drawn: `player_blast` at 12 a second: frame 0, frame 1 held through the charge and 2 as it ends;
  firing, 3 to 7 round and round with `player_blast_arms` over them, turned with the aim about where the
  arms meet the body (31.5, 33.5 up on its canvas, 17.5 over the feet), aligned on 3 and a pixel
  right and two down on the even frames, 4 and 6; after, 8 and 9 (`recoveryFrames`), no beam,
  no armour; the beam from the arms'
  reach (17 art pixels from the shoulder, 18 over the feet), `beam`'s tail, its middle stretched
  and its head, 16 pixels thick, in the energy colour, over a soft halo in the glow colour three times as thick at 0.5. In the air, the burst: its momentum braked, a 0.85 share kept
  a frame (`burstBrake`), not stopped, through `player_transform` at 10 a second, frame 2 held 24 frames more at level one, and on
  frame 3 everything within 64 art pixels (40) is pushed away, the other without a stun (5.5
  and a lift of 1) and the ball at 7; `burst` plays there in the energy colour at the reach's size.

Hits share the strip: the victim is stunned 60 frames, every button dead (the stick
too, when `StunRules.locksMovement` is on; it's parked off while a harder knockback is
tried), and any ball they hold pops free; the slide's leg stuns a body without the ball
too; the slash, the parry, the bolt, the burst and the pulse knock the body away as
well (`Player.knock`), and the pulse doesn't stun. The slash strips a body with or
without the ball, knocking it 4 along the swing and 2 up. The snatch has no
cooldown, as the slash has none, and meeting a live blade it's the parry: the slasher
is the one stripped and knocked back, the blade spent, resolved before the blades so it
always wins. The throw stance parries too, over its first ten frames (`ThrowParryRules`),
the body flashing white and its line the bright version of its colour: a slash meeting it strips the slasher and the thrower keeps the
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
series is over both go to the select before the drink. A stage that goes to its third point
starts that decider with the ball in neutral, loose where it starts, rather than in the hands of
whoever was just scored on (`Match.restartBallTo` nil when a point levels it, protocol 55).
Rectangles in a row, the stages not parked (`StageChoice.selectable`: The Wreck Center, Longball
Stadium, The Elements, Sky Net and Hoopfish Hideaway), the one under a cursor
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

A second mode (`GameMode.fortySeven`), on The Wreck Center or Hoopfish Hideaway (`StageChoice.fortySeven`,
picked on the stage select; on Hoopfish Hideaway, whose rim swims, the three-point radius is the plain
90 units round wherever it is, and its line isn't drawn: while the local player aims a shot, a
stretch of it 5 tiles long and 2 pixels thick shows round the rim toward them, clear at both ends
and their energy's colour in the middle, `drawSwimmingThreeLine`), no stage
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
- Gale Ale: the double jump's still tornado; level two adds the snatch's tornado that carries the ball off.
- Z Tea: the slash's beam on the ground and burst in the air; level two aims the beam and quickens the burst.

## Tuning pickers

Segmented pickers in the top-left corner change a stat live on both players. `Tuning.swift`
holds the variants; A is always the baseline as tuned. POWER's fourteen sit in two rows of seven.

- HEAD: how the detached head follows the body. Both close half the gap each frame. B,
  the default, leads sideways instead of trailing, the offset reversed across only.
- POWER, with LEVEL beside it (1 or 2): A none, B Web Water, C Super Smoothie, D Flash Fizz, E Platform Protein
  Shake, F Quake-Up Coffee, G Zeus Juice, H Frost Tea, I Blazing Boba, J Pulsepistol
  Punch, K Surf Soda, L Titan Tea, M Gale Ale, N Z Tea, at the level LEVEL picks, on this phone's player only, the
  other side keeping its drinks, with the body the power brings; A by default. The left bumper always steps POWER; the local side's power
  and level are lettered under the pickers.
- The field's goalposts, settled: the rims 107 high and 66 in from each wall, the posts
  60 in and drawn for a rim at 120, the gold 8 wide; the crossbar sits 20 below that,
  tilted 25° with the end toward the field up (on the CROSSBAR ANGLE debug slider there, the
  goalposts and backboards redrawn as it moves), the uprights 100 over it; the back rod
  and the crossbar with its uprights each have their own 1 black outline, as do the
  light panels.
- HITBOX, beside RESET, or a pad's left trigger (L2): draws the sim's boxes over the world. Bodies white (10 × 17.5 units, 16 × 28 art pixels), the loose
  ball purple, the two catch rings faint, the slide's leg and the slash's blade red, the
  snatch's reach green with the hand's ring while it's out, a flash's tear cyan.
- SFX: the sound words' face, DOT, CHERRY, CHOKO, REGGAE, YUSEI or EN (see Sound words).
- AI, beside that: the computer plays the other side, whatever pads are in. Off, the second
  pad or nothing does. The title's VS CPU / VS HUMAN toggle is the same switch, kept between launches;
  clicking a pad's right stick (R3) switches it too.

## Energy colours

Two palettes, as CardCourt has: `PixelPalette` (`_Graphic Assets/Pixel_Palette.png`,
AAP-64) for the world, `EsperPalette` for the interface. Seven energy colours to pick from
on the title, circles in its corner, the pick kept between launches (`EnergyColour`,
`esper.energyColour`): orange #FA6A0A, the default, teal #20D6C7, red #DF3E23, lime
#9CDB43, pink #BC4A9B, blue #285CC4 (palette 18, further from teal than 19) gold #F9A31B and purple #793A80 (palette 28), all AAP-64's; the body sprite's tone is the
colour lifted two fifths of the way to white. The loose ball, and the court's walls with nobody holding it, are the neutral colour, palette 40
#6D758D (`BallLook.neutral`); Wreck Center's middle ledge palette 39 #8B93AF, shaded as the tiles are; Surf
Soda's darker bubbles and its board's tail #403353; outlines drawn in code in the world
(the field's panels and goalposts, the opponent chevron, the round circles) #242234. The
sheets in `_Graphic Assets/Pixel Art` are recoloured to AAP-64's nearest by eye (CIE Lab),
alpha kept, by `Tools/recolour_to_palette.py`, which leaves two kinds alone: all-grey
sheets, the masks the energy colour tints, and the player sheets, which
`Tools/recolour_players.py` puts on twelve AAP-64 colours, one a part, the same in every sheet:
head #20D6C7, ball #FFFFFF, torso #FA6A0A and pelvis #BB7547, front thigh #FFD541 and leg
#FFFC40, back thigh #73172D and leg #B4202A (the thigh the darker, as the arms and front leg
go dark to light), front arm #59C135 and hand #9CDB43, back arm #793A80 and hand #BC4A9B; and the feet, the lower leg's last
third (from the user's walk: the foot starts 70% down from the knee), front #A6FCDB (palette
21) and back #E86A73 (26), drawn as shoes with the human look off, palette 22 #FFFFFF in front and 38 #B3B9D1 behind (`Look.frontShoe`, `backShoe`; `BodyPart.frontFoot`, `backFoot`;
the sheets as they were before the feet are in `Player Backup/Pre-Feet`);
the slash's pinks are left alone. Those are the part keys the game reads (`BodyPart`). The
GMS2 sheets are written as strips in Pixel Art, taking over the GMS2 sprites, and each sheet
as it was is kept in `Pixel Art/Player Backup`; the players' outline is `Look`'s, the palette's
#242234. Besides the silhouette, groups are lined where they lie over the rest of the body, each on
its own, front to back (`Look.strokedGroups`): the front arm and hand, the head (the
torso's and each shoe's own off for now) (the thighs as a group made a wedge where their line met the torso's); a pixel already lined is neither lined again nor counted as a
group's, so where two meet there's one line, on the later's pixels, and the earlier reads in
front: the torso over the legs, the head over all but the arms (the head apart from the body,
with the human look off, is its own sprite over everything). Each figure is one layer, the body, its line, head, energy,
cape, ball in hand and flashes, their depths packed under a tenth, so a whole body is in
front of or behind the other: in front, the one with the ball, else the last to touch it. An experiment, on (`HumanLook.enabled`; off puts it all back): the players drawn as
people, skin on the head, the arms and hands, the front in palette 35 #DBA463 and the back in 34
#BB7547, the torso, pelvis and front thigh palette 41 #4A5462 for everyone (`HumanLook.clothes`), the back thigh 42 #333941, the
lower legs and feet the energy's own colour, as the crown's grade is, the back ones at two
thirds of its brightness (`HumanLook.backLegShare`, 0.66; greyed, they barely glowed), and glowing as energy does
(`HumanLook.glowingParts`, left out of the glow's body mask with a per-frame glow mask, so
they take the plain threshold), as does the crown's grade where it's mostly energy; the head
drawn on the body rather than apart (no lag, no bob, no enlarging), outlined with it and not
glowing, its particles still rising off it; its top two thirds (`HumanLook.headEnergyShare`, on the HEAD GRADIENT debug
slider, every frame redrawn as it moves),
its line included, grades from the energy's colour at the crown down into the skin, leading
into them; the line there stays on the body in its grade. The outline is drawn as it is and never glowing, lifted off each frame onto its own white texture and
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
which the recolour took to pure white, drawn as painted. Each has an opposite: gold and teal,
red and lime, purple and pink, orange and blue. Each has a gem's name (`EnergyColour.name`):
Sapphire blue, Topaz orange, Ruby red, Amethyst purple, Quartz pink, Peridot lime, Tourmaline
teal, Citrine gold. Offline this phone's pick is player one and the other side teal,
or the pick's opposite if the pick is teal. Online the colour rides in the hello: the
host, player one, keeps theirs, and the other takes the opposite if they match. Any two
different colours can meet.

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

### Off the court

Everywhere but the court it was first taught on (`Opponent.readsStage`), it plays by a reading of
the stage (`OpponentTerrain.swift`, `OpponentStages.swift`):

- The stage read: every height a body stands at, by the stage's own collision, run together
  into surfaces (slopes stepping along them), and each tornado's middle; nothing under the lava
  counts. Then the moves between them (`Terrain.Link`): the full hop with the second jump at its
  top if short, walking off an edge (the second jump once it's fallen a way, or none), or down
  through a one-way; each tried with a copy of its body on the stage, and from 3 units either
  side of the takeoff, and kept only if all three land where they're for. Its jump is measured
  the same way, under water too. Read 1500 body frames at a time, over the countdown.
- Getting about (`go`): along a surface, or across the cheapest way of moves, walking to each
  takeoff and playing the move as it was tried; a move that fails 150 frames past what it
  should need is given up on for two seconds. The way is timed (`Terrain.route`, each move's
  frames from its try): a tornado on it only if it's up when it gets there, not sinking, rising or
  fire, and holds 30 frames more, so the chain through the Elements' tornados is set off on only
  when it can be finished; it's left from its middle, waiting for the pull there, 40 frames before
  it lets go. A move through another tornado on the way fails its try, as that one would catch it;
  drifting out of one isn't a way out, its edge only takes the body back. Out of a tornado into
  another with no plain hop, it also tries the stick held still a while before steering and the
  second jump held till it's dropped a little, those at a heavy cost so plain ways come first.
  With the ball over lava it only takes moves from a body's length in off an edge (`ballSafe`),
  each hop tried from there too, and backs off an edge it's dribbling at, the bounce would burn.
- The lava (`keepOffTheLava`): every input it sends is first played out with a copy of the body,
  the tornados holding and bursting as they will; one that ends in the lava is swapped for the
  nearest that doesn't, a jump or the stick another way. Stunned in a tornado it holds still,
  since the stick would drift it out. Over lava it doesn't lob. On the ground a walk is played
  out only a step, then let go, as it decides again every frame. Being crowded counts only when
  the other is on the side it's headed.
- Hazards (`dodgeHazards`): on the ground it steps out from under the lightning's line in its
  last 45 frames, and from under an icicle falling toward it or about to drop.
- Shots: a still rim's shot spots are found by trying shots, one place a frame, on the surfaces 25
  to 140 in front of it; a spot is a jump shot's if a shot off the floor won't go in. Every shot's
  flick is found by playing the shot out (a copy of the body through the rest of the stance, the
  jump, the release) and then the ball's own flight, the middle of the angles that go in.
- A rim that moves, Hoopfish Hideaway's, is followed ahead by stepping a copy of the Hoopfish: it
  shoots at where the rim will be, from under where it'll be in a second and a half, and only
  once a shot played out from there goes in (waiting for the rim to come round if none does,
  calling off a stance it can't finish), and from wherever it stands, checked every third frame,
  the moment one would; never dunks it; keeps the ball away from the other
  while it's off screen. The ball on the antenna is met where the fish will carry it, jumping in time.
- A loose ball is met where its stepped-ahead flight first comes in reach.
- Its plays that rush at the rim on the court (the dart, the jump over, being blocked) go by the
  next step of its way instead, which on the Elements can run away from the rim first.
- Longball's helmets: one coming from where it's headed it goes over, held still on the rise
  and across once clear of the top, rather than riding it back; one going its way it rides.

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
walls go white, fading back over 20 frames, and `score_strike` (thirteen 64 pixel frames, toned in the scorer's energy) erupts off the rim with it. Sparks and bolts play at 24 a second. Every sheet plays at a steady rate, sixty split evenly (7.5, 10, 12, 15, 20, 24, 30 or 60 a second), nothing between: the walk, run and crouch walk's speed-led cycles snap to the nearest (`Player.steady`; the run and dash at 24 at most), the throw's release and windup at 15, the air shot's release at 30, the dunk's slam frames 8 sim frames each (7.5), the double jump's rings aren't a sheet, Surf Soda's bubbles at 30. Stunned, the body and head flicker a dark shade of the energy colour. `ParticleLook.cubes` draws the head's fire as small 3D cubes, each tumbling on its own random axis (`cubeSpin` radians a second, `cubeSize` art pixels, 3, `cubeRate` a second off a head, half with a power's own, let go within `cubeSpread`
(5) art pixels of the crown's middle either way so they don't rise in one tail; the size and spread
on debug sliders with `cubeSliders`; stepping down with the squares' sizes), shaded as energy
in its colour, no face dark, the face to the light running toward white: one instanced Metal draw into the scene after SpriteKit, before the glow (borrowed from Project RingOut). The `esper_spark` frames (`ParticleLook.sprites`) are parked under it. A human's lower legs give off cubes of their own, in each leg's colour, from the leg's middle, the back leg's drawn behind the players (a silhouette of the bodies and their lines, drawn only on a frame with such a cube, keeps them out of wherever a body is): `legCubeSize` (2) and `legCubeSpread` (1) on the LEG CUBE sliders, `legCubeRate` (12) a second a leg. The jump spark and the dash's and slide's smoke, near-white on
their sheets, go through the ramp too, in the player's colour, but stop at the colour itself,
never lighter (`Look.sparkTone`), as the legs and the crown do; so do the wall spark and the
sheets' own energy, the skid's puffs, the slide's lines, the slash's blade. The catch spark,
the snatch's and the catch's, is toned in the player's colour on the paler ramp, a quarter
way to white at its lightest (`Look.energyTone`). A held throw shows the
charge, the swirl round the ball in hand at 30 a second and half its sheet's size: up to frame 67, then frames 35 to 67 round again for as long as the throw is held,
and when the throw is let go the frames after 67 play out where the ball was. Each player has a look with a team colour: orange for player 1, teal for player 2. The head
and the ball in hand are drawn in it, the ball's outline is in it, and so are the halo round
the ball (the ball itself is `Basketball`, three 8x8 frames painted as they are: cycling every 0.2 s in a dribbling hand, and loose it spins in the view only: backspin off a shot or a throw at 1.5 turns a second, kept through the air, half traded for the roll at a bounce, turning with its path when rolling, at most 4 turns a second) and the fire off the head. The body a light orange or a light teal toward the team colour, the back limbs a greyed,
darker version of it, a black line one pixel thick round the body following the outside
edge only, and the front arm stroked on its own where it lies over the body. The head is
split out of every frame and drawn as its own sprite with no line, trailing its place on
the body by a quarter of the gap each frame and bobbing a pixel, and its fire is released
into the world so it streams behind a moving head. The loose ball is purple, and from a shot, throw or dunk until its first bounce it's the colour
of whoever let it go, then shifts back over 30. A flying ball leaves a soft additive trail
in its colour. The library finds where the ball and the head sit in each frame so the halo
and the fire follow them. The head is drawn at 1.25 times about its own centre and lifted a pixel off the body. Three dim
yellow chevrons stack over a resting ball and light one after another from the top; over the
basket the holder scores on, the top one `ChevronTuning.basketLift` (18) art pixels over the rim, on
the BASKET CHEVRON Y debug slider. A
double jump leaves a short platform of loose digital squares under the feet where it was
taken; they hang a moment, then drop away and cut out. The head bits rise in a tight column that a steady push bends toward the ball along x, as a whole (`ParticleLook.flowSpeed`, 140, easing off within 6 pixels of level with it, as with the ball in hand); the legs' cubes go the same way.
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
the pulse is a bar from the hand to the edge; ice clones are the body's frame in ice, one left in the air any frame of the jump or double jump at random;
flames loop `fire_trail`; fireballs are the ball in fire; frozen bodies and ice clones are
drawn in the ice look (`Look.ice`: the front parts, the head and the torso's light in palette 57,
the back parts and the torso's shadow, the pelvis, in 49, outlined in 22; `SpriteLibrary.icePlayer`, warmed
with the rest), the clones at 0.8; a frozen ball, loose or in hand, is `basketball_ice`, with no halo, so no glow, and holds its turn; the cape is seven short rectangles chained along the glide's trail with a wave down
its length.

### Sound words

Manga sound effects over the action, Jump Ultimate Stars style (`View/Onomatopoeia.swift`), all
katakana or all English by the SFX picker, never mixed. Its options are the kana faces DOT
(DotGothic16, the default), CHERRY (Cherry Bomb One), CHOKO (Chokokutai), REGGAE (Reggae One)
and YUSEI (Yusei Magic), and EN (Dirty Brush); kept between launches, and a pick pops a sample
in the middle of the screen. The fonts are bundled in `Art/Fonts/` and registered with the
process on first use; each face is centred and sized by its own ド or D. Dirty Brush has no "!",
so English marks are brushed wedges; the Japanese are the faces' full-width ones. Each letter
grows along the word to 1.35x, rocks ±7° and bobs in turn, outlined in palette 29 and dropped
south-east, its fill split at its own middle. The word pops from 0.3 through 1.15 to 1 while a
warp grid flares it (near end squeezed, far end spread, middle arched), holds 0.5s, then rises
and fades. The words never glow: the mask draws them flat, warp and all.

A word stays off the action as JUS's do: of a list of spots round what made it, 10 art pixels
clear, it takes the first that covers least of the bodies, the loose ball and the other words,
kept on screen. For an event the list runs off to the side it flares and up, straight up, the
other side and up, level either side, higher, then below; for a basket, beside the net
courtward, then up or down that side, leaving the rim's top to the 2X. A word flares and tilts
away from whoever caused it.

| | JP | EN |
|---|---|---|
| Basket, confirmed, beside the net toward the court | パサッ！ | SWISH! |
| Three | ザシュッ！！ | SWOOSH!! |
| Dunk | ドガァン！！ | SLAM!! |
| Body hit | ドゴッ！ | WHAM! |
| Ball knocked loose | バシッ！ | SMACK! |
| Ball slashed | バチィン！ | THWACK! |
| Parry | キィン！ | TING! |
| Slash on a wall | ガキン | CLANG |
| Wall jump | キュッ | SQUEAK |
| Z Tea's beam / burst | ズドドドド / ドオォン！ | VWOOOM / BOOOM! |
| Quake | ゴゴゴゴ | RUMBLE |
| Freeze | ピキッ！ | CRACK! |
| Fireball bursts | ドカーン！ | KABOOM! |
| Lava burns, balls in lava | ジュウゥ | SIZZLE |
| Icicles | パリーン | CRASH |
| Lightning | バリバリッ | KRAKOOM! |

## Highway Traffic

Parked: off the stage select (`StageChoice.selectable`), its code kept.

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
  comes off the match's dice, a different set each match, so both phones agree with nothing sent.
  A player whose start is inside a car starts on its roof instead (`Match.spawnPoint`), at the
  match's start, after a point and after a burn. The road's side walls aren't drawn, so they're
  nothing to land on (`tileWallsHold` off; protocol 47). Each has its own
  length in tiles and its height the drawing's own; it's solid in blocks of eight art
  pixels (`Vehicle.blocks`), each column's unbroken runs one box, mirrored when it faces
  left. The blocks are set by hand in the bounds gallery (the BOUNDS picker, offline): the
  vehicle blown up with see-through blocks over it, a tap going round a block's kinds
  (solid, a slope rising to the right, one falling to the right, open), RESET goes back to the
  measured outline, COPY puts the table on the clipboard as Swift for `Vehicle.set`.
  Edits are kept between launches and stand in live until they're pasted in. A car's slope
  blocks are solid blocks for now (`Car.slopesActive` off): as five-unit slopes they let bodies
  sink into the car and stick there.
  The slopes (`Stage.slopes`, `SlopeRules`) are 45° and can't be clung to or jumped off: a block whose face abuts a slope is its fill, never a wall (`Stage.wall(beside:)`), solid under the diagonal and along
  their two straight sides: the body rides one up and down at the flat pace along the
  surface (the step is scaled by `SlopeRules.diagonal`, so no speed-up), its lead edge's
  ground read ahead so it climbs either way and onto the block a slope ends in, the
  ground snapped to on the way down so a descent never leaves it; standing, crouching
  and uncrouching on one work like on the flat; standing still
  on one, a body stays put; its straight side is a wall and there's no clinging to it;
  the ball bounces off the diagonal, the push into it turned back and a share kept, and
  rolls down it. Nothing harms a car (protocol 46).
- The drawings: `Tools/split_vehicles.py` splits each vector into its body and its wheels
  (a wheel is a top-level group starting at a tyre, as the artist grouped them in an Affinity
  export, whose DPI scale comes off; else a tyre's circle through its hub's bolts), and the helicopter into its hull,
  top rotor and tail rotor, each plain and its three reds, as imagesets in the catalog's
  Traffic folder; every vehicle's wheels now come apart.
  A body shivers a pixel under wheels drawn over it that stay put, each on its own beat, dips three
  pixels on its springs when someone lands on it. Each part is lined round a game pixel thick in
  the palette's outline (`HighwayArt.outline`), the line just under its own part.
- The helicopter draws under the backboard, net and rim it carries. A net whose rim jumps
  (more than 40 pixels in a frame, as one does coming on from where it was parked) comes with it
  whole rather than stretching after it.
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
jump shot, or a jump off a helmet to dunk or shoot. Its end walls can't be landed on, so
there's no wall jump off them (`StageFeatures.tileWallsHold`); a helmet can be (protocol 20). The computer always takes the jump
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
  in their colours. A Titan in a helmet's way isn't pushed: the helmet breaks on them, as at the
  far wall; riding one is the same for everyone.
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
  sizes. It's parked, hidden, until performance is being diagnosed (`GameScene.diagnosingPerformance`).
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
- The backboard: behind each rim a cluster of `flashspark2` in the guarding side's
  energy, 3 across, its bottom where the first 3 by 4 board's was (24 over the rim, its middle),
  and as many rows up from there as reach the uprights' tops, each on its own frame so the board shimmers, on a grid sheared to the
  crossbar's lean and angle, 10 behind the rim, at 0.4, at two thirds; the stands, sky, rails
  and lights show (`GoalpostTuning.sceneryHidden` off; on, they go under flat black so tuning
  sliders read);
  solid to the ball, a 20-unit-tall box (`FieldRules.backboardOffset`, `ballBlockers`)
  from the backboard's face all the way back to the end wall, so nothing gets behind it.
  Platform Protein Shake's slabs and walls are the same flash clusters, filling their box
  in the maker's energy.
- A global stage rule: the invisible bounds outside a stage's grid are never a wall to land on or
  jump off (`Stage.wall(beside:)`, protocol 36).
- A ball held up at a slope's foot, on the corner of the block under the slope above it, is
  tipped on down the slope under its middle, not parked there.
- A loose ball rolling on the floor loses 3% of its speed a frame and 0.01 more
  (`BallRules.rollingFriction`, `rollingDrag`), easing down to a stop at zero rather than snapping
  to rest.
- The camera on a scrolling stage (Longball, the Elements) glides after the local player, led
  by where they're heading (20 frames of their speed, the lead itself eased 5% a frame so a
  speed that keeps flipping doesn't shake it), 8% of the way there a frame, held inside
  the stage's ends; each round it starts on the local player.
  The view takes in the stage's height and the turf below the floor. When the ball is off
  the screen sideways, its chevrons sit at that edge at its height, pointing at it, purple
  outlined in dark purple. The opponent off the screen likewise: one chevron in their
  energy, outlined in black, at that edge, at their chest's height. All of
  it is the view; the sim never sees the camera, so it's safe online.

## The Elements

`Stage.elements`, The Elements on the stage select (a working title): 67 by 24 tiles, two
Wreck Centers across less a column, so there's a middle one, and 24 high (a large stage's most: lava to the ceiling of icicles, all of it on screen at 3x on a phone), zoomed by whole pixels to fit its height (3x on a phone, 5x on the iPad) and scrolling sideways on the same gliding camera as Longball, the lava the bottom row. A screen taller than that shows its spare rows split above and below: the lava's orange (palette 6) on down under it, the ceiling rock's inner colour (palette 30, #242234) on up over it, neither glowing. Palette 17 flat behind everything (showing up the shafts above the ceiling too), which never glows
(the glow's bright pass leaves out that exact colour), `mountains_bkg` stretched over the stage in front of
it, a bed of lava along the bottom (`lava`, eight 48 pixel frames, each strip a step further
through them, three tiles high) and, in front of both, the tiles of a hand-made map, each a 16
by 16 cell of `tileset_elements` (`Pixel Art/Stages/Elements`; the importer's `STAGE_ART` and
`ROOT_IMAGES`; the ceiling is lined with `icicle_empty` sockets, 32 across and side by side, and
`tornado` (eight 48 by 48 frames, twelve a second) is a whole sprite the map maker places, three
tiles across and three up from the cell its base's middle is in (see the tornados below); re-run the importer after changing the sheet, which can be any number of cells
across and down, its drawn cells read off it, though `StageMap.decoration` and a saved map
name cells by place, so tiles are added at the end or in the empty cells). The sides and the floor are the world's edge. Every tile of the map is solid,
bar the tileset's flecks (`StageMap.decoration`), drawn but with nothing to stand on. Hoops
are the straight-on pair, the court's placements.

The baked map (`StageMap.baked`, protocol 37, `bakedVersion` 4) is laid out by hand: the left side and the middle
platform the ball starts on drawn, the ceiling along the top, and the right side generated
from the left, tile for tile, each the tile opposite it in its piece of the tileset (a slope's
left tile for its right; the V's two halves swap). The middle platform is 11 across, columns 28
to 38, centred on the middle column, 33, where the ball starts.

None of the stage's art glows but the lava: the tiles, the mountains and the icicles are drawn once
into the glow's mask in green under the bodies (`MaskScene.syncStatic`), redone only when the map
changes; the flat background colour still lifts a little. The tornados and their overlays are drawn into it each frame as they animate, the part above the lava only.

The ceiling's icicles (`Stage.icicleSockets`, `IcicleRules`, `Match.icicles`) leave out columns 16
and under and their mirror, 50 and over. Every two seconds a socket picked by the count, the same on
both phones, grows an icicle if it's empty (`icicle_form`, six 32 by 48 frames at 15 a second),
then, grown, holds two to five seconds as the empty socket with `icicle`'s first frame hanging
behind it, which wiggles 6 degrees either way, a swing every 6 frames, about its top middle for the
last 40 frames before the drop; then drops it: `icicle`'s first frame (four 32 pixel
frames) falls as the ball does, from rest, and shatters on the first ground under it, rock, a
slope or the lava, or on whoever it meets, the other three frames playing there. Whoever it meets is
stripped and frozen; Frost Tea it only shatters on. Protocol 43.
Over each gap in the ceiling's row a shaft runs up through the sky (`Stage.fixedExtras`: the sky
above the ceiling is solid but for them, up to its top), walled in rock edges drawn on up through
a taller screen's spare rows (the tileset's (5, 3) on its left, (1, 3) on its right). The players
start in the air in the two shafts, columns 12 to 14 and 52 to 54, row 29, a few tiles above the
screen, and drop in, as they do again when burned. Nothing in a shaft, from just under the
ceiling up, is a wall to land on or jump off (`Stage.chutes`). They land on slide slopes (`Kind.slideLowerRight`,
`slideLowerLeft`, orange in the map maker's walls mode): nobody stands or walks up one. On one,
anything on the ground turns downhill into the forced slide; held uphill, the body walks up it
facing uphill but is carried back down at a quarter of walking speed
(`SlopeRules.slideSlopePushBack`), as up a down escalator, and let go it turns round and slides.

The tornados (`Stage.tornados`, `TornadoRules`, `Match.tornadoBoxes`): up for three seconds, then
bursting where they stand (`tornado_burst`, `fire_tornado_burst`, ten 96 pixel frames at full size,
centred on the tornado, at fifteen a second, as the tornados play), holding and burning nothing from the burst's
first frame, gone a second, and half a second rising back up out of the lava to their places,
over and over, all together; every fourth to come up is `fire_tornado`, which burns
whoever it touches as the lava does. A regular one that's up or rising takes whoever comes into it out of
the air (`PlayerState.suspended`), jumps back to full, and holds them, their middle drawn to its
middle 15% of the way a frame, gravity off, in the falling frame, the stick drifting them
sideways at a quarter of the air's drift (`TornadoRules.driftShare`), out if held; drawn hovering
round a 3 pixel circle counter-clockwise, as Smoothie's flight hovers, and the tornados hover
round one too (`ElementsArt.hoverRadius`); Blazing Boba is held by a fire one as by a regular one; from it they can shoot, throw,
snatch or slash as in Super Smoothie's flight, and jump is a full hop out, after which no tornado
takes them for half a second. Bursting, it lets them go. It takes the loose ball the same way,
coming in from outside (not one let go of inside it, as a shot from a body held there), and holds
it at its middle until it bursts. Each tornado is drawn behind the lava, so
it sinks into it, and again over the players at 33% (`ElementsArt.tornadoOverlayAlpha`), cropped to
above the lava.

Falling into the lava, a body or the ball, plays `fire_hit` and three sheets at the surface where it
went in, `lava_splash` on top (15 a second), `sizzle1` or `sizzle2` by a coin flip under it (15 a
second), and `explosion` under that (24 a second), all at half size, a quarter for the ball, the
splash at twice the others'. Burned
by a fire tornado, the same at the body's middle but the splash (`MatchEvent.tornadoBurned`).

The fireball (`Match.stageFireball`, `StageFireballRules`, `fireball`, four 16 pixel frames at 15 a
second): every five seconds one rises out of the lava two tiles short of the leftmost tornado and
takes two and a half seconds along a smooth curve through every tornado's middle to two tiles past
the rightmost and back under, each pass the other way from the last, first left to right, the sprite
(drawn pointing right) turned to its path. It strips whoever it touches, knocked its way and coasting
on it 20 frames before the stick has them again (`StageFireballRules.knockCoastFrames`), and bursts
(`fire_explosion`, `fire_hit`), gone for the rest of the pass; on Blazing Boba it only bursts.
It's drawn only above the lava's drawn surface (`ElementsArt.lavaSurfaceLine`, 32 pixels up, under
its crests), and coming out of it and going under it plays `lava_splash` there. A body
knocked out of a tornado, by anything, isn't taken straight back.

The nets flow leftward in the wind, in gusts (`HoopNet.wind`: 0.4 pixels a frame at the bottom,
easing to none at the rim, 70 to 100% as it gusts). The wind (`wind`, nine 32 pixel frames at ten a second): a puff about every third of a second in each
of two layers, behind the rock and in front of everything, each at 1, 0.75 or 0.5, starting
anywhere on screen and blowing 64 to 160 pixels leftward as it plays through, fading out; none of it
glows. On this stage the head's and legs' particles blow leftward rather than toward the ball.
The rain: streaks 2 to 5 pixels long at 45 degrees, falling from the top right to the bottom left,
in palette 48 or 22 at any strength from 0.2 up, not glowing, stopping at the lava's drawn surface.
Thousands, drawn as two textures made once (256 pixel tiles, 260 and 200 streaks times RAIN DENSITY,
0 to 4 on the debug panel there, 0.5 unless moved, kept between launches, `RainTuning`), each tiled over the screen and slid along, 240 and 360
pixels a second, whole pixels. It's the world's topmost layer (z 90, under the HUD), room left under it.
The rain splashes (`splash`, seven 48 pixel frames at 15 a second, half size, over the players)
about 24 times a second at random on screen: on any open top of rock under the ceiling, and on the left
side's slopes, turned to lie on them; never on the right side's slopes. On the lava it sizzles 20 times a second, `sizzle1` or `sizzle2` at a
quarter size, anywhere along its surface on screen.

Surf Soda rides the lava as ground (the sim gives that body a floor at the lava's surface), and
surfs the slide slopes rather than sliding: down them on the board at its run unless the stick
takes it up them, which it can.

Under it all plays `thunderstorm`, low (0.2), looped (`Ambience`): the first five minutes of
`_Sound FX/thunderstorm.mp3`, faded in and out four seconds at each end, as AAC
(`Tools/import_ambience.py`; `import_sounds.py` leaves it alone).

The lightning (`LightningRules`, `Match.lightningWarning`): every ten seconds the screen flashes
white (0.6, fading over 0.3 seconds, over everything but the rain), a column of palette 22 dots
floats slowly up from where it'll strike, and two seconds after the flash `small_lightning` (eight
32 by 96 frames at 15 a second, standing on its frame's bottom) strikes there: an open top of rock under no ceiling, picked by the
flash's count, the same on both phones. Whoever its line touches, up from the rock, is stripped,
but Zeus Juice. None of it glows.

Protocol 42.

The map's walls (`StageMap.walls`) are kept apart from the art: by default a block under
every solid tile, or as painted in the map maker's walls mode, each cell a block or a slope by
where its solid half lies, the lower right or left (a floor slope, `Stage.fixedSlopes`) or the
upper right or left (a ceiling slope, `Stage.ceilingSlopes`: solid above a diagonal, its flat top
a floor, its underside stopping a head where it comes down, its straight side a wall). A ball
takes a ceiling slope as its whole square.

The lava: whoever's feet go under its surface (`ElementsRules.lavaSurface`, 25 units) is put
back where they started, any ball they held back at the ball's start, and a loose ball in it
too. For now (protocol 27). A dribble that bounces down off a ledge into the lava, on the
dribble's bounce frame with the ball hanging past the edge over it, loses the ball to it the same
way (`Match.burnDribbles`, protocol 62).

The map is `StageMap`: the placed tiles by cell, the two rims (backboard on the left and on
the right; build a rock block behind each), the two starts (the cell their feet stand at the
bottom of) and the ball's. `StageMap.baked` is what every phone plays, online included; a
map kept by the map maker stands in for it offline only (`SavedStageMap`), unless a newer
map has been baked since (`StageMap.bakedVersion`, up by one with each bake), when it's put
aside under `esper.elementsMap.beforeBake` and the baked one shows. The map maker
(`MapEditor`, for a mouse; not on the TV) is the MAP picker on the debug panel, on this stage
offline: the match held still, the camera zoomed out to the whole stage at once (as big as it fits, not by whole pixels; back to play's zoom on close), a grid over the stage, a small panel in the upper right corner
with the tileset. Drag a tile
from the panel onto the stage to drop it, and with a tile chosen press an empty cell and drag
to paint; press a placed tile to pick it up and drop it elsewhere, or back on the panel to take
it away. ERASE, TORNADO, the rims, P1, P2 and BALL are picked from the button rows and dropped the same
way (press a marker to move it). UNDO steps back, RESET returns to the baked map, HIDE or
PALETTE shows or hides the tileset, COPY puts the map on the clipboard as Swift for
`StageMap.defaultMap`, and CLOSE restarts the round on the new map. Edits are kept between
launches. WALLS puts it in walls mode (TILES to come back): the walls, apart from the art, drawn as
transparent red over the stage, and the tool row is the wall kinds: SOLID, the four slopes by where
their solid half lies (◢ ◣ ◥ ◤) and OPEN. Press a cell and drag to lay the chosen kind; pressing a
cell that already has it opens it, and the stroke opens cells instead. In the tile mode a tile
placed brings a solid wall with it where there's none, and one taken off takes a solid wall,
never a painted slope.

## Hoopfish Hideaway

`Stage.wetshot`, `StageChoice.wetshotWake`: 37 by 19 tiles, under water, zoomed to the screen's width (not by
whole pixels), its bottom on the screen's: a phone crops blank water off the top (about two rows),
a squarer screen shows more water over it,
laid out in the map maker like the Elements (`MapStage.wetshot`, `StageMap.current[.wetshot]`,
kept offline under `esper.wetshotMap`; its first map a floor along the bottom row, the
Hoopfish over the middle). Its first name, Wetshot Wake, and Hoopfish Harbor are kept for later
(`_Design/notes.md`). Drawn: `Background_v2.png` (592 by 272, `WetshotBackground`) a row up
off the floor's row, which is palette 1 as is everything below it, everything over it the
water's top colour (palette 19), neither glowing; over the background the pile of backboards and
hoops the Hoopfish has collected (`StageMap.pile`, `WetshotArt.pilePicture`), drawn as one picture
at 75%, then `Foreground.png` (`WetshotForeground`) in the background's place, both behind
everything that moves and neither glowing. The pile's pieces, the three frames each of
`Backboards.png` and `hoops.png` (48 pixel cells, stage strips), are put down in the map maker anywhere, on the nearest whole art pixel
rather than the grid, picked up and moved with the piece tool in hand, erased with ERASE; two
TURN sliders under the props turn the newest piece and the one before it, whole degrees either
way to 180; the pile as laid out is baked into the stage's map; COPY, for now, puts each piece's kind, x, y and turn on the pasteboard instead of the
map's source;
then the map's props (`StageMap.Prop`, placed by their bottom left cell): `Plant 1` to `5`, the
two halves of `Rocks.png` (the top one first), and the Hoopfish, assembled back to front from
`topfin`, `tailfin`, `body`, `antenna` and `frontfin` with `hoop_straight` over its leftmost 48 pixels, 10
up. None of it glows, nor the background colour. The props come in through the importer's
`ROOT_IMAGES`.

The Hoopfish (`Hoopfish.swift`, `HoopfishRules`, `Match.hoopfish`) swims. It starts where
the map puts it with the ball on its antenna, no rim out, and swims off the side it faces (left) at
its crossing speed. The ball stays on it, crossing after crossing, until a hand takes it off. Two
seconds off screen, it comes back from that side turned round, from a height to a height off the
count (the same on both phones), ten seconds across from wholly off one side to wholly off the
other, swaying 30 units up and down one and a quarter times as it goes, slowly, its bottom kept between the
twelfth row from the top and as high as its three rows fit, over and over. What's on its antenna
changes only off screen: once the ball's been taken, the stage's rim from then on, turned with it.
The ball hangs on the antenna at its own point, 24 across and 24 up (`WetshotRules.ballPixelsAcross`/`Up`,
on BALL X and BALL Y offline); a stage's decider puts it back there. As drawn: the body breathing between 0.9 and 1.1 over two seconds, the fins swinging
out to 10 degrees and back over a second and a half (the top one clockwise), the tail one the
whole arc, 10 either way, the front one the whole arc, 15 either way, rising as it swings away from
level to 2 whole pixels at either end (`WetshotArt.frontFinLift`), the antenna, and the rim, net and ball on it, nodding 5
degrees either way over two seconds, the ball's glow there coming and going between none and 90%
over two seconds, still while someone dunks (and a rim swimming off the stage,
or gone, lets go of whoever hangs on it); each turning where it meets the
body (`WetshotArt.hoopfishParts`). Its rim and net glow, and so do its red rings and eye (left out of the
body's mask, `WetshotArt.bodyGlowMask`), the background's no-glow under them let through: drawn
pure blue in the mask over it (`MaskScene`'s `through`, under the fish's flats, and `throughFront`
and the net strands over them; `GameScene.glowThroughSnapshots`, `glowThroughFrontSnapshots`,
`glowThroughNets`), where the bright pass undoes the water's tint, so they glow in their own colours,
not the tinted ones. The rings are a single art pixel wide: any blue in the half-size mask counts,
and the brightest of the four full-size pixels under it is taken. The rest of it doesn't.

No dunking the Hoopfish (protocol 61): a dunk on it plays to its slam, the dunk sheet's third
frame, then the fish spins, `Hoopfish_spin` (eight 96 by 48 frames at 15 a second,
`HoopfishRules.spinFrames` 32, imported as a stage strip), its parts hidden and the rim's own
art and net with them, the rim out of play throughout (`Hoopfish.spin`), and the ball drops
from the dunker's hands, no point, the dunker let go into the air (`MatchEvent.hoopfishSpun`).
Bubbles burst all round it as it spins, some over it, and trail off its tail as it swims
(`WetshotArt.tailTip`, 10 a second). In 47, points here are worth double (`StageFeatures.doublePoints`),
a basket's points doubled; a best of seven's rounds stay one a basket. In 47, play on the stage starts with "Points Are Worth Double!" in the drink banner's
lettering, and each basket throws "2X" over the rim in CardCourt's 2X lettering (Avenir Next
Condensed Heavy, `TitleText.markTexture`) in palette 7 over 20, outlined 29, from a tenth of its
size up to its own over 0.3 seconds, held 1.2, then out to 1.2 as it fades over 0.5. A rim can't be dunked on in the stage's first or last column, and one swimming into either
lets go of whoever hangs on it (`Stage.dunkable`, protocol 59). A body bouncing off the rim's top
rises half as high as it would under water elsewhere (`RimRules.underwaterBounceShare`, the push
at the square root of a half; protocol 60). The ball's and the hoop's chevrons and the swimming
three-point line draw over the water's tint, not under it. No chevrons point at the ball off
screen here: off screen it's only ever on the antenna. The plants sway 5 degrees either way over four
seconds, each on its own beat, from their bottom middle. It carries the stage's one rim (`Hoop.shared`): both players score on it, the point
to whoever put the ball through (`ball.lastTouched`), protocol 48. For 20 frames after any point no
other counts (`BallRules.scoreLockoutFrames`): a rim on the move can take the same ball through twice. Its centre is 15 pixels across
(mirrored when it faces right) and 24 up from the Hoopfish's bottom left (`WetshotRules.rimFromHoopfish`), across on the
HOOP X debug slider offline, a whole pixel at a time, rim, art and net together; there's no
backboard. There's only ever one Hoopfish. Each of its parts will be animated, to be detailed.

The map maker here has the props in its panel in place of a tileset: pick one and press a cell
to place it, or drag it on; press a placed one to pick it up, drop it on the panel to take it
away, or ERASE it. The markers are P1, P2 and BALL. Walls are painted as on the Elements, with one-ways too (`Kind.oneWay`, a bar along the cell's top), on any map.

Bubbles rise around the screen, eight a second (three in ten over the players and the props, twice
the size), and off the feet of whoever's coming down, twelve a second, a quarter of the time three to six together,
each one of the first five cells of `bubbles_jellyfish` (cell 0 about as often as two of the
rest together), wobbling a pixel or three side to side and fading over two to four seconds.
One group at a time, six to twelve seconds after the last has gone, one to three jellyfish (cell 5) drift across from one side of the
screen to the other, bobbing slowly, breathing between 0.9 and 1.1 over two and a half seconds, turned to face the way they drift.

Under water (`StageFeatures.underwater`, protocol 58): gravity and the fall speeds are halved for
bodies and the ball, but a body rising pulls at an eighth, so a jump at half its push goes twice
as high, slowly; the jumps, the ground's and the air's speeds and every change of speed (the
pick-ups, the brakes, the frictions, the ball's roll) halved too, the ball's turning in the view halved, and every state's clock holds every other frame,
so each state, and its sheet with it, runs at half speed; the walk and run cycles too.
Over everything in the world, under the HUD, the water: palette 18 at the screen's bottom to 19
at its top (the energy cubes, drawn apart, tinted to match in their shader), at 33% (WATER TINT on the debug panel offline). And the whole screen sways, each row a
game pixel and a half side to side in three waves down the screen (WATER SWAY), in the glow's composite
(`GameScene.screenWave`), but not in the map maker, nor across the score's band at the top. The floor's fill doesn't glow either.

## Sky Net

`StageChoice.skyNet`, on the select: to be detailed; the court for now.

## Court

The Wreck Center on the stage select, and the default. Its backboard blocks are rows 8 and 9, and
the rims hang off them a tile under their top, lowered 6, at 84 (`Stage.courtRimDrop`; protocol 19);
RIM DEPTH (`Stage.courtRimDepth`, 0; protocol 23; no more than 5, as near as the rim can sit
and a ball at its centre still clear the block, a ball's radius off its face) slides each toward its block while `DunkTuning` holds a
body hung on the right rim, the hang and the hoop's art coming with them. Below
the floor's row everything is the outline black, #242234. Every stage's hoops are two layers on one 48-pixel canvas,
drawn to the players' scale and kept together as drawn, all under the bodies: `backboard`, then
the net, then `hoop`, the rim (`Pixel Art/Stages`, the importer's `STAGE_ART`, over the old
one-piece `Hoop.png`); Wreck Center's are drawn straight on, `backboard_straight` and
`hoop_straight` (`HoopTuning.art`), placed 5 art pixels out from the backboard and 10 up from the rim's point
(`HoopTuning.courtOffset`, and Longball Stadium's own `stadiumOffset`, (0, 10), on HOOP X and Y with `DunkTuning` on
for the stage picked, the net's NET X and Y kept per stage the same way, on top of where the stage's
hoop art has moved from the court's, and its shape on the NET
sliders there too, as on the UI tuning panel, and on Longball Stadium with tuning off as well; the held match starts on `DunkTuning.stage`, Longball
Stadium, since it can't reach the stage select), both kept out of the glow
(the mask marks them, as it does the banner). The rim is to get twitch physics. With twelve or so
debug sliders on at once they sit eight to a column;
the net is a cylinder of chevron rings drawn by the Metal layer (`CylinderNet`,
`NetTuning.cylinder`): NET RINGS (7) rings NET ROWS apart, each NET AROUND (9) chevrons round,
its radius from NET RADIUS TOP (7.5) to NET RADIUS BOTTOM (4.5) and its chevrons from NET TOP to
NET BOTTOM, alternate rings turned half a chevron into diamonds, the whole turned about its top
by NET TILT X (−20°), TURN Y and ROLL Z (0), mirrored on a left backboard; each stroke a box a pixel
thick through the cube renderer, glowing, left out wherever a body or a rim's art is drawn, so
it hangs behind the players and the rim and over the backboard; each ring swaying twice as far as its row of
the flat net's cloth (`NetTuning.swayShare`), and widening twice as far as the row spreads, so a
ball through the middle, which spreads a row both ways, opens it; the cloth runs unseen. A made
shot's swish moves it across three times as far again, fading over the swish's 40 frames
(`NetTuning.swishShare`). While someone hangs on a rim its net flares out at the bottom like a
lampshade, the bottom ring's radius out to 12 (`NetTuning.dunkFlareRadius`) over 10 frames and
easing back after. The sliders are in the match with the tuning on, and on
Longball Stadium; what they set is saved, and `NetTuning.bakedVersion` going up drops every saved
net value once at launch, so the values baked in come back. The flat net underneath, and with the cylinder off, is `HoopNet`: 5 straight columns of 7 downward chevrons hung from the rim, NET SPREAD
(3) art pixels apart across and NET ROWS (2, in quarters) apart down, each strand from the second row down leaning NET WEAVE (0.25) of
the way to the neighbour it's knotted to on that row, toward the right-hand one on one row and
the left-hand one on the next, an edge strand with no one that side hanging straight, so the
chevrons run in diagonals both ways, diamonds with knots; NET TAPER (0.5) narrows it toward the
bottom; NET SKEW (−0.25) raises each column that many art pixels over the one before, toward
the backboard, to match its angle; each chevron smaller than the one
above, from NET TOP (×1) at the rim to NET BOTTOM (×0.25) at the bottom (a chevron is 2.25
across and 1.5 deep at ×1, 1 thick), the whole net moved from the rim's point by NET X and
NET Y (0, −5 on the court, −1, −5 on Longball Stadium, then moved as far as its hoop art is from
`HoopTuning.netReference`, (5, 10); x mirrored on a left backboard, as the hoop's art is); the sliders are on the
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
a steady push toward the ball along x; a single-frame one (a snowflake, or the squares with
`ParticleLook.sprites` off) steps down in size instead. The double jump throws three oval rings of
energy under the feet (14 by 4 art pixels, a line thick), one every 0.06 seconds, each widening
to 2.5 times as it fades over 0.3; Blazing Boba's head burns `fire_particle`, Zeus Juice's sheds its bolts and Surf Soda's its bubbles, each half and half with the regular energy as Frost Tea's snowflakes are; and its burning ball, loose and flying, trails the same fire at twice a head's rate beside its usual trail, streaming back along the ball's path and turned to it, without the head's rise and wind, Frost Tea's sheds snowflakes among the energy,
Zeus Juice's throws the two lightning particles, half each. Sizes per sprite in
`ParticleLook`: energy 10, snowflake 6, fire 12, lightning 8. Hits spark with
`esper_spark` and `esper_spark2`, Zeus Juice's with `lightning_spark` and
`lightning_spark2`, at half size, centred, twice that on a wall; a fireball's burst is
twice its size on a wall. Blazing Boba's hits spark with `fire_spark`, `fire_spark2` or
`fire_spark3`, painted, at half size, centred. The flash sheet is drawn over, not added, so its tone shows,
and with the hitboxes on its tear's reach rings both ends. Head particles each start on
a random frame of their sheet, so a stream never plays in step. The wall jump spark is `fire_wallspark` as a
silhouette in the energy colour; Blazing Boba's is `fire_skid`. The flash is `flashspark2` at 0.66 in the energy colour at both
ends; the jump spark draws at three quarters, the ice one at 0.625 (half, and a quarter more);
Zeus Juice's, bottom-aligned, twelve pixels under the feet. Frost Tea's jump spark is
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
  run 4, taunt 2 and 7). The dribble's bounce plays at half a loose ball's (`GameScene.dribbleVolume`).
- step: the walk and run sheets' frames 0 and 4, on the ground, at twice its file's level.
- The announcer's 3, 2, 1 (announcer_1..3, or the second set announcer_1-2..3-2 on the COUNT
  picker, A or B): each number of the count as it goes up, in play.
- announcer_ballout and ballout2 together at BALL OUT, each panned halfway to its own side.
- port_in: the port-in at a round's start.
- swish: a point, with the strike on the rim; a dunk has none, the announcer's line instead.
- crowd_cheer, behind the rest, on every basket, and with it the announcer: on the game's last,
  thatlldoit, thatlldoit-2 or thatdecidesit, the finish slowing to 0.35 (offline) and the camera
  easing in on the ball to 0.55 of its view over 40 frames and then staying on it, in a hand or
  loose (where it was last seen while it's drawn nowhere), on Hoopfish Hideaway and the Elements kept inside the
  stage's sides, the HUD keeping its size, until
  the win screen; from the winning bucket nobody moves or catches (`Match.finished`: no inputs,
  the computer's among them, and no catches); otherwise a line drawn by weight: the generic score (score, -2, -3,
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
confirmed; a coin flip rolls on the shared dice, so both land the same. Protocol version 4. MULTIPLAYER opens the game's own multiplayer screen (`MultiplayerScreen`, in place of Apple's
matchmaker sheet, doing what it did, through GameKit's matchmaker): full screen on the screens' ground, PLAY NOW (matched with anyone looking), INVITE A FRIEND (the Game Center friends list,
pick one; the app asks for the list with `NSGKFriendListUsageDescription`), BACK; while matching,
the caption, whoever was invited with their answer (invited, on their way, can't play; a decline
ends the wait) and CANCEL. On the title's cursor, B back. An invite accepted from Game Center's
notification opens it on the joining. It fails at once until the app's record in App Store
Connect has Game Center on. The win screen's REMATCH waits for both; TITLE says bye. A disconnect
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
