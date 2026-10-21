import XCTest
@testable import EsperSim

/// The Spin Move, the down throw: the ball kept, a half hop, phasing, once an airtime.
final class SpinTests: XCTestCase {
    private func held(flo: Int) -> Match {
        var match = Match(stage: .court, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].position = Vec2(x: 120, y: 10)
        match.players[0].facing = .right
        match.players[1].position = Vec2(x: 300, y: 10)
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.players[0].flo = flo
        return match
    }

    /// The throw held, then flicked down (the aim, not the stick, so it isn't the stepback).
    private func spin(_ match: inout Match) {
        for _ in 0..<BallRules.throwWindupFrames + 1 { match.advance(inputs: [PlayerInput(throwBall: true), .idle]) }
        match.advance(inputs: [PlayerInput(aim: Vec2(x: 0, y: -1), throwBall: true), .idle])
        for _ in 0..<3 where match.players[0].state != .spinning { match.advance(inputs: [.idle, .idle]) }
    }

    func testItKeepsTheBallHopsAndPhasesForNoFlo() {
        for flo in [0, 50] {
            var match = held(flo: flo)
            spin(&match)
            XCTAssertEqual(match.players[0].state, .spinning)
            XCTAssertEqual(match.ball.holder, 0)
            XCTAssertTrue(match.players[0].spinPhasing)
            XCTAssertEqual(match.players[0].flo, flo, "costs nothing")
            XCTAssertGreaterThan(match.players[0].velocity.y, 0)
        }
    }

    func testOnceAnAirtimeTillTheBallsHadAgain() {
        var match = held(flo: 0)
        spin(&match)
        XCTAssertTrue(match.players[0].spinUsed)
        match.players[0].catchBall()
        XCTAssertFalse(match.players[0].spinUsed, "a catch brings it back")
    }

    func testPhasingASnatchTakesNothing() {
        var match = held(flo: 50)
        spin(&match)
        match.players[1].position = Vec2(x: match.players[0].position.x + 8, y: match.players[0].position.y)
        match.players[1].facing = .left
        for frame in 0..<SnatchRules.frames { match.advance(inputs: [.idle, PlayerInput(throwBall: frame == 0)]) }
        XCTAssertEqual(match.ball.holder, 0)
    }

    func testNothingTouchesTheSpinnerTheWholeSpin() {
        var match = held(flo: 0)
        spin(&match)
        var spun = 0
        while match.players[0].state == .spinning {
            XCTAssertTrue(match.players[0].spinPhasing, "phasing every frame it's drawn spinning")
            // Every way a hit lands: a strip (a thrown ball's, a power's, a slide's), a counter's stun.
            match.strip(0, by: 1, knock: Vec2(x: 3, y: 1))
            match.stunAsParried(0, by: 1)
            XCTAssertEqual(match.players[0].hitStun, 0)
            XCTAssertEqual(match.ball.holder, 0, "the ball kept")
            match.advance(inputs: [.idle, .idle])
            spun += 1
        }
        XCTAssertGreaterThanOrEqual(spun, SpinRules.frames - 3, "the whole spin, not cut short")
    }
}
