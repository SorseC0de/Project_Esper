import XCTest
@testable import EsperSim

/// ZONES: the grid, a run's log, the shot's outcome, the follower's straying, the turn rules
/// and the mode's stages.
final class ZonesTests: XCTestCase {
    private func court() -> Match {
        var match = Match(stage: .zones(.wreckCenter), specs: [.starting], mode: .zones)
        match.countdown = 0
        return match
    }

    // MARK: The grid

    func testTheGridGivesWhatDoesntDivideToA1() {
        let wreck = ZoneGrid(stage: .zones(.wreckCenter))
        XCTAssertEqual(wreck.columns, 8, "34 tiles: A to H")
        XCTAssertEqual(wreck.firstColumnTiles, 6, "A takes the two left over")
        XCTAssertEqual(wreck.rows, 4)
        XCTAssertEqual(wreck.firstRowTiles, 4, "16 divides")
        let hideaway = ZoneGrid(columns: 37, rows: 19)
        XCTAssertEqual(hideaway.columns, 9, "A to I")
        XCTAssertEqual(hideaway.firstColumnTiles, 5)
        XCTAssertEqual(hideaway.rows, 4, "19 tiles: 1 to 4")
        XCTAssertEqual(hideaway.firstRowTiles, 7, "1 takes the three left over")
        // Named from the bottom left: A1 at the corner, B just past A's wider span.
        XCTAssertEqual(wreck.zone(of: Vec2(x: 5, y: 5)).name, "A1")
        XCTAssertEqual(wreck.zone(of: Vec2(x: 6 * Stage.tileSize - 1, y: 5)).name, "A1")
        XCTAssertEqual(wreck.zone(of: Vec2(x: 6 * Stage.tileSize, y: 5)).name, "B1")
        XCTAssertEqual(wreck.zone(of: Vec2(x: 33 * Stage.tileSize, y: 15 * Stage.tileSize)).name, "H4")
        XCTAssertEqual(wreck.columnLines.count, 7)
        XCTAssertEqual(wreck.columnLines.first, 6 * Stage.tileSize)
        XCTAssertEqual(wreck.rowLines, [4, 8, 12].map { Double($0) * Stage.tileSize })
    }

    // MARK: The stages

    func testTheWreckCenterKeepsOnlyItsRightRimAndTheLeftBackboard() {
        let stage = Stage.zones(.wreckCenter)
        XCTAssertEqual(stage.hoops.count, 2)
        XCTAssertTrue(stage.hoops[0].rimless)
        XCTAssertFalse(stage.hoops[1].rimless)
        XCTAssertEqual(stage.playerSpawns[0], Vec2(x: ZonesRules.startX, y: Stage.tileSize))
        XCTAssertFalse(stage.overlapsSolid(Box(center: Vec2(x: ZonesRules.startX, y: 15), width: 8, height: 10)), "the start's clear")
        // The ball dropped through the rimless left hoop: no point.
        var match = court()
        match.players[0].hasBall = false
        match.ball.holder = nil
        match.ball.respawn(at: stage.hoops[0].position + Vec2(x: 0, y: 12))
        match.ball.lastTouched = 0
        match.ball.velocity = Vec2(x: 0, y: -3)
        match.ball.scoring = true
        for _ in 0..<30 { match.advance(inputs: [.idle]) }
        XCTAssertEqual(match.scores, [0])
        // The left backboard still stops the ball.
        XCTAssertFalse(stage.extras.isEmpty)
    }

    func testHoopfishHideawaysFishSwimsInPlaceOnTheRightWithTheRim() {
        let stage = Stage.zones(.hoopfishHideaway)
        XCTAssertTrue(stage.hoopfishStationary)
        var match = Match(stage: stage, specs: [.starting], mode: .zones)
        match.countdown = 0
        guard let fish = match.hoopfish else { return XCTFail("no Hoopfish") }
        XCTAssertEqual(fish.carrying, .hoop)
        XCTAssertFalse(fish.facesRight)
        XCTAssertGreaterThan(fish.position.x, stage.width / 2, "on the right")
        for _ in 0..<300 { match.advance(inputs: [.idle]) }
        XCTAssertEqual(match.hoopfish?.position, fish.position, "in place")
        XCTAssertEqual(match.stage.hoops[0].position, fish.antenna, "the rim on its antenna")
    }

    // MARK: Runs

    func testARunStartsWithTheBallAndFullFloThatNeverRunsOut() {
        var match = court()
        XCTAssertEqual(match.ball.holder, 0)
        XCTAssertEqual(match.players[0].flo, FloRules.full)
        match.advance(inputs: [PlayerInput(shoot: true, throwBall: true)])
        XCTAssertEqual(match.players[0].state, .transforming)
        for _ in 0..<(TransformRules.frames + FloStateRules.spendFrames * 3) { match.advance(inputs: [.idle]) }
        XCTAssertTrue(match.players[0].inFloState)
        XCTAssertEqual(match.players[0].flo, FloRules.full, "never spent")
    }

    func testThePickedPowerComesOnWithFloStateAndGoesWithIt() {
        var match = court()
        match.players[0].floStatePower = .galeAle
        XCTAssertEqual(match.players[0].power, .none)
        match.advance(inputs: [PlayerInput(shoot: true, throwBall: true)])
        for _ in 0..<TransformRules.frames { match.advance(inputs: [.idle]) }
        XCTAssertEqual(match.players[0].power, .galeAle)
        XCTAssertEqual(match.players[0].powerLevel, ZonesRules.powerLevel)
        for _ in 0..<5 { match.advance(inputs: [.idle]) }
        match.advance(inputs: [PlayerInput(shoot: true, throwBall: true)])
        XCTAssertFalse(match.players[0].inFloState)
        XCTAssertEqual(match.players[0].power, .none)
    }

    func testTheRecorderLogsEachMoveByItsZoneAndTheShotEndsIt() {
        var match = court()
        var recorder = ZonesRecorder(match: match, player: 0)
        func step(_ input: PlayerInput, _ frames: Int = 1) {
            for _ in 0..<frames {
                match.advance(inputs: [input])
                recorder.observe(match, input: input)
            }
        }
        // A walk, a stop, then the stick flicked out: the dash into the run, a move again, the
        // walk's or the run's alike; a jump; the shot.
        step(PlayerInput(stick: Vec2(x: 0.4, y: 0)), 20)
        step(.idle, 10)
        step(PlayerInput(stick: Vec2(x: 1, y: 0)), 60)
        step(PlayerInput(stick: Vec2(x: 1, y: 0), jump: true), 1)
        step(PlayerInput(stick: Vec2(x: 1, y: 0)), 10)
        step(PlayerInput(shoot: true), 1)
        for _ in 0..<120 where recorder.run.actions.last?.kind != .shoot { step(.idle) }
        let kinds = recorder.run.actions.map(\.kind)
        XCTAssertEqual(kinds, [.move, .move, .jump, .shoot], "\(recorder.run.actions.map(\.line))")
        XCTAssertEqual(recorder.run.actions[0].zone.name, "A1")
        XCTAssertNil(recorder.outcome, "the shot's still in the air")
        step(.idle, 240)
        XCTAssertNotNil(recorder.outcome, "the shot's settled, in or out")
        // Nothing after the shot is logged.
        XCTAssertEqual(recorder.run.actions.count, 4)
    }

    func testADunkMakesTheRun() {
        var match = court()
        let rim = match.stage.hoops[1].position
        match.players[0].position = Vec2(x: rim.x - 12, y: rim.y - 10)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        var recorder = ZonesRecorder(match: match, player: 0)
        // Throw held by the rim: the dunk.
        for _ in 0..<120 where recorder.outcome == nil {
            let input = PlayerInput(throwBall: true)
            match.advance(inputs: [input])
            recorder.observe(match, input: input)
        }
        XCTAssertEqual(recorder.outcome, .made, "\(recorder.run.actions.map(\.line))")
        XCTAssertEqual(recorder.run.actions.last?.kind, .dunk)
    }

    func testAFloaterIsTheShot() {
        var match = court()
        var recorder = ZonesRecorder(match: match, player: 0)
        // Throw held, then let go with the stick up: the floater.
        for _ in 0..<(BallRules.throwWindupFrames + 2) {
            let input = PlayerInput(stick: Vec2(x: 0, y: 1), throwBall: true)
            match.advance(inputs: [input])
            recorder.observe(match, input: input)
        }
        for _ in 0..<30 where recorder.run.actions.last?.kind != .shoot {
            let input = PlayerInput(stick: Vec2(x: 0, y: 1))
            match.advance(inputs: [input])
            recorder.observe(match, input: input)
        }
        XCTAssertEqual(recorder.run.actions.last?.kind, .shoot, "\(recorder.run.actions.map(\.line))")
        XCTAssertEqual(recorder.run.actions.last?.label, "Floater")
    }

    func testWatchingAgainGoesBackToTheTryItWasWatchedFrom() {
        var game = ZonesGame(leader: 0, stage: .wreckCenter)
        let run = ZonesRun(actions: [ZoneAction(kind: .shoot, zone: Zone(column: 5, row: 0), frame: 10)])
        game.beginRecording()
        _ = game.runEnded(run, outcome: .made)
        game.keepCandidate()
        game.rewind()
        XCTAssertEqual(game.phase, .confirming(attempt: 2))
        XCTAssertEqual(game.watched, run, "the leader's own run to watch")
        game.watchAgain()
        XCTAssertEqual(game.phase, .watching)
        XCTAssertEqual(game.mover, 0, "still the leader's turn while they watch their own run")
        game.beginFollowing()
        XCTAssertEqual(game.phase, .confirming(attempt: 2))
        _ = game.runEnded(run, outcome: .made)
        game.beginFollowing()
        game.rewind()
        game.watchAgain()
        game.beginFollowing()
        XCTAssertEqual(game.phase, .following(attempt: 2))
    }

    func testTheRunTimesOutWithoutAShot() {
        var match = court()
        var recorder = ZonesRecorder(match: match, player: 0)
        for _ in 0...ZonesRules.runFrames where recorder.outcome == nil {
            match.advance(inputs: [.idle])
            recorder.observe(match, input: .idle)
        }
        XCTAssertEqual(recorder.outcome, .timedOut)
        XCTAssertEqual(recorder.run.frames, ZonesRules.runFrames)
    }

    func testAFollowerStraysOnTheFirstMoveThatDiffers() {
        let set = ZonesRun(actions: [ZoneAction(kind: .move, zone: Zone(column: 0, row: 0), frame: 1),
                                     ZoneAction(kind: .jump, zone: Zone(column: 2, row: 0), frame: 60),
                                     ZoneAction(kind: .shoot, zone: Zone(column: 2, row: 1), frame: 80)])
        var match = court()
        var recorder = ZonesRecorder(match: match, player: 0, target: set)
        // A move from A1 matches; a jump from A1 doesn't.
        for _ in 0..<5 {
            let input = PlayerInput(stick: Vec2(x: 0.4, y: 0))
            match.advance(inputs: [input])
            recorder.observe(match, input: input)
        }
        XCTAssertEqual(recorder.followed, 1)
        XCTAssertNil(recorder.outcome)
        let jump = PlayerInput(stick: Vec2(x: 0.4, y: 0), jump: true)
        for _ in 0..<15 where recorder.outcome == nil {
            match.advance(inputs: [jump])
            recorder.observe(match, input: jump)
        }
        XCTAssertEqual(recorder.outcome, .strayed(at: 1))
        XCTAssertEqual(recorder.followed, 1, "the strayed move isn't counted as matched")
        // The same run matches itself.
        XCTAssertTrue(set.isFollowed(by: set))
        var longer = set
        longer.actions.insert(ZoneAction(kind: .taunt, zone: Zone(column: 0, row: 0), frame: 2), at: 1)
        XCTAssertFalse(set.isFollowed(by: longer))
    }

    // MARK: The turn

    func testTheLeaderRecordsConfirmsAndTheFollowerEarnsLettersToLose() {
        var game = ZonesGame(leader: 1, stage: .wreckCenter)
        let run = ZonesRun(actions: [ZoneAction(kind: .shoot, zone: Zone(column: 5, row: 0), frame: 10)])
        XCTAssertEqual(game.mover, 1)
        game.beginRecording()
        XCTAssertEqual(game.phase, .recording(attempt: 1))
        XCTAssertEqual(game.runEnded(run, outcome: .missed), .tryAgain(left: 2))
        game.rewind()
        XCTAssertEqual(game.phase, .recording(attempt: 2))
        XCTAssertEqual(game.runEnded(run, outcome: .made), .candidateMade(last: false))
        game.keepCandidate()
        XCTAssertEqual(game.phase, .confirming(attempt: 1))
        // Repeated but not scored, then repeated and scored: set.
        XCTAssertEqual(game.runEnded(run, outcome: .missed), .tryAgain(left: 2))
        game.rewind()
        XCTAssertEqual(game.runEnded(run, outcome: .made), .runSet)
        XCTAssertEqual(game.phase, .watching)
        XCTAssertEqual(game.mover, 0)
        game.beginFollowing()
        // The follower strays twice and misses once: a letter; the leader keeps leading.
        XCTAssertEqual(game.runEnded(run, outcome: .strayed(at: 0)), .tryAgain(left: 2))
        game.rewind()
        XCTAssertEqual(game.runEnded(run, outcome: .strayed(at: 0)), .tryAgain(left: 1))
        game.rewind()
        XCTAssertEqual(game.runEnded(run, outcome: .missed), .letter(count: 1, lost: false))
        XCTAssertEqual(game.leader, 1)
        XCTAssertEqual(game.phase, .lobby)
        XCTAssertEqual(game.lettersShown(0), "Z")
        // Four more and the follower's lost.
        game.letters[0] = 4
        game.beginRecording()
        _ = game.runEnded(run, outcome: .made)
        game.keepCandidate()
        _ = game.runEnded(run, outcome: .made)
        game.beginFollowing()
        for _ in 0..<2 { _ = game.runEnded(run, outcome: .missed); game.rewind() }
        XCTAssertEqual(game.runEnded(run, outcome: .missed), .letter(count: 5, lost: true))
        XCTAssertEqual(game.winner, 1)
    }

    func testALeaderWhoCantScoreOrRepeatHandsOverTheLead() {
        var game = ZonesGame(leader: 0, stage: .wreckCenter)
        let run = ZonesRun(actions: [ZoneAction(kind: .shoot, zone: Zone(column: 5, row: 0), frame: 10)])
        game.beginRecording()
        for _ in 0..<2 { _ = game.runEnded(run, outcome: .missed); game.rewind() }
        XCTAssertEqual(game.runEnded(run, outcome: .missed), .leadPassed)
        XCTAssertEqual(game.leader, 1)
        XCTAssertEqual(game.letters, [0, 0], "no letter for failing to set")
        // A made run on the last recording try is kept outright.
        game.beginRecording()
        for _ in 0..<2 { _ = game.runEnded(run, outcome: .missed); game.rewind() }
        XCTAssertEqual(game.runEnded(run, outcome: .made), .candidateMade(last: true))
        XCTAssertEqual(game.phase, .confirming(attempt: 1))
        // Can't repeat it: the lead goes back.
        for _ in 0..<2 { _ = game.runEnded(run, outcome: .strayed(at: 0)); game.rewind() }
        XCTAssertEqual(game.runEnded(run, outcome: .strayed(at: 0)), .leadPassed)
        XCTAssertEqual(game.leader, 0)
        XCTAssertNil(game.set)
    }

    func testARunReplaysToTheFrame() {
        var match = court()
        var recorder = ZonesRecorder(match: match, player: 0)
        let inputs = (0..<90).map { frame in frame < 30 ? PlayerInput(stick: Vec2(x: 1, y: 0)) : PlayerInput(stick: Vec2(x: 1, y: 0), jump: frame == 30) }
        for input in inputs {
            match.advance(inputs: [input])
            recorder.observe(match, input: input)
        }
        var again = court()
        for input in recorder.run.inputs { again.advance(inputs: [input]) }
        XCTAssertEqual(again.players[0].position, match.players[0].position)
        let data = try? JSONEncoder().encode(recorder.run)
        XCTAssertNotNil(data)
        XCTAssertEqual(try? JSONDecoder().decode(ZonesRun.self, from: data ?? Data()), recorder.run)
    }

    // MARK: Over the wire

    func testARunIsCodedWithItsInputsPackedFiveBytesAFrame() throws {
        // A quantized stick, as the pad's is before it's recorded, comes back exactly.
        var inputs: [PlayerInput] = []
        for frame in 0..<600 {
            var input = PlayerInput(stick: Vec2(x: 0.4, y: -0.7), aim: Vec2(x: 1, y: 0))
            input.jump = frame % 7 == 0
            input.shootButtons = UInt8(frame % 4)
            input.throwBall = frame % 11 == 0
            input.taunt = frame % 13 == 0
            inputs.append(input.quantized)
        }
        let run = ZonesRun(actions: [ZoneAction(kind: .jump, zone: Zone(column: 1, row: 0), frame: 7)], inputs: inputs, floStatePower: .voltaCola)
        let data = try JSONEncoder().encode(run)
        XCTAssertEqual(ZonesRun.pack(inputs).count, 600 * PlayerInput.wireBytes)
        XCTAssertLessThan(data.count, 6000, "ten seconds of run, packed, under six kilobytes with its log")
        XCTAssertEqual(try JSONDecoder().decode(ZonesRun.self, from: data), run)
    }

    func testTheWholeGameRoundTrips() throws {
        var game = ZonesGame(leader: 1, stage: .hoopfishHideaway)
        game.beginRecording()
        _ = game.runEnded(ZonesRun(actions: [ZoneAction(kind: .shoot, zone: Zone(column: 2, row: 1), frame: 40)],
                                   inputs: [PlayerInput.idle, PlayerInput(jump: true)], floStatePower: .galeAle), outcome: .made)
        game.keepCandidate()
        let data = try JSONEncoder().encode(game)
        XCTAssertEqual(try JSONDecoder().decode(ZonesGame.self, from: data), game)
    }

    func testAForfeitedTurnPassesTheLeadOrTakesTheLetter() {
        var game = ZonesGame(leader: 0, stage: .wreckCenter)
        XCTAssertTrue(game.isAtStart)
        game.beginRecording()
        XCTAssertFalse(game.isAtStart)
        game.forfeitTurn()
        XCTAssertEqual(game.leader, 1, "the leader gave the turn up: the other leads")
        XCTAssertEqual(game.phase, .lobby)
        // The follower gives their turn up: a letter.
        game.beginRecording()
        _ = game.runEnded(ZonesRun(actions: [ZoneAction(kind: .shoot, zone: Zone(column: 0, row: 0), frame: 1)]), outcome: .made)
        game.keepCandidate()
        _ = game.runEnded(ZonesRun(actions: [ZoneAction(kind: .shoot, zone: Zone(column: 0, row: 0), frame: 1)]), outcome: .made)
        XCTAssertEqual(game.phase, .watching)
        game.forfeitTurn()
        XCTAssertEqual(game.letters, [1, 0])
        XCTAssertEqual(game.phase, .lobby)
        XCTAssertNil(game.set)
    }
}
