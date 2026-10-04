import XCTest
@testable import EsperSim

/// FLO: what each play earns, up to full, and that it's kept through a point.
final class FloTests: XCTestCase {
    private func gains(_ match: Match) -> [(player: Int, amount: Int)] {
        match.events.compactMap { if case .floGained(let player, let amount, _) = $0 { return (player, amount) } else { return nil } }
    }

    func testATauntEarnsThreeAsTheBallFirstMeetsTheFloor() {
        var match = Match()
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.players[0].enter(.taunt)
        var earned: [Int] = []
        for _ in 0..<60 where match.players[0].state == .taunt {
            match.advance(inputs: [.idle, .idle])
            earned += gains(match).filter { $0.player == 0 }.map(\.amount)
        }
        XCTAssertEqual(earned, [FloRules.taunt], "once, as the ball first meets the floor")
        XCTAssertEqual(match.players[0].flo, FloRules.taunt)
    }

    func testABasketEarnsTwentyAndAPointKeepsIt() {
        var match = Match()
        match.countdown = 0
        match.ball.respawn(at: match.stage.hoops[1].position + Vec2(x: 0, y: 12))
        match.ball.velocity = .zero
        match.ball.scoring = true
        var earned = 0
        for _ in 0..<60 where match.scores[0] == 0 {
            match.advance(inputs: [.idle, .idle])
            earned += gains(match).filter { $0.player == 0 }.map(\.amount).reduce(0, +)
        }
        XCTAssertEqual(match.scores[0], 1)
        XCTAssertEqual(earned, FloRules.madeShot)
        match.restart(ballTo: 1)
        XCTAssertEqual(match.players[0].flo, FloRules.madeShot, "kept through the restart")
    }

    func testFloStopsAtFull() {
        var player = Player(spec: .starting, index: 0, position: .zero, facing: .right)
        var events: [MatchEvent] = []
        player.flo = FloRules.full - 2
        player.gainFlo(FloRules.madeShot, at: .zero, events: &events)
        XCTAssertEqual(player.flo, FloRules.full)
        XCTAssertEqual(events, [.floGained(player: 0, amount: 2, at: .zero)])
        player.gainFlo(FloRules.pop, at: .zero, events: &events)
        XCTAssertEqual(events.count, 1, "nothing more at full")
    }
}
