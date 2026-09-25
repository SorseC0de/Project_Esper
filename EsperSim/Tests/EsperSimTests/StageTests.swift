import XCTest
@testable import EsperSim

/// The football field: its layout, the coin flip, helmets and the portal.
final class StageTests: XCTestCase {
    private func field(seed: UInt32 = 1) -> Match { Match(stage: .footballField, seed: seed) }

    func testSpawnsAndTheBallAreClearOfSolids() {
        let match = field()
        for player in match.players { XCTAssertFalse(match.stage.overlapsSolid(player.body)) }
        XCTAssertFalse(match.stage.overlapsSolid(Box(center: match.stage.ballSpawn, width: 5, height: 5)))
        XCTAssertEqual(match.stage.columns, 340)
        XCTAssertEqual(match.stage.rows, 20)
    }

    func testEachStartsUnderTheRimTheyGuardAndTheCoinFlipGivesTheBall() {
        var holders = Set<Int>()
        for seed in 1...20 {
            let match = field(seed: UInt32(seed))
            let guarded0 = match.stage.hoops.first { $0.owner == 1 }!
            XCTAssertEqual(match.players[0].position.x, guarded0.position.x, accuracy: 0.001)
            XCTAssertNotNil(match.ball.holder)
            holders.insert(match.ball.holder!)
        }
        XCTAssertEqual(holders, [0, 1], "both sides win the flip sometimes")
    }

    func testHelmetsSpawnOnlyWithPossessionFromTheDefendersEnd() {
        var match = field()
        let holder = match.ball.holder!
        for _ in 0..<FieldRules.helmetSpawnFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.helmets.count, 1)
        let helmet = match.helmets[0]
        XCTAssertEqual(helmet.owner, 1 - holder, "in the defender's colour")
        let target = match.stage.hoops.first { $0.owner == holder }!
        XCTAssertEqual(helmet.speed > 0, target.position.x < match.stage.width / 2, "from the end the holder attacks")
        // Loose ball: the clock stops, the helmet keeps going.
        match.ball.holder = nil
        match.players[holder].hasBall = false
        match.ball.respawn(at: match.stage.ballSpawn)
        let x = match.helmets[0].box.min.x
        for _ in 0..<FieldRules.helmetSpawnFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.helmets.count, 1)
        XCTAssertNotEqual(match.helmets[0].box.min.x, x)
    }

    func testAHelmetPushesABodyAndCarriesARider() {
        var match = field()
        match.players[0].hasBall = false
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.ball.respawn(at: Vec2(x: 900, y: 150))
        let box = Box(min: Vec2(x: 500, y: 10), max: Vec2(x: 540, y: 50))
        match.helmets = [Helmet(id: 99, box: box, speed: 1, owner: 1, variant: 0)]
        match.helmetClock = -10_000
        match.players[0].position = Vec2(x: 545, y: 10)
        match.players[1].position = Vec2(x: 520, y: 50)
        match.advance(inputs: [.idle, .idle])
        XCTAssertGreaterThanOrEqual(match.players[0].body.min.x, match.helmets[0].box.max.x - 0.001, "pushed ahead")
        let riderX = match.players[1].position.x
        for _ in 0..<10 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[1].position.x, riderX + 10, accuracy: 0.5, "carried")
    }

    func testAPinnedBodyIsPassedThrough() {
        var match = field()
        match.players[0].hasBall = false
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.ball.respawn(at: Vec2(x: 900, y: 150))
        let right = match.stage.width - Stage.tileSize
        match.helmets = [Helmet(id: 99, box: Box(min: Vec2(x: right - 60, y: 10), max: Vec2(x: right - 10, y: 60)), speed: 1, owner: 1, variant: 0)]
        match.players[0].position = Vec2(x: right - 6, y: 10)
        for _ in 0..<30 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.helmets.isEmpty, "gone at the wall")
        XCTAssertFalse(match.stage.overlapsSolid(match.players[0].body))
    }

    func testTheLowestHelmetPushesAStandingBodyAndClearsACrouch() {
        var match = field()
        let lowest = FieldRules.helmetHeights[0]
        XCTAssertLessThan(lowest, match.players[0].standingHeightTop - match.players[0].position.y + 10)
        match.players[0].state = .crouch
        XCTAssertGreaterThan(lowest, match.players[0].body.max.y)
    }

    func testTheComputerGoesUnderTheLowestHelmet() {
        var match = field()
        var brain = Opponent(index: 1)
        match.players[0].hasBall = false
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.ball.respawn(at: Vec2(x: 400, y: 20))
        match.helmetClock = -10_000
        match.players[1].position = Vec2(x: 900, y: 10)
        let bottom = FieldRules.helmetHeights[0]
        match.helmets = [Helmet(id: 5, box: Box(min: Vec2(x: 780, y: bottom), max: Vec2(x: 820, y: bottom + 40)), speed: 2, owner: 0, variant: 0)]
        var passed = false
        for _ in 0..<150 where !passed {
            match.advance(inputs: [.idle, brain.decide(match)])
            if let helmet = match.helmets.first, helmet.box.min.x > match.players[1].position.x + 10 { passed = true }
        }
        XCTAssertTrue(passed, "the helmet went over it")
        XCTAssertLessThan(match.players[1].position.x, 900, "not carried along ahead of it")
    }

    func testACrouchStaysDownWhileThereIsNoRoomToStand() {
        var match = field()
        match.players[0].hasBall = false
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.ball.respawn(at: Vec2(x: 900, y: 150))
        match.players[0].position = Vec2(x: 700, y: 10)
        for _ in 0..<3 { match.advance(inputs: [PlayerInput(stick: Vec2(x: 0, y: -1)), .idle]) }
        XCTAssertEqual(match.players[0].state, .crouch)
        // A block low enough to fit a crouch and not a standing body.
        let bottom = (match.players[0].body.max.y + match.players[0].standingHeightTop) / 2
        match.helmets = [Helmet(id: 5, box: Box(min: Vec2(x: 680, y: bottom), max: Vec2(x: 720, y: bottom + 40)), speed: 0, owner: 1, variant: 0)]
        match.helmetClock = -10_000
        match.advance(inputs: [.idle, .idle])
        XCTAssertEqual(match.players[0].state, .crouch, "no room to stand")
    }

    func testAPushedBallFalls() {
        var match = field()
        match.players[0].hasBall = false
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.helmetClock = -10_000
        match.ball.release(from: Vec2(x: 705, y: 60), velocity: Vec2(x: -2, y: 0), by: 0, straight: true)
        match.helmets = [Helmet(id: 5, box: Box(min: Vec2(x: 660, y: 40), max: Vec2(x: 700, y: 80)), speed: 2, owner: 1, variant: 0)]
        let height = match.ball.position.y
        for _ in 0..<20 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertLessThan(match.ball.position.y, height - 5, "gravity takes it once pushed")
    }

    func testTheComputerGetsOnTopOfAHelmetComingAtIt() {
        var match = field()
        var brain = Opponent(index: 1)
        match.players[0].hasBall = false
        match.players[1].hasBall = false
        match.ball.holder = nil
        // The ball behind the helmet, so its way there runs into it.
        match.ball.respawn(at: Vec2(x: 400, y: 20))
        match.helmetClock = -10_000
        match.players[1].position = Vec2(x: 900, y: 10)
        // One at its height: none spawn this low, but one met in the air is the same.
        let bottom = 10.0
        match.helmets = [Helmet(id: 5, box: Box(min: Vec2(x: 780, y: bottom), max: Vec2(x: 820, y: bottom + 40)), speed: 2, owner: 0, variant: 0)]
        var rode = false
        for _ in 0..<120 where !rode {
            match.advance(inputs: [.idle, brain.decide(match)])
            if let helmet = match.helmets.first, match.players[1].grounded, abs(match.players[1].position.y - helmet.box.max.y) < 0.01 { rode = true }
        }
        XCTAssertTrue(rode, "up and riding it rather than pushed along")
    }

    func testTheBallBouncesOffABackboard() {
        var match = field()
        match.players[0].hasBall = false
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.helmetClock = -10_000
        let board = match.stage.ballBlockers[1]
        match.ball.release(from: Vec2(x: board.min.x - 20, y: board.center.y), velocity: Vec2(x: 4, y: 0), by: 0, straight: true)
        for _ in 0..<10 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertLessThan(match.ball.velocity.x, 0, "off the board and back")
        XCTAssertLessThanOrEqual(match.ball.box.max.x, board.min.x + 0.01)
    }

    func testOpposingHelmetsTakeEachOtherOut() {
        var match = field()
        match.helmets = [
            Helmet(id: 1, box: Box(min: Vec2(x: 400, y: 90), max: Vec2(x: 450, y: 140)), speed: 1, owner: 1, variant: 0),
            Helmet(id: 2, box: Box(min: Vec2(x: 451, y: 90), max: Vec2(x: 501, y: 140)), speed: -1, owner: 0, variant: 1),
        ]
        match.advance(inputs: [.idle, .idle])
        XCTAssertTrue(match.helmets.isEmpty)
        XCTAssertTrue(match.events.contains { if case .helmetsCollided = $0 { return true } else { return false } })
    }

    func testThePortalWarpsAThrownBallTenYardsTowardTheShootersRim() {
        var match = field()
        match.advance(inputs: [.idle, .idle])
        XCTAssertNotNil(match.portal)
        let portal = match.portal!
        match.players[0].hasBall = false
        match.players[1].hasBall = false
        match.ball.holder = nil
        match.ball.release(from: portal.centre - Vec2(x: 3, y: 0), velocity: Vec2(x: 2, y: 0), by: 0, straight: true)
        match.advance(inputs: [.idle, .idle])
        let warped = match.events.first { if case .portalWarped = $0 { return true } else { return false } }
        XCTAssertNotNil(warped)
        let rim = match.stage.hoops.first { $0.owner == 0 }!
        let sign: Double = rim.position.x > portal.centre.x ? 1 : -1
        XCTAssertEqual((match.ball.position.x - portal.centre.x) * sign, 10 * FieldRules.yard(in: match.stage), accuracy: 6)
        XCTAssertGreaterThan(match.ball.velocity.y, 0, "kept aloft")
    }

    func testThePortalLastsFiveSecondsAndAnotherFollows() {
        var match = field()
        match.advance(inputs: [.idle, .idle])
        let first = match.portal!.id
        for _ in 0..<FieldRules.portalFrames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertNotNil(match.portal)
        XCTAssertNotEqual(match.portal!.id, first)
        XCTAssertEqual(match.portal!.centre.y, FieldRules.portalHeight, accuracy: 0.001)
    }

    func testAShotFromEachSpawnCanScore() {
        for shooter in 0...1 {
            var match = field()
            let rim = match.stage.hoops.first { $0.owner == shooter }!
            // From four tiles in front of the rim, a jump shot let go at the top of a full
            // hop: the rim sits too high for one off the floor.
            let inward: Double = rim.position.x > match.stage.width / 2 ? -1 : 1
            var scored = false
            for step in 0..<40 where !scored {
                var trial = match
                trial.players[shooter].position = Vec2(x: rim.position.x + inward * 50, y: 10)
                trial.players[shooter].hasBall = false
                trial.players[1 - shooter].hasBall = false
                trial.players[1 - shooter].position.x = match.stage.width / 2
                trial.ball.holder = nil
                let angle = degrees(30 + Double(step))
                let from = trial.players[shooter].position + Vec2(x: 0, y: BallRules.shotReleaseHeight + 31)
                trial.ball.release(from: from, velocity: Vec2(x: Trig.cos(angle) * -inward, y: Trig.sin(angle)) * trial.players[shooter].spec.shotSpeed, by: shooter, straight: false)
                trial.ball.shotInFlight = true
                for _ in 0..<240 where !scored {
                    trial.advance(inputs: [.idle, .idle])
                    if trial.events.contains(where: { if case .scored = $0 { return true } else { return false } }) { scored = true }
                }
            }
            XCTAssertTrue(scored, "player \(shooter) can score on their rim")
            match.advance(inputs: [.idle, .idle])
        }
    }

    func testTheFieldStaysInStepAcrossTwoCopies() {
        var a = field(seed: 7), b = field(seed: 7)
        for frame in 0..<900 {
            let input = PlayerInput(stick: Vec2(x: frame % 120 < 60 ? 1 : -1, y: 0), jump: frame % 40 == 0)
            a.advance(inputs: [input, .idle])
            b.advance(inputs: [input, .idle])
        }
        XCTAssertEqual(a.checksum, b.checksum)
        XCTAssertEqual(a, b)
    }
}

/// Highway Traffic: the cars, their wrecking, and the helicopter's rim.
final class HighwayTests: XCTestCase {
    private func road(seed: UInt32 = 1) -> Match { Match(stage: .highway, seed: seed) }

    func testTheRoadFillsItsSlotsWithCarsOffTheDice() {
        let a = road(seed: 3), b = road(seed: 3)
        XCTAssertEqual(a.cars.count, HighwayRules.slots * 2, "a row on the road and a row on the deck")
        XCTAssertEqual(a.cars.filter { $0.level == 1 }.map(\.box.min.y), Array(repeating: HighwayRules.deckTop, count: HighwayRules.slots))
        XCTAssertTrue(a.cars.filter { $0.level == 1 }.allSatisfy(\.facesLeft))
        XCTAssertTrue(a.cars.filter { $0.level == 0 }.allSatisfy { !$0.facesLeft })
        XCTAssertEqual(a.cars.map(\.vehicle), b.cars.map(\.vehicle), "the same seed, the same traffic")
        for car in a.cars where car.level == 0 {
            XCTAssertEqual(car.box.min.y, Stage.tileSize, accuracy: 0.001, "on the road")
            for box in car.boxes { XCTAssertTrue(a.stage.extras.contains(box), "solid, tile by tile") }
            XCTAssertEqual(car.boxes.count, Int(car.vehicle.lengthTiles))
        }
        var kinds = Set<Vehicle>()
        for seed in 1...40 { kinds.formUnion(road(seed: UInt32(seed)).cars.map(\.vehicle)) }
        XCTAssertGreaterThan(kinds.count, 10, "every kind comes up")
    }

    func testThreeHitsWreckACarAndAnotherTakesItsPlace() {
        var match = road()
        let first = match.cars[0]
        for _ in 0..<3 {
            match.hitCar(0, fire: false)
            match.cars[0].guardFrames = 0
        }
        XCTAssertNotEqual(match.cars[0].id, first.id)
        XCTAssertEqual(match.cars[0].slot, 0)
        XCTAssertEqual(match.cars[0].hits, 0)
    }

    func testTheFuelTruckGoesUpOnOneHitOfFire() {
        var match = road()
        let box = match.cars[1].box
        match.cars[1] = Car(id: 77, vehicle: .fuelTruck, slot: 1, level: 0, box: box, facesLeft: false)
        match.hitCar(1, fire: false)
        XCTAssertEqual(match.cars[1].id, 77, "a plain hit only counts")
        match.cars[1].guardFrames = 0
        match.hitCar(1, fire: true)
        XCTAssertNotEqual(match.cars[1].id, 77)
    }

    func testASlashHitsACarOnceASwing() {
        var match = road()
        match.players[1].position.x = 300
        let car = match.cars[0]
        match.players[0].position = Vec2(x: car.box.min.x - 6, y: 10)
        match.players[0].facing = .right
        match.advance(inputs: [PlayerInput(shoot: true), .idle])
        for _ in 0..<SlashRules.frames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.cars.first { $0.id == car.id }?.hits, 1)
    }

    func testTheDeckCanBeJumpedUpThroughAndStoodOn() {
        var match = road()
        match.players[1].position.x = 300
        // In a gap between two slots, where no car stands.
        let gap = (match.slotCentre(0) + match.slotCentre(1)) / 2
        match.cars.removeAll { $0.level == 1 && abs($0.box.center.x - gap) < 60 }
        match.refreshExtras()
        match.players[0].position = Vec2(x: gap, y: 10)
        for frame in 0..<60 { match.advance(inputs: [PlayerInput(jump: frame % 20 < 14), .idle]) }
        for _ in 0..<60 { match.advance(inputs: [.idle, .idle]) }
        XCTAssertEqual(match.players[0].position.y, HighwayRules.deckTop, accuracy: 0.001, "up through it and standing on it")
    }

    func testTheHelicopterCarriesOneRimAcrossThenTheOther() {
        var match = road()
        match.advance(inputs: [.idle, .idle])
        let first = match.helicopter!
        let carried = match.stage.hoops[first.hoop]
        XCTAssertLessThan(carried.position.y, 200, "the carried rim is in play")
        XCTAssertEqual(match.stage.hoops[1 - first.hoop].position, HighwayRules.parked)
        var next: Helicopter?
        for _ in 0..<2000 where next == nil {
            match.advance(inputs: [.idle, .idle])
            if let flying = match.helicopter, flying.id != first.id { next = flying }
        }
        XCTAssertNotNil(next)
        XCTAssertNotEqual(next!.hoop, first.hoop, "the other side's rim next")
    }

    func testTheRoadStaysInStepAcrossTwoCopies() {
        var a = road(seed: 9), b = road(seed: 9)
        for frame in 0..<900 {
            let input = PlayerInput(stick: Vec2(x: frame % 120 < 60 ? 1 : -1, y: 0), jump: frame % 40 == 0, shoot: frame % 50 == 0)
            a.advance(inputs: [input, .idle])
            b.advance(inputs: [input, .idle])
        }
        XCTAssertEqual(a, b)
    }
}
