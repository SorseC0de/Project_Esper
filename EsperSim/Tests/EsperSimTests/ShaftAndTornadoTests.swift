import XCTest
@testable import EsperSim

/// The Elements' drop in: down a shaft through the sky onto a slide slope, which nobody
/// stands or walks up on; and its tornados, which hold, sink, and every fourth time burn.
final class ShaftAndTornadoTests: XCTestCase {
    private func elements() -> Match {
        var match = Match(stage: .elements, specs: [.starting, .starting])
        match.countdown = 0
        return match
    }

    func testEachPlayerDropsDownTheirShaftAndSlidesDownTheSlopeBelow() {
        var match = elements()
        var slid = [false, false]
        for _ in 0..<240 {
            match.advance(inputs: [.idle, .idle])
            for index in 0...1 where match.players[index].state == .slide && match.players[index].forcedSlide { slid[index] = true }
        }
        XCTAssertEqual(slid, [true, true])
        XCTAssertLessThan(match.players[0].position.y, 160, "down off the slope")
        XCTAssertGreaterThan(match.players[0].position.x, 180, "down it to the right")
        XCTAssertLessThan(match.players[1].position.x, 490, "and to the left on the right")
    }

    func testHeldUpASlideSlopeTheBodyWalksButIsCarriedDownAndLetGoItSlides() {
        var match = elements()
        // On the left slide slope, which falls to the right.
        let x = 155.0
        let surface = match.stage.slideSlopeDownhill(under: Box(min: Vec2(x: x - 5, y: 185), max: Vec2(x: x + 5, y: 202)), reach: 30)
        XCTAssertEqual(surface, .right)
        match.players[0].position = Vec2(x: x, y: match.stage.slopeHeight(atX: x, near: 185, reach: 20)!)
        match.players[0].grounded = true
        match.players[0].enter(.idle)
        var xs: [Double] = []
        for _ in 0..<30 {
            match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0)), .idle])
            xs.append(match.players[0].position.x)
        }
        XCTAssertEqual(match.players[0].state, .walk)
        XCTAssertEqual(match.players[0].facing, .left, "facing up it")
        XCTAssertGreaterThan(xs.last!, xs.first!, "carried back down")
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .slide)
        XCTAssertEqual(match.players[0].facing, .right, "turned round, down it")
    }

    func testARegularTornadoHoldsWhoeverComesIntoItAtItsMiddleUntilItSinks() {
        var match = elements()
        let tornado = match.stage.tornados[0]
        match.players[0].position = Vec2(x: tornado.center.x + 8, y: tornado.min.y - 4)
        match.players[0].velocity = Vec2(x: 0, y: 1)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.frame = 0
        for _ in 0..<90 { match.advance(inputs: [.idle, .idle]) }
        let player = match.players[0]
        XCTAssertEqual(player.state, .suspended)
        XCTAssertEqual(player.position.x, tornado.center.x, accuracy: 0.1, "drawn to the middle")
        XCTAssertEqual(player.position.y + player.spec.bodyHeight / 2, tornado.center.y, accuracy: 0.1)
        while TornadoRules.isUp(at: match.frame + 1) { match.advance(inputs: [.idle, .idle]) }
        match.advance(inputs: [.idle, .idle])
        match.advance(inputs: [.idle, .idle])
        XCTAssertNotEqual(match.players[0].state, .suspended, "let go as it sinks")
    }

    func testJumpingOutOfATornadoIsAJumpAndItDoesntTakeTheBodyStraightBack() {
        var match = elements()
        let tornado = match.stage.tornados[0]
        match.players[0].position = Vec2(x: tornado.center.x, y: tornado.center.y - 8)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        for _ in 0..<20 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].state, .suspended)
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .air)
        XCTAssertGreaterThan(match.players[0].velocity.y, 0)
        for _ in 0..<5 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].state, .air)
    }

    func testEveryFourthTornadoToComeUpIsFireAndBurns() {
        XCTAssertEqual((0..<8).map { TornadoRules.isFire(at: $0 * TornadoRules.cycleFrames) }, [false, false, false, true, false, false, false, true])
        var match = elements()
        let tornado = match.stage.tornados[0]
        match.frame = 3 * TornadoRules.cycleFrames
        match.players[0].position = Vec2(x: tornado.center.x, y: tornado.center.y - 8)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.advance(inputs: [.idle, .idle])
        XCTAssertTrue(match.events.contains(.lavaBurned(player: 0)))
        XCTAssertEqual(match.players[0].position, match.stage.playerSpawns[0])
    }

    func testATornadoBurstsInPlaceHoldingNothingThenRisesBackOutOfTheLava() {
        let match = elements()
        var bursting = match
        bursting.frame = TornadoRules.upFrames
        XCTAssertEqual(TornadoRules.burstFrame(at: bursting.frame), 0)
        XCTAssertEqual(bursting.tornadoBoxes, match.stage.tornados, "bursting where it stood")
        XCTAssertFalse(TornadoRules.holds(at: bursting.frame))
        var gone = match
        gone.frame = TornadoRules.upFrames + TornadoRules.burstFrames + 1
        XCTAssertLessThan(gone.tornadoBoxes[0].max.y, ElementsRules.lavaSurface)
        var back = match
        back.frame = TornadoRules.cycleFrames
        XCTAssertEqual(back.tornadoBoxes, match.stage.tornados)
    }

    func testABurstLetsGoAtOnce() {
        var match = elements()
        let tornado = match.stage.tornados[0]
        match.frame = TornadoRules.upFrames - 30
        match.players[0].position = Vec2(x: tornado.center.x, y: tornado.center.y - 8)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        for _ in 0..<29 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].state, .suspended)
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .air, "let go on the burst's first frame")
    }

    func testARegularTornadoTakesTheLooseBallButNotOneLetGoInsideIt() {
        var match = elements()
        let tornado = match.stage.tornados[0]
        match.players[0].position = Vec2(x: 30, y: 400)
        match.players[1].position = Vec2(x: 600, y: 400)
        match.ball.respawn(at: Vec2(x: tornado.center.x, y: tornado.max.y + 20))
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertNotNil(match.ball.tornadoCentre)
        XCTAssertEqual(match.ball.position.x, tornado.center.x, accuracy: 0.1)
        XCTAssertEqual(match.ball.position.y, tornado.center.y, accuracy: 0.1, "held at the middle")
        var inside = elements()
        inside.players[0].position = Vec2(x: 30, y: 400)
        inside.players[1].position = Vec2(x: 600, y: 400)
        inside.ball.release(from: tornado.center, velocity: Vec2(x: 3, y: 1), by: 0, straight: false)
        inside.advance(inputs: [.idle, .idle])
        XCTAssertNil(inside.ball.tornadoCentre, "let go inside, it flies on")
    }

    func testARisingTornadoCatchesToo() {
        var match = elements()
        match.frame = TornadoRules.upFrames + TornadoRules.burstFrames + TornadoRules.underFrames + TornadoRules.riseFrames / 2
        let tornado = match.tornadoBoxes[0]
        match.players[0].position = Vec2(x: tornado.center.x, y: tornado.center.y - 8)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .suspended)
    }

    func testTheStickDriftsABodySidewaysInATornadoAndOutOfIt() {
        var match = elements()
        let tornado = match.stage.tornados[0]
        match.players[0].position = Vec2(x: tornado.center.x, y: tornado.center.y - 8)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        for _ in 0..<20 { match.advance(inputs: [.idle, .idle]) }
        let from = match.players[0].position.x
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle])
        let step = match.players[0].position.x - from
        XCTAssertEqual(step, match.players[0].airSpeedMax * TornadoRules.driftShare, accuracy: 0.001)
        for _ in 0..<150 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle]) }
        XCTAssertNotEqual(match.players[0].state, .suspended, "drifted out")
    }

    func testTheChutesHaveNoWallToLandOn() {
        let stage = Stage.elements
        let chute = stage.chutes[0]
        let againstLeft = Box(min: Vec2(x: chute.min.x, y: 260), max: Vec2(x: chute.min.x + 10, y: 277.5))
        let againstRight = Box(min: Vec2(x: chute.max.x - 10, y: 225), max: Vec2(x: chute.max.x, y: 242.5))
        XCTAssertNil(stage.wall(beside: againstLeft))
        XCTAssertNil(stage.wall(beside: againstRight))
    }

    func testABallParkedAnywhereOnASlopeRollsDownIt() {
        for startX in stride(from: 141.0, through: 179.0, by: 1) {
            var match = elements()
            match.players[0].position = Vec2(x: 30, y: 400)
            match.players[1].position = Vec2(x: 600, y: 400)
            guard let surface = match.stage.slopeHeight(atX: startX, near: 180, reach: 25) else { continue }
            match.ball.respawn(at: Vec2(x: startX, y: surface + BallRules.radius))
            for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
            XCTAssertGreaterThan(match.ball.position.x, startX + 5, "rolled on from \(startX)")
        }
    }

    func testTheFireballArcsThroughEveryTornadoOutOfTheLavaAndBackAlternatingSides() {
        var match = elements()
        let centres = match.stage.tornados.map(\.center)
        for pass in 0..<2 {
            var path: [Vec2] = []
            for time in 0..<StageFireballRules.travelFrames {
                match.frame = pass * StageFireballRules.everyFrames + time
                path.append(match.stageFireball!.position)
            }
            match.frame = pass * StageFireballRules.everyFrames + StageFireballRules.travelFrames
            XCTAssertNil(match.stageFireball, "back under")
            XCTAssertLessThan(path.first!.y, ElementsRules.lavaSurface)
            XCTAssertLessThan(path.last!.y, ElementsRules.lavaSurface)
            XCTAssertEqual(path.last!.x > path.first!.x, pass == 0, "left to right, then back")
            for centre in centres {
                XCTAssertLessThan(path.map { $0.distance(to: centre) }.min()!, 4, "through the tornado at \(centre)")
            }
        }
    }

    private func fireballMeets(_ power: Power) -> Match {
        var match = elements()
        match.frame = 40
        let at = match.stageFireball!.position
        match.frame = 39
        match.players[0].position = Vec2(x: at.x, y: at.y - 8)
        match.players[0].power = power
        match.players[0].grounded = false
        match.players[0].tornadoCooldown = 999
        match.players[0].enter(.air)
        match.players[1].position = Vec2(x: 30, y: 400)
        match.advance(inputs: [.idle, .idle])
        return match
    }

    func testTheFireballStripsWhoeverItTouchesAndBurstsButBlazingBobaIsOnlyBurstOn() {
        let hit = fireballMeets(.none)
        XCTAssertTrue(hit.events.contains { if case .stageFireballBurst = $0 { return true }; return false })
        XCTAssertGreaterThan(hit.players[0].hitStun, 0, "stripped")
        XCTAssertNil(hit.stageFireball, "gone for the pass")
        let boba = fireballMeets(.blazingBoba)
        XCTAssertTrue(boba.events.contains { if case .stageFireballBurst = $0 { return true }; return false })
        XCTAssertEqual(boba.players[0].hitStun, 0)
    }

    func testBlazingBobaHangsInAFireTornado() {
        var match = elements()
        let tornado = match.stage.tornados[0]
        match.frame = 3 * TornadoRules.cycleFrames
        match.players[0].power = .blazingBoba
        match.players[0].position = Vec2(x: tornado.center.x, y: tornado.center.y - 8)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .suspended)
    }

    func testFallingInTheLavaSplashesForABodyAndTheBall() {
        var match = elements()
        match.players[0].position = Vec2(x: 300, y: ElementsRules.lavaSurface - 1)
        match.players[1].position = Vec2(x: 30, y: 400)
        match.ball.respawn(at: Vec2(x: 350, y: ElementsRules.lavaSurface - 1))
        match.advance(inputs: [.idle, .idle])
        XCTAssertTrue(match.events.contains(.lavaSplashed(at: Vec2(x: 300, y: ElementsRules.lavaSurface), ball: false)))
        XCTAssertTrue(match.events.contains { if case .lavaSplashed(_, true) = $0 { return true }; return false })
    }
}
