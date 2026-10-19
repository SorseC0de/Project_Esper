import XCTest
@testable import EsperSim

/// A loose ball is caught only out of a neutral state; the slide kicks one on.
final class CatchRulesTests: XCTestCase {
    private func court() -> Match {
        var match = Match(stage: .court, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].position = Vec2(x: 120, y: 10)
        match.players[0].facing = .right
        match.players[1].position = Vec2(x: 400, y: 10)
        match.ball.holder = nil
        match.players.indices.forEach { match.players[$0].hasBall = false }
        return match
    }

    func testOnlyNeutralStatesCatch() {
        let neutral: [PlayerState] = [.idle, .walk, .dash, .run, .pivot, .air, .flying, .crouch, .crouchWalk]
        let actions: [PlayerState] = [.jumpSquat, .land, .slide, .slashing, .snatching, .beamCharging, .beamFiring, .wallLand,
                                      .webSwing, .suspended, .shootStance, .throwStance, .taunt]
        for state in neutral { XCTAssertTrue(state.canCatch, "\(state)") }
        for state in actions { XCTAssertFalse(state.canCatch, "\(state)") }
    }

    func testZTeaChargingTheBeamDoesNotCatchTheBall() {
        var match = court()
        match.players[0].power = .zTea
        match.players[0].powerLevel = 1
        match.ball.respawn(at: Vec2(x: 300, y: 30))
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .beamCharging)
        // The ball dropped right on the hand, coming back as a throw would.
        match.ball.position = match.players[0].chest
        match.ball.velocity = .zero
        match.ball.lastTouched = 0
        match.ball.returning = true
        match.advance(inputs: [.idle, .idle])
        XCTAssertNotEqual(match.ball.holder, 0)
    }

    func testTheSlideKicksALooseBallOnRatherThanCatchingIt() {
        var match = court()
        match.ball.respawn(at: Vec2(x: 160, y: 30))
        match.ball.position = Vec2(x: 140, y: 10 + BallRules.radius)
        match.ball.velocity = .zero
        match.players[0].enter(.slide)
        match.players[0].velocity.x = 3
        var kicked = false
        for _ in 0..<10 {
            match.advance(inputs: [.idle, .idle])
            if match.ball.velocity.x > 1 { kicked = true }
        }
        XCTAssertNotEqual(match.ball.holder, 0)
        XCTAssertTrue(kicked, "sent on ahead")
    }
}
