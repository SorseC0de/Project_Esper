import XCTest
@testable import EsperSim

final class NetTests: XCTestCase {
    private func inputFor(_ frame: Int, player: Int) -> PlayerInput {
        // A busy, deterministic pattern: runs, jumps and shots at different times a side.
        let phase = (frame + player * 37) % 90
        var input = PlayerInput(stick: Vec2(x: phase < 45 ? 1 : -0.6, y: phase % 30 < 5 ? -1 : 0))
        input.jump = phase % 20 < 6
        input.shoot = phase % 33 == 0
        input.throwBall = phase % 41 == 0
        input.aim = Vec2(x: 0.5, y: 0.7)
        return input
    }

    func testInputsSurviveTheWire() {
        for frame in 0..<200 {
            let input = inputFor(frame, player: frame % 2).quantized
            var data = Data()
            input.encode(into: &data)
            XCTAssertEqual(PlayerInput.decode([UInt8](data), at: 0), input)
        }
        let odd = PlayerInput(stick: Vec2(x: 0.123, y: -0.987), aim: Vec2(x: -1, y: 0.5), jump: true, shootButtons: 5, throwBall: true, taunt: true)
        var data = Data()
        odd.quantized.encode(into: &data)
        XCTAssertEqual(PlayerInput.decode([UInt8](data), at: 0), odd.quantized)
        XCTAssertEqual(odd.quantized.stick.x, 0.123, accuracy: 0.01)
    }

    func testMessagesSurviveTheWire() {
        let packet = InputPacket(frame: 1234, advantage: -3, firstFrame: 1229, inputs: (0..<8).map { inputFor($0, player: 0).quantized },
                                 knownThrough: 1230, checkFrame: 1200, checksum: 0xDEADBEEF)
        let messages: [NetMessage] = [.hello(random: 0xCAFEBABE, version: 2, colour: 4), .inputs(packet), .pick(round: 3, choice: 2), .rematch(random: 7), .bye]
        for message in messages {
            XCTAssertEqual(NetMessage(data: message.data), message)
        }
        XCTAssertNil(NetMessage(data: Data([9, 9])))
        XCTAssertNil(NetMessage(data: Data()))
    }

    /// Two sessions joined by a lossy, laggy link end on the same match as a plain run of
    /// the same inputs, whatever the link did.
    func testTwoSidesConvergeOverALossyLink() {
        struct Link {
            var latency: Int
            var loss: Int
            var queue: [(deliverAt: Int, packet: InputPacket)] = []
            var dice = Dice(seed: 11)

            mutating func send(_ packet: InputPacket, at frame: Int) {
                if dice.roll(100) < loss { return }
                let jitter = dice.roll(3)
                queue.append((frame + latency + jitter, packet))
            }

            mutating func deliver(at frame: Int) -> [InputPacket] {
                let ready = queue.filter { $0.deliverAt <= frame }.map(\.packet)
                queue.removeAll { $0.deliverAt <= frame }
                return ready
            }
        }

        for (latency, loss) in [(0, 0), (3, 0), (5, 20), (8, 40), (2, 60)] {
            var a = RollbackSession(match: Match(countdown: 30), localIndex: 0, delay: NetRules.inputDelay)
            var b = RollbackSession(match: Match(countdown: 30), localIndex: 1, delay: NetRules.inputDelay)
            var toB = Link(latency: latency, loss: loss)
            var toA = Link(latency: latency, loss: loss)
            let frames = 600
            var clock = 0
            // Each side's input is a function of the frame it's for, so a tick that doesn't
            // run its frame offers the same input again and the plain run below can match it.
            while min(a.frame, b.frame) < frames {
                for packet in toA.deliver(at: clock) { a.receive(packet) }
                for packet in toB.deliver(at: clock) { b.receive(packet) }
                if a.frame < frames + 30 {
                    _ = a.tick(local: inputFor(a.frame, player: 0))
                    toB.send(a.outgoing(), at: clock)
                }
                if b.frame < frames + 30 {
                    _ = b.tick(local: inputFor(b.frame, player: 1))
                    toA.send(b.outgoing(), at: clock)
                }
                clock += 1
                guard clock < frames * 20 else {
                    XCTFail("the link stalled the sessions for good at latency \(latency) loss \(loss)")
                    break
                }
            }
            // Let the last inputs cross.
            for _ in 0..<(latency + 20) {
                for packet in toA.deliver(at: clock) { a.receive(packet) }
                for packet in toB.deliver(at: clock) { b.receive(packet) }
                clock += 1
            }
            let through = min(a.confirmedFrame, b.confirmedFrame)
            XCTAssertGreaterThanOrEqual(through, frames - 1, "latency \(latency) loss \(loss)")
            XCTAssertFalse(a.desynced)
            XCTAssertFalse(b.desynced)

            // The same inputs run plainly, frame by frame, as each side saw them delayed.
            var plain = Match(countdown: 30)
            for at in 0...through {
                let aInput = at >= NetRules.inputDelay ? inputFor(at - NetRules.inputDelay, player: 0).quantized : .idle
                let bInput = at >= NetRules.inputDelay ? inputFor(at - NetRules.inputDelay, player: 1).quantized : .idle
                plain.advance(inputs: [aInput, bInput])
            }
            // Each side's state before frame `through + 1` is the plain one: compare checksums
            // through the packet's own channel, and the frames themselves.
            XCTAssertEqual(plain.frame, through + 1)
            let aState = a.stateBefore(through + 1), bState = b.stateBefore(through + 1)
            XCTAssertNotNil(aState, "latency \(latency) loss \(loss)")
            XCTAssertNotNil(bState, "latency \(latency) loss \(loss)")
            if let aState, let bState {
                XCTAssertEqual(aState.checksum, plain.checksum, "side A split from the plain run at latency \(latency) loss \(loss)")
                XCTAssertEqual(bState.checksum, plain.checksum, "side B split from the plain run at latency \(latency) loss \(loss)")
                XCTAssertEqual(aState.players, plain.players)
                XCTAssertEqual(bState.ball, plain.ball)
            }
            if latency > 0 { XCTAssertGreaterThan(a.rollbacks + b.rollbacks, 0, "a laggy link should have rolled back at least once") }
        }
    }

    func testAFrameRunAgainOnlyShowsItsNewEvents() {
        // Side B's remote (A) is predicted idle; A really jumped, so A's jump shows once B hears.
        var b = RollbackSession(match: Match(), localIndex: 1, delay: 0)
        var shown: [FrameEvents] = []
        for _ in 0..<6 {
            shown += b.tick(local: .idle).shown
        }
        XCTAssertTrue(shown.flatMap(\.events).isEmpty)
        // A's inputs arrive: jump held from frame 0.
        let jump = PlayerInput(jump: true).quantized
        b.receive(InputPacket(frame: 6, advantage: 0, firstFrame: 0, inputs: Array(repeating: jump, count: 8)))
        let after = b.tick(local: .idle)
        let jumps = after.shown.flatMap(\.events).filter { $0 == .jumped(player: 0) }
        XCTAssertEqual(jumps.count, 1, "the jump shows once, from the frame run again")
        XCTAssertEqual(b.rollbacks, 1)
        // Run again with the same inputs, nothing new shows.
        b.receive(InputPacket(frame: 7, advantage: 0, firstFrame: 0, inputs: Array(repeating: jump, count: 8)))
        XCTAssertEqual(b.rollbacks, 1)
    }

    func testTheSimWaitsAtTheWindowAndAtTheStop() {
        var a = RollbackSession(match: Match(), localIndex: 0, delay: 2)
        for _ in 0..<40 { _ = a.tick(local: .idle) }
        XCTAssertEqual(a.frame, NetRules.predictionWindow, "runs the window past the last remote input, then waits")
        a.receive(InputPacket(frame: 100, advantage: 0, firstFrame: 0, inputs: Array(repeating: .idle, count: 100)))
        a.stopAt = 50
        for _ in 0..<80 { _ = a.tick(local: .idle) }
        XCTAssertEqual(a.frame, 50)
        XCTAssertTrue(a.settled)
        a.stopAt = nil
        _ = a.tick(local: .idle)
        XCTAssertEqual(a.frame, 51)
    }

    func testConfirmedEventsComeOnceBothSidesInputsAreIn() {
        var a = RollbackSession(match: Match(), localIndex: 0, delay: 0)
        var confirmed: [FrameEvents] = []
        var shown: [FrameEvents] = []
        for _ in 0..<5 {
            let tick = a.tick(local: PlayerInput(jump: true))
            shown += tick.shown
            confirmed += tick.confirmed
        }
        XCTAssertFalse(shown.flatMap(\.events).isEmpty)
        XCTAssertTrue(confirmed.isEmpty, "nothing is confirmed without the other side's inputs")
        a.receive(InputPacket(frame: 5, advantage: 0, firstFrame: 0, inputs: Array(repeating: .idle, count: 8)))
        let tick = a.tick(local: .idle)
        XCTAssertEqual(tick.confirmed.flatMap(\.events).filter { $0 == .jumped(player: 0) }.count, 1)
        // Offline, with the other side's input handed in, everything confirms at once.
        var solo = RollbackSession(match: Match(), localIndex: 0)
        let first = solo.tick(local: PlayerInput(jump: true), remote: .idle)
        XCTAssertEqual(first.shown, first.confirmed)
        XCTAssertTrue(solo.settled)
    }

    func testMatchChecksumSeesAChange() {
        var one = Match(), two = Match()
        one.advance(inputs: [PlayerInput(jump: true), .idle])
        two.advance(inputs: [.idle, .idle])
        XCTAssertNotEqual(one.checksum, two.checksum)
        var same = Match()
        same.advance(inputs: [.idle, .idle])
        XCTAssertEqual(same.checksum, two.checksum)
    }
}

extension RollbackSession {
    /// The match before `frame` was run, from the snapshots, for the tests.
    func stateBefore(_ at: Int) -> Match? {
        if at == frame { return match }
        return snapshotForTesting(at)
    }
}
