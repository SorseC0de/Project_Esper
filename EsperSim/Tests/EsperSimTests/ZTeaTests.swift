import XCTest
@testable import EsperSim

/// Z Tea: on the ground the slash charges and fires a beam; in the air, the burst.
final class ZTeaTests: XCTestCase {
    private func court(level: Int) -> Match {
        var match = Match(stage: .court, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].power = .zTea
        match.players[0].powerLevel = level
        match.players[0].position = Vec2(x: 80, y: 10)
        match.players[0].facing = .right
        match.players[1].position = Vec2(x: 250, y: 10)
        match.players[1].hasBall = true
        match.ball.holder = 1
        return match
    }

    func testTheChargedBeamStripsAndKnocksAlongItAndSendsTheBall() {
        var match = court(level: 1)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .beamCharging)
        var fired = false, struck = false
        for _ in 0..<(ZRules.chargeFrames + ZRules.fireFrames) {
            match.advance(inputs: [.idle, .idle])
            if match.events.contains(where: { if case .beamFired = $0 { return true } else { return false } }) { fired = true }
            if match.players[1].hitStun > 0 { struck = true }
        }
        XCTAssertTrue(fired)
        XCTAssertTrue(struck)
        XCTAssertFalse(match.players[1].hasBall)
        XCTAssertNotEqual(match.ball.holder, 1)
        XCTAssertGreaterThan(match.players[1].position.x, 250, "knocked along the beam")
    }

    func testTheStickTurnsItWhileFiringToAnyAngleWithin45Degrees() {
        var match = court(level: 1)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        for _ in 0..<5 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1)), .idle]) }
        XCTAssertEqual(match.players[0].beamAim, ZRules.aimRate * 5, accuracy: 1e-9, "a little way up, not snapped")
        for _ in 0..<ZRules.chargeFrames { match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1)), .idle]) }
        XCTAssertEqual(match.players[0].beamAim, ZRules.aimRange, accuracy: 1e-9)
        XCTAssertTrue(match.players[0].firingBeam)
        for _ in 0..<5 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1)), .idle]) }
        XCTAssertEqual(match.players[0].beamAim, ZRules.aimRange - ZRules.aimRate * 5, accuracy: 1e-9, "turned while it fires")
        XCTAssertEqual(match.beams.first?.direction ?? .zero, match.players[0].beamDirection)
    }

    func testTheBeamFiresThreeSecondsAtMostFreeAndHitsAgain() {
        var match = court(level: 1)
        match.players[0].flo = 10
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.ball.position = Vec2(x: 20, y: 10)
        // Clear of the court's ledge, which the knock would put them on.
        match.players[0].position.x = 300
        match.players[1].position.x = 360
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        var strikes = 0, fired = 0
        for _ in 0..<400 {
            match.advance(inputs: [.idle, .idle])
            strikes += match.events.filter { if case .struck = $0 { return true } else { return false } }.count
            // Its own frames, the hits' stops not counted.
            if match.players[0].firingBeam { fired = max(fired, match.players[0].stateTimer + 1) }
        }
        XCTAssertGreaterThanOrEqual(match.players[0].flo, 10, "it costs nothing")
        XCTAssertEqual(fired, ZRules.beamMaxFrames, "three seconds, no more")
        XCTAssertGreaterThan(strikes, 1, "hit again as it fired on")
        XCTAssertFalse(match.players[0].firingBeam)
    }

    func testTheSlashOrTheSnatchCallsTheBeamOffOnlyAfterItsFirstSecond() {
        for snatch in [false, true] {
            var match = court(level: 1)
            match.players[1].position.x = 600
            match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
            for _ in 0..<(ZRules.chargeFrames + 10) { match.advance(inputs: [.idle, .idle]) }
            XCTAssertTrue(match.players[0].firingBeam)
            let press = snatch ? PlayerInput(throwBall: true) : PlayerInput(shoot: true)
            // Too soon: it fires on.
            match.advance(inputs: [press, .idle])
            for _ in 0..<(ZRules.beamCancelFrames - 20) { match.advance(inputs: [.idle, .idle]) }
            XCTAssertTrue(match.players[0].firingBeam, "not called off in its first second")
            // Past the first second: it stops.
            for _ in 0..<20 { match.advance(inputs: [.idle, .idle]) }
            match.advance(inputs: [press, .idle])
            match.advance(inputs: [.idle, .idle])
            XCTAssertFalse(match.players[0].firingBeam, snatch ? "the snatch called it off" : "the slash called it off")
        }
    }

    func testABallTheBeamHitsCanScore() {
        var match = court(level: 1)
        match.players[1].hasBall = false
        match.players[1].position.x = 600
        match.ball.holder = nil
        match.players[0].position.x = 300
        match.players[0].facing = .right
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        var scoring = false, placed = false
        for _ in 0..<(ZRules.chargeFrames + 30) {
            // Laid along the beam as it starts to fire.
            if !placed, match.players[0].firingBeam {
                placed = true
                match.ball.position = match.players[0].beamOrigin + match.players[0].beamDirection * 30
                match.ball.velocity = .zero
            }
            match.advance(inputs: [.idle, .idle])
            if match.ball.scoring, match.ball.lastTouched == 0 { scoring = true }
        }
        XCTAssertTrue(scoring, "sent off a scoring shot of the firer's, the rims drawing it in")
    }

    func testTheJumpCallsTheChargeOff() {
        var match = court(level: 1)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        for _ in 0..<20 { match.advance(inputs: [.idle, .idle]) }
        match.advance(inputs: [PlayerInput(jump: true), .idle])
        XCTAssertNotEqual(match.players[0].state, .beamCharging)
        XCTAssertTrue(match.beams.isEmpty)
    }

    func testFiringNothingMovesItButChargingAHitStopsIt() {
        var match = court(level: 1)
        match.players[0].state = .beamFiring
        match.players[0].knock(Vec2(x: 5, y: 3))
        match.players[0].hitStun = 30
        XCTAssertEqual(match.players[0].state, .beamFiring)
        XCTAssertEqual(match.players[0].hitStun, 0)
        var charging = court(level: 1)
        charging.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        charging.players[0].hitStun = 30
        charging.advance(inputs: [.idle, .idle])
        XCTAssertNotEqual(charging.players[0].state, .beamCharging)
    }

    func testInTheAirItChargesAndFiresHangingAsTheSlashDoes() {
        var match = court(level: 1)
        match.players[0].position = Vec2(x: 200, y: 120)
        match.players[0].grounded = false
        match.players[0].enter(.air)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .beamCharging)
        var fired = false
        for _ in 0..<(ZRules.chargeFrames + 2) {
            match.advance(inputs: [.idle, .idle])
            if match.events.contains(where: { if case .beamFired = $0 { return true } else { return false } }) { fired = true }
        }
        XCTAssertTrue(fired, "fired from the air")
    }

    func testAtLevelTwoAFullChargeIsKeptTillTheNextSlashFiresIt() {
        var match = court(level: 2)
        match.players[1].position.x = 600
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        for _ in 0..<(ZRules.chargeFrames + 1) { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].beamStored)
        XCTAssertNotEqual(match.players[0].state, .beamFiring, "kept, not fired")
        XCTAssertTrue(match.beams.isEmpty)
        // Free to move with it, then a slash fires it at once.
        for _ in 0..<20 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle]) }
        match.advance(inputs: [.idle, .idle])
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), shoot: true), .idle])
        XCTAssertEqual(match.players[0].state, .beamFiring)
        XCTAssertFalse(match.players[0].beamStored)
    }

    func testTheBlastPoseOpensFiresOffEachArmInTurnAndEndsOnANeutralFrame() {
        var match = court(level: 2)
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1), shoot: true), .idle])
        var frames: [Int] = []
        var fired: [(frame: Int, hand: Int)] = []
        var pressedAgain = false
        for _ in 0..<160 {
            // The next pressed as soon as the cooldown allows, while the first's pose is on.
            let again = !pressedAgain && match.players[0].blastCooldown == 0
            if again { pressedAgain = true }
            match.advance(inputs: [again ? PlayerInput(stick: Vec2(x: 0, y: 1), shoot: true) : .idle, .idle])
            if let frame = match.players[0].blastSheetFrame, frames.last != frame { frames.append(frame) }
            for event in match.events { if case .blastFired(player: 0, let hand) = event { fired.append((frames.last ?? -1, hand)) } }
            if match.players[0].blastStep == nil, pressedAgain, fired.count == 2 { break }
        }
        XCTAssertEqual(Array(frames.prefix(5)), [0, 1, 2, 3, 4], "opened, then the back arm")
        XCTAssertEqual(fired.map(\.hand), [0, 1], "each arm in turn")
        XCTAssertEqual(fired.map(\.frame), [ZRules.blastBackArmRelease, ZRules.blastFrontArmRelease], "let go fully out")
        XCTAssertEqual(frames.last, 2, "ends on the neutral frame")
        XCTAssertNil(match.players[0].blastStep)
        // Grounded, it went 45 degrees up.
        XCTAssertGreaterThan(match.blasts.first?.velocity.y ?? 0, 0)
    }

    func testAShieldFlipMidWindupLetsNoBlastGo() {
        var match = court(level: 1)
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.ball.respawn(at: Vec2(x: 30, y: 200))
        match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1), shoot: true), .idle])
        XCTAssertNotNil(match.players[0].blastStep)
        match.advance(inputs: [PlayerInput(shield: true), .idle])
        var fired = false
        for _ in 0..<60 {
            match.advance(inputs: [.idle, .idle])
            if match.events.contains(where: { if case .blastFired = $0 { return true } else { return false } }) { fired = true }
        }
        XCTAssertFalse(fired)
    }
}
