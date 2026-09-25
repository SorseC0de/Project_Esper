import AVFoundation

/// The sound effects, from `Sounds` (brought in from `_Sound FX` by `Tools/import_sounds.py`).
/// Each file is read into memory once and played on a ring of voices through one engine,
/// so a sound starts the frame it's asked for and a few overlap.
@MainActor
final class SoundBoard {
    static let shared = SoundBoard()

    enum Effect: String, CaseIterable {
        case ballBounce = "ball_bounce"
        case esperSlash = "esper_slash"
        case jump
        case menuBack = "menu_back"
        case menuCursor = "menu_cursor"
        case menuSelect = "menu_select"
        case playerHit = "player_hit"
        case playerShoot = "player_shoot"
        case playerSnatch = "player_snatch"
        case slashWallClank = "slash_wallclank"
        case step
    }

    private static let voiceCount = 12
    private let engine = AVAudioEngine()
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0

    private init() {
        // Ambient: under the silent switch, and mixed with whatever else is playing.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav")
                    ?? Bundle.main.url(forResource: effect.rawValue, withExtension: "wav", subdirectory: "Sounds"),
                  let file = try? AVAudioFile(forReading: url),
                  file.processingFormat == format,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil else {
                print("SoundBoard: \(effect.rawValue).wav missing or not 44.1 kHz mono")
                continue
            }
            buffers[effect] = buffer
        }
        for _ in 0..<SoundBoard.voiceCount {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
        try? engine.start()
    }

    /// Plays on the next voice round the ring, cutting off whatever it was playing.
    func play(_ effect: Effect, volume: Float = 1) {
        guard let buffer = buffers[effect], volume > 0 else { return }
        // A call or another app can stop the engine; it starts again on the next sound.
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.volume = volume
        voice.scheduleBuffer(buffer, at: nil)
        voice.play()
    }
}
