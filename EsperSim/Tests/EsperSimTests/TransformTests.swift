import XCTest
@testable import EsperSim

/// FloState, the change into the energy form: throw and shoot together, the sheet played through
/// held still, and the same again to change back; FLO spent a step, and the lockout after.
final class TransformTests: XCTestCase {
    private func standing() -> Match {
        var match = Match()
        match.countdown = 0
        match.players[0].position = Vec2(x: 100, y: 10)
        match.players[0].grounded = true
        match.players[0].flo = 50
        return match
    }

    private let both = PlayerInput(shoot: true, throwBall: true)

    func testThrowAndShootTogetherChangeIntoTheEnergyFormHeldStill() {
        var match = standing()
        match.advance(inputs: [both, .idle])
        XCTAssertEqual(match.players[0].state, .transforming)
        let at = match.players[0].position
        for _ in 0..<(TransformRules.frames - 1) {
            match.advance(inputs: [both, .idle])
            XCTAssertEqual(match.players[0].position, at, "held still")
        }
        match.advance(inputs: [.idle, .idle])
        XCTAssertTrue(match.players[0].inFloState)
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
        match.players[0].inFloState = true
        match.advance(inputs: [both, .idle])
        XCTAssertFalse(match.players[0].inFloState)
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
        XCTAssertTrue(match.players[0].inFloState)
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        match.advance(inputs: [both, .idle])
        XCTAssertFalse(match.players[0].inFloState, "back, the snatch just started given way")
    }

    func testNoFloNoChange() {
        var match = standing()
        match.players[0].flo = 0
        match.advance(inputs: [both, .idle])
        XCTAssertNotEqual(match.players[0].state, .transforming)
    }

    func testLeavingLocksItOutForTenSeconds() {
        var match = standing()
        match.players[0].inFloState = true
        match.advance(inputs: [both, .idle])
        XCTAssertFalse(match.players[0].inFloState)
        XCTAssertFalse(match.players[0].floStateReady)
        match.advance(inputs: [.idle, .idle])
        match.advance(inputs: [both, .idle])
        XCTAssertNotEqual(match.players[0].state, .transforming, "locked out")
        for _ in 0..<FloStateRules.lockoutFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].floStateReady)
    }

    func testStandingStillSpendsNothingAndRunningSpendsAStep() {
        var match = standing()
        match.players[0].inFloState = true
        for _ in 0..<120 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].flo, 50, "still, nothing spent")
        let from = match.players[0].position.x
        for _ in 0..<60 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle]) }
        let travelled = match.players[0].position.x - from
        XCTAssertEqual(50 - match.players[0].flo, Int(travelled / FloStateRules.stepLength), "a FLO a step")
    }

    func testRunningOutLeavesIt() {
        var match = standing()
        match.players[0].inFloState = true
        match.players[0].flo = 1
        for _ in 0..<60 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle]) }
        XCTAssertFalse(match.players[0].inFloState)
        XCTAssertEqual(match.players[0].floStateLockout > 0, true)
    }

    func testItRunsATenthFaster() {
        var plain = standing(), flo = standing()
        flo.players[0].inFloState = true
        flo.players[0].flo = 100
        for _ in 0..<60 {
            plain.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle])
            flo.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle])
        }
        XCTAssertEqual(flo.players[0].velocity.x, plain.players[0].velocity.x * FloStateRules.speedShare, accuracy: 0.001)
    }
}
