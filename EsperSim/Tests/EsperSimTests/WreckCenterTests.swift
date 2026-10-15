import XCTest
@testable import EsperSim

/// The Wreck Center's belts carry as fast as they're drawn, and its platforms turn once when dropped through.
final class WreckCenterTests: XCTestCase {
    private func court() -> Match {
        StageMap.current[.wreckCenter] = StageMap.baked(.wreckCenter)
        var match = Match(stage: .court, specs: [.starting, .starting])
        match.countdown = 0
        match.ball.holder = nil
        match.players.indices.forEach { match.players[$0].hasBall = false }
        match.players[1].position = Vec2(x: 250, y: 10)
        return match
    }

    private func onLeftBelt(_ match: inout Match, x: Double) {
        match.players[0].position = Vec2(x: x, y: 140)
        match.players[0].velocity = .zero
        for _ in 0..<5 { match.advance(inputs: [.idle, .idle]) }
    }

    func testTheCourtHasItsBeltsAndPlatforms() {
        let match = court()
        XCTAssertEqual(match.stage.conveyors.count, 4)
        XCTAssertEqual(match.stage.dropPlatforms.count, 2)
        XCTAssertEqual(match.stage.conveyors.filter { $0.box.max.x <= 50 }.map(\.way), [1, 1])
        XCTAssertEqual(match.stage.conveyors.filter { $0.box.min.x >= 290 }.map(\.way), [-1, -1])
    }

    func testStandingOnTheLeftBeltIsCarriedRight() {
        var match = court()
        onLeftBelt(&match, x: 20)
        let start = match.players[0].position.x
        for _ in 0..<5 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertGreaterThan(match.players[0].position.x, start)
    }

    func testTheBeltCarriesAsFastAsItsArtMoves() {
        var match = court()
        onLeftBelt(&match, x: 20)
        let start = match.players[0].position.x
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].position.x - start, WreckCenterRules.beltSpeed * 60, accuracy: 0.01)
    }

    func testThePlatformsThreePointLineHoldsWhileItTurns() {
        var match = court()
        let before = match.stage.hoops.map { FortySevenRules.threePointRadius(for: $0, on: match.stage) }
        match.stage.fill(.empty, columns: 15...16, rows: 3...3)
        XCTAssertEqual(match.stage.hoops.map { FortySevenRules.threePointRadius(for: $0, on: match.stage) }, before)
    }

    func testABallOnTheBeltDropsIntoTheRimBelow() {
        var match = court()
        match.players[0].position = Vec2(x: 120, y: 10)
        match.ball.respawn(at: Vec2(x: 20, y: 140 + BallRules.radius))
        match.ball.position = Vec2(x: 20, y: 140 + BallRules.radius)
        match.ball.velocity = .zero
        for _ in 0..<600 where match.scores == [0, 0] { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.scores, [0, 1], "the left rim scores for the second side")
    }

    func testDroppingThroughTurnsThatPlatformAndItHoldsNobodyTillDone() {
        var match = court()
        match.players[0].position = Vec2(x: 160, y: 40)
        match.players[1].position = Vec2(x: 182, y: 40)
        for _ in 0..<5 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].grounded)
        let down = PlayerInput(stick: Vec2(x: 0, y: -1))
        for _ in 0..<(DropRules.holdFrames + 2) { match.advance(inputs: [down, .idle]) }
        XCTAssertGreaterThan(match.dropPlatformFrames[0], 0, "the one dropped through turns")
        XCTAssertEqual(match.dropPlatformFrames[1], 0, "the other stays still")
        XCTAssertTrue(match.players[1].grounded, "still standing on the other")
        for _ in 0..<(WreckCenterRules.platformFrames + 2) { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.dropPlatformFrames[0], 0)
        XCTAssertEqual(match.stage.tile(column: 15, row: 3), .oneWay, "standable again")
    }
}
