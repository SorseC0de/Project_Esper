import EsperSim
import Foundation
import QuartzCore
import SpriteKit
import UIKit

/// Footage capture: launched with `debug.footage` set in the defaults (or
/// `-footage` as an argument) to a plan, the scenes in `FootageScenes` are played one after another,
/// each recorded to its own video (`FootageRecorder`) with a log of its events beside it, in the
/// app's temporary folder, `Footage/`, and a `done` file once the last is over. The plan is `all`,
/// `scripted`, `cpu`, or a comma-separated list of words a scene's name must contain.
@MainActor
final class FootageRun {
    static let defaultsKey = "debug.footage"
    /// Release builds too: a launch argument or a stored default nobody sets by accident, and the
    /// optimised build is what keeps the recording at 60.
    static var requested: Bool { plan != nil && !over }
    /// The run under way, for the sound board's log.
    private(set) static weak var active: FootageRun?
    /// Once a run's done: no second one from the same launch argument, and the app quits.
    private(set) static var over = false
    static var plan: String? {
        if let argument = ProcessInfo.processInfo.arguments.firstIndex(of: "-footage"), ProcessInfo.processInfo.arguments.indices.contains(argument + 1) {
            return ProcessInfo.processInfo.arguments[argument + 1]
        }
        return UserDefaults.standard.string(forKey: defaultsKey)
    }
    /// The video's size: 1080p, as the TV draws, whatever the window; or `-footageSize WxH`, framed
    /// as a screen of that shape frames it (1440x1080, an iPad's).
    nonisolated static let videoSize: CGSize = {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-footageSize"), arguments.indices.contains(index + 1) {
            let sides = arguments[index + 1].split(separator: "x").compactMap { Double($0) }
            if sides.count == 2 { return CGSize(width: sides[0], height: sides[1]) }
        }
        return CGSize(width: 1920, height: 1080)
    }()
    /// Frames the view holds on a scripted scene's end, and on a game's win screen, before the next.
    static let scriptedTail = 60
    static let wonTail = 300

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Footage", isDirectory: true)
    let scenes: [FootageScene]
    var index = -1
    var director = FootageDirector()
    /// Frames the scene has run, drawn frames for a computer game, sim frames for a scripted one.
    var frames = 0
    /// Frames left before the next scene, once this one's done.
    var ending: Int?
    /// The drink pick: frames it's been up, and whether the scene's drink has been taken.
    var pickFrames = 0
    var picked = false
    /// Frames between the drink pick's cursor moves.
    static let pickBeat = 45
    /// The screens' ground in the video, as the HUD's view lays it on the screen: frames it fades
    /// in over, the blur's reach in video pixels, and the wash's darkness.
    nonisolated static let veilFrames = 15.0
    nonisolated static let veilBlur = 12.0
    nonisolated static let veilWash = 0.45
    var recorder: FootageRecorder?
    private var log: FileHandle?
    private let captureModeWas: Bool
    /// The drawing's clock: a sixtieth on for every frame drawn, so everything drawn by time keeps
    /// step with the sim, which steps once a frame, however slowly the frames come.
    private var clock = CACurrentMediaTime()

    func tick() -> CFTimeInterval {
        clock += 1.0 / 60
        return clock
    }

    var current: FootageScene? { scenes.indices.contains(index) ? scenes[index] : nil }

    /// The file names of the scene at `index`, its video and its log.
    func fileName(at index: Int) -> String { String(format: "%02d_%@", index, scenes[index].name) }

    /// Whether the scene at `index` was recorded whole by an earlier launch: its video closed, which
    /// leaves the `.ok` file beside it (a crash leaves a video without one).
    func recorded(at index: Int) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName(at: index) + ".ok").path)
    }

    init() {
        let plan = FootageRun.plan ?? "all"
        var picked: [FootageScene] = []
        switch plan {
        case "all": picked = FootageScenes.scripted + FootageScenes.cpuMatches
        case "scripted": picked = FootageScenes.scripted
        case "cpu": picked = FootageScenes.cpuMatches
        default:
            let words = plan.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            picked = (FootageScenes.scripted + FootageScenes.cpuMatches + FootageScenes.previewStills).filter { scene in words.contains { scene.name.contains($0) } }
        }
        scenes = picked
        captureModeWas = UserDefaults.standard.bool(forKey: GameScene.captureModeKey)
        // The folder's kept: a relaunch after a crash carries on past the scenes already recorded.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSLog("[FOOTAGE] %d scenes to %@", scenes.count, folder.path)
        FootageRun.active = self
    }

    /// The scene's inputs for a sim frame, nil for a side the computer plays; what the scene holds in
    /// place applied to the match first.
    func inputs(match: Match, mutate: ((inout Match) -> Void) -> Void) -> [PlayerInput?] {
        guard let scene = current, !scene.cpuMatch else { return [nil, nil] }
        // The tail after the scene's moment: the computer's, playing on to the cut.
        guard ending == nil else { return [nil, nil] }
        if let eachFrame = scene.eachFrame { mutate(eachFrame) }
        var asked = scene.step(&director, match)
        while asked.count < 2 { asked.append(nil) }
        director.tick()
        frames += 1
        return asked
    }

    /// Whether the scene has shown what it's for.
    func sceneDone(won: Bool, match: Match) -> Bool {
        guard let scene = current, ending == nil else { return false }
        if scene.cpuMatch { return won || frames >= scene.maxFrames }
        return director.finished || scene.done(director, match) || frames >= scene.maxFrames
    }

    /// A sound the board plays, at the video's time, for the mix.
    func logSound(_ name: String, volume: Float, pan: Float) {
        guard let log, let recorder else { return }
        let line = "{\"sound\": \"\(name)\", \"t\": \(String(format: "%.3f", recorder.videoTime)), \"volume\": \(String(format: "%.2f", volume)), \"pan\": \(String(format: "%.2f", pan))}\n"
        if let data = line.data(using: .utf8) { log.write(data) }
    }

    /// A looping sound begun on a loop voice, or that voice's loop ended.
    func logLoop(_ name: String, key: Int, volume: Float, on: Bool) {
        guard let log, let recorder else { return }
        let line = "{\"loop\": \"\(name)\", \"key\": \(key), \"on\": \(on), \"t\": \(String(format: "%.3f", recorder.videoTime)), \"volume\": \(String(format: "%.2f", volume))}\n"
        if let data = line.data(using: .utf8) { log.write(data) }
    }

    /// A frame's events into the scene's log, at the recording's time.
    func log(frame: Int, events: [MatchEvent], match: Match) {
        guard let log, let recorder else { return }
        let time = recorder.videoTime
        var lines = ""
        for event in events {
            switch event {
            case .ballBounced, .landed, .jumped, .dashed, .potholeBump, .snatchReached, .slid, .helmetSpawned, .helmetRemoved, .helicopterArrived:
                continue
            default:
                break
            }
            let text = "\(event)".replacingOccurrences(of: "EsperSim.", with: "").replacingOccurrences(of: "\"", with: "'")
            let players = match.players.map { String(format: "[%.0f,%.0f]", $0.position.x, $0.position.y) }.joined(separator: ",")
            lines += "{\"t\": \(String(format: "%.3f", time)), \"frame\": \(frame), \"event\": \"\(text)\", \"players\": [\(players)]}\n"
        }
        if !lines.isEmpty, let data = lines.data(using: .utf8) { log.write(data) }
    }

    /// A line on the run's state into the scene's log, every so often.
    func status(flow: String, match: Match) {
        guard let log else { return }
        let line = "{\"status\": \"flow \(flow) frame \(match.frame) countdown \(match.countdown) scene frames \(frames) phase \(director.phase) ending \(ending.map { "\($0)" } ?? "-") \(recorder?.stats ?? "no recorder")\"}\n"
        if let data = line.data(using: .utf8) { log.write(data) }
    }

    /// The recording of the scene at `index` begun: its video and its log, the log's first line the scene itself.
    func beginRecording(device: MTLDevice) {
        guard let scene = current else { return }
        let name = fileName(at: index)
        let logURL = folder.appendingPathComponent(name + ".jsonl")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        log = try? FileHandle(forWritingTo: logURL)
        let colours = scene.colours.map { "\"\($0)\"" }.joined(separator: ",")
        let drinks = scene.drinks.map { $0.map { "\"\($0)\"" } ?? "null" }.joined(separator: ",")
        let header = "{\"scene\": \"\(scene.name)\", \"stage\": \"\(scene.stage)\", \"stageName\": \"\(scene.stage.name)\", \"mode\": \"\(scene.mode)\", \"colours\": [\(colours)], \"drinks\": [\(drinks)], \"cpu\": \(scene.cpuMatch), \"rain\": \(scene.rain.map { "\($0)" } ?? "null")}\n"
        log?.write(header.data(using: .utf8)!)
        do {
            recorder = try FootageRecorder(url: folder.appendingPathComponent(name + ".mp4"), size: FootageRun.videoSize, device: device)
        } catch {
            NSLog("[FOOTAGE] no recorder: %@", "\(error)")
        }
        NSLog("[FOOTAGE] scene %d/%d %@", index + 1, scenes.count, scene.name)
    }

    /// The scene's recording closed.
    func endRecording() {
        try? log?.close()
        log = nil
        guard let recorder else { return }
        self.recorder = nil
        let closed = recorder.url.deletingPathExtension().appendingPathExtension("ok")
        recorder.finish { line, whole in
            NSLog("[FOOTAGE] %@", line)
            if whole { try? "ok".write(to: closed, atomically: true, encoding: .utf8) }
        }
    }

    /// Over: the settings back as they were, and the `done` file for whoever's waiting.
    /// A preview's big panel as it was drawn, untrimmed, beside the videos.
    static func keepStill(_ image: CGImage, named name: String) {
        guard let folder = active?.folder else { return }
        try? UIImage(cgImage: image).pngData()?.write(to: folder.appendingPathComponent(name + ".png"))
    }

    func finish() {
        FootageRun.over = true
        FootageRun.active = nil
        let folder = folder
        let last = recorder
        endRecording()
        UserDefaults.standard.removeObject(forKey: FootageRun.defaultsKey)
        UserDefaults.standard.set(captureModeWas, forKey: GameScene.captureModeKey)
        func done() {
            try? "done".write(to: folder.appendingPathComponent("done"), atomically: true, encoding: .utf8)
            NSLog("[FOOTAGE] done")
            // The run's the launch's whole purpose: out, so nothing's left playing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
        }
        if last == nil { done() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { done() } }
    }
}

extension GameScene {
    /// The footage run begun: the HUD off as Capture Mode has it, and the first scene.
    func startFootage() {
        let run = FootageRun()
        footage = run
        UserDefaults.standard.set(true, forKey: GameScene.captureModeKey)
        startNextFootageScene()
    }

    /// The next scene set up and started: its stage, mode, colours and drinks, the round begun,
    /// the scene's own setup laid over the fresh match, and its recording.
    func startNextFootageScene() {
        guard let footage else { return }
        footage.endRecording()
        footage.index += 1
        while footage.current != nil, footage.recorded(at: footage.index) {
            NSLog("[FOOTAGE] %@ already recorded", footage.fileName(at: footage.index))
            footage.index += 1
        }
        guard let scene = footage.current else {
            footage.finish()
            self.footage = nil
            AnoziraRules.rainForced = nil
            enter(.title)
            return
        }
        gameMode = scene.mode
        series = Series(seed: UInt32(truncatingIfNeeded: footage.index + 1) &* 7919)
        series.stage = scene.stage
        // No stage preview, straight into play, unless the scene's for the preview's still.
        previewedStage = scene.showsPreview ? nil : scene.stage
        var sides = [PlayerCustomization.saved(0), PlayerCustomization.saved(1)]
        for index in sides.indices where scene.colours.indices.contains(index) {
            // Yellow is gold's plain name; scenes say yellow.
            let named = scene.colours[index] == "yellow" ? "gold" : scene.colours[index]
            if let colour = EnergyColour(rawValue: named) { sides[index].energy = colour }
        }
        sides = PlayerCustomization.clashed(sides)
        applyColours(sides.map(\.energy), looks: sides.map(\.look))
        pickedDrinks = scene.drinks + Array(repeating: nil, count: max(0, 2 - scene.drinks.count))
        if !scene.mode.picksDrinkAhead {
            for index in series.drinks.indices where scene.drinks.indices.contains(index) {
                series.drinks[index].biomorph = scene.drinks[index]
                series.drinks[index].biomorphLevel = scene.drinks[index] == nil ? 0 : 2
            }
        }
        if scene.cpuMatch {
            let seed = UInt32(truncatingIfNeeded: footage.index &* 104729 &+ 17)
            opponent = Opponent(index: 1, seed: seed | 1)
            playerOneOpponent = Opponent(index: 0, seed: (seed &* 31) | 1)
        } else {
            // The seeds the headless probe proved the scene with.
            playerOneOpponent = Opponent(index: 0, seed: scene.seeds[0])
            opponent = Opponent(index: 1, seed: scene.seeds[1])
        }
        AnoziraRules.rainForced = scene.rain
        startRound()
        session.mutate { match in
            if scene.cpuMatch {
                scene.prepare(&match)
            } else {
                // The very match the headless probe proved the scene on: its seed, its specs.
                match = scene.makeMatch()
            }
        }
        footage.director = FootageDirector()
        footage.frames = 0
        footage.ending = nil
        footage.pickFrames = 0
        footage.picked = false
        if let device = MTLCreateSystemDefaultDevice() { footage.beginRecording(device: device) }
        enter(.playing)
    }

    /// A frame of the run: the scene's end noticed, the tail after it, and the next scene.
    func stepFootage() {
        guard let footage else { return }
        if let left = footage.ending {
            if left <= 1 {
                if flow == .won, let flowState {
                    footage.ending = Int.max
                    flowState.transition { [weak self] in self?.startNextFootageScene() }
                } else if flow != .won {
                    startNextFootageScene()
                }
            } else if left != Int.max {
                footage.ending = left - 1
            }
            return
        }
        if let scene = footage.current, !scene.pickMoves.isEmpty {
            if let screen = footagePickScreen {
                // The scene's moves along the bottles, a beat apart, then the drink.
                footage.pickFrames += 1
                if footage.pickFrames % FootageRun.pickBeat == 0 {
                    let beat = footage.pickFrames / FootageRun.pickBeat
                    if beat <= scene.pickMoves.count {
                        screen.move(scene.pickMoves[beat - 1])
                    } else if !footage.picked {
                        footage.picked = true
                        screen.fire()
                    }
                }
                return
            }
            // Drunk and back to play: the scene's over, before the next round's under way.
            if footage.picked, flow == .playing {
                footage.ending = 1
                return
            }
        }
        if footage.current?.cpuMatch == true { footage.frames += 1 }
        if match.frame % 120 == 0 { footage.status(flow: "\(flow)", match: match) }
        if footage.sceneDone(won: flow == .won, match: match) {
            footage.ending = flow == .won ? FootageRun.wonTail : FootageRun.scriptedTail
        }
    }
}
