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

    func testADunkOnTheHooperfishSpinsItAndScoresNothing() {
        var match = wetshot()
        match.hooperfish!.carrying = .hoop
        // Mid-crossing, the rim well inside the stage.
        match.hooperfish!.swimFrames = 100_000
        match.hooperfish!.from = Vec2(x: 160, y: 90)
        match.hooperfish!.to = Vec2(x: 161, y: 90)
        match.advance(inputs: [.idle, .idle])
        let rim = match.stage.hoops[0].position
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.players[0].position = rim - Vec2(x: 12, y: 20)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.players[0].velocity = .zero
        var spun = false, sawRimOut = false
        for _ in 0..<150 {
            match.advance(inputs: [PlayerInput(throwBall: true), .idle])
            if match.events.contains(.hooperfishSpun) { spun = true }
            if spun, match.hooperfish!.spin > 0, match.stage.hoops[0].position == HighwayRules.parked { sawRimOut = true }
        }
        XCTAssertTrue(spun, "the dunk got as far as the slam")
        XCTAssertTrue(sawRimOut, "the rim out of play through the spin")
        XCTAssertEqual(match.scores, [0, 0])
        XCTAssertNotEqual(match.players[0].state, .dunking)
        XCTAssertNotEqual(match.stage.hoops[0].position, HighwayRules.parked, "back once it's spun")
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
        match.players[0].position = match.hooperfish!.ballPoint - Vec2(x: 0, y: 10)
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

    func testUnderWaterGravityTheJumpsAndEverySpeedAreHalved() {
        var dry = Player(spec: .starting, index: 0, position: Vec2(x: 100, y: 10), facing: .right)
        var wet = dry
        wet.underwater = true
        XCTAssertEqual(wet.gravity, dry.gravity / 2)
        XCTAssertEqual(wet.runSpeed, dry.runSpeed / 2)
        XCTAssertEqual(wet.walkMaxSpeed, dry.walkMaxSpeed / 2)
        XCTAssertEqual(wet.airSpeedMax, dry.airSpeedMax / 2)
        XCTAssertEqual(wet.fullHopVelocity, dry.fullHopVelocity / 2)
        XCTAssertEqual(wet.fallSpeed, dry.fallSpeed / 2)
        var match = wetshot()
        match.players[0].enter(.idle)
        match.players[1].enter(.idle)
        for _ in 0..<10 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].stateTimer, 5, "every state's clock, and so its sheet, at half speed")
        XCTAssertTrue(Stage.wetshot.features.underwater)
    }
}

final class DeciderTests: XCTestCase {
    /// A point that levels the stage's best of three puts the ball in neutral for the decider;
    /// any other point gives it to whoever was scored on.
    func testTheDeciderStartsWithTheBallInNeutral() {
        var match = Match()
        match.countdown = 0
        func score(_ match: inout Match, owner: Int) {
            let hoop = match.stage.hoops.firstIndex { $0.owner == owner }!
            let rim = match.stage.hoops[hoop].position
            match.ball.respawn(at: rim + Vec2(x: 0, y: 6))
            match.ball.velocity = Vec2(x: 0, y: -2)
            match.ball.scoring = true
            match.ball.lastTouched = owner
            for _ in 0..<40 { match.advance(inputs: [.idle, .idle]) }
        }
        score(&match, owner: 0)
        XCTAssertEqual(match.scores, [1, 0])
        XCTAssertEqual(match.ball.holder, 1, "to whoever was scored on")
        score(&match, owner: 1)
        XCTAssertEqual(match.scores, [1, 1])
        XCTAssertNil(match.ball.holder, "level: the decider from neutral")
        XCTAssertEqual(match.ball.position.x, match.stage.ballSpawn.x, "loose where it starts")
    }

    func testOnWetshotWakeTheDecidersBallGoesBackOnTheHooperfish() {
        var match = Match(stage: .wetshot)
        match.hooperfish!.carrying = .hoop
        match.scores = [1, 1]
        match.restart(ballTo: nil)
        XCTAssertEqual(match.hooperfish!.carrying, .ball)
        XCTAssertNil(match.ball.holder)
        XCTAssertEqual(match.ball.position, match.hooperfish!.ballPoint)
    }

    private func jump(on stage: Stage) -> (height: Double, frames: Int) {
        var match = Match(stage: stage)
        match.countdown = 0
        for _ in 0..<30 { match.advance(inputs: [.idle, .idle]) }
        let start = match.players[0].position.y
        var top = start, topFrame = 0
        for frame in 0..<600 {
            match.advance(inputs: [PlayerInput(jump: true), .idle])
            if match.players[0].position.y > top { top = match.players[0].position.y; topFrame = frame }
        }
        return (top - start, topFrame)
    }

    func testUnderWaterAJumpGoesTwiceAsHighButRisesSlower() {
        let dry = jump(on: .court), wet = jump(on: .wetshot)
        XCTAssertEqual(wet.height / dry.height, 2, accuracy: 0.25)
        XCTAssertGreaterThan(Double(wet.frames), Double(dry.frames) * 3, "slow to the top")
    }

    func testARimSwimmingOffLetsGoOfWhoeverHangsOnIt() {
        var match = Match(stage: .wetshot)
        match.hooperfish!.carrying = .hoop
        // Swum off, the rim gone with it.
        match.hooperfish!.age = match.hooperfish!.swimFrames + 1
        match.players[0].state = .dunking
        match.players[0].dunkHoop = 0
        match.advance(inputs: [.idle, .idle])
        XCTAssertNotEqual(match.players[0].state, .dunking)
    }

    func testNoSecondPointRightAfterOne() {
        var match = Match(stage: .wetshot, mode: .fortySeven)
        match.countdown = 0
        match.hooperfish = nil
        match.stage.hoops[0].position = Stage.wetshot.hoops[0].position
        let rim = match.stage.hoops[0].position
        match.ball.respawn(at: rim + Vec2(x: 0, y: 6))
        match.ball.velocity = Vec2(x: 0, y: -2)
        match.ball.scoring = true
        match.ball.lastTouched = 0
        var points = 0
        for frame in 0..<12 {
            match.advance(inputs: [.idle, .idle])
            if match.events.contains(where: { if case .scored = $0 { return true }; return false }) { points += 1 }
            if frame == 6 {
                // Straight back up through it and down again, as a rim on the move can do.
                match.ball.position = rim + Vec2(x: 0, y: 6)
                match.ball.velocity = Vec2(x: 0, y: -2)
            }
        }
        XCTAssertEqual(points, 1)
    }

    func testNoDunkInTheFirstOrLastColumnAndOneThereIsLetGo() {
        let stage = Stage.wetshot
        var hoop = stage.hoops[0]
        hoop.position.x = 5
        XCTAssertFalse(stage.dunkable(hoop))
        hoop.position.x = stage.width - 5
        XCTAssertFalse(stage.dunkable(hoop))
        hoop.position.x = stage.width / 2
        XCTAssertTrue(stage.dunkable(hoop))
        var match = Match(stage: .wetshot)
        match.hooperfish!.carrying = .hoop
        match.hooperfish!.from = Vec2(x: -5, y: 100)
        match.hooperfish!.to = Vec2(x: -HooperfishRules.size.x, y: 100)
        match.hooperfish!.swimFrames = 600
        match.hooperfish!.age = 0
        match.players[0].state = .dunking
        match.players[0].dunkHoop = 0
        match.advance(inputs: [.idle, .idle])
        XCTAssertNotEqual(match.players[0].state, .dunking, "the rim in the first column lets go")
    }
}
