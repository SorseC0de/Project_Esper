import XCTest
@testable import EsperSim

final class MovementTests: XCTestCase {
    /// Runs the match with player 0 on `inputs` until `stop` is true or the frames run out.
    @discardableResult
    private func run(_ match: inout Match, frames: Int, input: (Int) -> PlayerInput, until stop: ((Match) -> Bool)? = nil) -> Int {
        for frame in 0..<frames {
            match.advance(inputs: [input(frame), .idle])
            if let stop, stop(match) { return frame }
        }
        return frames
    }

    private func peakHeight(_ jumpHeld: (Int) -> Bool) -> Double {
        var match = Match()
        let start = match.players[0].position.y
        var peak = start
        run(&match, frames: 120, input: { PlayerInput(jump: jumpHeld($0)) }) { match in
            peak = max(peak, match.players[0].position.y)
            return match.players[0].state == .land
        }
        return peak - start
    }

    func testFullHopReachesMeleeHeight() {
        let height = peakHeight { _ in true }
        XCTAssertEqual(height, 31.3, accuracy: 1.5)
    }

    func testShortHopReachesMeleeHeight() {
        // Let go during the jump squat.
        let height = peakHeight { $0 < 2 }
        XCTAssertEqual(height, 10.7, accuracy: 1.5)
    }

    /// Every preset's hops land on the SSBWiki heights its velocities were derived from.
    func testPresetHopsMatchTheirTables() {
        let table: [(FighterSpec, Double, Double)] = [
            (.meleeMario, 29, 11), (.meleeFalcon, 38.5, 14.9), (.meleeFox, 31.3, 10.7), (.meleeSheik, 34.1, 20.2),
        ]
        for (spec, fullHop, shortHop) in table {
            for (held, expected) in [(true, fullHop), (false, shortHop)] {
                var match = Match(specs: [spec, spec])
                let start = match.players[0].position.y
                var peak = start
                run(&match, frames: 120, input: { PlayerInput(jump: held || $0 < 2) }) { match in
                    peak = max(peak, match.players[0].position.y)
                    return match.players[0].state == .land
                }
                XCTAssertEqual(peak - start, expected, accuracy: 1.5, "\(spec.name) \(held ? "full" : "short") hop")
            }
        }
    }

    func testSmashInputDashesAndTiltWalks() {
        var match = Match()
        run(&match, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        XCTAssertEqual(match.players[0].state, .run)
        XCTAssertEqual(match.players[0].velocity.x, match.players[0].spec.runSpeed, accuracy: 0.001)

        var walker = Match()
        run(&walker, frames: 40, input: { _ in PlayerInput(stick: Vec2(x: 0.5, y: 0)) })
        XCTAssertEqual(walker.players[0].state, .walk)
        XCTAssertEqual(walker.players[0].velocity.x, walker.players[0].spec.walkMaxSpeed * 0.5, accuracy: 0.001)
    }

    func testWalkingFacesTheOpponentEitherWay() {
        var match = Match()
        // Player 0 starts left of player 1. Walking away still faces them.
        match.players[0].facing = .left
        run(&match, frames: 30, input: { _ in PlayerInput(stick: Vec2(x: -0.5, y: 0)) })
        XCTAssertEqual(match.players[0].state, .walk)
        XCTAssertLessThan(match.players[0].velocity.x, 0)
        XCTAssertEqual(match.players[0].facing, .right)
        // A smash away turns into a dash and turns the body away.
        run(&match, frames: 5, input: { _ in .idle })
        run(&match, frames: 3, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) })
        XCTAssertEqual(match.players[0].state, .dash)
        XCTAssertEqual(match.players[0].facing, .left)
        // Past the opponent, a walk faces back at them.
        match.players[0].position.x = match.players[1].position.x + 30
        match.players[0].velocity = .zero
        match.players[0].enter(.idle)
        run(&match, frames: 10, input: { _ in PlayerInput(stick: Vec2(x: 0.5, y: 0)) })
        XCTAssertEqual(match.players[0].facing, .left)
    }

    func testHoldingDownBrakesARunIntoAWalk() {
        var match = Match()
        run(&match, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        XCTAssertEqual(match.players[0].state, .run)
        let walking = run(&match, frames: 40, input: { _ in PlayerInput(stick: Vec2(x: 0.7, y: -0.7)) }) { $0.players[0].state == .walk }
        XCTAssertLessThan(walking, 40)
        XCTAssertGreaterThan(match.players[0].velocity.x, 0)
        XCTAssertLessThanOrEqual(match.players[0].velocity.x, match.players[0].spec.walkMaxSpeed + 0.001)
    }

    func testTractionStopsTheBody() {
        var match = Match()
        run(&match, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        let stopped = run(&match, frames: 60, input: { _ in .idle }) { $0.players[0].velocity.x == 0 }
        XCTAssertLessThan(stopped, 40)
    }

    func testFastFallHitsTheCap() {
        var match = Match()
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 60, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) }) { $0.players[0].fastFalling }
        XCTAssertEqual(match.players[0].velocity.y, -match.players[0].spec.fastFallSpeed, accuracy: 0.001)
    }

    func testCarrierFastFallsUnlessHoldingThrow() {
        var match = Match()
        match.players[0].hasBall = true
        match.ball.holder = 0
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 60, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) }) { $0.players[0].fastFalling || $0.players[0].grounded }
        XCTAssertTrue(match.players[0].fastFalling)

        var aiming = Match()
        aiming.players[0].hasBall = true
        aiming.ball.holder = 0
        run(&aiming, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&aiming, frames: 60, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1), throwBall: true) }) { $0.players[0].fastFalling || $0.players[0].grounded }
        XCTAssertFalse(aiming.players[0].fastFalling)
        XCTAssertEqual(aiming.players[0].state, .throwStance)
    }

    func testWallLandThenWallJump() {
        var match = Match()
        // Jump toward the court's left wall (x = 10) and hold into it.
        match.players[0].position = Vec2(x: 30, y: 10)
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        let clung = run(&match, frames: 120, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) }) { $0.players[0].state == .wallLand }
        XCTAssertLessThan(clung, 120, "never reached the wall")
        XCTAssertEqual(match.players[0].facing, .left)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .air)
        XCTAssertEqual(match.players[0].facing, .right)
        XCTAssertEqual(match.players[0].velocity.x, match.players[0].spec.wallJumpHorizontal, accuracy: 0.001)
        XCTAssertEqual(match.players[0].velocity.y, match.players[0].spec.wallJumpVertical, accuracy: 0.001)
        XCTAssertTrue(match.events.contains(.wallJumped(player: 0, wall: .left)))
    }

    func testClingLastsWhileHeldAndGraceAfterLettingGo() {
        var match = Match()
        match.players[0].position = Vec2(x: 30, y: 10)
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 120, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) }) { $0.players[0].state == .wallLand }
        run(&match, frames: 40, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) })
        XCTAssertEqual(match.players[0].state, .wallLand, "the cling should last as long as the stick is held")
        // Let go, then jump inside the grace window.
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .air)
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertTrue(match.events.contains(.wallJumped(player: 0, wall: .left)))
    }

    func testJumpNearAWallIsAWallJumpWithoutClinging() {
        var match = Match()
        match.players[0].position = Vec2(x: 30, y: 10)
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        // Drift to the wall without pressing into it, then press jump beside it.
        let beside = run(&match, frames: 120, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) }) { $0.players[0].body.min.x <= 12 }
        XCTAssertLessThan(beside, 120)
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertTrue(match.events.contains(.wallJumped(player: 0, wall: .left)))
    }

    func testJumpOnWallContactIsAWallJumpNotADoubleJump() {
        var match = Match()
        match.players[0].position = Vec2(x: 30, y: 10)
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        // Hold into the wall and mash jump the whole way there.
        let jumped = run(&match, frames: 120, input: { frame in
            PlayerInput(stick: Vec2(x: -1, y: 0), jump: frame % 2 == 0)
        }) { $0.events.contains(.wallJumped(player: 0, wall: .left)) }
        XCTAssertLessThan(jumped, 120, "never wall jumped")
        XCTAssertEqual(match.players[0].velocity.x, match.players[0].spec.wallJumpHorizontal, accuracy: 0.001)
    }

    func testJumpBesideAWallIsNotCaughtOnTheWayUp() {
        var match = Match()
        // Body against the left wall, stick into it, jump.
        match.players[0].position = Vec2(x: 15, y: 10)
        let lockout = match.players[0].spec.wallLandGroundLockoutFrames
        run(&match, frames: 10, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0), jump: true) }) { $0.players[0].state == .air }
        for _ in 0..<lockout - 2 {
            match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0)), .idle])
            XCTAssertEqual(match.players[0].state, .air)
        }
        let clung = run(&match, frames: 60, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) }) { $0.players[0].state == .wallLand }
        XCTAssertLessThan(clung, 60, "never clung once the lockout passed")
    }

    func testWallJumpDoesNotGiveTheDoubleJumpBack() {
        var match = Match()
        match.players[0].position = Vec2(x: 30, y: 10)
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        // Spend the double jump, then reach the wall and jump off it.
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0)), .idle])
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), jump: true), .idle])
        XCTAssertEqual(match.players[0].jumpsLeft, 0)
        run(&match, frames: 120, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) }) { $0.players[0].state == .wallLand }
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), jump: true), .idle])
        XCTAssertTrue(match.events.contains(.wallJumped(player: 0, wall: .left)))
        XCTAssertEqual(match.players[0].jumpsLeft, 0)
    }

    func testCoyoteJumpOffTheLedge() {
        var match = Match()
        // Stand on the middle ledge's right end and walk off it.
        match.players[0].position = Vec2(x: 185, y: 40)
        match.players[0].grounded = true
        let off = run(&match, frames: 60, input: { _ in PlayerInput(stick: Vec2(x: 0.5, y: 0)) }) { $0.players[0].state == .air }
        XCTAssertLessThan(off, 60)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0.5, y: 0)), .idle])
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0.5, y: 0), jump: true), .idle])
        XCTAssertTrue(match.events.contains(.jumped(player: 0)))
        XCTAssertEqual(match.players[0].jumpsLeft, 1)
        XCTAssertEqual(match.players[0].velocity.y, match.players[0].spec.fullHopVelocity, accuracy: 0.001)
    }

    func testJumpBufferedThroughLandingLag() {
        var match = Match()
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 120, input: { _ in .idle }) { $0.players[0].state == .land }
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        run(&match, frames: 5, input: { _ in .idle })
        XCTAssertEqual(match.players[0].state, .jumpSquat)
    }

    func testForwardJumpStartsAtAirSpeed() {
        var match = Match()
        let jumped = run(&match, frames: 10, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0), jump: true) }) { $0.players[0].state == .air }
        XCTAssertLessThan(jumped, 10)
        XCTAssertEqual(match.players[0].velocity.x, match.players[0].spec.airSpeedMax, accuracy: 0.001)
    }

    func testDoubleJumpTurnsAround() {
        var match = Match()
        run(&match, frames: 6, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0), jump: true) })
        run(&match, frames: 10, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), jump: true), .idle])
        XCTAssertEqual(match.players[0].velocity.x, -match.players[0].spec.doubleJumpHorizontalVelocity, accuracy: 0.001)
        XCTAssertEqual(match.players[0].facing, .left)
    }

    func testSkyWallsCannotBeClungTo() {
        let stage = Stage.court
        let inCourt = Box(min: Vec2(x: 10, y: 50), max: Vec2(x: 20, y: 65))
        XCTAssertEqual(stage.wall(beside: inCourt), .left)
        let inSky = inCourt.offset(by: Vec2(x: 0, y: stage.height))
        XCTAssertNil(stage.wall(beside: inSky))
    }

    func testSkyThenACeilingAndTheWallsGoUp() {
        let stage = Stage.court
        XCTAssertEqual(stage.tile(column: 10, row: stage.rows + 5), .empty)
        XCTAssertEqual(stage.tile(column: 10, row: stage.rows + Stage.skyRows), .solid)
        XCTAssertEqual(stage.tile(column: 0, row: stage.rows + 5), .solid)
        XCTAssertEqual(stage.tile(column: stage.columns - 1, row: stage.rows + 5), .solid)
        let box = Box(min: Vec2(x: 100, y: stage.height - 5), max: Vec2(x: 110, y: stage.height + 10))
        XCTAssertFalse(stage.sweepVertically(box, by: 20).ceiling)
    }

    func testLandingLagThenIdle() {
        var match = Match()
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 120, input: { _ in .idle }) { $0.players[0].state == .land }
        XCTAssertEqual(match.players[0].state, .land)
        run(&match, frames: 4, input: { _ in .idle })
        XCTAssertEqual(match.players[0].state, .idle)
    }
}

final class BallTests: XCTestCase {
    private func matchWithBallHeld() -> Match {
        var match = Match()
        match.players[0].hasBall = true
        match.ball.holder = 0
        return match
    }

    func testStanceFlickReleaseShoots() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.shotWindupFrames + 2 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        XCTAssertEqual(match.players[0].state, .shootStance)
        match.advance(inputs: [PlayerInput(aim: Vec2(x: 0.5, y: 0.8), shoot: true), .idle])
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .shooting)
        for _ in 0..<BallRules.shotReleaseFrames {
            match.advance(inputs: [.idle, .idle])
        }
        XCTAssertNil(match.ball.holder)
        XCTAssertFalse(match.players[0].hasBall)
        XCTAssertGreaterThan(match.ball.velocity.y, 0)
        XCTAssertGreaterThan(match.ball.velocity.x, 0)
        // One frame of gravity has already come off it.
        XCTAssertEqual(match.ball.velocity.length, BallRules.shotSpeed, accuracy: 0.2)
    }

    func testReleaseWithoutFlickIsAPumpFake() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.shotWindupFrames + 5 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .idle)
        XCTAssertTrue(match.players[0].hasBall)
        XCTAssertEqual(match.ball.holder, 0)
    }

    func testTapIsAQuickshotOnThePresetArc() {
        var match = matchWithBallHeld()
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        run(&match, frames: BallRules.shotWindupFrames, input: { _ in .idle })
        XCTAssertEqual(match.players[0].state, .shooting)
        run(&match, frames: BallRules.shotReleaseFrames, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        XCTAssertEqual(match.ball.velocity.x, cos(BallRules.shotAngleDefault) * BallRules.shotSpeed, accuracy: 0.001)
        XCTAssertGreaterThan(match.ball.velocity.y, 0)
    }

    func testJumpShotReleasedOnTheRiseShootsWithLift() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.shotWindupFrames + 2 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        match.advance(inputs: [PlayerInput(jump: true, shoot: true), .idle])
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertGreaterThan(match.players[0].velocity.y, 0)
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .shooting)
        run(&match, frames: BallRules.shotReleaseFrames, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        let preset = sin(BallRules.shotAngleDefault) * BallRules.shotSpeed
        XCTAssertGreaterThan(match.ball.velocity.y, preset)
    }

    func testShooterHangsAfterAnAirShot() {
        var match = matchWithBallHeld()
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        for _ in 0..<BallRules.shotWindupFrames + 2 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        match.advance(inputs: [PlayerInput(aim: Vec2(x: 0.6, y: 0.8), shoot: true), .idle])
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .shooting)
        run(&match, frames: BallRules.shotReleaseFrames + 1, input: { _ in .idle })
        let heightAtRelease = match.players[0].position.y
        run(&match, frames: BallRules.shotHangFrames - 3, input: { _ in .idle })
        XCTAssertEqual(match.players[0].state, .shooting)
        XCTAssertEqual(match.players[0].position.y, heightAtRelease, accuracy: 0.001)
        XCTAssertEqual(match.players[0].animationFrame.animation, .shootAir)
        XCTAssertEqual(match.players[0].animationFrame.frame, Animation.shootAir.frameCount - 1)
    }

    func testJumpShotReleasedOnTheWayDownWithoutAFlickIsAFake() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.shotWindupFrames + 2 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        match.advance(inputs: [PlayerInput(jump: true, shoot: true), .idle])
        run(&match, frames: 60, input: { _ in PlayerInput(shoot: true) }) { $0.players[0].velocity.y < 0 }
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .air)
        XCTAssertTrue(match.players[0].hasBall)
    }

    func testASecondShootButtonCancelsTheShot() {
        var match = matchWithBallHeld()
        for _ in 0..<10 {
            match.advance(inputs: [PlayerInput(shootButtons: 2), .idle])
        }
        XCTAssertEqual(match.players[0].state, .shootStance)
        match.advance(inputs: [PlayerInput(shootButtons: 2 | 1), .idle])
        XCTAssertEqual(match.players[0].state, .idle)
        XCTAssertTrue(match.players[0].hasBall)
        // Still holding both: no new stance until they're all up.
        match.advance(inputs: [PlayerInput(shootButtons: 1), .idle])
        XCTAssertEqual(match.players[0].state, .idle)
        match.advance(inputs: [.idle, .idle])
        match.advance(inputs: [PlayerInput(shootButtons: 1), .idle])
        XCTAssertEqual(match.players[0].state, .shootStance)
    }

    func testThrowCancelsTheShotAndShootCancelsTheThrow() {
        var match = matchWithBallHeld()
        for _ in 0..<10 { match.advance(inputs: [PlayerInput(shoot: true), .idle]) }
        XCTAssertEqual(match.players[0].state, .shootStance)
        match.advance(inputs: [PlayerInput(shoot: true, throwBall: true), .idle])
        XCTAssertEqual(match.players[0].state, .idle)
        // Holding throw on after the cancel doesn't start a throw stance.
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertEqual(match.players[0].state, .idle)
        match.advance(inputs: [.idle, .idle])

        for _ in 0..<5 { match.advance(inputs: [PlayerInput(throwBall: true), .idle]) }
        XCTAssertEqual(match.players[0].state, .throwStance)
        match.advance(inputs: [PlayerInput(shoot: true, throwBall: true), .idle])
        XCTAssertEqual(match.players[0].state, .idle)
        XCTAssertTrue(match.players[0].hasBall)
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .idle)
    }

    func testReleaseBetweenTheTapAndTheHoldIsAFake() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.quickshotFrames + 4 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .idle)
        XCTAssertTrue(match.players[0].hasBall)
    }

    func testFloaterCarriesTheRunItStartedFrom() {
        for direction in [1.0, -1.0] {
            var match = Match()
            match.players[0].position.x = 150
            match.players[0].hasBall = true
            match.ball.holder = 0
            run(&match, frames: 25, input: { _ in PlayerInput(stick: Vec2(x: direction, y: 0)) })
            for _ in 0..<BallRules.throwWindupFrames + 2 {
                match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1), throwBall: true), .idle])
            }
            run(&match, frames: BallRules.throwReleaseFrames + 1, input: { _ in .idle })
            XCTAssertEqual(match.ball.velocity.x, direction * match.players[0].spec.runSpeed, accuracy: 0.001)
        }
    }

    func testShotAngleClampsToRange() {
        var player = Match().players[0]
        player.shotAim = Vec2(x: 0, y: 1)
        XCTAssertEqual(player.shotVelocity.angle, BallRules.shotAngleMax, accuracy: 0.001)
        player.shotAim = Vec2(x: 1, y: -1)
        XCTAssertEqual(player.shotVelocity.angle, BallRules.shotAngleMin, accuracy: 0.001)
    }

    func testThrowGoesStraightInTheStickCardinal() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.throwWindupFrames + 2 {
            match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), throwBall: true), .idle])
        }
        run(&match, frames: BallRules.throwReleaseFrames + 1, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        XCTAssertTrue(match.ball.straight)
        XCTAssertTrue(match.ball.thrown)
        XCTAssertEqual(match.ball.velocity, Vec2(x: BallRules.throwSpeed, y: 0))
    }

    func testUpThrowIsAFloater() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.throwWindupFrames + 2 {
            match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1), throwBall: true), .idle])
        }
        run(&match, frames: BallRules.throwReleaseFrames + 1, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        XCTAssertTrue(match.ball.thrown)
        XCTAssertEqual(match.ball.velocity.y, BallRules.floaterSpeed, accuracy: 0.001)
        // Still drifting up at the same speed well into the float, then falling.
        run(&match, frames: BallRules.floaterFrames - 5, input: { _ in .idle })
        XCTAssertEqual(match.ball.velocity.y, BallRules.floaterSpeed, accuracy: 0.001)
        run(&match, frames: 40, input: { _ in .idle })
        XCTAssertLessThan(match.ball.velocity.y, 0)
    }

    func testTapThrowGoesWhenTheWindupEnds() {
        var match = matchWithBallHeld()
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), throwBall: true), .idle])
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), throwBall: true), .idle])
        run(&match, frames: BallRules.throwWindupFrames + BallRules.throwReleaseFrames + 1, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        XCTAssertEqual(match.ball.velocity, Vec2(x: BallRules.throwSpeed, y: 0))
    }

    func testFastBallBouncesOffUnlessInCatchStance() {
        var match = Match()
        let chest = match.players[0].chest
        match.ball.respawn(at: chest + Vec2(x: 20, y: 0))
        match.ball.velocity = Vec2(x: -BallRules.throwSpeed, y: 0)
        run(&match, frames: 10, input: { _ in .idle }) { $0.ball.velocity.x > 0 || $0.ball.holder != nil }
        XCTAssertNil(match.ball.holder)
        XCTAssertGreaterThan(match.ball.velocity.x, 0, "a thrown ball should bounce off an idle body")

        var ready = Match()
        ready.ball.respawn(at: chest + Vec2(x: 20, y: 0))
        ready.ball.velocity = Vec2(x: -BallRules.throwSpeed, y: 0)
        run(&ready, frames: 10, input: { _ in PlayerInput(shoot: true) }) { $0.ball.holder != nil }
        XCTAssertEqual(ready.ball.holder, 0)
    }

    func testLooseBallInFrontIsCaught() {
        var match = Match()
        match.ball.position = match.players[0].chest + Vec2(x: 6, y: 0)
        match.ball.velocity = .zero
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.ball.holder, 0)
        XCTAssertEqual(match.players[0].state, .catching)
        XCTAssertTrue(match.events.contains(.caught(player: 0)))
    }

    func testBallBehindIsNotCaughtUnlessMovingIntoIt() {
        var match = Match()
        match.ball.position = match.players[0].chest + Vec2(x: -6, y: 0)
        match.ball.velocity = .zero
        match.advance(inputs: [.idle, .idle])
        XCTAssertNil(match.ball.holder)
        // Backing into it, still facing away, picks it up.
        match.players[0].velocity.x = -1
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -0.5, y: 0)), .idle])
        XCTAssertEqual(match.ball.holder, 0)
        XCTAssertEqual(match.players[0].facing, .right)
    }

    func testShotFallingBesideTheRimIsSteeredIn() {
        var match = Match()
        match.ball.position = match.stage.hoops[1].position + Vec2(x: -10, y: 20)
        match.ball.velocity = Vec2(x: 0.3, y: 0)
        for _ in 0..<120 where match.scores[0] == 0 {
            match.advance(inputs: [.idle, .idle])
        }
        XCTAssertEqual(match.scores, [1, 0])
    }

    func testBallThroughTheRimScores() {
        var match = Match()
        match.ball.position = match.stage.hoops[1].position + Vec2(x: 0, y: 20)
        match.ball.velocity = .zero
        for _ in 0..<120 where match.scores[0] == 0 {
            match.advance(inputs: [.idle, .idle])
        }
        XCTAssertEqual(match.scores, [1, 0])
        XCTAssertGreaterThan(match.ball.respawnTimer, 0)
    }

    func testThrownBallIgnoresTheRimsSteering() {
        var match = Match()
        let rim = match.stage.hoops[1].position
        // Falling beside the rim within reach: a shot gets steered across, a throw doesn't.
        for thrown in [false, true] {
            match.ball.respawn(at: rim + Vec2(x: -15, y: 10))
            match.ball.velocity = Vec2(x: 0, y: -1)
            match.ball.thrown = thrown
            match.advance(inputs: [.idle, .idle])
            if thrown {
                XCTAssertEqual(match.ball.velocity.x, 0)
            } else {
                XCTAssertGreaterThan(match.ball.velocity.x, 0)
            }
        }
    }

    func testSwatReversesTheBall() {
        var match = Match()
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        match.ball.position = match.players[0].chest + Vec2(x: 10, y: 0)
        match.ball.velocity = Vec2(x: -3, y: 0)
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertTrue(match.events.contains(.swatted(player: 0, hit: true)))
        XCTAssertGreaterThan(match.ball.velocity.x, 0)
    }

    func testStepsAreDeterministic() {
        var a = Match(), b = Match()
        for frame in 0..<300 {
            let input = PlayerInput(stick: Vec2(x: frame % 40 < 20 ? 1 : -1, y: 0), jump: frame % 50 < 6, shoot: frame % 90 > 60)
            a.advance(inputs: [input, .idle])
            b.advance(inputs: [input, .idle])
        }
        XCTAssertEqual(a, b)
    }

    @discardableResult
    private func run(_ match: inout Match, frames: Int, input: (Int) -> PlayerInput, until stop: ((Match) -> Bool)? = nil) -> Int {
        for frame in 0..<frames {
            match.advance(inputs: [input(frame), .idle])
            if let stop, stop(match) { return frame }
        }
        return frames
    }
}
