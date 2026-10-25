import QuartzCore
/// The instruments for working on the game: the tuning panels, the pickers and sliders over
/// the pad, the HITBOX, WALLS and AI switches, the title's colour grids and the readouts.
/// A debug build has them; a Release build, the testers', has none.
enum DebugUI {
    #if DEBUG
    static let enabled = true
    #else
    static let enabled = false
    #endif
}

/// A probe for the stall on the stage select: the way from it into a match, each step printed
/// as "[LOAD]" with the milliseconds since the select came up, and any frame longer than
/// `longFrame` seconds, with what was showing. Out once the stall's found.
enum LoadTrace {
    nonisolated(unsafe) private static var start: Double?
    static let longFrame = 0.1
    static func begin(_ step: String) {
        start = CACurrentMediaTime()
        mark(step)
    }
    /// A step printed only when it's not the last one noted: what the select's waiting on, frame by frame.
    nonisolated(unsafe) private static var lastNote = ""
    static func note(_ step: String) {
        guard step != lastNote else { return }
        lastNote = step
        mark(step)
    }
    static func mark(_ step: String) {
        guard DebugUI.enabled, let start else { return }
        print(String(format: "[LOAD] %6.0f ms  %@", (CACurrentMediaTime() - start) * 1000, step))
    }
}
