import XCTest
@testable import EsperSim

final class ElementsTests: XCTestCase {
    func testTheElementsIsTwoCourtsAcrossAndTwoHigh() {
        let stage = Stage.elements
        XCTAssertEqual(stage.columns, Stage.court.columns * 2 - 1, "two courts across, less a column for a middle one")
        XCTAssertEqual(stage.rows, 24)
        XCTAssertEqual(stage.features.look, .elements)
        XCTAssertEqual(StageChoice.theElements.stage.features.look, .elements)
    }

    func testTheDefaultMapDropsEveryoneInFromAboveAndHangsTheRimsInTheOpen() {
        let stage = Stage.elements
        for (index, spawn) in stage.playerSpawns.enumerated() {
            let feet = Box(min: Vec2(x: spawn.x - 2, y: spawn.y), max: Vec2(x: spawn.x + 2, y: spawn.y + 17.5))
            XCTAssertFalse(stage.overlapsSolid(feet), "player \(index) starts clear")
            XCTAssertFalse(stage.isGrounded(feet), "player \(index) starts in the air")
            XCTAssertGreaterThan(spawn.y, stage.height, "above the stage, in its shaft")
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
        XCTAssertEqual(art(18, 15), .init(6, 5))
        XCTAssertEqual(art(48, 15), .init(7, 5))
        XCTAssertEqual(art(2, 9), .init(7, 3))
        XCTAssertEqual(art(64, 9), .init(13, 3))
    }

    func testDecorationTilesArentSolid() {
        var map = ElementsMap.baked
        map.tiles.append(.init(.init(30, 20), art: .init(2, 0)))
        map.tiles.append(.init(.init(31, 20), art: .init(2, 2)))
        map.walls = ElementsMap.derivedWalls(from: map.tiles)
        ElementsMap.current = map
        defer { ElementsMap.current = ElementsMap.baked }
        let stage = Stage.elements
        XCTAssertEqual(stage.tile(column: 30, row: 20), .empty)
        XCTAssertEqual(stage.tile(column: 31, row: 20), .solid)
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
        XCTAssertEqual(match.players[1].position.x, match.stage.playerSpawns[1].x, "the other's left alone")
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

    func testTornadosAreKeptWholeOnTheStageAndReadFromAMapWithout() throws {
        var map = ElementsMap.baked
        map.tornados = [.init(30, 4), .init(50, 4)]
        XCTAssertEqual(try JSONDecoder().decode(ElementsMap.self, from: JSONEncoder().encode(map)), map)
        XCTAssertTrue(map.swiftSource.contains("tornados: [Cell(30, 4), Cell(50, 4)]"))
        // A map kept before tornados were in it has none.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(map)) as! [String: Any]
        json["tornados"] = nil
        let old = try JSONDecoder().decode(ElementsMap.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.tornados, [])
        // Moved in until the whole sprite fits: three across, three up.
        XCTAssertEqual(ElementsMap.fittingTornado(.init(0, 40)), .init(1, ElementsRules.rows - 3))
        XCTAssertEqual(ElementsMap.fittingTornado(.init(ElementsRules.columns - 1, -3)), .init(ElementsRules.columns - 2, 0))
        let span = ElementsMap.tornadoCells(.init(10, 5))
        XCTAssertEqual(span.columns, 9...11)
        XCTAssertEqual(span.rows, 5...7)
    }

    private func withWalls(_ walls: [ElementsMap.Wall], _ body: (Stage) -> Void) {
        var map = ElementsMap.baked
        map.tiles = []
        map.walls = walls
        ElementsMap.current = map
        defer { ElementsMap.current = ElementsMap.baked }
        body(Stage.elements)
    }

    func testTheWallsAreBlocksAndSlopesApartFromTheArt() {
        let cells: [ElementsMap.Wall] = [.init(.init(10, 10), .solid), .init(.init(11, 10), .lowerRight), .init(.init(12, 10), .lowerLeft),
                                         .init(.init(13, 10), .upperRight), .init(.init(14, 10), .upperLeft)]
        withWalls(cells) { stage in
            XCTAssertEqual(stage.tile(column: 10, row: 10), .solid)
            XCTAssertEqual(stage.fixedSlopes.map(\.rising), [true, false])
            XCTAssertEqual(stage.ceilingSlopes.map(\.rising), [false, true])
            XCTAssertEqual(stage.slopes, stage.fixedSlopes)
        }
        // A map with no walls of its own has a block under each solid tile, and none under decoration.
        let map = ElementsMap(tiles: [.init(.init(1, 1), art: .init(2, 2)), .init(.init(2, 1), art: .init(2, 0))],
                              leftRim: .init(2, 16), rightRim: .init(64, 16), spawns: [.init(5, 10), .init(61, 10)], ball: .init(33, 18))
        XCTAssertEqual(map.walls, [.init(.init(1, 1), .solid)])
    }

    func testABodyStandsOnAndClimbsAFloorSlopeAndIsStoppedUnderACeilingOne() {
        // A rising slope: a body walking right up it is lifted with the surface.
        withWalls([.init(.init(20, 5), .lowerRight)]) { stage in
            let onIt = Box(min: Vec2(x: 205, y: 55), max: Vec2(x: 210, y: 72.5))
            XCTAssertNotNil(stage.slopeSurface(under: onIt, reach: 5.5))
            XCTAssertTrue(stage.slopeDescends(under: Box(min: Vec2(x: 205, y: 55), max: Vec2(x: 210, y: 72.5)), facing: .left, reach: 5.5))
        }
        // Upper right, the solid above a diagonal falling to the right: its underside is lowest at the right.
        withWalls([.init(.init(20, 10), .upperRight)]) { stage in
            let slope = stage.ceilingSlopes[0]
            XCTAssertEqual(slope.underside(at: 200), 110, accuracy: 0.001)
            XCTAssertEqual(slope.underside(at: 210), 100, accuracy: 0.001)
            // Walking under from the left, the head stops where the underside comes down to it.
            let body = Box(min: Vec2(x: 190, y: 95), max: Vec2(x: 195, y: 112.5))
            let swept = stage.sweepHorizontally(body, by: 10)
            XCTAssertLessThan(swept.moved, 10)
            XCTAssertNotNil(swept.blocked)
            // Straight up under it is stopped by the underside at the body's lowest point under it.
            let under = Box(min: Vec2(x: 201, y: 80), max: Vec2(x: 206, y: 97.5))
            let up = stage.sweepVertically(under, by: 20)
            XCTAssertTrue(up.ceiling)
            XCTAssertLessThan(up.moved, 20)
            // Its flat top is a floor, and the solid part is solid to the body.
            XCTAssertTrue(stage.overlapsSolid(Box(min: Vec2(x: 205, y: 100), max: Vec2(x: 209, y: 110))))
            XCTAssertFalse(stage.overlapsSolid(Box(min: Vec2(x: 200.5, y: 100), max: Vec2(x: 202, y: 105))), "the open corner under the diagonal")
            XCTAssertTrue(stage.isGrounded(Box(min: Vec2(x: 201, y: 110), max: Vec2(x: 206, y: 127.5))))
        }
    }

    // MARK: The forced slide

    /// A match on a staircase of slopes down to the right: eight cells from (20, 12) to (27, 5), then a
    /// floor, or with `floor` off only the slopes, so they end over open air. The first player
    /// stands on the top one facing right, in a slide.
    private func slideDown(floor: Bool = true, facing: Facing = .right, rising: Bool = false) -> Match {
        var walls: [ElementsMap.Wall] = (0..<8).map { i in
            rising ? .init(.init(20 + i, 5 + i), .lowerRight) : .init(.init(20 + i, 12 - i), .lowerLeft)
        }
        if floor { walls += (0..<60).map { .init(.init($0, 4), .solid) } }
        var map = ElementsMap.baked
        map.tiles = []
        map.walls = walls
        ElementsMap.current = map
        var match = Match(stage: .elements, specs: [.starting, .starting])
        ElementsMap.current = ElementsMap.baked
        match.countdown = 0
        match.players[0].position = rising ? Vec2(x: 205, y: 55) : Vec2(x: 205, y: 125)
        match.players[0].facing = facing
        match.players[0].grounded = true
        match.players[0].enter(.slide)
        match.players[0].velocity.x = match.players[0].spec.dashInitialVelocity * facing.sign
        match.players[1].position = Vec2(x: 600, y: 60)
        match.ball.respawn(at: Vec2(x: 300, y: 250))
        return match
    }

    func testASlideDownASlopeIsForcedRidesTheSurfaceAndEndsOnFlatGround() {
        var match = slideDown()
        let frames = match.players[0].spec.slideFrames
        var slopeFrames = 0
        var lastY = match.players[0].position.y
        for _ in 0..<80 {
            // Everything pressed but the jump: nothing gets out of it.
            match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), shoot: true, throwBall: true), .idle])
            let player = match.players[0]
            if player.position.y > 51 {
                slopeFrames += 1
                XCTAssertEqual(player.state, .slide, "still forced on the slope, frame \(slopeFrames)")
                XCTAssertTrue(player.grounded)
                XCTAssertLessThanOrEqual(player.position.y, lastY + 0.001, "down the surface, never up")
                lastY = player.position.y
            } else {
                break
            }
        }
        XCTAssertGreaterThan(slopeFrames, frames, "longer than a slide's own timer")
        // On the flat, the forced slide is over and the slide ends.
        for _ in 0..<40 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertNotEqual(match.players[0].state, .slide)
        XCTAssertFalse(match.players[0].forcedSlide)
        XCTAssertEqual(match.players[0].position.y, 50, accuracy: 0.001)
    }

    func testAJumpCancelsTheForcedSlide() {
        var match = slideDown()
        for _ in 0..<10 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].state, .slide)
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .jumpSquat)
        XCTAssertFalse(match.players[0].forcedSlide)
    }

    func testTheForcedSlideEndsInOpenAirOffTheSlopesEnd() {
        var match = slideDown(floor: false)
        var reachedAir = false
        for _ in 0..<60 {
            match.advance(inputs: [.idle, .idle])
            if match.players[0].state == .air { reachedAir = true; break }
        }
        XCTAssertTrue(reachedAir)
        XCTAssertFalse(match.players[0].forcedSlide)
    }

    func testASlideUpASlopeIsNotForcedAndRunsItsCourse() {
        var match = slideDown(rising: true)
        match.advance(inputs: [.idle, .idle])
        XCTAssertFalse(match.players[0].forcedSlide)
        for _ in 0..<(match.players[0].spec.slideFrames + 5) { match.advance(inputs: [.idle, .idle]) }
        XCTAssertNotEqual(match.players[0].state, .slide)
    }

    func testTheMapRoundTripsThroughItsSource() {
        XCTAssertTrue(ElementsMap.baked.swiftSource.contains("Placed(Cell(2, 9), art: Cell(7, 3))"))
        let data = try! JSONEncoder().encode(ElementsMap.baked)
        XCTAssertEqual(try! JSONDecoder().decode(ElementsMap.self, from: data), ElementsMap.baked)
    }
}
