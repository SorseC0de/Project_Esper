import XCTest
@testable import EsperSim

/// The Test Center's dummy does its one move over and over.
final class TrainingDummyTests: XCTestCase {
    private func events(_ routine: TrainingDummy.Routine, frames: Int = 600) -> (events: [MatchEvent], match: Match) {
        var match = Match(stage: .testCenter, specs: [.starting, .starting])
        match.countdown = 0
        match.ball.holder = nil
        match.players.indices.forEach { match.players[$0].hasBall = false }
        var dummy = TrainingDummy(index: 1, routine: routine)
        var seen: [MatchEvent] = []
        for _ in 0..<frames {
            let input = dummy.decide(&match)
            match.advance(inputs: [.idle, input])
            seen += match.events
        }
        return (seen, match)
    }

    func testTheShieldGoesUpFacingEachWayInTurn() {
        var match = Match(stage: .testCenter, specs: [.starting, .starting])
        match.countdown = 0
        match.ball.holder = nil
        match.players.indices.forEach { match.players[$0].hasBall = false }
        var dummy = TrainingDummy(index: 1, routine: .shield)
        var facings: [Facing] = []
        for _ in 0..<600 {
            let input = dummy.decide(&match)
            match.advance(inputs: [.idle, input])
            if match.events.contains(where: { if case .shieldRaised(player: 1, _) = $0 { return true } else { return false } }) {
                facings.append(match.players[1].facing)
            }
        }
        XCTAssertGreaterThanOrEqual(facings.count, 3)
        XCTAssertEqual(Array(facings.prefix(3)), [facings[0], facings[0] == .left ? .right : .left, facings[0]])
    }

    func testItSlashesAndSnatchesOverAndOver() {
        XCTAssertGreaterThanOrEqual(events(.slash).events.filter { $0 == .slashed(player: 1) }.count, 3)
        XCTAssertGreaterThanOrEqual(events(.snatch).events.filter { $0 == .snatchReached(player: 1) }.count, 3)
    }

    func testItSpinsWithTheBallOverAndOver() {
        let spun = events(.spin).events.filter { if case .spun(player: 1, _) = $0 { return true } else { return false } }
        XCTAssertGreaterThanOrEqual(spun.count, 3)
    }
}
