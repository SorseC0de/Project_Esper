import XCTest
@testable import EsperSim

/// Flight: a hand-laid stage drawn for 8x.
final class FlightTests: XCTestCase {
    func testFlightIsOnTheSelectAtItsSize() {
        XCTAssertTrue(StageChoice.selectable.contains(.flight))
        let stage = StageChoice.flight.stage
        XCTAssertEqual(stage.features.look, .flight)
        XCTAssertEqual(stage.columns, FlightRules.columns)
        XCTAssertEqual(stage.rows, FlightRules.rows)
        // At 8x, 16 art pixels a tile, its 2496-pixel-wide backdrop fits in it, and its height in a 1170-pixel phone.
        XCTAssertGreaterThanOrEqual(FlightRules.columns * 16 * 8, 2496)
        XCTAssertLessThanOrEqual(FlightRules.rows * 16 * 8, 1170)
    }

    func testTheBakedMapStandsEveryoneOnItsFloor() {
        var match = Match(stage: StageChoice.flight.stage)
        match.countdown = 0
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players.allSatisfy(\.grounded))
        XCTAssertEqual(match.stage.hoops.count, 2)
    }
}
