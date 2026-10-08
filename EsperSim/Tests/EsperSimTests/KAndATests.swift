import XCTest
@testable import EsperSim

/// K&A: the street under the bridge, at its art's size, its rims hung from the bridge.
final class KAndATests: XCTestCase {
    func testKAndAIsInEveryModeAtItsArtsSize() {
        XCTAssertTrue(StageChoice.selectable.contains(.kAndA))
        XCTAssertTrue(StageChoice.fortySeven.contains(.kAndA))
        XCTAssertTrue(ZonesRules.stages.contains(.kAndA))
        let stage = StageChoice.kAndA.stage
        XCTAssertEqual(stage.features.look, .kAndA)
        XCTAssertTrue(stage.features.seenWhole)
        // 592 by 304 in the file, one of its pixels an art pixel: 37 tiles by 19.
        XCTAssertEqual(stage.columns, 37)
        XCTAssertEqual(stage.rows, 19)
        XCTAssertEqual(stage.width, 592 * 0.625, accuracy: 1e-9)
        XCTAssertEqual(stage.height, 304 * 0.625, accuracy: 1e-9)
    }

    func testEveryoneStandsOnTheGroundUnderRimsHungFromTheBridge() {
        var match = Match(stage: .kAndA)
        match.countdown = 0
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players.allSatisfy(\.grounded))
        XCTAssertEqual(match.players[0].position.y, 30, accuracy: 1e-9, "three rows of ground")
        XCTAssertEqual(match.stage.hoops.count, 2)
        for hoop in match.stage.hoops {
            XCTAssertEqual(hoop.position.y + KAndARules.rimUnderBridge, KAndARules.bridgeBottom, accuracy: 1e-9, "hung from the bridge's underside")
            // The backboard solid from under the rim up to the bridge, as the court's to its blocks.
            let board = match.stage.fixedExtras.first { $0.min.y < hoop.position.y && $0.max.y > hoop.position.y }
            XCTAssertEqual(board?.max.y, KAndARules.bridgeBottom)
        }
        XCTAssertEqual(match.stage.hoops[0].backboard, .left)
        XCTAssertEqual(match.stage.hoops[1].backboard, .right)
    }

    func testZonesKeepsItsRightRimAndStartsOnTheGround() {
        let stage = Stage.zones(.kAndA)
        XCTAssertTrue(stage.hoops[0].rimless)
        XCTAssertFalse(stage.hoops[1].rimless)
        XCTAssertEqual(stage.playerSpawns[0].y, 30, accuracy: 1e-9)
        let grid = ZoneGrid(stage: stage)
        XCTAssertEqual(grid.columns, 9)
        XCTAssertEqual(grid.rows, 4)
    }
}
