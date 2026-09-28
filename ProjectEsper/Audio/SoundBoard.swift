import AVFoundation

/// The sound effects, from `Sounds` (brought in from `_Sound FX` by `Tools/import_sounds.py`).
/// Each file is read into memory once and played on a pool of voices through one engine,
/// so a sound starts the frame it's asked for and a few overlap. The voices are left
/// running and a sound goes to one that has finished, since stopping a playing voice
/// waits on the audio thread: on the TV that cost the main thread milliseconds a frame.
/// All of it is read and the engine started at launch (`prepare`), off the main thread.
@MainActor
final class SoundBoard {
    static let shared = SoundBoard()

    enum Effect: String, CaseIterable {
        case ballBounce = "ball_bounce"
        case catchBall = "catch"
        case fireHit = "fire_hit"
        case esperSlash = "esper_slash"
        case jump
        case lightningOne = "lightning_hit1"
        case lightningTwo = "lightning_hit2"
        case lightningThree = "lightning_hit3"
        case menuBack = "menu_back"
        case menuSelect = "menu_select"
        case menuSelectV2 = "menu_select_v2"
        case playerHit = "player_hit"
        case shootV2 = "shoot_v2"
        case swish
        case snatch
        case parry
        case portIn = "port_in"
        case slashWallClank = "slash_wallclank"
        case step
        // The announcer, levelled by the importer.
        case countA1 = "announcer_1", countA2 = "announcer_2", countA3 = "announcer_3"
        case countB1 = "announcer_1-2", countB2 = "announcer_2-2", countB3 = "announcer_3-2"
        case ballOut = "announcer_ballout", ballOut2 = "announcer_ballout2"
        case thatllDoIt = "announcer_thatlldoit", thatllDoIt2 = "announcer_thatlldoit-2", thatDecidesIt = "announcer_thatdecidesit"
        case score = "announcer_score", score2 = "announcer_score-2", score3 = "announcer_score-3", whatAScore = "announcer_whatascore"
        case slamDunk = "announcer_slamdunk", slamDunk2 = "announcer_slamdunk-2", slamDunk3 = "announcer_slamdunk-3", dunk = "announcer_dunk"
        case wristWork = "announcer_watchthewristwork", wristWork2 = "announcer_watchthewristwork-2"
        case itsAThree = "announcer_itsathree"
        case winner = "announcer_winner", winner2 = "announcer_winner-2", whatAWin = "announcer_whatawin"
        case crowdCheer = "crowd_cheer"
    }

    /// The announcer's lines by what they're for.
    static let gameWinners: [Effect] = [.thatllDoIt, .thatllDoIt2, .thatDecidesIt]
    static let scores: [Effect] = [.score, .score2, .score3, .whatAScore]
    static let dunks: [Effect] = [.slamDunk, .slamDunk2, .slamDunk3, .dunk]
    static let wristWorks: [Effect] = [.wristWork, .wristWork2]
    static let winners: [Effect] = [.winner, .winner2, .whatAWin]

    private static let voiceCount = 16
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var voices: [AVAudioPlayerNode] = []
    /// When each voice's last sound ends.
    private var busyUntil: [CFTimeInterval] = []
    /// The sounds are in memory and the engine has been started once.
    private var ready = false
    private var restartPending = false

    static let enabled = true

    private init() {}

    /// Everything read into memory and mixed off the main thread, at launch, and the
    /// engine started when it's done; nothing is loaded the first time a sound plays.
    /// A sound asked for before then is skipped.
    func prepare() {
        guard SoundBoard.enabled, voices.isEmpty else { return }
        // Ambient: under the silent switch, and mixed with whatever else is playing.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        for _ in 0..<SoundBoard.voiceCount {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
            busyUntil.append(0)
        }
        // A route change (the TV's HDMI resetting, headphones) or an interruption stops the
        // engine and its voices: they're started again, away from any frame being drawn.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            MainActor.assumeIsolated { SoundBoard.shared.scheduleRestart() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SoundBoard.shared.scheduleRestart() }
        }
        // The engine started now, at launch on the title, not when the loading's done,
        // which could be as a match begins.
        startEngine()
        let format = format
        Task.detached(priority: .userInitiated) {
            let loaded = SoundBoard.load(format: format)
            await MainActor.run {
                SoundBoard.shared.buffers = loaded.buffers
                SoundBoard.shared.ready = true
                SoundBoard.shared.prime()
            }
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        engine.prepare()
        do { try engine.start() } catch { return }
        for index in voices.indices {
            voices[index].play()
            busyUntil[index] = 0
        }
    }

    /// Every voice plays a moment of silence once, so the first real sound on each doesn't
    /// pay for the audio side's first go at it.
    private func prime() {
        guard engine.isRunning, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 441) else { return }
        silence.frameLength = 441
        if let samples = silence.floatChannelData?[0] { for index in 0..<441 { samples[index] = 0 } }
        for voice in voices where voice.isPlaying { voice.scheduleBuffer(silence, at: nil) }
    }

    /// The engine started again, and every voice set playing, each free.
    private func restart() {
        restartPending = false
        startEngine()
        if !voices.allSatisfy(\.isPlaying), engine.isRunning {
            for index in voices.indices {
                voices[index].play()
                busyUntil[index] = 0
            }
        }
    }

    private func scheduleRestart() {
        guard !restartPending else { return }
        restartPending = true
        DispatchQueue.main.async { SoundBoard.shared.restart() }
    }

    /// The buffers, each file read whole and the layered ones mixed, reversed and levelled.
    private final class Loaded: @unchecked Sendable {
        var buffers: [Effect: AVAudioPCMBuffer] = [:]
    }

    nonisolated private static func load(format: AVAudioFormat) -> Loaded {
        let loaded = Loaded()
        for effect in Effect.allCases {
            let parts = layers[effect] ?? [(effect.rawValue, 1)]
            let read = parts.compactMap { part in SoundBoard.read(part.file, format: format).map { ($0, part.level) } }
            guard read.count == parts.count, let longest = read.map({ $0.0.frameLength }).max(),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: longest), let mixed = buffer.floatChannelData?[0] else {
                print("SoundBoard: \(effect.rawValue) missing a file or not 44.1 kHz mono")
                continue
            }
            buffer.frameLength = longest
            for index in 0..<Int(longest) { mixed[index] = 0 }
            for (part, level) in read {
                guard let samples = part.floatChannelData?[0] else { continue }
                for index in 0..<Int(part.frameLength) { mixed[index] += samples[index] * level }
            }
            if reversed.contains(effect) {
                var frames = UnsafeMutableBufferPointer(start: mixed, count: Int(buffer.frameLength))
                frames.reverse()
            }
            if let gain = gain[effect] {
                for index in 0..<Int(buffer.frameLength) { mixed[index] = min(max(mixed[index] * gain, -1), 1) }
            }
            loaded.buffers[effect] = buffer
        }
        return loaded
    }

    static let lightning: [Effect] = [.lightningOne, .lightningTwo, .lightningThree]
    /// The menus' two sounds: moving the cursor, and choosing. menu_cursor was too loud
    /// beside everything else; the old choice sound moves to the cursor.
    static let navigate = Effect.menuSelect
    static let confirm = Effect.menuSelectV2
    /// Played back to front.
    nonisolated private static let reversed: Set<Effect> = [.menuSelectV2]
    /// Louder than their files, which a voice's volume can't go past: the step is recorded
    /// very quietly, its peak at 3% of full.
    /// The lightning hits are recorded hot, about -9 dB while sounding: a quarter brings them
    /// to about -21, beside the swish and the announcer.
    nonisolated private static let gain: [Effect: Float] = [.step: 2, .lightningOne: 0.25, .lightningTwo: 0.25, .lightningThree: 0.25]
    /// Sounds made of more than one file, mixed as they're read, each at its own level: the
    /// parry's two halves at 0.3, which sets them beside the hit, the snatch and the catch.
    nonisolated private static let layers: [Effect: [(file: String, level: Float)]] = [.parry: [("parry", 0.3), ("parry2", 0.3)]]
    /// The count: the announcer's first set or his second, on the COUNT picker (A or B).
    static let countSetKey = "esper.countSet"
    static var count: [Int: Effect] {
        UserDefaults.standard.integer(forKey: countSetKey) == 1
            ? [1: .countB1, 2: .countB2, 3: .countB3]
            : [1: .countA1, 2: .countA2, 3: .countA3]
    }

    /// One file from `Sounds`, read whole.
    nonisolated private static func read(_ name: String, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
              let file = try? AVAudioFile(forReading: url), file.processingFormat == format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    /// Plays on a voice that has finished; with every voice busy, the one nearest its end
    /// has its sound cut by the new one, scheduled to interrupt it, never stopped (a stop
    /// waits on the audio thread). With the engine down, the sound is skipped and a restart
    /// is asked for.
    func play(_ effect: Effect, volume: Float = 1, pan: Float = 0) {
        guard SoundBoard.enabled, ready, let buffer = buffers[effect], volume > 0 else { return }
        guard engine.isRunning else {
            scheduleRestart()
            return
        }
        let now = CACurrentMediaTime()
        let index = busyUntil.firstIndex { $0 <= now } ?? busyUntil.indices.min { busyUntil[$0] < busyUntil[$1] }!
        let voice = voices[index]
        guard voice.isPlaying else {
            scheduleRestart()
            return
        }
        let interrupting = busyUntil[index] > now
        busyUntil[index] = now + Double(buffer.frameLength) / buffer.format.sampleRate
        voice.volume = volume
        voice.pan = pan
        voice.scheduleBuffer(buffer, at: nil, options: interrupting ? .interrupts : [])
    }
}
