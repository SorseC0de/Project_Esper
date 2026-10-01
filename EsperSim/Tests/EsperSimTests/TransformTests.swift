import XCTest
@testable import EsperSim

/// The change into the energy form: throw and shoot together, the sheet played through held
/// still, and the same again to change back.
final class TransformTests: XCTestCase {
    private func standing() -> Match {
        var match = Match()
        match.countdown = 0
        match.players[0].position = Vec2(x: 100, y: 10)
        match.players[0].grounded = true
        return match
    }

    private let both = PlayerInput(shoot: true, throwBall: true)

    func testThrowAndShootTogetherChangeIntoTheEnergyFormHeldStill() {
        var match = standing()
        XCTAssertTrue(match.players[0].transformReady)
        match.advance(inputs: [both, .idle])
        XCTAssertEqual(match.players[0].state, .transforming)
        let at = match.players[0].position
        for _ in 0..<(TransformRules.frames - 1) {
            match.advance(inputs: [both, .idle])
            XCTAssertEqual(match.players[0].position, at, "held still")
        }
        match.advance(inputs: [.idle, .idle])
        XCTAssertTrue(match.players[0].transformed)
        XCTAssertNotEqual(match.players[0].state, .transforming)
    }

    func testTheSecondInAStanceJustTakenStillChanges() {
        var match = standing()
        match.players[0].hasBall = true
        match.ball.holder = 0
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .shootStance)
        match.advance(inputs: [both, .idle])
        XCTAssertEqual(match.players[0].state, .transforming)
    }

    func testTheSameAgainChangesStraightBack() {
        var match = standing()
        match.players[0].transformed = true
        match.advance(inputs: [both, .idle])
        XCTAssertFalse(match.players[0].transformed)
        XCTAssertNotEqual(match.players[0].state, .shootStance, "the press is spent on the change")
    }

    func testTheTransformSheetPlaysAtTenASecond() {
        var match = standing()
        match.advance(inputs: [both, .idle])
        XCTAssertEqual(match.players[0].animationFrame, AnimationFrame(.transform, 0))
        for _ in 0..<30 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].animationFrame, AnimationFrame(.transform, 5))
    }

    func testThePressesAFrameApartStillChangeBothWays() {
        var match = standing()
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .slashing)
        match.advance(inputs: [both, .idle])
        XCTAssertEqual(match.players[0].state, .transforming, "the slash just started gives way")
        for _ in 0..<TransformRules.frames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].transformed)
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        match.advance(inputs: [both, .idle])
        XCTAssertFalse(match.players[0].transformed, "back, the snatch just started given way")
    }
}
