import XCTest
@testable import EsperSim

/// The change into FloState can't be stopped, its orbiting ball pushes, and a Rounds point ends FloState.
final class FloStateRulesTests: XCTestCase {
    func testTheChangeIsSuperArmoured() {
        var match = Match(countdown: 0)
        match.players[0].enter(.transforming)
        match.players[0].hitStun = 30
        XCTAssertEqual(match.players[0].hitStun, 0, "never stunned")
        let at = match.players[0].position
        match.players[0].knock(Vec2(x: 5, y: 3))
        XCTAssertEqual(match.players[0].velocity, .zero, "never knocked")
        XCTAssertEqual(match.players[0].position, at)
        XCTAssertEqual(match.players[0].state, .transforming)
    }

    func testTheBallCirclingTheChangePushesAwayABodyItMeetsOnce() {
        var match = Match(countdown: 0)
        match.players[0].position = Vec2(x: 200, y: match.players[0].position.y)
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.players[0].enter(.transforming)
        guard let orbit = match.players[0].transformOrbitBall else { return XCTFail("no orbit") }
        // The other standing where the ball comes round next frame.
        match.players[1].position = Vec2(x: orbit.x, y: match.players[0].position.y)
        var pushed = 0
        for _ in 0..<TransformRules.frames {
            match.advance(inputs: [.idle, .idle])
            pushed += match.events.filter { if case .pushed(player: 1, by: 0, _) = $0 { return true } else { return false } }.count
        }
        XCTAssertEqual(pushed, 1)
        XCTAssertTrue(match.players[0].hasBall, "kept the ball through it")
    }

    func testARoundsPointEndsFloStateWithItsFloKept() {
        var match = Match(countdown: 30)
        match.countdown = 0
        match.players[1].inFloState = true
        match.players[1].flo = 60
        match.players[0].position.x = 250
        match.ball.position = match.stage.hoops[1].position + Vec2(x: 0, y: 20)
        match.ball.velocity = .zero
        match.ball.scoring = true
        for _ in 0..<120 where match.scores[0] == 0 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.scores[0], 1)
        XCTAssertFalse(match.players[1].inFloState)
        XCTAssertEqual(match.players[1].flo, 60, "kept, not burned")
        XCTAssertEqual(match.players[1].floStateLockout, 0, "no lockout: it wasn't left")
    }
}
