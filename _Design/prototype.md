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
  one controller is player 1, two controllers are players 0 and 1 in order; on the TV
  the controllers are players 0 and 1. A pad on player 1 sits the computer out, so a
  second person just picks up a pad. A keyboard on an iPad or a Mac is player 0 as well: WASD, space to jump, J to shoot,
  K to throw, shift as the left bumper, Esc quits on a Mac or in the simulator. The HUD is laid out in the phone's points and
  scaled up by `HudScene.scale(forHeight:)` on a bigger screen, the lettering rendered
  at that scale so it stays crisp. `Net/GameCenter` is Game
  Center: signing in, the matchmaker, and the bytes between the two phones. Two
  targets build the same sources and catalog: `ProjectEsper` for iPhone and iPad, and
  `ProjectEsperTV` for Apple TV, same bundle ID so the two play each other. On the TV
  there's no pad on screen, a controller is required, and its menu button is claimed as
  reset so it doesn't send the app home; the few phone-only calls sit behind
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
drifts a tenth faster (`DefenceRules`). `FighterSpec.baseline` is Melee Fox with a Falco-style dash, 6 frames, half Fox's ground, the burst always 0.4 over the
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
- Throw (without ball, in neutral or on defence): the snatch. The sheet's ten frames at
  15 a second, 40 sim frames, the hand out over sheet frames 2 and 3
  (`SnatchRules.activeSheetFrames`), the third sheet frame held twice as long, when the
  whole body plus a tile of reach in front, or the hand's catch ring at the spark's
  spot, takes any ball it touches while the body faces it: a loose one at any speed, or
  the one in the other's hands, where the sheet draws it that frame, or the holder's
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
- Knocked loose (by a slide or a slash), the ball pops straight up: the floater's drift
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
  through, and so does one faster than 5 a frame (a throw is 7) or a shot in flight
  before its first bounce, unless the body is reaching with a snatch or swinging the
  blade. The snatch is the catch: there is no catch stance.
- Knocked loose by the blade or the slide's leg, or robbed by a snatch, a body can't
  press anything or catch anything for 60 frames, longer than the pop's round trip,
  though the stick still moves it, and its sprite flickers white: the taker has first
  go at the ball.
- Rims steer: a ball falling within reach has its sideways speed blended toward what
  would carry it through the rim, a share a frame, never snapped. Only a shot's or a
  floater's ball, and only until its first bounce off anything; a throw's never. Down
  through a rim scores unless the ball rose up through that rim first.

Pad: A jump, B, R1 or R2 shoot, X throw, Y taunt, right stick aims a stance. L1 steps the top
tuning picker, menu resets, R3 switches the computer, L3 the hitboxes. Down on the stick
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
  is the web line, from the ground, the air or a wall: held, it aims along the stick with a
  faint line; let go, it fires, 120 units. It bends to a loose ball or the opponent within
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
  knocked on, and the ball it meets pops back toward the thrower. There's no slash.
  Level two's throw calls a strike down from the top of the screen, five units wide,
  from the top of the screen onto the ball in hand, where the stance's sheet draws it, as the charge starts or onto the
  snatch's hand at full stretch,
  stopping on the first thing it meets on the way down, a solid, the other body,
  stripped, or the loose ball, popped, once every 40 frames. The bolt throw plays the
  whole throw sheet, ground or air, with the sheet's ball drawn as energy, and the bolt
  leaves on its release frame, sixteen frames in.
  Numbers in `ZeusRules`.
- Frost Tea (I). The snatch freezes what it reaches, a body or the loose ball, for 60
  frames: held exactly where it is, nothing running, nothing caught, no hitbox live, though
  a frozen ball can still be picked up or snatched;
  a frozen body is stripped as well. The slide has no friction and no end, until jump,
  throw, shoot, the stick against it, or down let go cancel it. Level two: a double
  jump or a slide leaves an ice clone, the body's box, that freezes whatever touches it
  and shatters, or shatters after 60 frames. Numbers in `FrostRules`.
- Blazing Boba (J). A run at full speed or a slide leaves a flame every 4 frames, six
  wide and four tall at the feet, for 45 frames; the other body in one is stripped and
  the flame is spent. Shots and throws set the ball alight until its first bounce, and
  nobody but the thrower can catch or snatch it; the slash still can. Level two: shoot
  and throw together with nothing in hand makes a fireball in hand, fire swirling into
  it; it leaves at one and a half times the ball's speed; shot it arcs under half the ball's gravity with the aiming dots, thrown it flies
  dead straight, and it bursts on the first thing it meets and strips and knocks
  whatever's within 15 of the burst. Numbers in `BlazeRules`.
- Pulsepistol Punch (K). Shoot without the ball is the pulse: a pillar ten units tall
  at the hand, the width of the screen the way the body faces, that knocks the ball and
  the other body away without stunning, a held ball popping free; standing it's the
  gun sheet, its ten frames at 15 a second with the pulse on the third, one every 20,
  and nothing to see unless the hitboxes are on: a kinetic pulse, no spark. Level two fires in
  stride on the run, and throw is the pull, the same pulse bringing everything toward
  the body. Numbers in `PulseRules`.

Hits share the strip: the victim is stunned 60 frames and any ball they hold pops
free; the slash, the parry, the bolt, the burst and the pulse knock the body away as
well (`Player.knock`), and the pulse doesn't stun. The slash strips a body with or
without the ball, knocking it 2.5 along the swing and 1.5 up. The snatch has no
cooldown, as the slash has none, and meeting a live blade it's the parry: the slasher
is the one stripped and knocked back, the blade spent, resolved before the blades so it
always wins.

## The game loop

A best of seven, first to four points, in `Series`. The title screen, drawn by the
SwiftUI layer over the Metal view on a dark ultra-thin material with the court showing
through, offers BEST OF 7 and, greyed for now, MULTIPLAYER; jump on the pad starts too.
A round starts with both bodies struck in at their
spawns by a bolt and the crown in their colours, then the three count in title lettering
and BALL OUT!!! as it hits zero, when both can act. A point is a round: BUCKET!! goes up
with the strike, and whoever was scored on drinks. The computer drinks at once, one of
its three at random on the series' dice; the human gets the pick screen once the strike
has played, and the round counts again after the drink. Five circles across the top,
dark purple, fill in the round winner's colour as they go, with a sixth and seventh
added if the series gets there, and to either side of them each side's drinks with their
levels, in its colour. What the computer drank goes up as a banner after BUCKET!!. Four points
brings the win screen: NEW MATCH, a fresh
best of seven with the drinks gone, or TITLE. RESET starts the round again with the
drinks kept. A pick timer of twenty seconds for networked play is a number in `Series`,
not enforced yet.

Title lettering is `TitleText`: CardCourt's TwoXMark by another route, Avenir Next
Condensed Heavy, white over light blue split at the capitals' middle, a black outline
walked round a ring, a black drop to the south-east, drawn into a texture per string.

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
- Web Water: the swing; level two adds the web line.
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

## Tuning pickers

Segmented pickers in the top-left corner change a stat live on both players. `Tuning.swift`
holds the variants; A is always the baseline as tuned.

- HEAD: how the detached head follows the body. Both close half the gap each frame. B,
  the default, leads sideways instead of trailing, the offset reversed across only.
- POWER, with LEVEL beside it (1 or 2): A none, B Web Water, C Super Smoothie, D Flash Fizz, E Platform Protein
  Shake, F Quake-Up Coffee, G Zeus Juice, H Frost Tea, I Blazing Boba, J Pulsepistol
  Punch, at the level LEVEL picks. The left bumper steps this one; the local side's power
  and level are lettered under the pickers.
- The field's goalposts, settled: the rims 107 high and 66 in from each wall, the posts
  60 in and drawn for a rim at 120, the gold 8 wide; the crossbar sits 20 below that,
  tilted 20° with the end toward the field up, the uprights 100 over it; the back rod
  and the crossbar with its uprights each have their own 1 black outline, as do the
  light panels.
- HITBOX, beside RESET, or a pad's left stick click (L3): draws the sim's boxes over the world. Bodies white, the loose
  ball purple, the two catch rings faint, the slide's leg and the slash's blade red, the
  snatch's reach green with the hand's ring while it's out, a flash's tear cyan.
- AI, beside that: the computer plays the other side. Off, the second pad or nothing does.
  Clicking a pad's right stick (R3) switches it too, which is the only way on the TV.

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
walls go white, fading back over 20 frames, and the crown erupts off the rim with it. Sparks and bolts play at 24 a second. Stunned, the body and head flicker a dark shade of the energy colour and the hurt sheet plays at 10 a second, its last frame held. `ParticleLook.sprites` draws the head's fire and the double jump's platform with `esper_spark` frames at the squares' size, in place of the hard squares. The jump spark and the dash's smoke, near-white on
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

## Football Field

`Stage.footballField`, the stage in play for tuning (`Stage.current`); the court comes back
with stage selection. 340 by 20 tiles, ten courts long, flat and empty: the floor is an
invisible one-tile strip through the middle of the turf, the end walls solid. The rims sit
at 107, 66 in from each wall, floating between the
goalposts' uprights; by design a standing shot can't reach them, so scoring takes a
jump shot, or a jump off a helmet to dunk or shoot. The computer always takes the jump
shot at a rim that high. Each player starts
under the rim they guard, and the coin flip, off the series' dice so both phones agree,
puts the ball in one pair of hands. A ball that leaves the world comes back at centre.

- Helmets (`FieldRules`): 4 by 4 tiles, solid, in the defender's energy colour, one of the
  three helmet vectors filled in that colour, tipped back 30°, facing the
  way they go, drawn at 1.1 times the box; a burst of `flashspark2` in their colour
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
- The portal: a vertical loop at 90, above double-jump height, at a random x kept 200
  from either end; one at a time, five seconds each, the next as soon as it goes. A shot
  or throw still its thrower's through it comes out ten yards, a hundredth of the field
  each, toward the thrower's rim, with a lift of 2 forward and 3.5 up.
- The scenery (`FieldArt`) is flat shapes drawn once: a night sky with floodlight banks,
  the stands with fanning lines and two rails twelve pixels tall, four apart, that wears the possession's
  colour like the court's walls and, with the ball in hand, fills with chevrons drifting
  toward the rim the holder attacks; the floodlights' blooms take the same colour, purple
  when nobody has it, and so do the panels the lamps sit on, trapezoids wider at the top;
  the yard numbers at one and a half times; the turf's five-yard stripes,
  leaning yard lines, hashes and numbers with their arrows. Goalposts: a padded base in the
  colour of the side that guards it, as the court's blocks are, the pole's width and five more, behind the rim, the gold pole bending forward to the crossbar under it, two uprights.
- Shadows (`StageFeatures.shadows`, the view's alone): each body's current frame and its
  head, and the goalposts, cast in a dark greyed purple at two thirds, mirrored under the
  feet or the floor line and sheared by the turf's own lean where they stand, so they
  tip away from the field's middle as the yard lines tip toward it.
  A body's shadow stays on the ground under it: rising, it thins out and shrinks, gone at
  160 pixels up, half its size by then.
- The backboard: behind each rim a 3 by 4 cluster of `flashspark2` in the guarding side's
  energy, each on its own frame so the board shimmers, on a grid sheared to the
  crossbar's lean, 10 behind the rim and 24 over it at 0.4, sheared 20°, at two thirds;
  solid to the ball, a 4 by 20 unit box (`FieldRules.backboardOffset`, `ballBlockers`).
  Platform Protein Shake's slabs and walls are the same flash clusters, filling their box
  in the maker's energy.
- The camera scrolls sideways only: level, gliding after the local player a share of the
  way each frame and leading them by where they're heading, stopped at the field's ends.
  The view takes in the stage's height and the turf below the floor. When the ball is off
  the screen sideways, its chevrons sit at that edge at its height, pointing at it. All of
  it is the view; the sim never sees the camera, so it's safe online.

## Court

The tiles are flat colour, in dark shades: each colour at 0.45 of its brightness. The
floor and walls start purple and shift over 20 frames to the colour of whoever holds the
ball, and back. The backboard blocks wear the colour of the player who scores there's opponent, since you
score on the other side's basket. The ledge is
magenta. Three small faint green chevrons stack over the rim
the holder scores on. The head particles are sprites of their own, not an emitter, so each plays its sheet
through at 24 a second over its life (`esper_particle` by default), rising on one
swinging wind; a single-frame one (a snowflake, or the squares with
`ParticleLook.sprites` off) steps down in size instead. The double jump's platform plays
the particle sheet as its bits drop; Blazing Boba's head burns `fire_particle`, Frost Tea's sheds snowflakes among the energy,
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
side, the buttons in one byte), which both sides simulate quantized. Hello, picks, the
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
plays the left. MULTIPLAYER opens Apple's matchmaker sheet for two, invites or
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

- A "score" mode with three-point lines: a dim glowing arc in the background on each
  side, its peak touching the edge of the middle platform; a shot begun from behind
  the arc counts three. Not built; the note is the whole of it so far.
- Power-ups, including throw-button overrides.
