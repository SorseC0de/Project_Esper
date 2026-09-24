import XCTest
@testable import EsperSim

/// The newer powers, and the strip they share.
final class PowerTests: XCTestCase {
    private func with(_ power: Power, level: Int = 1, other: Power = .none) -> Match {
        var match = Match()
        match.players[0].power = power
        match.players[0].powerLevel = level
        match.players[1].power = other
        match.ball.respawn(at: Vec2(x: 300, y: 30))
        return match
    }

    @discardableResult
    private func run(_ match: inout Match, frames: Int, input: (Int) -> PlayerInput, other: PlayerInput = .idle, until stop: ((Match) -> Bool)? = nil) -> Int {
        for frame in 0..<frames {
            match.advance(inputs: [input(frame), other])
            if let stop, stop(match) { return frame }
        }
        return frames
    }

    // MARK: Slash and snatch

    func testSlashStripsAndKnocksABodyWithoutTheBall() {
        var match = with(.none)
        match.players[1].position.x = match.players[0].position.x + 14
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        let hit = run(&match, frames: SlashRules.frames, input: { _ in .idle }) { $0.events.contains(.struck(player: 1, by: 0)) }
        XCTAssertLessThan(hit, SlashRules.frames)
        XCTAssertEqual(match.players[1].hitStun, BallRules.hitStunFrames)
        XCTAssertGreaterThan(match.players[1].velocity.x, 0, "knocked the way of the swing")
        XCTAssertEqual(match.players[1].state, .air)
    }

    func testSnatchParriesALiveBlade() {
        var match = with(.none)
        match.players[1].position.x = match.players[0].position.x + 12
        match.players[1].facing = .left
        // The hand is out first; the other's blade comes live into it.
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        run(&match, frames: 6, input: { _ in .idle })
        match.advance(inputs: [.idle, PlayerInput(shoot: true)])
        let parried = run(&match, frames: 20, input: { _ in .idle }) { $0.events.contains(.parried(player: 1, by: 0)) }
        XCTAssertLessThan(parried, 20)
        XCTAssertGreaterThan(match.players[1].hitStun, 0, "the slasher is the one stripped")
        XCTAssertEqual(match.players[0].hitStun, 0)
    }

    func testJumpAndShootTogetherIsARisingSlash() {
        var match = with(.none)
        match.advance(inputs: [PlayerInput(jump: true, shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .jumpSquat)
        let out = run(&match, frames: 6, input: { _ in PlayerInput(jump: true) }) { $0.players[0].state == .slashing }
        XCTAssertLessThan(out, 6, "straight out of the squat into the slash")
        XCTAssertTrue(match.events.contains(.jumped(player: 0)))
        XCTAssertGreaterThan(match.players[0].velocity.y, 3, "with the jump's ascent")
        // Throw pressed during the squat is the snatch.
        var snatch = with(.none)
        snatch.advance(inputs: [PlayerInput(jump: true), .idle])
        snatch.advance(inputs: [PlayerInput(jump: true, throwBall: true), .idle])
        let hand = run(&snatch, frames: 6, input: { _ in PlayerInput(jump: true) }) { $0.players[0].state == .snatching }
        XCTAssertLessThan(hand, 6)
        XCTAssertFalse(snatch.players[0].grounded)
    }

    // MARK: Quake-Up Coffee

    func testQuakeStripsWhoeverStandsOnTheFloorAndHopsTheBall() {
        var match = with(.quakeUp)
        match.players[1].position.x = 250
        match.players[1].hasBall = true
        match.ball.holder = 1
        // A full hop, then down for the fast fall.
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 12, input: { _ in .idle })
        let quaked = run(&match, frames: 90, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) }) { $0.events.contains(.quaked(player: 0)) }
        XCTAssertLessThan(quaked, 90)
        XCTAssertFalse(match.players[1].hasBall, "stripped across the floor")
        XCTAssertGreaterThan(match.players[1].hitStun, 0)
    }

    func testQuakeAtLevelOneLeavesAHigherFloorAlone() {
        var match = with(.quakeUp)
        match.players[1].position = Vec2(x: 250, y: 90)
        match.players[1].hasBall = true
        match.ball.holder = 1
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 12, input: { _ in .idle })
        run(&match, frames: 90, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) }) { $0.events.contains(.quaked(player: 0)) }
        XCTAssertTrue(match.players[1].hasBall || !match.players[1].grounded)
        var whole = with(.quakeUp, level: 2)
        whole.players[1].position = Vec2(x: 290, y: 90)
        whole.players[1].hasBall = true
        whole.ball.holder = 1
        run(&whole, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&whole, frames: 12, input: { _ in .idle })
        run(&whole, frames: 90, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) }) { $0.events.contains(.quaked(player: 0)) }
        XCTAssertFalse(whole.players[1].hasBall, "at level two the whole screen is the floor")
    }

    // MARK: Zeus Juice

    func testABoltStripsTheBodyItMeets() {
        var match = with(.zeusJuice)
        match.players[1].position.x = match.players[0].position.x + 40
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertTrue(match.events.contains(.boltFired(player: 0)))
        XCTAssertNotEqual(match.players[0].state, .slashing, "Zeus Juice's shoot is the bolt, not the slash")
        let hit = run(&match, frames: 30, input: { _ in .idle }) { $0.events.contains(.popped(player: 1, by: 0)) }
        XCTAssertLessThan(hit, 30)
        XCTAssertTrue(match.bolts.isEmpty)
    }

    func testABoltPopsTheBallBackTowardTheThrower() {
        var match = with(.zeusJuice)
        match.ball.respawn(at: Vec2(x: match.players[0].chest.x + 30, y: match.players[0].chest.y))
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        let hit = run(&match, frames: 30, input: { _ in .idle }) { $0.events.contains { if case .boltLanded = $0 { return true } else { return false } } }
        XCTAssertLessThan(hit, 30)
        XCTAssertLessThan(match.ball.velocity.x, 0, "back toward the thrower")
    }

    func testLevelTwoThrowStrikesDownOnTheSnatchAndTheBallInHand() {
        var match = with(.zeusJuice, level: 2)
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        let struck = run(&match, frames: 20, input: { _ in .idle }) { $0.events.contains { if case .boltStruck(player: 0, _, _) = $0 { return true } else { return false } } }
        XCTAssertLessThan(struck, 20)
        var held = with(.zeusJuice, level: 2)
        held.players[0].hasBall = true
        held.ball.holder = 0
        held.advance(inputs: [PlayerInput(throwBall: true), .idle])
        held.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertTrue(held.events.contains { if case .boltStruck(player: 0, _, _) = $0 { return true } else { return false } })
    }

    // MARK: Frost Tea

    func testFrostSnatchFreezesTheBodyItReaches() {
        var match = with(.frostTea)
        match.players[1].position.x = match.players[0].position.x + 12
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        let frozen = run(&match, frames: 20, input: { _ in .idle }) { $0.events.contains(.frozen(player: 1)) }
        XCTAssertLessThan(frozen, 20)
        XCTAssertEqual(match.players[1].frozen, FrostRules.freezeFrames)
        let where_ = match.players[1].position
        run(&match, frames: 30, input: { _ in .idle }, other: PlayerInput(stick: Vec2(x: 1, y: 0), jump: true))
        XCTAssertEqual(match.players[1].position, where_, "held exactly where it was, whatever the stick says")
        XCTAssertGreaterThan(match.players[1].frozen, 0)
    }

    func testFrostSnatchFreezesALooseBallInPlace() {
        var match = with(.frostTea)
        match.ball.respawn(at: match.players[0].handCatchPoint)
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        run(&match, frames: 20, input: { _ in .idle }) { $0.events.contains(.ballFrozen) }
        XCTAssertEqual(match.ball.frozen, FrostRules.freezeFrames - 1)
        XCTAssertNil(match.ball.holder)
        let spot = match.ball.position
        run(&match, frames: 30, input: { _ in .idle })
        XCTAssertEqual(match.ball.position, spot)
        // Frozen, it can still be picked up: the other walks into it.
        match.players[1].position = Vec2(x: spot.x - 2, y: spot.y - BallRules.chestHeight)
        match.players[1].facing = .right
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.ball.holder, 1)
        XCTAssertEqual(match.ball.frozen, 0)
    }

    func testFrostSlideRunsUntilCancelled() {
        var match = with(.frostTea)
        run(&match, frames: 20, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0.7, y: -0.7)), .idle])
        XCTAssertEqual(match.players[0].state, .slide)
        let speed = match.players[0].velocity.x
        run(&match, frames: 60, input: { _ in PlayerInput(stick: Vec2(x: 0, y: -1)) })
        XCTAssertTrue(match.players[0].state == .slide || match.players[0].velocity.x == 0, "still sliding, or stopped by the wall")
        if match.players[0].state == .slide { XCTAssertEqual(match.players[0].velocity.x, speed, accuracy: 0.001) }
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), jump: true), .idle])
        XCTAssertEqual(match.players[0].state, .jumpSquat, "jump cancels it")
    }

    func testLevelTwoDoubleJumpLeavesACloneThatFreezesOnTouch() {
        var match = with(.frostTea, level: 2)
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 8, input: { _ in .idle })
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        run(&match, frames: 2, input: { _ in .idle })
        XCTAssertEqual(match.clones.count, 1)
        let clone = match.clones[0]
        match.players[1].position = Vec2(x: clone.box.center.x, y: clone.box.min.y)
        match.advance(inputs: [.idle, .idle])
        XCTAssertTrue(match.events.contains(.frozen(player: 1)))
        XCTAssertTrue(match.clones.isEmpty, "shattered on touch")
    }

    // MARK: Blazing Boba

    func testAFullRunLeavesFlamesThatStripTheOther() {
        var match = with(.blazingBoba)
        match.players[1].position.x = 40
        run(&match, frames: 40, input: { _ in PlayerInput(stick: Vec2(x: 1, y: 0)) })
        XCTAssertFalse(match.flames.isEmpty)
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.players[1].position = Vec2(x: match.flames[0].box.center.x, y: match.flames[0].box.min.y)
        match.advance(inputs: [.idle, .idle])
        XCTAssertTrue(match.events.contains(.popped(player: 1, by: 0)))
    }

    func testABurningShotCannotBeCaughtByTheOther() {
        var match = with(.blazingBoba)
        match.players[0].hasBall = true
        match.ball.holder = 0
        for _ in 0..<BallRules.shotWindupFrames + 2 { match.advance(inputs: [PlayerInput(shoot: true), .idle]) }
        match.advance(inputs: [.idle, .idle])
        run(&match, frames: BallRules.shotReleaseFrames + 1, input: { _ in .idle })
        XCTAssertTrue(match.ball.burning)
        // The other, right where the ball is, slow ball: not caught while it burns.
        match.ball.velocity = Vec2(x: 0.5, y: 0)
        match.players[1].position = Vec2(x: match.ball.position.x, y: match.ball.position.y - BallRules.chestHeight)
        match.players[1].facing = .right
        match.advance(inputs: [.idle, .idle])
        XCTAssertNil(match.ball.holder)
    }

    func testLevelTwoShootAndThrowTogetherMakeAFireballThatBursts() {
        var match = with(.blazingBoba, level: 2)
        match.players[1].position.x = 60
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .slashing, "shoot alone is still the slash")
        var summon = with(.blazingBoba, level: 2)
        summon.players[1].position.x = 60
        summon.advance(inputs: [PlayerInput(shoot: true, throwBall: true), .idle])
        XCTAssertTrue(summon.players[0].hasFireball)
        XCTAssertTrue(summon.events.contains(.fireballMade(player: 0)))
        match = summon
        // Thrown: it flies dead straight and bursts on the wall.
        run(&match, frames: 2, input: { _ in .idle })
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        run(&match, frames: BallRules.throwWindupFrames + 2, input: { _ in PlayerInput(throwBall: true) })
        run(&match, frames: 3, input: { _ in .idle })
        let thrown = run(&match, frames: 10, input: { _ in .idle }) { !$0.fireballs.isEmpty }
        XCTAssertLessThan(thrown, 10)
        XCTAssertFalse(match.players[0].hasFireball)
        XCTAssertTrue(match.fireballs[0].straight)
        let height = match.fireballs[0].position.y
        run(&match, frames: 5, input: { _ in .idle })
        if let flying = match.fireballs.first { XCTAssertEqual(flying.position.y, height, accuracy: 0.001, "a thrown fireball flies level") }
        let burst = run(&match, frames: 120, input: { _ in .idle }) { $0.events.contains { if case .fireballBurst = $0 { return true } else { return false } } }
        XCTAssertLessThan(burst, 120)
    }

    // MARK: Pulsepistol Punch

    func testThePulseKnocksTheBallAndTheOtherAwayWithoutStunning() {
        var match = with(.pulsepistol)
        match.players[1].position.x = match.players[0].position.x + 80
        match.players[1].hasBall = true
        match.ball.holder = 1
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .gunShoot)
        let pulsed = run(&match, frames: PulseRules.shotFrames, input: { _ in .idle }) { $0.events.contains(.pulsed(player: 0, pull: false)) }
        XCTAssertLessThan(pulsed, PulseRules.shotFrames)
        XCTAssertFalse(match.players[1].hasBall, "popped free")
        XCTAssertEqual(match.players[1].hitStun, 0, "but not stunned")
        XCTAssertGreaterThan(match.players[1].velocity.x, 0)
    }

    func testLevelTwoThrowPullsTheBallIn() {
        var match = with(.pulsepistol, level: 2)
        match.ball.respawn(at: Vec2(x: match.players[0].position.x + 100, y: match.players[0].position.y + PulseRules.handHeight))
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        XCTAssertEqual(match.players[0].state, .gunShoot, "throw is the pull, not the snatch")
        run(&match, frames: PulseRules.shotFrames, input: { _ in .idle }) { $0.events.contains(.pulsed(player: 0, pull: true)) }
        XCTAssertLessThan(match.ball.velocity.x, 0, "toward the body")
    }

    // MARK: Super Smoothie

    func testLevelTwoFlightForwardIsTheGlideThatSinksUnlessUpIsHeld() {
        var match = with(.superSmoothie, level: 2)
        run(&match, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&match, frames: 6, input: { _ in .idle })
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        run(&match, frames: 2, input: { _ in PlayerInput(jump: true) })
        XCTAssertEqual(match.players[0].state, .flying)
        // Forward: fast, and sinking.
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), jump: true), .idle])
        XCTAssertEqual(match.players[0].velocity.x, SmoothieRules.glideSpeed(withBall: false), accuracy: 0.001)
        XCTAssertEqual(match.players[0].velocity.y, -SmoothieRules.glideSink, accuracy: 0.001)
        // Forward and up: rising at the flight speed.
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 1), jump: true), .idle])
        XCTAssertGreaterThan(match.players[0].velocity.y, 0)
        // Backward: the drift, at the flight speed.
        match.advance(inputs: [PlayerInput(stick: Vec2(x: -1, y: 0), jump: true), .idle])
        XCTAssertEqual(match.players[0].velocity.x, -SmoothieRules.flightSpeed(level: 2, withBall: false), accuracy: 0.001)
        XCTAssertEqual(match.players[0].velocity.y, 0, accuracy: 0.001)
        // Level one forward is plain flight, no sink.
        var one = with(.superSmoothie, level: 1)
        run(&one, frames: 6, input: { _ in PlayerInput(jump: true) })
        run(&one, frames: 6, input: { _ in .idle })
        one.advance(inputs: [PlayerInput(jump: true), .idle])
        run(&one, frames: 2, input: { _ in PlayerInput(jump: true) })
        one.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), jump: true), .idle])
        XCTAssertEqual(one.players[0].velocity.y, 0, accuracy: 0.001)
    }
}
