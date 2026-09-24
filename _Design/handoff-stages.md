# Handoff: the new stages

Written 2026-09-24 for whoever picks this project up next, in a cheaper model. The user
is about to add stages beyond the one court. Everything here is what you need to build
them without breaking online play, which is the one thing that matters most. Read
`prototype.md` first for the game; this file is the stage work specifically.

## How the project works

- `EsperSim/` is the whole game as a value, `Match`, advanced by `advance(inputs:)` at
  60 a second. Pure Swift, deterministic, no clocks, no randomness outside `Dice`, no
  libm: all trig goes through `Trig`. Two phones run it in lockstep with rollback
  (`RollbackSession`), so anything gameplay-relevant lives here and only here.
- `ProjectEsper/` is the app: `GameScene` steps the sim through the session and draws
  the last state; nothing in it writes back into the match except the inputs it hands
  in and the few `session.mutate` calls between rounds.
- Build: `xcodebuild -project ProjectEsper.xcodeproj -scheme ProjectEsper -destination
  'generic/platform=iOS Simulator' -derivedDataPath <private path> build`. Always a
  private derived data path, or you collide with the user's Xcode. Tests: `cd EsperSim
  && swift test` (169 tests, all green as of this note). The user tests on device; you
  never run the simulator unless asked.
- Commit when a piece is done, with the design doc updated in the same commit. The user
  edits in Xcode meanwhile: `git status` before staging, stage only your own hunks.
- Comments: a few lines saying what and why, no essays. Names explicit, no shorthand.
  Constants are whole numbers in art pixels or round numbers; a stated number is the
  number, never nudged. Don't volunteer balance opinions; the user handles balance.

## What a stage is today

`Stage` (in `EsperSim/Sources/EsperSim/Stage.swift`): a grid of `Tile`s (`.empty`,
`.solid`, `.oneWay`), row 0 at the bottom, `columns` by `rows`, tile size 10 units
(16 art pixels). Outside the grid is solid below and to the sides; above the top row
the side walls carry on up through `Stage.skyRows` (10) of open sky to a ceiling. It
also holds the `hoops` (position, owner, backboard side), `playerSpawns`,
`playerFacings`, `ballSpawn`, and `extras`, the boxes made platforms add each frame.

The one stage, `Stage.court`, is built in code at the bottom of that file: 34 by 16,
floor and walls filled with `fill(.solid, columns:rows:)`, a backboard block each side
(columns 3...4 and 29...30, rows 7...8) with its rim on the inward face at y 80, and a
one-way ledge (columns 15...18, row 3). Player 0 spawns left facing right and scores on
the right rim; the rim's `owner` is who scores there's opponent, so `owner: 0` is the
right rim.

`Match.init(stage: Stage = .court, ...)` takes the stage. `GameScene.startRound()` and
the session's initial match use the default. There is no stage selection anywhere yet.

## How to add stages

Do it in this order, and keep every step green.

1. **Stage definitions in the sim.** Add each stage as a `static let` on `Stage` beside
   `court`, built the same way: `Stage(columns:rows:hoops:playerSpawns:playerFacings:
   ballSpawn:)` then `fill`. Give each a name the user chose. Then a `Stage.all: [Stage]`
   in a fixed order and a `StageId: Int` (or an enum with `Int` raw values) that indexes
   it; the wire and the series carry the id, never the stage. The user will describe the
   layouts; put the numbers in as given, in tiles and units, and mirror the court's
   conventions: rims on a backboard block's inward face, one-way ledges as `.oneWay`,
   floor row 0, walls in columns 0 and `columns - 1`.

2. **Selection, deterministic.** Offline: a `STAGE` picker in `Tuning.swift` and the
   scene's picker strip (`controls.addPicker`, see HEAD and POWER), and the title or
   series carries the choice into `startRound()`: `Match(stage: Stage.all[id], ...)`.
   Online: the choice must be identical on both phones before frame 0. Put the stage id
   in the `hello` message (`NetMessage.hello` in `Net.swift` gets a `stage: UInt8`,
   bump `NetRules.protocolVersion`), and decide the rule: the side whose Game Center id
   sorts first (`localIsFirst`, player 0) picks, or the seed picks from a rotation.
   Either is fine; both sides must compute the same id from the same bytes. Never read
   the picker on the non-choosing side.

3. **The camera and the view.** `GameScene.layout` fits the whole court on screen at a
   whole number of screen pixels per game pixel from `match.stage.columns` and `rows`,
   so a bigger stage just draws smaller; a taller stage may want the HUD's top row
   checked. `GameScene.build` draws the tiles once from `match.stage` at build time: it
   colours backboard blocks by the nearest rim's owner, ledges magenta, and runs the side
   walls up through the sky rows. Rims and nets come from `stage.hoops`. Because build
   happens once, a stage change needs the ground layer rebuilt: split the tile drawing
   out of `build()` into a `buildStage()` you can call again from `startRound()` when the
   stage id changes (remove `ground`'s children, `courtTiles`, `rimNodes`, `rimFlash`,
   and the platform slabs, then redraw). `bringPlayersIn` and everything else read the
   live `match.stage`.

4. **The computer.** `Opponent.swift` has the court baked into a few numbers: its shot
   spots are 45 and 70 units in from the rim on the floor and "the ledge" is the
   one-way row at `ledgeRow = 3`; `behind` uses `y < 90` for the backboard block; the
   climb-out uses 85; `landing(of:)` bounces the ball off the outer walls by
   `stage.width`. Generalise as you go: take the ledge row from the stage (scan for
   `.oneWay` rows), the block's top from the hoop's height, and keep spots relative to
   the rim. It's fine for the AI to be dumber on new stages at first; it's fine for it to
   never be better than the human. Run `swift test --filter OpponentTests` after.

5. **Rollback safety checklist**, every stage:
   - Nothing in a stage reads the frame count except a moving platform (see below), and
     nothing reads a clock, `Date`, or `random`.
   - The stage is part of the `Match` value: `Match` is `Equatable` and snapshots are
     copies, so a stage that changes over time (moving platforms) must keep its state
     in the `Match`, not in the scene.
   - Run `swift test --filter NetTests`: the convergence test runs two sessions over a
     lossy link and compares them to a plain run. Add a case that runs it on the new
     stage, by passing the stage into the `Match(countdown:)` calls in that test.
   - The checksum (`Match.checksum`) covers positions, the ball and scores. If a stage
     carries state, add it to the checksum.

6. **Moving platforms**, if the user asks: keep them in the sim as boxes whose position
   is a function of `match.frame` on a fixed path, added to `stage.extras` each frame
   like made slabs are (see `Match.advance`, `platforms`). The one real piece of work is
   carrying: after `Player.move`, a body grounded on a platform's box moves by the
   platform's displacement that frame, then gets pushed out of solids again; the ball
   resting on one too. Decide the crush case (platform rising into a body) and the
   drop-away case (platform falling faster than gravity). Plain adds and compares only;
   no trig unless it goes through `Trig`.

7. **Tests.** Every stage gets a test that spawns both players, drops the ball, and
   checks a shot from each spawn can score on its rim (use the AI's `shotAim` as a
   model, or run `Match` with a fixed aim), plus one that the spawns and the ball spawn
   aren't inside solids. Put them in a new `StageTests.swift`.

8. **Design doc.** `prototype.md` has a Court section; each stage gets its own
   paragraph there with the numbers, and the Multiplayer section notes that the stage
   id rides in hello.

## Things that bit before, so you don't repeat them

- An `SKSpriteNode`'s `size` is set in its parent's units: set `setScale(1)` before
  sizing a node you also scale, or the scale cancels. Print `frame.size` when a size
  change "does nothing".
- Effect strips are measured by the importer (`Tools/import_sprites.py` writes
  `ProjectEsper/Art/EffectSheets.swift`): frames, anchor and toning come from there.
  `ANCHOR_OVERRIDE` in the importer is where the artist's word beats the measurement.
- The user names the exact file when something's wrong. Believe them, measure what's on
  screen, then change one thing.
- "Viable" from the user means "without breaking online". Answer that first.
