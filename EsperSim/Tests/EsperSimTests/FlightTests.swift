import XCTest
@testable import EsperSim

/// Flight: a hand-laid stage drawn for 6x.
final class FlightTests: XCTestCase {
    func testFlightIsParkedAtItsSize() {
        XCTAssertFalse(StageChoice.selectable.contains(.flight), "parked off the select")
        let stage = StageChoice.flight.stage
        XCTAssertEqual(stage.features.look, .flight)
        XCTAssertEqual(stage.columns, FlightRules.columns)
        XCTAssertEqual(stage.rows, FlightRules.rows)
        // At 6x, 16 art pixels a tile, it's its 2496 by 1152 backdrop, and fits a 2532 by 1170 phone.
        XCTAssertEqual(FlightRules.columns * 16 * 6, 2496)
        XCTAssertEqual(FlightRules.rows * 16 * 6, 1152)
    }

    func testTheBakedMapStandsEveryoneOnItsFloor() {
        var match = Match(stage: StageChoice.flight.stage)
        match.countdown = 0
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players.allSatisfy(\.grounded))
        XCTAssertEqual(match.stage.hoops.count, 2)
        XCTAssertEqual(match.players[0].spec.scale, FlightRules.bodyScale, accuracy: 1e-9, "the bodies drawn a third bigger")
        XCTAssertEqual(match.players[0].spec.bodyHeight, FighterSpec.baseline.bodyHeight * FlightRules.bodyScale, accuracy: 1e-9)
    }
}
