import AVFoundation

/// A stage's background sound, looped low under everything: the Elements' thunderstorm.
/// The file is cut to its loop with a fade at each end (Tools/import_ambience.py).
final class Ambience {
    static let shared = Ambience()
    private static let volume: Float = 0.2
    private var player: AVAudioPlayer?
    private var playing: String?

    /// Plays `name`, or nothing; the same name again carries on where it is.
    func play(_ name: String?) {
        guard name != playing else { return }
        player?.stop()
        player = nil
        playing = name
        guard let name, SoundBoard.enabled,
              let url = Bundle.main.url(forResource: name, withExtension: "m4a")
                ?? Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Sounds"),
              let made = try? AVAudioPlayer(contentsOf: url) else { return }
        made.numberOfLoops = -1
        made.volume = Ambience.volume
        made.play()
        player = made
    }
}
