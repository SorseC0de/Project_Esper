import AVFoundation

/// The sound effects, from `Sounds` (brought in from `_Sound FX` by `Tools/import_sounds.py`).
/// Each file is read into memory once and played on a pool of voices through one engine,
/// so a sound starts the frame it's asked for and a few overlap. The voices are left
/// running and a sound goes to one that has finished, since stopping a playing voice
/// waits on the audio thread: on the TV that cost the main thread milliseconds a frame.
@MainActor
final class SoundBoard {
    static let shared = SoundBoard()

    enum Effect: String, CaseIterable {
        case ballBounce = "ball_bounce"
        case basket
        case catchBall = "catch"
        case countOne = "1"
        case countTwo = "2"
        case countThree = "3"
        case esperSlash = "esper_slash"
        case jump
        case lightningOne = "lightning1"
        case lightningTwo = "lightning2"
        case lightningThree = "lightning3"
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
    }

    private static let voiceCount = 12
    private let engine = AVAudioEngine()
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var voices: [AVAudioPlayerNode] = []
    /// When each voice's last sound ends.
    private var busyUntil: [CFTimeInterval] = []

    private init() {
        // Ambient: under the silent switch, and mixed with whatever else is playing.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        for effect in Effect.allCases {
            let parts = SoundBoard.layers[effect] ?? [(effect.rawValue, 1)]
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
            if SoundBoard.reversed.contains(effect), let samples = buffer.floatChannelData?[0] {
                var frames = UnsafeMutableBufferPointer(start: samples, count: Int(buffer.frameLength))
                frames.reverse()
            }
            if let gain = SoundBoard.gain[effect], let samples = buffer.floatChannelData?[0] {
                for index in 0..<Int(buffer.frameLength) { samples[index] = min(max(samples[index] * gain, -1), 1) }
            }
            buffers[effect] = buffer
        }
        for _ in 0..<SoundBoard.voiceCount {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
            busyUntil.append(0)
        }
        try? engine.start()
        if engine.isRunning { for voice in voices { voice.play() } }
    }

    static let lightning: [Effect] = [.lightningOne, .lightningTwo, .lightningThree]
    /// The menus' two sounds: moving the cursor, and choosing. menu_cursor was too loud
    /// beside everything else; the old choice sound moves to the cursor.
    static let navigate = Effect.menuSelect
    static let confirm = Effect.menuSelectV2
    /// Played back to front.
    private static let reversed: Set<Effect> = [.menuSelectV2]
    /// Louder than their files, which a voice's volume can't go past: the step is recorded
    /// very quietly, its peak at 3% of full.
    private static let gain: [Effect: Float] = [.step: 2]
    /// Sounds made of more than one file, mixed as they're read, each at its own level: the
    /// parry's two halves at 0.3, which sets them beside the hit, the snatch and the catch.
    private static let layers: [Effect: [(file: String, level: Float)]] = [.parry: [("parry", 0.3), ("parry2", 0.3)]]
    static let count: [Int: Effect] = [1: .countOne, 2: .countTwo, 3: .countThree]

    /// One file from `Sounds`, read whole.
    private static func read(_ name: String, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
              let file = try? AVAudioFile(forReading: url), file.processingFormat == format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    /// Plays on a voice that has finished; with every voice busy, the one nearest its end is cut off.
    func play(_ effect: Effect, volume: Float = 1) {
        guard let buffer = buffers[effect], volume > 0 else { return }
        // A call or another app can stop the engine; it starts again on the next sound.
        if !engine.isRunning {
            try? engine.start()
            guard engine.isRunning else { return }
            for voice in voices { voice.play() }
        }
        let now = CACurrentMediaTime()
        let index = busyUntil.firstIndex { $0 <= now } ?? busyUntil.indices.min { busyUntil[$0] < busyUntil[$1] }!
        let voice = voices[index]
        if busyUntil[index] > now {
            voice.stop()
            voice.play()
        }
        busyUntil[index] = now + Double(buffer.frameLength) / buffer.format.sampleRate
        voice.volume = volume
        voice.scheduleBuffer(buffer, at: nil)
    }
}
