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
        match.players[0].flo = FloRules.full
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

    func testTheSnatchInFloStateStepsThroughTheOtherAndTakesTheBall() {
        var match = standing()
        match.players[0].inFloState = true
        // The other right ahead with the ball, facing away.
        match.players[1].position = Vec2(x: 112, y: 10)
        match.players[1].grounded = true
        match.players[1].hasBall = true
        match.ball.holder = 1
        let from = match.players[0].position.x
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        // The snatch's frames, and the hit-stop the taking holds the match for.
        for _ in 0..<(SnatchRules.frames + HitStopRules.hitFrames + 2) { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].position.x - from, SnatchRules.floStateTravel, accuracy: 1, "carried 96 art pixels forward")
        XCTAssertEqual(SnatchRules.floStateTravel, 96 * 0.625, accuracy: 1e-9)
        XCTAssertEqual(match.ball.holder, 0, "the ball taken on the way through")
        XCTAssertGreaterThan(match.players[0].position.x, match.players[1].position.x, "and past the other")
    }

    func testTheSnatchInFloStateTakesWhatItSlidesPastLateInItsTravel() {
        // Too far for the hand's reach at full stretch, but on the body's way: a holder, and a loose ball.
        for loose in [false, true] {
            var match = standing()
            match.players[0].inFloState = true
            match.players[1].position = Vec2(x: 150, y: 10)
            match.players[1].grounded = true
            if loose {
                match.ball.respawn(at: Vec2(x: 150, y: 10 + BallRules.radius))
                match.ball.velocity = .zero
                match.players[1].position = Vec2(x: 40, y: 10)
            } else {
                match.players[1].hasBall = true
                match.ball.holder = 1
            }
            match.advance(inputs: [PlayerInput(throwBall: true), .idle])
            for _ in 0..<(SnatchRules.frames + HitStopRules.hitFrames + 2) { match.advance(inputs: [.idle, .idle]) }
            XCTAssertEqual(match.ball.holder, 0, loose ? "the loose ball taken on the way" : "the holder's ball taken on the way")
        }
    }

    func testTheSlashAndTheSnatchKeepTheirSpeedInTheAirAsOnTheGround() {
        for press in [PlayerInput(shoot: true), PlayerInput(throwBall: true)] {
            var travelled: [Double] = []
            for aloft in [false, true] {
                var match = Match(stage: .court, specs: [.starting, .starting])
                match.countdown = 0
                match.ball.respawn(at: Vec2(x: 300, y: 100))
                match.players[0].position = Vec2(x: 100, y: aloft ? 90 : 10)
                match.players[0].grounded = !aloft
                match.players[0].enter(aloft ? .air : .run)
                match.players[0].velocity = Vec2(x: 2.7, y: 0)
                let from = match.players[0].position.x
                match.advance(inputs: [press, .idle])
                for _ in 0..<12 { match.advance(inputs: [.idle, .idle]) }
                travelled.append(match.players[0].position.x - from)
            }
            XCTAssertGreaterThan(travelled[1], 20, "carried on in the air")
            XCTAssertEqual(travelled[1], travelled[0], accuracy: 1, "as far as on the ground")
        }
    }

    func testTheSnatchInFloStateIsDrawnFromItsOwnSheet() {
        var match = standing()
        match.players[0].inFloState = true
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertEqual(match.players[0].state, .snatching)
        XCTAssertEqual(match.players[0].animationFrame.animation, .snatchFloState)
        // Its seven frames under the snatch's timing: never past the last.
        for _ in 0..<SnatchRules.frames {
            XCTAssertLessThan(match.players[0].animationFrame.frame, Animation.snatchFloState.frameCount)
            match.advance(inputs: [.idle, .idle])
        }
        var human = standing()
        human.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertEqual(human.players[0].animationFrame.animation, .snatch)
    }

    func testTheChangesBurstPushesTheOtherAndTheBallAway() {
        var match = standing()
        match.players[1].position = Vec2(x: 120, y: 10)
        match.players[1].grounded = true
        match.ball.respawn(at: Vec2(x: 85, y: 14))
        match.advance(inputs: [both, .idle])
        for _ in 0..<(TransformRules.burstFrame + 2) { match.advance(inputs: [both, .idle]) }
        XCTAssertGreaterThan(match.players[1].position.x, 120, "pushed away")
        XCTAssertEqual(match.players[1].hitStun, 0, "not stunned")
        XCTAssertLessThan(match.ball.position.x, 85, "the ball sent away too")
    }

    func testTheChangeParriesABladeFromItsFirstFrameToItsBurst() {
        for at in [0, TransformRules.burstFrame] {
            var match = standing()
            match.players[1].position = Vec2(x: 115, y: 10)
            match.players[1].grounded = true
            match.players[1].facing = .left
            match.advance(inputs: [both, .idle])
            var parried = false
            for _ in 0..<(TransformRules.burstFrame + 2) {
                // The other's blade live, on the body, at that frame of the change.
                if match.players[0].state == .transforming, match.players[0].stateTimer == max(at - 1, 0), !parried,
                   match.players[1].state != .slashing {
                    match.players[1].enter(.slashing)
                    match.players[1].stateTimer = SlashRules.liveFrames.lowerBound
                }
                match.advance(inputs: [both, .idle])
                if match.events.contains(.parried(player: 1, by: 0)) { parried = true }
            }
            XCTAssertTrue(parried, "at frame \(at)")
            XCTAssertGreaterThan(match.players[1].hitStun, 0, "the slasher stripped, as a parry strips")
            XCTAssertTrue(match.players[0].inFloState || match.players[0].state == .transforming, "the change went on")
        }
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

    func testShortOfFullNoChange() {
        var match = standing()
        match.players[0].flo = FloRules.full - 1
        match.advance(inputs: [both, .idle])
        XCTAssertNotEqual(match.players[0].state, .transforming)
    }

    func testLeavingLocksItOutForASecond() {
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

    func testAFloEveryThreeTenthsOfASecondAndAFullMeterLastsHalfAMinute() {
        var match = standing()
        match.players[0].inFloState = true
        for _ in 0..<FloStateRules.spendFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].flo, FloRules.full - 1, "standing still spends too")
        match.players[0].flo = FloRules.full
        for _ in 0..<(30 * 60 - 1) { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].inFloState)
        match.advance(inputs: [.idle, .idle])
        XCTAssertFalse(match.players[0].inFloState, "out at half a minute")
        XCTAssertGreaterThan(match.players[0].floStateLockout, 0)
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
