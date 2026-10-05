import XCTest
@testable import EsperSim

/// Flight: a hand-laid stage as big as a phone shows whole at 4x.
final class FlightTests: XCTestCase {
    func testFlightIsOnTheSelectAtItsSize() {
        XCTAssertTrue(StageChoice.selectable.contains(.flight))
        let stage = StageChoice.flight.stage
        XCTAssertEqual(stage.features.look, .flight)
        XCTAssertEqual(stage.columns, FlightRules.columns)
        XCTAssertEqual(stage.rows, FlightRules.rows)
        // At 4x, 16 art pixels a tile, it fits a 2532 by 1170 phone, and no bigger would.
        XCTAssertLessThanOrEqual(FlightRules.columns * 16 * 4, 2532)
        XCTAssertGreaterThan((FlightRules.columns + 1) * 16 * 4, 2532)
        XCTAssertLessThanOrEqual(FlightRules.rows * 16 * 4, 1170)
        XCTAssertGreaterThan((FlightRules.rows + 1) * 16 * 4, 1170)
    }

    func testTheBakedMapStandsEveryoneOnItsFloor() {
        var match = Match(stage: StageChoice.flight.stage)
        match.countdown = 0
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players.allSatisfy(\.grounded))
        XCTAssertEqual(match.stage.hoops.count, 2)
    }
}
