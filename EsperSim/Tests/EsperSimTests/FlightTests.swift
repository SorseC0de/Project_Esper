import XCTest
@testable import EsperSim

/// Flight: the aisle of a plane at its art's size, its pitch leaning gravity, and its cart.
final class FlightTests: XCTestCase {
    private func flight(seed: UInt32 = 1) -> Match {
        var match = Match(stage: .flight, seed: seed)
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

    func testFlightIsOnTheSelectAtItsArtsSize() {
        XCTAssertTrue(StageChoice.selectable.contains(.flight))
        let stage = StageChoice.flight.stage
        XCTAssertEqual(stage.features.look, .flight)
        XCTAssertTrue(stage.features.tilts)
        // 1248 by 576 in the file, four of its pixels an art pixel: 312 by 144, 19 and a half tiles by 9.
        XCTAssertEqual(stage.width, 312 * 0.625, accuracy: 1e-9)
        XCTAssertEqual(stage.height, 144 * 0.625, accuracy: 1e-9)
        XCTAssertEqual(stage.rows, 9)
        XCTAssertEqual(stage.hoops.count, 2)
        XCTAssertEqual(stage.ballSpawn.x, stage.width / 2, "the ball over the middle")
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
        XCTAssertLessThanOrEqual(match.players[1].body.max.x, FlightRules.width + 1e-6)
        XCTAssertGreaterThan(match.players[1].body.max.x, FlightRules.width - 2)
    }

    func testThePitchLeansNowAndThenWithinItsMostAndComesBackLevelBetween() {
        var match = flight(seed: 7)
        var leaned = false
        var most = 0.0
        var levelAfterLeaning = 0
        for _ in 0..<(FlightRules.tiltEveryFrames * 4) {
            match.advance(inputs: [.idle, .idle])
            most = max(most, abs(match.stage.tilt))
            if abs(match.stage.tilt) > 0.05 { leaned = true }
            if leaned, match.stage.tilt == 0 { levelAfterLeaning += 1 }
        }
        XCTAssertTrue(leaned, "it leaned at some point")
        XCTAssertLessThanOrEqual(most, FlightRules.tiltMax + 1e-9)
        XCTAssertGreaterThanOrEqual(levelAfterLeaning, FlightRules.levelFrames, "and was level a while between leans")
    }

    func testALeanPullsTheBallAndAJumperSideways() {
        // A loose ball on the floor rolls down the lean: nose up, the left side down.
        var stage = Stage.flight
        stage.tilt = FlightRules.tiltMax / 2
        var ball = Ball(position: Vec2(x: 100, y: 20 + BallRules.radius))
        var events: [MatchEvent] = []
        for _ in 0..<120 { _ = ball.step(stage: stage, events: &events) }
        XCTAssertLessThan(ball.position.x, 90, "rolled left")
        // A jump straight up drifts down the lean too.
        var match = flight()
        match.cart = nil
        hold(&match, at: FlightRules.tiltMax / 2)
        let from = match.players[1].position.x
        match.advance(inputs: [.idle, PlayerInput(jump: true)])
        for _ in 0..<20 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertFalse(match.players[1].grounded, "still up")
        XCTAssertLessThan(match.players[1].position.x, from - 1, "carried left")
    }

    func testASteepPitchMakesTheFloorASlide() {
        var match = flight()
        match.cart = nil
        hold(&match, at: FlightRules.slideTilt)
        for _ in 0..<30 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[1].state, .slide)
        XCTAssertTrue(match.players[1].forcedSlide)
        XCTAssertEqual(match.players[1].facing, .left, "down the lean")
        // Short of it, they stand.
        var level = flight()
        level.cart = nil
        hold(&level, at: FlightRules.slideTilt * 0.9)
        for _ in 0..<30 { level.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(level.players[1].state, .idle)
    }

    func testTheCartRollsDownTheLeanIntoABodyAndPopsTheBall() {
        var match = flight()
        hold(&match, at: FlightRules.tiltMax / 2)
        match.ball.holder = 0
        match.players[0].hasBall = true
        let cartStart = match.cart?.box.min.x ?? 0
        var hit = false
        var popped = false
        for _ in 0..<FlightRules.tiltEveryFrames - 2 {
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
        hold(&match, at: FlightRules.tiltMax / 2)
        for _ in 0..<120 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertLessThan(match.cart?.box.min.x ?? 0, cart.box.min.x, "the cart rolled left")
        XCTAssertLessThan(match.players[1].position.x, before - 5, "carried along on it")
    }
}
