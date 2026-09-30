import AVFoundation
import UIKit

/// A stage's background sound, looped low under everything: the Elements' thunderstorm.
/// The file is cut to its loop with a fade at each end (Tools/import_ambience.py).
final class Ambience {
    static let shared = Ambience()
    private static let volume: Float = 0.2
    private var player: AVAudioPlayer?
    private var playing: String?

    /// Silent the moment the app leaves the screen, rather than playing on until it's suspended;
    /// back when it returns.
    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player?.pause()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player?.play()
        }
    }

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
