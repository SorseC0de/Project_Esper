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
        XCTAssertEqual(match.ball.position, fish.antenna)
        XCTAssertEqual(match.stage.hoops[0].position, HighwayRules.parked)
        for _ in 0..<30 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertLessThan(match.hooperfish!.position.x, fish.position.x, "swimming off the way it faces")
        XCTAssertEqual(match.ball.position, match.hooperfish!.antenna, "the ball rides along")
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

    func testOffScreenItTurnsRoundAndComesBackWithTheRimAtAHeightOffTheCount() {
        var match = wetshot()
        let first = match.hooperfish!
        for _ in 0..<first.swimFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.hooperfish!.away)
        XCTAssertEqual(match.hooperfish!.position.x, -HooperfishRules.size.x, accuracy: 0.001, "wholly off the left")
        XCTAssertNotEqual(match.ball.position, match.hooperfish!.antenna, "the ball it still had, left behind")
        for _ in 0..<HooperfishRules.waitFrames { match.advance(inputs: [.idle, .idle]) }
        let back = match.hooperfish!
        XCTAssertFalse(back.away)
        XCTAssertTrue(back.facesRight, "turned round")
        XCTAssertEqual(back.carrying, .hoop)
        XCTAssertEqual(back.swimFrames, HooperfishRules.swimFrames, "five seconds across")
        XCTAssertNotEqual(back.from.y, back.to.y, "a height to a height")
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.stage.hoops[0].position, match.hooperfish!.antenna, "the rim on its antenna")
        XCTAssertEqual(match.stage.hoops[0].backboard, .left, "turned with it")
    }

    func testUnderWaterGravityAndTheGroundsSpeedsAreHalvedButNotTheAirs() {
        var dry = Player(spec: .starting, index: 0, position: Vec2(x: 100, y: 10), facing: .right)
        var wet = dry
        wet.underwater = true
        XCTAssertEqual(wet.gravity, dry.gravity / 2)
        XCTAssertEqual(wet.runSpeed, dry.runSpeed / 2)
        XCTAssertEqual(wet.walkMaxSpeed, dry.walkMaxSpeed / 2)
        XCTAssertEqual(wet.airSpeedMax, dry.airSpeedMax)
        dry.enter(.land)
        wet.enter(.land)
        dry.stateTimer = 10
        wet.stateTimer = 10
        XCTAssertEqual(wet.animationFrame.frame * 2, dry.animationFrame.frame, "the sheet at half its rate")
        XCTAssertTrue(Stage.wetshot.features.underwater)
    }
}
