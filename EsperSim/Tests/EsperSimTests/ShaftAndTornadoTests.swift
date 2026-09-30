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

    func testATornadoSinksIntoTheLavaAndComesBack() {
        let match = elements()
        var sunk = match
        sunk.frame = TornadoRules.upFrames + TornadoRules.sinkFrames + 1
        XCTAssertLessThan(sunk.tornadoBoxes[0].max.y, ElementsRules.lavaSurface)
        var back = match
        back.frame = TornadoRules.cycleFrames
        XCTAssertEqual(back.tornadoBoxes, match.stage.tornados)
    }
}
