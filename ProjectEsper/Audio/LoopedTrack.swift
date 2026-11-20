import AVFoundation
import UIKit

/// A long sound looped under everything: the stage's ambience (the Elements' thunderstorm, cut to its
/// loop with a fade at each end by Tools/import_ambience.py) and the music (the Tutorial's Wreck, by
/// Tools/import_music.py). Neither plays on the title.
final class LoopedTrack {
    static let ambience = LoopedTrack(fileExtension: "m4a", volume: 0.2, heard: { GameSettings.ambience })
    static let music = LoopedTrack(fileExtension: "caf", volume: 0.5, heard: { true })
    static let all = [ambience, music]

    private let fileExtension: String
    private let volume: Float
    /// Its own setting, under the mute.
    private let heard: () -> Bool
    private var player: AVAudioPlayer?
    private var playing: String?

    /// Silent the moment the app leaves the screen, rather than playing on until it's suspended;
    /// back when it returns.
    private init(fileExtension: String, volume: Float, heard: @escaping () -> Bool) {
        self.fileExtension = fileExtension
        self.volume = volume
        self.heard = heard
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player?.pause()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player?.play()
        }
    }

    private var settingVolume: Float { heard() && !GameSettings.muted ? volume : 0 }

    /// Every track heard or silenced as the settings have it, carrying on underneath either way.
    static func applySettings() {
        for track in all { track.player?.volume = track.settingVolume }
    }

    /// Plays `name`, or nothing; the same name again carries on where it is.
    func play(_ name: String?) {
        guard name != playing else { return }
        player?.stop()
        player = nil
        playing = name
        guard let name, SoundBoard.enabled,
              let url = Bundle.main.url(forResource: name, withExtension: fileExtension)
                ?? Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Sounds"),
              let made = try? AVAudioPlayer(contentsOf: url) else { return }
        made.numberOfLoops = -1
        made.volume = settingVolume
        made.play()
        player = made
    }
}
