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
        XCTAssertEqual(match.ball.velocity.length, BallRules.shotSpeed, accuracy: 0.1)
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
            match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1), throwBall: true), .idle])
        }
        run(&match, frames: BallRules.throwReleaseFrames + 1, input: { _ in .idle })
        XCTAssertNil(match.ball.holder)
        XCTAssertTrue(match.ball.straight)
        XCTAssertTrue(match.ball.thrown)
        XCTAssertEqual(match.ball.velocity, Vec2(x: 0, y: BallRules.throwSpeed))
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

    func testBallBehindIsNotCaught() {
        var match = Match()
        match.ball.position = match.players[0].chest + Vec2(x: -6, y: 0)
        match.ball.velocity = .zero
        match.advance(inputs: [.idle, .idle])
        XCTAssertNil(match.ball.holder)
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

    func testThrownBallIgnoresTheRimsPull() {
        var match = Match()
        let rim = match.stage.hoops[1].position
        // Just outside the absorb radius, inside the pull, moving up: a shot gets bent in, a throw doesn't.
        for thrown in [false, true] {
            match.ball.respawn(at: rim + Vec2(x: -15, y: 5))
            match.ball.velocity = Vec2(x: 0, y: 1)
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
    private func run(_ match: inout Match, frames: Int, input: (Int) -> PlayerInput) -> Int {
        for frame in 0..<frames {
            match.advance(inputs: [input(frame), .idle])
        }
        return frames
    }
}
