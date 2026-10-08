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
        // The starts are over the two cars: each lands on a roof, two rows over the three of ground.
        XCTAssertEqual(match.players[0].position.y, 50, accuracy: 1e-9)
        XCTAssertEqual(match.players[1].position.y, 50, accuracy: 1e-9)
        XCTAssertEqual(match.stage.tile(column: 18, row: 2), .solid, "three rows of ground")
        XCTAssertEqual(match.stage.tile(column: 18, row: 3), .empty)
        XCTAssertEqual(match.stage.hoops.count, 2)
        for hoop in match.stage.hoops {
            // The rims where the map puts them, under the bridge; the backboard solid from under the
            // rim up to the stage's ceiling, the bridge being no wall.
            XCTAssertLessThan(hoop.position.y, KAndARules.bridgeBottom)
            let board = match.stage.fixedExtras.first { $0.min.y < hoop.position.y && $0.max.y > hoop.position.y }
            XCTAssertEqual(board?.max.y, Double(match.stage.rows + match.stage.skyRows) * Stage.tileSize, "the backboard solid up to the ceiling, over the bridge")
        }
        XCTAssertEqual(match.stage.hoops[0].backboard, .left)
        XCTAssertEqual(match.stage.hoops[1].backboard, .right)
    }

    func testTheCarsAreOneWaysWithOneWaySlopesAtTheirEnds() {
        let stage = Stage.kAndA
        XCTAssertEqual(stage.fixedSlopes.count, 4)
        XCTAssertTrue(stage.fixedSlopes.allSatisfy(\.oneWay))
        XCTAssertEqual(stage.fixedSlopes.filter(\.rising).count, 2, "a slope up onto each roof, one down off it")
        XCTAssertEqual(stage.tile(column: 8, row: 4), .oneWay)
        // A body dropped onto the roof stands on it, above the ground.
        var match = Match(stage: .kAndA)
        match.countdown = 0
        match.players[0].position = Vec2(x: 80, y: 70)
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].grounded)
        XCTAssertEqual(match.players[0].position.y, 50, accuracy: 1e-9, "on the roof, row 4's top")
    }

    func testAOneWaySlopeIsPassedFromBelowAndLandedOnFromAbove() {
        let stage = Stage.kAndA
        // Under the first car's left slope, cell 6, 4, a box rising through it isn't stopped.
        let below = Box(min: Vec2(x: 59, y: 30), max: Vec2(x: 69, y: 47))
        let rise = stage.sweepVertically(below, by: 8)
        XCTAssertEqual(rise.moved, 8, accuracy: 1e-9)
        XCTAssertFalse(rise.ceiling)
        XCTAssertFalse(stage.overlapsSolid(Box(min: Vec2(x: 59, y: 41), max: Vec2(x: 69, y: 58))), "nothing solid in it")
        // Falling from over it, the box lands on its surface at its middle: 44 at x 64.
        let above = Box(min: Vec2(x: 59, y: 52), max: Vec2(x: 69, y: 69))
        let fall = stage.sweepVertically(above, by: -12)
        XCTAssertTrue(fall.landed)
        XCTAssertEqual(above.min.y + fall.moved, 44, accuracy: 1e-9)
        // Dropping through, it's passed like a one-way block.
        XCTAssertFalse(stage.sweepVertically(above, by: -12, oneWays: false).landed)
        // Its straight side is no wall: a box walking left into it from the roof goes on.
        let beside = Box(min: Vec2(x: 72, y: 50), max: Vec2(x: 82, y: 67))
        XCTAssertNil(stage.sweepHorizontally(beside, by: -5).blocked)
        // The ball from below goes up through it too.
        var ball = Ball(position: Vec2(x: 64, y: 30 + BallRules.radius))
        ball.velocity = Vec2(x: 0, y: 4)
        ball.straight = false
        var events: [MatchEvent] = []
        var top = ball.position.y
        for _ in 0..<30 {
            _ = ball.step(stage: stage, events: &events)
            top = max(top, ball.position.y)
        }
        XCTAssertGreaterThan(top, 50, "the ball up through the slope")
    }

    func testTheCarIsNeitherClimbedNorJumpedOff() {
        let stage = Stage.kAndA
        // Beside the hood's end, cell 4, 3, a one-way with its top at 40: no ledge, no wall.
        let body = Box(min: Vec2(x: 28, y: 30), max: Vec2(x: 38, y: 47.5))
        XCTAssertNil(stage.ledge(beside: body, side: .right, reach: 10, top: 30...50))
        XCTAssertNil(stage.wall(beside: body))
        // Nor the roof's corner over the slope, from under it.
        let underRoof = Box(min: Vec2(x: 59, y: 35), max: Vec2(x: 69, y: 52.5))
        XCTAssertNil(stage.ledge(beside: underRoof, side: .right, reach: 10, top: 40...60))
    }

    func testTheHoodIsWalkedUpOntoTheRoof() {
        var match = Match(stage: .kAndA)
        match.countdown = 0
        // Set down on the hood, cell 5, 3's top at 40, the slope up to the roof at 6, 4 ahead.
        match.players[0].position = Vec2(x: 52, y: 40)
        for _ in 0..<10 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].grounded)
        XCTAssertEqual(match.players[0].position.y, 40, accuracy: 1e-9)
        var lowest = 40.0
        var frames = 0
        while match.players[0].position.x < 80, frames < 120 {
            match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle])
            lowest = min(lowest, match.players[0].position.y)
            frames += 1
        }
        XCTAssertLessThan(frames, 120, "walked onto the roof")
        XCTAssertEqual(lowest, 40, accuracy: 1e-9, "never through the slope")
        XCTAssertEqual(match.players[0].position.y, 50, accuracy: 1e-9, "up on the roof")
        XCTAssertTrue(match.players[0].grounded)
    }

    func testTheMapLaysItsWallsAndStarts() {
        let before = StageMap.current[.kAndA]
        defer { StageMap.current[.kAndA] = before }
        XCTAssertEqual(Stage.kAndA.tile(column: 10, row: 5), .empty)
        var map = before
        map.walls.append(StageMap.Wall(StageMap.Cell(10, 5), .solid))
        map.spawns = [StageMap.Cell(3, 3), StageMap.Cell(30, 3)]
        map.rightRim = StageMap.Cell(28, 12)
        StageMap.current[.kAndA] = map
        let stage = Stage.kAndA
        XCTAssertEqual(stage.tile(column: 10, row: 5), .solid, "a wall painted in the map maker is the stage's")
        XCTAssertEqual(stage.playerSpawns[0].x, 35, accuracy: 1e-9, "the starts the map's")
        XCTAssertEqual(stage.playerFacings, [.right, .left])
        XCTAssertEqual(stage.hoops[1].position, Vec2(x: 285, y: 125), "the rims the map's too")
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
