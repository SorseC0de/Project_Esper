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

    func testWalkingWithTheBallFacesTheOpponentEitherWay() {
        var match = Match()
        match.players[0].hasBall = true
        match.ball.holder = 0
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

    func testHoldingDownWithTheBallBrakesARunIntoAWalk() {
        var match = Match()
        match.players[0].hasBall = true
        match.ball.holder = 0
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

    func testWallJumpGivesTheDoubleJumpBack() {
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
        XCTAssertEqual(match.players[0].jumpsLeft, 1)
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

    func testTheBodyTurnsWithTheStickInTheAir() {
        var match = Match()
        run(&match, frames: 6, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0), jump: true) })
        XCTAssertEqual(match.players[0].facing, .right)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0)), .idle])
        XCTAssertEqual(match.players[0].facing, .left)
    }

    func testAWalkWithTheBallCanStillTurnForAFewFrames() {
        var match = Match()
        match.players[0].hasBall = true
        match.ball.holder = 0
        // Player 0 starts left of player 1, so a settled walk faces right.
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -0.5, y: 0)), .idle])
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -0.5, y: 0)), .idle])
        XCTAssertEqual(match.players[0].state, .walk)
        XCTAssertEqual(match.players[0].facing, .left)
        run(&match, frames: 6, input: { _ in PlayerInput(stick: Vec2(x: -0.5, y: 0)) })
        XCTAssertEqual(match.players[0].facing, .right)
    }

    func testAirReversalIsImmediate() {
        var match = Match()
        run(&match, frames: 6, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0), jump: true) })
        run(&match, frames: 5, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        XCTAssertGreaterThan(match.players[0].velocity.x, 0)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0)), .idle])
        XCTAssertEqual(match.players[0].velocity.x, -match.players[0].spec.airSpeedMax, accuracy: 0.001)
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
        XCTAssertEqual(match.ball.velocity.length, FighterSpec.baseline.shotSpeed, accuracy: 0.2)
    }

    func testReleaseWithoutFlickFollowsThroughOnThePresetArc() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.shotWindupFrames + 5 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .shooting)
        run(&match, frames: BallRules.shotReleaseFrames, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        XCTAssertEqual(match.ball.velocity.x, cos(BallRules.shotAngleDefault) * FighterSpec.baseline.shotSpeed, accuracy: 0.001)
    }

    func testDownOnTheGroundCancelsTheShot() {
        var match = matchWithBallHeld()
        for _ in 0..<10 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .idle)
        XCTAssertTrue(match.players[0].hasBall)
    }

    func testTapIsAQuickshotOnThePresetArc() {
        var match = matchWithBallHeld()
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        run(&match, frames: BallRules.shotWindupFrames, input: { _ in .idle })
        XCTAssertEqual(match.players[0].state, .shooting)
        run(&match, frames: BallRules.shotReleaseFrames, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        XCTAssertEqual(match.ball.velocity.x, cos(BallRules.shotAngleDefault) * FighterSpec.baseline.shotSpeed, accuracy: 0.001)
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
        let preset = sin(BallRules.shotAngleDefault) * FighterSpec.baseline.shotSpeed
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

    func testJumpShotReleasedOnTheWayDownIsAnOrdinaryShot() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.shotWindupFrames + 2 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        match.advance(inputs: [PlayerInput(jump: true, shoot: true), .idle])
        run(&match, frames: 60, input: { _ in PlayerInput(shoot: true) }) { $0.players[0].velocity.y < 0 }
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .shooting)
        XCTAssertFalse(match.players[0].shotLift)
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

    func testReleaseBeforeTheHoldFiresWhenTheWindupEnds() {
        var match = matchWithBallHeld()
        for _ in 0..<10 {
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
        }
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .shootStance)
        run(&match, frames: BallRules.shotWindupFrames, input: { _ in .idle })
        XCTAssertEqual(match.players[0].state, .shooting)
    }

    func testDropUnderALedgeReachesTheFloor() {
        let stage = Stage.court
        // Over the ledge itself there's no drop from its top; just past its end it's down to the floor.
        XCTAssertEqual(stage.drop(fromX: 165, y: 40), 0, accuracy: 0.001)
        XCTAssertEqual(stage.drop(fromX: 195, y: 40), 30, accuracy: 0.001)
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
            XCTAssertEqual(match.ball.velocity.x, direction * match.players[0].spec.runSpeed * BallRules.floaterMomentumShare, accuracy: 0.001)
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

    func testFastBallGoesThroughUnlessSnatched() {
        var match = Match()
        let chest = match.players[0].chest
        match.ball.respawn(at: chest + Vec2(x: 20, y: 0))
        match.ball.velocity = Vec2(x: -BallRules.throwSpeed, y: 0)
        let through = run(&match, frames: 10, input: { _ in .idle }) { $0.ball.position.x < chest.x - 10 || $0.ball.holder != nil }
        XCTAssertLessThan(through, 10)
        XCTAssertNil(match.ball.holder)
        XCTAssertLessThan(match.ball.velocity.x, 0, "a thrown ball should go straight through an idle body")

        // The snatch, pressed as it comes, takes it.
        var snatching = Match()
        snatching.ball.respawn(at: chest + Vec2(x: BallRules.throwSpeed * Double(SnatchRules.activeFrames.lowerBound + 3), y: 0))
        snatching.ball.velocity = Vec2(x: -BallRules.throwSpeed, y: 0)
        run(&snatching, frames: SnatchRules.activeFrames.upperBound, input: { _ in PlayerInput(throwBall: true) }) { $0.ball.holder != nil }
        XCTAssertEqual(snatching.ball.holder, 0)

        // Shoot held does nothing for it: the press is a slash, and after that it still goes through.
        var holding = Match()
        holding.players[1].position.x = 20
        holding.ball.respawn(at: chest + Vec2(x: 150, y: 0))
        holding.ball.velocity = Vec2(x: -6, y: 0)
        run(&holding, frames: 40, input: { _ in PlayerInput(shoot: true) }) { $0.ball.holder != nil }
        XCTAssertNil(holding.ball.holder)
    }

    /// Player 1 shoots a flat one from 120 out that comes down through player 0's chest,
    /// on the left side of the court where nothing is in the way.
    private func shotAtPlayerZero() -> Match {
        var match = Match()
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[1].position.x = 145
        match.players[1].facing = .left
        match.players[0].position.x = 25
        for _ in 0..<BallRules.shotWindupFrames + 2 { match.advance(inputs: [.idle, PlayerInput(shoot: true)]) }
        match.advance(inputs: [.idle, PlayerInput(aim: Vec2(x: -1, y: 0.3), shoot: true)])
        match.advance(inputs: [.idle, .idle])
        run(&match, frames: BallRules.shotReleaseFrames + 1, input: { _ in .idle })
        return match
    }

    func testAShotInFlightGoesThroughABodyUnlessItIsSnatched() {
        var match = shotAtPlayerZero()
        XCTAssertNil(match.ball.holder)
        XCTAssertTrue(match.ball.shotInFlight)
        var lowestOverBody = 100.0
        let passed = run(&match, frames: 60, input: { _ in .idle }) { match in
            if abs(match.ball.position.x - 25) < 5 { lowestOverBody = min(lowestOverBody, match.ball.position.y) }
            return match.ball.position.x < 18
        }
        XCTAssertLessThan(passed, 60, "the shot should go straight through")
        XCTAssertLessThan(lowestOverBody, 25 + 10, "it should have passed through the body, not over it")
        XCTAssertNil(match.ball.holder)

        // The same, with a snatch pressed as it comes: taken.
        var ready = shotAtPlayerZero()
        run(&ready, frames: 60, input: { _ in .idle }) { $0.ball.position.x - 25 < 45 }
        let caught = run(&ready, frames: 20, input: { _ in PlayerInput(throwBall: true) }) { $0.ball.holder == 0 }
        XCTAssertLessThan(caught, 20)
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

    func testBallThroughTheRimScoresAndThePointRestartsWithTheBallInTheOthersHands() {
        var match = Match(countdown: 30)
        match.countdown = 0
        match.players[0].position.x = 250
        match.ball.position = match.stage.hoops[1].position + Vec2(x: 0, y: 20)
        match.ball.velocity = .zero
        for _ in 0..<120 where match.scores[0] == 0 {
            match.advance(inputs: [.idle, .idle])
        }
        XCTAssertEqual(match.scores, [1, 0])
        XCTAssertTrue(match.events.contains { if case .scored(player: 0, hoop: 1, _) = $0 { return true } else { return false } })
        XCTAssertEqual(match.ball.holder, 1)
        XCTAssertTrue(match.players[1].hasBall)
        XCTAssertEqual(match.players[0].position, match.stage.playerSpawns[0])
        XCTAssertEqual(match.players[1].position, match.stage.playerSpawns[1])
        XCTAssertEqual(match.countdown, 30)
    }

    func testADunkHangsOnTheRimBeforeThePointRestarts() {
        var match = Match(countdown: 30)
        match.countdown = 0
        // In the air just inside the dunk's reach of the right rim, holding the ball.
        let rim = match.stage.hoops[1].position
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.players[0].position = rim + Vec2(x: -20, y: -BallRules.chestHeight)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        // The dunk turns the body to the backboard and glides it to its place on the rim
        // through the wind-up, from the throw stance's frame, the ball in hand until the slam.
        XCTAssertEqual(match.players[0].state, .dunking)
        XCTAssertEqual(match.players[0].facing, .right)
        let began = match.players[0].position
        XCTAssertEqual(match.players[0].animationFrame, AnimationFrame(.throwForward, 3))
        XCTAssertTrue(match.players[0].hasBall)
        XCTAssertEqual(match.scores, [0, 0])
        match.advance(inputs: [.idle, .idle])
        XCTAssertGreaterThan(match.players[0].position.distance(to: began), 0)
        XCTAssertLessThan(match.players[0].position.distance(to: began), 6, "it should glide, not jump")
        let scored = run(&match, frames: BallRules.dunkFrames, input: { _ in .idle }) { $0.scores[0] == 1 }
        XCTAssertLessThan(scored, BallRules.dunkFrames)
        // One frame already went to the glide check above.
        XCTAssertGreaterThanOrEqual(scored + 2, BallRules.dunkFrames / 2)
        XCTAssertEqual(match.players[0].position.x, rim.x + BallRules.dunkOffset.x, accuracy: 0.001)
        XCTAssertEqual(match.players[0].position.y, rim.y + BallRules.dunkOffset.y, accuracy: 0.001)
        XCTAssertEqual(match.players[0].animationFrame.animation, .dunk)
        XCTAssertEqual(match.restartIn, BallRules.dunkHangFrames)
        // Still hanging there, the point not yet restarted, for the beat.
        run(&match, frames: BallRules.dunkHangFrames - 2, input: { _ in .idle })
        XCTAssertEqual(match.players[0].state, .dunking)
        XCTAssertEqual(match.countdown, 0)
        run(&match, frames: 2, input: { _ in .idle })
        XCTAssertEqual(match.countdown, 30 - 1)
        XCTAssertEqual(match.ball.holder, 1)
        XCTAssertEqual(match.players[0].position, match.stage.playerSpawns[0])
    }

    func testAThrowStanceInTheAirKeepsItsRun() {
        var match = Match()
        match.players[0].hasBall = true
        match.ball.holder = 0
        run(&match, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        run(&match, frames: 6, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0), jump: true) })
        XCTAssertEqual(match.players[0].state, .air)
        let entry = match.players[0].velocity.x
        run(&match, frames: 10, input: { _ in PlayerInput(throwBall: true) })
        XCTAssertEqual(match.players[0].state, .throwStance)
        XCTAssertGreaterThan(match.players[0].velocity.x, entry - 10 * match.players[0].spec.throwStanceAirBrake - 0.001)
        XCTAssertGreaterThan(match.players[0].velocity.x, entry * 0.8)
    }

    func testTheCountHoldsEveryoneStill() {
        var match = Match(countdown: 10)
        let start = match.players[0].position
        run(&match, frames: 10, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0), jump: true) })
        XCTAssertEqual(match.players[0].position, start)
        XCTAssertEqual(match.players[0].state, .idle)
        run(&match, frames: 10, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        XCTAssertGreaterThan(match.players[0].position.x, start.x)
    }

    func testOnlyABallThatStillSteersIsPulledByTheRim() {
        var match = Match()
        let rim = match.stage.hoops[1].position
        // Falling beside the rim within reach: a steering ball is pulled across, another isn't.
        for steers in [true, false] {
            match.ball.respawn(at: rim + Vec2(x: -15, y: 10))
            match.ball.velocity = Vec2(x: 0, y: -1)
            match.ball.steers = steers
            match.advance(inputs: [.idle, .idle])
            if steers {
                XCTAssertGreaterThan(match.ball.velocity.x, 0)
            } else {
                XCTAssertEqual(match.ball.velocity.x, 0)
            }
        }
    }

    func testAShotSteersUntilItsFirstBounceAndAThrowNever() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.shotWindupFrames + 2 { match.advance(inputs: [PlayerInput(shoot: true), .idle]) }
        match.advance(inputs: [.idle, .idle])
        run(&match, frames: BallRules.shotReleaseFrames, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        XCTAssertTrue(match.ball.steers)
        run(&match, frames: 200, input: { _ in .idle }) { $0.events.contains { if case .ballBounced = $0 { return true } else { return false } } }
        XCTAssertFalse(match.ball.steers)

        var thrown = matchWithBallHeld()
        for _ in 0..<BallRules.throwWindupFrames + 2 { thrown.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), throwBall: true), .idle]) }
        run(&thrown, frames: BallRules.throwReleaseFrames + 1, input: { _ in .idle })
        XCTAssertNil(thrown.ball.holder)
        XCTAssertFalse(thrown.ball.steers)
    }

    func testTheFloaterSteers() {
        var match = matchWithBallHeld()
        for _ in 0..<BallRules.throwWindupFrames + 2 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1), throwBall: true), .idle]) }
        run(&match, frames: BallRules.throwReleaseFrames + 1, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        XCTAssertTrue(match.ball.thrown)
        XCTAssertTrue(match.ball.steers)
    }

    func testRisingUpThroughTheRimThenFallingBackIsNotAScore() {
        var match = Match()
        // Straight up through the rim from under it, then down through it again.
        match.ball.respawn(at: match.stage.hoops[1].position + Vec2(x: 0, y: -10))
        match.ball.velocity = Vec2(x: 0, y: 4)
        run(&match, frames: 120, input: { _ in .idle }) { $0.ball.position.y < $0.stage.hoops[1].position.y - 10 && $0.ball.velocity.y < 0 }
        XCTAssertEqual(match.scores, [0, 0])
        XCTAssertNil(match.ball.roseThrough)
    }

    func testABallInTheSparkRingIsCaught() {
        var match = Match()
        // Outside the chest ring, inside the spark's ring out front.
        let at = match.players[0].handCatchPoint + Vec2(x: 6, y: 5)
        XCTAssertGreaterThan(at.distance(to: match.players[0].chest), BallRules.catchRadius)
        match.ball.respawn(at: at)
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.ball.holder, 0)
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

final class WebWaterTests: XCTestCase {
    /// Both on Web Water at level two, the line included.
    private func webbed() -> Match {
        var match = Match()
        for index in match.players.indices {
            match.players[index].power = .webWater
            match.players[index].powerLevel = 2
        }
        return match
    }

    func testTheWebLineWaitsForLevelTwo() {
        var match = webbed()
        match.players[0].powerLevel = 1
        match.ball.respawn(at: match.players[0].chest + Vec2(x: 60, y: 0))
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertFalse(match.players[0].webAiming)
        XCTAssertEqual(match.players[0].state, .snatching)
    }

    @discardableResult
    private func run(_ match: inout Match, frames: Int, input: (Int) -> PlayerInput, other: PlayerInput = .idle, until stop: ((Match) -> Bool)? = nil) -> Int {
        for frame in 0..<frames {
            match.advance(inputs: [input(frame), other])
            if let stop, stop(match) { return frame }
        }
        return frames
    }

    func testDoubleJumpIsASwingThatComesOutHigherAndForward() {
        var match = webbed()
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 10, input: { _ in .idle })
        let halt = match.players[0].position
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .webSwing)
        XCTAssertNotNil(match.players[0].webAnchor)
        var lowest = halt.y
        run(&match, frames: WebRules.swingFrames * 3, input: { _ in .idle }) { match in
            lowest = min(lowest, match.players[0].position.y)
            return match.players[0].state != .webSwing
        }
        XCTAssertEqual(match.players[0].state, .air)
        XCTAssertLessThan(lowest, halt.y, "the swing should dip under the anchor first")
        XCTAssertGreaterThan(match.players[0].position.y, halt.y, "and come out higher than it halted")
        XCTAssertGreaterThan(match.players[0].position.x, halt.x)
        XCTAssertGreaterThan(match.players[0].velocity.x, 0)
    }

    func testHeldJumpLengthensTheSwing() {
        func swing(holding: Bool) -> (frames: Int, x: Double) {
            var match = webbed()
            run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
            run(&match, frames: 10, input: { _ in .idle })
            match.advance(inputs: [PlayerInput(jump: true), .idle])
            let frames = run(&match, frames: 120, input: { _ in PlayerInput(jump: holding) }) { $0.players[0].state != .webSwing }
            return (frames, match.players[0].position.x)
        }
        let short = swing(holding: false)
        let long = swing(holding: true)
        XCTAssertGreaterThan(long.frames, short.frames)
        XCTAssertGreaterThan(long.x, short.x)
    }

    func testWebWaterClingsWithoutSliding() {
        var match = webbed()
        match.players[0].position = Vec2(x: 30, y: 10)
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 120, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) }) { $0.players[0].state == .wallLand }
        let height = match.players[0].position.y
        run(&match, frames: 60, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) })
        XCTAssertEqual(match.players[0].state, .wallLand)
        XCTAssertEqual(match.players[0].position.y, height, accuracy: 0.001)
    }

    /// High up, in the air, still, with nothing near.
    private func aloft() -> Match {
        var match = webbed()
        match.players[0].position = Vec2(x: 100, y: 100)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.ball.respawn(at: Vec2(x: 300, y: 30))
        match.advance(inputs: [.idle, .idle])
        return match
    }

    func testTheSwingIsACooldownNotTheDoubleJump() {
        var match = aloft()
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .webSwing)
        // Let go at once: the least arc, then the air, and the cooldown starts as it ends.
        run(&match, frames: 60, input: { _ in .idle }) { $0.players[0].state != .webSwing }
        XCTAssertEqual(match.players[0].state, .air)
        XCTAssertEqual(match.players[0].swingCooldown, WebRules.swingCooldownFrames)
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .air, "no swing inside the cooldown")
        run(&match, frames: 10, input: { _ in .idle })
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .air, "still none, halfway through it")
        run(&match, frames: WebRules.swingCooldownFrames, input: { _ in .idle }) { $0.players[0].swingCooldown == 0 }
        XCTAssertFalse(match.players[0].grounded)
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .webSwing, "the cooldown over, it swings again without landing")
    }

    func testAFullSwingCannotChainStraightIntoAnother() {
        var match = aloft()
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        run(&match, frames: 120, input: { _ in PlayerInput(jump: true) }) { $0.players[0].state != .webSwing }
        XCTAssertEqual(match.players[0].state, .air)
        // A fresh press straight after the full swing.
        match.advance(inputs: [.idle, .idle])
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .air)
        XCTAssertGreaterThan(match.players[0].swingCooldown, 0)
    }

    func testAFullSwingFitsInsideTheCooldown() {
        var match = aloft()
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        let full = run(&match, frames: 120, input: { _ in PlayerInput(jump: true) }) { $0.players[0].state != .webSwing }
        XCTAssertLessThanOrEqual(full + 1, WebRules.swingCooldownFrames)
        XCTAssertGreaterThan(full + 4, WebRules.swingCooldownFrames, "the cooldown is a full swing's frames, not much more")
    }

    func testWebLineFiresFromAWall() {
        var match = webbed()
        match.players[0].position = Vec2(x: 30, y: 10)
        match.ball.respawn(at: Vec2(x: 90, y: 40))
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 120, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0)) }) { $0.players[0].state == .wallLand }
        XCTAssertEqual(match.players[0].state, .wallLand)
        match.ball.respawn(at: match.players[0].chest + Vec2(x: 70, y: 0))
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), throwBall: true), .idle])
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), throwBall: true), .idle])
        XCTAssertEqual(match.players[0].state, .wallLand, "aiming shouldn't drop the cling")
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle])
        XCTAssertEqual(match.ball.tether, 0)
    }

    func testWebLineBendsToANearbyBall() {
        var match = webbed()
        // The ball sits 60 out and 10 up: about 9 degrees off a flat aim, inside the assist.
        match.ball.respawn(at: match.players[0].chest + Vec2(x: 60, y: 10))
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), throwBall: true), .idle])
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.ball.tether, 0)
    }

    func testWebLineReelsInALooseBall() {
        var match = webbed()
        match.ball.respawn(at: match.players[0].chest + Vec2(x: 60, y: 0))
        match.ball.velocity = .zero
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertTrue(match.players[0].webAiming)
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.ball.tether, 0)
        XCTAssertTrue(match.events.contains(.webLine(player: 0, hit: true)))
        run(&match, frames: 30, input: { _ in .idle }) { $0.ball.holder != nil }
        XCTAssertEqual(match.ball.holder, 0)
        XCTAssertNil(match.players[0].webLine)
    }

    func testAMissedLineStaysLiveWhileItShows() {
        var match = webbed()
        // Fired flat ahead at nothing, the other behind, then the ball drops through it a few frames later.
        match.players[1].position.x = 30
        match.ball.respawn(at: Vec2(x: 300, y: 30))
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), throwBall: true), .idle])
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle])
        XCTAssertTrue(match.events.contains(.webLine(player: 0, hit: false)))
        XCTAssertNil(match.ball.tether)
        match.ball.respawn(at: match.players[0].chest + Vec2(x: 60, y: 20))
        match.ball.velocity = Vec2(x: 0, y: -4)
        let snagged = run(&match, frames: WebRules.missFrames, input: { _ in .idle }) { $0.ball.tether == 0 }
        XCTAssertLessThan(snagged, WebRules.missFrames, "the ball crossed the line while it showed and wasn't taken")
    }

    func testTheSwingIsTheSameAtAnyHeight() {
        func swing(from height: Double) -> (dip: Double, travel: Double) {
            var match = webbed()
            match.players[0].position = Vec2(x: 100, y: height)
            match.players[0].grounded = false
            match.players[0].enter(.air)
            match.advance(inputs: [.idle, .idle])
            let start = match.players[0].position
            match.advance(inputs: [PlayerInput(jump: true), .idle])
            XCTAssertEqual(match.players[0].state, .webSwing)
            var lowest = start.y
            run(&match, frames: 120, input: { _ in .idle }) { match in
                lowest = min(lowest, match.players[0].position.y)
                return match.players[0].state != .webSwing
            }
            return (start.y - lowest, match.players[0].position.x - start.x)
        }
        let low = swing(from: 40)
        let high = swing(from: 140)
        XCTAssertEqual(low.dip, high.dip, accuracy: 0.5)
        XCTAssertEqual(low.travel, high.travel, accuracy: 0.5)
    }

    func testWebLineTakesTheBallOffTheOpponent() {
        var match = webbed()
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[1].position.x = match.players[0].position.x + 50
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        match.advance(inputs: [.idle, .idle])
        XCTAssertFalse(match.players[1].hasBall)
        XCTAssertEqual(match.ball.tether, 0)
        run(&match, frames: 30, input: { _ in .idle }) { $0.ball.holder != nil }
        XCTAssertEqual(match.ball.holder, 0)
    }

    func testWebLineDragsTheOpponentInFront() {
        var match = webbed()
        match.players[1].position.x = match.players[0].position.x + 60
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[1].state, .webbed)
        run(&match, frames: WebRules.pullMaxFrames + 2, input: { _ in .idle }) { $0.players[1].state != .webbed }
        XCTAssertNotEqual(match.players[1].state, .webbed)
        XCTAssertEqual(match.players[1].position.x, match.players[0].position.x + WebRules.dropDistance, accuracy: 1.5)
    }

    func testWebLineAtAWallReelsTheShooterToIt() {
        var match = webbed()
        match.players[0].position = Vec2(x: 60, y: 10)
        match.players[0].facing = .left
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), throwBall: true), .idle])
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .webPull)
        run(&match, frames: WebRules.pullMaxFrames + 2, input: { _ in .idle }) { $0.players[0].state != .webPull }
        XCTAssertLessThan(match.players[0].body.min.x, 16, "should end up against the left wall")
    }

    func testNoPowerNoWebAndTheBallStillThrows() {
        var plain = Match()
        plain.ball.respawn(at: plain.players[0].chest + Vec2(x: 60, y: 0))
        plain.advance(inputs: [PlayerInput(throwBall: true), .idle])
        plain.advance(inputs: [.idle, .idle])
        XCTAssertNil(plain.ball.tether)
        XCTAssertFalse(plain.events.contains { if case .webLine = $0 { return true } else { return false } })

        var match = webbed()
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertEqual(match.players[0].state, .throwStance)
    }
}


final class SodaAndFizzTests: XCTestCase {
    /// Both on the power, at level two unless said otherwise.
    private func with(_ power: Power, level: Int = 2) -> Match {
        var match = Match()
        for index in match.players.indices {
            match.players[index].power = power
            match.players[index].powerLevel = level
        }
        return match
    }

    func testLevelTwoSodaFliesFasterAndLonger() {
        XCTAssertEqual(SmoothieRules.flightSpeed(level: 2, withBall: true), SmoothieRules.flightSpeed(level: 1, withBall: false))
        XCTAssertGreaterThan(SmoothieRules.flightSpeed(level: 2, withBall: false), SmoothieRules.flightSpeed(level: 1, withBall: false))
        XCTAssertGreaterThan(SmoothieRules.flightFrames(level: 2), SmoothieRules.flightFrames(level: 1))
        var match = with(.superSmoothie, level: 2)
        match.ball.respawn(at: Vec2(x: 300, y: 30))
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 10, input: { _ in .idle })
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) }) { $0.players[0].state == .flying }
        // Backward is the drift at the flight speed; forward is the glide, faster.
        run(&match, frames: 5, input: { _ in PlayerInput(stick: Vec2(x: -1, y: 0), jump: true) })
        XCTAssertEqual(match.players[0].velocity.x, -SmoothieRules.flightSpeed(level: 2, withBall: false), accuracy: 0.001)
    }

    func testFlightNeedsNoSecondJump() {
        var match = Match(specs: [.starting, .starting])
        match.players[0].power = .superSmoothie
        match.ball.respawn(at: Vec2(x: 300, y: 30))
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 10, input: { _ in .idle })
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) }) { $0.players[0].state == .flying }
        XCTAssertEqual(match.players[0].state, .flying)
    }

    func testLevelOneFizzFlashesWithoutATearAndLevelTwoTearsBothEnds() {
        var one = with(.flashFizz, level: 1)
        one.players[1].position.x = 300
        one.ball.respawn(at: Vec2(x: 300, y: 30))
        one.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), shoot: true), .idle])
        XCTAssertEqual(one.players[0].position.x, 130 + FizzRules.flashDistance(level: 1), accuracy: 0.001)
        XCTAssertNil(one.players[0].tear)

        // Level two: further, and the other holding the ball where it came out loses it to
        // the tear on the spot.
        var two = with(.flashFizz, level: 2)
        two.players[1].hasBall = true
        two.ball.holder = 1
        two.players[1].position.x = 130 + FizzRules.flashDistance(level: 2) + 8
        two.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), shoot: true), .idle])
        XCTAssertEqual(two.players[0].position.x, 130 + FizzRules.flashDistance(level: 2), accuracy: 0.001)
        XCTAssertTrue(two.events.contains(.popped(player: 1, by: 0)))
        XCTAssertFalse(two.players[1].hasBall)
        XCTAssertEqual(two.ball.holder, 0)
    }

    @discardableResult
    private func run(_ match: inout Match, frames: Int, input: (Int) -> PlayerInput, until stop: ((Match) -> Bool)? = nil) -> Int {
        for frame in 0..<frames {
            match.advance(inputs: [input(frame), .idle])
            if let stop, stop(match) { return frame }
        }
        return frames
    }

    func testHeldJumpInTheAirIsFlightThatIgnoresGravity() {
        var match = with(.superSmoothie, level: 1)
        match.ball.respawn(at: Vec2(x: 300, y: 30))
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 10, input: { _ in .idle })
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) }) { $0.players[0].state == .flying }
        XCTAssertEqual(match.players[0].state, .flying)
        let height = match.players[0].position.y
        run(&match, frames: 30, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0), jump: true) })
        XCTAssertEqual(match.players[0].state, .flying)
        XCTAssertEqual(match.players[0].position.y, height, accuracy: 0.001)
        XCTAssertEqual(match.players[0].velocity.x, SmoothieRules.flightSpeed(level: 1, withBall: false), accuracy: 0.001)
        // Let go and it falls.
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .air)
    }

    func testFlightCancelsIntoTheSlashAndTheSnatch() {
        for (input, state) in [(PlayerInput(jump: true, shoot: true), PlayerState.slashing), (PlayerInput(jump: true, throwBall: true), PlayerState.snatching)] {
            var match = with(.superSmoothie)
            match.players[1].hasBall = true
            match.ball.holder = 1
            match.players[1].position.x = 300
            run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
            run(&match, frames: 10, input: { _ in .idle })
            run(&match, frames: 6, input: { _ in PlayerInput(jump: true) }) { $0.players[0].state == .flying }
            XCTAssertEqual(match.players[0].state, .flying)
            match.advance(inputs: [input, .idle])
            XCTAssertEqual(match.players[0].state, state)
        }
    }

    func testFlightRunsOutAndRefillsOnLanding() {
        var match = with(.superSmoothie, level: 1)
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 10, input: { _ in .idle })
        let budget = SmoothieRules.flightFrames(level: 1)
        let ended = run(&match, frames: budget + 20, input: { _ in PlayerInput(jump: true) }) { $0.players[0].state == .air && $0.players[0].flightLeft <= 0 }
        XCTAssertLessThan(ended, budget + 20)
        run(&match, frames: 200, input: { _ in .idle }) { $0.players[0].grounded }
        XCTAssertEqual(match.players[0].flightLeft, budget)
    }

    func testWarpToYourOwnBallAndCatchIt() {
        var match = with(.flashFizz)
        match.players[0].hasBall = true
        match.ball.holder = 0
        for _ in 0..<BallRules.throwWindupFrames + 2 {
            match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), throwBall: true), .idle])
        }
        run(&match, frames: BallRules.throwReleaseFrames + 8, input: { _ in .idle })
        XCTAssertEqual(match.ball.owner, 0)
        let ballWas = match.ball.position
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), shoot: true), .idle])
        XCTAssertTrue(match.events.contains { if case .warped(player: 0, _, _) = $0 { return true } else { return false } })
        XCTAssertEqual(match.ball.holder, 0)
        XCTAssertEqual(match.players[0].position.x, ballWas.x, accuracy: 0.001)
    }

    func testAFlashAlongTheStickTearsANearbyBallIntoTheHands() {
        var match = with(.flashFizz)
        match.players[1].position.x = 300
        // A ball out of every ring's reach, but within the tear's once the flash lands.
        match.ball.respawn(at: match.players[0].position + Vec2(x: FizzRules.flashDistance(level: 2) + 4, y: 15))
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), shoot: true), .idle])
        XCTAssertTrue(match.events.contains { if case .flashed(player: 0, _, _) = $0 { return true } else { return false } })
        XCTAssertEqual(match.players[0].position.x, 130 + FizzRules.flashDistance(level: 2), accuracy: 0.001)
        XCTAssertEqual(match.ball.holder, 0)
    }

    func testAFlashInPlaceTearsABallBehindIn() {
        var match = with(.flashFizz)
        match.players[1].position.x = 300
        // Behind, where the rings don't catch it standing still.
        match.ball.respawn(at: match.players[0].chest + Vec2(x: -10, y: 5))
        match.advance(inputs: [.idle, .idle])
        XCTAssertNil(match.ball.holder)
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].position.x, 130, accuracy: 0.001)
        XCTAssertEqual(match.ball.holder, 0)
    }

    func testAFlashPastTheBallLeavesIt() {
        var match = with(.flashFizz)
        match.players[1].position.x = 300
        match.ball.respawn(at: match.players[0].chest + Vec2(x: 70, y: 0))
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), shoot: true), .idle])
        XCTAssertNil(match.ball.holder)
        XCTAssertNotNil(match.players[0].tear)
    }

    func testAFlashIntoTheFloorArrivesClearOfIt() {
        var match = with(.flashFizz)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        XCTAssertFalse(match.stage.overlapsSolid(match.players[0].body))
        XCTAssertGreaterThanOrEqual(match.players[0].position.y, 10)
    }

    func testOverhangDribbleCanBeWarpedDownTo() {
        var match = with(.flashFizz)
        // On the right backboard block, feet at its left edge, facing left, dribbling.
        match.players[0].position = Vec2(x: 290.5, y: 90)
        match.players[0].facing = .left
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.players[1].position.x = 100
        match.advance(inputs: [.idle, .idle])
        XCTAssertTrue(match.players[0].grounded)
        // Some dribble frame puts the ball past the edge.
        var found = false
        for _ in 0..<60 where !found {
            match.advance(inputs: [.idle, .idle])
            if match.players[0].overhangBall(in: match.stage) != nil {
                found = true
                match.advance(inputs: [PlayerInput(shoot: true), .idle])
            }
        }
        XCTAssertTrue(found, "no dribble frame overhung the block")
        XCTAssertTrue(match.events.contains { if case .warped(player: 0, _, _) = $0 { return true } else { return false } })
        XCTAssertTrue(match.players[0].hasBall)
        XCTAssertEqual(match.players[0].position.y, 10, accuracy: 0.001)
    }

    func testFlashFizzHasNoSlashOnDefence() {
        var match = with(.flashFizz)
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[1].position.x = 300
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertNotEqual(match.players[0].state, .slashing)
        XCTAssertTrue(match.events.contains { if case .flashed = $0 { return true } else { return false } })
    }
}

final class ShakeTests: XCTestCase {
    /// Both on the shake at level two, the wall included.
    private func shaken() -> Match {
        var match = Match()
        for index in match.players.indices {
            match.players[index].power = .platformShake
            match.players[index].powerLevel = 2
        }
        match.ball.respawn(at: Vec2(x: 300, y: 30))
        return match
    }

    func testTheWallWaitsForLevelTwo() {
        var match = shaken()
        match.players[0].powerLevel = 1
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .slashing)
    }

    @discardableResult
    private func run(_ match: inout Match, frames: Int, input: (Int) -> PlayerInput, until stop: ((Match) -> Bool)? = nil) -> Int {
        for frame in 0..<frames {
            match.advance(inputs: [input(frame), .idle])
            if let stop, stop(match) { return frame }
        }
        return frames
    }

    /// A full hop, then a fast fall at the apex.
    private func fastFallFromTheApex(_ match: inout Match) {
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 60, input: { _ in .idle }) { $0.players[0].velocity.y <= 0 }
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1)), .idle])
    }

    func testFastFallMakesAPlatformYouLandOn() {
        var match = shaken()
        fastFallFromTheApex(&match)
        XCTAssertEqual(match.platforms.count, 1)
        XCTAssertTrue(match.events.contains(.platformMade(player: 0)))
        let top = match.platforms[0].box.max.y
        XCTAssertGreaterThan(top, 30)
        run(&match, frames: 10, input: { _ in .idle }) { $0.players[0].grounded }
        XCTAssertTrue(match.players[0].grounded)
        XCTAssertEqual(match.players[0].position.y, top, accuracy: 0.001)
        XCTAssertEqual(match.players[0].jumpsLeft, match.players[0].spec.jumps)
    }

    func testPlatformDissipatesAndYouFall() {
        var match = shaken()
        fastFallFromTheApex(&match)
        run(&match, frames: 10, input: { _ in .idle }) { $0.players[0].grounded }
        let standing = match.players[0].position.y
        run(&match, frames: ShakeRules.platformFrames + 2, input: { _ in .idle })
        XCTAssertTrue(match.platforms.isEmpty)
        run(&match, frames: 5, input: { _ in .idle })
        XCTAssertLessThan(match.players[0].position.y, standing)
    }

    func testAnotherPlatformWaitsForTheCooldown() {
        var match = shaken()
        fastFallFromTheApex(&match)
        run(&match, frames: 10, input: { _ in .idle }) { $0.players[0].grounded }
        XCTAssertEqual(match.platforms.count, 1)
        // Jump off it and fast fall again while it stands: inside the cooldown, nothing.
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 60, input: { _ in .idle }) { $0.players[0].velocity.y <= 0 }
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1)), .idle])
        XCTAssertEqual(match.platforms.count, 1)
    }

    func testAnotherPlatformNeedsAJumpSinceTheLast() {
        var match = shaken()
        fastFallFromTheApex(&match)
        run(&match, frames: 10, input: { _ in .idle }) { $0.players[0].grounded }
        XCTAssertEqual(match.platforms.count, 1)
        // Stand on it till it goes, drop to the floor, and wait out the cooldown.
        run(&match, frames: 200, input: { _ in .idle }) { $0.players[0].grounded && $0.players[0].position.y < 15 && $0.players[0].platformCooldown == 0 }
        XCTAssertTrue(match.platforms.isEmpty)
        // Up in the air with no jump, holding down: still nothing.
        match.players[0].position.y = 60
        match.players[0].grounded = false
        match.players[0].enter(.air)
        run(&match, frames: 40, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) }) { $0.players[0].grounded }
        XCTAssertTrue(match.platforms.isEmpty, "a fall with no jump since the last slab shouldn't make one")
        // A jump arms it again.
        run(&match, frames: 10, input: { _ in .idle })
        fastFallFromTheApex(&match)
        XCTAssertEqual(match.platforms.count, 1)
    }

    func testShootWithoutTheBallMakesAWallInFront() {
        var match = shaken()
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .walling)
        run(&match, frames: ShakeRules.wallAppearFrame, input: { _ in .idle }) { !$0.platforms.isEmpty }
        XCTAssertEqual(match.platforms.count, 1)
        let wall = match.platforms[0].box
        XCTAssertEqual(wall.min.x, 130 + 5 + 2, accuracy: 0.001)
        XCTAssertEqual(wall.width, ShakeRules.wallWidth, accuracy: 0.001)
        XCTAssertEqual(wall.min.y, 10, accuracy: 0.001)
        XCTAssertEqual(wall.height, ShakeRules.wallHeight, accuracy: 0.001)
        XCTAssertEqual(match.players[0].platformCooldown, ShakeRules.cooldownFrames)
        // Walking into it stops at it.
        run(&match, frames: 40, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        XCTAssertLessThanOrEqual(match.players[0].body.max.x, wall.min.x + 0.001)
    }

    func testPlatformBlocksTheBall() {
        var match = shaken()
        fastFallFromTheApex(&match)
        let box = match.platforms[0].box
        match.ball.respawn(at: Vec2(x: box.center.x, y: box.max.y + 20))
        match.ball.velocity = .zero
        run(&match, frames: 30, input: { _ in .idle }) { $0.ball.velocity.y == 0 && $0.ball.position.y > box.max.y }
        XCTAssertGreaterThanOrEqual(match.ball.position.y, box.max.y)
    }
}

/// Without the ball: the crouch, the slide, the Esper Slash, the snatch and the ledge.
final class FootsiesTests: XCTestCase {
    @discardableResult
    private func run(_ match: inout Match, frames: Int, input: (Int) -> PlayerInput, until stop: ((Match) -> Bool)? = nil) -> Int {
        for frame in 0..<frames {
            match.advance(inputs: [input(frame), .idle])
            if let stop, stop(match) { return frame }
        }
        return frames
    }

    /// Nobody's ball, parked out of everyone's reach.
    private func neutral() -> Match {
        var match = Match()
        match.ball.respawn(at: Vec2(x: 300, y: 30))
        return match
    }

    /// The other holding the ball, standing at `x`: player 0 on defence.
    private func defending(otherAt x: Double = 300) -> Match {
        var match = Match()
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[1].position.x = x
        return match
    }

    // MARK: Crouch

    func testDownWithoutTheBallCrouchesAndCrouchWalks() {
        var match = neutral()
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1)), .idle])
        XCTAssertEqual(match.players[0].state, .crouch)
        run(&match, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: -0.7, y: -0.7)) })
        XCTAssertEqual(match.players[0].state, .crouchWalk)
        XCTAssertEqual(match.players[0].facing, .left)
        XCTAssertEqual(match.players[0].velocity.x, -match.players[0].spec.crouchWalkSpeed * 0.7, accuracy: 0.001)
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .idle)
    }

    func testDownWithTheBallStaysStanding() {
        var match = Match()
        match.players[0].hasBall = true
        match.ball.holder = 0
        run(&match, frames: 5, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) })
        XCTAssertEqual(match.players[0].state, .idle)
    }

    func testAWalkWithoutTheBallFacesTheStick() {
        var match = neutral()
        // Player 0 starts left of player 1; walking away keeps facing away.
        run(&match, frames: 30, input: { _ in PlayerInput(stick: Vec2(x: -0.5, y: 0)) })
        XCTAssertEqual(match.players[0].state, .walk)
        XCTAssertEqual(match.players[0].facing, .left)
    }

    // MARK: Slide

    func testDownAtFullRunIsASlideAtTheDashBurst() {
        var match = neutral()
        run(&match, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        XCTAssertEqual(match.players[0].state, .run)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0.7, y: -0.7)), .idle])
        XCTAssertEqual(match.players[0].state, .slide)
        XCTAssertTrue(match.events.contains(.slid(player: 0)))
        XCTAssertEqual(match.players[0].velocity.x, match.players[0].spec.dashInitialVelocity, accuracy: 0.001)
        // Held down through it, it ends in a crouch still carrying most of the burst.
        let frames = match.players[0].spec.slideFrames
        let ended = run(&match, frames: frames + 2, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) }) { $0.players[0].state != .slide }
        XCTAssertLessThanOrEqual(ended, frames)
        XCTAssertEqual(match.players[0].state, .crouch)
        XCTAssertGreaterThan(match.players[0].velocity.x, match.players[0].spec.dashInitialVelocity - 0.5)
    }

    func testShootWhileCrouchedIsASlide() {
        var match = neutral()
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1)), .idle])
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .slide)
        XCTAssertEqual(match.players[0].velocity.x, match.players[0].spec.dashInitialVelocity, accuracy: 0.001)
    }

    func testSlideKnocksTheBallOutOfAGroundedHoldersHands() {
        var match = defending(otherAt: 230)
        run(&match, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        XCTAssertEqual(match.players[0].state, .run)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0.7, y: -0.7)), .idle])
        XCTAssertEqual(match.players[0].state, .slide)
        let frames = match.players[0].spec.slideFrames
        let hit = run(&match, frames: frames, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) }) { $0.events.contains(.popped(player: 1, by: 0)) }
        XCTAssertLessThan(hit, frames, "the leg never reached them")
        XCTAssertFalse(match.players[1].hasBall)
        // Popped straight up, nobody's, and the slider's hand ring is right there to take it.
        XCTAssertNil(match.ball.owner)
        XCTAssertNotEqual(match.ball.holder, 1)
    }

    func testSlideLeavesAnAirborneHolderAlone() {
        var match = defending(otherAt: 142)
        // Just off the ground and rising, over the leg's height.
        match.players[1].position.y = 10.5
        match.players[1].velocity.y = 1
        match.players[1].grounded = false
        match.players[1].enter(.air)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1)), .idle])
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .slide)
        let popped = run(&match, frames: 4, input: { _ in .idle }) { $0.events.contains(.popped(player: 1, by: 0)) }
        XCTAssertEqual(popped, 4)
        XCTAssertTrue(match.players[1].hasBall)
    }

    // MARK: Esper Slash

    func testShootOnDefenceIsTheEsperSlashAndOnTheGroundItEndsThere() {
        var match = defending()
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .slashing)
        XCTAssertTrue(match.events.contains(.slashed(player: 0)))
        XCTAssertTrue(match.players[0].grounded, "from the ground the swing is planted")
        let swung = run(&match, frames: SlashRules.frames + 2, input: { _ in .idle }) { $0.players[0].state != .slashing }
        XCTAssertEqual(swung + 1, SlashRules.frames)
        XCTAssertEqual(match.players[0].state, .idle)
        XCTAssertTrue(match.players[0].grounded)
    }

    func testARunCarriesIntoASlashAndASnatch() {
        var slashing = defending()
        run(&slashing, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        XCTAssertEqual(slashing.players[0].state, .run)
        slashing.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(slashing.players[0].state, .slashing)
        run(&slashing, frames: 6, input: { _ in .idle })
        XCTAssertGreaterThan(slashing.players[0].velocity.x, 2, "the run should still be carrying it")

        var snatching = neutral()
        run(&snatching, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        snatching.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertEqual(snatching.players[0].state, .snatching)
        run(&snatching, frames: 6, input: { _ in .idle })
        XCTAssertGreaterThan(snatching.players[0].velocity.x, 2)
    }

    func testShootInNeutralIsASlashToo() {
        var match = neutral()
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .slashing)
    }

    func testAirSlashFloatsThroughTheSwingThenRolls() {
        var match = defending()
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 60, input: { _ in .idle }) { $0.players[0].velocity.y <= 0 }
        let apex = match.players[0].position.y
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .slashing)
        run(&match, frames: SlashRules.frames - 1, input: { _ in .idle })
        XCTAssertEqual(match.players[0].state, .slashing)
        XCTAssertGreaterThan(match.players[0].position.y, apex, "with gravity cut it should still be up there")
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .rolling)
        let rolled = run(&match, frames: 60, input: { _ in .idle }) { $0.players[0].state == .land }
        XCTAssertLessThan(rolled, 60)
        XCTAssertGreaterThan(rolled, 5, "the roll is a commitment")
    }

    func testSlashKnocksTheBallOutOfTheHoldersHands() {
        var match = defending(otherAt: 140)
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        let hit = run(&match, frames: SlashRules.frames, input: { _ in .idle }) { $0.events.contains(.popped(player: 1, by: 0)) }
        XCTAssertTrue(SlashRules.liveFrames.contains(hit + 1))
        XCTAssertFalse(match.players[1].hasBall)
        XCTAssertEqual(match.ball.velocity, Vec2(x: 0, y: BallRules.floaterSpeed))
    }

    func testSlashPopsTheBallOffAHolderTheBladeOnlyTouchesTheBodyOf() {
        // The other stands at the tip of the forward swing: its box reaches the near edge
        // of their body and not the ball at their centre.
        var match = defending(otherAt: 152)
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        let hit = run(&match, frames: SlashRules.frames, input: { _ in .idle }) { $0.events.contains(.popped(player: 1, by: 0)) }
        XCTAssertTrue(SlashRules.liveFrames.contains(hit + 1))
        XCTAssertFalse(match.players[1].hasBall)
    }

    func testSlashSwatsALooseBallAway() {
        var match = defending()
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        match.advance(inputs: [.idle, .idle])
        // The other lets go; a ball dropping in front meets the forward swing.
        match.players[1].hasBall = false
        match.ball.respawn(at: match.players[0].chest + Vec2(x: 12, y: 21))
        match.ball.velocity = Vec2(x: 0, y: -2)
        let swatted = run(&match, frames: SlashRules.frames, input: { _ in .idle }) { $0.events.contains(.swatted(player: 0, hit: true)) }
        XCTAssertLessThan(swatted, SlashRules.frames)
        // Spiked down and away, at about 45 degrees.
        XCTAssertGreaterThan(match.ball.velocity.x, 0)
        XCTAssertLessThan(match.ball.velocity.y, 0)
        let angle = atan2(match.ball.velocity.y, match.ball.velocity.x)
        XCTAssertEqual(angle, SlashRules.spikeAngle, accuracy: SlashRules.spikeJitter + 0.05)
        XCTAssertGreaterThanOrEqual(match.ball.velocity.length, SlashRules.swatSpeed - 0.2)
    }

    // MARK: Snatch

    func testThrowWithoutTheBallIsASnatchThatTakesAFastBall() {
        var match = neutral()
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertEqual(match.players[0].state, .snatching)
        // Too fast to catch by hand, straight at the chest, arriving while the hand is out.
        let arrival = SnatchRules.activeFrames.lowerBound + 2
        match.ball.respawn(at: match.players[0].chest + Vec2(x: BallRules.throwSpeed * Double(arrival), y: 0))
        match.ball.velocity = Vec2(x: -BallRules.throwSpeed, y: 0)
        let taken = run(&match, frames: SnatchRules.activeFrames.upperBound, input: { _ in .idle }) { $0.ball.holder == 0 }
        XCTAssertLessThan(taken, SnatchRules.activeFrames.upperBound)
        XCTAssertEqual(match.players[0].state, .catching)
        XCTAssertEqual(match.players[0].snatchCooldown, SnatchRules.cooldownFrames)
    }

    func testSnatchIgnoresABallBehind() {
        var match = neutral()
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        run(&match, frames: 4, input: { _ in .idle })
        match.ball.respawn(at: match.players[0].chest + Vec2(x: -7, y: 0))
        run(&match, frames: 4, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
    }

    func testSnatchTakesABallOnTheHandsRingBeyondItsBox() {
        var match = neutral()
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        run(&match, frames: SnatchRules.activeFrames.lowerBound, input: { _ in .idle })
        let player = match.players[0]
        let beyondBox = player.spec.bodyWidth / 2 + SnatchRules.reach + BallRules.radius + 1
        let spot = player.position + Vec2(x: beyondBox, y: BallRules.handCatchCentre.y)
        XCTAssertFalse(Box(center: spot, width: BallRules.radius * 2, height: BallRules.radius * 2).overlaps(player.snatchHitbox!))
        match.ball.respawn(at: spot)
        run(&match, frames: 4, input: { _ in .idle }) { $0.ball.holder == 0 }
        XCTAssertEqual(match.ball.holder, 0)
    }

    func testSnatchTakesTheBallFromTheHoldersHands() {
        var match = defending(otherAt: 140)
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        let taken = run(&match, frames: SnatchRules.activeFrames.upperBound, input: { _ in .idle }) { $0.ball.holder == 0 }
        XCTAssertLessThan(taken, SnatchRules.activeFrames.upperBound)
        XCTAssertFalse(match.players[1].hasBall)
        XCTAssertTrue(match.players[0].hasBall)
    }

    func testSnatchRepeatsAsSoonAsItIsOver() {
        var match = neutral()
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        run(&match, frames: SnatchRules.frames, input: { _ in .idle }) { $0.players[0].state == .idle }
        XCTAssertEqual(match.players[0].state, .idle)
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertEqual(match.players[0].state, .snatching)
    }

    func testSnatchSparkComesOnTheThirdSheetFrame() {
        var match = neutral()
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        let sparked = run(&match, frames: 12, input: { _ in .idle }) { $0.events.contains(.snatchReached(player: 0)) }
        XCTAssertEqual(sparked + 1, SnatchRules.sparkFrame)
        XCTAssertEqual(match.players[0].animationFrame, AnimationFrame(.snatch, 2))
    }

    func testWebWaterKeepsTheLineOnThrow() {
        var match = neutral()
        match.players[0].power = .webWater
        match.players[0].powerLevel = 2
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertNotEqual(match.players[0].state, .snatching)
        XCTAssertTrue(match.players[0].webAiming)
    }

    // MARK: Ledge

    func testFallingPastABlockCornerGrabsTheLedgeAndClimbsUp() {
        var match = neutral()
        // Dropped just left of the right backboard block, whose top-left corner is (290, 90).
        match.players[0].position = Vec2(x: 282, y: 130)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        let grabbed = run(&match, frames: 90, input: { _ in .idle }) { $0.players[0].state == .ledgeHang }
        XCTAssertLessThan(grabbed, 90, "never grabbed the ledge")
        XCTAssertTrue(match.events.contains(.ledgeGrabbed(player: 0)))
        XCTAssertEqual(match.players[0].facing, .right)
        XCTAssertEqual(match.players[0].position, Vec2(x: 285, y: 90 - LedgeRules.hangDepth))
        let climb = LedgeRules.hangFrames + LedgeRules.climbFrames + 2
        let stood = run(&match, frames: climb, input: { _ in .idle }) { $0.players[0].state == .idle }
        XCTAssertLessThan(stood, climb)
        XCTAssertEqual(match.players[0].position.y, 90, accuracy: 0.001)
        XCTAssertGreaterThan(match.players[0].position.x, 290)
        XCTAssertTrue(match.players[0].grounded)
    }

    func testNoLedgeGrabWithTheBall() {
        var match = Match()
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.players[0].position = Vec2(x: 282, y: 130)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        run(&match, frames: 90, input: { _ in .idle }) { $0.players[0].grounded }
        XCTAssertEqual(match.players[0].position.y, 10, accuracy: 0.001)
    }

    func testWalkingOffALedgeDoesNotGrabItBack() {
        var match = neutral()
        // Standing on the right block, walking off its left edge.
        match.players[0].position = Vec2(x: 300, y: 90)
        match.players[0].grounded = true
        run(&match, frames: 90, input: { _ in PlayerInput(stick: Vec2(x: -0.5, y: 0)) }) { $0.players[0].grounded && $0.players[0].position.y < 89 }
        XCTAssertEqual(match.players[0].position.y, 10, accuracy: 0.001)
    }

    func testTheDunkRunsItsSheetFromTheStanceAndHoldsTheHang() {
        var player = Match().players[0]
        player.enter(.dunking)
        player.stateTimer = 1
        XCTAssertEqual(player.animationFrame, AnimationFrame(.throwForward, 3))
        player.stateTimer = BallRules.dunkFrames / 2
        XCTAssertEqual(player.animationFrame, AnimationFrame(.dunk, 2), "the slam on the release frame")
        player.stateTimer = BallRules.dunkFrames + BallRules.dunkHangFrames - 1
        XCTAssertEqual(player.animationFrame, AnimationFrame(.dunk, 5))
        XCTAssertEqual(Animation.dunkStart(of: 3), BallRules.dunkFrames / 2)
    }
}

final class OpponentTests: XCTestCase {
    @discardableResult
    private func run(_ match: inout Match, frames: Int, input: (Int) -> PlayerInput, until stop: ((Match) -> Bool)? = nil) -> Int {
        for frame in 0..<frames {
            match.advance(inputs: [input(frame), .idle])
            if let stop, stop(match) { return frame }
        }
        return frames
    }

    /// Runs the match with the human on `input` and the opponent deciding for itself.
    @discardableResult
    private func play(_ match: inout Match, _ opponent: inout Opponent, frames: Int, input: (Int) -> PlayerInput, until stop: ((Match) -> Bool)? = nil) -> Int {
        for frame in 0..<frames {
            let theirs = opponent.decide(match)
            match.advance(inputs: [input(frame), theirs])
            if let stop, stop(match) { return frame }
        }
        return frames
    }

    func testTheOpponentIsDeterministic() {
        var a = Match(), b = Match()
        var brainA = Opponent(index: 1), brainB = Opponent(index: 1)
        a.players[1].hasBall = true
        a.ball.holder = 1
        b.players[1].hasBall = true
        b.ball.holder = 1
        for frame in 0..<600 {
            let input = PlayerInput(stick: Vec2(x: frame % 80 < 40 ? 1 : -1, y: 0), jump: frame % 90 < 6)
            a.advance(inputs: [input, brainA.decide(a)])
            b.advance(inputs: [input, brainB.decide(b)])
        }
        XCTAssertEqual(a, b)
        XCTAssertEqual(brainA, brainB)
    }

    func testLeftAloneWithTheBallItShoots() {
        var match = Match()
        var brain = Opponent(index: 1)
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[0].position.x = 300
        let shot = play(&match, &brain, frames: 900, input: { _ in .idle }) { $0.events.contains(.shot(player: 1)) }
        XCTAssertLessThan(shot, 900, "never took the shot")
        XCTAssertLessThan(match.ball.position.x, 130, "the shot should be going at its own rim on the left")
    }

    func testItKeepsOutOfALiveSwingAndDartsPastASpentOne() {
        var match = Match()
        var brain = Opponent(index: 1)
        match.players[1].hasBall = true
        match.ball.holder = 1
        // The human stands in the way, between it and its rim, and swings.
        match.players[0].position.x = 180
        match.players[1].position.x = 205
        match.players[0].enter(.slashing)
        // While the blade is live it never pushes toward them.
        for _ in 0..<SlashRules.liveFrames.upperBound - 1 {
            let theirs = brain.decide(match)
            XCTAssertGreaterThanOrEqual(theirs.stick.x, 0, "pushed into a live blade")
            match.advance(inputs: [.idle, theirs])
        }
        XCTAssertTrue(match.players[1].hasBall)
        // Spent: past them inside a second.
        let past = play(&match, &brain, frames: 60, input: { _ in .idle }) { $0.players[1].position.x < 170 }
        XCTAssertLessThan(past, 60, "never darted past the spent swing")
    }

    func testOnDefenceItGuardsTheRimAndSwingsInReach() {
        var match = Match()
        var brain = Opponent(index: 1)
        match.players[0].hasBall = true
        match.ball.holder = 0
        // It heads first for the spot in front of the rim the human scores on, the right one.
        play(&match, &brain, frames: 60, input: { _ in .idle })
        XCTAssertGreaterThan(match.players[1].position.x, 240)
        // The human walks up to it: a swing or a snatch comes.
        let swung = play(&match, &brain, frames: 400, input: { _ in PlayerInput(stick: Vec2(x: 0.6, y: 0)) }) {
            $0.events.contains(.slashed(player: 1)) || $0.players[1].state == .snatching
        }
        XCTAssertLessThan(swung, 400, "never went for the ball in reach")
    }

    func testStandingStillWithTheBallDrawsItIn() {
        var match = Match()
        var brain = Opponent(index: 1)
        match.players[0].hasBall = true
        match.ball.holder = 0
        let came = play(&match, &brain, frames: 600, input: { _ in .idle }) {
            $0.events.contains(.slashed(player: 1)) || $0.players[1].state == .snatching
        }
        XCTAssertLessThan(came, 600, "it should come and take a swing at a body standing about")
    }

    func testABallOnTheLedgeIsReachedWithAFullHop() {
        var match = Match()
        var brain = Opponent(index: 1)
        match.players[0].position.x = 20
        // The ball as it lies at the start: dropped from the spawn onto the ledge.
        run(&match, frames: 150, input: { _ in .idle })
        XCTAssertTrue(match.ball.resting)
        XCTAssertGreaterThan(match.ball.position.y, 35)
        let got = play(&match, &brain, frames: 400, input: { _ in .idle }) { $0.ball.holder == 1 }
        XCTAssertLessThan(got, 400, "never got up to the ball")
    }

    func testAHitBodyCannotPressAnythingForAMoment() {
        var match = Match()
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[1].position.x = 142
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        run(&match, frames: SlashRules.frames, input: { _ in .idle }) { $0.events.contains(.popped(player: 1, by: 0)) }
        XCTAssertEqual(match.players[1].hitStun, BallRules.hitStunFrames)
        // A jump press does nothing while stunned, and the stick still moves it.
        match.advance(inputs: [.idle, PlayerInput(stick: Vec2(x: 1, y: 0), jump: true)])
        XCTAssertNotEqual(match.players[1].state, .jumpSquat)
        XCTAssertNotEqual(match.players[1].state, .idle)
        run(&match, frames: BallRules.hitStunFrames, input: { _ in .idle })
        XCTAssertEqual(match.players[1].hitStun, 0)
    }

    func testTheBallKnockedLooseGoesToTheSlasherNotBackToTheStunnedHolder() {
        var match = Match()
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[1].position.x = 142
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        run(&match, frames: SlashRules.frames, input: { _ in .idle }) { $0.events.contains(.popped(player: 1, by: 0)) }
        // It pops up and comes down through the holder's own rings, and they can't take it.
        var holderTookIt = false
        let taken = run(&match, frames: 60, input: { _ in .idle }) { match in
            if match.ball.holder == 1 { holderTookIt = true }
            return match.ball.holder != nil
        }
        XCTAssertFalse(holderTookIt)
        XCTAssertLessThan(taken, 60)
        XCTAssertEqual(match.ball.holder, 0)
    }

    func testASnatchedBodyIsStunnedToo() {
        var match = Match()
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[1].position.x = 140
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        run(&match, frames: SnatchRules.activeFrames.upperBound, input: { _ in .idle }) { $0.ball.holder == 0 }
        XCTAssertEqual(match.ball.holder, 0)
        XCTAssertEqual(match.players[1].hitStun, BallRules.hitStunFrames)
    }

    func testItLeavesItsOwnShotAloneUntilItLandsOrScores() {
        var match = Match()
        var brain = Opponent(index: 1)
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[0].position.x = 300
        let shot = play(&match, &brain, frames: 900, input: { _ in .idle }) { $0.events.contains(.shot(player: 1)) }
        XCTAssertLessThan(shot, 900)
        var tookItBack = false
        play(&match, &brain, frames: 300, input: { _ in .idle }) { match in
            if match.ball.holder == 1, match.scores == [0, 0] { tookItBack = true }
            return tookItBack || !match.ball.shotInFlight
        }
        XCTAssertFalse(tookItBack, "it caught its own shot on the way to the rim")
    }

    func testWithTheBallLooseItGoesForIt() {
        var match = Match()
        var brain = Opponent(index: 1)
        match.players[0].position.x = 20
        match.ball.respawn(at: Vec2(x: 280, y: 30))
        let got = play(&match, &brain, frames: 300, input: { _ in .idle }) { $0.ball.holder == 1 }
        XCTAssertLessThan(got, 300, "never picked the ball up")
    }
}

final class GreateraidTests: XCTestCase {
    func testOneHorchataIsTheBaselineAndJuiceRaisesThenAddsAJump() {
        var drinks = Drinks.none
        drinks.drink(.hastyHorchata)
        let spec = drinks.spec()
        XCTAssertEqual(spec.runSpeed, FighterSpec.baseline.runSpeed, accuracy: 0.001)
        XCTAssertEqual(spec.dashInitialVelocity, FighterSpec.baseline.dashInitialVelocity, accuracy: 0.001)
        XCTAssertEqual(spec.airSpeedMax, FighterSpec.baseline.airSpeedMax, accuracy: 0.001)
        XCTAssertEqual(FighterSpec.starting.jumps, FighterSpec.baseline.jumps)
        XCTAssertEqual(FighterSpec.starting.runSpeed, FighterSpec.baseline.runSpeed - 0.5, accuracy: 0.001)
        drinks.drink(.jumperJuice)
        XCTAssertEqual(drinks.spec().fullHopVelocity, FighterSpec.starting.fullHopVelocity * 1.1, accuracy: 0.001)
        XCTAssertEqual(drinks.spec().jumps, 2)
        drinks.drink(.jumperJuice)
        let third = drinks.spec()
        XCTAssertEqual(third.jumps, 3)
        // Half the height: the square of the speed ratio.
        XCTAssertEqual(third.thirdJumpVelocity * third.thirdJumpVelocity, third.fullHopVelocity * third.fullHopVelocity / 2, accuracy: 0.001)
    }

    func testTheThirdJumpComesLast() {
        var drinks = Drinks.none
        drinks.drink(.jumperJuice)
        drinks.drink(.jumperJuice)
        var match = Match(specs: [drinks.spec(), .starting])
        var jumps = 0
        var thirdVelocity = 0.0
        for frame in 0..<60 {
            let press = frame % 20 == 0
            match.advance(inputs: [PlayerInput(jump: press), .idle])
            if match.events.contains(.doubleJumped(player: 0)) {
                jumps += 1
                if jumps == 2 { thirdVelocity = match.players[0].velocity.y }
            }
        }
        XCTAssertEqual(jumps, 2, "two jumps in the air after the first")
        XCTAssertEqual(thirdVelocity, drinks.spec().thirdJumpVelocity, accuracy: 0.001)
        XCTAssertEqual(match.players[0].jumpsLeft, 0)
    }

    func testCannonColaRunsTheSameArcFaster() {
        func flight(pace: Double) -> (landing: Vec2, frames: Int) {
            var match = Match()
            match.players[0].spec.shotPace = pace
            match.players[0].hasBall = true
            match.ball.holder = 0
            for _ in 0..<BallRules.shotWindupFrames + 2 {
                match.advance(inputs: [PlayerInput(shoot: true), .idle])
            }
            match.advance(inputs: [PlayerInput(aim: Vec2(x: 0.5, y: 0.8), shoot: true), .idle])
            var frames = 0
            var landing = Vec2.zero
            while frames < 300 {
                match.advance(inputs: [.idle, .idle])
                frames += 1
                if let bounce = match.events.compactMap({ event -> Vec2? in
                    if case .ballBounced(let position) = event { return position } else { return nil }
                }).first {
                    landing = bounce
                    break
                }
            }
            return (landing, frames)
        }
        let plain = flight(pace: 1)
        let cola = flight(pace: 1.5)
        XCTAssertEqual(cola.landing.x, plain.landing.x, accuracy: 3, "the same arc, so the same landing")
        XCTAssertEqual(cola.landing.y, plain.landing.y, accuracy: 3)
        XCTAssertLessThan(cola.frames, plain.frames * 3 / 4, "run through faster")
    }

    func testTearsPopAHolderWhoseBodyIsInReach() {
        var match = Match()
        for index in match.players.indices {
            match.players[index].power = .flashFizz
            match.players[index].powerLevel = 2
        }
        match.players[1].hasBall = true
        match.ball.holder = 1
        // The body's near edge just inside the tear's reach of the exit, the ball's centre outside it.
        let exit = 130 + FizzRules.flashDistance(level: 2)
        match.players[1].position.x = exit + FizzRules.tearRadius + match.players[1].spec.bodyWidth / 2 - 1
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), shoot: true), .idle])
        XCTAssertTrue(match.events.contains(.popped(player: 1, by: 0)))
    }

    func testBoostersStackToTwoAndThenStopBeingOffered() {
        var drinks = Drinks.none
        drinks.drink(.cannonCola)
        drinks.drink(.cannonCola)
        drinks.drink(.cannonCola)
        XCTAssertEqual(drinks.level(of: .cannonCola), 2)
        XCTAssertEqual(drinks.spec().shotPace, 1.5, accuracy: 0.001)
        XCTAssertEqual(drinks.spec().shotSpeed, FighterSpec.starting.shotSpeed, accuracy: 0.001)
        var dice = Dice(seed: 3)
        for _ in 0..<50 {
            let offer = drinks.offers(&dice)
            XCTAssertEqual(offer.count, 3)
            XCTAssertFalse(offer.contains(.cannonCola))
            XCTAssertEqual(Set(offer).count, 3, "an offer never repeats a bottle")
        }
    }

    func testBiomorphsAreRarerAndOneAtATimeThenBioBoba() {
        var drinks = Drinks.none
        var dice = Dice(seed: 9)
        var biomorphs = 0, boosters = 0
        for _ in 0..<300 {
            for drink in drinks.offers(&dice) {
                if drink.kind == .biomorph { biomorphs += 1 } else { boosters += 1 }
            }
        }
        XCTAssertGreaterThan(boosters, biomorphs * 2)
        XCTAssertGreaterThan(biomorphs, 0)
        drinks.drink(.superSmoothie)
        XCTAssertEqual(drinks.power, .superSmoothie)
        XCTAssertEqual(drinks.powerLevel, 1)
        for _ in 0..<50 {
            let offer = drinks.offers(&dice)
            XCTAssertFalse(offer.contains { $0.kind == .biomorph && $0 != .superSmoothie }, "with a biomorph in hand no other is offered")
        }
        var sawSecondSip = false
        for _ in 0..<50 where drinks.offers(&dice).contains(.superSmoothie) { sawSecondSip = true }
        XCTAssertTrue(sawSecondSip, "the biomorph in hand comes round as its second sip")
        XCTAssertTrue(drinks.isSecondSip(.superSmoothie))
        drinks.drink(.superSmoothie)
        XCTAssertEqual(drinks.powerLevel, 2)
        for _ in 0..<50 {
            XCTAssertFalse(drinks.offers(&dice).contains { $0.kind == .biomorph }, "at level two no biomorph is offered")
        }
    }

    func testASeriesIsFirstToFourAndGrowsItsCircles() {
        var series = Series()
        XCTAssertEqual(series.circles, 5)
        for winner in [0, 1, 0, 1, 0] { series.record(pointFor: winner) }
        XCTAssertNil(series.winner)
        XCTAssertEqual(series.circles, 6)
        series.record(pointFor: 1)
        XCTAssertEqual(series.circles, 7)
        series.record(pointFor: 0)
        XCTAssertEqual(series.winner, 0)
        let fresh = series.fresh()
        XCTAssertEqual(fresh.wins, [0, 0])
        XCTAssertEqual(fresh.drinks, [.none, .none])
    }
}
