import XCTest
@testable import EsperSim

final class RecordingTests: XCTestCase {
    /// A computer game recorded, written out and read back, then played from its inputs alone,
    /// lands on the very match it did, a change made partway included.
    func testRecordingPlaysBackTheSameMatch() throws {
        for choice in [StageChoice.wreckCenter, .anozira, .flightB411] {
            var session = RollbackSession(match: Match(stage: choice.stage, specs: [.starting, .starting], countdown: 60, seed: 11), localIndex: 0)
            session.startRecording()
            var one = Opponent(index: 0, seed: 3), two = Opponent(index: 1, seed: 5)
            for frame in 0..<2400 {
                if frame == 900 { session.mutate { $0.players[0].flo = FloRules.full } }
                _ = session.tick(local: one.decide(session.match), remote: two.decide(session.match))
            }
            let data = try PropertyListEncoder.binary.encode(session.recording!)
            let recording = try PropertyListDecoder().decode(SessionRecording.self, from: data)
            XCTAssertEqual(recording.start, session.recording!.start)

            var replay = RollbackSession(match: recording.start, localIndex: 0)
            while replay.frame < recording.endFrame {
                if let changed = recording.change(at: replay.frame) { replay.mutate { $0 = changed } }
                let inputs = recording.inputs(at: replay.frame)!
                _ = replay.tick(local: inputs[0], remote: inputs[1])
            }
            XCTAssertEqual(replay.match, session.match, "\(choice) parted")
            print("[recording] \(choice): \(data.count) bytes for \(recording.inputs.count) frames")
        }
    }
}

extension PropertyListEncoder {
    static var binary: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }
}
