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
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
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

    func testAtLevelTwoTheStickTurnsItWhileFiringToAnyAngleWithin45Degrees() {
        var match = court(level: 2)
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        for _ in 0..<5 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1)), .idle]) }
        XCTAssertEqual(match.players[0].beamAim, ZRules.aimRate * 5, accuracy: 1e-9, "a little way up, not snapped")
        for _ in 0..<ZRules.chargeFrames { match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1)), .idle]) }
        XCTAssertEqual(match.players[0].beamAim, ZRules.aimRange, accuracy: 1e-9)
        XCTAssertTrue(match.players[0].firingBeam)
        for _ in 0..<5 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1)), .idle]) }
        XCTAssertEqual(match.players[0].beamAim, ZRules.aimRange - ZRules.aimRate * 5, accuracy: 1e-9, "turned while it fires")
        XCTAssertEqual(match.beams.first?.direction ?? .zero, match.players[0].beamDirection)
        var level = court(level: 1)
        level.advance(inputs: [PlayerInput(shoot: true), .idle])
        for _ in 0..<10 { level.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1)), .idle]) }
        XCTAssertEqual(level.players[0].beamAim, 0)
    }

    func testTheBeamFiresOnBurningFloAndHitsAgainTillItRunsOutOrIsStopped() {
        var match = court(level: 1)
        match.players[0].flo = 10
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.ball.position = Vec2(x: 20, y: 10)
        // Clear of the court's ledge, which the knock would put them on.
        match.players[0].position.x = 300
        match.players[1].position.x = 360
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        var strikes = 0, held = 0
        for _ in 0..<400 {
            match.advance(inputs: [.idle, .idle])
            strikes += match.events.filter { if case .struck = $0 { return true } else { return false } }.count
            held = max(held, match.players[0].beamHeld)
        }
        XCTAssertEqual(match.players[0].flo, 0, "burned")
        XCTAssertGreaterThan(held, 0, "fired on past its own time")
        XCTAssertGreaterThan(strikes, 1, "hit again as it fired on")
        XCTAssertFalse(match.players[0].firingBeam, "and done when it ran out")

        // Pressed again while it fires, it stops at its own time with the FLO kept.
        var stopped = court(level: 1)
        stopped.players[0].flo = 50
        stopped.players[1].position.x = 600
        stopped.advance(inputs: [PlayerInput(shoot: true), .idle])
        for _ in 0..<(ZRules.chargeFrames + 10) { stopped.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(stopped.players[0].firingBeam)
        stopped.advance(inputs: [PlayerInput(shoot: true), .idle])
        for _ in 0..<ZRules.fireFrames { stopped.advance(inputs: [.idle, .idle]) }
        XCTAssertFalse(stopped.players[0].firingBeam)
        XCTAssertEqual(stopped.players[0].flo, 50)
    }

    func testTheJumpCallsTheChargeOff() {
        var match = court(level: 1)
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
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
        charging.advance(inputs: [PlayerInput(shoot: true), .idle])
        charging.players[0].hitStun = 30
        charging.advance(inputs: [.idle, .idle])
        XCTAssertNotEqual(charging.players[0].state, .beamCharging)
    }

    func testTheBurstPushesWhoeverIsCloseAndComesQuickerAtLevelTwo() {
        func burst(level: Int) -> (frame: Int, pushed: Bool) {
            var match = court(level: level)
            // Just off the floor, held there through the sheet; the other standing beside it.
            match.players[0].position = Vec2(x: 200, y: 14)
            match.players[0].grounded = false
            match.players[0].enter(.air)
            match.players[1].position = Vec2(x: 220, y: 10)
            match.advance(inputs: [PlayerInput(shoot: true), .idle])
            XCTAssertEqual(match.players[0].state, .zBurst)
            for frame in 0..<120 {
                match.advance(inputs: [.idle, .idle])
                if match.events.contains(where: { if case .zBurst = $0 { return true } else { return false } }) {
                    return (frame, match.players[1].velocity.x > 2)
                }
            }
            return (-1, false)
        }
        let one = burst(level: 1), two = burst(level: 2)
        XCTAssertTrue(one.pushed)
        XCTAssertTrue(two.pushed)
        XCTAssertLessThan(two.frame, one.frame)
    }
}
