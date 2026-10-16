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
        inputs[player] = PlayerInput(stick: stick, throwBall: true)
        func raised() -> Bool { match.events.contains { if case .shieldRaised = $0 { return true } else { return false } } }
        match.advance(inputs: inputs)
        for _ in 0..<SnatchRules.sparkFrame where !raised() { match.advance(inputs: [.idle, .idle]) }
    }

    func testTheStickHeldRaisesAShieldAndANeutralPressSnatches() {
        var match = court()
        raise(&match, stick: Vec2(x: -1, y: 0))
        XCTAssertEqual(match.shields.count, 1)
        XCTAssertEqual(match.shields.first?.normal.x ?? 0, 1, accuracy: 0.001)
        var plain = court()
        raise(&plain, stick: .zero)
        XCTAssertTrue(plain.shields.isEmpty)
        var forward = court()
        raise(&forward, stick: Vec2(x: 1, y: 0))
        XCTAssertTrue(forward.shields.isEmpty, "forward is still the snatch")
        XCTAssertTrue(plain.shields.isEmpty)
    }

    func testBackRaisesItInFrontAndUpTilts() {
        var match = court()
        raise(&match, stick: Vec2(x: -1, y: 0))
        XCTAssertEqual(match.players[0].facing, .right, "no turn")
        XCTAssertGreaterThan(match.shields.first?.normal.x ?? 0, 0)
        var up = court()
        raise(&up, stick: Vec2(x: 0, y: 1))
        XCTAssertEqual(up.shields.first?.normal.y ?? 0, Trig.sin(degrees(45)), accuracy: 0.001)
    }

    func testItHangsWhereItWasRaisedAndGoesAfterItsArt() {
        var match = court()
        raise(&match, stick: Vec2(x: -1, y: 0))
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
        raise(&match, stick: Vec2(x: -1, y: 0))
        for _ in 0..<ShieldRules.perfectFrames { match.advance(inputs: [.idle, .idle]) }
        ballAt(&match, shield: match.shields[0], from: 1, speed: 4)
        for _ in 0..<6 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertGreaterThan(match.ball.velocity.x, 0, "back the way it came")

        var perfect = court()
        raise(&perfect, stick: Vec2(x: -1, y: 0))
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
        raise(&match, stick: Vec2(x: -1, y: 0))
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
        raise(&match, stick: Vec2(x: -1, y: 0))
        // The other's where this one goes, this one taken down to raise it again.
        let first = match.shields.removeFirst()
        match.shields.append(Shield(owner: 1, centre: first.centre, normal: Vec2(x: -1, y: 0), tilt: 0))
        for _ in 0..<SnatchRules.frames { match.advance(inputs: [.idle, .idle]) }
        match.players[0].position = Vec2(x: 120, y: 10)
        match.players[0].facing = .right
        raise(&match, stick: Vec2(x: -1, y: 0))
        XCTAssertTrue(match.shields.isEmpty, "both broken")
    }

    func testASnatchOnItBreaksItForTenFlo() {
        var match = court()
        match.players[1].position = Vec2(x: 145, y: 10)
        match.players[1].facing = .left
        raise(&match, stick: Vec2(x: -1, y: 0))
        let flo = match.players[1].flo
        var broke = false
        for frame in 0..<SnatchRules.frames {
            match.advance(inputs: [.idle, PlayerInput(throwBall: frame == 0)])
            if match.events.contains(where: { if case .shieldBroken(player: 0, _) = $0 { return true } else { return false } }) { broke = true }
        }
        XCTAssertTrue(broke)
        XCTAssertEqual(match.players[1].flo, flo + ShieldRules.breakFlo)
    }

    func testADownShieldOnTheGroundHopsWithAJumpToSpare() {
        var match = court()
        let jumps = match.players[0].jumpsLeft
        // Out along its way, down onto the floor.
        let offsets = ShieldRules.handOffsets
        ShieldRules.handOffsets[.down] = Vec2(x: 7, y: -7)
        defer { ShieldRules.handOffsets = offsets }
        raise(&match, stick: Vec2(x: 0, y: -1))
        XCTAssertEqual(match.shields.count, 1)
        XCTAssertGreaterThan(match.players[0].velocity.y, 0, "hopped")
        XCTAssertEqual(match.players[0].jumpsLeft, jumps)
        XCTAssertGreaterThan(match.players[0].doubleJumpTimer, 0)
    }

    func testABladeOnItParriesTheSwinger() {
        var match = court()
        match.players[1].position = Vec2(x: 150, y: 10)
        match.players[1].facing = .left
        raise(&match, stick: Vec2(x: -1, y: 0))
        let parried = (0..<30).contains { _ in
            match.advance(inputs: [.idle, PlayerInput(shoot: !match.players[1].lastInput.shoot)])
            return match.events.contains { if case .parried(player: 1, by: 0) = $0 { return true } else { return false } }
        }
        XCTAssertTrue(parried)
    }
}
