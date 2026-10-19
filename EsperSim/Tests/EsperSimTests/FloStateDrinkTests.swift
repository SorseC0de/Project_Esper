import XCTest
@testable import EsperSim

/// 47's picked drink: dormant till FloState, at its second level there, gone again after.
final class FloStateDrinkTests: XCTestCase {
    func testThePickedDrinkWakesWithFloStateAndSleepsAfter() {
        var match = Match(countdown: 0)
        match.players[0].floStateDrink = .galeAle
        let run = match.players[0].spec.runSpeed
        XCTAssertEqual(match.players[0].power, .none, "dormant before FloState")
        match.players[0].flo = FloRules.full
        match.players[0].enter(.transforming)
        for _ in 0...TransformRules.frames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertTrue(match.players[0].inFloState)
        XCTAssertEqual(match.players[0].power, .galeAle)
        XCTAssertEqual(match.players[0].powerLevel, 2)
        match.players[0].leaveFloState()
        XCTAssertEqual(match.players[0].power, .none)
        XCTAssertEqual(match.players[0].spec.runSpeed, run, accuracy: 0.0001)
    }

    func testABoosterPickedChangesTheBodyOnlyInFloState() {
        var match = Match(countdown: 0)
        match.players[0].floStateDrink = .hastyHorchata
        let run = match.players[0].spec.runSpeed
        match.players[0].flo = FloRules.full
        match.players[0].enter(.transforming)
        for _ in 0...TransformRules.frames { match.advance(inputs: [.idle, .idle]) }
        XCTAssertGreaterThan(match.players[0].spec.runSpeed, run)
        match.players[0].leaveFloState()
        XCTAssertEqual(match.players[0].spec.runSpeed, run, accuracy: 0.0001)
    }
}
