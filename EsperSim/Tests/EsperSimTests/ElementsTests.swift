import XCTest
@testable import EsperSim

final class ElementsTests: XCTestCase {
    func testTheElementsIsTwoCourtsAcrossAndTwoHigh() {
        let stage = Stage.elements
        XCTAssertEqual(stage.columns, Stage.court.columns * 2 - 1, "two courts across, less a column for a middle one")
        XCTAssertEqual(stage.rows, Stage.court.rows * 2)
        XCTAssertEqual(stage.features.look, .elements)
        XCTAssertEqual(StageChoice.theElements.stage.features.look, .elements)
    }

    func testTheDefaultMapStandsEveryoneOnSomethingAndHangsTheRimsInTheOpen() {
        let stage = Stage.elements
        for (index, spawn) in stage.playerSpawns.enumerated() {
            let feet = Box(min: Vec2(x: spawn.x - 2, y: spawn.y), max: Vec2(x: spawn.x + 2, y: spawn.y + 17.5))
            XCTAssertFalse(stage.overlapsSolid(feet), "player \(index) starts clear")
            XCTAssertTrue(stage.isGrounded(feet), "player \(index) starts standing")
            XCTAssertGreaterThan(spawn.y, ElementsRules.lavaSurface)
        }
        for hoop in stage.hoops {
            XCTAssertFalse(stage.overlapsSolid(Box(center: hoop.position, width: 10, height: 6)), "the rim's in the open")
        }
        XCTAssertFalse(stage.overlapsSolid(Box(center: stage.ballSpawn, width: 5, height: 5)))
    }

    func testTheDefaultMapMirrorsAboutTheMiddleAndTheBallStartsDeadCentre() {
        let map = ElementsMap.baked
        let last = ElementsRules.columns - 1
        // Everything but the ceiling and the middle platform the ball starts on.
        let sides = map.tiles.filter { $0.cell.row != ElementsRules.rows - 1 && !((28...38).contains($0.cell.column) && (12...15).contains($0.cell.row)) }
        XCTAssertEqual(Set(sides.map { [$0.cell.column, $0.cell.row] }), Set(sides.map { [last - $0.cell.column, $0.cell.row] }))
        XCTAssertEqual(map.leftRim.column, last - map.rightRim.column)
        XCTAssertEqual(map.leftRim.row, map.rightRim.row)
        XCTAssertEqual(map.spawns[0].column, last - map.spawns[1].column)
        XCTAssertEqual(map.spawns[0].row, map.spawns[1].row)
        XCTAssertTrue(map.tiles.allSatisfy { (0...last).contains($0.cell.column) && (0..<ElementsRules.rows).contains($0.cell.row) }, "nothing off the stage")
        let stage = Stage.elements
        XCTAssertEqual(stage.ballSpawn.x, stage.width / 2, accuracy: 0.0001)
        // The middle platform is centred too: its top row runs 28 to 38 about the middle column, 33.
        let top = map.tiles.filter { $0.cell.row == 14 && (26...40).contains($0.cell.column) }.map(\.cell.column).sorted()
        XCTAssertEqual(top, Array(28...38))
    }

    func testTheRightSideUsesTheOppositeTilesOfTheLeft() {
        // A slope's left tile on the left is its right tile on the right, across the middle.
        let map = ElementsMap.baked
        func art(_ column: Int, _ row: Int) -> ElementsMap.Cell? { map.tiles.first { $0.cell == .init(column, row) }?.art }
        XCTAssertEqual(art(19, 15), .init(6, 5))
        XCTAssertEqual(art(47, 15), .init(7, 5))
        XCTAssertEqual(art(2, 9), .init(7, 3))
        XCTAssertEqual(art(64, 9), .init(13, 3))
    }

    func testDecorationTilesArentSolid() {
        var map = ElementsMap.baked
        map.tiles.append(.init(.init(30, 25), art: .init(2, 0)))
        map.tiles.append(.init(.init(31, 25), art: .init(2, 2)))
        ElementsMap.current = map
        defer { ElementsMap.current = ElementsMap.baked }
        let stage = Stage.elements
        XCTAssertEqual(stage.tile(column: 30, row: 25), .empty)
        XCTAssertEqual(stage.tile(column: 31, row: 25), .solid)
    }

    func testTheLavaSendsWhoeverFallsInBackToTheirStart() {
        var match = Match(stage: .elements, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.players[0].position = Vec2(x: 300, y: ElementsRules.lavaSurface + 3)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        var burned = false
        for _ in 0..<40 {
            match.advance(inputs: [.idle, .idle])
            if match.events.contains(.lavaBurned(player: 0)) { burned = true; break }
        }
        XCTAssertTrue(burned)
        XCTAssertEqual(match.players[0].position, match.stage.playerSpawns[0])
        XCTAssertFalse(match.players[0].hasBall)
        XCTAssertNil(match.ball.holder)
        XCTAssertEqual(match.ball.position.x, match.stage.ballSpawn.x, accuracy: 0.001)
        XCTAssertEqual(match.players[1].position, match.stage.playerSpawns[1], "the other's left alone")
    }

    func testALooseBallInTheLavaGoesBackToItsStart() {
        var match = Match(stage: .elements, specs: [.starting, .starting])
        match.countdown = 0
        match.ball.holder = nil
        match.ball.respawn(at: Vec2(x: 300, y: ElementsRules.lavaSurface + 4))
        match.ball.velocity = Vec2(x: 0, y: -3)
        for _ in 0..<30 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertGreaterThan(match.ball.position.y, ElementsRules.lavaSurface - 1)
        XCTAssertEqual(match.ball.position.x, match.stage.ballSpawn.x, accuracy: 20)
    }

    func testTheMapRoundTripsThroughItsSource() {
        XCTAssertTrue(ElementsMap.baked.swiftSource.contains("Placed(Cell(2, 9), art: Cell(7, 3))"))
        let data = try! JSONEncoder().encode(ElementsMap.baked)
        XCTAssertEqual(try! JSONDecoder().decode(ElementsMap.self, from: data), ElementsMap.baked)
    }
}
