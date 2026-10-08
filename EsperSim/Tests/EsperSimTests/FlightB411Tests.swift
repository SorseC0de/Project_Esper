import XCTest
@testable import EsperSim

/// Flight B411: the aisle of a plane at its art's size, its pitch leaning gravity, and its cart.
final class FlightB411Tests: XCTestCase {
    private func flight(seed: UInt32 = 1) -> Match {
        var match = Match(stage: .flightB411, seed: seed)
        match.countdown = 0
        return match
    }

    /// The pitch held at `tilt`: the lean it's going from and to both that, the clock just started.
    private func hold(_ match: inout Match, at tilt: Double) {
        match.tiltFrom = tilt
        match.tiltTarget = tilt
        match.tiltClock = 1
        match.stage.tilt = tilt
    }

    func testFlightB411IsOnTheSelectAtItsArtsSize() {
        XCTAssertTrue(StageChoice.selectable.contains(.flightB411))
        let stage = StageChoice.flightB411.stage
        XCTAssertEqual(stage.features.look, .flightB411)
        XCTAssertTrue(stage.features.tilts)
        // 1248 by 576 in the file, four of its pixels an art pixel: 312 by 144, 19 and a half tiles by 9.
        XCTAssertEqual(stage.width, 312 * 0.625, accuracy: 1e-9)
        XCTAssertEqual(stage.height, 144 * 0.625, accuracy: 1e-9)
        XCTAssertEqual(stage.rows, 9)
        XCTAssertEqual(stage.hoops.count, 2)
        XCTAssertEqual(stage.ballSpawn.x, stage.width / 2, "the ball over the middle")
        XCTAssertTrue(StageChoice.fortySeven.contains(.flightB411), "47 plays on it")
        XCTAssertFalse(ZonesRules.stages.contains(.flightB411), "ZONES doesn't")
        // No dunking on it, wherever a rim is.
        XCTAssertFalse(stage.features.dunks)
        XCTAssertFalse(stage.dunkable(stage.hoops[1]))
        XCTAssertFalse(stage.dunkable(Hoop(position: Vec2(x: stage.width / 2, y: 65), owner: 0, backboard: .right)))
        // The ceiling near the plane's: the tuned rows of sky over the art, then solid, whatever the lean.
        XCTAssertEqual(stage.skyRows, FlightB411Rules.skyRows)
        XCTAssertEqual(stage.tile(column: 5, row: stage.rows + stage.skyRows), .solid)
        XCTAssertEqual(stage.tile(column: 5, row: stage.rows), stage.skyRows == 0 ? .solid : .empty)
        var match = flight()
        match.cart = nil
        var highest = 0.0
        for frame in 0..<240 {
            hold(&match, at: frame < 120 ? 0 : FlightB411Rules.tiltMax)
            match.advance(inputs: [.idle, PlayerInput(jump: frame % 40 == 0)])
            highest = max(highest, match.players[1].body.max.y)
        }
        XCTAssertLessThanOrEqual(highest, stage.height + Double(stage.skyRows) * Stage.tileSize + 1e-6)
    }

    func testEveryoneStandsOnTheFloorAndTheWallIsWhereTheArtEnds() {
        var match = flight()
        match.cart = nil
        for _ in 0..<60 { hold(&match, at: 0); match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players.allSatisfy(\.grounded))
        XCTAssertEqual(match.players[0].position.y, 20, accuracy: 1e-9, "two rows of floor")
        XCTAssertEqual(match.players[0].spec.scale, FighterSpec.baseline.scale, "the bodies their own size")
        // Walked right for a long while, the second stops at the art's edge, not the grid's.
        for _ in 0..<600 { hold(&match, at: 0); match.advance(inputs: [.idle, PlayerInput(stick: Vec2(x: 1, y: 0))]) }
        XCTAssertLessThanOrEqual(match.players[1].body.max.x, FlightB411Rules.width + 1e-6)
        XCTAssertGreaterThan(match.players[1].body.max.x, FlightB411Rules.width - 2)
    }

    func testThePitchLeansNowAndThenWithinItsMostAndComesBackLevelBetween() {
        var match = flight(seed: 7)
        var leaned = false
        var most = 0.0
        var levelAfterLeaning = 0
        for _ in 0..<(FlightB411Rules.tiltEveryFrames * 4) {
            match.advance(inputs: [.idle, .idle])
            most = max(most, abs(match.stage.tilt))
            if abs(match.stage.tilt) > 0.05 { leaned = true }
            if leaned, match.stage.tilt == 0 { levelAfterLeaning += 1 }
        }
        XCTAssertTrue(leaned, "it leaned at some point")
        XCTAssertLessThanOrEqual(most, FlightB411Rules.tiltMax + 1e-9)
        XCTAssertGreaterThanOrEqual(levelAfterLeaning, FlightB411Rules.levelFrames, "and was level a while between leans")
    }

    func testALeanPullsTheBallAndAJumperSideways() {
        // A loose ball on the floor rolls down the lean: nose up, the left side down.
        var stage = Stage.flightB411
        stage.tilt = FlightB411Rules.tiltMax / 2
        var ball = Ball(position: Vec2(x: 100, y: 20 + BallRules.radius))
        var events: [MatchEvent] = []
        for _ in 0..<120 { _ = ball.step(stage: stage, events: &events) }
        XCTAssertLessThan(ball.position.x, 90, "rolled left")
        // A jump straight up drifts down the lean too.
        var match = flight()
        match.cart = nil
        hold(&match, at: FlightB411Rules.tiltMax / 2)
        let from = match.players[1].position.x
        match.advance(inputs: [.idle, PlayerInput(jump: true)])
        for _ in 0..<20 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertFalse(match.players[1].grounded, "still up")
        XCTAssertLessThan(match.players[1].position.x, from - 1, "carried left")
    }

    func testASteepPitchMakesTheFloorASlide() {
        var match = flight()
        match.cart = nil
        hold(&match, at: FlightB411Rules.slideTilt)
        for _ in 0..<30 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[1].state, .slide)
        XCTAssertTrue(match.players[1].forcedSlide)
        XCTAssertEqual(match.players[1].facing, .left, "down the lean")
        // Short of it, they stand.
        var level = flight()
        level.cart = nil
        hold(&level, at: FlightB411Rules.slideTilt * 0.9)
        for _ in 0..<30 { level.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(level.players[1].state, .idle)
    }

    func testTheCartRollsDownTheLeanIntoABodyAndPopsTheBall() {
        var match = flight()
        hold(&match, at: FlightB411Rules.tiltMax / 2)
        match.ball.holder = 0
        match.players[0].hasBall = true
        let cartStart = match.cart?.box.min.x ?? 0
        var hit = false
        var popped = false
        for _ in 0..<FlightB411Rules.tiltEveryFrames - 2 {
            match.advance(inputs: [.idle, .idle])
            if match.events.contains(where: { if case .cartHit(player: 0, _) = $0 { return true } else { return false } }) {
                hit = true
                popped = match.ball.holder == nil
                break
            }
        }
        XCTAssertTrue(hit, "the cart reached the first body")
        XCTAssertTrue(popped, "and the ball left their hands")
        XCTAssertLessThan(match.cart?.box.min.x ?? 0, cartStart, "rolled left, down the lean")
        XCTAssertLessThan(match.players[0].velocity.x, 0, "knocked its way")
        XCTAssertLessThan(match.cart?.rolled ?? 0, 0, "and its wheels turned that way")
    }

    func testEveryoneIsHalfAsFastOnItInFlightToo() {
        var match = flight()
        match.cart = nil
        var level = Match(stage: .court)
        level.countdown = 0
        for _ in 0..<60 {
            hold(&match, at: 0)
            match.advance(inputs: [.idle, PlayerInput(stick: Vec2(x: 1, y: 0))])
            level.advance(inputs: [.idle, PlayerInput(stick: Vec2(x: 1, y: 0))])
        }
        XCTAssertEqual(match.players[1].runSpeed, level.players[1].runSpeed / 2, accuracy: 1e-9)
        XCTAssertEqual(match.players[1].airSpeedMax, level.players[1].airSpeedMax / 2, accuracy: 1e-9)
        // Super Smoothie's flight at half too, and level: the lean doesn't pull it.
        var flier = flight()
        flier.cart = nil
        hold(&flier, at: FlightB411Rules.tiltMax / 2)
        flier.players[1].power = .superSmoothie
        flier.players[1].position = Vec2(x: 150, y: 30)
        flier.players[1].grounded = false
        flier.players[1].state = .flying
        flier.players[1].flightLeft = 600
        for _ in 0..<20 { flier.advance(inputs: [.idle, PlayerInput(stick: Vec2(x: 0, y: 1), jump: true)]) }
        XCTAssertEqual(flier.players[1].state, .flying)
        XCTAssertEqual(flier.players[1].velocity.x, 0, accuracy: 1e-9, "straight up, the lean leaving it alone")
        XCTAssertEqual(flier.players[1].velocity.y, SmoothieRules.flightSpeed(level: 1, withBall: false) / 2, accuracy: 1e-9)
    }

    func testTheCartIsStoodOnAndRidden() {
        var match = flight()
        hold(&match, at: 0)
        // The second dropped onto the cart's top, level.
        guard let cart = match.cart else { return XCTFail("no cart") }
        match.players[1].position = Vec2(x: cart.box.center.x, y: cart.box.max.y + 1)
        match.players[1].velocity = .zero
        for _ in 0..<30 { hold(&match, at: 0); match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[1].grounded)
        XCTAssertEqual(match.players[1].position.y, cart.box.max.y, accuracy: 1e-6, "standing on the cart")
        // The plane leans: the cart rolls, and they go with it.
        let before = match.players[1].position.x
        hold(&match, at: FlightB411Rules.tiltMax / 2)
        for _ in 0..<120 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertLessThan(match.cart?.box.min.x ?? 0, cart.box.min.x, "the cart rolled left")
        XCTAssertLessThan(match.players[1].position.x, before - 5, "carried along on it")
    }
}
