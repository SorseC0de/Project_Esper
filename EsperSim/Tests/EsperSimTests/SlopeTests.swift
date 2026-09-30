import XCTest
@testable import EsperSim

/// Walking, crouching and jumping on floor slopes: the pace along the surface the same as on
/// the flat, climbing in either direction, no stalls at the joins, no crouch that won't end.
final class SlopeTests: XCTestCase {
    /// A hill of six slope cells over solid fill, on a floor, with a plateau on top: rising to the
    /// right, its plateau at y 110 from x 260 to 330, or to the left, from x 280 to 350.
    private func hill(rising right: Bool) -> Match {
        var walls: [ElementsMap.Wall] = (0..<60).map { .init(.init($0, 4), .solid) }
        for i in 0..<6 {
            let column = right ? 20 + i : 40 - i
            walls.append(.init(.init(column, 5 + i), right ? .lowerRight : .lowerLeft))
            for row in 5..<(5 + i) { walls.append(.init(.init(column, row), .solid)) }
        }
        for column in (right ? 26...32 : 28...34) { for row in 5...10 { walls.append(.init(.init(column, row), .solid)) } }
        var map = ElementsMap.baked
        map.tiles = []
        map.walls = walls
        ElementsMap.current = map
        defer { ElementsMap.current = ElementsMap.baked }
        var match = Match(stage: .elements, specs: [.starting, .starting])
        match.countdown = 0
        match.players[1].position = Vec2(x: 600, y: 60)
        match.ball.respawn(at: Vec2(x: 300, y: 250))
        return match
    }

    private func walk(_ match: inout Match, stick: Vec2, frames: Int, _ each: (Player) -> Void = { _ in }) {
        for _ in 0..<frames {
            match.advance(inputs: [PlayerInput(stick: stick), .idle])
            each(match.players[0])
        }
    }

    func testAHillCanBeWalkedUpEitherWayOntoItsPlateau() {
        for right in [true, false] {
            var match = hill(rising: right)
            match.players[0].position = Vec2(x: right ? 150 : 460, y: 50)
            match.players[0].facing = right ? .right : .left
            var grounded = 0
            walk(&match, stick: Vec2(x: right ? 1 : -1, y: 0), frames: 65) { if $0.grounded { grounded += 1 } }
            XCTAssertEqual(match.players[0].position.y, 110, accuracy: 0.001, "on the plateau, going \(right ? "right" : "left")")
            XCTAssertGreaterThan(grounded, 60, "on the ground the whole way")
        }
    }

    func testThePaceAlongASlopeIsTheFlatPaceUpAndDown() {
        var flat = hill(rising: true)
        flat.players[0].position = Vec2(x: 40, y: 50)
        var last = flat.players[0].position.x, flatStep = 0.0
        walk(&flat, stick: Vec2(x: 1, y: 0), frames: 40) { flatStep = $0.position.x - last; last = $0.position.x }
        for right in [true, false] {
            var up = hill(rising: true)
            up.players[0].position = Vec2(x: right ? 150 : 295, y: right ? 50 : 110)
            up.players[0].facing = right ? .right : .left
            var previous = up.players[0].position
            var path: [Double] = []
            walk(&up, stick: Vec2(x: right ? 1 : -1, y: 0), frames: 40) {
                if $0.position.y > 52, $0.position.y < 108, $0.grounded, abs($0.position.y - previous.y) > 0.1 {
                    path.append(((($0.position.x - previous.x) * ($0.position.x - previous.x)) + (($0.position.y - previous.y) * ($0.position.y - previous.y))).squareRoot())
                }
                previous = $0.position
            }
            XCTAssertGreaterThan(path.count, 15)
            for step in path { XCTAssertEqual(step, flatStep, accuracy: 0.001, right ? "up" : "down") }
        }
    }

    func testWalkingDownASlopeStaysOnTheGround() {
        for right in [true, false] {
            var match = hill(rising: right)
            match.players[0].position = Vec2(x: right ? 295 : 315, y: 110)
            match.players[0].facing = right ? .left : .right
            var air = 0
            walk(&match, stick: Vec2(x: right ? -1 : 1, y: 0), frames: 60) { if $0.state == .air { air += 1 } }
            XCTAssertEqual(air, 0, "no hop off the surface")
            XCTAssertEqual(match.players[0].position.y, 50, accuracy: 0.001, "down to the floor")
        }
    }

    func testCrouchingOnASlopeEndsWhenReleasedAndCrouchWalksUp() {
        var match = hill(rising: true)
        match.players[0].position = Vec2(x: 205, y: 55)
        match.players[0].grounded = true
        walk(&match, stick: Vec2(x: 0, y: -1), frames: 20)
        XCTAssertEqual(match.players[0].state, .crouch)
        walk(&match, stick: .zero, frames: 30)
        XCTAssertEqual(match.players[0].state, .idle, "room to stand on a slope")
        var up = hill(rising: true)
        up.players[0].position = Vec2(x: 150, y: 50)
        walk(&up, stick: Vec2(x: 1, y: -1), frames: 90)
        XCTAssertGreaterThan(up.players[0].position.y, 60, "crouch walking up")
        XCTAssertEqual(up.players[0].state, .crouchWalk)
    }

    func testAJumpFromASlopeLandsBackOnIt() {
        var match = hill(rising: true)
        match.players[0].position = Vec2(x: 225, y: 70)
        match.players[0].grounded = true
        let surface = { (x: Double) in match.stage.slopeSurface(under: Box(min: Vec2(x: x - 5, y: 70), max: Vec2(x: x + 5, y: 87.5)), reach: 20) }
        let start = surface(225)
        XCTAssertNotNil(start)
        for frame in 0..<80 { match.advance(inputs: [PlayerInput(jump: frame < 6), .idle]) }
        let player = match.players[0]
        XCTAssertTrue(player.grounded)
        XCTAssertEqual(player.position.y, surface(player.position.x) ?? -1, accuracy: 0.001, "standing on the surface")
    }
}
