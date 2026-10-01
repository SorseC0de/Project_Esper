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
            // The rim held still where the map puts it, the Hooperfish out of it.
            match.hooperfish = nil
            match.stage.hoops[0].position = Stage.wetshot.hoops[0].position
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

    private func wetshot() -> Match {
        var match = Match(stage: .wetshot)
        match.countdown = 0
        match.players[0].position = Vec2(x: 30, y: 10)
        match.players[1].position = Vec2(x: 340, y: 10)
        return match
    }

    func testTheHooperfishStartsWithTheBallOnItsAntennaAndNoRimOut() {
        var match = wetshot()
        let fish = match.hooperfish!
        XCTAssertEqual(fish.carrying, .ball)
        XCTAssertEqual(fish.position, match.stage.hooperfishStart)
        XCTAssertEqual(match.ball.position, fish.ballPoint)
        XCTAssertEqual(match.stage.hoops[0].position, HighwayRules.parked)
        for _ in 0..<30 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertLessThan(match.hooperfish!.position.x, fish.position.x, "swimming off the way it faces")
        XCTAssertEqual(match.ball.position, match.hooperfish!.ballPoint, "the ball rides along")
    }

    func testAHandTakesTheBallOffTheAntenna() {
        var match = wetshot()
        match.players[0].position = match.hooperfish!.antenna - Vec2(x: 0, y: 10)
        // Facing the way it swims, so the ball comes to the hands.
        match.players[0].facing = .left
        match.players[0].grounded = false
        match.players[0].enter(.air)
        for _ in 0..<5 where match.ball.holder == nil { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.ball.holder, 0)
        XCTAssertEqual(match.hooperfish?.carrying, Hooperfish.Carrying.nothing)
    }

    private func throughCrossing(_ match: inout Match) {
        let fish = match.hooperfish!
        for _ in 0..<(fish.swimFrames - fish.age + HooperfishRules.waitFrames) { match.advance(inputs: [.idle, .idle]) }
    }

    func testUntakenTheBallComesBackOnItsAntennaTurnedRoundFromAHeightToAHeight() {
        var match = wetshot()
        let first = match.hooperfish!
        for _ in 0..<first.swimFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.hooperfish!.away)
        XCTAssertEqual(match.hooperfish!.position.x, -HooperfishRules.size.x, accuracy: 0.001, "wholly off the left")
        XCTAssertEqual(match.ball.position, match.hooperfish!.ballPoint, "the ball still on it")
        for _ in 0..<HooperfishRules.waitFrames { match.advance(inputs: [.idle, .idle]) }
        let back = match.hooperfish!
        XCTAssertFalse(back.away)
        XCTAssertTrue(back.facesRight, "turned round")
        XCTAssertEqual(back.carrying, .ball, "back with the ball, not yet taken")
        XCTAssertEqual(back.swimFrames, HooperfishRules.swimFrames, "ten seconds across")
        XCTAssertNotEqual(back.from.y, back.to.y, "a height to a height")
        for y in [back.from.y, back.to.y] {
            XCTAssertGreaterThanOrEqual(y, HooperfishRules.lowest)
            XCTAssertLessThanOrEqual(y, match.stage.height - 3 * Stage.tileSize)
        }
    }

    func testOnceTheBallsTakenTheRimComesOnItsNextCrossingAndStays() {
        var match = wetshot()
        match.ball.holder = 0
        match.players[0].hasBall = true
        match.hooperfish!.carrying = .nothing
        throughCrossing(&match)
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.hooperfish!.carrying, .hoop)
        XCTAssertEqual(match.stage.hoops[0].position, match.hooperfish!.antenna, "the rim on its antenna")
        XCTAssertEqual(match.stage.hoops[0].backboard, .left, "turned with it")
        throughCrossing(&match)
        XCTAssertEqual(match.hooperfish!.carrying, .hoop, "from then on")
    }

    func testUnderWaterGravityAndTheGroundsSpeedsAreHalvedButNotTheAirs() {
        var dry = Player(spec: .starting, index: 0, position: Vec2(x: 100, y: 10), facing: .right)
        var wet = dry
        wet.underwater = true
        XCTAssertEqual(wet.gravity, dry.gravity / 2)
        XCTAssertEqual(wet.runSpeed, dry.runSpeed / 2)
        XCTAssertEqual(wet.walkMaxSpeed, dry.walkMaxSpeed / 2)
        XCTAssertEqual(wet.airSpeedMax, dry.airSpeedMax)
        XCTAssertEqual(wet.fallSpeed, dry.fallSpeed / 2)
        var match = wetshot()
        match.players[0].enter(.idle)
        match.players[1].enter(.idle)
        for _ in 0..<10 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].stateTimer, 5, "every state's clock, and so its sheet, at half speed")
        XCTAssertTrue(Stage.wetshot.features.underwater)
    }
}
