import Darwin
import Foundation
import os
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
    /// Timed from launch until the first `begin`.
    nonisolated(unsafe) private static let launched = CACurrentMediaTime()
    /// In Release too, as `MemoryTrace` is, so a launch can be timed as testers get it.
    static func mark(_ step: String) {
        print(String(format: "[LOAD] %6.0f ms  %4d MB  %@", (CACurrentMediaTime() - (start ?? launched)) * 1000, MemoryTrace.footprint, step))
    }
}

/// The app's memory in the console, `[MEM]`, as the system counts it against the limit that ends the
/// app without a crash log: at launch, then each time it's moved `step` MB, with what was showing and
/// how many textures the sprite library holds. In Release too, as the TV scheme runs; out once the
/// leak's found.
enum MemoryTrace {
    static let step = 25
    nonisolated(unsafe) private static var lastPrinted: Int?
    /// What was showing at the main thread's last check, for the sampler's lines.
    nonisolated(unsafe) private static var lastShowing = "launch"
    private static let lock = NSLock()
    /// Sampled off the main thread too, `samplesPerSecond`, so a climb while the main thread's
    /// held (a rebuild, a lock-in) still prints before the system ends the app.
    static let samplesPerSecond = 10
    nonisolated(unsafe) private static var sampler: DispatchSourceTimer?
    static func startSampling() {
        guard sampler == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "MemoryTrace", qos: .utility))
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(samplesPerSecond))
        timer.setEventHandler {
            lock.lock()
            let showing = lastShowing
            lock.unlock()
            report(footprint, "sampler, last seen " + showing)
        }
        timer.resume()
        sampler = timer
    }

    /// The footprint the system holds against the app, in MB.
    static var footprint: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    /// Printed if it's moved `step` MB since the last print.
    static func check(_ showing: @autoclosure () -> String, breakdown: () -> String) {
        let shown = showing()
        lock.lock()
        // A new screen gets the whole breakdown, however little it's moved, so each step through the flow is counted.
        let screenChanged = shown.split(separator: ",").first != lastShowing.split(separator: ",").first
        lastShowing = shown
        if screenChanged { lastPrinted = nil }
        lock.unlock()
        if report(footprint, shown) { print("[MEM]   \(breakdown())") }
    }

    /// Printed if it's moved `step` MB since the last print, from either thread; whether it was.
    @discardableResult
    private static func report(_ now: Int, _ showing: String) -> Bool {
        lock.lock()
        let moved = lastPrinted.map { abs(now - $0) >= step } ?? true
        if moved { lastPrinted = now }
        lock.unlock()
        guard moved else { return false }
        print("[MEM] \(now) MB, \(os_proc_available_memory() / 1_048_576) MB left, \(showing)")
        return true
    }
}
