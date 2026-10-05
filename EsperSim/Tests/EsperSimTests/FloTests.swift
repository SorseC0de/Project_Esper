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
        match.ball.lastTouched = 0
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

    func testAnOwnBasketEarnsTheOtherNothing() {
        var match = Match()
        match.countdown = 0
        match.ball.respawn(at: match.stage.hoops[1].position + Vec2(x: 0, y: 12))
        match.ball.velocity = .zero
        match.ball.scoring = true
        match.ball.lastTouched = 1
        for _ in 0..<60 where match.scores[0] == 0 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.scores[0], 1, "the point still counts")
        XCTAssertEqual(match.players[0].flo, 0, "but only your own baskets earn FLO")
    }

    func testFloStopsAtFull() {
        var player = Player(spec: .starting, index: 0, position: .zero, facing: .right)
        var events: [MatchEvent] = []
        player.flo = FloRules.full - 2
        player.gainFlo(FloRules.madeShot, at: .zero, events: &events)
        XCTAssertEqual(player.flo, FloRules.full)
        XCTAssertEqual(events, [.floGained(player: 0, amount: 2, at: .zero)])
        player.gainFlo(FloRules.hit, at: .zero, events: &events)
        XCTAssertEqual(events.count, 1, "nothing more at full")
    }
}

final class FloDropTests: XCTestCase {
    func testAHitEarnsFiveOffTheOther() {
        var match = Match()
        match.countdown = 0
        match.players[1].flo = 12
        match.players[0].position = Vec2(x: 150, y: 10)
        match.players[1].position = Vec2(x: 160, y: 10)
        match.players[0].facing = .right
        var earned = 0
        for frame in 0..<40 {
            match.advance(inputs: [PlayerInput(shoot: frame == 0), .idle])
            for case .floGained(0, let amount, _) in match.events { earned += amount }
        }
        XCTAssertEqual(earned, FloRules.hit, "a hit, no ball")
        XCTAssertEqual(match.players[1].flo, FloRules.takesFromTheOther ? 12 - FloRules.hit : 12)
    }

    func testABurnLeavesTheFloHoveringForAnyoneToTake() {
        var match = Match(stage: .elements, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].flo = 30
        let lava = match.stage.features.lavaSurface!
        match.players[0].position = Vec2(x: 200, y: lava - 5)
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].flo, 0)
        XCTAssertEqual(match.floBundles.count, 1)
        let bundle = match.floBundles[0]
        XCTAssertEqual(bundle.amount, 30)
        XCTAssertGreaterThanOrEqual(bundle.position.y, lava + FloRules.bundleLift)
        // The other player, standing in reach of it, takes it.
        match.players[1].position = bundle.position - Vec2(x: 0, y: match.players[1].chest.y - match.players[1].position.y)
        match.advance(inputs: [.idle, .idle])
        XCTAssertTrue(match.floBundles.isEmpty)
        XCTAssertEqual(match.players[1].flo, 30)
    }
}

/// A made basket goes down the net through the rim's middle, and keeps its way for after.
final class NetDropTests: XCTestCase {
    func testAMadeBasketIsHeldAtTheRimsMiddleWithItsWayKeptForTheNet() {
        var match = Match()
        match.countdown = 0
        let hoop = match.stage.hoops[1]
        match.ball.respawn(at: hoop.position + Vec2(x: -2, y: 8))
        match.ball.velocity = Vec2(x: 0.6, y: -2)
        match.ball.scoring = true
        match.ball.lastTouched = 0
        var entry: Vec2?
        for _ in 0..<20 where entry == nil {
            match.advance(inputs: [.idle, .idle])
            for case .scored(_, _, let came, _, _) in match.events { entry = came }
        }
        XCTAssertEqual(match.scores[0], 1)
        XCTAssertEqual(match.ball.position.x, hoop.position.x, accuracy: 1e-9, "held at the rim's middle")
        XCTAssertEqual(entry?.x ?? 0, 0.6, accuracy: 1e-9, "the net swishes the way it came in")
    }
}
