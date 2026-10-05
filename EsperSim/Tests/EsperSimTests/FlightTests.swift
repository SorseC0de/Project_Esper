import XCTest
@testable import EsperSim

/// Flight: a hand-laid stage as long as a phone shows whole at 3x.
final class FlightTests: XCTestCase {
    func testFlightIsOnTheSelectAtItsSize() {
        XCTAssertTrue(StageChoice.selectable.contains(.flight))
        let stage = StageChoice.flight.stage
        XCTAssertEqual(stage.features.look, .flight)
        XCTAssertEqual(stage.columns, FlightRules.columns)
        XCTAssertEqual(stage.rows, FlightRules.rows)
        // At 3x, 16 art pixels a tile, it fits a 2532-pixel-wide phone.
        XCTAssertLessThanOrEqual(FlightRules.columns * 16 * 3, 2532)
        XCTAssertGreaterThan((FlightRules.columns + 1) * 16 * 3, 2532)
    }

    func testTheBakedMapStandsEveryoneOnItsFloor() {
        var match = Match(stage: StageChoice.flight.stage)
        match.countdown = 0
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players.allSatisfy(\.grounded))
        XCTAssertEqual(match.stage.hoops.count, 2)
    }
}
