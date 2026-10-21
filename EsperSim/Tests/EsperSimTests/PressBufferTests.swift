import XCTest
@testable import EsperSim

/// Strike and Guard are kept a few frames, as jump is: a press in the landing lag comes out after
/// it, and the last press wins.
final class PressBufferTests: XCTestCase {
    private func landed() -> Match {
        var match = Match(stage: .court, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].hasBall = false
        match.ball.holder = nil
        match.ball.position = Vec2(x: 300, y: 10)
        match.players[0].position = Vec2(x: 100, y: 10)
        match.players[0].grounded = true
        match.players[0].enter(.land)
        return match
    }

    func testAStrikeInTheLandingLagComesOutAfterIt() {
        var match = landed()
        var slashed = false
        for frame in 0..<12 {
            match.advance(inputs: [PlayerInput(shoot: frame == 0), .idle])
            if match.events.contains(.slashed(player: 0)) { slashed = true }
        }
        XCTAssertTrue(slashed)
    }

    func testTheLastPressWins() {
        var match = landed()
        var slashed = false, snatched = false
        for frame in 0..<12 {
            match.advance(inputs: [PlayerInput(shoot: frame == 0, throwBall: frame == 1), .idle])
            if match.events.contains(.slashed(player: 0)) { slashed = true }
            if match.players[0].state == .snatching { snatched = true }
        }
        XCTAssertFalse(slashed)
        XCTAssertTrue(snatched)
    }
}
