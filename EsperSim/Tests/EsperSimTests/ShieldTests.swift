import XCTest
@testable import EsperSim

/// Shielding: the up-snatch on defence, the flipjump back and the tumble, the shield round its arc.
final class ShieldTests: XCTestCase {
    private func court() -> Match {
        var match = Match(stage: .court, specs: [.starting, .starting])
        match.countdown = 0
        match.players[0].position = Vec2(x: 120, y: 10)
        match.players[0].facing = .right
        match.players[1].position = Vec2(x: 300, y: 10)
        match.ball.holder = nil
        match.players.indices.forEach { match.players[$0].hasBall = false }
        match.ball.respawn(at: Vec2(x: 200, y: 150))
        match.ball.position = Vec2(x: 30, y: 200)
        match.ball.velocity = .zero
        for _ in 0..<5 { match.advance(inputs: [.idle, .idle]) }
        return match
    }

    /// The shield's shortcut pressed on defence (the other holding the ball for that frame, the
    /// ball then put back as it was): the flip starts and the shield's up at once.
    private func raise(_ match: inout Match, player: Int = 0) {
        var inputs: [PlayerInput] = [.idle, .idle]
        inputs[player] = PlayerInput(shield: true)
        let loose = match.ball, other = 1 - player
        match.ball.holder = other
        match.players[other].hasBall = true
        match.advance(inputs: inputs)
        match.ball = loose
        match.players[other].hasBall = false
    }

    func testAnyTimeWithoutTheBallTheUpSnatchFlipsAndRaisesOne() {
        var loose = court()
        loose.advance(inputs: [PlayerInput(shield: true), .idle])
        XCTAssertEqual(loose.players[0].state, .flipJump, "the ball loose")
        XCTAssertEqual(loose.shields.count, 1)
        var upLoose = court()
        upLoose.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1), throwBall: true), .idle])
        XCTAssertEqual(upLoose.players[0].state, .flipJump)
        var downLoose = court()
        downLoose.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1), throwBall: true), .idle])
        XCTAssertEqual(downLoose.players[0].state, .flipJump, "down asks for it as up does")
        var defence = court()
        defence.ball.holder = 1
        defence.players[1].hasBall = true
        defence.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: 1), throwBall: true), .idle])
        XCTAssertEqual(defence.players[0].state, .flipJump)
        var holding = court()
        holding.ball.holder = 0
        holding.players[0].hasBall = true
        holding.advance(inputs: [PlayerInput(shield: true), .idle])
        XCTAssertTrue(holding.shields.isEmpty, "not with the ball")
    }

    func testItGoesFromStraightBelowToStraightAboveItsFaceSixtyEitherWay() {
        var match = court()
        raise(&match)
        var shield = match.shields[0]
        shield.age = 0
        XCTAssertEqual(shield.centre.x, shield.pivot.x, accuracy: 0.001)
        XCTAssertLessThan(shield.centre.y, shield.pivot.y)
        XCTAssertEqual(shield.normal.y, -Trig.sin(degrees(60)), accuracy: 0.001)
        XCTAssertGreaterThan(shield.normal.x, 0, "out the way it faced")
        shield.age = ShieldRules.flipFrames - 1
        XCTAssertEqual(shield.centre.x, shield.pivot.x, accuracy: 0.001)
        XCTAssertGreaterThan(shield.centre.y, shield.pivot.y)
        XCTAssertEqual(shield.normal.y, Trig.sin(degrees(60)), accuracy: 0.001)
    }

    func testTheFlipIgnoresTheStickAndGravityThenTumblesOnTillItLands() {
        var match = court()
        let from = match.players[0].position
        raise(&match)
        for frame in 1..<ShieldRules.flipFrames {
            match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: -1), jump: true), .idle])
            let expected = from + ShieldRules.flipOffset(share: Double(frame + 1) / Double(ShieldRules.flipFrames), side: 1)
            if match.players[0].state != .flipJump { break }
            XCTAssertEqual(match.players[0].position.x, expected.x, accuracy: 0.001, "frame \(frame)")
        }
        // In the air at the flip's end: the tumble, left and right its only say, till it lands.
        var aloft = court()
        aloft.players[0].position = Vec2(x: 120, y: 120)
        aloft.players[0].grounded = false
        aloft.players[0].enter(.air)
        raise(&aloft)
        for _ in 0..<ShieldRules.flipFrames { aloft.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(aloft.players[0].state, .tumbling)
        let drift = aloft.players[0].velocity.x
        aloft.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0), shoot: true), .idle])
        XCTAssertEqual(aloft.players[0].state, .tumbling, "no button answers")
        XCTAssertGreaterThan(aloft.players[0].velocity.x, drift, "steered")
        for _ in 0..<240 where aloft.players[0].state == .tumbling { aloft.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(aloft.players[0].state, .land)
    }

    func testOnesOwnShieldsDontBreakEachOther() {
        var match = court()
        match.shields.append(Shield(owner: 0, pivot: match.players[0].body.center, side: 1))
        raise(&match)
        XCTAssertEqual(match.shields.count, 2)
    }

    func testTwoInOnePlaceClashThenPushBothAway() {
        var match = court()
        match.players[1].position = Vec2(x: 140, y: 10)
        match.shields.append(Shield(owner: 1, pivot: match.players[1].body.center, side: -1))
        raise(&match)
        XCTAssertTrue(match.shields.isEmpty, "both broken")
        XCTAssertTrue(match.events.contains { if case .shieldClashed = $0 { return true } else { return false } })
        XCTAssertEqual(match.hitStop, HitStopRules.shieldClashFrames)
        for _ in 0..<HitStopRules.shieldClashFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertLessThan(match.players[0].velocity.x, 0)
        XCTAssertGreaterThan(match.players[1].velocity.x, 0)
        XCTAssertEqual(match.players[0].state, .air, "off the flip")
    }

    /// The ball coming at the shielder across, from the side the shield's on.
    private func ballAt(_ match: inout Match, shield: Shield, speed: Double) {
        // Level with its raiser's middle, just outside its reach, coming at them across.
        match.ball.respawnTimer = 0
        match.ball.position = shield.pivot + Vec2(x: shield.side * (ShieldRules.reach + BallRules.radius + 1), y: 0)
        match.ball.velocity = Vec2(x: -shield.side * speed, y: 0)
        match.ball.thrown = false
    }

    func testEachShieldTurnsTheBallOnce() {
        var match = court()
        raise(&match)
        for _ in 0..<ShieldRules.perfectFrames { match.advance(inputs: [.idle, .idle]) }
        match.shields[0].turnedFlight = match.ball.flight
        ballAt(&match, shield: match.shields[0], speed: 4)
        let inward = match.ball.velocity
        for _ in 0..<3 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertGreaterThan(match.ball.velocity.dot(inward), 0, "passed on through")
    }

    func testALateBallReflectsAndAPerfectOneIsPoppedUp() {
        var match = court()
        raise(&match)
        for _ in 0..<ShieldRules.perfectFrames { match.advance(inputs: [.idle, .idle]) }
        ballAt(&match, shield: match.shields[0], speed: 4)
        let inward = match.ball.velocity
        var reflected = false
        for _ in 0..<4 {
            match.advance(inputs: [.idle, .idle])
            if match.events.contains(where: { if case .shieldReflected = $0 { return true } else { return false } }) { reflected = true }
        }
        XCTAssertTrue(reflected)
        XCTAssertLessThan(match.ball.velocity.dot(inward), 0, "back the way it came")

        var perfect = court()
        raise(&perfect)
        ballAt(&perfect, shield: perfect.shields[0], speed: 4)
        var popped = false
        for _ in 0..<4 {
            perfect.advance(inputs: [.idle, .idle])
            if perfect.events.contains(where: { if case .shieldPerfect = $0 { return true } else { return false } }) { popped = true }
        }
        XCTAssertTrue(popped)
        XCTAssertTrue(perfect.players[0].shieldParried, "as a parry: the flip ends in the air, not the tumble")
    }

    func testAThrownBallBreaksItAndAFloaterBouncesOff() {
        var match = court()
        raise(&match)
        for _ in 0..<ShieldRules.perfectFrames { match.advance(inputs: [.idle, .idle]) }
        ballAt(&match, shield: match.shields[0], speed: 4)
        match.ball.thrown = true
        match.ball.lastTouched = 1
        var countered = false
        for _ in 0..<4 {
            match.advance(inputs: [.idle, .idle])
            countered = countered || match.events.contains { if case .countered(player: 0, by: 1, _) = $0 { return true } else { return false } }
        }
        XCTAssertTrue(match.shields.isEmpty)
        XCTAssertTrue(countered)
        XCTAssertGreaterThan(match.players[0].hitStun, 0, "the shielder struck")

        var floater = court()
        raise(&floater)
        for _ in 0..<ShieldRules.perfectFrames { floater.advance(inputs: [.idle, .idle]) }
        ballAt(&floater, shield: floater.shields[0], speed: 4)
        floater.ball.thrown = true
        floater.ball.floaterShot = true
        for _ in 0..<4 { floater.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(floater.shields.count, 1)
    }

    func testItGoesAtTheArcsEnd() {
        var match = court()
        raise(&match)
        for _ in 0..<ShieldRules.lifeFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.shields.isEmpty)
    }

    func testTheOthersShieldIsSolidToTheirBody() {
        var match = court()
        raise(&match)
        let start = match.shields[0].pivot
        match.players[1].position = Vec2(x: start.x + ShieldRules.reach + 8, y: 10)
        for _ in 0..<5 { match.advance(inputs: [.idle, PlayerInput(stick: Vec2(x: -1, y: 0))]) }
        // Walking into its reach, the body's held at its edge.
        guard let pivot = match.shields.first?.pivot else { return XCTFail("gone") }
        XCTAssertGreaterThanOrEqual(match.players[1].body.min.x, pivot.x + ShieldRules.reach - 0.5)
    }

    func testABladeOnItParriesTheSwinger() {
        // A shield up on someone standing still, the other swinging into it.
        var match = court()
        match.players[1].position = Vec2(x: 140, y: 10)
        match.players[1].facing = .left
        match.shields.append(Shield(owner: 0, pivot: match.players[0].body.center, side: 1))
        let parried = (0..<20).contains { _ in
            match.advance(inputs: [.idle, PlayerInput(shoot: !match.players[1].lastInput.shoot)])
            return match.events.contains { if case .parried(player: 1, by: 0) = $0 { return true } else { return false } }
        }
        XCTAssertTrue(parried)
    }

    func testASnatchOnItBreaksItAndStunsTheShielder() {
        var match = court()
        // A shield up on someone standing still, the other snatching into it.
        match.players[1].position = Vec2(x: 140, y: 10)
        match.players[1].facing = .left
        match.shields.append(Shield(owner: 0, pivot: match.players[0].body.center, side: 1))
        var countered = false
        for _ in 0..<20 where !countered {
            match.advance(inputs: [.idle, PlayerInput(throwBall: !match.players[1].lastInput.throwBall)])
            countered = match.events.contains { if case .countered(player: 0, by: 1, _) = $0 { return true } else { return false } }
        }
        XCTAssertTrue(countered)
        XCTAssertTrue(match.shields.isEmpty)
        XCTAssertGreaterThan(match.players[0].hitStun, 0)
        XCTAssertEqual(match.hitStop, HitStopRules.counterFrames)
    }

    func testParryingWithTheFlipsShieldEndsItInTheAir() {
        var match = court()
        match.players[1].position = Vec2(x: 140, y: 10)
        match.players[1].facing = .left
        match.players[0].enter(.flipJump)
        match.shields.append(Shield(owner: 0, pivot: match.players[0].body.center, side: 1))
        let parried = (0..<20).contains { _ in
            match.advance(inputs: [.idle, PlayerInput(shoot: !match.players[1].lastInput.shoot)])
            return match.events.contains { if case .parried(player: 1, by: 0) = $0 { return true } else { return false } }
        }
        XCTAssertTrue(parried)
        XCTAssertTrue(match.players[0].shieldParried)

        var aloft = court()
        aloft.players[0].position = Vec2(x: 120, y: 120)
        aloft.players[0].grounded = false
        aloft.players[0].enter(.air)
        raise(&aloft)
        aloft.players[0].shieldParried = true
        for _ in 0..<ShieldRules.flipFrames { aloft.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(aloft.players[0].state, .air, "every move back, no tumble")
    }

    func testAPowerStopsOnItAndPerfectlyMetTurnsBack() {
        var perfect = court()
        raise(&perfect)
        let pivot = perfect.shields[0].pivot
        perfect.bolts.append(Bolt(id: 900, owner: 1, position: pivot + Vec2(x: ShieldRules.reach + 5, y: 0), velocity: Vec2(x: -4, y: 0),
                                  framesLeft: VoltaRules.boltFrames))
        for _ in 0..<2 { perfect.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(perfect.bolts.first?.owner, 0, "the shielder's now")
        XCTAssertGreaterThan(perfect.bolts.first?.velocity.x ?? 0, 0, "back the way it came")

        var late = court()
        raise(&late)
        for _ in 0..<ShieldRules.perfectFrames { late.advance(inputs: [.idle, .idle]) }
        let latePivot = late.shields[0].pivot
        late.bolts.append(Bolt(id: 900, owner: 1, position: latePivot + Vec2(x: ShieldRules.reach + 5, y: 0), velocity: Vec2(x: -4, y: 0),
                               framesLeft: VoltaRules.boltFrames))
        var blocked = false
        for _ in 0..<3 {
            late.advance(inputs: [.idle, .idle])
            blocked = blocked || late.events.contains { if case .powerBlocked(player: 0, _) = $0 { return true } else { return false } }
        }
        XCTAssertTrue(blocked)
        XCTAssertTrue(late.bolts.isEmpty)
        XCTAssertEqual(late.players[0].hitStun, 0)
    }

    func testABeamOffAPerfectShieldTurnsBackAndStunsItsFirerOnce() {
        var match = court()
        match.players[1].position = Vec2(x: 220, y: 10)
        match.players[1].facing = .left
        match.players[1].enter(.beamFiring)
        match.beams.append(Beam(id: 901, owner: 1, origin: match.players[1].beamOrigin, direction: Vec2(x: -1, y: 0), framesLeft: ZRules.fireFrames))
        raise(&match)
        var struck = 0
        for _ in 0..<40 {
            match.advance(inputs: [.idle, .idle])
            struck += match.events.filter { if case .struck(player: 1, by: 0) = $0 { return true } else { return false } }.count
        }
        XCTAssertEqual(struck, 1)
        XCTAssertNotEqual(match.players[1].state, .beamFiring, "its firing ended")
        XCTAssertEqual(match.players[0].hitStun, 0, "the shielder untouched")
    }

    func testABodyInsideItIsShovedOut() {
        var match = court()
        match.players[1].position = Vec2(x: 130, y: 10)
        match.shields.append(Shield(owner: 0, pivot: match.players[0].body.center, side: 1))
        for _ in 0..<10 { match.advance(inputs: [.idle, .idle]) }
        guard let shield = match.shields.first else { return XCTFail("gone") }
        XCTAssertGreaterThanOrEqual(match.players[1].body.distance(to: shield.pivot), ShieldRules.reach, "out to the reach's edge")
        XCTAssertGreaterThan(match.players[1].position.x, 130)
    }

    // MARK: Guarderade and Shelter Seltzer

    private func drinking(_ drink: Greateraid, level: Int) -> Match {
        var drinks = Drinks()
        for _ in 0..<level { drinks.drink(drink) }
        var match = Match(stage: .court, specs: [drinks.spec(), .starting])
        match.countdown = 0
        match.players[0].position = Vec2(x: 120, y: 10)
        match.players[0].facing = .right
        match.players[1].position = Vec2(x: 300, y: 10)
        match.ball.holder = nil
        match.players.indices.forEach { match.players[$0].hasBall = false }
        match.ball.respawn(at: Vec2(x: 200, y: 150))
        match.ball.position = Vec2(x: 30, y: 200)
        match.ball.velocity = .zero
        for _ in 0..<5 { match.advance(inputs: [.idle, .idle]) }
        return match
    }

    func testGuarderadeMakesTheShieldBigger() {
        var match = drinking(.guarderade, level: 1)
        match.advance(inputs: [PlayerInput(shield: true), .idle])
        XCTAssertEqual(match.shields.first?.reach, ShieldRules.guarderadeReach)
        XCTAssertEqual(match.shields.first?.pictureScale, ShieldRules.guarderadePictureScale)
    }

    func testGuarderadeAtLevelTwoShieldsAgainOutOfTheTumbleOnce() {
        for level in 1...2 {
            var match = drinking(.guarderade, level: level)
            match.players[0].position = Vec2(x: 160, y: 120)
            match.players[0].grounded = false
            match.players[0].enter(.air)
            match.advance(inputs: [PlayerInput(shield: true), .idle])
            for _ in 0..<ShieldRules.flipFrames + 1 { match.advance(inputs: [.idle, .idle]) }
            XCTAssertEqual(match.players[0].state, .tumbling)
            match.advance(inputs: [PlayerInput(shield: true), .idle])
            XCTAssertEqual(match.players[0].state == .flipJump, level == 2, "level \(level)")
            if level == 2 {
                for _ in 0..<ShieldRules.flipFrames + 1 { match.advance(inputs: [.idle, .idle]) }
                match.advance(inputs: [PlayerInput(shield: true), .idle])
                XCTAssertNotEqual(match.players[0].state, .flipJump, "only once before landing")
            }
        }
    }

    func testShelterSeltzerLeavesTheShieldWhereItEndedASecond() {
        var match = drinking(.shelterSeltzer, level: 1)
        match.advance(inputs: [PlayerInput(shield: true), .idle])
        for _ in 0..<ShieldRules.flipFrames + 5 { match.advance(inputs: [.idle, .idle]) }
        guard let shield = match.shields.first else { return XCTFail("gone with the arc") }
        XCTAssertTrue(shield.lingering)
        let left = shield.pivot
        for _ in 0..<20 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle]) }
        XCTAssertEqual(match.shields.first?.pivot, left, "left where it was")
        XCTAssertTrue((ShieldRules.loopFrames.lowerBound...ShieldRules.sheetFrames - 1).contains(match.shields.first!.sheetFrame))
        for _ in 0..<ShieldRules.shelterLingerFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.shields.isEmpty, "gone after its second")
    }

    func testShelterSeltzerPlantsAStillShieldOnlyAsTheFlipsLeaves() {
        var match = drinking(.shelterSeltzer, level: 1)
        match.advance(inputs: [PlayerInput(shield: true), .idle])
        XCTAssertEqual(match.shields.count, 1)
        XCTAssertFalse(match.shields[0].planted, "the flip's own shield first, sweeping as ever")
        var last: Shield?
        while let flip = match.shields.first, !flip.planted {
            last = flip
            match.advance(inputs: [.idle, .idle])
        }
        guard let ended = last, let planted = match.shields.first else { return XCTFail("planted as the flip's left") }
        XCTAssertEqual(match.shields.count, 1, "the flip's gone as the planted one comes")
        XCTAssertTrue(planted.planted)
        XCTAssertEqual(planted.tilt, ended.tilt, accuracy: 0.0001, "at the flip's last angle")
        XCTAssertEqual(planted.centre.x, ended.centre.x, accuracy: 0.0001)
        XCTAssertEqual(planted.centre.y, ended.centre.y, accuracy: 0.0001)
        XCTAssertFalse(planted.inPerfectWindow, "no perfect window of its own")
        let centre = planted.centre
        for _ in 0..<20 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 1, y: 0)), .idle]) }
        XCTAssertEqual(match.shields.first?.centre, centre, "still")
        XCTAssertEqual(match.shields.first?.tilt ?? 0, ended.tilt, accuracy: 0.0001, "never turning")
    }

    func testShelterSeltzerAtLevelTwoSnatchesRaiseAGuardAtTheHandThatParriesASlash() {
        var match = drinking(.shelterSeltzer, level: 2)
        match.players[1].position = Vec2(x: 140, y: 10)
        match.players[1].facing = .left
        match.advance(inputs: [PlayerInput(throwBall: true), .idle])
        guard let guardShield = match.shields.first else { return XCTFail("no guard") }
        XCTAssertTrue(guardShield.guardOnly)
        XCTAssertEqual(guardShield.pivot.x, match.players[0].handCatchPoint.x, accuracy: 3)
        let parried = (0..<20).contains { _ in
            match.advance(inputs: [.idle, PlayerInput(shoot: !match.players[1].lastInput.shoot)])
            return match.events.contains { if case .parried(player: 1, by: 0) = $0 { return true } else { return false } }
        }
        XCTAssertTrue(parried, "the slash parried by the snatch's guard")
    }

    func testAnExcludedBallPassesTheOthersShieldUntouched() {
        var match = court()
        raise(&match)
        ballAt(&match, shield: match.shields[0], speed: 4)
        match.ball.exclusiveTo = 1
        match.ball.exclusionFrames = ExclusionRules.frames
        let velocity = match.ball.velocity
        var touched = false
        for _ in 0..<4 {
            match.advance(inputs: [.idle, .idle])
            if match.events.contains(where: { if case .shieldPerfect = $0 { return true }; if case .shieldReflected = $0 { return true }; return false }) { touched = true }
        }
        XCTAssertFalse(touched, "not theirs to shield")
        XCTAssertEqual(match.ball.exclusiveTo, 1, "still the other's")
        XCTAssertEqual(match.ball.velocity.x, velocity.x, accuracy: 0.5)
    }
}
