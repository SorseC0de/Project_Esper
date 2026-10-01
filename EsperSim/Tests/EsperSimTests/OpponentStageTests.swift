import XCTest
@testable import EsperSim

/// The computer off the court: it gets about the Elements without burning, takes the ball off the
/// Hooperfish, and scores on each stage it reads.
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

    func testOnWetshotItTakesTheBallOffTheHooperfishThenScores() {
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
    /// Two computers against each other a minute and a half on each stage it reads: points go in,
    /// and the lava takes hardly anyone.
    func testTwoComputersPlayEachStage() {
        // Longball's field takes a few minutes a point; its attack is tested on its own.
        for stage in [Stage.elements, .wetshot] {
            var match = Match(stage: stage, specs: [.starting, .starting])
            match.countdown = 0
            var brains = [Opponent(index: 0, seed: 3), Opponent(index: 1, seed: 7)]
            var burns = [0, 0]
            for _ in 0..<5400 {
                let inputs = [brains[0].decide(match), brains[1].decide(match)]
                match.advance(inputs: inputs)
                for event in match.events { if case .lavaBurned(let player) = event { burns[player] += 1 } }
                if match.finished { break }
            }
            XCTAssertGreaterThan(match.scores.reduce(0, +), 0, "\(stage.features.look)")
            // Knocked off a tornado by the other's swing is fair; walking or jumping into the lava isn't.
            XCTAssertLessThanOrEqual(burns.reduce(0, +), 2, "\(stage.features.look)")
        }
    }
}
