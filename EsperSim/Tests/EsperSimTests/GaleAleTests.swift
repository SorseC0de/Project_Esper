import XCTest
@testable import EsperSim

/// Gale Ale: the double jump leaves a still tornado; at level two the snatch sends one off that
/// strips, takes the ball, and bursts on a wall letting it go.
final class GaleAleTests: XCTestCase {
    private func court(level: Int) -> Match {
        var match = Match(stage: .court, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].power = .galeAle
        match.players[0].powerLevel = level
        match.players[0].position = Vec2(x: 120, y: 10)
        match.players[1].position = Vec2(x: 250, y: 10)
        return match
    }

    func testTheDoubleJumpLeavesAStillTornadoThatHoldsWhoeverFallsIn() {
        var match = court(level: 1)
        // At the top of a jump, the second one.
        match.players[0].position = Vec2(x: 120, y: 60)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.players[0].jumpsLeft = 1
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertEqual(match.gales.count, 1)
        guard !match.gales.isEmpty else { return }
        let gale = match.gales[0]
        XCTAssertFalse(gale.snatching)
        XCTAssertEqual(gale.box.width, 40)
        XCTAssertEqual(gale.box.height, 20)
        // The other dropped into it.
        match.players[1].position = Vec2(x: gale.box.center.x, y: gale.box.max.y + 4)
        match.players[1].grounded = false
        match.players[1].enter(.air)
        var held = false
        for _ in 0..<20 where !held {
            match.advance(inputs: [.idle, .idle])
            held = match.players[1].state == .suspended
        }
        XCTAssertTrue(held)
        // Gone in its time, letting go.
        for _ in 0..<GaleRules.stillFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.gales.isEmpty)
        XCTAssertNotEqual(match.players[1].state, .suspended)
    }

    func testAShotTakenByAStillTornadoCanBeCaughtFromIt() {
        var match = court(level: 1)
        match.players[0].position = Vec2(x: 120, y: 60)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.players[0].jumpsLeft = 1
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        guard let gale = match.gales.first else { return XCTFail("no gale") }
        // The other held in it, and a shot of the first's dropped in from above.
        match.players[1].position = Vec2(x: gale.box.center.x, y: gale.box.max.y + 4)
        match.players[1].grounded = false
        match.players[1].enter(.air)
        for _ in 0..<20 where match.players[1].state != .suspended { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[1].state, .suspended)
        match.ball.release(from: Vec2(x: gale.box.center.x, y: gale.box.max.y + 15), velocity: Vec2(x: 0, y: -2), by: 0, straight: false)
        match.ball.shotInFlight = true
        for _ in 0..<30 where match.ball.holder == nil { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.ball.holder, 1, "held, it's nobody's shot: caught")
    }

    func testLevelOnesSnatchSendsNothing() {
        var match = court(level: 1)
        for frame in 0..<30 { match.advance(inputs: [PlayerInput(throwBall: frame == 0), .idle]) }
        XCTAssertTrue(match.gales.isEmpty)
    }

    func testTheSnatchsTornadoStripsTakesTheBallAndBurstsOnTheWall() {
        var match = court(level: 2)
        match.players[0].facing = .right
        match.players[1].position = Vec2(x: 170, y: 10)
        match.players[1].hasBall = true
        match.ball.holder = 1
        var sent = false, carried = false, burst = false
        for frame in 0..<200 where !burst {
            match.advance(inputs: [PlayerInput(throwBall: frame == 0), .idle])
            if match.gales.contains(where: \.snatching) { sent = true }
            if match.gales.contains(where: \.carrying) { carried = true }
            burst = match.events.contains { if case .galeBurst = $0 { return true } else { return false } }
        }
        XCTAssertTrue(sent)
        XCTAssertTrue(carried, "the ball taken off them and carried")
        XCTAssertTrue(burst, "burst on the far wall")
        XCTAssertNil(match.ball.holder)
        XCTAssertNil(match.ball.tornadoCentre)
        // Let go by the wall, on the right.
        XCTAssertGreaterThan(match.ball.position.x, 250)
    }
}
