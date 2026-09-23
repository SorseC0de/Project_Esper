import Foundation

/// The events of one frame, as the sim last ran it.
public struct FrameEvents: Equatable {
    public var frame: Int
    public var events: [MatchEvent]
}

/// What one tick of the session gave the screen: whether the sim moved, the events to
/// show (those of frames run for the first time, and anything new in a frame run again
/// after a rollback), and the events of frames now confirmed by both sides' inputs, for
/// anything that must never be undone, a point most of all.
public struct SessionTick {
    public var advanced = false
    public var shown: [FrameEvents] = []
    public var confirmed: [FrameEvents] = []
}

/// One side of a match run in lockstep with rollback: the same `Match` on both phones,
/// inputs exchanged by frame. Each frame runs as soon as the local input is known, with
/// the remote's predicted as held where it hasn't arrived; when it arrives different, the
/// sim rolls back to that frame and runs forward again. Offline it's the same session
/// with the other side's input handed in each tick, so there is one code path.
public struct RollbackSession {
    public let localIndex: Int
    public var remoteIndex: Int { 1 - localIndex }
    public let delay: Int
    public let window: Int
    /// The match as it is now, predictions and all.
    public private(set) var match: Match
    /// Frames run so far; the next to run.
    public private(set) var frame = 0
    /// The last frame run with both sides' real inputs; nothing before it can change.
    public private(set) var confirmedFrame = -1
    /// The sim won't run this frame or past it, so both sides stop on the same one.
    public var stopAt: Int?
    /// The remote's newest frame heard of, and how far ahead it says it is.
    public private(set) var remoteFrame = -1
    private var remoteAdvantage = 0
    private var stall = 0
    /// How many rollbacks, and frames run again, for the corner readout.
    public private(set) var rollbacks = 0
    public private(set) var framesRerun = 0
    /// True once a checksum from the other side disagreed with the same frame here.
    public private(set) var desynced = false

    private var localInputs: [PlayerInput] = []
    private var remoteInputs: [PlayerInput?] = []
    private var remoteKnownThrough = -1
    /// The last local frame the other side says it holds every input through.
    private var ackedThrough = -1
    /// The remote input each frame was last run with, real or predicted.
    private var usedRemote: [Int: PlayerInput] = [:]
    /// The match before each frame was run, for frames that could still be run again.
    private var snapshots: [Int: Match] = [:]
    private var eventsByFrame: [Int: [MatchEvent]] = [:]
    private var pendingShown: [FrameEvents] = []
    private var confirmedHandedOut = -1

    public init(match: Match, localIndex: Int, delay: Int = 0, window: Int = NetRules.predictionWindow) {
        self.match = match
        self.localIndex = localIndex
        self.delay = delay
        self.window = window
        frame = match.frame
        confirmedFrame = frame - 1
        confirmedHandedOut = frame - 1
        remoteKnownThrough = frame - 1
        for _ in 0..<frame {
            localInputs.append(.idle)
            remoteInputs.append(.idle)
        }
    }

    // MARK: Running

    /// One tick: the local input for the frame `delay` ahead, the remote's for this frame
    /// when it's local too, and the frame run if it can be. A frame's local input is set
    /// the first time that frame is reached and never again, since it may already have
    /// gone over the wire; a tick that doesn't run the frame drops its sample.
    public mutating func tick(local: PlayerInput, remote: PlayerInput? = nil) -> SessionTick {
        var tick = SessionTick()
        if localInputs.count <= frame + delay {
            setLocal(local.quantized, at: frame + delay)
        }
        if let remote {
            setRemote(remote.quantized, at: frame)
            remoteFrame = frame
        }
        tick.shown = pendingShown
        pendingShown = []
        if canRun(remoteGiven: remote != nil) {
            run(frame, shown: &tick.shown)
            tick.advanced = true
        }
        tick.confirmed = takeConfirmed()
        return tick
    }

    /// Whether this frame can run now: not held at a stop, not too far past the last remote
    /// input, and not ahead of the other side by more than they are of us, in which case
    /// half the gap is held back.
    private mutating func canRun(remoteGiven: Bool) -> Bool {
        if stall > 0 {
            stall -= 1
            return false
        }
        if let stopAt, frame >= stopAt { return false }
        guard frame - remoteKnownThrough <= window else { return false }
        if !remoteGiven, frame % NetRules.syncEveryFrames == 0, remoteFrame >= 0 {
            let lead = ((frame - remoteFrame) - remoteAdvantage) / 2
            if lead > 1 {
                stall = min(lead, NetRules.syncMaxStall)
                return false
            }
        }
        return true
    }

    /// The remote's inputs off the wire. Any that differ from what a frame was run with
    /// roll the sim back to that frame and run it forward again.
    public mutating func receive(_ packet: InputPacket) {
        remoteFrame = max(remoteFrame, packet.frame)
        remoteAdvantage = packet.advantage
        ackedThrough = max(ackedThrough, packet.knownThrough)
        var earliestChanged: Int?
        for (offset, input) in packet.inputs.enumerated() {
            let at = packet.firstFrame + offset
            guard at >= 0, at >= remoteInputs.count || remoteInputs[at] == nil else { continue }
            setRemote(input, at: at)
            if at < frame, let used = usedRemote[at], used != input {
                earliestChanged = min(earliestChanged ?? at, at)
            }
        }
        if let earliestChanged { rollback(to: earliestChanged) }
        updateConfirmed()
        // The other side's state before a frame both sides have every input for should be ours.
        if packet.checkFrame >= 0, packet.checkFrame - 1 <= confirmedFrame,
           let mine = snapshots[packet.checkFrame], mine.checksum != packet.checksum {
            desynced = true
        }
    }

    /// Every local input the other side hasn't acknowledged, and the newest few anyway,
    /// with where the sim is, the lead, what's held of theirs, and the checksum of the
    /// state before the last confirmed frame.
    public func outgoing() -> InputPacket {
        let last = min(frame + delay, localInputs.count - 1)
        var first = min(ackedThrough + 1, last - NetRules.redundantInputs + 1)
        first = max(first, last - NetRules.maxInputsPerPacket + 1, 0)
        let inputs = last >= first ? (first...last).map { localInputs[$0] } : []
        let checkFrame = confirmedFrame
        let checksum = snapshots[checkFrame]?.checksum ?? 0
        return InputPacket(frame: frame, advantage: frame - remoteFrame, firstFrame: first, inputs: inputs,
                           knownThrough: remoteKnownThrough,
                           checkFrame: snapshots[checkFrame] == nil ? -1 : checkFrame, checksum: checksum)
    }

    /// A change to the match from outside the inputs, a drink between rounds or a fresh
    /// count, made only once every frame before this one is confirmed, so it can't be
    /// undone by a rollback; both sides make the same change on the same frame.
    public mutating func mutate(_ change: (inout Match) -> Void) {
        change(&match)
        snapshots = [:]
        usedRemote = [:]
    }

    /// Every frame before the next one is known on both sides.
    public var settled: Bool { confirmedFrame >= frame - 1 }

    // MARK: Inside

    private mutating func setLocal(_ input: PlayerInput, at at: Int) {
        while localInputs.count <= at { localInputs.append(.idle) }
        localInputs[at] = input
    }

    private mutating func setRemote(_ input: PlayerInput, at at: Int) {
        while remoteInputs.count <= at { remoteInputs.append(nil) }
        remoteInputs[at] = input
        while remoteKnownThrough + 1 < remoteInputs.count, remoteInputs[remoteKnownThrough + 1] != nil {
            remoteKnownThrough += 1
        }
    }

    private var lastKnownRemote: PlayerInput {
        remoteKnownThrough >= 0 ? remoteInputs[remoteKnownThrough] ?? .idle : .idle
    }

    private mutating func run(_ at: Int, shown: inout [FrameEvents]) {
        snapshots[at] = match
        let remote = at < remoteInputs.count ? remoteInputs[at] ?? lastKnownRemote : lastKnownRemote
        usedRemote[at] = remote
        var inputs = [PlayerInput](repeating: .idle, count: match.players.count)
        if localIndex < inputs.count { inputs[localIndex] = at < localInputs.count ? localInputs[at] : .idle }
        if remoteIndex < inputs.count { inputs[remoteIndex] = remote }
        match.advance(inputs: inputs)
        let events = match.events
        if let before = eventsByFrame[at] {
            let fresh = RollbackSession.difference(events, before)
            if !fresh.isEmpty { shown.append(FrameEvents(frame: at, events: fresh)) }
        } else if !events.isEmpty {
            shown.append(FrameEvents(frame: at, events: events))
        }
        eventsByFrame[at] = events
        frame = at + 1
        updateConfirmed()
    }

    private mutating func rollback(to at: Int) {
        guard let saved = snapshots[at] else { return }
        let target = frame
        rollbacks += 1
        framesRerun += target - at
        match = saved
        frame = at
        var shown: [FrameEvents] = []
        for again in at..<target {
            run(again, shown: &shown)
        }
        pendingShown += shown
    }

    private mutating func updateConfirmed() {
        confirmedFrame = min(frame - 1, remoteKnownThrough)
        for old in snapshots.keys where old < confirmedFrame { snapshots[old] = nil }
        for old in usedRemote.keys where old < confirmedFrame { usedRemote[old] = nil }
    }

    private mutating func takeConfirmed() -> [FrameEvents] {
        guard confirmedFrame > confirmedHandedOut else { return [] }
        var handed: [FrameEvents] = []
        for at in (confirmedHandedOut + 1)...confirmedFrame {
            if let events = eventsByFrame[at], !events.isEmpty {
                handed.append(FrameEvents(frame: at, events: events))
            }
            eventsByFrame[at] = nil
        }
        confirmedHandedOut = confirmedFrame
        return handed
    }

    func snapshotForTesting(_ at: Int) -> Match? { snapshots[at] }

    /// The events in `now` that weren't in `before`, as a multiset.
    static func difference(_ now: [MatchEvent], _ before: [MatchEvent]) -> [MatchEvent] {
        var remaining = before
        var fresh: [MatchEvent] = []
        for event in now {
            if let index = remaining.firstIndex(of: event) {
                remaining.remove(at: index)
            } else {
                fresh.append(event)
            }
        }
        return fresh
    }
}
