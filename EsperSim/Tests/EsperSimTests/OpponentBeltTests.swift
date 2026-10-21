import XCTest
@testable import EsperSim

/// The Wreck Center's belts drop a loose ball into the rim below; the computer guards the drop.
final class OpponentBeltTests: XCTestCase {
    /// A missed layup on the belt over the rim the human scores on: kept out, whatever the
    /// frame or two its jump is early or late.
    func testABeltDropIntoItsRimIsKeptOut() {
        var kept = 0
        for seed: UInt32 in 1...5 {
            var match = Match(stage: .court, specs: [.starting, .starting])
            match.countdown = 0
            var brain = Opponent(index: 1, seed: seed)
            let rim = match.stage.hoops.first { $0.owner == 0 } ?? match.stage.hoops[0]
            guard let belt = match.stage.conveyors.min(by: { abs($0.box.center.x - rim.position.x) < abs($1.box.center.x - rim.position.x) }) else {
                return XCTFail("the court's belts")
            }
            match.players[0].hasBall = false
            match.ball.holder = nil
            match.ball.release(from: Vec2(x: belt.box.center.x, y: belt.box.max.y + 20), velocity: Vec2(x: 0, y: -1), by: 0, straight: false)
            match.ball.shotInFlight = true
            match.ball.scoring = true
            match.players[1].position = Vec2(x: 170, y: 10)
            for _ in 0..<300 {
                let input = brain.decide(match)
                match.advance(inputs: [.idle, input])
            }
            if match.scores[0] == 0 { kept += 1 }
        }
        XCTAssertGreaterThanOrEqual(kept, 4, "kept out \(kept) of 5")
    }

    /// A miss resting deep on the belt, the far end from its drop: time to get up there, up the
    /// wall from the middle platform, and take it, from anywhere on the platform or the floor under it.
    func testABallDeepOnTheBeltIsFetched() {
        for start in [Vec2(x: 170, y: 40), Vec2(x: 185, y: 40), Vec2(x: 165, y: 10)] {
            var match = Match(stage: .court, specs: [.starting, .starting])
            match.countdown = 0
            var brain = Opponent(index: 1, seed: 1)
            let rim = match.stage.hoops.first { $0.owner == 0 } ?? match.stage.hoops[0]
            guard let belt = match.stage.conveyors.min(by: { abs($0.box.center.x - rim.position.x) < abs($1.box.center.x - rim.position.x) }) else {
                return XCTFail("the court's belts")
            }
            match.players[0].hasBall = false
            match.players[0].position = Vec2(x: 40, y: 10)
            match.ball.holder = nil
            let chain = match.stage.conveyors.filter { $0.way == belt.way && abs($0.box.max.y - belt.box.max.y) < 0.5 }
            let far = belt.way < 0 ? chain.map(\.box.max.x).max()! - BallRules.radius - 1 : chain.map(\.box.min.x).min()! + BallRules.radius + 1
            match.ball.release(from: Vec2(x: far, y: belt.box.max.y + BallRules.radius), velocity: .zero, by: 0, straight: false)
            match.players[1].position = start
            var climbed = false
            for _ in 0..<320 {
                let input = brain.decide(match)
                match.advance(inputs: [.idle, input])
                if match.players[1].position.y >= belt.box.max.y - 0.5 { climbed = true }
                if match.ball.holder == 1 { break }
            }
            XCTAssertTrue(climbed, "from \(start): up on the belt")
            XCTAssertEqual(match.ball.holder, 1, "from \(start): the ball taken")
            XCTAssertEqual(match.scores[0], 0, "from \(start)")
        }
    }
}
