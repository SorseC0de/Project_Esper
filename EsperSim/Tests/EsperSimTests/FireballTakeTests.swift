import XCTest
@testable import EsperSim

/// Blazing Boba's fireballs taken out of the air: a drinker's snatch takes any, and a thrower
/// catches their own before it meets anything.
final class FireballTakeTests: XCTestCase {
    private func court() -> Match {
        var match = Match(stage: .court, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].position = Vec2(x: 120, y: 10)
        match.players[0].facing = .right
        match.players[1].position = Vec2(x: 200, y: 10)
        match.players[1].facing = .left
        match.ball.holder = nil
        match.players.indices.forEach { match.players[$0].hasBall = false }
        match.ball.respawn(at: Vec2(x: 30, y: 200))
        return match
    }

    func testABobaDrinkersSnatchTakesTheOthersFireball() {
        var match = court()
        match.players[1].power = .blazingBoba
        match.fireballs.append(Fireball(id: 99, owner: 0, position: match.players[1].handCatchPoint + Vec2(x: -8, y: 0),
                                        velocity: Vec2(x: 1, y: 0), framesLeft: 100, straight: true))
        var taken = false
        for frame in 0..<SnatchRules.frames where !taken {
            match.advance(inputs: [.idle, PlayerInput(throwBall: frame == 0)])
            taken = match.players[1].hasFireball
        }
        XCTAssertTrue(taken)
        XCTAssertTrue(match.fireballs.isEmpty)
    }

    func testWithoutBobaTheSnatchTakesNoFireball() {
        var match = court()
        match.fireballs.append(Fireball(id: 99, owner: 0, position: match.players[1].handCatchPoint + Vec2(x: -8, y: 0),
                                        velocity: Vec2(x: 1, y: 0), framesLeft: 100, straight: true))
        for frame in 0..<SnatchRules.frames { match.advance(inputs: [.idle, PlayerInput(throwBall: frame == 0)]) }
        XCTAssertFalse(match.players[1].hasFireball)
    }

    func testTheThrowerCatchesTheirOwnFireball() {
        var match = court()
        match.players[0].power = .blazingBoba
        match.fireballs.append(Fireball(id: 99, owner: 0, position: match.players[0].chest + Vec2(x: 20, y: 0),
                                        velocity: Vec2(x: -2, y: 0), framesLeft: 100, straight: true))
        for _ in 0..<12 where !match.players[0].hasFireball { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].hasFireball)
        XCTAssertTrue(match.events.contains(.fireballTaken(player: 0)) || match.fireballs.isEmpty)
    }
}
