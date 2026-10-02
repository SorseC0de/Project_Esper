import XCTest
@testable import EsperSim

/// The computer off the court: it gets about the Elements without burning, takes the ball off the
/// Hoopfish, and scores on each stage it reads.
final class OpponentStageTests: XCTestCase {
    private struct Outcome {
        var frames: Int
        var burns = 0
        var plans: [Opponent.Plan: Int] = [:]
    }

    /// Runs with the human standing still and the computer deciding, until `stop`.
    @discardableResult
    private func play(_ match: inout Match, _ opponent: inout Opponent, frames: Int, until stop: (Match) -> Bool) -> Outcome {
        var outcome = Outcome(frames: frames)
        for frame in 0..<frames {
            let theirs = opponent.decide(match)
            match.advance(inputs: [.idle, theirs])
            outcome.plans[opponent.current, default: 0] += 1
            outcome.burns += match.events.filter { if case .lavaBurned(player: 1) = $0 { return true } else { return false } }.count
            if stop(match) {
                outcome.frames = frame
                return outcome
            }
        }
        return outcome
    }

    private func holding(_ match: inout Match, _ player: Int) {
        match.countdown = 0
        match.players[player].hasBall = true
        match.ball.holder = player
    }

    func testTheTerrainReadsEachStage() {
        for stage in [Stage.elements, .wetshot, .footballField] {
            let match = Match(stage: stage, specs: [.starting, .starting])
            let terrain = Terrain(stage: match.stage, player: match.players[1])
            var frames = 0
            while !terrain.ready {
                terrain.prepare(budget: Opponent.readingBudget)
                frames += 1
            }
            XCTAssertFalse(terrain.surfaces.isEmpty)
            XCTAssertGreaterThan(terrain.rise, 30)
            // Read over the countdown, not the match.
            XCTAssertLessThan(frames, 60, "\(stage.features.look)")
        }
    }

    func testOnTheElementsTheWayDownToItsRimRunsThroughTheTornados() {
        let match = Match(stage: .elements, specs: [.starting, .starting])
        let terrain = Terrain(stage: match.stage, player: match.players[1])
        while !terrain.ready { terrain.prepare(budget: Opponent.readingBudget) }
        let room = terrain.surface(under: Vec2(x: 200, y: 150))!, platform = terrain.surface(under: Vec2(x: 60, y: 100))!
        let way = terrain.route(from: room, to: platform) { _, _ in true }
        XCTAssertNotNil(way)
        XCTAssertTrue(way!.contains { terrain.surfaces[$0.to].tornado != nil })
    }

    func testOnTheElementsWithTheBallItScoresWithoutBurning() {
        var match = Match(stage: .elements, specs: [.starting, .starting])
        var brain = Opponent(index: 1)
        holding(&match, 1)
        let outcome = play(&match, &brain, frames: 3600) { $0.scores[1] > 0 }
        XCTAssertLessThan(outcome.frames, 3600)
        XCTAssertEqual(outcome.burns, 0)
    }

    func testOnTheElementsItFetchesTheLooseBallWithoutBurning() {
        var match = Match(stage: .elements, specs: [.starting, .starting])
        match.countdown = 0
        var brain = Opponent(index: 1)
        let outcome = play(&match, &brain, frames: 2400) { $0.ball.holder == 1 }
        XCTAssertLessThan(outcome.frames, 2400)
        XCTAssertEqual(outcome.burns, 0)
    }

    func testOnLongballWithTheBallItScores() {
        var match = Match(stage: .footballField, specs: [.starting, .starting])
        var brain = Opponent(index: 1)
        holding(&match, 1)
        match.players[0].position = Vec2(x: match.stage.width - 66, y: 10)
        let outcome = play(&match, &brain, frames: 4800) { $0.scores[1] > 0 }
        XCTAssertLessThan(outcome.frames, 4800)
    }

    func testOnWetshotItTakesTheBallOffTheHoopfishThenScores() {
        var match = Match(stage: .wetshot, specs: [.starting, .starting])
        match.countdown = 0
        var brain = Opponent(index: 1)
        let fetched = play(&match, &brain, frames: 3600) { $0.ball.holder == 1 }
        XCTAssertLessThan(fetched.frames, 3600)
        let scored = play(&match, &brain, frames: 3600) { $0.scores[1] > 0 }
        XCTAssertLessThan(scored.frames, 3600)
    }
}

final class OpponentDuelTests: XCTestCase {
    /// Two computers against each other on each stage it reads, three pairings: points go in, and
    /// the lava takes nobody who wasn't knocked into it.
    func testTwoComputersPlayEachStage() {
        // Longball's field takes a few minutes a point; its attack is tested on its own.
        for stage in [Stage.elements, .wetshot] {
            var points = 0, unforced = 0
            for pairing in 0..<3 {
                var match = Match(stage: stage, specs: [.starting, .starting])
                match.countdown = 0
                var brains = [Opponent(index: 0, seed: UInt32(3 + pairing * 4)), Opponent(index: 1, seed: UInt32(7 + pairing * 4))]
                var knocked = [false, false]
                for _ in 0..<5400 {
                    let inputs = [brains[0].decide(match), brains[1].decide(match)]
                    // Hit lately, it's flying where the hit sent it: a burn from that is the other's doing.
                    for player in 0..<2 {
                        if match.players[player].hitStun > 0 || match.players[player].knockedAloft { knocked[player] = true }
                        if match.players[player].grounded { knocked[player] = false }
                    }
                    match.advance(inputs: inputs)
                    for event in match.events { if case .lavaBurned(let player) = event, !knocked[player] { unforced += 1 } }
                    if match.finished { break }
                }
                points += match.scores.reduce(0, +)
            }
            XCTAssertGreaterThan(points, 0, "\(stage.features.look)")
            XCTAssertLessThanOrEqual(unforced, 2, "\(stage.features.look)")
        }
    }
}
