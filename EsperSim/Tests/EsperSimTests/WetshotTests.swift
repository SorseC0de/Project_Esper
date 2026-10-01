import XCTest
@testable import EsperSim

/// Wetshot Wake: laid out in the map maker, its one rim on the Hooperfish, both players'.
final class WetshotTests: XCTestCase {
    func testTheOneRimRidesTheHooperfish() {
        let stage = Stage.wetshot
        XCTAssertEqual(stage.columns, 37)
        XCTAssertEqual(stage.rows, 19)
        XCTAssertEqual(stage.hoops.count, 1)
        XCTAssertTrue(stage.hoops[0].shared)
        let fish = StageMap.baked(.wetshot).hooperfish!.cell
        XCTAssertEqual(stage.hoops[0].position, Vec2(x: Double(fish.column) * Stage.tileSize, y: Double(fish.row) * Stage.tileSize) + WetshotRules.rimFromHooperfish)
    }

    func testWhoeverPutsTheBallThroughTheSharedRimScores() {
        for scorer in 0...1 {
            var match = Match(stage: .wetshot)
            match.countdown = 0
            let rim = match.stage.hoops[0].position
            match.ball.respawn(at: rim + Vec2(x: 0, y: 6))
            match.ball.velocity = Vec2(x: 0, y: -2)
            match.ball.scoring = true
            match.ball.lastTouched = scorer
            for _ in 0..<10 { match.advance(inputs: [.idle, .idle]) }
            XCTAssertEqual(match.scores[scorer], 1, "player \(scorer + 1)'s point")
            XCTAssertEqual(match.scores[1 - scorer], 0)
        }
    }

    func testTheSelectParksSlamstillTraffic() {
        XCTAssertFalse(StageChoice.selectable.contains(.slamstillTraffic))
        XCTAssertTrue(StageChoice.selectable.contains(.wetshotWake))
        XCTAssertTrue(StageChoice.selectable.contains(.skyNet))
    }

    func testAMapWithPropsCodesAndReadsBack() throws {
        var map = StageMap.baked(.wetshot)
        map.props.append(.init(.plant3, at: .init(4, 1)))
        let data = try JSONEncoder().encode(map)
        XCTAssertEqual(try JSONDecoder().decode(StageMap.self, from: data), map)
        XCTAssertTrue(map.swiftSource(.wetshot).contains("Prop(.plant3, at: Cell(4, 1))"))
        XCTAssertTrue(map.swiftSource(.wetshot).contains("wetshotDefaultMap"))
    }
}
