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

    func testTheRedCarIsElevenSolidsAndTwoSlopesToStandOn() {
        let stage = Stage.kAndA
        let solids = (4...11).filter { stage.tile(column: $0, row: 3) == .solid }.count + (7...9).filter { stage.tile(column: $0, row: 4) == .solid }.count
        XCTAssertEqual(solids, 11)
        XCTAssertEqual(stage.fixedSlopes.count, 2)
        XCTAssertEqual(stage.fixedSlopes.filter(\.rising).count, 1, "one slope up onto the roof, one down off it")
        // A body dropped onto the roof stands on it, above the ground.
        var match = Match(stage: .kAndA)
        match.countdown = 0
        match.players[0].position = Vec2(x: 80, y: 70)
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].grounded)
        XCTAssertEqual(match.players[0].position.y, 50, accuracy: 1e-9, "on the roof, row 4's top")
    }

    func testTheMapLaysItsWallsAndStarts() {
        let before = StageMap.current[.kAndA]
        defer { StageMap.current[.kAndA] = before }
        XCTAssertEqual(Stage.kAndA.tile(column: 10, row: 5), .empty)
        var map = before
        map.walls.append(StageMap.Wall(StageMap.Cell(10, 5), .solid))
        map.spawns = [StageMap.Cell(3, 3), StageMap.Cell(30, 3)]
        StageMap.current[.kAndA] = map
        let stage = Stage.kAndA
        XCTAssertEqual(stage.tile(column: 10, row: 5), .solid, "a wall painted in the map maker is the stage's")
        XCTAssertEqual(stage.playerSpawns[0].x, 35, accuracy: 1e-9, "the starts the map's")
        XCTAssertEqual(stage.playerFacings, [.right, .left])
        XCTAssertEqual(stage.hoops[1].position.y, KAndARules.rimHeight, "the rims the bridge's, not the map's")
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
