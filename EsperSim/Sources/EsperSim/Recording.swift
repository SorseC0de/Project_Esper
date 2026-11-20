import Foundation

/// A session as it was played: the match it started from, every change made to it from outside
/// the inputs, and both sides' inputs frame by frame. Played back on the build it was made on,
/// the sim runs the same match again.
public struct SessionRecording: Codable {
    public var start: Match
    public var changes: [Change] = []
    /// Each frame's inputs from the start's frame on, player one's first.
    public var inputs: [[PlayerInput]] = []

    /// The match as a change left it, before the frame it was made on ran.
    public struct Change: Codable {
        public var frame: Int
        public var match: Match
    }

    public init(start: Match) {
        self.start = start
    }

    /// The frame after the last one recorded.
    public var endFrame: Int { start.frame + inputs.count }

    /// The inputs the frame ran with, none past the end.
    public func inputs(at frame: Int) -> [PlayerInput]? {
        let index = frame - start.frame
        return inputs.indices.contains(index) ? inputs[index] : nil
    }

    /// The last change made at the frame, which leaves the match as every change on it did.
    public func change(at frame: Int) -> Match? {
        changes.last { $0.frame == frame }?.match
    }
}

