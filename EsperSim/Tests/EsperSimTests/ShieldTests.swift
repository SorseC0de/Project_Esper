import XCTest
@testable import EsperSim

/// Shielding: the snatch with the stick held a way raises a shield at the hand.
final class ShieldTests: XCTestCase {
    private func court() -> Match {
        var match = Match(stage: .court, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].position = Vec2(x: 120, y: 10)
        match.players[0].facing = .right
        match.players[1].position = Vec2(x: 300, y: 10)
        match.ball.holder = nil
        match.players.indices.forEach { match.players[$0].hasBall = false }
        match.ball.respawn(at: Vec2(x: 200, y: 150))
        match.ball.position = Vec2(x: 30, y: 200)
        match.ball.velocity = .zero
        for _ in 0..<5 { match.advance(inputs: [.idle, .idle]) }
        return match
    }

    /// Snatch pressed with the stick held, then the stick let go, till the shield's up.
    private func raise(_ match: inout Match, stick: Vec2, player: Int = 0) {
        var inputs: [PlayerInput] = [.idle, .idle]
        inputs[player] = PlayerInput(stick: stick, shield: true)
        func raised() -> Bool { match.events.contains { if case .shieldRaised = $0 { return true } else { return false } } }
        match.advance(inputs: inputs)
        for _ in 0..<SnatchRules.sparkFrame where !raised() { match.advance(inputs: [.idle, .idle]) }
    }

    func testTheButtonRaisesOneStillOrForwardAndTheSnatchStaysASnatch() {
        for stick in [Vec2.zero, Vec2(x: 1, y: 0)] {
            var match = court()
            raise(&match, stick: stick)
            XCTAssertEqual(match.shields.count, 1)
            XCTAssertEqual(match.shields.first?.normal.x ?? 0, 1, accuracy: 0.001)
        }
        var snatch = court()
        snatch.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), throwBall: true), .idle])
        for _ in 0..<SnatchRules.frames { snatch.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(snatch.shields.isEmpty)
    }
    func testBackTurnsRoundFirstAndUpTilts() {
        var match = court()
        raise(&match, stick: Vec2(x: -1, y: 0))
        XCTAssertEqual(match.players[0].facing, .left)
        XCTAssertLessThan(match.shields.first?.normal.x ?? 0, 0)
        var up = court()
        raise(&up, stick: Vec2(x: 0, y: 1))
        XCTAssertEqual(up.shields.first?.normal.y ?? 0, Trig.sin(degrees(45)), accuracy: 0.001)
    }
    func testOnesOwnShieldsDontBreakEachOther() {
        var match = court()
        raise(&match, stick: Vec2(x: 1, y: 0))
        for _ in 0..<SnatchRules.frames { match.advance(inputs: [.idle, .idle]) }
        match.players[0].facing = .right
        raise(&match, stick: Vec2(x: 1, y: 0))
        XCTAssertEqual(match.shields.count, 2)
    }

    func testEachShieldTurnsTheBallOnce() {
        var match = court()
        raise(&match, stick: Vec2(x: 1, y: 0))
        for _ in 0..<ShieldRules.perfectFrames { match.advance(inputs: [.idle, .idle]) }
        match.shields[0].turnedFlight = match.ball.flight
        ballAt(&match, shield: match.shields[0], from: 1, speed: 4)
        for _ in 0..<6 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertLessThan(match.ball.velocity.x, 0, "passed on through")
    }

    func testTheLoopKeepsItUpAFrameEachTime() {
        let loops = ShieldRules.extraLoops
        defer { ShieldRules.extraLoops = loops }
        ShieldRules.extraLoops = 2
        XCTAssertEqual(ShieldRules.lifeFrames, (18 + 8) * 4)
        XCTAssertEqual(ShieldRules.sheetFrame(atAge: 14 * 4), 10, "round to the loop's start")
        XCTAssertEqual(ShieldRules.sheetFrame(atAge: (14 + 8) * 4), 14, "then on out")
    }

    func testAnUpShieldSendsAFallingBallOutNotStraightUp() {
        var match = court()
        raise(&match, stick: Vec2(x: 0, y: 1))
        let shield = match.shields[0]
        match.ball.position = shield.centre + Vec2(x: 0, y: 12)
        match.ball.velocity = Vec2(x: 0, y: -4)
        match.ball.thrown = false
        for _ in 0..<6 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertGreaterThan(match.ball.velocity.x, 0)
    }

    func testItHangsWhereItWasRaisedAndGoesAfterItsArt() {
        var match = court()
        raise(&match, stick: Vec2(x: 1, y: 0))
        let at = match.shields[0].centre
        for _ in 0..<20 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle]) }
        XCTAssertEqual(match.shields.first?.centre, at)
        for _ in 0..<ShieldRules.lifeFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.shields.isEmpty)
    }

    private func ballAt(_ match: inout Match, shield: Shield, from side: Double, speed: Double) {
        match.ball.position = shield.centre + Vec2(x: side * 12, y: 0)
        match.ball.velocity = Vec2(x: -side * speed, y: 0)
        match.ball.thrown = false
    }

    func testALateBallReflectsAndAPerfectOneIsPoppedUp() {
        var match = court()
        raise(&match, stick: Vec2(x: 1, y: 0))
        for _ in 0..<ShieldRules.perfectFrames { match.advance(inputs: [.idle, .idle]) }
        ballAt(&match, shield: match.shields[0], from: 1, speed: 4)
        for _ in 0..<6 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertGreaterThan(match.ball.velocity.x, 0, "back the way it came")

        var perfect = court()
        raise(&perfect, stick: Vec2(x: 1, y: 0))
        ballAt(&perfect, shield: perfect.shields[0], from: 1, speed: 4)
        var popped = false
        for _ in 0..<4 {
            perfect.advance(inputs: [.idle, .idle])
            if perfect.events.contains(where: { if case .shieldPerfect = $0 { return true } else { return false } }) { popped = true }
        }
        XCTAssertTrue(popped)
        XCTAssertEqual(perfect.ball.velocity.x, 0)
    }

    func testAThrownBallBreaksIt() {
        var match = court()
        raise(&match, stick: Vec2(x: 1, y: 0))
        for _ in 0..<ShieldRules.perfectFrames { match.advance(inputs: [.idle, .idle]) }
        ballAt(&match, shield: match.shields[0], from: 1, speed: 4)
        match.ball.thrown = true
        for _ in 0..<6 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.shields.isEmpty)
    }

    func testTwoInOnePlaceBreakEachOther() {
        var match = court()
        match.players[1].position = Vec2(x: 150, y: 10)
        match.players[1].facing = .left
        raise(&match, stick: Vec2(x: 1, y: 0))
        // The other's where this one goes, this one taken down to raise it again.
        let first = match.shields.removeFirst()
        match.shields.append(Shield(owner: 1, centre: first.centre, normal: Vec2(x: -1, y: 0), tilt: 0))
        for _ in 0..<SnatchRules.frames { match.advance(inputs: [.idle, .idle]) }
        match.players[0].position = Vec2(x: 120, y: 10)
        match.players[0].facing = .right
        raise(&match, stick: Vec2(x: 1, y: 0))
        XCTAssertTrue(match.shields.isEmpty, "both broken")
    }

    func testASnatchOnItBreaksItForTenFlo() {
        var match = court()
        match.players[1].position = Vec2(x: 145, y: 10)
        match.players[1].facing = .left
        raise(&match, stick: Vec2(x: 1, y: 0))
        let flo = match.players[1].flo
        var broke = false
        for frame in 0..<SnatchRules.frames {
            match.advance(inputs: [.idle, PlayerInput(throwBall: frame == 0)])
            if match.events.contains(where: { if case .shieldBroken(player: 0, _) = $0 { return true } else { return false } }) { broke = true }
        }
        XCTAssertTrue(broke)
        XCTAssertEqual(match.players[1].flo, flo + ShieldRules.breakFlo)
    }

    func testUpAndDownShieldsHopTheFloatersHalfHopWithAJumpToSpare() {
        for stick in [Vec2(x: 0, y: 1), Vec2(x: 0, y: -1)] {
            var match = court()
            let jumps = match.players[0].jumpsLeft
            raise(&match, stick: stick)
            XCTAssertEqual(match.shields.count, 1)
            XCTAssertGreaterThan(match.players[0].velocity.y, 0, "hopped")
            XCTAssertEqual(match.players[0].jumpsLeft, jumps)
        }
    }

    func testAFloaterBouncesOffRatherThanBreakingIt() {
        var match = court()
        raise(&match, stick: Vec2(x: 1, y: 0))
        for _ in 0..<ShieldRules.perfectFrames { match.advance(inputs: [.idle, .idle]) }
        ballAt(&match, shield: match.shields[0], from: 1, speed: 4)
        match.ball.thrown = true
        match.ball.floaterShot = true
        for _ in 0..<6 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.shields.count, 1)
        XCTAssertGreaterThan(match.ball.velocity.x, 0)
    }

    func testTheOthersShieldIsSolidToTheirBody() {
        var match = court()
        raise(&match, stick: Vec2(x: 1, y: 0))
        let wall = match.shields[0].bounds
        match.players[1].position = Vec2(x: wall.max.x + 20, y: 10)
        for _ in 0..<60 { match.advance(inputs: [.idle, PlayerInput(stick: Vec2(x: -1, y: 0))]) }
        XCTAssertGreaterThanOrEqual(match.players[1].body.min.x, wall.max.x - 0.01)
    }

    func testABladeOnItParriesTheSwinger() {
        var match = court()
        match.players[1].position = Vec2(x: 150, y: 10)
        match.players[1].facing = .left
        raise(&match, stick: Vec2(x: 1, y: 0))
        let parried = (0..<30).contains { _ in
            match.advance(inputs: [.idle, PlayerInput(shoot: !match.players[1].lastInput.shoot)])
            return match.events.contains { if case .parried(player: 1, by: 0) = $0 { return true } else { return false } }
        }
        XCTAssertTrue(parried)
    }
}
